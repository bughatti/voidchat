----------------------------------------------------------------------
-- VoidChat copy box: the game can't copy text out of a chat window, so a
-- click on a line (or the C button for the whole tab) puts the plain text in
-- a box where Ctrl+A, Ctrl+C work. A secret line (instanced combat) can't be
-- read by addons: it is left out and counted.
----------------------------------------------------------------------
local _, ns = ...

local A = { 0, 0.78, 1 }
local box

local function VoidPX()
    local s = UIParent and UIParent:GetEffectiveScale()
    if s and s > 0 and PixelUtil and PixelUtil.GetPixelToUIUnitFactor then return PixelUtil.GetPixelToUIUnitFactor() / s end
    return 1
end

local function build()
    if box then return box end
    local f = CreateFrame("Frame", "VoidChatCopyBox", UIParent, "BackdropTemplate")
    box = f
    f:SetSize(520, 300)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = VoidPX() })
    f:SetBackdropColor(0.03, 0.03, 0.05, 0.95)
    f:SetBackdropBorderColor(A[1], A[2], A[3], 0.8)
    f:EnableMouse(true)
    f:Hide()

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOPLEFT", 10, -8)
    f.title:SetTextColor(A[1], A[2], A[3])
    f.hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.hint:SetPoint("BOTTOMLEFT", 10, 8)
    f.hint:SetPoint("BOTTOMRIGHT", -10, 8)
    f.hint:SetJustifyH("LEFT")

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)

    local sf = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 10, -28)
    sf:SetPoint("BOTTOMRIGHT", -30, 26)
    local eb = CreateFrame("EditBox", nil, sf)
    eb:SetMultiLine(true)
    eb:SetAutoFocus(false)
    eb:SetFontObject(ChatFontNormal)
    eb:SetWidth(470)
    eb:SetScript("OnEscapePressed", function() f:Hide() end)
    -- read-only: typing puts the text back
    eb:SetScript("OnTextChanged", function(self, user) if user and f.text then self:SetText(f.text); self:HighlightText() end end)
    sf:SetScrollChild(eb)
    f.edit, f.scroll = eb, sf
    f:SetScript("OnSizeChanged", function(self) eb:SetWidth(self:GetWidth() - 50) end)

    tinsert(UISpecialFrames, "VoidChatCopyBox")   -- Esc closes it
    ns.Move(f, { db = ns.DB, key = "copy" })
    return f
end

local function show(title, text, hidden)
    local f = build()
    f.text = text
    f.title:SetText(title)
    local hint = "Ctrl+C copies the selected text. Esc closes."
    if hidden and hidden > 0 then
        hint = hidden .. (hidden == 1 and " line" or " lines")
            .. " left out: the game hides chat from addons in instanced combat. " .. hint
    end
    f.hint:SetText(hint)
    f:Show()
    f.edit:SetText(text)
    f.edit:SetFocus()
    f.edit:HighlightText()
    C_Timer.After(0, function() f.scroll:SetVerticalScroll(f.scroll:GetVerticalScrollRange()) end)
end

local function plainLine(line)
    local p = ns.Plain(line.text)
    if not p then return nil end
    if ns.DB().stamps then p = date("%H:%M", line.t) .. " " .. p end
    return p
end

function ns.CopyLine(line)
    if line.secret then
        show("Copy", "", 1)
        return
    end
    show("Copy a line", plainLine(line) or "")
end

function ns.CopyTab()
    local lines, label = ns.TabLines(200)
    local out, hidden = {}, 0
    for _, line in ipairs(lines) do
        local p = plainLine(line)
        if p then out[#out + 1] = p else hidden = hidden + 1 end
    end
    show("Copy: " .. label .. " (" .. #out .. " lines)", table.concat(out, "\n"), hidden)
end
