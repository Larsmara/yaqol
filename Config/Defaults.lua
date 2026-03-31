local ADDON_NAME, ns = ...

-- [ DEFAULTS ] ----------------------------------------------------------------
ns.Defaults = {
    profile = {
        minimap = { hide = false, minimapPos = 220 },
        configScale = 1.0,
        fpsBackup = nil,  -- snapshot of settings before Apply FPS

        -- QOL automation module
        qol = {
            autoQuest      = false,  -- auto accept/complete/collect quests
            autoGossip     = false,  -- auto-click single-option gossip/quest dialogs
            autoSummon     = false,  -- auto-accept summoning stone (5 s delay)
            autoRez        = false,  -- auto-accept resurrection offers
            autoRezInCombat = false, -- allow auto-rez even if the caster is in combat
            holdToRelease  = false,  -- require ALT/SHIFT/CTRL to release spirit
            sellJunk       = false,  -- sell grey items when visiting a vendor
            autoRepair      = false,  -- repair all gear when visiting a repair vendor
            repairGuild     = false,  -- prefer guild bank funds for repairs
            declineDuel     = false,  -- auto-decline duel requests
            declineGuild    = false,  -- auto-decline guild invite requests
            durabilityWarn  = false,  -- warn when any gear piece drops below threshold
            durabilityThresh = 20,    -- percent threshold for durability warning
            durPoint = "CENTER", durRelPoint = "CENTER", durX = 0, durY = -200,
            affixReminder   = false,  -- show this week's M+ affixes on login
        },

        -- Teleport module
        teleport = {
            enabled = true,
            showUnknown = true,
            minGroupSize = 2,  -- show panel when group has at least this many members (1 = always)
            scale = 1.0,
            point = "CENTER", relPoint = "CENTER", x = 0, y = 0,
        },

        -- Aura Reminder module
        reminder = {
            enabled = true,
            scale = 1.0,
            enabledMythicPlus = true,
            enabledRaid = true,
            enabledDungeon = true,
            minKeystoneLevel = 1,
            remindOnBuffLost = true,
            onlyOutOfCombat = true,
            showTooltip = true,
            enterDelay = 2,
            dismissAfter = 0,    -- 0 = never auto-dismiss
            buffMinRemaining = 60, -- seconds; 0 = just check presence
            point = "TOP", relPoint = "TOP", x = 0, y = -150,

            -- spellID lists per category; user-extensible
            -- Flask buff IDs (Midnight Season 1 — four stat flasks + PvP variant)
            flasks = {
                { spellID = 1235110, label = "Flask of the Blood Knights" },
                { spellID = 1235108, label = "Flask of the Magisters" },
                { spellID = 1235111, label = "Flask of the Shattered Sun" },
                { spellID = 1235057, label = "Flask of Thalassian Resistance" },
                { spellID = 1239355, label = "Vicious Thalassian Flask of Honor" },
                -- PvP-morphed variants (Blizzard replaces buff ID inside arena/BG)
                { spellID = 1235113, label = "Flask (PvP variant 1)" },
                { spellID = 1235114, label = "Flask (PvP variant 2)" },
                { spellID = 1235115, label = "Flask (PvP variant 3)" },
                { spellID = 1235116, label = "Flask (PvP variant 4)" },
            },
            -- Food is detected via the generic "Well Fed" / "Hearty Well Fed" buff.
            -- spellID 455369 = "Well Fed", 462187 = "Hearty Well Fed"
            -- (These are shared by ALL Midnight food items — one active = satisfied)
            food = {
                { spellID = 455369, label = "Well Fed" },
                { spellID = 462187, label = "Hearty Well Fed" },
            },
            -- Augment Rune buff IDs (covers all current and legacy rune variants)
            -- Items: 259085 = Void-Touched Augment Rune, 243191 = Ethereal Augment Rune
            augmentRunes = {
                { spellID = 1264426, label = "Augment Rune (Void-Touched)" },
                { spellID = 453250,  label = "Augment Rune (Ethereal)" },
                { spellID = 1234969, label = "Augment Rune (variant)" },
                { spellID = 1242347, label = "Augment Rune (variant)" },
                { spellID = 393438,  label = "Crystallized Augment Rune (TWW)" },
                { spellID = 347901,  label = "Augment Rune (legacy)" },
            },
            weaponBuffs = {
                -- Temporary weapon enchants (Midnight Season 1)
                -- Weightstone (blunt), Whetstone (bladed), oils (neutral)
                -- These are applied via items and show as weapon enchant buffs.
                -- Add your preferred enchant spell IDs here.
                -- Refulgent Weightstone / Whetstone (items 237367-237371)
                -- Thalassian Phoenix Oil (items 243733-243734)
                -- Oil of Dawn (items 243735-243736)
                -- Smuggler's Enchanted Edge (items 243737-243738)
                -- Note: Shaman imbues, rogue poisons & paladin rites are class
                --       mechanics and are best tracked via those class-specific spells.
            },
            -- Completely custom extra spells the user wants monitored
            custom = {},

            -- Class-specific buff reminders (poisons, rites, imbues, stances…)
            -- enableClassBuffs = false turns off the whole class buff section.
            -- classBuffs[spellID_as_string] = false disables a single check.
            enableClassBuffs = true,
            classBuffs = {},  -- per-spell overrides: e.g. { ["386208"] = false }

            -- Party/raid buff reminders (Fort, MotW, AI, Battle Shout, Skyfury…)
            -- Only fires for the player's class and only if anyone in the group is missing it.
            -- partyBuffs[key] = false disables a single buff (e.g. { fort = false })
            enablePartyBuffs = true,
            partyBuffs = {},
        },
    },
}
