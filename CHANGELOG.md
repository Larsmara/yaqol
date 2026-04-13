# yaqol

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
