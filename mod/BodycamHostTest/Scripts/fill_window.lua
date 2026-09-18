-- Opt-in TDM experiment: constrain each initial bot-fill window, then restore.
return function(api)
    local armed, window

    local function state(c, maxBots)
        local total, bots, humans, unknown = 0, 0, 0, 0
        local players = api.try(function() return c.gs.PlayerArray end)
        if not players then return nil, 'PlayerArray unavailable' end
        total = #players
        for i = 1, total do
            local bot = api.try(function() return players[i].bIsABot end)
            if bot == true then bots = bots + 1
            elseif bot == false then humans = humans + 1
            else unknown = unknown + 1 end
        end
        if unknown > 0 or humans < 1 then return nil, 'bot/human roster unclear' end
        return {total=total, bots=bots, humans=humans, target=humans + maxBots * 2}
    end

    local function assetAndData(c)
        if not c.host or api.name(c.gm:GetClass()):lower():find('gm_teamdeathmatch', 1, true) == nil then
            return nil, nil, 'requires a networked Team Deathmatch host'
        end
        local asset = api.try(function() return c.gs.GameModeConfigDataAsset end)
        if not api.valid(asset) or
            api.try(function() return asset:IsA('/Script/Bodycam.GameModeConfigDataAsset') end) ~= true then
            return nil, nil, 'GameModeConfigDataAsset unavailable'
        end
        local property = api.try(function() return asset:Reflection():GetProperty('TeamConfig') end)
        local struct = property and api.try(function() return property:GetStruct() end)
        if not api.valid(property) or
            api.name(property) ~= 'StructProperty /Script/Bodycam.GameModeConfigDataAsset:TeamConfig' or
            not api.valid(struct) or api.name(struct) ~= 'ScriptStruct /Script/Bodycam.TeamConfig' then
            return nil, nil, 'TeamConfig reflection changed'
        end
        local field
        struct:ForEachProperty(function(p)
            if api.name(p) == 'IntProperty /Script/Bodycam.TeamConfig:MaxPlayers' and
                api.isType(p, 'IntProperty') then field = p end
        end)
        if not field then return nil, nil, 'MaxPlayers field not verified' end
        local data = api.try(function() return asset.TeamConfig end)
        if not api.valid(data) then return nil, nil, 'TeamConfig value unavailable' end
        return asset, data
    end

    local function restore(c, reason)
        if not window then return end
        local asset, data, err = assetAndData(c)
        if not asset or api.name(c.world) ~= window.world or api.name(asset) ~= window.asset then
            api.log('Bot fill window restore FAILED: ' .. tostring(err or 'world/asset changed') .. '; press F9 in the live match')
            window = nil; return
        end
        local before = api.try(function() return data.MaxPlayers end)
        if before == window.original then
            api.log('Bot fill window: gameplay MaxPlayers already restored to ' .. window.original)
            window = nil; return
        end
        if before ~= window.target then
            api.log('Bot fill window restore REFUSED: field changed externally to ' .. tostring(before) .. '; press F9 if needed')
            window = nil; return
        end
        local ok, writeErr = pcall(function() data.MaxPlayers = window.original end)
        local after = api.try(function() return data.MaxPlayers end)
        api.log('Bot fill window ' .. reason .. ': TeamConfig.MaxPlayers ' .. before .. ' -> ' .. tostring(after)
            .. (ok and after == window.original and ' RESTORED' or (' FAILED ' .. tostring(writeErr))))
        window = nil
    end

    local function apply(c, cap, limit)
        local asset, data, err = assetAndData(c)
        if not asset then return false, err end
        local roster, rosterErr = state(c, cap)
        if not roster then return false, rosterErr end
        local before = api.try(function() return data.MaxPlayers end)
        if before ~= limit then return false, 'active TeamConfig.MaxPlayers=' .. tostring(before) .. ', expected ' .. limit end
        if roster.target >= limit or roster.total > roster.target or (cap > 0 and roster.bots >= cap * 2) then
            return false, string.format('initial fill window missed: roster=%d bots=%d target=%d',
                roster.total, roster.bots, roster.target)
        end
        local ok, writeErr = pcall(function() data.MaxPlayers = roster.target end)
        local after = api.try(function() return data.MaxPlayers end)
        api.log(string.format('Bot fill initial-fill test: humans=%d bots=%d; gameplay MaxPlayers %d -> %s; TeamMaxSize untouched',
            roster.humans, roster.bots, before, tostring(after)))
        if not ok or after ~= roster.target then return false, 'write failed: ' .. tostring(writeErr) end
        window = {world=api.name(c.world), asset=api.name(asset), original=before,
            target=roster.target, cap=cap, started=os.time()}
        api.log('Bot fill window ACTIVE for at most 35 seconds, then restores ' .. before .. '; session maxPlayers stays ' .. limit)
        return true
    end

    local function configure(c, cap, limit)
        if not c.host then api.log('Bot fill REFUSED: not an active host'); return false end
        if not api.capEnabled() then api.log('Bot fill REFUSED: bot decision cap is not active'); return false end
        local worldName = api.name(c.world)
        local transition = worldName:find('/Game/Map/TransitionMap/', 1, true) ~= nil
        if not transition and api.name(c.gm:GetClass()):lower():find('gm_teamdeathmatch', 1, true) == nil then
            armed = nil
            api.log('Bot fill window skipped outside Team Deathmatch; future bot decisions are still capped')
            return false
        end
        if window then
            if window.cap == cap and window.original == limit and window.world == worldName then
                api.log('Bot fill window already active; keeping its original restore timer')
                return true
            end
            restore(c, 'reconfigured restore')
        end
        armed = {world=worldName, cap=cap, limit=limit}
        if transition then
            api.log('Bot fill ARMED for the next playable Team Deathmatch map')
            return true
        end
        local roster = state(c, cap)
        if roster and roster.total <= roster.target and (cap == 0 or roster.bots < cap * 2) then
            local ok, err = apply(c, cap, limit)
            api.log('Bot fill current-map result: ' .. (ok and 'ACTIVE' or ('DEFERRED: ' .. tostring(err))))
        else
            api.log('Bot fill ARMED for each next Team Deathmatch map; existing bots are not removed')
        end
        return true
    end

    local function poll(c)
        -- Bodycam briefly creates this authoritative transition world with stale
        -- PlayerStates. It is not the new playable map's fill window.
        if c.host and api.name(c.world):find('/Game/Map/TransitionMap/', 1, true) then return end
        if window then
            if not c.host then return end
            if api.name(c.world) ~= window.world then
                local asset, data = assetAndData(c)
                local current = data and api.try(function() return data.MaxPlayers end)
                if asset and api.name(asset) == window.asset and current == window.target then
                    local ok = pcall(function() data.MaxPlayers = window.original end)
                    local after = api.try(function() return data.MaxPlayers end)
                    api.log('Bot fill world-change restore: ' .. current .. ' -> ' .. tostring(after)
                        .. (ok and after == window.original and ' RESTORED' or ' FAILED'))
                else
                    api.log('Bot fill window ended on world change; press F9 to confirm full gameplay capacity')
                end
                window = nil
            else
                local roster = state(c, window.cap)
                if roster and roster.bots > window.cap * 2 then
                    api.log('Bot fill result: FAILED; bots exceeded cap (' .. roster.bots .. ' > ' .. window.cap * 2 .. ')')
                    restore(c, 'failed-window restore')
                elseif os.time() - window.started >= 35 then
                    if roster then api.log('Bot fill result at restore: roster=' .. roster.total .. ' bots=' .. roster.bots
                        .. ' humans=' .. roster.humans .. ' target=' .. window.target) end
                    restore(c, 'timed restore')
                end
            end
        end
        if armed and c.host and api.name(c.world) ~= armed.world then
            armed.world = api.name(c.world)
            if not api.capEnabled() then
                armed = nil
                api.log('Bot fill stopped: bot decision cap is off'); return
            end
            local ok, err = apply(c, armed.cap, armed.limit)
            api.log('Bot fill next-map result: ' .. (ok and 'ACTIVE' or ('FAILED: ' .. tostring(err))))
        end
    end
    return {configure=configure, poll=poll,
        activeWindow=function() return window ~= nil end}
end
