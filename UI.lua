-- UI.lua
-- MMD-I's own window, fully independent of MMD's UI.lua. This is the
-- other side of the decoupling decision: rather than MMD's code
-- knowing anything about MMD-I, MMD-I reads MMD's PUBLIC DATA
-- (MMD.gdb.characters, guaranteed present since MMD is a required
-- dependency) and merges it with its own local entries itself, in its
-- own window. If MMD-I's data shape or display ever changes, MMD's own
-- files never need to change to match -- the coupling only runs one
-- direction, and only against MMD.gdb.characters's documented shape
-- (see MMD's own Core.lua), not against any of MMD's internal code.
--
-- Deliberately independent rather than reused from MMD:
--   - Own bundled copy of the monospace font (not a path into MMD's
--     folder -- MMD's internal file layout could change without
--     warning; this way MMD-I doesn't care).
--   - Own dungeon-name derivation via the same public Blizzard API MMD
--     uses (C_ChallengeMode.GetMapTable/GetMapUIInfo), rather than
--     reading MMD.db.dungeons (now MMD.gdb.dungeons) -- one less thing tying MMD-I to MMD's
--     internal table shape.
--
-- Per the standing decision for this tool: NO current-key line, for
-- either tracked or inspected rows -- "we can always ask."

local ADDON_NAME, MMDI = ...

local ROW_HEIGHT = 20
local NAME_COL_WIDTH = 22
local COMPLETED_COL_WIDTH = 6

local expandedState = {}
local frame

local MMDI_MONO_FONT = CreateFont("MMDIMonoFont")
MMDI_MONO_FONT:SetFont("Interface\\AddOns\\MythicMetaData-Inspect\\Fonts\\SourceCodePro-Regular.ttf", 11, "")
MMDI_MONO_FONT:SetTextColor(1, 1, 1)

-- ---------------------------------------------------------------------
-- Own dungeon-name cache -- independent of MMD's, deliberately.
-- ---------------------------------------------------------------------

local dungeonNames = {} -- [mapID] = name

local function refreshDungeonCache()
    if C_MythicPlus and C_MythicPlus.RequestMapInfo then
        C_MythicPlus.RequestMapInfo()
    end
    if not (C_ChallengeMode and C_ChallengeMode.GetMapTable) then return end
    for _, mapID in ipairs(C_ChallengeMode.GetMapTable() or {}) do
        local name = C_ChallengeMode.GetMapUIInfo(mapID)
        if name then dungeonNames[mapID] = name end
    end
end

local function getSortedDungeonList()
    local list = {}
    for mapID, name in pairs(dungeonNames) do
        table.insert(list, { mapID = mapID, name = name })
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

-- ---------------------------------------------------------------------
-- Merge: MMD's tracked characters (read-only) + MMD-I's own local
-- entries, skipping any inspected entry whose name already has a real
-- tracked record (richer data always wins).
-- ---------------------------------------------------------------------

function MMDI.Merge_GetList()
    local list = {}

    if MMD and MMD.gdb and MMD.gdb.characters then
        for charKey, record in pairs(MMD.gdb.characters) do
            table.insert(list, { charKey = charKey, source = "tracked", record = record })
        end
    end

    for charKey, entry in pairs(MMDI.db.entries) do
        if not (MMD and MMD.gdb and MMD.gdb.characters and MMD.gdb.characters[charKey]) then
            table.insert(list, { charKey = charKey, source = "inspected", entry = entry })
        end
    end

    table.sort(list, function(a, b) return a.charKey < b.charKey end)
    return list
end

-- ---------------------------------------------------------------------
-- Row formatting
-- ---------------------------------------------------------------------

-- Duplicated from MMD's own UI.lua (that function is private to its
-- file) rather than reused, per the decoupling decision -- MMD-I reads
-- only MMD.gdb.characters's documented shape, never MMD's internal
-- code. Uses this file's own independently-derived dungeonNames cache
-- for the name lookup, not MMD.db.dungeons.
local function formatCurrentKeyLine(record)
    if not record.currentKey then
        return "Idle - no key held"
    end
    local ck = record.currentKey
    local dungeonName = dungeonNames[ck.mapID] or ("Map " .. tostring(ck.mapID))
    local keyText = string.format("%s +%s", dungeonName, tostring(ck.level))

    if ck.inProgress then
        local elapsedMin = math.floor((GetServerTime() - (ck.startedAt or GetServerTime())) / 60)
        local status = string.format("In Progress, %dm", elapsedMin)
        if ck.mayNotBeOwnKey then
            keyText = keyText .. " (may not be own key)"
        end
        return string.format("%s -- %s", status, keyText)
    end

    return keyText
end

-- Tracked rows: full current-key line, matching MMD's own /mmd show
-- exactly. Inspected rows: the key portion is replaced outright with
-- the literal word INSPECTED, so the two data sources are unmistakable
-- at a glance in the same list -- context and capture age still shown
-- alongside it, just never anything that could be mistaken for a real
-- current-key reading.
local function formatHeaderLine(item)
    if item.source == "tracked" then
        return string.format("%s: %s", item.charKey, formatCurrentKeyLine(item.record))
    end
    local entry = item.entry
    local mins = math.floor((GetServerTime() - (entry.addedAt or GetServerTime())) / 60)
    local ageStr = mins < 60 and (mins .. "m ago") or (string.format("%.1fh ago", mins / 60))
    local scoreStr = entry.seasonScore and (", score " .. entry.seasonScore) or ""
    return string.format("%s: INSPECTED (%s, captured %s%s)", item.charKey, entry.context or "?", ageStr, scoreStr)
end

-- Returns the stats string for a dungeon row, or nil to skip the row
-- entirely. Tracked entries show a placeholder for never-attempted
-- (matching MMD's own convention); inspected entries skip missing rows
-- outright (matching this tool's specific display decision).
local function formatDungeonStats(item, mapID)
    if item.source == "tracked" then
        local d = item.record.dungeons[mapID]
        if not d then
            return string.format("%" .. COMPLETED_COL_WIDTH .. "s", "-")
        end
        if d.abandoned and not d.completed and not d.depleted then
            return "Abandoned"
        end
        local completedStr = d.completed and ("+" .. d.completed) or "-"
        local stats = string.format("%" .. COMPLETED_COL_WIDTH .. "s", completedStr)
        if d.depleted then
            stats = stats .. string.format("  (failed +%d)", d.depleted)
        end
        return stats
    else
        local d = item.entry.dungeons and item.entry.dungeons[mapID]
        if not d or not d.completed then
            return nil -- skip: inspected entries omit missing runs entirely
        end
        return string.format("%" .. COMPLETED_COL_WIDTH .. "s", "+" .. d.completed)
    end
end

-- ---------------------------------------------------------------------
-- Frame construction (same conventions as MMD's own window, built
-- independently)
-- ---------------------------------------------------------------------

local function createFrame()
    local f = CreateFrame("Frame", "MythicMetaDataInspectMergeFrame", UIParent, "BackdropTemplate")
    f:SetSize(420, 320)
    f:SetPoint("TOPRIGHT", -540, -100)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetClampedToScreen(true)

    if f.SetBackdrop then
        f:SetBackdrop({
            bgFile = "Interface/Tooltips/UI-Tooltip-Background",
            edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
            edgeSize = 12,
            insets = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        f:SetBackdropColor(0, 0, 0, 0.85)
    end

    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

    local titleBar = CreateFrame("Frame", nil, f)
    titleBar:SetPoint("TOPLEFT", 0, 0)
    titleBar:SetPoint("TOPRIGHT", 0, 0)
    titleBar:SetHeight(24)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() f:StartMoving() end)
    titleBar:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)

    local title = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("LEFT", 8, 0)
    title:SetText("Mythic Meta Data - Inspect")

    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -4, -4)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    local expandAllBtn = CreateFrame("Button", nil, titleBar, "UIPanelButtonTemplate")
    expandAllBtn:SetSize(80, 20)
    expandAllBtn:SetPoint("RIGHT", closeBtn, "LEFT", -4, 0)
    expandAllBtn:SetText("Expand All")
    expandAllBtn:SetScript("OnClick", function()
        local list = MMDI.Merge_GetList()
        local allOpen = true
        for _, item in ipairs(list) do
            if not expandedState[item.charKey] then allOpen = false end
        end
        for _, item in ipairs(list) do
            expandedState[item.charKey] = not allOpen
        end
        MMDI.UI_Refresh()
    end)

    local scrollFrame = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 8, -28)
    scrollFrame:SetPoint("BOTTOMRIGHT", -28, 8)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(1, 1)
    scrollFrame:SetScrollChild(content)
    content:SetWidth(scrollFrame:GetWidth())

    f.scrollFrame = scrollFrame
    f.content = content
    content.rowPool = {}

    f:Hide()
    return f
end

local function acquireRow(index, parent)
    local row = parent.rowPool[index]
    if not row then
        row = CreateFrame("Button", nil, parent)
        row:SetHeight(ROW_HEIGHT)
        row:SetPoint("LEFT", parent, "LEFT", 0, 0)
        row:SetPoint("RIGHT", parent, "RIGHT", 0, 0)

        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.text:SetPoint("LEFT", 4, 0)
        row.text:SetJustifyH("LEFT")
        row.text:SetPoint("RIGHT", -4, 0)

        row.divider = row:CreateTexture(nil, "ARTWORK")
        row.divider:SetColorTexture(1, 1, 1, 0.15)
        row.divider:SetWidth(1)
        row.divider:SetPoint("TOP", row, "TOP", 0, 0)
        row.divider:SetPoint("BOTTOM", row, "BOTTOM", 0, 0)
        row.divider:Hide()

        parent.rowPool[index] = row
    end
    row:Show()
    return row
end

function MMDI.UI_Refresh()
    if not frame or not frame:IsShown() then return end

    refreshDungeonCache()

    local content = frame.content
    content:SetWidth(frame.scrollFrame:GetWidth())
    local yOffset, rowIndex = 0, 0

    for _, item in ipairs(MMDI.Merge_GetList()) do
        rowIndex = rowIndex + 1
        local headerRow = acquireRow(rowIndex, content)
        headerRow:ClearAllPoints()
        headerRow:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -yOffset)
        headerRow:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -yOffset)
        headerRow.text:SetFontObject(GameFontHighlightSmall)
        headerRow.divider:Hide()

        local arrow = expandedState[item.charKey] and "v " or "> "
        headerRow.text:SetText(arrow .. formatHeaderLine(item))

        headerRow:SetScript("OnClick", function()
            expandedState[item.charKey] = not expandedState[item.charKey]
            MMDI.UI_Refresh()
        end)

        yOffset = yOffset + ROW_HEIGHT

        if expandedState[item.charKey] then
            for _, dungeon in ipairs(getSortedDungeonList()) do
                local stats = formatDungeonStats(item, dungeon.mapID)
                if stats then
                    rowIndex = rowIndex + 1
                    local detailRow = acquireRow(rowIndex, content)
                    detailRow:ClearAllPoints()
                    detailRow:SetPoint("TOPLEFT", content, "TOPLEFT", 16, -yOffset)
                    detailRow:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -yOffset)
                    detailRow:SetScript("OnClick", nil)
                    detailRow.text:SetFontObject(MMDI_MONO_FONT)

                    local nameCol = string.format("%-" .. NAME_COL_WIDTH .. "s", dungeon.name .. ":")
                    detailRow.text:SetText(nameCol)
                    local dividerX = 4 + detailRow.text:GetStringWidth() + 3
                    detailRow.divider:ClearAllPoints()
                    detailRow.divider:SetPoint("TOP", detailRow, "TOP", 0, 0)
                    detailRow.divider:SetPoint("BOTTOM", detailRow, "BOTTOM", 0, 0)
                    detailRow.divider:SetPoint("LEFT", detailRow, "LEFT", dividerX, 0)
                    detailRow.divider:Show()

                    detailRow.text:SetText(nameCol .. stats)
                    yOffset = yOffset + ROW_HEIGHT
                end
            end
        end
    end

    for i = rowIndex + 1, #content.rowPool do
        content.rowPool[i]:Hide()
    end
    content:SetHeight(math.max(yOffset, 1))
end

function MMDI.UI_Show()
    if not frame then
        frame = createFrame()
    end
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
        MMDI.UI_Refresh()
    end
end

function MMDI.UI_Hide()
    if frame then frame:Hide() end
end
