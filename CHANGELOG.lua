local ADDON_NAME, ns = ...

-- [ CHANGELOG ] ---------------------------------------------------------------
-- Add a new entry at the TOP of this table for each release.
-- `version` must match the release tag (without the leading 'v').
-- `date`    is a human-readable string shown in the popup.
-- `changes` is an ordered list of lines rendered inside the popup.
-- ---------------------------------------------------------------------------
ns.Changelog = {
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
