-- Core.lua
-- Addon-wide namespace, SavedVariables bootstrap, and slash command
-- dispatch for Mythic Meta Data - Inspect (MMD-I).
--
-- MMD-I is deliberately a SEPARATE, LOCAL-ONLY tool: it never syncs
-- anything to anyone, never writes into MMD's own guild-tracked
-- MMD.db.characters, and only ever captures data through two explicit,
-- user-initiated paths -- inspecting someone, or /mmdi scan. No
-- background polling, no automatic scanning, ever.

local ADDON_NAME, MMDI = ...
_G.MMDI = MMDI -- convenient global for debugging via /run

-- ---------------------------------------------------------------------
-- SavedVariables shape:
--
-- MythicMetaDataInspectDB = {
--   entries = {
--     ["Name-Realm"] = {
--       addedAt = <epoch>,               -- capture time; refreshed on every re-capture
--       context = "Group" | "M+" | "Raid",  -- inferred at capture, may be relabeled later (see Context.lua)
--       holdUntil = <epoch> or nil,      -- set via /mmdi review's "do not purge" checkbox
--       seasonScore = <number> or nil,
--       dungeons = { [mapID] = { completed = n }, ... },  -- completed only; Blizzard doesn't expose others' fails
--     },
--   },
-- }
--
-- No checksum, no lastUpdated-for-sync -- this table is never
-- broadcast, so none of MMD's sync machinery applies here.
-- ---------------------------------------------------------------------

local DEFAULTS = {
    entries = {},
}

local function applyDefaults(db, defaults)
    for k, v in pairs(defaults) do
        if db[k] == nil then
            if type(v) == "table" then
                db[k] = {}
                applyDefaults(db[k], v)
            else
                db[k] = v
            end
        elseif type(v) == "table" and type(db[k]) == "table" then
            applyDefaults(db[k], v)
        end
    end
end

local loaderFrame = CreateFrame("Frame")
loaderFrame:RegisterEvent("ADDON_LOADED")
loaderFrame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        MythicMetaDataInspectDB = MythicMetaDataInspectDB or {}
        applyDefaults(MythicMetaDataInspectDB, DEFAULTS)
        MMDI.db = MythicMetaDataInspectDB
        MMDI.SelfCheck()
    end
end)

-- ---------------------------------------------------------------------
-- Self-check -- same pattern as MMD's: names a missing file instead of
-- letting it surface later as a confusing nil-call.
-- ---------------------------------------------------------------------

local EXPECTED_FUNCTIONS = {
    ["Capture.lua"] = { "Capture_Unit", "Capture_Scan", "Capture_AssignContext", "Capture_DumpUnit", "Capture_Test" },
    ["Context.lua"] = { "Context_OnChallengeModeStart", "Context_OnCombatStart" },
    ["Purge.lua"] = { "Purge_IsEligible", "Purge_Run", "Purge_GetEligibleList" },
    ["ReviewUI.lua"] = { "ReviewUI_Show", "ReviewUI_Hide" },
    ["UI.lua"] = { "UI_Show", "UI_Refresh", "UI_Hide", "Merge_GetList" },
}

function MMDI.SelfCheck()
    local missingFiles = {}
    for fileName, functionNames in pairs(EXPECTED_FUNCTIONS) do
        for _, fnName in ipairs(functionNames) do
            if MMDI[fnName] == nil then
                missingFiles[fileName] = true
                break
            end
        end
    end

    if next(missingFiles) then
        MMDI.loadOK = false
        local names = {}
        for fileName in pairs(missingFiles) do table.insert(names, fileName) end
        table.sort(names)
        print("|cffff5555MMDI|r: the following file(s) did not load correctly: " ..
            table.concat(names, ", ") ..
            ". Re-check your AddOns/MythicMetaData-Inspect folder.")
    else
        MMDI.loadOK = true
    end
end

function MMDI.IsFullyLoaded()
    return MMDI.loadOK == true
end

-- ---------------------------------------------------------------------
-- Slash commands
-- ---------------------------------------------------------------------

SLASH_MYTHICMETADATAINSPECT1 = "/mmdi"
SlashCmdList["MYTHICMETADATAINSPECT"] = function(msg)
    if not MMDI.IsFullyLoaded() then
        print("|cffff5555MMDI|r: addon did not load cleanly this session; commands disabled until that's resolved.")
        return
    end

    local args = {}
    for word in msg:gmatch("%S+") do
        table.insert(args, word)
    end
    local cmd = (args[1] or ""):lower()

    if cmd == "scan" then
        MMDI.Capture_Scan()
    elseif cmd == "show" then
        MMDI.UI_Show()
    elseif cmd == "purge" then
        MMDI.Purge_Run()
    elseif cmd == "review" then
        MMDI.ReviewUI_Show()
    elseif cmd == "dump" then
        MMDI.Capture_DumpUnit(args[2] or "target")
    elseif cmd == "test" then
        MMDI.Capture_Test()
    else
        print("|cff66ccffMMDI|r commands: scan, show, review, purge, test")
    end
end
