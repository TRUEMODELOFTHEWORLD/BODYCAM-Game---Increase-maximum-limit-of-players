-- F11: guarded, one-shot writes to reflected host match settings.
return function(api)
    local structs = {
        PhaseConfig='ScriptStruct /Script/Bodycam.PhaseConfig',
        ScoringConfig='ScriptStruct /Script/Bodycam.ScoringConfig',
        TeamConfig='ScriptStruct /Script/Bodycam.TeamConfig',
        LoadoutConfig='ScriptStruct /Script/Bodycam.LoadoutConfig'
    }
    local types = {float='FloatProperty', int='IntProperty', bool='BoolProperty'}

    local function matchValue(a, b)
        if type(a) == 'number' and type(b) == 'number' then return math.abs(a - b) < 0.001 end
        return a == b
    end

    local function findTarget(c, asset, key, spec)
        local typeName = types[spec.kind]
        if spec.group == 'GameState' then
            local field
            api.properties(c.gs:GetClass(), function(p)
                if api.name(p) == 'IntProperty /Game/GM/GT_Base.GT_Base_C:VoteMapTimerMax'
                    and api.isType(p, typeName) then field = p end
            end)
            if not field then return nil, 'GameState.VoteMapTimerMax reflection changed' end
            return {owner=c.gs, data=c.gs, field=key, label='GameState.' .. key}
        end
        if not api.valid(asset) or
            api.try(function() return asset:IsA('/Script/Bodycam.GameModeConfigDataAsset') end) ~= true then
            return nil, 'active GameModeConfigDataAsset unavailable'
        end
        local property = api.try(function() return asset:Reflection():GetProperty(spec.group) end)
        if not api.valid(property) or
            api.name(property) ~= 'StructProperty /Script/Bodycam.GameModeConfigDataAsset:' .. spec.group then
            return nil, spec.group .. ' reflection changed'
        end
        local struct = api.try(function() return property:GetStruct() end)
        if not api.valid(struct) or api.name(struct) ~= structs[spec.group] then
            return nil, spec.group .. ' struct changed'
        end
        local field
        struct:ForEachProperty(function(p)
            if api.name(p) == typeName .. ' /Script/Bodycam.' .. spec.group .. ':' .. key
                and api.isType(p, typeName) then field = p end
        end)
        if not field then return nil, spec.group .. '.' .. key .. ' reflection changed' end
        local data = api.try(function() return asset[spec.group] end)
        if not api.valid(data) then return nil, spec.group .. ' value unavailable' end
        return {owner=asset, data=data, group=spec.group, field=key,
            label=spec.group .. '.' .. key}
    end

    local function apply()
        api.log('=== F11 server settings experiment ===')
        local selected, err = api.readConfig()
        if not selected then api.log('F11 REFUSED: config: ' .. tostring(err)); return end
        local requested = 0
        for _ in pairs(selected) do requested = requested + 1 end
        if requested == 0 then
            api.log('F11: no serverSettings values enabled; null means skip')
            return
        end
        local c = api.context()
        if not c.host or not api.valid(c.gs) then
            api.log('F11 REFUSED: requires an active networked host match'); return
        end
        local asset = api.try(function() return c.gs.GameModeConfigDataAsset end)
        local planned = {}
        local preflightErrors = 0
        for _, key in ipairs(api.order) do
            if selected[key] ~= nil then
                local target, why = findTarget(c, asset, key, api.specs[key])
                if not target then
                    preflightErrors = preflightErrors + 1
                    api.log('F11 ' .. key .. ': REFUSED: ' .. tostring(why))
                else
                    target.value = selected[key]
                    target.before = api.try(function() return target.data[target.field] end)
                    if type(target.before) ~= type(target.value) then
                        preflightErrors = preflightErrors + 1
                        api.log('F11 ' .. target.label .. ': REFUSED: current value/type unavailable')
                    else
                        planned[#planned + 1] = target
                    end
                end
            end
        end
        if preflightErrors > 0 then
            api.log('F11 result: FAILED preflight; no server settings were written')
            return
        end
        local accepted = 0
        for _, target in ipairs(planned) do
            local ok, why = pcall(function() target.data[target.field] = target.value end)
            local after = api.try(function()
                if target.group then return target.owner[target.group][target.field] end
                return target.owner[target.field]
            end)
            local success = ok and matchValue(after, target.value)
            if success then accepted = accepted + 1 end
            api.log('F11 ' .. target.label .. ': ' .. tostring(target.before) .. ' -> ' ..
                tostring(after) .. '; immediate local write=' .. (success and 'SUCCESS' or 'FAILED') ..
                (why and ('; ' .. tostring(why)) or ''))
            if target.field == 'ScoreLimit' then
                api.log('F11 active GetScoreLimit()=' ..
                    tostring(api.try(function() return c.gs:GetScoreLimit() end)) ..
                    '; asset write does not call OverrideScoreLimit')
            elseif target.field == 'PhaseDuration' then
                api.log('F11 active GetPhaseDuration()=' ..
                    tostring(api.try(function() return c.gs:GetPhaseDuration() end)))
            end
        end
        api.log(string.format('F11 result: local writes accepted %d/%d; gameplay, replication and next-map persistence UNVERIFIED',
            accepted, #planned))
    end
    return apply
end
