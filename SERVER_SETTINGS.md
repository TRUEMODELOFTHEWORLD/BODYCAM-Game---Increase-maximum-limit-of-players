# Local server-settings experiment

This file and the F11 experiment are local only; they have not been pushed to GitHub.

Edit `ue4ss/Mods/BodycamHostTest/config.json` in your Bodycam installation. The first two settings stay at the top:

- `maxPlayers`: load with **F9**.
- `maxBotsPerTeam`: loads automatically when hosting; refresh with **F10**.
- `serverSettings`: set one or more fields to a value, then press **F11** in a hosted match.

`null` means **skip**. F11 does not change the player or bot limits. It checks reflected types and logs every immediate write in `BodycamHostTest.log`. A successful write is not proof that gameplay or other clients accepted it. Start with **one field at a time**. Values below are conservative input guards, not Bodycam's proven limits.

| JSON field under `serverSettings` | Test guard | Earlier TDM value | Likely effect |
| --- | --- | ---: | --- |
| `PhaseDuration` | 60–3600 | 600 | Match phase length, likely seconds |
| `bUseTimerForWaitingPlayers` | true/false | true | Waiting countdown toggle |
| `WaitingForPlayersDuration` | 0–300 | 30 | Waiting phase, likely seconds |
| `RoundWarmupDuration` | 0–120 | 6 | Round warmup, likely seconds |
| `EndRoundDuration` | 0–120 | 6 | Delay after a round, likely seconds |
| `RespawnDelay` | 0–60 | 2 | Respawn wait, likely seconds |
| `RemainingTimeToStartTimerSounds` | 0–30 | 5 | Countdown audio threshold |
| `ScoreLimit` | integer 1–500 | 75 | TDM kill target |
| `MaxPhases` | integer 1–20 | 1 | Phase count; meaning unclear |
| `TeamSwitchInterval` | integer 0–120 | 5 | Team-switch timing; unit unknown |
| `GraceWindowDistance` | 0–5000 | 300 | Loadout grace distance; unit unknown |
| `GraceWindowDuration` | 0–120 | 30 | Loadout grace time, likely seconds |
| `VoteMapTimerMax` | integer 5–300 | 45 | Possible map-vote timer cap |

These values were reflected in a prior Bodycam build. F11 verifies each field against the running build before writing. `ScoreLimit` writes only the asset field; it does **not** invoke the separate active-score override, which caused uncertainty in an earlier test. For match-start settings, press F11 before a new map and check whether the value survives travel.

Example: set `"RespawnDelay": 4`, leave the other fields `null`, press F11, then measure one respawn with another client.
