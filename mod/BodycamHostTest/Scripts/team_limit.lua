-- Applies the reflected Bodycam TeamConfig player fields.
return function(api)
    local function raiseTeamCaps()
        api.log("=== Player limit TeamConfig capacity experiment ===")
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
        -- Deathmatch is free-for-all: its stock TeamMaxSize is 1. Raising it
        -- changes a game rule unrelated to player capacity and may prevent
        -- the waiting phase from completing. Only TDM has larger teams.
        local isTdm = api.name(c.gm:GetClass()):lower():find('gm_teamdeathmatch', 1, true) ~= nil
        local nextTeam = isTdm and math.ceil(limit / 2) or oldTeam
        api.log("Active asset: " .. api.name(asset) .. "; configured maxPlayers=" .. limit)
        api.log("Configured test target: MaxPlayers " .. oldTotal .. " -> " .. nextTotal
            .. "; TeamMaxSize " .. oldTeam .. " -> " .. nextTeam)
        if nextTotal < oldTotal or nextTeam < oldTeam then
            api.log("TeamConfig result: REFUSED to lower active match capacity; restart match for a smaller target")
            return "lower"
        end
        if nextTotal <= oldTotal and nextTeam <= oldTeam then
            api.log("TeamConfig result: NO CHANGE; active gameplay capacity already matches config"); return true
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
        return true
    end
    return raiseTeamCaps
end
