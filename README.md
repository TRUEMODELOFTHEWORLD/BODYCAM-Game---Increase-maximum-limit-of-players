# Bodycam Host Tool — player and bot limits

An experimental [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS) mod for the **host** of a Bodycam match. It lets the host try a configurable player limit and, in Team Deathmatch, limit the initial automatic bot fill. It was developed against Bodycam build `25228199`. Whether real players can join past Bodycam's normal lobby limit is **not yet verified**.

## Install

1. Close Bodycam. [Download `BodycamHostTool-win64.zip` from v0.1.0](https://github.com/TRUEMODELOFTHEWORLD/BODYCAM-Game---Increase-maximum-limit-of-players/releases/download/v0.1.0/BodycamHostTool-win64.zip) and extract its **contents** into `...\Steam\steamapps\common\Bodycam\Bodycam\Binaries\Win64\` — the folder containing `Bodycam-Win64-Shipping.exe`. The ZIP already contains UE4SS and the mod; do not create an extra `BodycamHostTool` folder. After extraction, `dwmapi.dll` should sit beside the game EXE, and `ue4ss\UE4SS.dll` should exist.
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

## Keys while hosting

| Key | Action |
| --- | --- |
| **F4** | Apply `maxPlayers` to the active TeamConfig gameplay fields. |
| **F9** | Try the other reflected host/session capacity fields and log each result. |
| **F10** | Toggle the automatic bot decision cap from `maxBotsPerTeam`. |
| **F2** | Toggle the **Team Deathmatch** initial-fill window. When armed, it briefly lowers gameplay capacity on each new map, then restores `maxPlayers` after at most 35 seconds. |
| **F3** | Log the current human/bot roster and team counts without changing anything. |
| **F8** | Log capacity diagnostics without changing anything. |
| **F1** | Toggle the bot decision watch. When it is active, F1 stops the hook and turns off its cap; do this before **Restart All Mods**. |

For a new Team Deathmatch host, press **F4 → F9 → F10 → F2** once the match is live. If the current map has already filled with bots, F2 arms the test for the **next** map. After teams form, wait about 35 seconds and press **F3** to check the roster. Each key is a separate press; pressing F10 or F2 again turns that feature off. After changing `config.json`, turn F2 off if armed, press **F1** if the bot decision watch is active, use UE4SS **Restart All Mods**, then apply the keys again. To **lower** an already active player limit, start a fresh hosted match first; F4 intentionally refuses to shrink a live match.

The F10 decision cap can also be tested in free-for-all Deathmatch, where `maxBotsPerTeam` acts as a **total** bot cap; the F2 initial-fill window is **TDM only**. Bots already present are not removed. The bot cap depends on Bodycam's future spawn decisions and is experimental.

Observed in a hosted TDM test: with `maxPlayers=50` and `maxBotsPerTeam=6`, two map fills reached **12 bots, six per team**, and the gameplay capacity field was restored to 50. This does **not** prove 50 human slots, backend lobby advertisement, or joins past the normal limit. If a test fails, share the relevant `[BodycamHost]` lines from `BodycamHostTest.log` (remove player names before posting).

UE4SS is included under its own MIT license in `ue4ss\LICENSE`. See [third-party details](THIRD-PARTY.md). This project is independent of Bodycam and UE4SS.
