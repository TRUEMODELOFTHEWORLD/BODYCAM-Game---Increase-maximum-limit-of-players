-- Phase 1: reflection first, explicit F9 writes, no offsets or guessed Bodycam calls.
local source = debug.getinfo(1, "S").source:gsub("^@", ""):gsub("\\", "/")
local scripts = assert(source:match("^(.*)/[^/]+$"), "Cannot locate mod directory")
local root = scripts .. "/.."
local Config = dofile(scripts .. "/config.lua")
local logPath = root .. "/BodycamHostTest.log"
local function log(s)
    local line = "[BodycamHost] " .. tostring(s)
    print(line .. "\n")
    local f = io.open(logPath, "a")
    if f then f:write(os.date("!%Y-%m-%dT%H:%M:%SZ "), line, "\n"); f:close() end
end
local function try(fn)
    local ok, value = pcall(fn)
    if ok then return value end
    return nil, tostring(value)
end
local function valid(o) return o ~= nil and try(function() return o:IsValid() end) == true end
local function name(o) return try(function() return o:GetFullName() end) or "NOT FOUND" end
local function short(o) return try(function() return o:GetFName():ToString() end) or "?" end
local function read(o, p) return try(function() return o[p] end) end
local function isType(p, t)
    return PropertyTypes and PropertyTypes[t] ~= nil and try(function() return p:IsA(PropertyTypes[t]) end) == true
end
local function related(s)
    s = s:lower()
    for _, token in ipairs({"session", "lobby", "maxplayer", "publicconnection", "playerlimit", "teamsize",
        "maxmember", "team", "spawn", "capacity", "match", "host", "playerarray", "numplayer",
        "gamemode", "gamestate", "gameinstance", "playerstate"}) do
        if s:find(token, 1, true) then return true end
    end
    return false
end
local function properties(class, cb)
    local seen = {}
    for _ = 1, 20 do
        if not valid(class) then return end
        class:ForEachProperty(function(p)
            local n = short(p)
            if not seen[n] then seen[n] = true; cb(p, n) end
        end)
        class = class:GetSuperStruct()
    end
end
local function scalar(v)
    if type(v) == "number" or type(v) == "boolean" then return tostring(v) end
    if valid(v) then return name(v) end
    return "<not scalar; not expanded>"
end

