---
applyTo: "**/*.lua"
---

# yaqol — Coding Instructions

## Addon Identity

- Addon name: **yaqol** (Yet Another Quality Of Life)
- Interface target: `120001` (Retail WoW, Midnight / 12.x)
- Entry point: `Core/Init.lua` — defines `yaqol` via `LibStub("AceAddon-3.0"):NewAddon`
- Namespace: `local ADDON_NAME, ns = ...` — all shared state hangs off `ns`
- SavedVariables: `yaqolDB` via AceDB-3.0

## Module Pattern

```lua
-- In each module file:
local ADDON_NAME, ns = ...
ns.MyModule = {}
local M = ns.MyModule

function M.Init(addon) ... end
function M.Refresh(addon) ... end
```

`Init` is called from `yaqol:OnEnable`. `Refresh` is called from `yaqol:OnProfileChanged`.  
Modules must not call each other directly — communicate through `ns` or events.

## Load Order

Files load in the order declared in `yaqol.toc`. A module can reference `ns.X` only if `X` is defined in a file listed earlier in the toc. Never forward-reference.

## Database / Defaults

- All defaults live in `Config/Defaults.lua` as `ns.Defaults`
- Access profile data via `ns.Addon.db.profile`
- Write migration guards in `yaqol:OnInitialize` for every new field added — check `== nil` before setting

## Config / Options

- All AceConfig option tables built in `Config/Options.lua` via `ns.Config.Build(addon)`
- Group keys match `db.profile` sub-table names exactly
- `get`/`set` closures read and write `ns.Addon.db.profile.<group>.<key>` directly

## pcall Policy

- Required for WoW 12.x secret-value APIs: `UnitHealthPercent`, `UnitPowerPercent`, etc.
- Permitted at infrastructure error boundaries (EventBus, CombatManager, ProfileManager)
- Forbidden in combat scenarios — never mask a live issue
- Never use pcall to swallow bugs

## Combat Lockdown

- All protected frame ops (`SetPoint`, `Show`, `Hide`, `SetAttribute`, `RegisterStateDriver`) must check `InCombatLockdown()`
- Queue deferred work and flush on `PLAYER_REGEN_ENABLED`
- Never call secure template methods during combat

## Code Style (enforced)

- Inline code aggressively — minimize LOC
- No multi-line comments — single-line `--` only
- Constants at file top; no magic numbers
- Section dividers: `-- [ TITLE ] -----------------------------------------------------------------` (no blank line after)
- `SCREAMING_SNAKE_CASE` — constants, system IDs
- `PascalCase` — methods, classes, mixins
- `camelCase` — locals, parameters, frame fields

## Event Patterns

- `frame:RegisterUnitEvent()` — unit-specific WoW events
- Cross-module: fire through an event bus, not direct calls
- `EventRegistry:RegisterCallback()` — Blizzard UI system events (EditMode, etc.)

## Frame Layering

- Use frame levels (constants) not strata for z-ordering within a plugin
- Change strata only to escape a parent's strata (tooltips, dialogs)

## Architecture Rules

- Domain Driven Design. Object Oriented. SOLID. DRY (unless DRY violates SRP).
- No fallback code. Work once or fail fast. No defensive nil-chains.
- No memory leaks, O(n²) where O(n) exists, or wasted cycles.
- Single Responsibility — if a file exceeds ~1000 LOC, decompose it.
- New features go in the contextually correct module under `Modules/`.
