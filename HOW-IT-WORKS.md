# How the BODYCAM Host Tool Works

This document describes revision 4.0 of the UE4SS mod: what runs automatically, what each hotkey changes, how disabled settings are handled, and which results remain experimental.

## Runtime overview

```text
BODYCAM
  -> Unreal Engine runtime objects
  -> UE4SS reflection and hooks
  -> BodycamHostTest Lua scripts
       -> F9  player capacity
       -> F10 experimental bot cap
       -> F11 experimental server settings
       -> F12 read-only bot discovery
```

The mod does not patch the BODYCAM executable or replace original game assets. It finds live Unreal objects and reflected properties while the host is running.

## Safe defaults and null semantics

The shipped configuration keeps optional behavior disabled:

```json
{
  "playerAndBotLimits": {
    "maxPlayers": 24,
    "maxBotsPerTeam": 12
  },
  "experimentalServerSettings": {
    "PhaseDuration": null,
    "bUseTimerForWaitingPlayers": null,
    "WaitingForPlayersDuration": null,
    "RoundWarmupDuration": null,
    "EndRoundDuration": null,
    "RespawnDelay": null,
    "RemainingTimeToStartTimerSounds": null,
    "ScoreLimit": null,
    "MaxPhases": null,
    "TeamSwitchInterval": null,
    "GraceWindowDistance": null,
    "GraceWindowDuration": null,
    "VoteMapTimerMax": null
  }
}
```

`null` means disabled. This is enforced in `config.lua`, before a value reaches gameplay code:

```text
Read config.json
  -> validate keys and types
  -> discard null optional values
  -> return only explicitly enabled settings
```

Consequences:

- A null server setting is absent from the table passed to `server_settings.lua`.
- If every server setting is null, F11 returns before resolving or writing game properties.
- The shipped value `maxBotsPerTeam: 12` means a cap of 12 bots on team 0 and 12 bots on team 1 in TDM. The hook is installed only after F10. A null value keeps it disabled.
- Optional settings are never applied automatically.

Tests cover the null configuration path and confirm that the mocked game values remain unchanged.

The parser also accepts the earlier flat `maxPlayers`, `maxBotsPerTeam`, and `serverSettings` layout for compatibility. New configurations use the grouped layout so the two primary limits remain obvious at the top.

## Host authority check

Writes require an authoritative multiplayer host:

```text
AuthorityGameMode exists
IsServer == true
IsStandalone == false
```

Clients, menus, and standalone worlds do not qualify. The scripts also dispatch mutations onto the game thread and wrap risky operations with guarded calls.

## F9: player capacity

BODYCAM uses multiple capacity values. Changing one displayed number is insufficient, so F9 tries to synchronize several verified runtime layers:

```text
GameModeConfigDataAsset.TeamConfig.MaxPlayers
BodycamGameState.MaxPlayers
Bodycam GameInstance "Session Max Players"
GameSession.MaxPlayers
Other exact allowlisted capacity fields found on inspected objects
```

The flow is:

```text
Read maxPlayers
  -> confirm host
  -> locate expected objects
  -> verify reflected property names and types
  -> read existing values
  -> write capacity values
  -> perform immediate and delayed readbacks
  -> log retained or overwritten values
```

The accepted configuration range of 2 through 64 is an input guard. It is not a claim that 64 players are supported or stable.

### Team size handling

For Team Deathmatch, `TeamMaxSize` is raised to approximately half of `maxPlayers`:

```text
maxPlayers = 40
TeamMaxSize = 20
```

For free-for-all Deathmatch, revision 4.0 preserves BODYCAM's existing `TeamMaxSize`, normally 1. An earlier build changed it as though Deathmatch had two teams. Live logs showed it changing from 1 to 30, which was unrelated to FFA capacity and was a plausible contributor to unstable prematch flow.

## F10: experimental bot cap

The bot limiter targets the reflected Blueprint function:

```text
/Game/GM/Gamemode/BP_BodycamGameModeAbstract
  -> ShouldSpawnBots
```

When explicitly enabled, its hook:

1. Confirms the callback belongs to the authoritative game mode.
2. Counts bots from `GameState.PlayerArray`.
3. Counts team membership for TDM.
4. Blocks a future spawn decision after the configured cap is reached.

It does not delete existing bots. In TDM, the configured number is treated as a per-team cap. In free-for-all Deathmatch, it is treated as a total cap.

The hook is experimental because BODYCAM may expect bot filling to complete before advancing its waiting phase. The shipped value is 12, meaning 12 bots per side in TDM. The host must still press F10 to install the experimental hook. Setting `maxBotsPerTeam` to null and pressing F10 disables the cap and removes an existing hook when possible.

### Removed automatic fill window

An older implementation temporarily lowered `TeamConfig.MaxPlayers` during initial TDM bot fill, registered early lifecycle callbacks, and polled the match every 100 ms. The game sometimes froze or repeated its 30-second prematch while that system was active.

Revision 4.0 removes that module from the runtime and release ZIP. It no longer:

