-- One host-side bot request per keypress. Uses the function found in live reflection.
return function(api)
    local observation
    local recovery
    local counts
    local function aliveName(o) return api.valid(o) and api.name(o) or "NONE" end
    local function byName(c, wanted)
        if not wanted then return nil end
        for i = 1, #c.gs.PlayerArray do
            local ps = c.gs.PlayerArray[i]
            if api.name(ps) == wanted then return ps end
        end
    end
    local function trace(c, stateName, controllerName)
        local ps = byName(c, stateName)
        local controller
        if controllerName then
            for _, candidate in ipairs(FindAllOf("ALS_AI_Controller_C") or {}) do
                if api.valid(candidate) and api.name(candidate) == controllerName then
                    controller = candidate; break
                end
            end
        end
        local pawn = controller and api.try(function() return controller:GetPawn() end)
        if not api.valid(pawn) and controller then pawn = api.try(function() return controller.Pawn end) end
        local ownerState = controller and api.try(function() return controller.PlayerState end)
        local statePawn = ps and api.try(function() return ps:GetPawn() end)
        local team = ps and api.try(function() return ps.TeamID end)
        api.log("Lifecycle: PlayerState=" .. aliveName(ps) .. " TeamID=" .. tostring(team or "UNKNOWN")
            .. " Controller=" .. aliveName(controller) .. " Controller.PlayerState=" .. aliveName(ownerState)
            .. " Controller.Pawn=" .. aliveName(pawn) .. " PlayerState.Pawn=" .. aliveName(statePawn))
    end
    local function functionSignature(path)
        local f = StaticFindObject(path)
        if not api.valid(f) then api.log("Reflected function NOT FOUND: " .. path); return end
        api.log("Reflected function: " .. path)
        f:ForEachProperty(function(p)
            local cls = api.try(function() return p:GetPropertyClass() end)
            api.log("  " .. api.name(p) .. " expected object class=" .. aliveName(cls))
        end)
    end
    local function oneControllerArgument(path, paramName)
        local f = StaticFindObject(path)
        if not api.valid(f) then return false, "function not reflected: " .. path end
        local fields, ok = 0, true
        f:ForEachProperty(function(p)
            fields = fields + 1
            local cls = api.try(function() return p:GetPropertyClass() end)
            if api.short(p) ~= paramName or not api.isType(p, "ObjectProperty") or
                api.name(cls) ~= "Class /Script/Engine.Controller" then ok = false end
        end)
        if fields ~= 1 or not ok then return false, "unexpected signature: " .. path end
        return true
    end
    local function findUnassigned(c)
        local byState = {}
        for i = 1, #c.gs.PlayerArray do
            local ps = c.gs.PlayerArray[i]
            if api.try(function() return ps.bIsABot end) == true and
                api.try(function() return ps.TeamID end) == -1 then byState[api.name(ps)] = ps end
        end
        for _, controller in ipairs(FindAllOf("ALS_AI_Controller_C") or {}) do
            if api.valid(controller) and
                api.try(function() return controller:GetWorld():GetAddress() == c.world:GetAddress() end) == true then
                local ps = api.try(function() return controller.PlayerState end)
                if api.valid(ps) and byState[api.name(ps)] then return controller, ps end
            end
        end
    end
    local function recover()
        api.log("=== F5 one-bot team/pawn recovery ===")
        if recovery then api.log("Recovery SKIPPED: previous recovery is still observed"); return end
        local c = api.context()
        if not c.host then api.log("Recovery REFUSED: not a networked host"); return end
        if api.try(function() return c.gm:IsA("/Script/Bodycam.BodycamGameMode") end) ~= true then
            api.log("Recovery REFUSED: active GameMode is not BodycamGameMode"); return
        end
        local component = api.try(function() return c.gm.TeamManagementComponent end)
        if not api.valid(component) then api.log("Recovery FAILED: no TeamManagementComponent"); return end
        local controller, ps = findUnassigned(c)
        if not controller then api.log("Recovery SKIPPED: no unassigned bot with a live AI controller"); return end
        local validArg, reason = oneControllerArgument(
            "/Script/Bodycam.BodycamTeamManagementComponent:AssignTeamToPlayer", "NewPlayer")
        if not validArg then api.log("Recovery REFUSED: " .. reason); return end
        local stateName, controllerName = api.name(ps), api.name(controller)
        api.log("Selected bot: " .. stateName .. "; controller=" .. controllerName)
        trace(c, stateName, controllerName)
        local ok, callErr = pcall(function() component:AssignTeamToPlayer(controller) end)
        local team = api.try(function() return ps.TeamID end)
        api.log("AssignTeamToPlayer: " .. (ok and "RETURNED" or "FAILED")
            .. "; TeamID=" .. tostring(team) .. (callErr and ("; " .. tostring(callErr)) or ""))
        if not ok or type(team) ~= "number" or team < 0 then
            api.log("Recovery PARTIAL/FAILED: bot remains unassigned; no pawn restart attempted")
            return
        end
        local pawn = api.try(function() return controller:GetPawn() end)
        if api.valid(pawn) then api.log("Recovery: pawn already present after team assignment"); trace(c,stateName,controllerName)
        else
            local restartOK, restartReason = oneControllerArgument("/Script/Engine.GameModeBase:RestartPlayer", "NewPlayer")
            if not restartOK then api.log("Pawn restart SKIPPED: " .. restartReason)
            else
                local called, restartErr = pcall(function() c.gm:RestartPlayer(controller) end)
                api.log("RestartPlayer: " .. (called and "RETURNED" or "FAILED")
                    .. (restartErr and ("; " .. tostring(restartErr)) or ""))
            end
        end
        trace(c,stateName,controllerName)
        recovery = {world=api.name(c.world), stateName=stateName, controllerName=controllerName, checks=0}
    end
    local function inspect()
        api.log("=== F6 bot lifecycle diagnostic (read only) ===")
        local c = api.context()
        if not c.host then api.log("Diagnostic: networked host not found"); return end
        local snapshot, countErr = counts(c)
        api.log("Current roster: " .. (snapshot and snapshot.text or ("UNAVAILABLE: " .. tostring(countErr))))
        local teamSize = api.try(function() return c.gs:GetMaxTeamSize() end)
        api.log("GameState.GetMaxTeamSize(): " .. tostring(teamSize or "UNAVAILABLE"))
        functionSignature("/Script/Bodycam.BodycamTeamManagementComponent:AssignTeamToPlayer")
        functionSignature("/Script/Bodycam.BodycamGameMode:AssignTeamToPlayerPostLogin")
        functionSignature("/Script/Bodycam.BodycamGameMode:SpawnBot")
        functionSignature("/Script/Engine.GameModeBase:RestartPlayer")
        local asset = api.try(function() return c.gs.GameModeConfigDataAsset end)
        if api.valid(asset) then
            local teamProperty = api.try(function() return asset:Reflection():GetProperty("TeamConfig") end)
            local struct = teamProperty and api.try(function() return teamProperty:GetStruct() end)
            local teamConfig = api.try(function() return asset.TeamConfig end)
            if api.valid(struct) then
                api.log("TeamConfig in " .. api.name(asset) .. " (read only):")
                local ok, err = pcall(function()
                    struct:ForEachProperty(function(p)
                        local v, readErr = api.try(function() return teamConfig[api.short(p)] end)
                        local value = (type(v) == "number" or type(v) == "boolean") and tostring(v)
                            or tostring(readErr or "NONSCALAR")
                        api.log("  " .. api.name(p) .. " = " .. value)
                    end)
                end)
                if not ok then api.log("TeamConfig reflection unavailable: " .. tostring(err)) end
            end
        end
        local count = 0
        for i = 1, #c.gs.PlayerArray do
            local ps = c.gs.PlayerArray[i]
            if api.try(function() return ps.bIsABot end) == true and
                api.try(function() return ps.TeamID end) == -1 and count < 6 then
                count = count + 1
                trace(c, api.name(ps), nil)
            end
        end
        api.log("Unassigned bot entries inspected: " .. count)
    end
    local function raiseTeamCaps()
        api.log("=== F4 configured TeamConfig capacity experiment ===")
        local limit, configErr = api.config()
        if not limit then api.log("TeamConfig change REFUSED: config: " .. tostring(configErr)); return end
        local c = api.context()
        if not c.host or api.try(function() return c.gm:IsA("/Script/Bodycam.BodycamGameMode") end) ~= true then
            api.log("TeamConfig change REFUSED: not a networked Bodycam host"); return
        end
        local asset = api.try(function() return c.gs.GameModeConfigDataAsset end)
        if not api.valid(asset) or
            api.try(function() return asset:IsA("/Script/Bodycam.GameModeConfigDataAsset") end) ~= true then
            api.log("TeamConfig change REFUSED: active GameModeConfigDataAsset not found"); return
        end
        local teamProperty = api.try(function() return asset:Reflection():GetProperty("TeamConfig") end)
        if not api.valid(teamProperty) or
            api.name(teamProperty) ~= "StructProperty /Script/Bodycam.GameModeConfigDataAsset:TeamConfig" then
            api.log("TeamConfig change REFUSED: unexpected TeamConfig property"); return
        end
        local struct = api.try(function() return teamProperty:GetStruct() end)
        if not api.valid(struct) or api.name(struct) ~= "ScriptStruct /Script/Bodycam.TeamConfig" then
            api.log("TeamConfig change REFUSED: unexpected TeamConfig struct"); return
        end
        local fields = {}
        local reflected, reflectErr = pcall(function()
            struct:ForEachProperty(function(p) fields[api.short(p)] = p end)
        end)
        if not reflected then api.log("TeamConfig change REFUSED: reflection failed: " .. tostring(reflectErr)); return end
        for _, n in ipairs({"MaxPlayers", "TeamMaxSize"}) do
            if not api.valid(fields[n]) or not api.isType(fields[n], "IntProperty") or
                api.name(fields[n]) ~= "IntProperty /Script/Bodycam.TeamConfig:" .. n then
                api.log("TeamConfig change REFUSED: unexpected field " .. n); return
            end
        end
        local data = api.try(function() return asset.TeamConfig end)
        if not api.valid(data) then api.log("TeamConfig change REFUSED: struct value unavailable"); return end
        local oldTotal = api.try(function() return data.MaxPlayers end)
        local oldTeam = api.try(function() return data.TeamMaxSize end)
        if type(oldTotal) ~= "number" or type(oldTeam) ~= "number" or
            oldTotal < 2 or oldTotal > 64 or oldTeam < 1 or oldTeam > 64 then
            api.log("TeamConfig change REFUSED: unexpected current values " .. tostring(oldTotal) .. "/" .. tostring(oldTeam)); return
        end
        local nextTotal = limit
        local nextTeam = math.ceil(limit / 2)
        api.log("Active asset: " .. api.name(asset) .. "; configured maxPlayers=" .. limit)
        api.log("Configured test target: MaxPlayers " .. oldTotal .. " -> " .. nextTotal
            .. "; TeamMaxSize " .. oldTeam .. " -> " .. nextTeam)
        if nextTotal < oldTotal or nextTeam < oldTeam then
            api.log("TeamConfig result: REFUSED to lower active match capacity; restart match for a smaller target")
            return
        end
        if nextTotal <= oldTotal and nextTeam <= oldTeam then
            api.log("TeamConfig result: NO CHANGE; config does not allow a higher target"); return
        end
        local okTotal, totalErr = pcall(function() data.MaxPlayers = nextTotal end)
        local gotTotal = api.try(function() return asset.TeamConfig.MaxPlayers end)
        api.log("TeamConfig.MaxPlayers: " .. oldTotal .. " -> " .. tostring(gotTotal)
            .. "; " .. (okTotal and gotTotal == nextTotal and "SUCCESS" or "FAILED")
            .. (totalErr and ("; " .. tostring(totalErr)) or ""))
        if not okTotal or gotTotal ~= nextTotal then
            api.log("TeamConfig result: FAILED; TeamMaxSize not changed"); return
        end
        local okTeam, teamErr = pcall(function() data.TeamMaxSize = nextTeam end)
        local gotTeam = api.try(function() return asset.TeamConfig.TeamMaxSize end)
        api.log("TeamConfig.TeamMaxSize: " .. oldTeam .. " -> " .. tostring(gotTeam)
            .. "; " .. (okTeam and gotTeam == nextTeam and "SUCCESS" or "FAILED")
            .. (teamErr and ("; " .. tostring(teamErr)) or ""))
        if not okTeam or gotTeam ~= nextTeam then
            local restored = pcall(function() data.MaxPlayers = oldTotal end)
            api.log("TeamConfig result: PARTIAL/FAILED; MaxPlayers rollback " .. (restored and "attempted" or "FAILED"))
            return
        end
        api.log("TeamConfig result: local fields accepted; active bot beyond 10 still UNVERIFIED")
    end
    counts = function(c)
        local total, bots, unknown = 0, 0, 0
        local teams = {}
        local ok, err = pcall(function()
            local players = c.gs.PlayerArray
            total = #players
            for i = 1, total do
                local ps = players[i]
                local bot = api.try(function() return ps.bIsABot end)
                if bot == true then bots = bots + 1 elseif bot ~= false then unknown = unknown + 1 end
                local team = api.try(function() return ps.TeamID end)
                if type(team) == "number" then teams[team] = (teams[team] or 0) + 1 end
            end
        end)
        if not ok then return nil, err end
        local labels = {}
        for team, n in pairs(teams) do labels[#labels + 1] = tostring(team) .. "=" .. n end
        table.sort(labels)
        return {total=total, bots=bots, unknown=unknown,
            text=string.format("PlayerArray=%d bots=%d unknownBotFlags=%d teams={%s}", total, bots, unknown, table.concat(labels, ", "))}
    end
    local function press()
        api.log("=== F7 single-bot experiment ===")
        if observation then api.log("Bot request SKIPPED: previous request is still being observed"); return end
        local limit, err = api.config()
        if not limit then api.log("Bot request FAILED: config: " .. tostring(err)); return end
        local c = api.context()
        if not c.host then api.log("Bot request REFUSED: not a confirmed networked host"); return end
        if api.try(function() return c.gm:IsA("/Script/Bodycam.BodycamGameMode") end) ~= true then
            api.log("Bot request REFUSED: active GameMode is not BodycamGameMode"); return
        end
        local public, publicErr = api.try(function() return c.gm:IsPublicLobby() end)
        api.log("Host access diagnostic: IsPublicLobby=" .. tostring(public) .. "; Lua type=" .. type(public)
            .. (publicErr and ("; read error=" .. publicErr) or ""))
        -- User confirmed this is their own public hosted match. Access type is diagnostic;
        -- networked host authority, exact function signature and count limit remain required.
        local f = StaticFindObject("/Script/Bodycam.BodycamGameMode:SpawnBot")
        if not api.valid(f) then api.log("Bot request FAILED: reflected SpawnBot not found"); return end
        -- The observed base signature consists solely of ObjectProperty ReturnValue.
        local fields, signatureOK = 0, true
        f:ForEachProperty(function(p)
            fields = fields + 1
            if api.short(p) ~= "ReturnValue" or not api.isType(p, "ObjectProperty") then signatureOK = false end
        end)
        if not signatureOK or fields ~= 1 then api.log("Bot request REFUSED: SpawnBot signature differs from captured build"); return end
        local before, countErr = counts(c)
        if not before then api.log("Bot request FAILED: cannot count current players: " .. tostring(countErr)); return end
        api.log("Before spawn: " .. before.text)
        if before.total >= limit then api.log("Bot request REFUSED: PlayerArray already at configured maxPlayers=" .. limit); return end
        local previousStates = {}
        for i = 1, #c.gs.PlayerArray do previousStates[api.name(c.gs.PlayerArray[i])] = true end
        -- Call the instance member so the game's Blueprint implementation can dispatch normally.
        local ok, result = pcall(function() return c.gm:SpawnBot() end)
        api.log("SpawnBot call: " .. (ok and "RETURNED" or "FAILED") .. "; result=" .. (ok and api.name(result) or tostring(result)))
        if not ok then return end
        local newStateName
        for i = 1, #c.gs.PlayerArray do
            local ps = c.gs.PlayerArray[i]
            if not previousStates[api.name(ps)] and api.try(function() return ps.bIsABot end) == true then
                newStateName = api.name(ps); break
            end
        end
        observation = {world=api.name(c.world), before=before, checks=0,
            stateName=newStateName, controllerName=api.name(result)}
        local after = counts(c)
        if after then api.log("Immediately after spawn: " .. after.text) end
        trace(c, newStateName, observation.controllerName)
        api.log("Bot result: PENDING; a returned object alone does not prove an extra active bot")
    end
    local function poll(c)
        if recovery then
            if not c.host or api.name(c.world) ~= recovery.world then
                api.log("Recovery observation stopped: host/world changed"); recovery=nil
            else
                recovery.checks = recovery.checks + 1
                if recovery.checks <= 12 then
                    api.log("Recovery delayed check " .. recovery.checks .. "/12")
                    trace(c,recovery.stateName,recovery.controllerName)
                end
                if recovery.checks >= 12 then recovery=nil end
            end
        end
        if not observation then return end
        if not c.host or api.name(c.world) ~= observation.world then
            api.log("Bot observation stopped: host/world changed"); observation = nil; return
        end
        local current, err = counts(c)
        if not current then api.log("Bot observation FAILED: " .. tostring(err)); observation=nil; return end
        observation.checks = observation.checks + 1
        api.log("Bot delayed check " .. observation.checks .. "/24: " .. current.text
            .. "; total delta=" .. (current.total - observation.before.total)
            .. "; bot delta=" .. (current.bots - observation.before.bots))
        if observation.checks == 1 or observation.checks % 4 == 0 or not byName(c, observation.stateName) then
            trace(c, observation.stateName, observation.controllerName)
        end
        if observation.checks >= 24 then
            local increased = current.total > observation.before.total and current.bots > observation.before.bots
                and current.unknown == 0 and observation.before.unknown == 0
            api.log("Bot result after ~2 minutes: " .. (increased and "EXTRA BOT ENTRY OBSERVED" or "INCONCLUSIVE / NO RETAINED EXTRA BOT")
                .. "; visually verify pawn, team, AI activity and scoreboard. Human join capacity remains UNVERIFIED.")
            observation = nil
        end
    end
    return {press=press, poll=poll, inspect=inspect, recover=recover, raiseTeamCaps=raiseTeamCaps}
end
