local _, ns = ...

local WIDTH, HEIGHT = 210, 200
local MIN_W, MIN_H, MAX_W, MAX_H = 180, 120, 400, 600
local HEADER_H, FOOTER_H, ROW_H, PAD = 22, 18, 18, 6
local ORB, ORB_INSET = 18, 3
local BODY_TOP = 1 + HEADER_H + PAD
local BODY_BOTTOM = PAD + 3 + FOOTER_H + PAD
local WHITE = "Interface\\Buttons\\WHITE8x8"
local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local QUESTION_MARK = "Interface\\Icons\\INV_Misc_QuestionMark"
local DIM = 0.5

local STATUS = {
    ok = { 0.45, 0.45, 0.45, "Macro is up to date." },
    pending = { 1, 0.7, 0.2, "In combat - macro updates when combat ends." },
    missing = { 1, 0.25, 0.25, "Macro missing - free a character macro slot, then /dtp." },
    stale = { 1, 0.25, 0.25, "Macro out of date - the list is too long." },
}

local accent = { r = 1, g = 1, b = 1 }
local frame, header, body, footer, grip, orb
local dot, priority, clear, input, placeholder
local empty, thumb, dropLine, budget
local expandedOnly = {}
local rows = {}
local offset = 0
local dragFrom, dropAt, dragElapsed
local Refresh

local function UIDB()
    local d = ns.DB()
    d.ui = d.ui or {}
    return d.ui
end

local function Tint(b)
    if b.active then
        b.label:SetTextColor(accent.r, accent.g, accent.b)
    else
        b.label:SetTextColor(DIM, DIM, DIM)
    end
end

local function ShowTooltip(owner, title, ...)
    GameTooltip:SetOwner(owner, "ANCHOR_TOP")
    GameTooltip:SetText(title, 1, 1, 1)
    for i = 1, select("#", ...) do
        GameTooltip:AddLine((select(i, ...)), nil, nil, nil, true)
    end
    GameTooltip:Show()
end

local function GlyphButton(parent, text, onClick, tooltip)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(14, HEADER_H)
    b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.label:SetPoint("CENTER")
    b.label:SetText(text)
    Tint(b)
    b:SetScript("OnClick", onClick)
    b:SetScript("OnEnter", function(self)
        self.label:SetTextColor(1, 1, 1)
        if tooltip then tooltip(self) end
    end)
    b:SetScript("OnLeave", function(self)
        Tint(self)
        GameTooltip:Hide()
    end)
    return b
end

local function SavePosition()
    local ui = UIDB()
    frame:StopMovingOrSizing()
    ui.x, ui.y = frame:GetLeft(), frame:GetTop()
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", ui.x, ui.y)
end

local function StartMove()
    frame:StartMoving()
end

local function RestorePosition()
    local ui = UIDB()
    frame:ClearAllPoints()
    if ui.x and ui.y then
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", ui.x, ui.y)
    else
        frame:SetPoint("TOP", UIParent, "TOP", 0, -180)
    end
end

local function ApplyLayout()
    local ui = UIDB()
    local collapsed = ui.collapsed
    local small = ORB + 2 * ORB_INSET
    frame:SetResizeBounds(collapsed and small or MIN_W, collapsed and small or MIN_H, MAX_W, MAX_H)
    if collapsed then
        frame:SetSize(small, small)
    else
        frame:SetSize(ui.w or WIDTH, ui.h or HEIGHT)
    end
    frame:SetBackdropColor(0.05, 0.05, 0.06, collapsed and 0 or 0.88)
    frame:SetBackdropBorderColor(0, 0, 0, collapsed and 0 or 1)
    frame:EnableMouse(not collapsed)
    for _, region in ipairs(expandedOnly) do
        region:SetShown(not collapsed)
    end
    -- The orb is meant to persist, so Esc should only close the expanded window.
    tDeleteItem(UISpecialFrames, frame:GetName())
    if not collapsed then tinsert(UISpecialFrames, frame:GetName()) end
end

local function ToggleCollapsed()
    local ui = UIDB()
    ui.collapsed = not ui.collapsed
    input:ClearFocus()
    ApplyLayout()
    Refresh()
    if orb:IsMouseOver() then orb:GetScript("OnEnter")(orb) end
end

