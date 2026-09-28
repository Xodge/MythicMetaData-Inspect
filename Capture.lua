-- Capture.lua
-- The ONLY two ways data ever enters MMD-I's store:
--   1. Passive: hooking NotifyInspect to know who was asked about, then
--      actually capturing on INSPECT_READY once the server has answered
--      -- one unit at a time.
--   2. Active: /mmdi scan -- loops your current party/raid, calling the
--      same underlying API directly, no InspectFrame involved at all.
-- No periodic re-checks, no background polling, no reacting to roster
-- changes on their own. Both paths are hard-gated on combat lockout.
--
-- DATA SHAPE, UNCONFIRMED: C_PlayerInfo.GetPlayerMythicPlusRatingSummary
-- is documented to return a MythicPlusRatingSummary table with a score
-- and a list of completed runs, but the exact field names inside it
-- haven't been verified live (same category of thing that's bitten
-- this project before). Capture_ParseRatingSummary tries several
-- plausible field names rather than asserting one; /mmdi dump <unit>
-- prints the raw table so the real names can be confirmed and this
-- parser tightened up with certainty.

local ADDON_NAME, MMDI = ...

-- ---------------------------------------------------------------------
-- Context assignment -- reflects YOUR OWN group situation at the
-- moment of capture (that's what determines whether an inspect/scan is
-- even possible in the first place, per the "inspect already requires
-- being in range or in-group" constraint).
-- ---------------------------------------------------------------------

function MMDI.Capture_AssignContext()
    if IsInRaid() then
        return "Raid"
    end
    if C_ChallengeMode and C_ChallengeMode.GetActiveChallengeMapID and C_ChallengeMode.GetActiveChallengeMapID() then
        return "M+"
    end
    return "Group"
end

-- ---------------------------------------------------------------------
-- Parsing C_PlayerInfo.GetPlayerMythicPlusRatingSummary's return value
-- ---------------------------------------------------------------------

local SCORE_FIELD_CANDIDATES = { "currentSeasonScore", "overallScore", "score", "mythicPlusScore", "rating" }
local RUNS_FIELD_CANDIDATES = { "runs", "completedRuns", "runHistory", "seasonRuns" }
local RUN_MAPID_FIELD_CANDIDATES = { "mapChallengeModeID", "challengeModeID", "dungeonID", "mapID" }
local RUN_LEVEL_FIELD_CANDIDATES = { "bestRunLevel", "level", "keyLevel", "mythicLevel" }
-- CONFIRMED against the live API docs (Blizzard's MythicPlusRatingSummary /
-- MythicPlusRatingMapSummary shape): currentSeasonScore, runs[], and within
-- each run challengeModeID / bestRunLevel all match candidates already above,
-- so the guesswork this file's header worried about turned out fine. What's
-- new here is finishedSuccess -- a per-run field this parser wasn't reading
-- at all, meaning a depleted/failed key could get stored and displayed
-- identically to a completed one. Skip runs explicitly marked unfinished;
-- leave anything where the field itself is missing/unrecognized alone so a
-- future API shape change fails soft instead of silently dropping real runs.
local RUN_FINISHED_FIELD_CANDIDATES = { "finishedSuccess", "completed", "success" }

local function firstField(t, candidates)
    for _, name in ipairs(candidates) do
        if t[name] ~= nil then
            return t[name]
        end
    end
    return nil
end

-- Returns seasonScore, dungeons ({ [mapID] = { completed = n } }), or
-- nil, nil if the summary couldn't be read at all (API unavailable, or
-- no recognizable score/runs field found).
local function parseRatingSummary(unit)
    if not (C_PlayerInfo and C_PlayerInfo.GetPlayerMythicPlusRatingSummary) then
        return nil, nil
    end

    local ok, summary = pcall(C_PlayerInfo.GetPlayerMythicPlusRatingSummary, unit)
    if not ok or type(summary) ~= "table" then
        return nil, nil
    end

    local seasonScore = firstField(summary, SCORE_FIELD_CANDIDATES)
    local runsList = firstField(summary, RUNS_FIELD_CANDIDATES)

    local dungeons = {}
    if type(runsList) == "table" then
        for _, run in ipairs(runsList) do
            local mapID = firstField(run, RUN_MAPID_FIELD_CANDIDATES)
            local level = firstField(run, RUN_LEVEL_FIELD_CANDIDATES)
            local finished = firstField(run, RUN_FINISHED_FIELD_CANDIDATES)
            -- finished == false means Blizzard explicitly told us this run
            -- was depleted/abandoned; finished == nil means the field wasn't
            -- found at all (old behavior, unchanged). Either way, only a
            -- confirmed false is excluded.
            if mapID and level and finished ~= false then
                -- Keep the highest level seen per dungeon, in case the
                -- runs list isn't already deduplicated/best-only.
                dungeons[mapID] = { completed = math.max((dungeons[mapID] or {}).completed or 0, level) }
            end
        end
    end

    return seasonScore, dungeons