-- A menu can have an authoritative GameMode. Require a networked server too.
local function context()
    local c = {host = false, reason = "No active local controller/world"}
    for _, pc in ipairs(FindAllOf("PlayerController") or {}) do
        if valid(pc) and try(function() return pc:IsLocalController() end) == true then
            c.world = try(function() return pc:GetWorld() end)
            break
        end
    end
    if not valid(c.world) then return c end
    c.gm = read(c.world, "AuthorityGameMode")
    c.gs = read(c.world, "GameState")
    c.gi = read(c.world, "OwningGameInstance")
    local k = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
    c.server = valid(k) and try(function() return k:IsServer(c.world) end)
    c.standalone = valid(k) and try(function() return k:IsStandalone(c.world) end)
    c.host = valid(c.gm) and c.server == true and c.standalone == false
    c.reason = c.host and "Networked authoritative host detected; private/public status not inferred"
        or "Not a confirmed networked host (client/menu/standalone/unknown); writes refused"
    if valid(c.gs) then c.count = try(function() return #c.gs.PlayerArray end) end
    return c
end

-- Only these exact names qualify for a test write, after reflection verifies IntProperty.
-- Two Bodycam-specific exceptions below were confirmed by live F8 reflection.
local writableNames = {MaxPlayers = true, NumPublicConnections = true, PublicConnections = true}
local bodycamSessionProperty = "IntProperty /Game/MenuSystemPro/Blueprints/Core/BodycamGI.BodycamGI_C:Session Max Players"
local bodycamStateProperty = "ByteProperty /Script/Bodycam.BodycamGameState:MaxPlayers"
local function targets(c)
    local out, seen = {}, {}
    local function add(o, role, depth, writable)
        if not valid(o) or #out >= 24 then return end
        local id = name(o)
        if seen[id] or id:find("Default__", 1, true) then return end
        if try(function() return o:HasAnyFlags(0x30) end) ~= false then return end
        seen[id] = true
        out[#out + 1] = {object = o, role = role, depth = depth, writable = writable}
    end
    add(c.gm, "GameMode/gameplay", 0, true)
    add(c.gs, "GameState/replicated observation", 0, false)
    add(c.gi, "GameInstance/session configuration", 0, true)
    local i = 1
    while i <= #out do
        local t = out[i]
        if t.depth < 2 then
            properties(t.object:GetClass(), function(p, n)
                local lower = n:lower()
                if (isType(p, "ObjectProperty") or isType(p, "ObjectPtrProperty")) and
                    (lower:find("session") or lower:find("lobby") or lower:find("settings") or lower:find("team") or n == "GameModeConfigDataAsset") then
                    local child = read(t.object, n)
                    local belongs = valid(child) and try(function() return child:GetWorld():GetAddress() == c.world:GetAddress() end)
                    -- This exact asset link was observed on the live match GameState. Read only.
                    if n == "GameModeConfigDataAsset" then
                        add(child, t.role .. "." .. n, t.depth + 1, false)
                    end
                    if belongs then
                        local write = t.writable and (lower:find("session") ~= nil or lower:find("lobby") ~= nil)
                        add(child, t.role .. "." .. n, t.depth + 1, write)
                    end
                end
            end)
        end
        i = i + 1
    end
    return out
end

local function header(c)
    log(c.reason)
    log("World: " .. name(c.world))
    log("GameMode: " .. (valid(c.gm) and name(c.gm:GetClass()) or "NOT FOUND"))
    log("GameState: " .. (valid(c.gs) and name(c.gs:GetClass()) or "NOT FOUND"))
    log("Current PlayerArray entries: " .. tostring(c.count or "UNKNOWN") .. " (may include bots/spectators; not verified human connections)")
    log("Online/EOS session interface: UNKNOWN (native interfaces are not necessarily UObjects)")
    log("Current advertised backend capacity: UNKNOWN; a local property is not backend readback")
end

local function inspectObjects(ts)
    local lines = 0
    for _, t in ipairs(ts) do
        log("Object [" .. t.role .. "]: " .. name(t.object))
        properties(t.object:GetClass(), function(p, n)
            if related(n) and lines < 100 then
                lines = lines + 1
                local v, err = read(t.object, n)
                local value = scalar(v)
                if isType(p, "ArrayProperty") then
                    value = "array entries=" .. tostring(try(function() return #v end) or "UNKNOWN")
                end
                log("  " .. name(p) .. " = " .. (err and ("READ FAILED: " .. err) or value))
            end
        end)
    end
    if lines >= 100 then log("Property output capped at 100 lines") end
end

-- Enumerates metadata only, once per F8. Logs bounded multiplayer signatures, no player identifiers.
local function inspectClasses()
    local classes, funcs, params = 0, 0, 0
    local seen = {}
    ForEachUObject(function(o)
        if classes >= 30 or not valid(o) then return end
        if try(function() return o:IsClass() end) ~= true then return end
        local path = name(o)
        local candidates = {BodycamCreateLobby=true, BodycamUpdateLobby=true, BodycamLobbyManager=true,
            BodycamGameMode=true, BodycamGameState=true, GameModeConfigDataAsset=true,
            GameSession=true, GameSessionSettings=true, BodycamGI_C=true, GI_BodycamSteamBackend_C=true,
            BP_BodycamGameModeAbstract_C=true, GM_Deathmatch_C=true, GS_Bodycam_C=true}
        local relevant = candidates[short(o)] == true
        if not relevant or seen[path] then return end
        seen[path], classes = true, classes + 1
        log("Reflected class: " .. path)
        o:ForEachProperty(function(p)
            if related(short(p)) and params < 180 then params = params + 1; log("  Class property: " .. name(p)) end
        end)
        o:ForEachFunction(function(f)
            local fn = short(f):lower()
            local capacity = fn:find("max", 1, true) or fn:find("limit", 1, true)
                or fn:find("lobby", 1, true) or fn:find("session", 1, true)
            if funcs >= 60 or not capacity then return end
            funcs = funcs + 1
            log("  Function: " .. name(f) .. " flags=" .. tostring(try(function() return f:GetFunctionFlags() end)))
            f:ForEachProperty(function(p)
                if params < 180 then params = params + 1; log("    Signature field: " .. name(p)) end
            end)
        end)
    end)
    log(string.format("Filtered metadata: classes=%d/30 functions=%d/60 fields=%d/180; unloaded/native-only items may be absent", classes, funcs, params))
end

local pending -- Strings/numbers only; never retain UObject wrappers across travel/GC.
local function diagnostic()
    log("=== F8 diagnostic (read only) ===")
    local n, err = Config.read(root .. "/config.json")
    log("Requested player limit: " .. tostring(n or ("INVALID: " .. err)))
    local c = context()
    header(c)
    inspectObjects(targets(c))
    inspectClasses()
    log("=== End diagnostic ===")
end

local function apply()
    log("=== F9 capacity experiment ===")
    local n, err = Config.read(root .. "/config.json")
    if not n then log("Result: FAILED; configuration: " .. err); return end
    log("Requested player limit: " .. n .. " (2-64 is a test guard, not supported capacity)")
    local c = context()
    header(c)
    if not c.host then log("Result: FAILED; " .. c.reason); return end
    local attempted, accepted = 0, 0
    local records = {}
    for _, t in ipairs(targets(c)) do
        if t.writable or t.object == c.gs then
            properties(t.object:GetClass(), function(p, prop)
                local full = name(p)
                local exactSession = full == bodycamSessionProperty and t.object == c.gi
                local exactState = full == bodycamStateProperty and t.object == c.gs
                if not exactSession and not exactState and not (t.writable and writableNames[prop]) then return end
                local label = "[" .. t.role .. "] " .. name(t.object) .. "." .. prop
                local expectedType = exactState and "ByteProperty" or "IntProperty"
                if not isType(p, expectedType) then log(label .. ": SKIPPED; not reflected " .. expectedType); return end
                if exactState then log("GameState byte write is an experiment; replication/admission effects are unverified") end
                attempted = attempted + 1
                local before, readErr = read(t.object, prop)
                if type(before) ~= "number" then log(label .. ": READ FAILED " .. tostring(readErr)); return end
                local ok, setErr = pcall(function() t.object[prop] = n end)
                local after, afterErr = read(t.object, prop)
                local success = ok and after == n
                if success then accepted = accepted + 1 end
                log(label .. ": " .. before .. " -> " .. tostring(after) .. "; local write=" .. (success and "SUCCESS" or "FAILED")
                    .. (setErr and ("; " .. tostring(setErr)) or "") .. (afterErr and ("; " .. afterErr) or ""))
                records[#records + 1] = {object = name(t.object), property = prop, desired = n}
            end)
        end
    end
    pending = {world = name(c.world), records = records, checks = 0}
    log(string.format("Local properties accepted: %d/%d", accepted, attempted))
    log("Result: " .. (accepted > 0 and "PARTIAL" or "FAILED") .. "; backend advertisement and beyond-limit joins UNVERIFIED")
    log("Session creation/update not intercepted. Existing lobby allocation may retain its original limit.")
    log("Team arrays/spawns and scoreboard/UI: NOT MODIFIED; validate with real clients")
end

local botTest = dofile(scripts .. "/bot_test.lua")({
    log=log, try=try, valid=valid, name=name, short=short, isType=isType, context=context,
    config=function() return Config.read(root .. "/config.json") end
})
local botProbe = dofile(scripts .. "/bot_probe.lua")({
    log=log, try=try, valid=valid, name=name, short=short, context=context,
    botConfig=function() return Config.readBotCap(root .. "/config.json") end
})
local fillWindow = dofile(scripts .. "/fill_window.lua")({
    log=log, try=try, valid=valid, name=name, isType=isType, context=context,
    botConfig=function() return Config.readBotCap(root .. "/config.json") end,
    playerConfig=function() return Config.read(root .. "/config.json") end,
    capEnabled=botProbe.capEnabled
})
local lastSummary, queued, pollFailed = nil, false, false
local function poll()
    local c = context()
    local summary = name(c.world) .. "/" .. tostring(c.host) .. "/" .. tostring(c.count)
    if summary ~= lastSummary then lastSummary = summary; header(c) end
    botTest.poll(c)
    botProbe.poll(c)
    fillWindow.poll(c)
    if not pending then return end
    if not c.host or name(c.world) ~= pending.world then
        log("Write observation stopped: host/world changed; F8 then F9 in the new hosted match")
        pending = nil; return
    end
    local live = {}
    for _, t in ipairs(targets(c)) do live[name(t.object)] = t.object end
    for _, r in ipairs(pending.records) do
        local o = live[r.object]
        local value = o and read(o, r.property)
        log("Delayed readback " .. r.object .. "." .. r.property .. " = " .. tostring(value or "UNAVAILABLE")
            .. "; " .. (value == r.desired and "RETAINED locally" or "FAILED / overwritten / unavailable"))
    end
    pending.checks = pending.checks + 1
    if pending.checks >= 3 then pending = nil end
end
local function dispatch(fn)
    if queued then return end
    queued = true
    local ok, err = pcall(function()
        ExecuteInGameThread(function()
            local worked, why = pcall(fn)
            queued = false
            if not worked then log("ERROR: " .. tostring(why)) end
        end)
    end)
    if not ok then queued = false; log("Game-thread dispatch FAILED: " .. tostring(err)) end
end

log("=== BodycamHostTest phase 1 revision 3.6 loaded; inspected build 25228199 ===")
log("F4 = apply configured limit to active TeamConfig")
log("F3 = read-only bot-fill probe (no hooks or changes)")
log("F1 = toggle Blueprint bot-decision watch and disable bot cap; turn it off before restarting mods")
log("F10 = toggle configured bot cap on future spawn decisions; F1 turns off the hook and cap")
log("F2 = toggle automatic TDM bot-fill window; restores full capacity after 35s on each map")
log("F8 = diagnostic; F9 = apply config to your hosted match; restart to discard changes")
log("Config: " .. root .. "/config.json")
log("F2 temporarily changes gameplay capacity on TDM map changes; actual human admission remains unverified.")
RegisterKeyBind(Key.F8, function() dispatch(diagnostic) end)
RegisterKeyBind(Key.F3, function() dispatch(botProbe.run) end)
RegisterKeyBind(Key.F1, function() dispatch(botProbe.toggleWatch) end)
RegisterKeyBind(Key.F10, function() dispatch(botProbe.toggleCap) end)
RegisterKeyBind(Key.F2, function() dispatch(fillWindow.press) end)
RegisterKeyBind(Key.F9, function() dispatch(apply) end)
RegisterKeyBind(Key.F4, function() dispatch(botTest.raiseTeamCaps) end)
LoopAsync(5000, function()
    dispatch(function()
        local ok, err = pcall(poll)
        if not ok and not pollFailed then log("Automatic diagnostic FAILED (F8 to retry): " .. tostring(err)); pollFailed = true end
    end)
    return false
end)
