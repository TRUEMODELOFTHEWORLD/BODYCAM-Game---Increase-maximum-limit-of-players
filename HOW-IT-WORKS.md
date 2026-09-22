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
  "maxBotsPerTeam": 6
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
TeamConfig.TeamMaxSize = 20
```

For a normal two-team mode:

```text
40 total players
     │
     ├── Team 1: up to 20
     └── Team 2: up to 20
```

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

Team Deathmatch introduces another complication.

BODYCAM may perform its initial bot population extremely quickly when a new match starts.

By the time a normal periodic script detects the match, the game may already have filled many available positions.

The mod therefore contains an initial-fill workaround.

For example:

```text
Configured maximum players: 40
Configured bots per team:   6
Current humans:              1
```

The initial desired population is approximately:

```text
1 human
```
