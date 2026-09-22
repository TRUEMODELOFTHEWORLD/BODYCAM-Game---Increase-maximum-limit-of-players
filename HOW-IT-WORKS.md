# How the BODYCAM Player Limit Mod Works

This document explains what the mod actually changes, how it interacts with BODYCAM, and what has — and has not — been proven through testing.

The short version:

```text
BODYCAM
   │
   ▼
Unreal Engine Runtime
   │
   ▼
UE4SS
   │
   ▼
Lua Mod
   │
   ├── Gameplay player limits
   ├── Team size limits
   ├── GameState / GameInstance limits
   ├── Session-related capacity values
   └── Bot spawning control
```

The mod does **not** permanently patch the BODYCAM executable or modify BODYCAM's original game files.

Instead, it uses **UE4SS** to interact with Unreal Engine objects while the game is running.

---

# The Basic Idea

BODYCAM does not appear to use one single value for its multiplayer limit.

Increasing the maximum number of players therefore requires changing several related values in the running game.

For example, setting:

```json
{
  "maxPlayers": 40,
  "maxBotsPerTeam": null
}
```

does more than simply make the UI display `40`.

The mod identifies and changes several real gameplay and session-related values used by BODYCAM.

---

# Host Authority Check

Before modifying anything, the mod verifies that the local game instance is actually acting as the authoritative multiplayer host.

Conceptually:

```text
World
 │
 ├── AuthorityGameMode exists
 │
 ├── IsServer == true
 │
 └── IsStandalone == false
 │
 ▼
Confirmed multiplayer host
```

If these conditions are not satisfied, the mod refuses to perform the player-limit writes.

This prevents the mod from blindly modifying unrelated game worlds, menus, clients, or standalone instances.

---

# Gameplay Player Limit

One of the important discoveries was BODYCAM's:

```text
GameModeConfigDataAsset
    │
    └── TeamConfig
          │
          ├── MaxPlayers
          └── TeamMaxSize
```

The mod accesses these through Unreal Engine reflection.

For a configured maximum of:

```text
40 players
```

the mod sets approximately:

```text
TeamConfig.MaxPlayers  = 40
TeamConfig.TeamMaxSize = 20  (two-team modes only)
```

For a normal two-team mode:

```text
40 total players
     │
     ├── Team 1: up to 20
     └── Team 2: up to 20
```

In free-for-all Deathmatch, the mod preserves the game's existing `TeamMaxSize` (normally 1). Changing it as though Deathmatch had two teams was linked to unstable prematch behavior.

This is a real gameplay configuration structure used by BODYCAM.

---

# Multiple Player Limits Exist

Changing `TeamConfig.MaxPlayers` alone is not enough.

During development, additional player-capacity values were discovered in BODYCAM's runtime objects.

These include values associated with:

```text
GameMode
GameState
GameInstance
Session
Lobby / Settings objects
Team configuration
```

Known capacity-related properties include names such as:

```text
MaxPlayers
NumPublicConnections
PublicConnections
```

BODYCAM-specific reflected properties were also discovered, including values corresponding to:

```text
BodycamGI_C
└── Session Max Players

BodycamGameState
└── MaxPlayers
```

The mod therefore attempts to keep the relevant capacity values synchronized.

Conceptually:

```text
                    maxPlayers = 40
                           │
              ┌────────────┼────────────┐
              │            │            │
              ▼            ▼            ▼

        Gameplay        GameInstance    GameState

        MaxPlayers      Session Max     MaxPlayers
            40          Players = 40       40

        TeamMaxSize
            20
```

Additional recognized session/lobby capacity properties can also be updated when suitable reflected objects are found.

---

# Reflection Instead of Hardcoded Memory Addresses

An important design decision in this project is the use of **Unreal Engine reflection** wherever possible.

The mod does not rely on fixed addresses such as:

```text
BODYCAM.exe + 0x12345678
```

Those addresses can easily change when the game updates.

Instead, the mod attempts to identify Unreal classes, objects, functions, and properties by their reflected information.

Conceptually:

```text
Find the object
      │
      ▼
Find the property
      │
      ▼
Verify its Unreal type
      │
      ▼
Verify that it belongs to the expected BODYCAM class
      │
      ▼
Read current value
      │
      ▼
Write new value
      │
      ▼
Read it back
```

For example, before modifying an important value, the mod can verify that it really is the expected Unreal property rather than blindly writing into memory.

This makes experimentation considerably safer and more resilient to changes than relying entirely on hardcoded offsets.

---

# Readback Verification

The mod does not simply assume that a write succeeded.

After changing a value, it reads the property again.

Conceptually:

```text
Before: 10

Write:  40

After:  40

Result: SUCCESS
```

Delayed readbacks are also performed.

This is important because games frequently reconstruct objects, reset settings, or overwrite configuration values during events such as:

```text
Map changes
Round changes
Session creation
GameMode recreation
Lobby transitions
```

A value successfully becoming `40` for one frame does not necessarily mean it will remain `40`.

