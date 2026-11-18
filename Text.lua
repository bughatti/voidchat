----------------------------------------------------------------------
-- VoidChat text helpers: secret checks, plain text for copy and search,
-- short channel tags, and which tab a line belongs to.
--
-- Midnight (12.x) can hand addons chat text as a SECRET value (in
-- instanced combat). A secret line can be shown (FontString:SetText takes
-- it) but never read, compared, searched or copied. Every helper here
-- checks first and leaves a secret line alone.
----------------------------------------------------------------------
local _, ns = ...

local issecret = _G.issecretvalue
function ns.Secret(v)
    -- never compare v first (a secret can't even be compared with nil)
    return issecret ~= nil and issecret(v) == true
end

-- Plain text: colors, textures and atlas icons gone, links shown as their [name].
-- BattleTag names (|K...|k) are protected: they can't be read, so "[friend]".
function ns.Plain(s)
    if type(s) ~= "string" or ns.Secret(s) then return nil end
    s = s:gsub("||", "\1")   -- an escaped pipe is text, not a code: set it aside
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|cn[%w_]+:", ""):gsub("|r", "")
    s = s:gsub("|H.-|h(.-)|h", "%1")
    s = s:gsub("|T.-|t", ""):gsub("|A.-|a", "")
    s = s:gsub("|K.-|k", "[friend]")
    s = s:gsub("\1", "|")
    return s
end

-- "[2. Trade - City]" -> "[T]". The game's own short names where we know them, else the number.
local SHORT = {
    General = "G", Trade = "T", LocalDefense = "LD", WorldDefense = "WD",
    LookingForGroup = "LFG", Services = "S", GuildRecruitment = "GR", NewcomerChat = "N",
}
function ns.ShortChannels(s)
    if type(s) ~= "string" or ns.Secret(s) then return s end
    return (s:gsub("(|Hchannel:[^|]-|h)%[(%d+)%. ([^%]]-)%](|h)", function(open, num, name, close)
        local base = name:match("^(.-) %- ") or name
        base = base:gsub("%s*%(.-%)", "")
        local tag = SHORT[base:gsub("%s", "")] or num
        return open .. "[" .. tag .. "]" .. close
    end))
end

-- Tabs (kinds). A line's kind comes from the chat event, never from its text,
-- except Void addon lines (prints have no event): those are told by their prefix.
local KIND = {
    WHISPER = "whisper", WHISPER_INFORM = "whisper", BN_WHISPER = "whisper", BN_WHISPER_INFORM = "whisper",
    BN_WHISPER_PLAYER_OFFLINE = "whisper", AFK = "whisper", DND = "whisper",
    GUILD = "guild", OFFICER = "guild", GUILD_ACHIEVEMENT = "guild", GUILD_ITEM_LOOTED = "guild",
    PARTY = "group", PARTY_LEADER = "group", RAID = "group", RAID_LEADER = "group", RAID_WARNING = "group",
    INSTANCE_CHAT = "group", INSTANCE_CHAT_LEADER = "group",
    CHANNEL = "channel", COMMUNITIES_CHANNEL = "channel",
    -- Loot = items, currency, coin: who got what. XP, reputation and skill lines stay in All.
    LOOT = "loot", MONEY = "loot", CURRENCY = "loot",
}
ns.WHISPER_IN = { WHISPER = true, BN_WHISPER = true }

function ns.KindOf(event, text)
    if type(event) == "string" and not ns.Secret(event) then
        local t = event:match("^CHAT_MSG_(.+)$")
        if t and t:match("^CHANNEL%d+$") then return "channel", t end   -- ChatTypeInfo.CHANNEL5
        return t and KIND[t] or "other", t
    end
    -- no event: an addon's print. Void addons start with their colored name.
    if type(text) == "string" and not ns.Secret(text) then
        local head = text:sub(1, 40):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        if head:match("^%[?Void%u%a+%]?[:%s]") then return "void" end
    end
    return "other"
end

-- A name for a whisper tab: "Name" on your realm, "Name-Realm" otherwise.
function ns.ShortName(name)
    if type(name) ~= "string" or ns.Secret(name) or name == "" then return nil end
    if Ambiguate then
        local ok, s = pcall(Ambiguate, name, "none")
        if ok and type(s) == "string" then return s end
    end
    return name
end
