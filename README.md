# Bodycam Host Tool

A [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS) mod and development base for hosting larger Bodycam matches, inspecting bot behavior, and testing reflected server settings.

The player limit has worked with real players above Bodycam's default count. Bot limits and the additional server settings are experimental and have not all been validated across game modes or patches.

## Install

1. Close Bodycam and [download the current ZIP](release/BodycamHostTool-win64.zip?raw=1).
2. Extract the ZIP contents beside `Bodycam-Win64-Shipping.exe`, usually under `Bodycam\Binaries\Win64`.
3. Edit `ue4ss\Mods\BodycamHostTest\config.json`.

Already using UE4SS? Copy [mod/BodycamHostTest](mod/BodycamHostTest) into `ue4ss\Mods\` and enable `BodycamHostTest : 1` in `ue4ss\Mods\mods.txt`.

## Main settings

Most users only need the first section of `config.json`:

```json
{
  "playerAndBotLimits": {
    "maxPlayers": 24,
    "maxBotsPerTeam": 12
  }
}
```

### `maxPlayers`

Sets the requested maximum player capacity for the hosted match. Press **F9** after entering a hosted match to apply it. Values from 2 through 64 are accepted as a test range; 64 is not a guaranteed stable or officially supported player count.

### `maxBotsPerTeam`

Sets the experimental bot cap. In Team Deathmatch, `12` means up to 12 bots on each side. In free-for-all Deathmatch, it means 12 bots total. Press **F10** to apply it. Existing bots are not removed. Set the value to `null` and press F10 to disable and remove the bot hook when possible.

The remaining `experimentalServerSettings` can be left at `null`. Developers interested in those options should read [How the tool works](HOW-IT-WORKS.md#f11-experimental-server-settings) and the [server settings reference](SERVER_SETTINGS.md).

## Controls

| Key | Action |
| --- | --- |
| **F9** | Apply `maxPlayers` to the active hosted match. |
| **F10** | Apply the experimental bot cap. The default `12` means 12 bots per side in TDM. |

Advanced development controls, including F11 server settings and the F12 read-only bot probe, are documented in [HOW-IT-WORKS.md](HOW-IT-WORKS.md).

The older automatic bot-fill window was removed from the runtime. It changed gameplay capacity during prematch and could interfere with Bodycam's waiting phase, including repeated 30-second prerounds or freezes. Its source is retained in [research/fill_window_experimental.lua](research/fill_window_experimental.lua) for developers studying the approach.

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