The readback system helps determine whether BODYCAM accepted and retained the modification.

---

# Bot Control Is a Separate System

Increasing player capacity creates another problem.

If BODYCAM sees many empty player positions, its normal bot-fill system may attempt to fill those positions with bots.

For example:

```text
Maximum players: 40
Humans connected: 1

Potential empty positions: 39
```

That is undesirable if the goal is to leave those positions available for real players.

The mod therefore has a separate bot-control system.

---

# ShouldSpawnBots Hook

BODYCAM contains a Blueprint function associated with deciding whether additional bots should spawn.

The mod hooks:

```text
BP_BodycamGameModeAbstract_C
└── ShouldSpawnBots
```

Conceptually, BODYCAM asks:

```text
Should another bot spawn?
```

The mod can then evaluate the current bot population:

```text
BODYCAM
   │
   ▼
ShouldSpawnBots()
   │
   ▼
UE4SS Lua Hook
   │
   ├── Count bots
   ├── Determine game mode
   ├── Count Team 1 bots
   ├── Count Team 2 bots
   │
   ▼
Configured bot limit reached?
   │
   ├── YES → prevent additional spawn
   │
   └── NO  → allow normal BODYCAM logic
```

For example:

```json
{
  "maxPlayers": 40,
  "maxBotsPerTeam": 6
}
```

can allow a 40-player gameplay capacity while preventing BODYCAM from immediately filling all of the unused positions with bots.

The system prevents future bot spawns above the configured limit.

It does not simply delete existing bots.

---

# Initial TDM Bot Fill

An earlier version temporarily lowered `TeamConfig.MaxPlayers` during initial bot fill and polled the match every 100 ms. Live testing associated that approach with freezes and repeated 30-second prematch cycles.

Revision 4.0 removes the fill window from the runtime. The old implementation remains in `research/fill_window_experimental.lua` for study, but it is not packaged as an active mod script.

Bot limiting is now manual and experimental. The safe default is:

```json
"maxBotsPerTeam": null
```

With that value, no bot hook is installed.

---

# F9

`F9` performs the primary player-limit operation.

Conceptually:

```text
Read configured maximum
          │
          ▼
Verify authoritative host
          │
          ▼
Find relevant BODYCAM objects
          │
          ▼
Verify reflected properties
          │
          ▼
Modify gameplay configuration
          │
          ├── MaxPlayers
          └── TeamMaxSize
          │
          ▼
Modify discovered session /
GameInstance / GameState values
          │
          ▼
Read everything back
          │
          ▼
Report success / failure /
retention information
```

---

# F10

`F10` is primarily associated with the bot-control configuration.

Conceptually:

```text
Read bot configuration
        │
        ▼
Apply / refresh bot limit
        │
        ▼
ShouldSpawnBots hook
        │
        ▼
Prevent future bot spawning
above the configured limit
```

The bot hook is not initialized automatically. `maxBotsPerTeam` must contain an integer and the host must press F10. Setting it to `null` and pressing F10 disables and removes an existing hook.

---

# What UE4SS Provides

UE4SS is the bridge between the Lua mod and BODYCAM's Unreal Engine runtime.

It allows Lua code to interact with things such as:

```text
Unreal objects
Unreal classes
Properties
Functions
Blueprint functions
Hooks
Keybinds
Game-thread execution
```

This is why the project does not require BODYCAM's original source code.

The architecture is roughly:

```text
                     BODYCAM
                        │
                        ▼
              Unreal Engine runtime
                        │
                        ▼
                      UE4SS
                        │
                        ▼
                 BodycamHostTest
                        │
             ┌──────────┴──────────┐
             │                     │
             ▼                     ▼
       Player Capacity         Bot Control
             │                     │
             ▼                     ▼
        MaxPlayers           ShouldSpawnBots
        TeamMaxSize              hook
        GameState
        GameInstance
        Session values
```

---

# What Has Been Demonstrated

The project has demonstrated that a BODYCAM host can modify real runtime values controlling multiplayer capacity.

This includes important gameplay and session-related structures rather than merely changing a displayed lobby number.

The project has also successfully allowed human players to join hosted matches beyond BODYCAM's normal/default player count during testing.

That is an important distinction.

This is not simply:

```text
UI says 40 players
```

The project changes actual runtime structures involved in player and team capacity.

---

# What Has NOT Yet Been Proven

The configured upper boundary should **not** be interpreted as BODYCAM's proven maximum supported player count.

For example, if the configuration accepts:

```text
2 - 64 players
```

that does **not** mean:

```text
64 players are officially supported
```

or even:

```text
64 players are proven stable
```

The upper value is currently an experimental/test guard.

Several layers still require investigation.

```text
[✓] Gameplay MaxPlayers

[✓] TeamMaxSize

[✓] GameInstance/session-related capacity values

[✓] GameState MaxPlayers

[✓] Additional reflected capacity properties

[✓] Host-authority verification

[✓] Bot-spawn interception

[✓] TDM initial-fill handling


[?] Online-session creation arguments

[?] EOS / Steam advertised lobby capacity

[?] Join admission at much larger player counts

[?] Replication scaling

[?] Scoreboard/UI behavior

[?] Spawn-point behavior

[?] 20v20 / 30v30 / larger gameplay stability

[?] Network bandwidth requirements

[?] CPU performance at high populations

[?] BODYCAM's actual hard maximum
```