- changes gameplay capacity during bot fill;
- installs early `InitGameState` or `BeginPlay` fill callbacks;
- runs the 100 ms fill-window polling loop;
- enables the bot cap automatically when a host is detected.

The old implementation is retained only at `research/fill_window_experimental.lua` for developers who want to study it.

## F11: experimental server settings

F11 applies only non-null fields under `experimentalServerSettings`. These include phase timing, respawn timing, scoring, team switching, loadout grace values, and the possible map vote timer.

F11 uses an all-or-nothing preflight:

```text
Read enabled fields
  -> require active networked host
  -> locate the active GameModeConfigDataAsset or GameState
  -> verify every property name, owner structure, and Unreal type
  -> if any requested field fails, write nothing
  -> otherwise write requested values and read them back
```

The reflected structures include:

- `PhaseConfig`
- `ScoringConfig`
- `TeamConfig`
- `LoadoutConfig`
- `GT_Base_C.VoteMapTimerMax`

Most of these fields have not been fully tested. A successful local readback does not prove gameplay effect, client replication, persistence across travel, or safety in every game mode. Phase and waiting settings have the highest match-flow risk and should remain null unless they are being tested individually.

See [SERVER_SETTINGS.md](SERVER_SETTINGS.md) for the current fields and input guards.

## F12: read-only bot difficulty discovery

F12 does not change gameplay. It inspects live objects and logs reflected fields and functions whose names relate to:

```text
bot, accuracy, aim, skill, reaction, perception,
sight, hearing, fire, spread, recoil, target,
detection, range, vision, movement, speed
```

It examines the GameInstance, GameMode, GameState, live `AI_Humanoid_C` instances, AI controllers, perception components, and sight configuration objects.

This probe exists to help build patch-resistant bot difficulty features. Earlier inspection found names such as `GetBotsAccuracy`, `CurrentAccuracy`, `BotSkillThreshold`, `BotsAim`, and `UpdateBotAccuracy`. Those names are discovery leads; they are not yet confirmed writable difficulty controls.

## Reflection and write guards

The mod prefers reflection over hardcoded memory offsets. Before a guarded write, it checks details such as:

- exact reflected property path;
- expected Unreal property type;
- expected owning class or structure;
- valid live object;
- authoritative world;
- reasonable current value and configured range.

This improves patch resilience, but reflected names and behavior can still change after a BODYCAM update.

## Readback and logging

Immediate readback answers whether the local property accepted a value. Delayed readback helps identify values that BODYCAM later resets during session creation or map travel.

Logs are written to:

```text
ue4ss/Mods/BodycamHostTest/BodycamHostTest.log
```

Readback has limits. A locally retained value does not prove that Steam or EOS advertises the same capacity, that joining clients are admitted, or that replicated gameplay remains stable.

## Source layout

| File | Purpose |
| --- | --- |
| `Scripts/main.lua` | Host discovery, F9 capacity writes, hotkeys, polling, and logging |
| `Scripts/config.lua` | Strict JSON parsing, validation, and null filtering |
| `Scripts/team_limit.lua` | Mode-aware `TeamConfig` capacity handling |
| `Scripts/bot_probe.lua` | Bot inspection and the explicit experimental spawn hook |
| `Scripts/server_settings.lua` | F11 preflight and guarded one-shot setting writes |
| `Scripts/difficulty_probe.lua` | F12 read-only bot difficulty discovery |
| `research/fill_window_experimental.lua` | Removed prematch fill-window experiment |

## Demonstrated and unproven behavior

Demonstrated in earlier live testing:

- reflected player capacity values can accept host-side writes;
- capacity values can retain writes locally;
- human players have joined beyond BODYCAM's default player count;
- the bot decision function can be found and intercepted;
- host checks prevent writes in non-host contexts.

Not yet proven:

- a stable maximum player count;
- Steam or EOS lobby advertisement at every configured size;
- reliable join admission at high populations;
- replication, CPU, bandwidth, spawn, scoreboard, and UI behavior at scale;
- full gameplay behavior of every F11 setting;
- a stable writable bot difficulty property;
- bot cap compatibility with every game mode and future patch.

The automatic TDM fill window is specifically not considered demonstrated functionality. It was removed because its runtime behavior correlated with freezes and repeated prematch cycles.

## Building other mods from this project

The reusable pattern is:

```text
observe -> reflect -> validate -> change one thing -> read back -> test live -> document
```

Projects such as [TRENCH](https://github.com/0x0d4ddy/TRENCH) can reuse the host checks, reflection helpers, configuration parser, and logging approach. A derived mod should keep mode-specific behavior separate and should avoid assuming that a property with a promising name controls the entire multiplayer system.

## Testing reports

Useful reports include:

- BODYCAM build and UE4SS version;
- map and game mode;
- configured player and bot values;
- actual human and bot population;
- whether the match advanced beyond prematch;
- whether map travel and late joins worked;
- crashes, freezes, UI issues, and performance;
- relevant `BodycamHostTest.log` output.

The project remains an experimental host-capacity and runtime research tool. Each BODYCAM patch may require reflected paths and assumptions to be checked again.
