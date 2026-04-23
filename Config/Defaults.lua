local ADDON_NAME, ns = ...

-- [ DEFAULTS ] ----------------------------------------------------------------
ns.Defaults = {
    profile = {
        minimap = { hide = false, minimapPos = 220 },
        configScale = 1.0,
        configPanelPos = { point = "CENTER", relPoint = "CENTER", x = 0, y = 0 },
        fpsBackup = nil,  -- snapshot of settings before Apply FPS

        -- QOL automation module
        qol = {
            autoQuest      = false,  -- auto accept/complete/collect quests
            autoGossip     = false,  -- auto-click single-option gossip/quest dialogs
            autoSummon     = false,  -- auto-accept summoning stone (5 s delay)
            autoRez        = false,  -- auto-accept resurrection offers
            autoRezInCombat = false, -- allow auto-rez even if the caster is in combat
            holdToRelease  = false,  -- require holding SHIFT to release spirit
            holdDuration   = 3,      -- seconds to hold before button enables
            holdAutoRelease = false, -- auto-release when countdown completes
            questSkipModifier = "SHIFT", -- hold this key to skip auto-quest actions
            autoSkipCinematic = false, -- auto-skip cinematics and cutscenes
            autoConfirmDelete = false, -- auto-fill the "DELETE" confirmation when destroying an item
            fasterLooting  = false,  -- enable faster auto-looting
            lootingDelay   = 0.2,    -- seconds between loot calls (0.2 is reliable; lower = faster but may miss items)
            sellJunk       = false,  -- sell grey items when visiting a vendor
            autoRepair      = false,  -- repair all gear when visiting a repair vendor
            repairGuild     = false,  -- prefer guild bank funds for repairs
            declineDuel     = false,  -- auto-decline duel requests
            declineGuild    = false,  -- auto-decline guild invite requests
            durabilityWarn  = false,  -- warn when any gear piece drops below threshold
            durabilityThresh = 20,    -- percent threshold for durability warning
            durPoint = "CENTER", durRelPoint = "CENTER", durX = 0, durY = -200,
            affixReminder   = false,  -- show this week's M+ affixes on login
            autoSlotKeystone    = false, -- auto-slot keystone when opening the challenge UI
            autoStartChallenge  = false, -- auto-start the M+ after keystone slots (3-second countdown)
            petReminder     = false,  -- warn when hunter/warlock pet is dead or missing
            petPoint = "CENTER", petRelPoint = "CENTER", petX = 0, petY = 100,
        },

        -- Mythic+ Timer module
        mythicTimer = {
            enabled       = true,
            hideBlizzard  = true,   -- hide default Blizzard M+ block in objective tracker
            point = "CENTER", relPoint = "CENTER", x = 300, y = 200,
            -- Completion message
            completionMsg        = false,
            completionMsgText    = "{dungeon} +{level} timed! {time} remaining — {deaths} death(s)",
            completionMsgChannel = "PARTY",
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
            showAllBuffs = false,  -- show all tracked buffs (present = dimmed, missing = blinking)
            point = "TOP", relPoint = "TOP", x = 0, y = -150,

            -- Weapon oil / temp enchant reminder (checks main-hand slot)
            weaponOil = false,

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

        -- Merchant module
        merchant = {
            enable = true,  -- extend merchant window to show 20 items per page
        },

        -- Raid Tools bar
        raidTools = {
            enabled   = true,
            minimized = false,
            point    = "CENTER", relPoint = "CENTER", x = 0, y = 200,
        },

        -- Great Vault progress tracker
        vaultTracker = {
            enabled         = true,
            showRaid        = true,
            showWorld       = true,
            showPvP         = false,
            scale           = 1.0,
            point = "RIGHT", relPoint = "RIGHT", x = -20, y = 0,
        },

        -- Combat Resurrection tracker
        combatRess = {
            enabled = true,
            scale   = 1.0,
            point = "CENTER", relPoint = "CENTER", x = 250, y = 0,
        },

        -- Skyriding HUD
        skyridingHUD = {
            enabled  = true,
            point    = "CENTER", relPoint = "CENTER", x = 0, y = -250,
        },

        -- Friend List styling module (ClassColorFriends)
        friendList = {
            enable           = true,
            useClassColor    = true,
            showLevel        = false,
            hideMaxLevel     = true,
            hideRealm        = false,
            useNoteAsName    = false,
            squareIcons      = true,
            forceClientIcons = true,
            statusIconPack   = "SQUARE",  -- "NONE" | "SQUARE"
            favoriteStyle    = "BAR",     -- "STAR" | "BAR" | "OFF"
            factionTint      = true,
            factionTintAlpha = 0.14,      -- 0..0.30
        },

        -- Group Finder companion filter panel
        groupFilter = {
            enabled    = true,
            -- Require section
            needTank   = false,
            needHealer = false,
            needDps    = false,
            needMyClass = false,
            hasTank    = false,
            hasHealer  = false,
            -- Difficulty section
            difficultyNormal     = false,
            difficultyHeroic     = false,
            difficultyMythic     = false,
            difficultyMythicPlus = false,
            -- Playstyle section
            playstyle1 = false,
            playstyle2 = false,
            playstyle3 = false,
            playstyle4 = false,
            -- Min Rating
            minRating  = 0,
        },

        -- Mouse Tracker ring + crosshair
        mouseTracker = {
            enabled   = false,
            -- Ring
            showRing  = true,
            radius    = 32,
            thickness = 2,
            alpha     = 0.85,
            useAccent = true,
            r = 1.0, g = 1.0, b = 1.0,
            -- Dot
            showDot  = false,
            dotSize  = 6,
            -- Crosshair
            showCrosshair      = false,
            crosshairLength    = 20,
            crosshairGap       = 6,
            crosshairThickness = 2,
        },
    },
    global = {
        theme = "mellow",  -- "mellow" | "blizzard"
        runHistoryByChar = {},  -- ["Realm-Name"] = { runs[] }
        historyPanelPos  = { point = "CENTER", relPoint = "CENTER", x = 0, y = 0 },
    },
}
