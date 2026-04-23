# yaqol — Yet Another Quality Of Life

> **Disclaimer: This addon is shamelessly vibecoded.**

A personal World of Warcraft addon built around Mythic+ and general quality-of-life. Bundles a collection of features that the author wanted but couldn't find together in a single lightweight package.

---

## Installation

**WowUp** (recommended): Open WowUp → *Install* tab → *Install from URL* and paste:
```
https://github.com/Larsmara/yaqol
```
Or download the latest `yaqol-vX.Y.Z.zip` from the [Releases](https://github.com/Larsmara/yaqol/releases) page and extract it into your `World of Warcraft/_retail_/Interface/AddOns/` folder.

> The folder name **must** be `yaqol` to match the `.toc` file.

---

## Features

### ⏱️ Mythic+ Timer
A replacement M+ timer overlay that suppresses all Blizzard M+ UI blocks and shows a cleaner, information-dense view.

- Textured DiamondMetal header with affix icons and tooltips
- Countdown with colour-coded pace line showing projected +3 / +2 / +1 finish times
- Mob pull count percentage with two decimal places
- Per-boss kill times shown as coloured tiles
- Death counter with accumulated time penalty
- Completion/timeout banner showing upgrade level (+1/+2/+3) and time remaining or overtime
- Optional completion chat message sent to party — supports tokens `{dungeon}`, `{level}`, `{time}`, `{overtime}`, `{deaths}`, `{upgrades}` (message is queued and sent after leaving the instance, working around Blizzard's in-instance chat restriction)
- Demo mode that simulates a scripted +12 run at 30× speed
- Frame position saved and restored across sessions

### 🗓️ Run History
A filterable log of all your completed Mythic+ runs, stored per character.

- Tracks dungeon, key level, time, delta vs. limit, upgrade level, deaths, and date
- Filter by time window (current week / season / all time), dungeon, and minimum key level
- Colour-coded rows: green (+3), blue (+2), yellow (+1), grey (timed, no upgrade), red (depleted)
- Stat summary bar showing totals across the filtered view
- Panel position saved and restored across sessions

### 🏆 Vault Tracker
A compact popup anchored near (or to) the minimap showing your Great Vault progress for the week.

- Shows M+ (always), Raid, World, and PvP tracks (each toggle-able)
- Slot indicators colour-coded: vivid green (unlocked), amber (in progress), dark grey (not started)
- Displays the projected item level reward for each unlocked slot
- Click the anchor to pin the popup open; click again or close it to dismiss

### 🗺️ Teleport Panel
A compact, draggable list of dungeon teleport buttons for the current Mythic+ season.

- Shows only when you are in a group (configurable minimum group size: 1–5 members)
- Automatically hides while you are inside an instance
- Greyed-out buttons for spells you haven't learned yet (toggle-able)
- Highlights the dungeon matching **your own keystone** with a gold border and `+N` level badge
- Panel fades to full opacity when your group reaches 5 members
- Closeable via an `×` button in the header; re-appears automatically when you join a new group
- Fully draggable; position is saved per-profile

### 🔔 Buff / Aura Reminder
An on-screen panel that warns you about missing pre-pull consumables.

- Tracks **flasks**, **food** (Well Fed), **augment runes**, **weapon buffs**, and fully **custom spell IDs**
- Activates automatically on entering a Mythic+, raid, or regular dungeon (each toggle-able)
- Minimum keystone level threshold — won't warn you on low keys
- Configurable expiry threshold: only warns if a buff has less than N seconds remaining
- Optional enter delay and auto-dismiss timer
- "Always show all tracked buffs" mode — present buffs shown dimmed, missing buffs blink
- Shows the key holder and level when inside an active M+
- Supports class-specific self-buffs (Paladin auras, Mage Arcane Intellect, Shaman weapon enchants, etc.)

### ☠️ Combat Ress Timer
A small draggable icon showing the shared combat resurrection charge pool.

- Displays current charges with a cooldown swipe showing the recharge progress
- Visible in raids and in Mythic+ (configurable minimum key level)
- Uses `GetSpellCharges(Rebirth)` — works for all classes' battle-rez spells

### 🛡️ Raid Tools
A compact collapsible toolbar for raid leads and assistants.

- 8 world marker buttons — left-click to place, right-click to clear
- Clear All markers button
- Ready Check button
- Countdown buttons: 3 s / 5 s / 10 s
- Auto-hides when you are not the group leader or an assist
- Collapsible; position saved per-profile

### 🔍 Group Filter
An advanced filter panel that overlays the LFG Search view.

- Toggle needs/has role filters (tank, healer, DPS, my class)
- Difficulty filters (Normal, Heroic, Mythic, M+)
- Playstyle filters
- Minimum Mythic+ rating filter
- Per-dungeon activity toggles for pinpoint queue filtering
- Filters commit and re-run the search live on every change

### 👥 Friend List
A replacement friend list panel displayed as a minimap dropdown.

- Shows both WoW and BattleNet friends in a unified list
- Game client icons indicating which WoW version (Retail, Classic, TBC, Wrath, Cata, MoP, WoWLabs)
- Online/Away/DND status indicators

### 🐭 Mouse Tracker
Draws a ring and/or crosshair around the cursor — useful for streaming or presentations.

- Ring rendered with 64 texture-quad segments for a smooth, gap-free circle
- Configurable ring radius, thickness, and opacity
- Optional crosshair with configurable line length, center gap, and line width
- Optional center dot with configurable size
- Custom color picker with live swatch preview and quick preset colors (White / Red / Yellow / Cyan / Green)
- Option to follow the active theme accent color

### 🪂 Skyriding HUD
A minimal heads-up display for Skyriding mounts.

- Charge pips showing ready charges and partial recharge fill for the shared Surge Forward / Skyward Ascent charge pool (up to 6 charges)
- Whirling Surge cooldown bar (hidden while ready)
- Only shown when mounted on a Skyriding mount in Skyriding mode; hides during Steady Flight

### 🛒 Merchant
Extends the default vendor window to show 20 items per page instead of 10.

- Rebuilds the vendor frame into a 4-column × 5-row layout on first open
- Pagination buttons repositioned to match the wider frame

### ⚙️ QoL Automation
A collection of small automation toggles, all off by default:

| Setting | What it does |
|---|---|
| Auto Accept Quests | Accepts, completes, and collects quest rewards automatically; hold a configurable modifier key to skip |
| Auto Gossip | Clicks through single-option NPC gossip dialogs |
| Auto Summon | Accepts summoning stone requests after a 5 s delay |
| Auto Resurrect | Accepts resurrection offers automatically |
| Hold to Release | Greys out the release button on death; requires holding SHIFT for a configurable duration before it enables |
| Auto Repair | Repairs all gear when opening a repair vendor; optionally uses guild bank funds |
| Sell Junk | Sells all grey items when you open any vendor |
| Decline Duels | Auto-declines duel requests |
| Decline Guild Invites | Auto-declines guild invite requests |
| Durability Warning | Fading red on-screen warning when any gear piece drops below a configurable % durability threshold |
| Affix Reminder | Popup on login showing this week's Mythic+ affixes |
| Auto-skip Cinematics | Skips in-game and in-world cinematics automatically |
| Auto-slot Keystone | Inserts your keystone automatically when you open the Challenge Mode UI |
| Pet Reminder | Persistent red warning for Hunters and Warlocks when no pet is summoned |
| Auto-fill Item Destroy | Auto-fills the DELETE confirmation when destroying items |

### 📐 Layout Mode
Arrange all movable frames at once without hunting through settings.

- Accessible via `/yaqol layout` (or `/yq layout`) or the **Arrange** button in the config panel
- All movable frames appear simultaneously with drag handles
- Click **Done** to save all positions at once

### 🖥️ FPS / Performance Settings
One-click application of a curated set of CVar tweaks aimed at improving frame rate — and a **Restore** button to undo them all.

---

## Commands

| Command | Action |
|---|---|
| `/yaqol` | Open the configuration panel |
| `/yq` | Alias for `/yaqol` |
| `/yaqol tp` | Toggle the teleport panel |
| `/yaqol layout` | Enter / exit layout mode |

---

## Configuration

Click the minimap button or type `/yaqol` (or `/yq`) to open the configuration panel. Each module has its own tab. Switching to a module tab shows a live preview of its frame. Settings are saved per character profile via AceDB; global data (run history) is saved account-wide.

---

## Requirements

- World of Warcraft: Midnight (Interface 12.x)
- No external dependencies — all required Ace3 libraries and LibKeystone are bundled.

---

## Notes

- **Keystone highlighting** in the Teleport Panel shows **your own key only**. Blizzard does not expose an API for reading party members' keystones; highlighting others' keys would require addon-to-addon comms (like BigWigs does), which is out of scope.
- **Completion chat messages** from the M+ Timer are queued and sent after you leave the instance — this is a hard requirement in WoW 12.0, where `SendChatMessage` is blocked inside instances.

---

## License

Personal use. No warranty. Vibecoded with love.
