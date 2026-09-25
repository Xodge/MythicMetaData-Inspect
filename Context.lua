-- Context.lua
-- Relabels entries already sitting at "Group" context to "M+" or
-- "Raid" as the group's situation changes -- pure metadata correction
-- on existing entries, never a new capture, never touching Inspect
-- data or anyone's Blizzard-side info again.
--
-- The Raid relabel is the ONE deliberate exception to "shut everything
-- down in combat": it's a local table write, not anything touching
-- secure/protected UI (unlike InspectFrame or anything anchored to
-- it), so combat lockdown has nothing to say about it.

local ADDON_NAME, MMDI = ...

-- Builds a set of charKeys ("Name-Realm") currently in your party or
-- raid, for matching against stored entries.
local function getCurrentGroupCharKeys()
    local keys = {}
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local unit = "raid" .. i
            if UnitExists(unit) and not UnitIsUnit(unit, "player") then
                local name, realm = UnitName(unit)
                if name then
                    realm = (realm and realm ~= "") and realm or GetRealmName()
                    keys[name .. "-" .. realm] = true
                end
            end
        end
    elseif IsInGroup() then
        for i = 1, 4 do
            local unit = "party" .. i
            if UnitExists(unit) then
                local name, realm = UnitName(unit)
                if name then
                    realm = (realm and realm ~= "") and realm or GetRealmName()
                    keys[name .. "-" .. realm] = true
                end
            end
        end
    end
    return keys
end

local function relabel(newContext)
    local currentGroup = getCurrentGroupCharKeys()
    for charKey, entry in pairs(MMDI.db.entries) do
        if entry.context == "Group" and currentGroup[charKey] then
            entry.context = newContext
        end
    end
end

-- Group -> M+: fires the instant a key starts, no combat wait needed
-- (this isn't the case being guarded against -- see file header).
function MMDI.Context_OnChallengeModeStart()
    relabel("M+")
end

-- Group -> Raid: only at first combat, and only while actually in a
-- raid group -- deliberately NOT locked in the moment a group converts
-- to raid, since a >5-person group can convert to raid and back to
-- party without ever fighting anything, and that shouldn't count.
function MMDI.Context_OnCombatStart()
    if IsInRaid() then
        relabel("Raid")
    end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("CHALLENGE_MODE_START")
frame:RegisterEvent("PLAYER_REGEN_DISABLED")
frame:SetScript("OnEvent", function(_, event)
    if not (MMDI.IsFullyLoaded and MMDI.IsFullyLoaded()) then return end
    if event == "CHALLENGE_MODE_START" then
        MMDI.Context_OnChallengeModeStart()
    elseif event == "PLAYER_REGEN_DISABLED" then
        MMDI.Context_OnCombatStart()
    end
end)