end

-- ---------------------------------------------------------------------
-- Shared capture routine -- used by both the Inspect hook and /mmdi scan.
-- ---------------------------------------------------------------------

function MMDI.Capture_Unit(unit)
    if InCombatLockdown() then
        if MMDI.db and MMDI.db.debug then
            print("|cff888888MMDI debug|r: Capture_Unit(" .. tostring(unit) .. ") aborted -- in combat")
        end
        return -- hard gate: never capture in combat, no exceptions
    end
    if not UnitExists(unit) or not UnitIsPlayer(unit) then
        if MMDI.db and MMDI.db.debug then
            print("|cff888888MMDI debug|r: Capture_Unit(" .. tostring(unit) .. ") aborted -- unit doesn't exist or isn't a player")
        end
        return
    end

    local name, realm = UnitName(unit)
    if not name then
        if MMDI.db and MMDI.db.debug then
            print("|cff888888MMDI debug|r: Capture_Unit(" .. tostring(unit) .. ") aborted -- UnitName returned nothing")
        end
        return
    end
    realm = (realm and realm ~= "") and realm or GetRealmName()
    local charKey = name .. "-" .. realm

    local seasonScore, dungeons = parseRatingSummary(unit)
    local dungeonCount = 0
    if dungeons then
        for _ in pairs(dungeons) do dungeonCount = dungeonCount + 1 end
    end
    if seasonScore == nil and dungeonCount == 0 then
        if MMDI.db and MMDI.db.debug then
            print(string.format(
                "|cff888888MMDI debug|r: Capture_Unit(%s / %s) got NOTHING usable from GetPlayerMythicPlusRatingSummary -- run /mmdi dump %s to see the raw table",
                tostring(unit), charKey, tostring(unit)))
        end
        return -- nothing usable came back; don't overwrite a possibly-better existing entry with emptiness
    end

    MMDI.db.entries[charKey] = {
        addedAt = GetServerTime(), -- fresh capture always resets the clock
        holdUntil = nil,           -- and clears any prior hold -- new data supersedes an old hold
        context = MMDI.Capture_AssignContext(),
        seasonScore = seasonScore,
        dungeons = dungeons or {},
    }

    if MMDI.db and MMDI.db.debug then
        print(string.format("|cff888888MMDI debug|r: Capture_Unit stored %s -- score=%s, dungeons=%d",
            charKey, tostring(seasonScore), dungeonCount))
    end
end

-- Passive path: THIS WAS THE BUG. NotifyInspect only sends the request to
-- the server -- per Blizzard's own docs it "triggers INSPECT_READY when
-- information is asynchronously available," same as the talent handshake
-- every other inspect addon has to wait on. Capturing inside the
-- NotifyInspect hook itself, as this used to do, read
-- GetPlayerMythicPlusRatingSummary before the response had come back, so it
-- only worked when the client happened to already have a cached answer for
-- that person (e.g. inspected them moments earlier). That's exactly the
-- "sometimes works, mostly doesn't" pattern -- it was a race against network
-- latency, not a parsing problem. Now: record who we asked and their GUID,
-- then capture only once INSPECT_READY confirms that unit's data is in.
local pendingInspect = nil -- { unit = <token at request time>, guid = <their GUID> }

hooksecurefunc("NotifyInspect", function(unit)
    if not (MMDI.IsFullyLoaded and MMDI.IsFullyLoaded()) then return end
    local guid = UnitGUID(unit)
    if guid then
        pendingInspect = { unit = unit, guid = guid }
        if MMDI.db and MMDI.db.debug then
            print(string.format("|cff888888MMDI debug|r: NotifyInspect(%s) -- guid=%s, awaiting INSPECT_READY", unit, guid))
        end
    elseif MMDI.db and MMDI.db.debug then
        print("|cff888888MMDI debug|r: NotifyInspect(" .. tostring(unit) .. ") -- UnitGUID returned nothing, not tracking this request")
    end
end)

-- The unit token captured at request time (e.g. "target") may no longer
-- point at the same person by the time INSPECT_READY fires -- target could
-- have changed, or scrolled off in a raid frame click. Re-resolve by GUID
-- across the places an inspect could plausibly have come from.
local function resolveUnitByGUID(guid)
    if pendingInspect and UnitGUID(pendingInspect.unit) == guid then
        return pendingInspect.unit
    end
    if UnitGUID("target") == guid then return "target" end
    if UnitGUID("mouseover") == guid then return "mouseover" end
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local u = "raid" .. i
            if UnitGUID(u) == guid then return u end
        end
    elseif IsInGroup() then
        for i = 1, 4 do
            local u = "party" .. i
            if UnitGUID(u) == guid then return u end
        end
    end
    return nil
end

