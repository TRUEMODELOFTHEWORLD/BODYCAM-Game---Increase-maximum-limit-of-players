local M = {}

-- Testing guards, not claims about Bodycam's supported ranges.
M.serverOrder = {
    'PhaseDuration', 'bUseTimerForWaitingPlayers', 'WaitingForPlayersDuration',
    'RoundWarmupDuration', 'EndRoundDuration', 'RespawnDelay',
    'RemainingTimeToStartTimerSounds', 'ScoreLimit', 'MaxPhases',
    'TeamSwitchInterval', 'GraceWindowDistance', 'GraceWindowDuration',
    'VoteMapTimerMax'
}
M.serverSpecs = {
    PhaseDuration={group='PhaseConfig', kind='float', min=60, max=3600},
    bUseTimerForWaitingPlayers={group='PhaseConfig', kind='bool'},
    WaitingForPlayersDuration={group='PhaseConfig', kind='float', min=0, max=300},
    RoundWarmupDuration={group='PhaseConfig', kind='float', min=0, max=120},
    EndRoundDuration={group='PhaseConfig', kind='float', min=0, max=120},
    RespawnDelay={group='PhaseConfig', kind='float', min=0, max=60},
    RemainingTimeToStartTimerSounds={group='PhaseConfig', kind='float', min=0, max=30},
    ScoreLimit={group='ScoringConfig', kind='int', min=1, max=500},
    MaxPhases={group='ScoringConfig', kind='int', min=1, max=20},
    TeamSwitchInterval={group='TeamConfig', kind='int', min=0, max=120},
    GraceWindowDistance={group='LoadoutConfig', kind='float', min=0, max=5000},
    GraceWindowDuration={group='LoadoutConfig', kind='float', min=0, max=120},
    VoteMapTimerMax={group='GameState', kind='int', min=5, max=300}
}

local NULL = {}
local function decode(text)
    local i = 1
    local function spaces()
        while i <= #text and text:sub(i, i):match('%s') do i = i + 1 end
    end
    local function fail() error('Expected a JSON object with numeric, boolean or null values', 0) end
    local object
    local function value(depth)
        spaces()
        if text:sub(i, i) == '{' then return object(depth + 1) end
        local start = i
        while i <= #text and not text:sub(i, i):match('[,%}%s]') do i = i + 1 end
        local token = text:sub(start, i - 1)
        if token == 'null' then return NULL end
        if token == 'true' then return true end
        if token == 'false' then return false end
        if not (token:match('^%-?%d+$') or token:match('^%-?%d+%.%d+$')) then fail() end
        local unsigned = token:sub(1, 1) == '-' and token:sub(2) or token
        if unsigned:match('^0%d') then fail() end
        local n = tonumber(token)
        if not n or n ~= n or math.abs(n) > 1000000000 then fail() end
        return n
    end
    object = function(depth)
        if depth > 2 or text:sub(i, i) ~= '{' then fail() end
        i = i + 1
        spaces()
        local out = {}
        if text:sub(i, i) == '}' then i = i + 1; return out end
        while true do
            if text:sub(i, i) ~= '"' then fail() end
            local close = text:find('"', i + 1, true)
            if not close then fail() end
            local key = text:sub(i + 1, close - 1)
            if not key:match('^[A-Za-z][A-Za-z0-9]*$') or out[key] ~= nil then fail() end
            i = close + 1
            spaces()
            if text:sub(i, i) ~= ':' then fail() end
            i = i + 1
            out[key] = value(depth)
            spaces()
            local separator = text:sub(i, i)
            if separator == '}' then i = i + 1; return out end
            if separator ~= ',' then fail() end
            i = i + 1
            spaces()
        end
    end
    spaces()
    local out = object(1)
    spaces()
    if i <= #text then fail() end
    return out
end

local function parseFields(text)
    local ok, fields = pcall(decode, text)
    if not ok then return nil, fields end
    for key in pairs(fields) do
        if key ~= 'maxPlayers' and key ~= 'maxBotsPerTeam' and key ~= 'serverSettings' then
            return nil, 'Unknown top-level key: ' .. key
        end
    end
    local n = fields.maxPlayers
    if type(n) ~= 'number' or n % 1 ~= 0 or n < 2 or n > 64 then
        return nil, 'maxPlayers must be an integer from 2 through 64'
    end
    local cap = fields.maxBotsPerTeam
    if cap == NULL then cap = nil end
    if cap ~= nil and (type(cap) ~= 'number' or cap % 1 ~= 0 or cap < 0 or cap > 32 or cap > n) then
        return nil, 'maxBotsPerTeam must be an integer from 0 through min(32, maxPlayers)'
    end
    local settings = fields.serverSettings
    if settings == NULL or (settings ~= nil and type(settings) ~= 'table') then
        return nil, 'serverSettings must be an object'
    end
    local selected = {}
    for key, setting in pairs(settings or {}) do
        local spec = M.serverSpecs[key]
        if not spec then return nil, 'Unknown serverSettings key: ' .. key end
        if setting ~= NULL then
            if spec.kind == 'bool' then
                if type(setting) ~= 'boolean' then return nil, key .. ' must be true, false or null' end
            elseif type(setting) ~= 'number' or setting < spec.min or setting > spec.max or
                (spec.kind == 'int' and setting % 1 ~= 0) then
                return nil, key .. ' must be ' .. spec.kind .. ' in ' .. spec.min .. '-' .. spec.max .. ' or null'
            end
            selected[key] = setting
        end
    end
    return {maxPlayers=n, maxBotsPerTeam=cap, serverSettings=selected}
end

function M.parse(text)
    local fields, err = parseFields(text)
    if not fields then return nil, err end
    return fields.maxPlayers
end

function M.parseBotCap(text)
    local fields, err = parseFields(text)
    if not fields then return nil, err end
    if fields.maxBotsPerTeam == nil then return nil, 'maxBotsPerTeam is disabled (null or omitted)' end
    return fields.maxBotsPerTeam
end

function M.parseServerSettings(text)
    local fields, err = parseFields(text)
    if not fields then return nil, err end
    return fields.serverSettings
end

local function readText(path)
    local f, err = io.open(path, 'rb')
    if not f then return nil, err end
    local text = f:read(4097)
    f:close()
    if not text or #text > 4096 then return nil, 'Config empty or larger than 4096 bytes' end
    return text
end

function M.read(path)
    local text, err = readText(path)
    if not text then return nil, err end
    return M.parse(text)
end

function M.readBotCap(path)
    local text, err = readText(path)
    if not text then return nil, err end
    return M.parseBotCap(text)
end

function M.readServerSettings(path)
    local text, err = readText(path)
    if not text then return nil, err end
    return M.parseServerSettings(text)
end

return M
