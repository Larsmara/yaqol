# yaqol

## [v1.1.2](https://github.com/Larsmara/yaqol/tree/v1.1.2) (2026-04-18)
[Full Changelog](https://github.com/Larsmara/yaqol/compare/v1.1.1...v1.1.2) [Previous Releases](https://github.com/Larsmara/yaqol/releases)

**Fixes:**
- M+ Timer: completion chat message now works — WoW 12.0 blocks `SendChatMessage` inside instances; message is built at key completion and queued, then sent when the player zones back to the world

[Full Changelog](https://github.com/Larsmara/yaqol/compare/v1.1.0...v1.1.1) [Previous Releases](https://github.com/Larsmara/yaqol/releases)

**New:**
- M+ Timer: optional completion message — sends a customisable message to party/say/yell when the key finishes; supports tokens `{dungeon}`, `{level}`, `{time}`, `{overtime}`, `{deaths}`, `{upgrades}`
- Teleport: map ID lookup is now built dynamically from `C_ChallengeMode.GetMapTable()` — fixes keys for any dungeon whose hardcoded ID didn't match the current season
- Teleport: Shift+Click the refresh button to print the full keystone cache and map mappings to chat for debugging
- Teleport: refresh button no longer wipes the cache — keeps visible keys while waiting for updated responses

**Fixes:**
- M+ Timer: Blizzard mob-count / criteria block now fully hidden — `ObjectiveTrackerFrame:Show` is hooked so it stays suppressed through every mob kill during the key
- M+ Timer: `StageBlock` and `ScenarioTimerFrame` added to the hide list; all Blizzard M+ UI elements are now covered
- M+ Timer: `CHALLENGE_MODE_START` immediately suppresses all Blizzard blocks at key start
- Combat Ress & Buff Reminder: keystone level comparison crash fixed — `GetActiveKeystoneInfo()` returns `level` as the first value, not the third
- Teleport: own keystone now reliably shown — LibKeystone `pName` is `nil` at load time; callback now substitutes `UnitName("player")` when playerName is absent

[Full Changelog](https://github.com/Larsmara/yaqol/compare/v1.0.35...v1.1.0) [Previous Releases](https://github.com/Larsmara/yaqol/releases)

**New:**
- Mouse Tracker: new module — draws a ring and/or crosshair around the cursor, great for streaming or presentations
- Mouse Tracker: ring uses 64 texture-quad segments for a smooth, gap-free circle with configurable radius, thickness, and opacity
- Mouse Tracker: optional crosshair with configurable line length, center gap, and line width
- Mouse Tracker: optional center dot with configurable size
- Mouse Tracker: custom color picker with live swatch preview; quick preset colors (White/Red/Yellow/Cyan/Green); option to follow theme accent color
- M+ Timer: completion banner now shows death count and time penalty
- Options: panel position is now saved and restored across sessions
- Run History: panel position is now saved and restored across sessions

**Fixes:**
- M+ Timer: body background now correctly follows the active theme color (was always a hardcoded dark stone texture)
- M+ Timer: DiamondMetal header corners fixed to 32×39 px — no longer overflow the frame width
- M+ Timer: boss kill times now recorded correctly (criteriaData sparse-indexing bug fixed)
- M+ Timer: keystone level was reading the wrong return value from `GetActiveKeystoneInfo`
- Run History: recording was broken — switched from `GetActiveKeystoneInfo` (returns nil after key deactivates) to `GetChallengeCompletionInfo`
- Vault Tracker: M+ progress now displays correctly (`Enum.WeeklyRewardChestThresholdType.Activities` renamed from `MythicPlus` in 12.0)
- Vault Tracker: colored reward boxes no longer washed out (draw layer was covering the colored texture)
- Vault Tracker: item level now read from the correct `GetItemInfo` return index
- Vault Tracker: `GetExampleRewardItemHyperlinks` return value now handled as a string (not a table)
- Combat Ress: crash on M+ keystone level detection fixed
- Buff Reminder: crash on M+ keystone level detection fixed
- Teleport: own keystone now always displayed — was falling back to direct API calls that return 0 before M+ data loads; now reads from LibKeystone cache with correct unit token

[Full Changelog](https://github.com/Larsmara/yaqol/compare/v1.0.34...v1.0.35) [Previous Releases](https://github.com/Larsmara/yaqol/releases)

**New:**
- M+ Timer: full visual redesign — textured DiamondMetal header, NineSlice border, cleaner layout
- M+ Timer: boss kill times displayed as coloured tiles per boss
- M+ Timer: pace line shows projected finish times for +3 / +2 / +1 upgrade thresholds
- M+ Timer: current week's affix icons shown in the timer header, with tooltips on hover
- M+ Timer: timed/completed banner on key finish — shows upgrade level (+1/+2/+3) and time remaining or overtime
- M+ Timer: Options demo now loops automatically; affix icons and banner are shown during the demo
- Buff Reminder: "Always Show All Tracked Buffs" toggle — present buffs shown dimmed, missing buffs still blink
- Options: switching to a module tab shows a live preview of its frame
- Options: closing the config panel now stops the M+ Timer demo

**Fixes:**
- Raid Tools: collapse state now persists across reloads

## [v1.0.34](https://github.com/Larsmara/yaqol/tree/v1.0.34) (2026-04-17)
[Full Changelog](https://github.com/Larsmara/yaqol/compare/v1.0.33...v1.0.34) [Previous Releases](https://github.com/Larsmara/yaqol/releases)

**New:**
- Combat Ress Timer: draggable icon showing available combat resurrection charges (visible in raids and M+)

**Fixes:**
- Buff Reminder: Shaman shields (Lightning Shield / Water Shield) now merged into one entry — only one can be active at a time
- Buff Reminder: Shaman Earthliving Weapon now correctly detected as a temporary weapon enchant
- QOL: Hold to Release now grays out the release button on death, requires holding SHIFT for a configurable duration before enabling it
- Options: all sliders now render correctly and no longer overflow the panel bounds; value label now visible

## [v1.0.33](https://github.com/Larsmara/yaqol/tree/v1.0.33) (2026-04-13)
[Full Changelog](https://github.com/Larsmara/yaqol/compare/v1.0.32...v1.0.33) [Previous Releases](https://github.com/Larsmara/yaqol/releases)

**Fixes:**
- M+ Timer: pull count now shows two decimal places (e.g. `14.67%`)
- M+ Timer: frame now correctly stays visible after the key ends until the player zones out

## [v1.0.32](https://github.com/Larsmara/yaqol/tree/v1.0.32) (2026-04-13)
[Full Changelog](https://github.com/Larsmara/yaqol/compare/v1.0.31...v1.0.32) [Previous Releases](https://github.com/Larsmara/yaqol/releases)

**Fixes:**
- M+ Timer: mob count percentage was calculated incorrectly (showing ~16% instead of ~90%)
- M+ Timer: timer frame now stays visible after dungeon completion until the player leaves
- Skyriding HUD: re-check visibility after a short delay on `PLAYER_ENTERING_WORLD` so spell data is ready; also track `ZONE_CHANGED_NEW_AREA`

## [v1.0.31](https://github.com/Larsmara/yaqol/tree/v1.0.31) (2026-04-12)
[Full Changelog](https://github.com/Larsmara/yaqol/compare/v1.0.30...v1.0.31) [Previous Releases](https://github.com/Larsmara/yaqol/releases)

**New:**
- Auto-fill the DELETE confirmation when destroying items (QOL toggle)

**Fixes:**
- Auto-skip cinematics: `GameMovieFinished()` replaced with `MovieFrame_StopMovie()` (removed in 12.0)
- Auto-skip cinematics: in-world cinematics now use `CinematicFrame_CancelCinematic()`

## [v1.0.30](https://github.com/Larsmara/yaqol/tree/v1.0.30) (2026-04-12)
[Full Changelog](https://github.com/Larsmara/yaqol/compare/v1.0.29...v1.0.30) [Previous Releases](https://github.com/Larsmara/yaqol/releases)

- New: Skyriding HUD — charge pips (with partial recharge fill) and Whirling Surge cooldown bar
- New: Skyriding HUD only shows on skyriding mounts in Skyriding mode (not Steady Flight)
- Fix: Raid Tools: ADDON_ACTION_BLOCKED in combat — Hide/Show now guards InCombatLockdown()
- Fix: Pet reminder: no longer alerts "No active pet!" while mounted
- Fix: Pet reminder: also alerts when pet is on Passive stance

## [v1.0.27](https://github.com/Larsmara/yaqol/tree/v1.0.27) (2026-04-07)
[Full Changelog](https://github.com/Larsmara/yaqol/compare/v1.0.26...v1.0.27) [Previous Releases](https://github.com/Larsmara/yaqol/releases)

- New: Mythic+ Timer overlay — shows countdown, +2/+3 cutoffs, pull count, boss progress, death counter
- New: M+ Timer options tab with enable/disable, hide Blizzard block, and demo/test mode
- New: Demo mode simulates a scripted +12 dungeon run at 30× speed
- New: Pet reminder for Hunters and Warlocks — persistent red warning when no pet summoned
- New: Auto-slot keystone when opening the Challenge Mode UI
- Fix: Auto-skip cinematics now uses PLAY_MOVIE/CINEMATIC_START events (old hooks removed in 12.x)
- Fix: Buff Reminder delete button no longer bleeds outside scroll frame
- Fix: Layout Mode now properly hides Pet Reminder and M+ Timer on exit
- Improved: Teleport panel keystone sharing — better cache management, re-request after key completion, /reload preserves cache

## [v1.0.23](https://github.com/Larsmara/yaqol/tree/v1.0.23) (2026-04-02)
[Full Changelog](https://github.com/Larsmara/yaqol/compare/v1.0.0...v1.0.1) [Previous Releases](https://github.com/Larsmara/yaqol/releases)

- v1.0.1: fix LarsQOL crash, add changelog UI, /yq alias  
