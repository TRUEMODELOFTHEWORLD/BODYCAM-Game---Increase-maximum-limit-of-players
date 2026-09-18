"""Focused Lua regression for the TDM map-transition bot-fill window.

Run with `python -m unittest discover -s tests` after installing `lupa`.
This mock tests control flow; only a live Bodycam host can verify hook timing.
"""

from pathlib import Path
import unittest

from lupa.lua54 import LuaRuntime


SCRIPT = Path(__file__).resolve().parents[1] / "mod/BodycamHostTest/Scripts/fill_window.lua"

MOCK = r'''
logs = {}
local function named(n)
    return {IsValid=function() return true end, GetFullName=function() return n end}
end
local field = named('IntProperty /Script/Bodycam.TeamConfig:MaxPlayers')
local struct = named('ScriptStruct /Script/Bodycam.TeamConfig')
struct.ForEachProperty = function(_, cb) cb(field) end
local property = named('StructProperty /Script/Bodycam.GameModeConfigDataAsset:TeamConfig')
property.GetStruct = function() return struct end
team = named('TeamConfig value')
team.MaxPlayers = 50
local asset = named('GameModeConfigDataAsset /Game/Test.Asset')
asset.IsA = function() return true end
asset.Reflection = function() return {GetProperty=function() return property end} end
asset.TeamConfig = team
function makeContext(path, address, players, mode)
    local world = named(path)
    world.GetAddress = function() return address end
    local gm = named('GameMode ' .. path)
    gm.GetClass = function() return named(mode or 'BlueprintGeneratedClass /Game/GM/Gamemode/GM_TeamDeathMatch.GM_TeamDeathMatch_C') end
    return {host=true, world=world, gm=gm, gs={GameModeConfigDataAsset=asset,PlayerArray=players}}
end
function human() return {bIsABot=false} end
function bot() return {bIsABot=true} end
api = {
    log=function(s) logs[#logs+1]=s end,
    try=function(f) local ok, value = pcall(f); if ok then return value end end,
    valid=function(o) return o ~= nil and type(o.IsValid)=='function' and o:IsValid() end,
    name=function(o) return o and o:GetFullName() or 'NOT FOUND' end,
    isType=function(_, t) return t=='IntProperty' end,
    capEnabled=function() return true end,
}
'''


class NextMapTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(MOCK)
        self.mod = self.lua.execute('return dofile(...)', SCRIPT.as_posix())(self.lua.globals().api)
        self.g = self.lua.globals()

    def roster(self, humans, bots):
        return self.lua.table_from([self.g.human() for _ in range(humans)]
                                   + [self.g.bot() for _ in range(bots)])

    def test_lobby_does_not_consume_next_map_attempt(self):
        first = self.g.makeContext('World /Game/TDM.TDM', 1, self.roster(1, 49))
        lobby = self.g.makeContext('World /Game/Map/Lobby/Lobby.Lobby', 2, self.roster(1, 0), 'GM_Bodycam_C')
        self.assertTrue(self.mod.configure(first, 6, 50))
        self.mod.poll(lobby)
        next_map = self.g.makeContext('World /Game/NewTDM.NewTDM', 3, self.roster(0, 0))
        self.mod.poll(next_map, True)
        self.assertEqual(self.g.team.MaxPlayers, 50)
        next_map.gs.PlayerArray = self.roster(1, 0)
        self.mod.poll(next_map, True)
        self.assertEqual(self.g.team.MaxPlayers, 13)
        self.assertIn('next-map result: ACTIVE', '\n'.join(self.g.logs.values()))

    def test_repeated_map_name_uses_world_identity(self):
        first = self.g.makeContext('World /Game/TDM.TDM', 1, self.roster(1, 49))
        self.mod.configure(first, 6, 50)
        next_map = self.g.makeContext('World /Game/TDM.TDM', 2, self.roster(1, 0))
        self.mod.poll(next_map, True)
        self.assertEqual(self.g.team.MaxPlayers, 13)

    def test_early_map_change_restores_prior_window(self):
        first = self.g.makeContext('World /Game/TDM.TDM', 1, self.roster(1, 0))
        self.mod.configure(first, 6, 50)
        self.assertEqual(self.g.team.MaxPlayers, 13)
        next_map = self.g.makeContext('World /Game/NewTDM.NewTDM', 2, self.roster(2, 0))
        self.mod.poll(next_map, True)
        self.assertEqual(self.g.team.MaxPlayers, 14)
        self.assertIn('world-change restore: 13 -> 50 RESTORED', '\n'.join(self.g.logs.values()))

    def test_full_roster_reports_missed_window(self):
        first = self.g.makeContext('World /Game/TDM.TDM', 1, self.roster(1, 49))
        self.mod.configure(first, 6, 50)
        next_map = self.g.makeContext('World /Game/NewTDM.NewTDM', 2, self.roster(1, 49))
        self.mod.poll(next_map, True)
        self.assertEqual(self.g.team.MaxPlayers, 50)
        self.assertIn('next-map result: FAILED: initial fill window missed', '\n'.join(self.g.logs.values()))


if __name__ == '__main__':
    unittest.main()
