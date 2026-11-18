----------------------------------------------------------------------
-- VoidChat start-up: build the window, hide Blizzard's chat window, and put
-- Blizzard's edit box (where you type) under ours.
--
-- Blizzard's chat frames keep running hidden: they still get every event and
-- format every line (that's where we read them). Only what you see goes.
-- The edit box is Blizzard's own, untouched apart from its spot: it already
-- sits on UIParent in 12.x (ChatFrameEditBoxMixin:OnLoad), so hiding the chat
-- frames doesn't hide it, and slash commands and macros keep working.
-- Off switch: the settings menu ("Hide Blizzard's chat window", reloads).
----------------------------------------------------------------------
local ADDON, ns = ...

local hider = CreateFrame("Frame")
hider:Hide()

local function park(f)
    if f and f.SetParent and not f.voidChatParked then
        f.voidChatParked = true
        f:SetParent(hider)
    end
end

-- Tabs get moved between parents by Blizzard's dock code: keep them hidden instead.
local function keepHidden(f)
    if not f or f.voidChatHidden then return end
    f.voidChatHidden = true
    f:HookScript("OnShow", function(self) self:Hide() end)
    f:Hide()
end

local function anchorEditBox(eb)
    if not (eb and ns.W.frame) then return end
    eb:ClearAllPoints()
    eb:SetPoint("TOPLEFT", ns.W.frame, "BOTTOMLEFT", -5, 2)
    eb:SetPoint("TOPRIGHT", ns.W.frame, "BOTTOMRIGHT", 5, 2)
end

local function hideFrame(f, name)
    park(f)
    keepHidden(_G[name .. "Tab"])
    park(_G[name .. "Minimized"])
    anchorEditBox(_G[name .. "EditBox"] or f.editBox)
end

local function hideBlizzard()
    ns.EachChatFrame(hideFrame)   -- the numbered windows and every whisper window
    for _, n in ipairs({ "GeneralDockManager", "ChatFrameMenuButton", "ChatFrameChannelButton",
                         "ChatFrameToggleVoiceDeafenButton", "ChatFrameToggleVoiceMuteButton",
                         "TextToSpeechButtonFrame" }) do
        park(_G[n])
    end
end

-- Where Blizzard's chat was: our window starts there (once; after that it's yours).
local function startSpot()
    local cf = _G.ChatFrame1
    local d = ns.DB()
    if d.placedFromBlizzard or not cf then return end
    d.placedFromBlizzard = true
    local l, b, w, h = cf:GetLeft(), cf:GetBottom(), cf:GetWidth(), cf:GetHeight()
    if not (l and b and w and h) or ns.Secret(l) then return end
    local s = cf:GetEffectiveScale() / UIParent:GetEffectiveScale()
    d.w = math.max(300, math.floor(w * s + 0.5))
    d.h = math.max(120, math.floor(h * s + 0.5) + 22)
    d.home = { math.floor(l * s + 0.5), math.floor(b * s + 0.5) }
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON then
        ns.loaded = true   -- our saved variables are in: ns.DB() uses them from now on
        ns.DB()
        ns.HookAll()
    elseif event == "PLAYER_LOGIN" then
        local d = ns.DB()
        startSpot()
        ns.Build()
        if d.hideBlizzard then
            hideBlizzard()
            if type(_G.FCF_OpenTemporaryWindow) == "function" then
                hooksecurefunc("FCF_OpenTemporaryWindow", hideBlizzard)
            end
        end
        ns.SelectTab(d.tab)
    end
end)
