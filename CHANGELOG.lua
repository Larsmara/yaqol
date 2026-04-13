local ADDON_NAME, ns = ...

-- [ CHANGELOG ] ---------------------------------------------------------------
-- Add a new entry at the TOP of this table for each release.
-- `version` must match the release tag (without the leading 'v').
-- `date`    is a human-readable string shown in the popup.
-- `changes` is an ordered list of lines rendered inside the popup.
-- ---------------------------------------------------------------------------
ns.Changelog = {
    {
        version = "1.0.32",
        date    = "2026-04-13",
        changes = {
            "|cff2dc9b8Fix|r  M+ Timer: mob count percentage was showing ~16% instead of ~90%",
            "|cff2dc9b8Fix|r  M+ Timer: frame now stays visible after dungeon completion until player leaves",
            "|cff2dc9b8Fix|r  Skyriding HUD: re-checks visibility after zone change and on delayed load",
        },
    },
    {
        version = "1.0.31",
        date    = "2026-04-12",
        changes = {
            "|cff00d1b2New|r  Auto-fill the DELETE confirmation when destroying items (QOL toggle)",
            "|cff2dc9b8Fix|r  Auto-skip cinematics: GameMovieFinished() replaced with MovieFrame_StopMovie() (removed in 12.0)",
            "|cff2dc9b8Fix|r  Auto-skip cinematics: in-world cinematics now use CinematicFrame_CancelCinematic()",
        },
    },
    {
        version = "1.0.30",
        date    = "2026-04-12",
        changes = {
            "|cff00d1b2New|r  Skyriding HUD — charge pips (with partial recharge fill) and Whirling Surge cooldown bar",
            "|cff00d1b2New|r  Skyriding HUD only shows on skyriding mounts in Skyriding mode (not Steady Flight)",
            "|cff2dc9b8Fix|r  Raid Tools: ADDON_ACTION_BLOCKED in combat — Hide/Show now guards InCombatLockdown()",
            "|cff2dc9b8Fix|r  Pet reminder: no longer alerts 'No active pet!' while mounted",
            "|cff2dc9b8Fix|r  Pet reminder: also alerts when pet is on Passive stance",
        },
    },
    {
        date    = "2026-04-07",
        changes = {
            "|cff00d1b2New|r  Mythic+ Timer overlay — countdown, +2/+3 cutoffs, pull count, boss progress, death counter",
            "|cff00d1b2New|r  M+ Timer options tab with demo/test mode (simulates a +12 run at 30× speed)",
            "|cff00d1b2New|r  Pet reminder for Hunters / Warlocks — persistent red warning when no pet summoned",
            "|cff00d1b2New|r  Auto-slot keystone when opening the Challenge Mode UI",
            "|cff2dc9b8Fix|r  Auto-skip cinematics: switched to PLAY_MOVIE / CINEMATIC_START events (12.x compatible)",
            "|cff2dc9b8Fix|r  Buff Reminder delete button no longer bleeds outside scroll frame",
            "|cff2dc9b8Fix|r  Layout Mode properly hides Pet Reminder and M+ Timer on exit",
            "|cffffff00Improved|r  Teleport keystone sharing — better caching, re-request after key completion, /reload keeps cache",
        },
    },
    {
        version = "1.0.23",
        date    = "2026-04-02",
        changes = {
            "|cff2dc9b8Fix|r  Raid Tools bar now only shows when in a group as leader or assist — hides otherwise",
        },
    },
    {
        version = "1.0.22",
        date    = "2026-04-02",
        changes = {
            "|cff2dc9b8Fix|r  Raid Tools: removed unknown event WORLD_MAP_UPDATE (caused load error on some clients)",
            "|cff2dc9b8Fix|r  Raid Tools: removed RunMacroText calls (not available in addon environment)",
            "|cff2dc9b8Fix|r  Raid Tools: countdown now uses SendChatMessage to RAID/PARTY/SAY channel",
        },
    },
    {
        version = "1.0.21",
        date    = "2026-04-02",
        changes = {
            "|cff00d1b2New|r  Raid Tools bar: world markers (toggle on/off with active state), Clear All, Ready Check, and 3 s / 5 s / 10 s countdown buttons",
            "|cff00d1b2New|r  Raid Tools bar collapses to a slim side tab with '<' / '>' toggle",
            "|cff00d1b2New|r  Buff reminder: party badge shows how many group members have each buff (X/Y format)",
            "|cff00d1b2New|r  Buff reminder: orange '!' badge on icons when a non-player-class buff is missing from the entire group",
            "|cff00d1b2New|r  General settings: Game UI Scale picker with pixel-perfect presets for 4K / 1440p / 1080p at 100% / 125% / 150% DPI",
            "|cff888888New|r  Merchant window toggle moved into QOL tab - Vendor section",
            "|cff2dc9b8Fix|r  Well Fed buff now correctly dismissed when the aura is ContextuallySecret (Midnight API)",
            "|cff2dc9b8Fix|r  Food icon now shows the first available texture instead of always using the first list entry",
            "|cff2dc9b8Fix|r  Quest auto-accept now works for multi-quest NPCs using GOSSIP_SHOW (modern WoW path)",
            "|cff2dc9b8Fix|r  Merchant extended window no longer throws a nil-frame error before first vendor visit",
        },
    },
    {
        version = "1.0.20",
        date    = "2026-04-01",
        changes = {
            "|cff00d1b2New|r  Merchant: window now shows 20 items per page in a 4-column layout",
        },
    },
    {
        version = "1.0.19",
        date    = "2026-04-01",
        changes = {
            "|cff00d1b2New|r  Friend List: class-colours friend names, custom status icons, client icons & faction tints",
            "|cff2dc9b8Fix|r  Buff reminder panel no longer throws ADDON_ACTION_BLOCKED error during combat",
            "|cff2dc9b8Fix|r  Food reminder now dismisses correctly for legacy expansion feasts (e.g. Legion feasts)",
            "|cff2dc9b8Fix|r  Auto-gossip no longer intercepts quest turn-ins when a completed quest is available",
        },
    },
    {
        version = "1.0.18",
        date    = "2026-03-31",
        changes = {
            "|cff2dc9b8Fix|r  Removed click-to-cast from buff reminders (not possible from addon code)",
        },
    },
    {
        version = "1.0.17",
        date    = "2026-03-31",
        changes = {
            "|cff2dc9b8Fix|r  Buff reminder icons: clicking now works (parent frame was stealing mouse-down events)",
            "|cff2dc9b8Fix|r  Buff reminder dragging: use right-click drag to move the panel",
        },
    },
    {
        version = "1.0.16",
        date    = "2026-03-31",
        changes = {
            "|cff00d1b2New|r  Faster looting now suppresses the loot window entirely — loot goes straight to bags",
            "|cff2dc9b8Fix|r  Buff reminders failing to appear in instanced content (retry logic improved)",
            "|cff2dc9b8Fix|r  Auto-skip cinematics error on login (Midnight removed the old hook targets)",
        },
    },
    {
        version = "1.0.15",
        date    = "2026-03-31",
        changes = {
            "|cff2dc9b8Fix|r  Quest skip modifier now correctly grouped under auto-quest (not gossip)",
            "|cff2dc9b8Fix|r  Faster looting now also sets autoLootDelay=0 so the loot window closes instantly",
        },
    },
    {
        version = "1.0.14",
        date    = "2026-04-01",
        changes = {
            "|cff00d1b2New|r  Buff reminder icons show item count badge (e.g. how many flasks you have)",
            "|cff00d1b2New|r  Hover tooltip shows how many of the consumable are in your bags",
        },
    },
    {
        version = "1.0.13",
        date    = "2026-03-31",
        changes = {
            "|cff00d1b2New|r  Click buff reminder icons to cast the spell",
            "|cff00d1b2New|r  Tooltip shows how many group members are missing a party buff",
            "|cff00d1b2New|r  QOL: Faster looting (auto-loot without right-click)",
        },
    },
    {
        version = "1.0.12",
        date    = "2026-03-31",
        changes = {
            "|cff2dc9b8Fix|r  Now available on CurseForge",
        },
    },
    {
        version = "1.0.11",
        date    = "2026-03-31",
        changes = {
            "|cff2dc9b8Fix|r  WowUp update compatibility improvements",
        },
    },
    {
        version = "1.0.10",
        date    = "2026-03-31",
        changes = {
            "|cff2dc9b8Fix|r  WowUp update now works correctly after fresh install",
        },
    },
    {
        version = "1.0.9",
        date    = "2026-03-31",
        changes = {
            "|cff2dc9b8Fix|r  WowUp install and update now work correctly for all users",
        },
    },
    {
        version = "1.0.8",
        date    = "2026-03-31",
        changes = {
            "|cff2dc9b8Fix|r  Switched to BigWigsMods packager for guaranteed WowUp compatibility",
        },
    },
    {
        version = "1.0.7",
        date    = "2026-03-31",
        changes = {
            "|cff2dc9b8Fix|r  WowUp stable updates now work correctly (release.json added to releases)",
        },
    },
    {
        version = "1.0.6",
        date    = "2026-03-31",
        changes = {
            "|cff2dc9b8Fix|r  WowUp stable install now works via 'Install from URL'",
            "|cff2dc9b8Fix|r  Release zip has correct structure (yaqol/ root folder)",
            "|cff2dc9b8Fix|r  Version shown in-game no longer has a leading 'v'",
        },
    },
    {
        version = "1.0.5",
        date    = "2026-03-31",
        changes = {
            "|cff2dc9b8New|r  Weapon oil / temp enchant reminder (toggle in Buff Reminder tab)",
            "|cff2dc9b8New|r  Hold-to-release modifier selector: ANY / ALT / SHIFT / CTRL",
            "|cff2dc9b8New|r  Hold a modifier key to skip auto-quest actions (configurable)",
            "|cff2dc9b8New|r  Auto-complete all turn-in quests on the same NPC in one interaction",
            "|cff2dc9b8New|r  Auto-skip cinematics and cutscenes (toggle in QOL tab)",
            "|cff2dc9b8New|r  Addon icon now shown in the AddOns list",
        },
    },
    {
        version = "1.0.5",
        date    = "2026-03-31",
        changes = {
            "|cff2dc9b8New|r  Weapon oil / temp enchant reminder (toggle in Buff Reminder tab)",
            "|cff2dc9b8New|r  Hold-to-release modifier selector: ANY / ALT / SHIFT / CTRL",
        },
    },
    {
        version = "1.0.3",
        date    = "2026-03-31",
        changes = {
            "|cffffff00Fix|r  Config panel title still showed LarsQOL → now yaqol",
            "|cffffff00Fix|r  Frame names and chat prefix renamed to yaqol",
        },
    },
    {
        version = "1.0.1",
        date    = "2026-03-31",
        changes = {
            "|cffffff00Fix|r  Crash on load: LarsQOL:Profile() → yaqol:Profile()",
            "|cff2dc9b8New|r  What's New changelog popup in config panel header",
            "|cff2dc9b8New|r  /yq slash command alias",
        },
    },
    {
        version = "1.0.0",
        date    = "2026-03-31",
        changes = {
            "|cff2dc9b8New|r  Renamed addon from yacol → yaqol",
            "|cff2dc9b8New|r  M+ Teleport panel with per-dungeon portals",
            "|cff2dc9b8New|r  Buff Reminder for flasks, food, augment runes, weapon buffs",
            "|cff2dc9b8New|r  Class / party buff reminders",
            "|cff2dc9b8New|r  QOL automations: quests, gossip, summons, rez, vendor, M+ affixes",
            "|cff2dc9b8New|r  Layout Mode — drag all movable frames at once",
            "|cff2dc9b8New|r  Minimap button with right-click menu",
            "|cff2dc9b8New|r  FPS / graphics preset tuning in General tab",
            "|cff2dc9b8New|r  Per-character AceDB profiles",
        },
    },
}
