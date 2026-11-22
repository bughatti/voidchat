----------------------------------------------------------------------
-- VoidChat window: tabs, the lines, search, scroll, resize, settings menu.
--
-- Lines are drawn as FontStrings (not a ScrollingMessageFrame): in 12.x a
-- message frame's AddMessage refuses secret text from addon code, while
-- FontString:SetText takes it. So a secret line (instanced combat) still shows.
-- Each FontString sizes itself to its wrapped text; they are chained bottom-up,
-- so no height math is done on text we may not be allowed to read.
----------------------------------------------------------------------
local _, ns = ...

local A = { 0, 0.78, 1 }   -- Void cyan
local HEADER_H, PAD, GAP = 20, 5, 2

local function VoidPX()
    local s = UIParent and UIParent:GetEffectiveScale()
    if s and s > 0 and PixelUtil and PixelUtil.GetPixelToUIUnitFactor then return PixelUtil.GetPixelToUIUnitFactor() / s end
    return 1
end

local DEFAULTS = {
    w = 440, h = 190, font = 13, bg = 0.55, stamps = false, whisperTabs = true,
    hideBlizzard = true, fade = true, tab = "all",
}

-- Settings are per character (VoidChatCharDB; every Void addon's settings are). 0.1.0 kept them
-- account-wide in VoidChatUIDB: a character's first load starts from a copy of that.
-- Before our saved variables are loaded (lines arriving at load time) a scratch table answers.
local scratch
local function fill(db)
    for k, v in pairs(DEFAULTS) do if db[k] == nil then db[k] = v end end
    ns.CheckTabs(db)
    return db
end
function ns.DB()
    if not ns.loaded then
        scratch = scratch or fill({})
        return scratch
    end
    if type(VoidChatCharDB) ~= "table" then
        VoidChatCharDB = {}
        if type(VoidChatUIDB) == "table" then
            for k, v in pairs(VoidChatUIDB) do
                VoidChatCharDB[k] = (type(v) == "table" and CopyTable) and CopyTable(v) or v
            end
        end
    end
    return fill(VoidChatCharDB)
end

local MAX_PEOPLE = 6

local W = {}            -- the window's parts
ns.W = W
local people = {}       -- whisper tabs this session: { key, label, who }
local unread = {}       -- [tab key] = true: news in a tab you're not looking at (session only)
local offset = 0        -- lines skipped from the newest (scrolled up)
local newBelow = 0
local query            -- search text (lower case) or nil
local lastActivity = GetTime()

local function db() return ns.DB() end

-- the shown tabs (your list, hidden ones left out), then this session's whisper tabs
local function allTabs()
    local out = {}
    for _, t in ipairs(db().tabs) do if not t.hidden then out[#out + 1] = t end end
    if db().whisperTabs then
        for _, p in ipairs(people) do out[#out + 1] = p end
    end
    return out
end

local function tabByKey(key)
    local list = allTabs()
    for _, t in ipairs(list) do if t.key == key then return t end end
    return list[1] or db().tabs[1]
end

-- Does a line belong in a tab?
local function inTab(tab, line)
    if tab.who then return line.who == tab.who end
    return ns.TabShows(tab, line)
end

local function matches(tab, line)
    if not inTab(tab, line) then return false end
    if query then
        if line.secret then return false end
        local p = line.plain
        if p == nil then p = ns.Plain(line.text) or ""; line.plain = p end
        return p:lower():find(query, 1, true) ~= nil
    end
    return true
end

----------------------------------------------------------------------
-- Drawing the lines
----------------------------------------------------------------------
local rows = {}

local function fontPath()
    local f = _G.ChatFontNormal and select(1, _G.ChatFontNormal:GetFont())
    return f or "Fonts\\FRIZQT__.TTF"
end

local function row(i)
    local fs = rows[i]
    if fs then return fs end
    fs = W.body:CreateFontString(nil, "ARTWORK")
    fs:SetJustifyH("LEFT")
    fs:SetJustifyV("TOP")
    fs:SetWordWrap(true)
    if fs.SetNonSpaceWrap then fs:SetNonSpaceWrap(true) end
    rows[i] = fs
    return fs
end

local function stamp(line)
    if not db().stamps then return nil end
    return "|cff808080" .. date("%H:%M", line.t) .. "|r "
end

function ns.Redraw()
    if not W.frame then return end
    local d = db()
    local tab = tabByKey(d.tab)
    local width = W.body:GetWidth() - PAD * 2
    if width <= 10 then return end
    local size = d.font
    local maxRows = math.floor((W.body:GetHeight() - PAD) / (size + GAP)) + 1

    -- never scroll past the oldest line
    local L = ns.lines
    local total = 0
    for i = 1, #L do if matches(tab, L[i]) then total = total + 1 end end
    offset = math.max(0, math.min(offset, total - 1))   -- (long wrapped lines: every one reachable)

    -- newest first: skip `offset` matches, then take up to maxRows
    local picked, skipped = {}, 0
    for i = #L, 1, -1 do
        local line = L[i]
        if matches(tab, line) then
            if skipped < offset then skipped = skipped + 1
            else
                picked[#picked + 1] = line
                if #picked >= maxRows then break end
            end
        end
    end

    local prev
    for i = 1, math.max(#picked, #rows) do
        local fs = row(i)
        local line = picked[i]
        if line then
            fs:SetFont(fontPath(), size, "")
            fs:SetShadowOffset(1, -1)
            fs:SetWidth(width)
            fs:ClearAllPoints()
            if prev then fs:SetPoint("BOTTOMLEFT", prev, "TOPLEFT", 0, GAP)
            else fs:SetPoint("BOTTOMLEFT", W.body, "BOTTOMLEFT", PAD, PAD) end
            fs:SetTextColor(line.r, line.g, line.b)
            local st = stamp(line)
            if st and not line.secret then fs:SetText(st .. line.text) else fs:SetText(line.text) end
            fs.line = line
            fs:Show()
            -- one line taller than the window: show where it starts (click copies all of it)
            if not prev and not line.secret then
                local h = fs:GetStringHeight()
                if type(h) == "number" and not ns.Secret(h) and h > W.body:GetHeight() - PAD * 2 then
                    fs:ClearAllPoints()
                    fs:SetPoint("TOPLEFT", W.body, "TOPLEFT", PAD, -PAD)
                end
            end
            prev = fs
        else
            fs.line = nil
            fs:SetText("")
            fs:Hide()
        end
    end

    -- "new lines below" button while scrolled up
    if offset > 0 then
        W.down.text:SetText(newBelow > 0 and (newBelow .. " new  \226\150\188") or "\226\150\188")
        W.down:SetWidth(W.down.text:GetStringWidth() + 14)
        W.down:Show()
    else
        newBelow = 0
        W.down:Hide()
    end
    W.empty:SetShown(#picked == 0)
    W.empty:SetText(query and "No line matches your search."
        or (ns.TabPicksNothing(tab) and "This tab shows nothing yet: right-click it and pick what it shows.")
        or "Nothing here yet.")
end

----------------------------------------------------------------------
-- Tabs
----------------------------------------------------------------------
local tabButtons = {}

local function styleTab(b, active)
    b.text:SetTextColor(active and 1 or 0.7, active and 1 or 0.7, active and 1 or 0.7)
    b.bar:SetShown(active or unread[b.def.key] == true)
    if active then b.bar:SetColorTexture(A[1], A[2], A[3], 1)
    else b.bar:SetColorTexture(A[1], A[2], A[3], 0.45) end
end

function ns.LayoutTabs()
    if not W.frame then return end
    local d = db()
    local x = PAD
    local limit = W.header:GetWidth() - (W.tools and W.tools:GetWidth() or 0) - PAD
    local searching = W.search and W.search:IsShown()
    local overflow = {}
    for i, def in ipairs(allTabs()) do
        local b = tabButtons[i]
        if not b then
            b = CreateFrame("Button", nil, W.header)
            b:SetHeight(HEADER_H)
            b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            b.text:SetPoint("CENTER", 0, 1)
            b.bar = b:CreateTexture(nil, "OVERLAY")
            b.bar:SetHeight(2)
            b.bar:SetPoint("BOTTOMLEFT", 2, 0)
            b.bar:SetPoint("BOTTOMRIGHT", -2, 0)
            b:SetScript("OnClick", function(self, button)
                if button == "RightButton" then
                    if self.def.who then ns.CloseWhisperTab(self.def.key)
                    else ns.TabMenu(self, self.def) end
                    return
                end
                ns.SelectTab(self.def.key)
            end)
            b:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                if self.def.who then
                    GameTooltip:AddLine("Whispers with " .. self.def.label, 1, 1, 1)
                    GameTooltip:AddLine("Right-click: close this tab", 0.7, 0.7, 0.7)
                else
                    GameTooltip:AddLine(self.def.label, 1, 1, 1)
                    GameTooltip:AddLine("Right-click: rename, what it shows, move, hide, new tab", 0.7, 0.7, 0.7, true)
                end
                GameTooltip:Show()
            end)
            b:SetScript("OnLeave", function() GameTooltip:Hide() end)
            if ns.MoveHandle then ns.MoveHandle(W.frame, b) end   -- a tab drags the window too
            tabButtons[i] = b
        end
        b.def = def
        b.text:SetText(def.label)
        local w = math.ceil(b.text:GetStringWidth()) + 14
        b:SetWidth(w)
        b:ClearAllPoints()
        b:SetPoint("LEFT", W.header, "LEFT", x, 0)
        local fits = x + w <= limit - 20   -- room for the » button
        b:SetShown(fits and not searching)
        b.fits = fits
        if fits then x = x + w else overflow[#overflow + 1] = def end
        styleTab(b, def.key == d.tab)
    end
    for i = #allTabs() + 1, #tabButtons do tabButtons[i]:Hide() end
    -- tabs that don't fit: the » button lists them (lit when one of them has news)
    W.more.list = overflow
    W.more:SetShown(#overflow > 0 and not searching)
    local news = false
    for _, def in ipairs(overflow) do if unread[def.key] or def.key == d.tab then news = true end end
    W.more.text:SetTextColor(news and A[1] or 0.75, news and A[2] or 0.75, news and A[3] or 0.75)
end

function ns.SelectTab(key)
    local t = tabByKey(key)
    db().tab = t.key
    unread[t.key] = nil
    offset, newBelow = 0, 0
    ns.LayoutTabs()
    ns.Redraw()
end

local function whisperTab(who)
    for _, p in ipairs(people) do if p.who == who then return p end end
    if #people >= MAX_PEOPLE then
        -- drop the oldest one that has nothing unread and isn't open; else the oldest not open
        -- (its lines stay in the Whisper tab)
        for pass = 1, 2 do
            for i, p in ipairs(people) do
                if (pass == 2 or not unread[p.key]) and db().tab ~= p.key then
                    unread[p.key] = nil
                    table.remove(people, i)
                    break
                end
            end
            if #people < MAX_PEOPLE then break end
        end
        if #people >= MAX_PEOPLE then return nil end
    end
    local label = who:match("^([^%-]+)") or who
    local p = { key = "who:" .. who, label = label, who = who }
    people[#people + 1] = p
    return p
end

function ns.CloseWhisperTab(key)
    for i, p in ipairs(people) do
        if p.key == key then table.remove(people, i) break end
    end
    unread[key] = nil
    if db().tab == key then ns.SelectTab("whisper") return end   -- (resets the scroll too: Sol review)
    ns.LayoutTabs()
    ns.Redraw()
end

----------------------------------------------------------------------
-- New lines
----------------------------------------------------------------------
local function onLine(line)
    if line.kind == "whisper" and line.who and db().whisperTabs then whisperTab(line.who) end
    local d = db()
    local active = tabByKey(d.tab)
    local unreadChanged = false
    for _, t in ipairs(allTabs()) do
        if t.key ~= active.key and inTab(t, line) and not unread[t.key] and t.key ~= "all" then
            unread[t.key] = true
            unreadChanged = true
        end
    end
    if offset > 0 and matches(active, line) then
        offset = offset + 1          -- keep the view still while reading back
        newBelow = newBelow + 1
    end
    if line.kind ~= "loot" and line.kind ~= "other" then lastActivity = GetTime() end
    if line.kind == "whisper" then lastActivity = GetTime() end
    if W.frame then
        if unreadChanged or line.kind == "whisper" then ns.LayoutTabs() end
        ns.Redraw()
    end
end
ns.listeners[#ns.listeners + 1] = onLine

----------------------------------------------------------------------
-- Line under the mouse (copy on click)
----------------------------------------------------------------------
local function lineUnderMouse()
    for _, fs in ipairs(rows) do
        if fs:IsShown() and fs.line then
            -- a secret line's geometry is secret too: its answer may not be testable
            local over = fs:IsMouseOver()
            if not ns.Secret(over) and over then return fs.line end
        end
    end
end

----------------------------------------------------------------------
-- Settings menu
----------------------------------------------------------------------
local function openMenu(owner)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
    MenuUtil.CreateContextMenu(owner, function(_, root)
        local d = db()
        root:CreateTitle("VoidChat")
        local function toggle(label, key, after)
            root:CreateCheckbox(label, function() return d[key] == true end, function()
                d[key] = not d[key]
                if after then after() end
                ns.Redraw()
            end)
        end
        ns.FillTabsMenu(root:CreateButton("Tabs (right-click a tab to edit it)"))
        toggle("Show the time on each line", "stamps")
        -- off: the person tabs go now, not only new ones (Codex, 2026-11-18)
        toggle("A tab for each person you whisper", "whisperTabs", function()
            if not d.whisperTabs then
                for _, p in ipairs(people) do unread[p.key] = nil end
                wipe(people)
                if type(d.tab) == "string" and d.tab:find("^who:") then ns.SelectTab("whisper") end
            end
            ns.LayoutTabs()
        end)
        toggle("Fade the window when idle", "fade")
        local size = root:CreateButton("Text size")
        for _, n in ipairs({ 11, 12, 13, 14, 16, 18 }) do
            size:CreateRadio(tostring(n), function() return d.font == n end, function() d.font = n; ns.Redraw() end)
        end
        local bg = root:CreateButton("Background")
        for _, v in ipairs({ { "Clear", 0 }, { "Light", 0.3 }, { "Medium", 0.55 }, { "Dark", 0.8 } }) do
            bg:CreateRadio(v[1], function() return d.bg == v[2] end, function() d.bg = v[2]; ns.ApplyLook() end)
        end
        root:CreateDivider()
        root:CreateCheckbox("Hide Blizzard's chat window (reloads)", function() return d.hideBlizzard end, function()
            d.hideBlizzard = not d.hideBlizzard
            ReloadUI()
        end)
        root:CreateButton("Put the window back where it started", function()
            if ns.MoveReset then ns.MoveReset(W.frame) end
            d.w, d.h = DEFAULTS.w, DEFAULTS.h
            W.frame:SetSize(d.w, d.h)
            ns.LayoutTabs(); ns.Redraw()
        end)
    end)
end

ns.OpenSettings = openMenu

----------------------------------------------------------------------
-- Building the window
----------------------------------------------------------------------
function ns.ApplyLook()
    local d = db()
    W.frame:SetBackdropColor(0.03, 0.03, 0.05, d.bg)
    W.frame:SetBackdropBorderColor(A[1], A[2], A[3], d.bg > 0 and 0.5 or 0)
    W.header.bg:SetColorTexture(0, 0, 0, math.min(0.9, d.bg + 0.15))
end

-- A header button: a texture when given (the game font has no gear glyph: the user, 2026-11-17,
-- "the settings is not a gear, just a blue box"), else a letter.
local function iconButton(parent, label, tip, onClick, texture, texSize)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(18, 18)
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.text:SetPoint("CENTER", 0, 1)
    b.text:SetTextColor(0.75, 0.75, 0.75)
    if texture then
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetSize(texSize or 14, texSize or 14)
        b.icon:SetPoint("CENTER")
        local ok = b.icon:SetTexture(texture)
        if ok == false then b.icon:Hide(); b.icon = nil; b.text:SetText(label)
        else b.icon:SetVertexColor(0.8, 0.8, 0.8) end
    else
        b.text:SetText(label)
    end
    b:SetScript("OnEnter", function(self)
        if self.icon then self.icon:SetVertexColor(A[1], A[2], A[3]) end
        self.text:SetTextColor(A[1], A[2], A[3])
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(tip, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function(self)
        if self.icon then self.icon:SetVertexColor(0.8, 0.8, 0.8) end
        self.text:SetTextColor(0.75, 0.75, 0.75)
        GameTooltip:Hide()
    end)
    b:SetScript("OnClick", onClick)
    return b
end

function ns.Build()
    if W.frame then return end
    local d = db()
    local f = CreateFrame("Frame", "VoidChatWindow", UIParent, "BackdropTemplate")
    W.frame = f
    f:SetSize(d.w, d.h)
    -- first time: where Blizzard's chat was (Hide.lua startSpot); later the saved spot wins
    f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", d.home and d.home[1] or 20, d.home and d.home[2] or 60)
    f:SetFrameStrata("LOW")
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = VoidPX() })
    f:SetResizable(true)
    if f.SetResizeBounds then f:SetResizeBounds(260, 90, 1200, 800) end
    f:EnableMouse(true)

    local header = CreateFrame("Frame", nil, f)
    W.header = header
    header:SetPoint("TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", -1, -1)
    header:SetHeight(HEADER_H)
    header.bg = header:CreateTexture(nil, "BACKGROUND")
    header.bg:SetAllPoints()
    header:EnableMouse(true)

    -- right side: search, copy, settings
    local tools = CreateFrame("Frame", nil, header)
    W.tools = tools
    tools:SetPoint("RIGHT", -2, 0)
    tools:SetSize(18 * 3 + 4, HEADER_H)
    local gear = iconButton(tools, "S", "Settings", function(self) openMenu(self) end,
        "Interface\\Buttons\\UI-OptionsButton", 15)
    gear:SetPoint("RIGHT", 0, 0)
    local copy = iconButton(tools, "C", "Copy the lines of this tab (up to the last 200)", function() ns.CopyTab() end)
    copy:SetPoint("RIGHT", gear, "LEFT", -2, 0)
    local find = iconButton(tools, "?", "Search this tab", function() ns.ToggleSearch() end,
        "Interface\\Common\\UI-Searchbox-Icon", 12)
    find:SetPoint("RIGHT", copy, "LEFT", -2, 0)
    -- » : the tabs that don't fit the width
    local more = iconButton(header, "\194\187", "More tabs", function(self)
        if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
        MenuUtil.CreateContextMenu(self, function(_, root)
            for _, def in ipairs(self.list or {}) do
                local label = def.label .. (unread[def.key] and "  |cff00c7ff(new)|r" or "")
                root:CreateRadio(label, function() return db().tab == def.key end, function() ns.SelectTab(def.key) end)
            end
            -- the open tab is one of these: its button is off-screen, so its right-click is here
            -- (Codex, 2026-11-18: overflow tabs couldn't be edited or closed)
            for _, def in ipairs(self.list or {}) do
                if def.key == db().tab then
                    root:CreateDivider()
                    if def.who then
                        root:CreateButton("Close " .. def.label, function() ns.CloseWhisperTab(def.key) end)
                    else
                        root:CreateButton("Edit " .. def.label .. "...", function()
                            C_Timer.After(0, function() ns.TabMenu(W.more, def) end)
                        end)
                    end
                end
            end
        end)
    end)
    W.more = more
    more:SetPoint("RIGHT", tools, "LEFT", -2, 0)
    more:Hide()

    -- search box (over the tabs while open)
    local sb = CreateFrame("EditBox", nil, header, "InputBoxTemplate")
    W.search = sb
    sb:SetAutoFocus(false)
    sb:SetHeight(16)
    sb:SetPoint("LEFT", 10, 0)
    sb:SetPoint("RIGHT", tools, "LEFT", -6, 0)
    sb:Hide()
    sb:SetScript("OnTextChanged", function(self)
        local t = self:GetText()
        query = (t ~= "" and t:lower()) or nil
        offset = 0
        ns.Redraw()
    end)
    sb:SetScript("OnEscapePressed", function() ns.ToggleSearch(false) end)
    sb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

    -- the lines
    local body = CreateFrame("Frame", nil, f)
    W.body = body
    body:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
    body:SetPoint("BOTTOMRIGHT", -1, 1)
    body:SetClipsChildren(true)
    body:SetHyperlinksEnabled(true)
    body:EnableMouse(true)
    body:EnableMouseWheel(true)
    -- Right-click a name for the player menu (Whisper, Invite, Target...). The user, 2026-11-22: right-clicking a
    -- name in General did "nothing at all". Logged in game: the click did reach SetItemRef, but on WoW Forever the
    -- player menu is attached to the chat frame it's given (FriendsFrame_ShowDropdown: ownerFrame = chatFrame) and a
    -- menu closes the moment its owner isn't visible (Blizzard_Menu: "if not ownerRegion:IsVisible() then
    -- CloseMenu"). We passed Blizzard's chat frame, which VoidChat hides: the menu opened and closed in one frame.
    -- So for a player's or Battle.net friend's name VoidChat opens that same menu the way Blizzard's link handlers do
    -- (ItemRefHandlers: FriendsFrame_ShowDropdown / ShowBNDropdown) but with the owner set apart: this window (shown)
    -- owns the menu, Blizzard's chat frame stays the chat frame (its menu actions "Move to whisper window" read its
    -- messages: Sol 11-22). Any other link, a shift-right-click (put the name in chat), or no UnitPopup: as before.
    if type(VoidChatUIDB) == "table" then VoidChatUIDB._dbgRC = nil end   -- the 11-22 debug log
    local function openPlayerMenu(owner, link)
        if type(_G.UnitPopup_OpenMenu) ~= "function" or type(link) ~= "string" or ns.Secret(link) then return false end
        local kind, opts = link:match("^(%a+):(.*)$")
        local chatFrame = _G.DEFAULT_CHAT_FRAME
        if kind == "player" then
            local name, lineID, chatType = strsplit(":", opts)
            if not name or name == "" then return false end
            _G.UnitPopup_OpenMenu("FRIEND", { name = name, lineID = lineID, chatType = chatType, chatTarget = name,
                chatFrame = chatFrame, ownerFrame = owner })
            return true
        elseif kind == "BNplayer" then
            local name, bnetIDAccount, _, chatType = strsplit(":", opts)
            if not name or name == "" or not bnetIDAccount then return false end
            if _G.BNIsSelf and _G.BNIsSelf(bnetIDAccount) then return true end   -- Blizzard shows no menu for you
            -- no line ID, as Blizzard's own BN handler (ItemRefHandlersShared) passes none
            _G.UnitPopup_OpenMenu("BN_FRIEND", { name = name, chatType = chatType, chatTarget = name,
                chatFrame = chatFrame, bnetIDAccount = bnetIDAccount, ownerFrame = owner })
            return true
        end
        return false
    end
    body:SetScript("OnHyperlinkClick", function(self, link, text, button)
        W.linkClicked = GetTime()
        if button == "RightButton" and not IsModifiedClick("CHATLINK") and openPlayerMenu(self, link) then return end
        SetItemRef(link, text, button, _G.DEFAULT_CHAT_FRAME)
    end)
    body:SetScript("OnHyperlinkEnter", function(self, link)
        if ns.Secret(link) or type(link) ~= "string" then return end
        local kind = link:match("^(%a+):")
        local ok = { item = 1, spell = 1, quest = 1, achievement = 1, enchant = 1, talent = 1, currency = 1,
                     unit = 1, keystone = 1, battlepet = 1, mount = 1, transmogappearance = 1 }
        if kind and ok[kind] then
            GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
            pcall(GameTooltip.SetHyperlink, GameTooltip, link)
            GameTooltip:Show()
        end
    end)
    body:SetScript("OnHyperlinkLeave", function() GameTooltip:Hide() end)
    body:SetScript("OnMouseUp", function(_, button)
        if button ~= "LeftButton" then return end
        if W.linkClicked and GetTime() - W.linkClicked < 0.2 then return end
        local line = lineUnderMouse()
        if line then ns.CopyLine(line) end
    end)
    body:SetScript("OnMouseWheel", function(_, delta)
        if IsShiftKeyDown() then
            offset = delta > 0 and 1e6 or 0
        else
            offset = math.max(0, offset + delta * 3)
        end
        if offset == 0 then newBelow = 0 end
        ns.Redraw()
    end)

    W.empty = body:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    W.empty:SetPoint("CENTER")

    local down = CreateFrame("Button", nil, f, "BackdropTemplate")
    W.down = down
    down:SetHeight(16)
    down:SetPoint("BOTTOMRIGHT", -18, 4)
    down:SetFrameLevel(body:GetFrameLevel() + 5)
    down:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = VoidPX() })
    down:SetBackdropColor(0, 0, 0, 0.85)
    down:SetBackdropBorderColor(A[1], A[2], A[3], 0.8)
    down.text = down:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    down.text:SetPoint("CENTER")
    down.text:SetTextColor(A[1], A[2], A[3])
    down:SetScript("OnClick", function() offset, newBelow = 0, 0; ns.Redraw() end)
    down:Hide()

    -- resize grip
    local grip = CreateFrame("Button", nil, f)
    grip:SetSize(14, 14)
    grip:SetPoint("BOTTOMRIGHT", -1, 1)
    grip:SetFrameLevel(body:GetFrameLevel() + 6)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function()
        f:StopMovingOrSizing()
        if f.SetUserPlaced then f:SetUserPlaced(false) end
        d.w, d.h = math.floor(f:GetWidth() + 0.5), math.floor(f:GetHeight() + 0.5)
        ns.MoveSave(f)   -- StartSizing re-anchors the frame: save the spot again
    end)
    f:SetScript("OnSizeChanged", function() ns.LayoutTabs(); ns.Redraw() end)

    -- drag by the header (every box movable and kept)
    ns.Move(f, { db = ns.DB, key = "window", handle = header })

    -- fade when idle: the frame and tabs, never the text
    local fadeT = 0
    f:SetScript("OnUpdate", function(self, el)
        fadeT = fadeT + el
        if fadeT < 0.2 then return end
        fadeT = 0
        local want = 1
        if db().fade and not self:IsMouseOver() and not (W.search:HasFocus())
            and GetTime() - lastActivity > 15 then
            if not _G.ACTIVE_CHAT_EDIT_BOX then want = 0 end   -- not while you type
        end
        local cur = self.voidFade or 1
        if cur ~= want then
            cur = want > cur and math.min(want, cur + 0.25) or math.max(want, cur - 0.08)
            self.voidFade = cur
            header:SetAlpha(cur)
            grip:SetAlpha(cur)
            local bgA = db().bg
            self:SetBackdropColor(0.03, 0.03, 0.05, bgA * (0.35 + 0.65 * cur))
            self:SetBackdropBorderColor(A[1], A[2], A[3], (bgA > 0 and 0.5 or 0) * cur)
        end
    end)
    f:HookScript("OnEnter", function() lastActivity = GetTime() end)

    ns.ApplyLook()
    ns.LayoutTabs()
    ns.Redraw()
end

function ns.ToggleSearch(open)
    if open == nil then open = not W.search:IsShown() end
    if open then
        for _, b in ipairs(tabButtons) do b:Hide() end
        W.more:Hide()
        W.search:Show()
        W.search:SetFocus()
    else
        W.search:SetText("")
        W.search:ClearFocus()
        W.search:Hide()
        query = nil
        ns.LayoutTabs()
        ns.Redraw()
    end
end

-- The lines shown in the open tab (for Copy), oldest first.
function ns.TabLines(limit)
    local tab = tabByKey(db().tab)
    local out = {}
    for i = #ns.lines, 1, -1 do
        local line = ns.lines[i]
        if matches(tab, line) then
            table.insert(out, 1, line)
            if #out >= limit then break end
        end
    end
    return out, tab.label
end
