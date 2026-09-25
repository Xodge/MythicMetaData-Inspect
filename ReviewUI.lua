-- ReviewUI.lua
-- /mmdi review: a small window listing every currently purge-eligible
-- entry, each with a checkbox that sets a 24-hour hold instead of
-- letting it be removed by the next /mmdi purge. Closes immediately on
-- combat start, same as everything else in this addon -- there's no
-- legitimate reason to be reviewing this list mid-fight.

local ADDON_NAME, MMDI = ...

local frame
local ROW_HEIGHT = 22

local function buildRow(index, parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -((index - 1) * ROW_HEIGHT))
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -((index - 1) * ROW_HEIGHT))

    row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    row.check:SetSize(20, 20)
    row.check:SetPoint("LEFT", 4, 0)

    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.text:SetPoint("LEFT", row.check, "RIGHT", 4, 0)
    row.text:SetJustifyH("LEFT")
    row.text:SetPoint("RIGHT", -4, 0)

    return row
end

local function createFrame()
    local f = CreateFrame("Frame", "MythicMetaDataInspectReviewFrame", UIParent, "BackdropTemplate")
    f:SetSize(380, 300)
    f:SetPoint("CENTER")
    f:SetMovable(true)
    f:EnableMouse(true)
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
    title:SetText("MMDI: Purge Review")

    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -4, -4)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    local doneBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    doneBtn:SetSize(80, 22)
    doneBtn:SetPoint("BOTTOMRIGHT", -8, 8)
    doneBtn:SetText("Done")
    doneBtn:SetScript("OnClick", function() f:Hide() end)

    local scrollFrame = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 8, -28)
    scrollFrame:SetPoint("BOTTOMRIGHT", -28, 36)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(1, 1)
    scrollFrame:SetScrollChild(content)
    content:SetWidth(scrollFrame:GetWidth())

    f.content = content
    f.rowPool = {}
    f:Hide()
    return f
end

local function formatAge(addedAt)
    local mins = math.floor((GetServerTime() - addedAt) / 60)
    if mins < 60 then return mins .. "m ago" end
    return string.format("%.1fh ago", mins / 60)
end

local function refresh()
    if not frame then return end

    local list = MMDI.Purge_GetEligibleList()
    local content = frame.content
    content:SetWidth(frame:GetWidth() - 40)

    for i, item in ipairs(list) do
        local row = frame.rowPool[i]
        if not row then
            row = buildRow(i, content)
            frame.rowPool[i] = row
        end
        row:Show()
        row.text:SetText(string.format("%s  [%s]  %s", item.charKey, item.entry.context, formatAge(item.entry.addedAt)))
        row.check:SetChecked(false)
        row.check:SetScript("OnClick", function(self)
            if self:GetChecked() then
                item.entry.holdUntil = GetServerTime() + MMDI.HOLD_SECONDS
            else
                item.entry.holdUntil = nil
            end
        end)
    end

    for i = #list + 1, #frame.rowPool do
        frame.rowPool[i]:Hide()
    end

    content:SetHeight(math.max(#list * ROW_HEIGHT, 1))

    if #list == 0 then
        print("|cff66ccffMMDI|r: nothing currently eligible for purge.")
    end
end

function MMDI.ReviewUI_Show()
    if InCombatLockdown() then
        print("|cffff5555MMDI|r: not available in combat.")
        return
    end
    if not frame then
        frame = createFrame()
    end
    frame:Show()
    refresh()
end

function MMDI.ReviewUI_Hide()
    if frame then
        frame:Hide()
    end
end