local function BodyHeight()
    return frame:GetHeight() - BODY_TOP - BODY_BOTTOM
end

local function VisibleRows()
    return math.max(1, math.floor(BodyHeight() / ROW_H))
end

local function RowEnter(row)
    if dragFrom then return end
    row.hl:Show()
    row.remove:Show()
end

local function RowLeave(row)
    if row:IsMouseOver() then return end
    row.hl:Hide()
    row.remove:Hide()
end

local function Render()
    local names = ns.DB().names
    local visible = VisibleRows()
    offset = math.max(0, math.min(offset, #names - visible))

    for i = 1, math.max(visible, #rows) do
        local row = rows[i]
        local index = offset + i
        if i <= visible and names[index] then
            row.index = index
            row.rank:SetText(index)
            row.name:SetText(names[index])
            row:SetAlpha(index == dragFrom and 0.35 or 1)
            row:Show()
        elseif row then
            row.hl:Hide()
            row.remove:Hide()
            row:Hide()
        end
    end

    empty:SetShown(#names == 0)

    if #names > visible then
        local bodyH = BodyHeight()
        thumb:SetHeight(bodyH * visible / #names)
        thumb:SetPoint("TOPRIGHT", 0, -bodyH * offset / #names)
        thumb:Show()
    else
        thumb:Hide()
    end
end

local function DragUpdate(_, elapsed)
    local _, y = GetCursorPosition()
    local rel = body:GetTop() - y / body:GetEffectiveScale()
    local n = #ns.DB().names
    local visible = VisibleRows()

    dragElapsed = dragElapsed + elapsed
    if dragElapsed > 0.08 then
        dragElapsed = 0
        if rel < 0 and offset > 0 then
            offset = offset - 1
            Render()
        elseif rel > BodyHeight() and offset < n - visible then
            offset = offset + 1
            Render()
        end
    end

    local slot = math.floor(rel / ROW_H + 0.5)
    slot = math.max(0, math.min(slot, visible, n - offset))
    dropAt = offset + slot + 1
    dropLine:SetPoint("TOPLEFT", 0, -slot * ROW_H)
    dropLine:SetPoint("TOPRIGHT", -4, -slot * ROW_H)
end

local function StartDrag(row)
    dragFrom, dropAt, dragElapsed = row.index, nil, 0
    row.hl:Hide()
    row.remove:Hide()
    dropLine:Show()
    body:SetScript("OnUpdate", DragUpdate)
    Render()
end

local function StopDrag()
    body:SetScript("OnUpdate", nil)
    dropLine:Hide()
    local from, at = dragFrom, dropAt
    dragFrom, dropAt = nil, nil
    if from and at then
        local to = at > from and at - 1 or at
        if to ~= from then
            ns.Move(from, to)
            return
        end
    end
    Render()
end

local function CreateRow(i)
    local row = CreateFrame("Button", nil, body)
    row:SetHeight(ROW_H)
    row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
    row:SetPoint("TOPRIGHT", -4, -(i - 1) * ROW_H)
    row:RegisterForDrag("LeftButton")

    row.hl = row:CreateTexture(nil, "BACKGROUND")
    row.hl:SetAllPoints()
    row.hl:SetColorTexture(accent.r, accent.g, accent.b, 0.12)
    row.hl:Hide()

    row.rank = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.rank:SetPoint("LEFT", 2, 0)
    row.rank:SetWidth(14)
    row.rank:SetJustifyH("RIGHT")

    row.remove = GlyphButton(row, "x", function() ns.RemoveAt(row.index, true) end)
    row.remove:SetHeight(ROW_H)
    row.remove:SetPoint("RIGHT", -2, 0)
    row.remove:HookScript("OnLeave", function() RowLeave(row) end)
    row.remove:Hide()

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetPoint("LEFT", row.rank, "RIGHT", 6, 0)
    row.name:SetPoint("RIGHT", row.remove, "LEFT", -2, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    row:SetScript("OnEnter", RowEnter)
    row:SetScript("OnLeave", RowLeave)
    row:SetScript("OnDragStart", StartDrag)
    row:SetScript("OnDragStop", StopDrag)
    return row
end

local function AddFromInput()
    local text = strtrim(input:GetText())
    local name = text ~= "" and text or ns.SafeTargetName("target")
    if not name then
        ns.Print("No target - target something or type a name.")
        return
    end
    if ns.AddName(name, true) and text ~= "" then
        input:SetText("")
    end
end

local function PickupDTPMacro()
    if InCombatLockdown() then return end
    local index = GetMacroIndexByName(ns.MACRO_NAME)
    if index > 0 then PickupMacro(index) end
end

local function CreateHeader()
    header = CreateFrame("Button", nil, frame)
    header:SetPoint("TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", -1, -1)
    header:SetHeight(HEADER_H)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", StartMove)
    header:SetScript("OnDragStop", SavePosition)
    expandedOnly[#expandedOnly + 1] = header

    local title = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("LEFT", ORB_INSET - 1 + ORB + 5, 0)
    title:SetJustifyH("LEFT")
    title:SetWordWrap(false)
    title:SetText("Dynamic Target Ping")
    title:SetTextColor(accent.r, accent.g, accent.b)

    local close = GlyphButton(header, "x", function() frame:Hide() end)
    close:SetPoint("RIGHT", -2, 0)

    priority = GlyphButton(header, "#1", function()
        ns.SetPriority(not ns.DB().priority, true)
    end, function(self)
        ShowTooltip(self, "First match wins: " .. (ns.DB().priority and "on" or "off"),
            "Earlier names take priority when several are in range.")
    end)
    priority:SetWidth(18)
    priority:SetPoint("RIGHT", close, "LEFT", -2, 0)

    dot = CreateFrame("Frame", nil, header)
    dot:SetSize(10, 10)
    dot:SetPoint("RIGHT", priority, "LEFT", -2, 0)
    dot:EnableMouse(true)
    dot.tex = dot:CreateTexture(nil, "ARTWORK")
    dot.tex:SetSize(6, 6)
    dot.tex:SetPoint("CENTER")
    dot.tex:SetTexture(CIRCLE)
    dot:SetScript("OnEnter", function(self) ShowTooltip(self, "Macro status", self.tip) end)
    dot:SetScript("OnLeave", function() GameTooltip:Hide() end)
    title:SetPoint("RIGHT", dot, "LEFT", -4, 0)

    local sep = frame:CreateTexture(nil, "BORDER")
    sep:SetPoint("TOPLEFT", header, "BOTTOMLEFT")
    sep:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT")
    sep:SetHeight(1)
    sep:SetColorTexture(accent.r, accent.g, accent.b, 0.15)
    expandedOnly[#expandedOnly + 1] = sep
end

local function CreateBody()
    body = CreateFrame("Frame", nil, frame)
    body:SetPoint("TOPLEFT", PAD, -BODY_TOP)
    body:SetPoint("BOTTOMRIGHT", -PAD, BODY_BOTTOM)
    body:EnableMouseWheel(true)
    body:SetScript("OnMouseWheel", function(_, delta)
        offset = offset - delta
        Render()
    end)
    expandedOnly[#expandedOnly + 1] = body

    empty = body:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    empty:SetPoint("LEFT", 8, 0)
    empty:SetPoint("RIGHT", -8, 0)
    empty:SetText("Target something and press +")

    thumb = body:CreateTexture(nil, "OVERLAY")
    thumb:SetWidth(2)
    thumb:SetColorTexture(accent.r, accent.g, accent.b, 0.4)

    dropLine = body:CreateTexture(nil, "OVERLAY")
    dropLine:SetHeight(1)
    dropLine:SetColorTexture(accent.r, accent.g, accent.b, 1)
    dropLine:Hide()

    for i = 1, math.floor((MAX_H - BODY_TOP - BODY_BOTTOM) / ROW_H) do
        rows[i] = CreateRow(i)
        rows[i]:Hide()
    end
end

local function CreateFooter()
    footer = CreateFrame("Frame", nil, frame)
    footer:SetPoint("BOTTOMLEFT", PAD, PAD + 3)
    footer:SetPoint("BOTTOMRIGHT", -PAD, PAD + 3)
    footer:SetHeight(FOOTER_H)
    expandedOnly[#expandedOnly + 1] = footer

    clear = GlyphButton(footer, "clear", function()
        if #ns.DB().names > 0 then StaticPopup_Show("DYNAMICTARGETPING_CLEAR") end
    end)
    clear:SetSize(clear.label:GetStringWidth() + 6, FOOTER_H)
    clear:SetPoint("RIGHT")

    local add = GlyphButton(footer, "+", AddFromInput, function(self)
        ShowTooltip(self, "Add", "Adds the typed name, or your current target.")
    end)
    add:SetSize(16, FOOTER_H)
    add:SetPoint("RIGHT", clear, "LEFT", -2, 0)

    local scan = GlyphButton(footer, "", ns.ScanQuestMobs, function(self)
        ShowTooltip(self, "Add quest mobs",
            "Adds nearby enemies needed for kill or loot quest objectives.",
            "Enemy nameplates must be visible.")
    end)
    scan:SetSize(14, FOOTER_H)
    scan.icon = scan:CreateTexture(nil, "OVERLAY")
    scan.icon:SetSize(12, 12)
    scan.icon:SetPoint("CENTER")
    scan.icon:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
    scan.icon:SetVertexColor(DIM, DIM, DIM)
    scan:HookScript("OnEnter", function(self) self.icon:SetVertexColor(1, 1, 1) end)
    scan:HookScript("OnLeave", function(self) self.icon:SetVertexColor(DIM, DIM, DIM) end)
    scan:SetPoint("RIGHT", add, "LEFT", -2, 0)

    input = CreateFrame("EditBox", nil, footer, "BackdropTemplate")
    input:SetPoint("LEFT")
    input:SetPoint("RIGHT", scan, "LEFT", -4, 0)
    input:SetHeight(FOOTER_H)
    input:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    input:SetBackdropColor(0, 0, 0, 0.35)
    input:SetBackdropBorderColor(1, 1, 1, 0.08)
    input:SetFontObject("GameFontHighlightSmall")
    input:SetTextInsets(5, 5, 0, 0)
    input:SetAutoFocus(false)
    input:SetMaxLetters(48)
    input:SetScript("OnEnterPressed", function(self)
        if strtrim(self:GetText()) ~= "" then AddFromInput() end
        self:ClearFocus()
    end)
    input:SetScript("OnEscapePressed", input.ClearFocus)
    input:SetScript("OnTextChanged", function(self) placeholder:SetShown(self:GetText() == "") end)
    input:SetScript("OnEditFocusGained", function(self)
        self:SetBackdropBorderColor(accent.r, accent.g, accent.b, 0.5)
    end)
    input:SetScript("OnEditFocusLost", function(self) self:SetBackdropBorderColor(1, 1, 1, 0.08) end)

    placeholder = input:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    placeholder:SetPoint("LEFT", 5, 0)
    placeholder:SetText("Add name...")
end

local function CreateOrb()
    orb = CreateFrame("Button", nil, frame)
    orb:SetSize(ORB, ORB)
    orb:SetPoint("TOPLEFT", ORB_INSET, -ORB_INSET)
    orb:SetFrameLevel(header:GetFrameLevel() + 2)
    orb:RegisterForDrag("LeftButton")

    orb.ring = orb:CreateTexture(nil, "BACKGROUND")
    orb.ring:SetAllPoints()
    orb.ring:SetTexture(CIRCLE)
    orb.ring:SetVertexColor(accent.r, accent.g, accent.b, 0.6)

    orb.icon = orb:CreateTexture(nil, "ARTWORK")
    orb.icon:SetPoint("TOPLEFT", 2, -2)
    orb.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    orb.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local mask = orb:CreateMaskTexture()
    mask:SetAllPoints(orb.icon)
    mask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    orb.icon:AddMaskTexture(mask)

    orb.dot = orb:CreateTexture(nil, "OVERLAY")
    orb.dot:SetSize(7, 7)
    orb.dot:SetPoint("BOTTOMRIGHT")
    orb.dot:SetTexture(CIRCLE)

    orb:SetScript("OnClick", ToggleCollapsed)
    orb:SetScript("OnDragStart", function()
        if IsShiftKeyDown() then PickupDTPMacro() else StartMove() end
    end)
    orb:SetScript("OnDragStop", SavePosition)
    orb:SetScript("OnEnter", function(self)
        self.ring:SetVertexColor(accent.r, accent.g, accent.b, 1)
        local len = #ns.BuildBody(ns.DB().names)
        ShowTooltip(self, "Dynamic Target Ping",
            UIDB().collapsed and "Click to expand." or "Click to minimize.",
            "Drag to move. Shift-drag to put the macro on an action bar.",
            ("%d/%d characters. %s"):format(len, ns.MACRO_MAX_LENGTH, dot.tip or ""))
    end)
    orb:SetScript("OnLeave", function(self)
        self.ring:SetVertexColor(accent.r, accent.g, accent.b, 0.6)
        GameTooltip:Hide()
    end)
end

local function CreateWindow()
    frame = CreateFrame("Frame", "DynamicTargetPingFrame", UIParent, "BackdropTemplate")
    frame:Hide()
    frame:SetFrameStrata("MEDIUM")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:SetDontSavePosition(true)
    frame:SetResizable(true)
    frame:EnableMouse(true)
    frame:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })

    CreateHeader()
    CreateBody()
    CreateFooter()
    CreateOrb()

    grip = CreateFrame("Button", nil, frame)
    grip:SetSize(10, 10)
    grip:SetPoint("BOTTOMRIGHT", -1, 1)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:GetNormalTexture():SetVertexColor(accent.r, accent.g, accent.b)
    grip:SetAlpha(0.5)
    grip:SetScript("OnMouseDown", function() frame:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function()
        local ui = UIDB()
        ui.w, ui.h = frame:GetSize()
        SavePosition()
    end)
    expandedOnly[#expandedOnly + 1] = grip

    budget = frame:CreateTexture(nil, "OVERLAY")
    budget:SetPoint("BOTTOMLEFT", 1, 1)
    budget:SetHeight(1)
    expandedOnly[#expandedOnly + 1] = budget

    frame:SetScript("OnShow", function()
        UIDB().shown = true
        Refresh()
    end)
    -- IsShown stays true when only UIParent is hidden (Alt+Z), so that doesn't clear the flag.
    frame:SetScript("OnHide", function(self)
        UIDB().shown = self:IsShown()
        input:ClearFocus()
    end)
    frame:SetScript("OnSizeChanged", function() Refresh() end)

    RestorePosition()
    ApplyLayout()
end

Refresh = function()
    if not (frame and frame:IsShown()) then return end
    local d = ns.DB()

    if not UIDB().collapsed then Render() end

    local status = ns.GetStatus()
    local s = STATUS[status]
    dot.tex:SetVertexColor(s[1], s[2], s[3])
    dot.tip = s[4]
    orb.dot:SetVertexColor(s[1], s[2], s[3])
    orb.dot:SetShown(status ~= "ok" and UIDB().collapsed)

    priority.active = d.priority
    Tint(priority)
    clear:SetAlpha(#d.names > 0 and 1 or 0.35)

    local ratio = math.min(#ns.BuildBody(d.names) / ns.MACRO_MAX_LENGTH, 1)
    budget:SetWidth(math.max((frame:GetWidth() - 2) * ratio, 1))
    if ratio > 0.9 then
        budget:SetColorTexture(1, 0.25, 0.25, 0.9)
    else
        budget:SetColorTexture(accent.r, accent.g, accent.b, 0.6)
    end

    local index = GetMacroIndexByName(ns.MACRO_NAME)
    local icon = index > 0 and select(2, GetMacroInfo(index)) or QUESTION_MARK
    orb.icon:SetTexture(icon)
    orb.icon:SetDesaturated(index == 0)
end
ns.Refresh = Refresh

function ns.ToggleWindow()
    if not frame then CreateWindow() end
    if frame:IsShown() and not UIDB().collapsed then
        frame:Hide()
        return
    end
    if UIDB().collapsed then ToggleCollapsed() end
    frame:Show()
end

function ns.InitUI()
    local _, class = UnitClass("player")
    local c = class and RAID_CLASS_COLORS[class]
    if c then accent.r, accent.g, accent.b = c.r, c.g, c.b end
    if UIDB().shown then
        CreateWindow()
        frame:Show()
    end
end

StaticPopupDialogs.DYNAMICTARGETPING_CLEAR = {
    text = "Clear all DynamicTargetPing targets?",
    button1 = YES,
    button2 = NO,
    OnAccept = function() ns.Clear(true) end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

function DynamicTargetPing_OnAddonCompartmentClick()
    ns.ToggleWindow()
end
