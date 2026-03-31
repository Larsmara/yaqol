# LarsQOL — Development Notes

Hard-won lessons from building and debugging this addon. Useful reference for future work.

---

## WoW API Gotchas

### `IsInInstance()` vs `GetInstanceInfo()` — Critical Difference

**Problem:** `IsInInstance()` returns `"none"` during `PLAYER_ENTERING_WORLD` and `ZONE_CHANGED_NEW_AREA` events, even when the player is loading into an instance. Any zone-entry logic that calls `IsInInstance()` immediately after these events will always think the player is in the open world.

**Solution:** Use `GetInstanceInfo()` instead. It returns the correct instance type immediately when these events fire.

```lua
-- WRONG — returns "none" during PLAYER_ENTERING_WORLD
local _, iType = IsInInstance()

-- CORRECT — returns "party", "raid", etc. immediately
local _, iType = GetInstanceInfo()
```

---

### `C_Timer.After` / `C_Timer.NewTimer` Unreliable During Loading Screens

**Problem:** Timers scheduled from inside `PLAYER_ENTERING_WORLD` or `ZONE_CHANGED_NEW_AREA` handlers can be silently dropped by the game engine during a loading screen transition. `C_Timer.NewTimer` (cancellable) and `C_Timer.After` both exhibited this behaviour.

**Solution:** Use `C_Timer.After(0, fn)` to defer execution to the **next frame**. This is safe and is the pattern used by EllesmereUI. Combine with a sequence counter so rapid zone events don't trigger multiple checks:

```lua
local pendingSeq = 0
local function ScheduleCheck()
    pendingSeq = pendingSeq + 1
    local seq = pendingSeq
    C_Timer.After(0, function()
        if seq ~= pendingSeq then return end  -- superseded by a later event
        isActive = ShouldActivate()
        if isActive then CheckAndShow() end
    end)
end
```

---

### `C_ChallengeMode.GetActiveKeystoneInfo()` Return Values

**Problem:** We wrote `local _, lvl = C_ChallengeMode.GetActiveKeystoneInfo()` assuming the level was the second return value. It is the **first**. The second return value is a table of affixes. This caused a silent Lua error (`table >= number` comparison fails), which made `ShouldActivate()` return `nil` on its second call inside `CheckAndShow()`.

**Correct signature:**
```lua
local level, affixes, wasEnergized = C_ChallengeMode.GetActiveKeystoneInfo()
-- Always tonumber() guard it:
local lvl = tonumber(C_ChallengeMode.GetActiveKeystoneInfo()) or 0
```

---

### `C_ChallengeMode.IsChallengeModeActive()` vs `C_MythicPlus.IsMythicPlusActive()`

Prefer `C_ChallengeMode.IsChallengeModeActive()`. It is what Blizzard's own UI and EllesmereUI use. `IsMythicPlusActive` exists but may not behave consistently across follower dungeons and other edge cases.

---

### Follower Dungeons Report as M+ with Keystone Level 0

Follower dungeons (and regular heroics) show up as `iType == "party"` and `C_ChallengeMode.IsChallengeModeActive()` may return true with a level of 0. Do not gate dungeon reminders exclusively on M+ being active — fall through to `db.enabledDungeon` so regular dungeons are also covered:

```lua
if iType == "party" then
    if db.enabledMythicPlus and C_ChallengeMode.IsChallengeModeActive() then
        local lvl = tonumber(C_ChallengeMode.GetActiveKeystoneInfo()) or 0
        if lvl >= db.minKeystoneLevel then return true end
        -- Below threshold — fall through to dungeon check
    end
    return db.enabledDungeon  -- covers heroic, follower, mythic 0, etc.
end
```

---

## Midnight 12.0 Aura API — Secret Values

### `GetPlayerAuraBySpellID` Restrictions

In Midnight (12.0), Blizzard introduced "secret values" — aura data that is restricted during combat and inside M+ keystones / PvP. Calling `GetPlayerAuraBySpellID` on a non-whitelisted spell ID during combat returns `nil` (not an error), giving a false "buff not present" result.

**Rules:**
- Always wrap in `pcall` so future API changes don't break the addon.
- Only query non-secret IDs during combat. Out-of-combat all IDs are readable.
- Since we default to `onlyOutOfCombat = true`, this is belt-and-suspenders — but the code is correct either way.

```lua
local function PlayerHasAura(spellID)
    local ok, result = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellID)
    return ok and result ~= nil
end
```

### Whitelisted (Non-Secret) IDs in Midnight 12.0

These IDs are readable via `GetPlayerAuraBySpellID` in all contexts (combat, M+, PvP):

- **Raid buffs:** Mark of the Wild (`1126`, `432661`), Arcane Intellect (`1459`, `432778`), Battle Shout (`6673`), Power Word: Fortitude (`21562`), Skyfury (`462854`), Blessing of the Bronze (13 class variants)
- **Paladin Rites:** `433568`, `433583`
- **Rogue Poisons:** `2823`, `8679`, `3408`, `5761`, `315584`, `381637`, `381664`
- **Shaman Imbuements:** `319773`, `319778`, `382021`, `382022`, `457496`, `457481`, `462757`, `462742`
- **Midnight Flasks:** `1235110`, `1235108`, `1235111`, `1235057`, `1239355`, `1235113`–`1235116`

### Devotion Aura is ContextuallySecret

Spell ID `465` (Devotion Aura) is explicitly marked `ContextuallySecret` in Midnight 12.0. `GetPlayerAuraBySpellID(465)` will return `nil` in some contexts regardless of whether the aura is active. Use `pcall` and treat a `nil` result as inconclusive rather than "missing".

### Well Fed / Hearty Well Fed

All Midnight food grants the generic "Well Fed" buff (`455369`) or "Hearty Well Fed" (`462187`). These IDs are **not** in the non-secret whitelist — only query them out of combat. Checking either one is sufficient; if active, the player has food.

### Augment Rune Buff IDs

Rune buff IDs across expansions/ranks (not all whitelisted — OOC only):
`1264426`, `453250`, `1234969`, `1242347`, `393438`, `347901`

---

## `IsSpellKnown` vs `IsPlayerSpell`

`IsSpellKnown` misses some talent-granted spells. Use both:

```lua
local function Known(spellID)
    if not spellID then return false end
    return (IsPlayerSpell and IsPlayerSpell(spellID)) or IsSpellKnown(spellID) or false
end
```

---

## AceDB Defaults and Profile Migration

When defaults change between addon versions, existing saved profiles retain their old values — AceDB only applies defaults for keys that don't exist yet. If you need to force-update an existing value (e.g. `enabledDungeon` changed from `false` to `true`), add a migration guard in `OnInitialize`:

```lua
function LarsQOL:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New("LarsQOLDB", ns.Defaults, true)
    local r = self.db.profile.reminder
    -- Migrate: ensure new sub-tables exist
    for _, key in ipairs({"flasks","food","augmentRunes","weaponBuffs","custom","classBuffs","partyBuffs"}) do
        if not r[key] then r[key] = {} end
    end
    -- Migrate: force-update values whose defaults changed
    if r.enabledDungeon == false then r.enabledDungeon = true end
end
```

---

## Reference

- EllesmereUIAuraBuffReminders by Ellesmere — studied for API patterns, spell ID whitelists, and Midnight compatibility techniques. No code copied.
- Blizzard API reference: `_ref/` folder in workspace.
