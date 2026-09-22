-- Read-only snapshot of bot difficulty candidates in the current match.
return function(api)
    local tokens = {"bot", "accuracy", "aim", "skill", "reaction", "perception",
        "sight", "hearing", "fire", "shoot", "spread", "recoil", "target",
        "detect", "range", "vision", "movement", "speed"}

    local function relevant(s)
        s = s:lower()
        for _, token in ipairs(tokens) do
            if s:find(token, 1, true) then return true end
        end
        return false
    end

    local function value(o, n)
        local v, err = api.try(function() return o[n] end)
        if err then return "<unreadable: " .. tostring(err) .. ">" end
        if type(v) == "number" or type(v) == "boolean" or type(v) == "string" then return tostring(v) end
        if api.valid(v) then return api.name(v) end
        return "<complex/nil>"
    end

    local function inspect(o, label)
        if not api.valid(o) then return end
        api.log("[difficulty] " .. label .. " = " .. api.name(o))
        local class = api.try(function() return o:GetClass() end)
        local seen, fields, funcs = {}, 0, 0
        for _ = 1, 12 do
            if not api.valid(class) then break end
            local ok, err = pcall(function()
                class:ForEachProperty(function(p)
                    local n = api.short(p)
                    if relevant(n) and not seen[n] and fields < 65 then
                        seen[n], fields = true, fields + 1
                        api.log("[difficulty]   field " .. api.name(p) .. " = " .. value(o, n))
                    end
                end)
                class:ForEachFunction(function(f)
                    local n = api.short(f)
                    if relevant(n) and not seen["fn:" .. n] and funcs < 30 then
                        seen["fn:" .. n], funcs = true, funcs + 1
                        api.log("[difficulty]   function " .. api.name(f))
                    end
                end)
            end)
            if not ok then api.log("[difficulty] reflection stopped: " .. tostring(err)); break end
            class = api.try(function() return class:GetSuperStruct() end)
        end
        api.log("[difficulty]   totals: " .. fields .. " fields, " .. funcs .. " functions")
    end

    local function firstOf(className, limit)
        local found, err = api.try(function() return FindAllOf(className) end)
        if not found then
            api.log("[difficulty] FindAllOf(" .. className .. ") unavailable: " .. tostring(err))
            return
        end
        api.log("[difficulty] " .. className .. " instances = " .. #found)
        local count = 0
        for _, o in ipairs(found) do
            if api.valid(o) and not api.name(o):find("Default__", 1, true) then
                inspect(o, className)
                count = count + 1
                if count >= limit then break end
            end
        end
    end

    return function()
        api.log("=== F12 bot difficulty probe: read only ===")
        local c = api.context()
        if not c.host then api.log("[difficulty] No authoritative hosted match: " .. c.reason); return end
        inspect(c.gi, "GameInstance")
        inspect(c.gm, "GameMode")
        inspect(c.gs, "GameState")
        firstOf("AI_Humanoid_C", 2)
        firstOf("AIController", 2)
        firstOf("AIPerceptionComponent", 2)
        firstOf("AISenseConfig_Sight", 2)
        api.log("=== End F12 bot difficulty probe ===")
    end
end