That distinction is important.

This project should currently be considered an **experimental host-capacity override and research project**, rather than a claim that BODYCAM officially supports any particular large player count.

---

# The Next Important Layer

One especially interesting area for future research is BODYCAM's actual online-session creation process.

The current mod can identify and modify numerous runtime capacity values.

A stronger implementation may eventually intercept the moment BODYCAM creates or updates its online session.

Conceptually, the game may perform something similar to:

```text
CreateSession
    │
    └── NumPublicConnections = 10
```

The ideal experiment would be to identify that operation and modify the value before the online subsystem receives it:

```text
CreateSession
    │
    └── NumPublicConnections = 40
```

That would help determine whether Steam/EOS/session advertisement represents another independent player-count restriction.

The complete chain being investigated is therefore:

```text
Gameplay configuration
        │
        ▼
GameMode / GameState
        │
        ▼
GameInstance
        │
        ▼
Online session creation
        │
        ▼
Steam / EOS lobby
        │
        ▼
Joining client
        │
        ▼
Player admission
        │
        ▼
Replication
        │
        ▼
Actual gameplay
```

The long-term goal is not to assume where BODYCAM's real maximum exists.

The goal is to experimentally identify **every layer in the chain and determine which one becomes the first actual bottleneck**.

---

# Why This Project Is Useful

Even beyond increasing the player count, the project demonstrates a useful approach to researching Unreal Engine games:

```text
Observe
  ↓
Reflect
  ↓
Verify
  ↓
Modify
  ↓
Read back
  ↓
Test
  ↓
Document
```

Instead of assuming that a particular variable controls a feature, the project attempts to discover BODYCAM's actual runtime structures and verify their behavior experimentally.

That work can also serve as a foundation for other BODYCAM mods.

---

# Projects Built From This Work

One of the first projects to build on this research is **TRENCH**, created by `0x0d4ddy`.

TRENCH extends the idea in a different direction, using increased match capacity to create large bot battles together with features such as:

* configurable team populations
* automatic bot filling
* large battles such as 12v12, 20v20, and beyond
* artillery strikes
* configurable artillery behavior
* 3D incoming-shell audio
* presets
* an external control panel

Its author credits this player-limit project as the foundation that solved the initial problem of allowing BODYCAM hosts to exceed the game's normal player restriction through Unreal reflection.

Seeing independent projects build on this research is exactly why this repository is public.

---

# Project Background

This project began with a simple question:

> Can BODYCAM's normal player limit be increased without permanently modifying the game?

Instead of assuming the answer, the project developed through experimentation.

The process involved:

```text
Idea
 ↓
Runtime investigation
 ↓
Reflection experiments
 ↓
Host testing
 ↓
Failed assumptions
 ↓
New discoveries
 ↓
Player joins
 ↓
Bot-control experiments
 ↓
More testing
 ↓
Public release
```

The project was developed collaboratively through extensive testing and AI-assisted programming/research.

The human side of the project provided the original idea, testing environment, observations, direction, and repeated real-world validation.

AI assistance helped inspect the results, reason about BODYCAM's Unreal structures, develop the UE4SS Lua implementation, and iteratively refine the experimental approach.

Neither part by itself would have produced the same result.

---

# Philosophy

The project intentionally avoids claiming more than testing has demonstrated.

Finding a property called:

```text
MaxPlayers
```

does not automatically prove that it controls the complete multiplayer system.

Writing:

```text
MaxPlayers = 64
```

does not automatically prove that 64 players can join.

And successfully joining more than the default number does not automatically prove that significantly larger matches are stable.

Every additional layer needs to be tested.

That is part of the purpose of this repository.

**Experiment first. Verify second. Document what actually happens.**

---

# Contributing

Testing is extremely valuable.

Useful reports include:

```text
BODYCAM version
UE4SS version
Configured player limit
Actual number of human players joined
Game mode
Map
Host hardware
Whether late joining worked
Whether lobby capacity displayed correctly
Any crashes
Any UI problems
Any replication problems
Performance observations
Relevant UE4SS log output
```

Testing different population levels is especially useful:

```text
12
16
20
24
30
32
40
48
64
```

Do not assume that a successful configuration write means the same number of players can actually participate.

The interesting result is the **highest population that successfully passes through the entire networking chain and remains playable**.

---

# Final Note

This project is experimental.

BODYCAM was not designed around these modifications, and future game updates may change the relevant classes, properties, functions, or online-session behavior.

That uncertainty is also what makes the research interesting.

What started as:

```text
"Can we increase BODYCAM's player limit?"
```

has become a broader investigation into how BODYCAM's multiplayer architecture actually works.

And now other projects are already building on the discoveries.
