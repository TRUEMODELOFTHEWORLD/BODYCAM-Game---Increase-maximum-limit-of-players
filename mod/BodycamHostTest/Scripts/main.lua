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
local function contextForWorld(world)
    local c = {host = false, reason = "No active local controller/world"}
    c.world = world
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
local function context()
    for _, pc in ipairs(FindAllOf("PlayerController") or {}) do
        if valid(pc) and try(function() return pc:IsLocalController() end) == true then
            local world = try(function() return pc:GetWorld() end)
            if valid(world) then return contextForWorld(world) end
        end
    end
    return contextForWorld(nil)
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

local function apply(teamAccepted)
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
    log("Result: " .. ((accepted > 0 or teamAccepted == true) and "PARTIAL" or "FAILED")
        .. "; TeamConfig=" .. (teamAccepted == true and "ACCEPTED" or "UNCONFIRMED")
        .. "; backend advertisement and beyond-limit joins UNVERIFIED")
    log("Session creation/update not intercepted. Existing lobby allocation may retain its original limit.")
    log("Team arrays/spawns and scoreboard/UI: NOT MODIFIED; validate with real clients")
end

local applyTeamLimit = dofile(scripts .. "/team_limit.lua")({
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
local applyServerSettings = dofile(scripts .. "/server_settings.lua")({
    log=log, try=try, valid=valid, name=name, isType=isType, properties=properties,
    context=context, specs=Config.serverSpecs, order=Config.serverOrder,
    readConfig=function() return Config.readServerSettings(root .. "/config.json") end
})
local function loadBotLimit(source)
    log("Bot limit load requested (" .. source .. ")")
    if not botProbe.enableCap() then return end
    local limit, err = Config.read(root .. "/config.json")
    if not limit then
        log("Bot initial-fill window unavailable: " .. tostring(err))
        return
    end
    fillWindow.configure(context(), botProbe.currentCap(), limit)
end
local function loadPlayerLimit()
    if fillWindow.activeWindow() then
        log("F9 player limit REFUSED during the bot initial-fill window; retry after it restores")
        return
    end
    local teamResult = applyTeamLimit()
    if teamResult == "lower" then
        log("F9 player limit REFUSED: start a fresh match to lower the active limit")
        return
    end
    apply(teamResult)
    if botProbe.capEnabled() then
        local limit, err = Config.read(root .. "/config.json")
        if limit then fillWindow.configure(context(), botProbe.currentCap(), limit)
        else log("Bot initial-fill window unavailable: " .. tostring(err)) end
    end
end
local lastSummary, queued, pollFailed, autoAttemptWorld = nil, false, false, nil
local function poll()
    local c = context()
    local summary = name(c.world) .. "/" .. tostring(c.host) .. "/" .. tostring(c.count)
    if summary ~= lastSummary then lastSummary = summary; header(c) end
    if not c.host then autoAttemptWorld = nil end
    if c.host and not botProbe.capEnabled() and autoAttemptWorld ~= name(c.world) then
        autoAttemptWorld = name(c.world)
        loadBotLimit("automatic host detection")
    end
    botProbe.poll(c)
    fillWindow.poll(c)
    if not pending then return end
    if not c.host or name(c.world) ~= pending.world then
        log("Write observation stopped: host/world changed; press F9 in the new hosted match")
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

log("=== BodycamHostTest local revision 3.9 server-settings test loaded ===")
log("F9 = load configured player limit; F10 = load configured bot limit; F11 = load enabled server settings")
log("Config: " .. root .. "/config.json")
log("Bot limit will load automatically when a hosted match is detected; existing bots are not removed")
log("TDM bot fill may temporarily lower gameplay capacity for up to 35 seconds; human admission remains unverified")
RegisterKeyBind(Key.F9, function() dispatch(loadPlayerLimit) end)
RegisterKeyBind(Key.F10, function() dispatch(function() loadBotLimit("F10 refresh") end) end)
RegisterKeyBind(Key.F11, function() dispatch(applyServerSettings) end)
local function earlyFill(param, event)
    local actor = try(function() return param:Get() end)
    if not valid(actor) then actor = param end
    if not valid(actor) then return end
    if event == 'BeginPlay' and
        not name(actor:GetClass()):lower():find('gm_teamdeathmatch', 1, true) then return end
    local world = try(function() return actor:GetWorld() end)
    if not valid(world) then return end
    local c = contextForWorld(world)
    if not c.host or not valid(c.gm) or not valid(c.gs) then return end
    if not name(c.gm:GetClass()):lower():find('gm_teamdeathmatch', 1, true) then return end
    if event == 'BeginPlay' and name(actor) ~= name(c.gm) then return end
    fillWindow.poll(c, true)
end
if type(RegisterInitGameStatePostHook) == 'function' then
    RegisterInitGameStatePostHook(function(param)
        local ok, err = pcall(earlyFill, param, 'InitGameState')
        if not ok then log('Early bot fill InitGameState FAILED: ' .. tostring(err)) end
    end)
else log('Early bot fill InitGameState hook unavailable') end
if type(RegisterBeginPlayPostHook) == 'function' then
    RegisterBeginPlayPostHook(function(param)
        local ok, err = pcall(earlyFill, param, 'BeginPlay')
        if not ok then log('Early bot fill BeginPlay FAILED: ' .. tostring(err)) end
    end)
else log('Early bot fill BeginPlay hook unavailable') end
LoopAsync(100, function()
    dispatch(function() fillWindow.poll(context(), true) end)
    return false
end)
LoopAsync(5000, function()
    dispatch(function()
        local ok, err = pcall(poll)
        if not ok and not pollFailed then log("Automatic host check FAILED: " .. tostring(err)); pollFailed = true end
    end)
    return false
end)
