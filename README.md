# Bodycam Host Tool — player and bot limits

An experimental [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS) mod for the **host** of a Bodycam match. It lets the host try a configurable player limit and, in Team Deathmatch, limit the initial automatic bot fill. It was developed against Bodycam build `25228199`. Whether real players can join past Bodycam's normal lobby limit is **not yet verified**.

## Install

1. Close Bodycam. [Download `BodycamHostTool-win64.zip` from v0.1.1](https://github.com/TRUEMODELOFTHEWORLD/BODYCAM-Game---Increase-maximum-limit-of-players/releases/download/v0.1.1/BodycamHostTool-win64.zip) and extract its **contents** into `...\Steam\steamapps\common\Bodycam\Bodycam\Binaries\Win64\` — the folder containing `Bodycam-Win64-Shipping.exe`. The ZIP already contains UE4SS and the mod; do not create an extra `BodycamHostTool` folder. After extraction, `dwmapi.dll` should sit beside the game EXE, and `ue4ss\UE4SS.dll` should exist.
2. Edit `Win64\ue4ss\Mods\BodycamHostTest\config.json`:

   ```json
   {
     "maxPlayers": 24,
     "maxBotsPerTeam": 6
   }
   ```

   `maxPlayers` accepts whole numbers **2–64**. This is a test guard, not a proven game capacity. `maxBotsPerTeam` accepts **0–32** and cannot exceed `maxPlayers`.
3. Start Bodycam and host a match. UE4SS should load the mod automatically. Check `Win64\ue4ss\Mods\BodycamHostTest\BodycamHostTest.log` for `[BodycamHost] ... loaded`. If that file is missing, check `Win64\ue4ss\UE4SS.log` for a loading error.

If you already have UE4SS or other mods, back up your current `ue4ss` folder first. Copy the [BodycamHostTest source folder](mod/BodycamHostTest) into your existing `ue4ss\Mods` and add `BodycamHostTest : 1` to your existing `ue4ss\Mods\mods.txt`; keep your existing UE4SS runtime and mod list. If another mod uses F10, resolve that key conflict before testing the bot cap.

When upgrading from v0.1.0, fully close Bodycam before replacing the old scripts. A full game restart clears the old key bindings and bot hook.

## Use

Host a match and press **F9 once** to load `maxPlayers`. The mod automatically loads `maxBotsPerTeam` when it detects a hosted match (normally within five seconds). It arms the Team Deathmatch initial-fill limit for the next map if the current map already has too many bots.

There are only two mod keys:

| Key | Action |
| --- | --- |
| **F9** | Load or reload `maxPlayers` into the reflected gameplay and host/session fields. |
| **F10** | Load or reload `maxBotsPerTeam` and arm the Team Deathmatch initial-fill limit. It does **not** toggle the cap off. |

After editing the config, press F9 if you changed `maxPlayers`, or F10 if you changed `maxBotsPerTeam`; you do **not** need to restart the mod. To **lower** an already active player limit, start a fresh hosted match first. Existing bots are **not** removed immediately. On a TDM map fill, the mod temporarily lowers gameplay capacity to limit the initial bots, then restores the configured player limit after at most 35 seconds. In free-for-all Deathmatch, `maxBotsPerTeam` acts as a **total** bot-decision cap; the temporary initial-fill limit is TDM only.

Observed with the earlier four-key version in a hosted TDM test: with `maxPlayers=50` and `maxBotsPerTeam=6`, two map fills reached **12 bots, six per team**, and the gameplay capacity field was restored to 50. The new automatic two-key flow passes local Lua tests but still needs an in-game map-fill check. This does **not** prove 50 human slots, backend lobby advertisement, or joins past the normal limit. If a test fails, share the relevant `[BodycamHost]` lines from `BodycamHostTest.log` (remove player names before posting).

UE4SS is included under its own MIT license in `ue4ss\LICENSE`. See [third-party details](THIRD-PARTY.md). This project is independent of Bodycam and UE4SS.