local inspectReadyFrame = CreateFrame("Frame")
inspectReadyFrame:RegisterEvent("INSPECT_READY")
inspectReadyFrame:SetScript("OnEvent", function(_, _, guid)
    if not (MMDI.IsFullyLoaded and MMDI.IsFullyLoaded()) then return end
    local debugOn = MMDI.db and MMDI.db.debug
    if not pendingInspect then
        if debugOn then print("|cff888888MMDI debug|r: INSPECT_READY(" .. tostring(guid) .. ") -- no pending request, ignoring") end
        return
    end
    if pendingInspect.guid ~= guid then
        if debugOn then
            print(string.format("|cff888888MMDI debug|r: INSPECT_READY(%s) -- doesn't match pending %s, ignoring",
                tostring(guid), tostring(pendingInspect.guid)))
        end
        return -- an inspect this session didn't request, or a stale signal
    end
    local unit = resolveUnitByGUID(guid)
    if debugOn then
        print(string.format("|cff888888MMDI debug|r: INSPECT_READY(%s) matched -- resolved unit=%s", guid, tostring(unit)))
    end
    pendingInspect = nil
    if unit then
        MMDI.Capture_Unit(unit)
    end
end)

-- Combat start: hard shutdown, no exceptions, matches the reasoning
-- that there's no conceivable legitimate use of this addon mid-pull.
local combatGateFrame = CreateFrame("Frame")
combatGateFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
combatGateFrame:SetScript("OnEvent", function()
    if MMDI.ReviewUI_Hide then MMDI.ReviewUI_Hide() end
    if MMDI.UI_Hide then MMDI.UI_Hide() end
end)

-- Active path: /mmdi scan. Loops whatever group you're currently in --
-- party or raid -- calling the same capture routine per member. Never
-- runs on its own; only in direct response to the command.
function MMDI.Capture_Scan()
    if InCombatLockdown() then
        print("|cffff5555MMDI|r: not scanning in combat.")
        return
    end

    local count = 0
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local unit = "raid" .. i
            if UnitExists(unit) and not UnitIsUnit(unit, "player") then
                MMDI.Capture_Unit(unit)
                count = count + 1
            end
        end
    elseif IsInGroup() then
        for i = 1, 4 do
            local unit = "party" .. i
            if UnitExists(unit) then
                MMDI.Capture_Unit(unit)
                count = count + 1
            end
        end
    else
        print("|cff66ccffMMDI|r: not in a group.")
        return
    end

    print(string.format("|cff66ccffMMDI|r: scanned %d group member(s).", count))
end

-- Diagnostic only: forces a real capture on the player's own unit,
-- through the SAME pipeline a real inspect or scan uses (context
-- assignment, parsing, storage) -- bypassing the need to be in a group
-- and inspect someone else just to test that the mechanism works.
-- Reports directly from the stored entry, not through the merge view,
-- since Merge_GetList deliberately suppresses an inspected entry
-- whenever a tracked entry exists for that name -- and the player's
-- own name is always tracked, so testing through /mmdi show would
-- always show "only the guild stuff" regardless of whether capture
-- itself succeeded.
function MMDI.Capture_Test()
    if InCombatLockdown() then
        print("|cffff5555MMDI|r: not available in combat.")
        return
    end

    MMDI.Capture_Unit("player")

    local name, realm = UnitName("player")
    realm = (realm and realm ~= "") and realm or GetRealmName()
    local charKey = name .. "-" .. realm
    local entry = MMDI.db.entries[charKey]

    if not entry then
        print("|cffff5555MMDI|r test: capture produced nothing -- check /mmdi dump player for the raw API response.")
        return
    end

    local dungeonCount = 0
    for _ in pairs(entry.dungeons or {}) do dungeonCount = dungeonCount + 1 end

    print(string.format(
        "|cff66ccffMMDI|r test: captured %s -- context=%s, score=%s, dungeons with data=%d",
        charKey, entry.context, tostring(entry.seasonScore), dungeonCount))
end

-- Diagnostic only: prints the raw summary table for a given unit (target
-- by default) so the real field names can be confirmed and the
-- candidate lists above tightened with certainty.
function MMDI.Capture_DumpUnit(unit)
    if not (C_PlayerInfo and C_PlayerInfo.GetPlayerMythicPlusRatingSummary) then
        print("|cff66ccffMMDI|r: C_PlayerInfo.GetPlayerMythicPlusRatingSummary not available.")
        return
    end
    local ok, summary = pcall(C_PlayerInfo.GetPlayerMythicPlusRatingSummary, unit)
    print(string.format("|cff66ccffMMDI|r dump(%s): ok=%s type=%s", unit, tostring(ok), type(summary)))
    if ok and type(summary) == "table" then
        for k, v in pairs(summary) do
            print(string.format("  %s = %s (%s)", tostring(k), tostring(v), type(v)))
        end
    end
end
