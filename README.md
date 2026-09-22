# Bodycam Host Tool

A [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS) mod and development base for hosting larger Bodycam matches, inspecting bot behavior, and testing reflected server settings.

The player limit has worked with real players above Bodycam's default count. Bot limits and the additional server settings are experimental and have not all been validated across game modes or patches.

## Install

1. Close Bodycam and [download the current ZIP](release/BodycamHostTool-win64.zip?raw=1).
2. Extract the ZIP contents beside `Bodycam-Win64-Shipping.exe`, usually under `Bodycam\Binaries\Win64`.
3. Edit `ue4ss\Mods\BodycamHostTest\config.json`.

Already using UE4SS? Copy [mod/BodycamHostTest](mod/BodycamHostTest) into `ue4ss\Mods\` and enable `BodycamHostTest : 1` in `ue4ss\Mods\mods.txt`.

## Safe default configuration

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

The two commonly used limits are grouped first under `playerAndBotLimits`. Less established options are kept separately under `experimentalServerSettings`.

`null` means disabled. Disabled values are removed while parsing and never reach the reflection writer. The shipped value is 12 bots per side in TDM; the hook still runs only after F10. Set it to null to disable it. Experimental server settings are written only when **F11** is pressed, and only fields with explicit non-null values are considered.

## Controls

| Key | Action |
| --- | --- |
| **F9** | Apply `maxPlayers` to the active hosted match. |
| **F10** | Apply the experimental bot cap. The default `12` means 12 bots per side in TDM. |
| **F11** | Apply only explicitly enabled `experimentalServerSettings`. |
| **F12** | Log a read-only snapshot of live bot difficulty candidates. |

`maxPlayers` accepts integers from 2 to 64 as a test guard. The highest stable game limit remains unknown. In free-for-all Deathmatch, F9 now preserves Bodycam's `TeamMaxSize` value instead of treating the match as two teams.

The older automatic bot-fill window was removed from the runtime. It changed gameplay capacity during prematch and could interfere with Bodycam's waiting phase, including repeated 30-second prerounds or freezes. Its source is retained in [research/fill_window_experimental.lua](research/fill_window_experimental.lua) for developers studying the approach.

## Experimental server settings

See [SERVER_SETTINGS.md](SERVER_SETTINGS.md) for fields, ranges, and test status. Most were discovered through reflection and still require live host/client validation. Test one setting at a time in a private match.

## Building on the project

The scripts use reflected names, type checks, host checks, guarded writes, and local readback logging. This makes the project useful as a base for other Bodycam modes and projects such as Trench, but reflected paths and behavior may differ after patches.

- `config.lua` parses configuration and removes disabled values.
- `server_settings.lua` performs an all-or-nothing reflection preflight before writing.
- `team_limit.lua` handles mode-aware gameplay capacity.
- `bot_probe.lua` contains the experimental bot decision hook.
- `difficulty_probe.lua` discovers live bot-related objects and fields without writing.

Read [HOW-IT-WORKS.md](HOW-IT-WORKS.md) for a deeper explanation of the runtime design. [TRENCH](https://github.com/0x0d4ddy/TRENCH) is another project built from this mod's groundwork.

Run `python -m unittest discover -s tests` before packaging. Live game behavior cannot be proven by mocked tests, so check `BodycamHostTest.log` after each private-match test.

UE4SS is included under its MIT license. See [THIRD-PARTY.md](THIRD-PARTY.md).

## Donations

BTC: `3FTzjsXen8HPhqT9RmqJJGtBNFkDsZNpcw`

ETH: `0xf1adc3c3d480847c0d3df1ad011ee2e7e340ff30`

XRP: `rHcXrn8joXL2Qe7BaMnhB5VRuj1XKEmUW6` (destination tag `253343087`)
