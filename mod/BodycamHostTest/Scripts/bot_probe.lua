-- Targeted, read-only inspection of the active host's automatic bot fill.
return function(api)
    local watch, callbackCount, reportedCount = nil, 0, 0
    local capEnabled, capPerTeam, blockedCount, reportedBlocked = false, nil, 0, 0
    local hookErrors, reportedErrors = 0, 0
    local decisionPath = "/Game/GM/Gamemode/BP_BodycamGameModeAbstract.BP_BodycamGameModeAbstract_C:ShouldSpawnBots"
    local function relevant(s)
        s = s:lower()
        return s:find("bot", 1, true) or s:find("fill", 1, true)
            or s:find("desired", 1, true) or s:find("spawn", 1, true)
    end

    local function inspect(o, label)
        if not api.valid(o) then api.log(label .. ": NOT FOUND"); return end
        api.log(label .. ": " .. api.name(o))
        local class, fields, functions, seen = o:GetClass(), 0, 0, {}
        for _ = 1, 16 do
            if not api.valid(class) then break end
            class:ForEachProperty(function(p)
                local n = api.short(p)
                if relevant(n) and not seen[n] and fields < 30 then
                    seen[n], fields = true, fields + 1
                    local value, err = api.try(function() return o[n] end)
                    if type(value) ~= "number" and type(value) ~= "boolean" and type(value) ~= "string" then
                        value = api.valid(value) and api.name(value) or "<complex/unavailable>"
                    end
                    api.log("  field " .. api.name(p) .. " = " .. tostring(value)
                        .. (err and ("; read failed: " .. err) or ""))
                end
            end)
            class:ForEachFunction(function(f)
                local n = api.short(f)
                if relevant(n) and not seen["fn:" .. n] and functions < 35 then
                    seen["fn:" .. n], functions = true, functions + 1
                    api.log("  function " .. api.name(f))
                    local params = 0
                    f:ForEachProperty(function(p)
                        if params < 8 then
                            params = params + 1
                            api.log("    " .. api.name(p))
                        end
                    end)
                end
            end)
            class = class:GetSuperStruct()
        end
        api.log(label .. " relevant reflected entries: " .. fields .. " fields, " .. functions .. " functions")
    end

    local function roster(c)
        if not api.valid(c.gs) then return end
        local total, bots, humans, unknown, teams = 0, 0, 0, 0, {}
        local players = api.try(function() return c.gs.PlayerArray end)
        if not players then api.log("Roster PlayerArray: unreadable"); return end
        for i = 1, #players do
            total = total + 1
            local ps = players[i]
            local bot = api.try(function() return ps.bIsABot end)
            local team = api.try(function() return ps.TeamID end)
            if bot == true then
                bots = bots + 1
                if type(team) == "number" then teams[team] = (teams[team] or 0) + 1 end
            elseif bot == false then humans = humans + 1
            else unknown = unknown + 1 end
        end
        api.log(string.format("Roster: entries=%d bots=%d nonbots=%d unknown=%d bot teams 0=%d 1=%d unassigned=%d",
            total, bots, humans, unknown, teams[0] or 0, teams[1] or 0, teams[-1] or 0))
    end

    local function run()
        api.log("=== F3 bot-fill probe (read only; no hooks) ===")
        local c = api.context()
        if not c.host then api.log("Probe REFUSED: " .. c.reason); return end
        api.log("World: " .. api.name(c.world))
        api.log("GameMode class: " .. api.name(c.gm:GetClass()))
        roster(c)
        inspect(c.gm, "GameMode")
        inspect(c.gi, "GameInstance")
        inspect(c.gs, "GameState")
        local asset = api.try(function() return c.gs.GameModeConfigDataAsset end)
        if api.valid(asset) then
            local max = api.try(function() return asset.TeamConfig.MaxPlayers end)
            local team = api.try(function() return asset.TeamConfig.TeamMaxSize end)
            api.log("TeamConfig (human and bot capacity): MaxPlayers=" .. tostring(max)
                .. " TeamMaxSize=" .. tostring(team))
        end
        for _, path in ipairs({
            "/Script/Bodycam.BodycamGameMode:ShouldSpawnBots",
            "/Script/Bodycam.BodycamGameMode:ForceBotsMethod",
            "/Game/GM/Gamemode/BP_BodycamGameModeAbstract.BP_BodycamGameModeAbstract_C:ShouldSpawnBots",
            "/Game/GM/Gamemode/BP_BodycamGameModeAbstract.BP_BodycamGameModeAbstract_C:GetBotsMethod"
        }) do
            local f = StaticFindObject(path)
            api.log("Exact bot decision function: " .. path .. " = " .. (api.valid(f) and "FOUND" or "NOT FOUND"))
        end
        api.log("=== End F3 bot-fill probe ===")
    end
    local function toggleWatch()
        if watch then
            local ok, err = pcall(function()
                UnregisterHook(decisionPath, watch.pre, watch.post)
            end)
            api.log("F1 bot-decision watch: " .. (ok and "STOPPED" or ("STOP FAILED: " .. tostring(err))))
            if ok then watch = nil; capEnabled = false; capPerTeam = nil end
            return
        end
        local c = api.context()
        if not c.host then api.log("F1 bot-decision watch REFUSED: not an active host"); return end
        local f = StaticFindObject(decisionPath)
        if not api.valid(f) then api.log("F1 bot-decision watch REFUSED: Blueprint function missing"); return end
        local pre, post = RegisterHook(decisionPath, function(contextParam)
            callbackCount = callbackCount + 1
            if not capEnabled then return end
            local shouldBlock = false
            local ok = pcall(function()
                local gm = contextParam and contextParam:get()
                if not api.valid(gm) or
                    gm:IsA('/Script/Bodycam.BodycamGameMode') ~= true then return end
                local world = gm:GetWorld()
                if not api.valid(world) then return end
                local authority = world.AuthorityGameMode
                if not api.valid(authority) or authority:GetAddress() ~= gm:GetAddress() then return end
                local gs = world.GameState
                if not api.valid(gs) then return end
                local class = api.name(gm:GetClass()):lower()
                local tdm = class:find('gm_teamdeathmatch', 1, true) ~= nil
                local ffa = not tdm and class:find('gm_deathmatch', 1, true) ~= nil
                if not tdm and not ffa then return end
                local bots, unknown, teams = 0, 0, {}
                local players = gs.PlayerArray
                for i = 1, #players do
                    local ps = players[i]
                    local bot = ps.bIsABot
                    if bot == true then
                        bots = bots + 1
                        local team = ps.TeamID
                        if type(team) ~= 'number' then unknown = unknown + 1
                        else teams[team] = (teams[team] or 0) + 1 end
                    elseif bot ~= false then unknown = unknown + 1 end
                end
                if unknown > 0 then return end
                shouldBlock = ffa and bots >= capPerTeam or
                    (tdm and (bots >= capPerTeam * 2 or
                        (teams[0] or 0) >= capPerTeam or (teams[1] or 0) >= capPerTeam))
            end)
            if not ok then hookErrors = hookErrors + 1; return end
            if shouldBlock then
                blockedCount = blockedCount + 1
                return false
            end
        end)
        if type(pre) ~= "number" or type(post) ~= "number" then
            api.log("F1 bot-decision watch FAILED: hook IDs unavailable"); return
        end
        watch = {pre=pre, post=post}
        reportedCount = callbackCount
        api.log("F1 bot-decision watch STARTED (Blueprint function; observation only, no return override)")
    end
    local function poll(c)
        if not watch then return end
        if callbackCount ~= reportedCount then
            api.log("Blueprint ShouldSpawnBots callbacks: +" .. (callbackCount - reportedCount)
                .. " total=" .. callbackCount .. "; host=" .. tostring(c.host))
            reportedCount = callbackCount
        end
        if blockedCount ~= reportedBlocked then
            api.log('Bot cap decision overrides: +' .. (blockedCount - reportedBlocked)
                .. ' total=' .. blockedCount .. '; requested per-team cap=' .. tostring(capPerTeam)
                .. '; existing bots are not removed')
            reportedBlocked = blockedCount
        end
        if hookErrors ~= reportedErrors then
            api.log('Bot cap hook errors: +' .. (hookErrors - reportedErrors)
                .. ' total=' .. hookErrors .. '; original decisions left unchanged')
            reportedErrors = hookErrors
        end
    end
    local function toggleCap()
        if capEnabled then
            capEnabled = false
            api.log('F10 bot cap OFF; Blueprint decision watch remains active until F1')
            return
        end
        local cap, err = api.botConfig()
        if cap == nil then api.log('F10 bot cap REFUSED: ' .. tostring(err)); return end
        local c = api.context()
        if not c.host then api.log('F10 bot cap REFUSED: not an active host'); return end
        if not watch then toggleWatch() end
        if not watch then api.log('F10 bot cap REFUSED: decision watch unavailable'); return end
        capPerTeam, capEnabled = cap, true
        api.log('F10 bot cap ON: maxBotsPerTeam=' .. cap ..
            ' in TDM; total bot cap=' .. cap .. ' in FFA; maxPlayers unchanged')
        api.log('Only future automatic spawn decisions can be blocked; existing bots remain until replaced or next map')
    end
    return {run=run, toggleWatch=toggleWatch, toggleCap=toggleCap, poll=poll,
        capEnabled=function() return capEnabled end}
end
