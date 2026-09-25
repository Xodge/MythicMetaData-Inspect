-- Purge.lua
-- Flat eligibility window, no per-context timers. Nothing is ever
-- deleted automatically -- eligibility just means "/mmdi purge would
-- remove this if run right now." A held entry (holdUntil in the
-- future, set via /mmdi review) is skipped regardless of age.

local ADDON_NAME, MMDI = ...

MMDI.PURGE_SECONDS = 4 * 3600  -- eligible for purge 4 hours after capture
MMDI.HOLD_SECONDS = 24 * 3600  -- a "do not purge" hold lasts 24 hours before re-entering eligibility

function MMDI.Purge_IsEligible(entry)
    local now = GetServerTime()
    if now < (entry.addedAt or 0) + MMDI.PURGE_SECONDS then
        return false -- too new
    end
    if entry.holdUntil and now < entry.holdUntil then
        return false -- actively held
    end
    return true
end

-- Returns { {charKey=, entry=}, ... } for every currently-eligible
-- entry, sorted by name. Used by /mmdi review to build its list.
function MMDI.Purge_GetEligibleList()
    local list = {}
    for charKey, entry in pairs(MMDI.db.entries) do
        if MMDI.Purge_IsEligible(entry) then
            table.insert(list, { charKey = charKey, entry = entry })
        end
    end
    table.sort(list, function(a, b) return a.charKey < b.charKey end)
    return list
end

-- Removes every eligible-and-not-held entry. Only ever runs in direct
-- response to /mmdi purge -- never on a timer, never at login.
function MMDI.Purge_Run()
    local removed = 0
    for charKey, entry in pairs(MMDI.db.entries) do
        if MMDI.Purge_IsEligible(entry) then
            MMDI.db.entries[charKey] = nil
            removed = removed + 1
        end
    end
    print(string.format("|cff66ccffMMDI|r: purged %d record(s).", removed))
end
