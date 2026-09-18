# Bodycam Host Tool

A [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS) mod for Bodycam hosts to set a player limit and limit automatic bots. Human players have joined hosted matches beyond Bodycam's default player count; the highest working limit is still unknown.

## Install

1. Close Bodycam and [download the v0.1.1 ZIP](https://github.com/TRUEMODELOFTHEWORLD/BODYCAM-Game---Increase-maximum-limit-of-players/releases/download/v0.1.1/BodycamHostTool-win64.zip).
2. Extract the ZIP's **contents** into the folder containing `Bodycam-Win64-Shipping.exe` (usually `...\Steam\steamapps\common\Bodycam\Bodycam\Binaries\Win64\`). UE4SS and the mod are included.
3. Edit `ue4ss\Mods\BodycamHostTest\config.json`:

   ```json
   {
     "maxPlayers": 24,
     "maxBotsPerTeam": 6
   }
   ```

`maxPlayers` accepts whole numbers from **2 to 64**. This is a test guard, not a proven game limit. `maxBotsPerTeam` accepts **0 to 32** and cannot exceed `maxPlayers`.

Already have UE4SS? Copy only the [BodycamHostTest mod folder](mod/BodycamHostTest) into `ue4ss\Mods\` and add `BodycamHostTest : 1` to your existing `ue4ss\Mods\mods.txt`.

## Use

Host a match and press **F9 once** to load `maxPlayers`. The configured bot limit loads automatically when you host.

| Key | What it does |
| --- | --- |
| **F9** | Load or reload `maxPlayers`. |
| **F10** | Reload `maxBotsPerTeam` after editing the config. It does not turn the bot limit off. |

In Team Deathmatch, `maxBotsPerTeam` is per team. In free-for-all Deathmatch, it caps future bot-spawn decisions across the match. Bots already in a match are not removed; check the next map after changing the bot limit. Team Deathmatch may briefly reduce available slots during the initial bot fill, then restore the configured player limit.

To lower a player limit already active in a match, start a new hosted match and press F9. If the mod does not load, check `ue4ss\Mods\BodycamHostTest\BodycamHostTest.log` and `ue4ss\UE4SS.log`.

UE4SS is included under its own MIT license. See [third-party details](THIRD-PARTY.md).
