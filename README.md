# yacol — Yet Another Collection Of Lua

> **Disclaimer: This addon is shamelessly vibecoded.**

A personal World of Warcraft addon for Mythic+ players. Bundles several small quality-of-life features that the author wanted but couldn't find in a single lightweight package.

---

## Features

### 🗺️ Teleport Panel
A compact, draggable list of dungeon teleport buttons for the current Mythic+ season.

- Shows only when you are in a group (configurable minimum group size: 1–5 members)
- Automatically hides while you are inside an instance
- Greyed-out buttons for spells you haven't learned yet (toggle-able)
- Highlights the dungeon matching **your own keystone** with a gold border and `+N` level badge
- Panel fades to full opacity when your group reaches 5 members — right when you need it most
- Closeable via an `×` button in the header; re-appears automatically when you join a new group
- Fully draggable; position is saved per-profile

### 🔔 Buff / Aura Reminder
An on-screen reminder that nags you about missing pre-pull consumables.

- Tracks **flasks**, **food** (Well Fed), **augment runes**, **weapon buffs**, and fully **custom spell IDs**
- Activates automatically on entering a Mythic+, raid, or regular dungeon (each toggle-able)
- Minimum keystone level threshold — won't pester you on low keys
- Configurable expiry threshold: only warns if a buff has less than N seconds remaining
- Optional enter delay and auto-dismiss timer
- Shows a tooltip listing exactly which buffs are missing
- Supports class-specific self-buffs (e.g. Paladin auras, Mage Arcane Intellect) and party-buff awareness

### ⚙️ QoL Automation
A collection of small automation toggles, all off by default:

| Setting | What it does |
|---|---|
| Auto Accept Quests | Accepts, completes, and collects quest rewards automatically |
| Auto Gossip | Clicks through single-option gossip / quest dialogs |
| Auto Summon | Accepts summoning stone requests after a 5 s delay |
| Auto Resurrect | Accepts resurrection offers automatically |
| Hold to Release | Requires Alt/Shift/Ctrl to release spirit (prevents accidental releases) |
| Sell Junk | Sells all grey items when you open a vendor |
| Auto Repair | Repairs all gear at a repair vendor; optionally uses guild bank funds |
| Decline Duels | Auto-declines duel requests |
| Decline Guild Invites | Auto-declines guild invite requests |
| Durability Warning | Shows an on-screen fading red warning when any piece of gear drops below a configurable % threshold |
| Affix Reminder | Displays this week's Mythic+ affixes in a popup on login |

### 📐 Layout Mode
Arrange all on-screen frames at once without hunting through settings.

- Accessible via `/yacol layout` or the **Arrange** button in the config panel
- All movable frames appear simultaneously with drag handles
- Click **Done** to save all positions at once

### 🖥️ FPS / Performance Settings
One-click application of a curated set of CVar tweaks aimed at improving frame rate — and a **Restore** button to undo them all.

---

## Installation

1. Download or clone this repository.
2. Copy the `yacol` folder into your WoW `Interface/AddOns/` directory.
3. Reload WoW or log in — the addon will appear in your AddOn list as **yacol**.

> The folder name **must** be `yacol` to match the `.toc` file.

---

## Commands

| Command | Action |
|---|---|
| `/yacol` | Open the configuration panel |
| `/lqol` | Alias for `/yacol` |
| `/yacol tp` | Toggle the teleport panel |
| `/yacol layout` | Enter / exit layout mode |

---

## Configuration

Click the minimap button or type `/yacol` to open the configuration panel. Settings are saved per character profile via AceDB.

---

## Requirements

- World of Warcraft: The War Within / Midnight (Interface 12.x)
- No external dependencies — all required Ace3 libraries are bundled.

---

## Notes on keystone highlighting

The gold-border keystone highlight shows **your own key only**. Blizzard does not expose an API for reading party members' keystones, so highlighting other players' keys would require addon-to-addon communication (like BigWigs does). That infrastructure is out of scope for this addon.

---

## License

Personal use. No warranty. Vibecoded with love.
