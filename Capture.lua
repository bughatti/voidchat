----------------------------------------------------------------------
-- VoidChat capture: every line Blizzard's chat frames show, after Blizzard
-- formatted it (links, colors, channel names, censoring all done by the game).
--
-- Why a hook and not our own event handler: Blizzard's chat engine and its
-- edit box are secure code in 12.x (slash commands, macros). We leave them
-- alone and only post-hook each chat frame's AddMessage:
--   AddMessage(text, r, g, b, chatTypeID, accessID, typeID, event, eventArgs, formatter)
-- A print() arrives with only text (and maybe a color).
--
-- One message can land in several Blizzard frames (General and a Whisper tab):
-- it is kept once. Player chat carries a line ID (event arg 11): the key.
-- Other lines: the Nth copy of a text in one frame this frame-time is kept only
-- if no frame had N yet (two identical loot lines stay two). A SECRET line can't
-- be compared: its event name is the key instead.
--
-- LOOT lines are read from CHAT_MSG_LOOT directly, not from the frames: the
-- user, 2026-11-17, in Uldaman: "trying to figure out who looted the staff in
-- the group and i had no way to figure it out". Blizzard's frames show loot only
-- if your chat settings say so; the event always comes. So the Loot tab has every
-- item anyone in your group got (that the game tells your client about).
--
-- History is SESSION ONLY (the user, 2026-11-17): other players' lines never
-- go to SavedVariables.
--
-- Secret values: never compare one, not even with nil. type() is allowed.
----------------------------------------------------------------------
local _, ns = ...

local MAX = 1500
ns.lines = {}            -- oldest first; each { text, r, g, b, kind, who, looter, t, secret }
ns.listeners = {}

local hooked = {}
local seenID = {}
local frameCount, taken = {}, {}
local lastNow

local function resetFrameKeys(now)
    if now ~= lastNow then
        lastNow = now
        wipe(frameCount); wipe(taken)
    end
end

local function isCombatLog(f)
    if f == _G.ChatFrame2 then return true end
    local n = f.GetName and f:GetName()
    local tab = type(n) == "string" and _G[n .. "Tab"]
    local label = tab and tab.GetText and tab:GetText()
    if type(label) ~= "string" or ns.Secret(label) then return false end
    return label == (_G.COMBAT_LOG or "Combat Log")
end

local function store(text, r, g, b, event, eventArgs, forceKind)
    if ns.Secret(r) or ns.Secret(g) or ns.Secret(b) then r, g, b = 1, 1, 1 end
    local secret = ns.Secret(text)
    local kind, chatType = ns.KindOf(event, text)
    if forceKind then kind = forceKind end
    local who, looter
    if type(eventArgs) == "table" then
        if kind == "whisper" then who = ns.ShortName(eventArgs[2]) end
        if kind == "loot" then looter = ns.ShortName(eventArgs[2]) end
    end
    local line = {
        text = text, r = tonumber(r) or 1, g = tonumber(g) or 1, b = tonumber(b) or 1,
        kind = kind, chatType = chatType, who = who, looter = looter, t = time(), secret = secret,
    }
    -- which channel ("Trade", "LookingForGroup"): tabs can pick channels by name (Tabs.lua)
    if kind == "channel" then line.channel = ns.ChannelName(eventArgs, not secret and text or nil) end
    if not secret then line.text = ns.ShortChannels(text) end
    local L = ns.lines
    L[#L + 1] = line
    if #L > MAX then table.remove(L, 1) end
    for _, fn in ipairs(ns.listeners) do fn(line) end
    return line
end
ns.Store = store

-- Blizzard copying old lines into another window: FCF_OpenTemporaryWindow (a whisper window)
-- and ChatFrameUtil.PopOutChat (moving a channel) re-add each line with its access ID. A live
-- channel notice also has an access ID (ChatFrameOverrides.lua, INVITE / YOU_CHANGED), and
-- joining a channel again repeats its text, so the access ID alone doesn't make a copy: the
-- call stack has to name one of the two copy functions (Codex, 2026-11-18).
local function copyingHistory()
    if type(debugstack) ~= "function" then return false end
    local ok, st = pcall(debugstack, 3, 12, 0)
    if not ok or type(st) ~= "string" or ns.Secret(st) then return false end   -- a stack can be secret
    return st:find("OpenTemporaryWindow", 1, true) ~= nil or st:find("PopOutChat", 1, true) ~= nil
end

-- A plain text we already have among the last lines.
local function recentText(text)
    local L = ns.lines
    for i = #L, math.max(1, #L - 300), -1 do
        local l = L[i]
        if not l.secret and l.raw == text then return true end
    end
    return false
end

-- Blizzard shows system, loot, coin, XP, skill... lines with only the chat type's number
-- (AddMessage(arg1, r, g, b, info.id), ChatFrameOverrides.lua), no event name. The number
-- is ChatTypeInfo[type].id = GetChatTypeIndex(type): turn it back into the type.
local idToType
local function typeOfID(id)
    if type(id) ~= "number" or ns.Secret(id) or type(_G.ChatTypeInfo) ~= "table" then return nil end
    if not idToType or not idToType[id] then
        idToType = {}
        for t, info in pairs(_G.ChatTypeInfo) do
            if type(info) == "table" and type(info.id) == "number" then idToType[info.id] = t end
        end
    end
    return idToType[id]
end

local function onAdd(frame, text, r, g, b, chatTypeID, accessID, typeID, event, eventArgs)
    if type(text) == "nil" then return end
    local secretText = ns.Secret(text)
    local given = (type(event) == "string" and not ns.Secret(event)) and event or nil
    local ev = given
    if not ev then
        local t = typeOfID(chatTypeID)
        if t then ev = "CHAT_MSG_" .. t end
    end
    if ns.LOOT_EVENTS[ev or ""] then return end          -- read from the event itself
    local now = GetTime()
    resetFrameKeys(now)

    local lineID = type(eventArgs) == "table" and eventArgs[11] or nil
    if ns.Secret(lineID) then lineID = nil end
    if type(lineID) == "number" and lineID > 0 and ev then
        local key = ev .. ":" .. lineID
        if seenID[key] then return end
        seenID[key] = now
    else
        local key
        if not secretText then
            if type(text) ~= "string" then return end
            -- an old line copied again (no event, but a chat access ID): not new
            if not given and type(accessID) == "number" and not ns.Secret(accessID)
                and recentText(text) and copyingHistory() then return end
            key = text
        else
            key = ev or "?secret"
        end
        local k = tostring(frame) .. "\1" .. key
        local n = (frameCount[k] or 0) + 1
        frameCount[k] = n
        if n <= (taken[key] or 0) then return end
        taken[key] = n
    end
    -- A print with no chat type: which addon printed it? The call stack names the file. Every
    -- Void addon's line goes to the Void tab, whatever its prefix (VoidDev's "Layer stayed ..."
    -- lines start with "Layer", seen in All on 2026-11-17).
    local fromVoid = false
    if not ev and type(debugstack) == "function" then
        local ok, st = pcall(debugstack, 2, 12, 0)
        if ok and type(st) == "string" and not ns.Secret(st) then
            for addon in st:gmatch("AddOns[/\\](Void%w+)[/\\]") do
                if addon ~= "VoidChat" then fromVoid = true break end
            end
        end
    end
    local line = store(text, r, g, b, ev, eventArgs, fromVoid and "void" or nil)
    if not secretText then line.raw = text end
