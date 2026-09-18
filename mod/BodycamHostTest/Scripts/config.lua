local M = {}

-- Strict, flat JSON for the two numbers this experiment understands.
local function parseFields(text)
    local body = text:match('^%s*{%s*(.-)%s*}%s*$')
    if not body then return nil, 'Expected a JSON object' end
    local fields, count = {}, 0
    for item in (body .. ','):gmatch('(.-),') do
        local key, digits = item:match('^%s*"([%w]+)"%s*:%s*([0-9]+)%s*$')
        if not key or (key ~= 'maxPlayers' and key ~= 'maxBotsPerTeam') or
            fields[key] or (#digits > 1 and digits:sub(1, 1) == '0') then
            return nil, 'Expected maxPlayers and optional maxBotsPerTeam as unique integers'
        end
        fields[key], count = tonumber(digits), count + 1
    end
    if count < 1 or count > 2 or fields.maxPlayers == nil then
        return nil, 'maxPlayers is required'
    end
    if fields.maxPlayers < 2 or fields.maxPlayers > 64 then
        return nil, 'maxPlayers must be an integer from 2 through 64'
    end
    local cap = fields.maxBotsPerTeam
    if cap ~= nil and (cap < 0 or cap > 32 or cap > fields.maxPlayers) then
        return nil, 'maxBotsPerTeam must be an integer from 0 through min(32, maxPlayers)'
    end
    return fields
end

function M.parse(text)
    local fields, err = parseFields(text)
    if not fields then return nil, err end
    return fields.maxPlayers
end

function M.parseBotCap(text)
    local fields, err = parseFields(text)
    if not fields then return nil, err end
    if fields.maxBotsPerTeam == nil then return nil, 'maxBotsPerTeam is not configured' end
    return fields.maxBotsPerTeam
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

return M
