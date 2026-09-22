# Experimental server settings

Set individual fields under `serverSettings`, then press **F11** in an active hosted match. All fields default to `null`.

## Null behavior

`null` means disabled. The configuration parser omits null entries from the table passed to the runtime writer. When every field is null, F11 logs that no settings are enabled and returns before resolving game objects or writing anything.

These settings are never applied automatically. F11 first verifies every requested property, owning structure, and reflected type. If any requested field fails preflight, none of the requested fields are written.

## Fields

| JSON field | Input guard | Earlier observed value | Expected purpose |
| --- | --- | ---: | --- |
| `PhaseDuration` | 60–3600 | 600 | Match phase length, likely seconds |
| `bUseTimerForWaitingPlayers` | true/false | true | Waiting countdown toggle |
| `WaitingForPlayersDuration` | 0–300 | 30 | Waiting phase duration, likely seconds |
| `RoundWarmupDuration` | 0–120 | 6 | Round warmup duration |
| `EndRoundDuration` | 0–120 | 6 | Delay after a round |
| `RespawnDelay` | 0–60 | 2 | Respawn wait, likely seconds |
| `RemainingTimeToStartTimerSounds` | 0–30 | 5 | Countdown audio threshold |
| `ScoreLimit` | integer 1–500 | 75 | TDM kill target |
| `MaxPhases` | integer 1–20 | 1 | Phase count; meaning unclear |
| `TeamSwitchInterval` | integer 0–120 | 5 | Team switching timing; unit unknown |
| `GraceWindowDistance` | 0–5000 | 300 | Loadout grace distance; unit unknown |
| `GraceWindowDuration` | 0–120 | 30 | Loadout grace duration |
| `VoteMapTimerMax` | integer 5–300 | 45 | Possible map vote timer cap |

The guards prevent obviously invalid input; they are not verified Bodycam limits. Most fields were reflected from an earlier build and have not been fully tested for gameplay effect, replication, persistence, or compatibility with every mode.

`ScoreLimit` changes the asset field without calling the separate active score override. A successful immediate readback only proves that the local property accepted the value.

## Suggested test process

1. Use a private hosted match.
2. Enable one field and leave every other field null.
3. Press F11 once.
4. Observe the full round, map transition, and at least one connected client.
5. Review `ue4ss\Mods\BodycamHostTest\BodycamHostTest.log`.

Phase and waiting settings carry the most match-flow risk. Keep them null unless you are deliberately testing them.
