----------------------------------------------------------------------
-- VoidChat tabs you can edit, like Blizzard's chat tabs (the user, 2026-11-17:
-- "the chat has no way to edit each tab like the default blizzard").
--
-- Right-click a tab: rename it, pick what it shows (message groups and each
-- channel by name), move it left or right, hide it, delete it (your own tabs),
-- or make a new tab. The settings menu lists every tab to bring a hidden one back.
--
-- A tab = { key, label, show = { group = true }, allCh, ch = { [channel] = true },
-- hidden, custom }. Saved per character (VoidChatCharDB.tabs). Whisper tabs for
-- each person are session-only and only close.
----------------------------------------------------------------------
local _, ns = ...

-- Message groups, in menu order. A line belongs to exactly one (ns.GroupOf).
ns.GROUPS = {
    { key = "say",      label = "Say, yell and emotes" },
    { key = "whisper",  label = "Whispers" },
    { key = "guild",    label = "Guild and officer" },
    { key = "group",    label = "Party, raid and instance" },
    { key = "loot",     label = "Loot and money" },
    { key = "progress", label = "XP, reputation and skill" },
    { key = "npc",      label = "NPC talk" },
    { key = "system",   label = "System messages" },
    { key = "void",     label = "Void addons" },
    { key = "other",    label = "Other addons and the rest" },
}

local SAY = { SAY = true, YELL = true, EMOTE = true, TEXT_EMOTE = true }
local PROGRESS = { COMBAT_XP_GAIN = true, COMBAT_FACTION_CHANGE = true, SKILL = true, ACHIEVEMENT = true,
    COMBAT_HONOR_GAIN = true, TRADESKILLS = true, OPENING = true, PET_INFO = true, COMBAT_MISC_INFO = true }
local SYSTEM = { SYSTEM = true, CHANNEL_NOTICE = true, CHANNEL_NOTICE_USER = true, CHANNEL_JOIN = true,
    CHANNEL_LEAVE = true, CHANNEL_LIST = true, IGNORED = true, FILTERED = true, RESTRICTED = true }

function ns.GroupOf(line)
    if line.group then return line.group end
    local k, t = line.kind, line.chatType
    local g
    if k == "whisper" or k == "guild" or k == "group" or k == "loot" or k == "void" or k == "channel" then
        g = k
    elseif t and SAY[t] then g = "say"
    elseif t and PROGRESS[t] then g = "progress"
    elseif t and (t:match("^MONSTER_") or t:match("^RAID_BOSS_")) then g = "npc"
    elseif t and (SYSTEM[t] or t:match("^BN_INLINE")) then g = "system"
    else g = "other" end
    line.group = g
    return g
end

----------------------------------------------------------------------
-- Channel names: "2. Trade - City" -> "Trade"; "Trade (Services) - English 50" -> "Trade (Services)".
----------------------------------------------------------------------
local function baseName(s)
    if type(s) ~= "string" or ns.Secret(s) or s == "" then return nil end
    s = s:gsub("^%d+%.%s*", "")
    s = s:match("^(.-) %- ") or s
    if s == "" then return nil end
    return s
end

local seenChannels = {}
-- From the event (arg9 = channelBaseName, arg4 = "2. Trade - City"), else the line's channel link.
function ns.ChannelName(args, text)
    local n
    if type(args) == "table" then n = baseName(args[9]) or baseName(args[4]) end
    if not n and type(text) == "string" and not ns.Secret(text) then
        n = baseName(text:match("|Hchannel:[^|]-|h%[([^%]]-)%]|h"))
    end
    if n then seenChannels[n] = true end
    return n
end