end

-- Line IDs older than 5 minutes are dropped (they only matter within a frame).
local sweep = 0
local function sweepIDs()
    local now = GetTime()
    if now - sweep < 60 then return end
    sweep = now
    for k, t in pairs(seenID) do if now - t > 300 then seenID[k] = nil end end
end

function ns.HookFrame(f)
    if type(f) ~= "table" or hooked[f] or type(f.AddMessage) ~= "function" or isCombatLog(f) then return end
    hooked[f] = true
    hooksecurefunc(f, "AddMessage", function(...) onAdd(...); sweepIDs() end)
end

-- Every chat frame there is: the numbered ones and Blizzard's own list (whisper windows).
function ns.EachChatFrame(fn)
    for i = 1, (_G.NUM_CHAT_WINDOWS or 10) do
        local f = _G["ChatFrame" .. i]
        if f then fn(f, "ChatFrame" .. i) end
    end
    if type(_G.CHAT_FRAMES) == "table" then
        for _, name in pairs(_G.CHAT_FRAMES) do
            local f = type(name) == "string" and _G[name]
            if f then fn(f, name) end
        end
    end
end

function ns.HookAll() ns.EachChatFrame(ns.HookFrame) end

-- Whisper pop-out windows come and go.
if type(_G.FCF_OpenTemporaryWindow) == "function" then
    hooksecurefunc("FCF_OpenTemporaryWindow", function() ns.HookAll() end)
end

----------------------------------------------------------------------
-- Loot, straight from the event: who got what.
----------------------------------------------------------------------
ns.LOOT_EVENTS = { CHAT_MSG_LOOT = true, CHAT_MSG_CURRENCY = true, CHAT_MSG_MONEY = true }
local lootSeen = {}
local loot = CreateFrame("Frame")
for e in pairs(ns.LOOT_EVENTS) do loot:RegisterEvent(e) end
loot:SetScript("OnEvent", function(_, event, ...)
    local text = ...
    if type(text) == "nil" then return end
    local args = { ... }
    local lineID = args[11]
    if type(lineID) == "number" and not ns.Secret(lineID) and lineID > 0 then
        if lootSeen[lineID] then return end
        lootSeen[lineID] = true
    end
    local info = _G.ChatTypeInfo and _G.ChatTypeInfo[event:sub(10)]
    local r, g, b = 0, 0.67, 0
    if info and type(info.r) == "number" then r, g, b = info.r, info.g, info.b end
    local line = store(text, r, g, b, event, args)
    if not ns.Secret(text) then line.raw = text end
end)

-- Lines Blizzard already showed before we loaded (the login burst): copy them in once.
function ns.Backfill()
    local f = _G.DEFAULT_CHAT_FRAME or _G.ChatFrame1
    if not (f and f.GetNumMessages and f.GetMessageInfo) then return end
    for i = 1, f:GetNumMessages() do
        local text, r, g, b = f:GetMessageInfo(i)
        if type(text) ~= "nil" then
            local line = store(text, r, g, b, nil, nil)
            if not ns.Secret(text) then line.raw = text end
        end
    end
end

-- Hook as early as possible so the login lines are caught; what was already shown first.
ns.Backfill()
ns.HookAll()
