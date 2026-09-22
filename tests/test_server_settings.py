"""Mock checks for the local F11 experiment; live Bodycam behavior is separate."""

from pathlib import Path
import unittest

from lupa.lua54 import LuaRuntime

SCRIPTS = Path(__file__).resolve().parents[1] / 'mod/BodycamHostTest/Scripts'

MOCK = r'''
logs = {}
local function named(n)
    return {GetFullName=function() return n end, IsValid=function() return true end}
end
local function field(n, kind)
    local p = named(n); p.kind = kind; return p
end
phaseValue = named('PhaseConfig value')
phaseValue.RespawnDelay = 2
scoreValue = named('ScoringConfig value')
scoreValue.ScoreLimit = 75
local phaseField = field('FloatProperty /Script/Bodycam.PhaseConfig:RespawnDelay', 'FloatProperty')
local scoreField = field('IntProperty /Script/Bodycam.ScoringConfig:ScoreLimit', 'IntProperty')
local function property(group, f)
    local p = named('StructProperty /Script/Bodycam.GameModeConfigDataAsset:' .. group)
    local s = named('ScriptStruct /Script/Bodycam.' .. group)
    s.ForEachProperty = function(_, cb) cb(f) end
    p.GetStruct = function() return s end
    return p
end
phaseProperty = property('PhaseConfig', phaseField)
scoreProperty = property('ScoringConfig', scoreField)
asset = named('GameModeConfigDataAsset /Game/Test')
asset.IsA = function() return true end
asset.PhaseConfig, asset.ScoringConfig = phaseValue, scoreValue
asset.Reflection = function()
    return {GetProperty=function(_, group)
        if group == 'PhaseConfig' then return phaseProperty end
        if group == 'ScoringConfig' then return scoreProperty end
    end}
end
local voteField = field('IntProperty /Game/GM/GT_Base.GT_Base_C:VoteMapTimerMax', 'IntProperty')
gs = named('GameState /Game/Test')
gs.GameModeConfigDataAsset, gs.VoteMapTimerMax = asset, 45
gs.GetClass = function()
    return {ForEachProperty=function(_, cb) cb(voteField) end}
end
gs.GetScoreLimit = function() return 75 end
gs.GetPhaseDuration = function() return 600 end
c = {host=true, gs=gs}
selected = {}
api = {
    log=function(s) logs[#logs+1] = s end,
    try=function(f) local ok, v = pcall(f); if ok then return v end end,
    valid=function(o) return o and type(o.IsValid)=='function' and o:IsValid() end,
    name=function(o) return o:GetFullName() end,
    isType=function(p, kind) return p.kind == kind end,
    properties=function(cls, cb) cls:ForEachProperty(cb) end,
    context=function() return c end,
    readConfig=function() return selected end
}
'''


class ServerSettingsTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.config = self.lua.execute('return dofile(...)', (SCRIPTS / 'config.lua').as_posix())
        self.lua.execute(MOCK)
        g = self.lua.globals()
        g.api.specs, g.api.order = self.config.serverSpecs, self.config.serverOrder
        self.apply = self.lua.execute('return dofile(...)', (SCRIPTS / 'server_settings.lua').as_posix())(g.api)
        self.g = g

    def logs(self):
        return '\n'.join(self.g.logs.values())

    def test_existing_two_settings_and_disabled_defaults(self):
        text = (SCRIPTS.parent / 'config.json').read_text()
        self.assertEqual(self.config.parse(text), 24)
        cap, reason = self.config.parseBotCap(text)
        self.assertIsNone(cap)
        self.assertIn('disabled', reason)
        self.assertEqual(len(self.config.parseServerSettings(text)), 0)
        self.apply()
        self.assertIn('no serverSettings values enabled', self.logs())

    def test_null_values_are_removed_before_runtime_apply(self):
        selected = self.config.parseServerSettings(
            '{"maxPlayers":24,"maxBotsPerTeam":null,"serverSettings":'
            '{"PhaseDuration":null,"WaitingForPlayersDuration":null,'
            '"RoundWarmupDuration":null,"RespawnDelay":null}}'
        )
        self.assertEqual(len(selected), 0)
        self.g.selected = selected
        self.apply()
        self.assertEqual(self.g.phaseValue.RespawnDelay, 2)
        self.assertIn('no serverSettings values enabled', self.logs())

    def test_only_explicit_values_apply(self):
        selected = self.config.parseServerSettings(
            '{"maxPlayers":50,"maxBotsPerTeam":4,"serverSettings":'
            '{"RespawnDelay":4.5,"ScoreLimit":150,"VoteMapTimerMax":90,"PhaseDuration":null}}'
        )
        self.g.selected = selected
        self.apply()
        self.assertEqual(self.g.phaseValue.RespawnDelay, 4.5)
        self.assertEqual(self.g.scoreValue.ScoreLimit, 150)
        self.assertEqual(self.g.gs.VoteMapTimerMax, 90)
        self.assertIn('local writes accepted 3/3', self.logs())
        self.assertIn('active GetScoreLimit()=75', self.logs())

    def test_bad_reflection_prevents_all_writes(self):
        self.g.selected = self.config.parseServerSettings(
            '{"maxPlayers":50,"serverSettings":{"RespawnDelay":4,"VoteMapTimerMax":90}}'
        )
        self.g.phaseProperty.GetFullName = lambda _: 'changed'
        self.apply()
        self.assertEqual(self.g.phaseValue.RespawnDelay, 2)
        self.assertEqual(self.g.gs.VoteMapTimerMax, 45)
        self.assertIn('FAILED preflight', self.logs())

    def test_nonhost_prevents_writes(self):
        self.g.selected = self.config.parseServerSettings(
            '{"maxPlayers":50,"serverSettings":{"RespawnDelay":4}}'
        )
        self.g.c.host = False
        self.apply()
        self.assertEqual(self.g.phaseValue.RespawnDelay, 2)
        self.assertIn('requires an active networked host', self.logs())

    def test_invalid_json_and_values_rejected(self):
        invalid = [
            '{}', '{"maxPlayers":1}', '{"maxPlayers":65}',
            '{"maxPlayers":50,"serverSettings":{"RespawnDelay":"fast"}}',
            '{"maxPlayers":50,"serverSettings":{"ScoreLimit":0}}',
            '{"maxPlayers":50,"serverSettings":{"MaxPhases":1.5}}',
            '{"maxPlayers":50,"serverSettings":{"Unknown":5}}',
            '{"maxPlayers":50,"serverSettings":{"RespawnDelay":3,"RespawnDelay":4}}',
            '{"maxPlayers":50,"serverSettings":null}',
            '{"maxPlayers":50,}',
        ]
        for text in invalid:
            with self.subTest(text=text):
                self.assertIsNone(self.config.parse(text)[0])


if __name__ == '__main__':
    unittest.main()