-- Every channel name we know: joined ones, ones seen this session, ones a tab already picks.
function ns.ChannelNames()
    local set = {}
    for n in pairs(seenChannels) do set[n] = true end
    if type(GetChannelList) == "function" then
        local list = { pcall(GetChannelList) }
        if list[1] then
            for i = 2, #list, 3 do
                local n = baseName(list[i + 1])
                if n then set[n] = true end
            end
        end
    end
    for _, t in ipairs(ns.DB().tabs or {}) do
        for n in pairs(t.ch or {}) do set[n] = true end
    end
    local out = {}
    for n in pairs(set) do out[#out + 1] = n end
    table.sort(out)
    return out
end

----------------------------------------------------------------------
-- The tab list
----------------------------------------------------------------------
function ns.DefaultTabs(voidInAll)
    local every = {}
    for _, g in ipairs(ns.GROUPS) do every[g.key] = true end
    every.void = voidInAll and true or nil
    return {
        { key = "all",     label = "All",     show = every, allCh = true },
        { key = "whisper", label = "Whisper", show = { whisper = true } },
        { key = "guild",   label = "Guild",   show = { guild = true } },
        { key = "group",   label = "Group",   show = { group = true } },
        { key = "channel", label = "Trade",   show = {}, ch = { Trade = true, ["Trade (Services)"] = true } },
        { key = "loot",    label = "Loot",    show = { loot = true } },
        { key = "void",    label = "Void",    show = { void = true } },
    }
end

-- Fix up a saved list (missing tables, unknown fields) so the rest never checks.
function ns.CheckTabs(d)
    if type(d.tabs) ~= "table" or #d.tabs == 0 then
        d.tabs = ns.DefaultTabs(d.voidInAll)
    end
    d.voidInAll = nil   -- 0.1.0 setting: now the All tab's "Void addons" tick
    local seen = {}
    for i = #d.tabs, 1, -1 do
        local t = d.tabs[i]
        if type(t) ~= "table" or type(t.key) ~= "string" or seen[t.key] then
            table.remove(d.tabs, i)
        else
            seen[t.key] = true
            if type(t.show) ~= "table" then t.show = {} end
            if t.ch ~= nil and type(t.ch) ~= "table" then t.ch = nil end
            if type(t.label) ~= "string" or t.label == "" then t.label = "Tab" end
        end
    end
    if #d.tabs == 0 then d.tabs = ns.DefaultTabs() end
end

function ns.TabShows(tab, line)
    local g = ns.GroupOf(line)
    if g == "channel" then
        return tab.allCh == true or (tab.ch ~= nil and line.channel ~= nil and tab.ch[line.channel] == true)
    end
    return tab.show[g] == true
end

-- Does the tab pick anything at all? (an empty new tab says how to fill it)
function ns.TabPicksNothing(tab)
    if tab.who then return false end
    if tab.allCh then return false end
    for _, v in pairs(tab.show or {}) do if v then return false end end
    for _, v in pairs(tab.ch or {}) do if v then return false end end
    return true
end

local function refresh()
    ns.LayoutTabs()
    ns.Redraw()
end

local function visibleCount()
    local n = 0
    for _, t in ipairs(ns.DB().tabs) do if not t.hidden then n = n + 1 end end
    return n
end

local function indexOf(tab)
    for i, t in ipairs(ns.DB().tabs) do if t == tab then return i end end
end

-- the next shown tab to the left (-1) or right (+1), skipping hidden ones
local function neighbour(i, dir)
    local tabs = ns.DB().tabs
    local j = i + dir
    while tabs[j] and tabs[j].hidden do j = j + dir end
    return tabs[j] and j or nil
end

function ns.HideTab(tab, hide)
    if hide and visibleCount() <= 1 then
        print("|cff00c7ffVoidChat|r: at least one tab stays shown.")
        return
    end
    tab.hidden = hide or nil
    if hide and ns.DB().tab == tab.key then
        ns.SelectTab(ns.FirstShownTab())   -- (SelectTab also resets the scroll: Sol review)
        return
    end
    refresh()
end

function ns.FirstShownTab()
    for _, t in ipairs(ns.DB().tabs) do if not t.hidden then return t.key end end
    return "all"
end

----------------------------------------------------------------------
-- Name pop-up (rename / new tab)
----------------------------------------------------------------------
local function editBoxOf(popup)
    return (popup.GetEditBox and popup:GetEditBox()) or popup.editBox or popup.EditBox
end

local function acceptName(popup)
    local eb = editBoxOf(popup)
    local text = eb and eb:GetText()
    if type(text) ~= "string" then return end
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then return end
    -- (no byte cut here: maxLetters already caps it by letters, and a byte cut can split a UTF-8 letter)
    if popup.data and popup.data.done then popup.data.done(text) end
end

StaticPopupDialogs["VOIDCHAT_TAB_NAME"] = {
    text = "%s",
    button1 = OKAY or "OK",
    button2 = CANCEL or "Cancel",
    hasEditBox = true,
    maxLetters = 24,
    OnShow = function(self, data)
        local eb = editBoxOf(self)
        if eb then
            eb:SetText((data and data.current) or "")
            eb:HighlightText()
            eb:SetFocus()
        end
    end,
    OnAccept = function(self) acceptName(self) end,
    EditBoxOnEnterPressed = function(eb)
        local popup = eb:GetParent()
        acceptName(popup)
        popup:Hide()
    end,
    EditBoxOnEscapePressed = function(eb) eb:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

function ns.AskName(title, current, done)
    StaticPopup_Show("VOIDCHAT_TAB_NAME", title, nil, { current = current, done = done })
end

function ns.NewTab()
    ns.AskName("Name the new tab (a channel's name, like LookingForGroup, picks that channel):", "", function(name)
        local tab = { key = ("c%d%03d"):format(time(), math.random(0, 999)), label = name, show = {}, custom = true }
        -- a channel's name: the tab shows that channel straight away
        for _, ch in ipairs(ns.ChannelNames()) do
            if ch:lower() == name:lower() then tab.ch = { [ch] = true } break end
        end
        table.insert(ns.DB().tabs, tab)
        ns.SelectTab(tab.key)
    end)
end

function ns.ResetTabs()
    local d = ns.DB()
    d.tabs = ns.DefaultTabs()
    d.tab = "all"
    refresh()
end

----------------------------------------------------------------------
-- Right-click menu of a tab
----------------------------------------------------------------------
local function toggleChannel(tab, name)
    if tab.allCh then
        -- "every channel" was on: keep all the others, drop this one
        tab.allCh = nil
        tab.ch = {}
        for _, n in ipairs(ns.ChannelNames()) do if n ~= name then tab.ch[n] = true end end
    else
        tab.ch = tab.ch or {}
        tab.ch[name] = (not tab.ch[name]) or nil
    end
    refresh()
end

-- what the tab shows: groups, then channels (fills a menu or a submenu)
local function fillShows(menu, tab)
    for _, g in ipairs(ns.GROUPS) do
        menu:CreateCheckbox(g.label, function() return tab.show[g.key] == true end, function()
            tab.show[g.key] = (not tab.show[g.key]) or nil
            refresh()
        end)
    end
    menu:CreateDivider()
    menu:CreateTitle("Channels")
    menu:CreateCheckbox("Every channel", function() return tab.allCh == true end, function()
        tab.allCh = (not tab.allCh) or nil
        if tab.allCh then tab.ch = nil end
        refresh()
    end)
    for _, name in ipairs(ns.ChannelNames()) do
        menu:CreateCheckbox(name, function()
            return tab.allCh == true or (tab.ch ~= nil and tab.ch[name] == true)
        end, function() toggleChannel(tab, name) end)
    end
end

function ns.TabMenu(owner, tab)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle(tab.label)
        root:CreateButton("Rename...", function()
            ns.AskName("Rename the tab:", tab.label, function(name) tab.label = name; refresh() end)
        end)
        fillShows(root:CreateButton("What it shows"), tab)
        local function move(dir)
            local a = indexOf(tab)
            local b = a and neighbour(a, dir)
            if b then local t = ns.DB().tabs; t[a], t[b] = t[b], t[a]; refresh() end
        end
        local i = indexOf(tab)
        if i and neighbour(i, -1) then root:CreateButton("Move left", function() move(-1) end) end
        if i and neighbour(i, 1) then root:CreateButton("Move right", function() move(1) end) end
        if visibleCount() > 1 then
            root:CreateButton("Hide this tab", function() ns.HideTab(tab, true) end)
        end
        if tab.custom then
            root:CreateButton("|cffff6060Delete this tab|r", function()
                local d = ns.DB()
                local at = indexOf(tab)
                if at then table.remove(d.tabs, at) end
                if visibleCount() == 0 then d.tabs = ns.DefaultTabs() end
                if d.tab == tab.key then ns.SelectTab(ns.FirstShownTab()) else refresh() end
            end)
        end
        root:CreateDivider()
        root:CreateButton("New tab...", ns.NewTab)
    end)
end

-- The settings menu's "Tabs" part: show / hide each, new, reset.
function ns.FillTabsMenu(menu)
    for _, t in ipairs(ns.DB().tabs) do
        menu:CreateCheckbox(t.label, function() return not t.hidden end, function() ns.HideTab(t, not t.hidden) end)
    end
    menu:CreateDivider()
    menu:CreateButton("New tab...", ns.NewTab)
    menu:CreateButton("Put the tabs back as they started", ns.ResetTabs)
end
