-- NZR Forever - Cadres joueur / cible au style du jeu, plus lisibles
-- Portrait rond ou carré cerclé d'or, pastille de niveau, nom doré, barres du
-- jeu en relief et texte centré bien contrasté. Plusieurs styles de texte et la
-- couleur de classe en option. Désactivé de base (Réglages > Cadres).
local _, NZR = ...
local M = NZR:Module("Frames")
local plain = NZR.plain
local MEDIA = "Interface\\AddOns\\NZRForever\\Media\\uf\\"
local BAR = "Interface\\TargetingFrame\\UI-StatusBar"

local PANEL_W, PORT, PANEL_H = 214, 62, 52
local frames = {}

local function DB() return NZR.db end

local hider = CreateFrame("Frame")
hider:Hide()

local function HideBlizzard(frame)
    if not frame then return end
    pcall(frame.UnregisterAllEvents, frame)
    pcall(frame.SetParent, frame, hider)
end

---------------------------------------------------------------------------
-- Couleurs
---------------------------------------------------------------------------
local function ClassRGB(unit)
    local ok, _, cls = pcall(UnitClass, unit)
    if ok and plain(cls) then
        local c = (C_ClassColor and C_ClassColor.GetClassColor and C_ClassColor.GetClassColor(cls)) or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[cls])
        if c then return c.r, c.g, c.b end
    end
end

local function ReactionRGB(unit)
    local ok, tapped = pcall(UnitIsTapDenied, unit)
    if ok and plain(tapped) and tapped then return 0.5, 0.5, 0.5 end
    -- tout ce qu'on peut attaquer (ennemi ou neutre) : rouge
    local oka, atk = pcall(UnitCanAttack, "player", unit)
    if oka and plain(atk) and atk then return 0.8, 0.1, 0.08 end
    local ok2, r = pcall(UnitReaction, unit, "player")
    if ok2 and plain(r) then
        if r <= 2 then return 0.85, 0.15, 0.12
        elseif r == 3 then return 0.9, 0.45, 0.1
        elseif r == 4 then return 0.95, 0.85, 0.2 end
    end
    return 0.1, 0.8, 0.1
end

local function HealthRGB(unit)
    if DB().ufColor == "class" then
        if UnitIsPlayer(unit) then
            local r, g, b = ClassRGB(unit)
            if r then return r, g, b end
        else
            return ReactionRGB(unit)
        end
    end
    return 0.1, 0.8, 0.1                      -- vert du jeu
end

---------------------------------------------------------------------------
-- Construction (style du jeu : panneau sombre, liseré doré)
---------------------------------------------------------------------------
-- boîte comme celles de WoW Forever : liseré noir, liseré or, fond sombre
local GOLD = { 0.78, 0.62, 0.30 }
local function ForeverBox(f, top, bottom)
    local function edge(layer, sub, inset, r, g, b, a)
        for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
            local t = f:CreateTexture(nil, layer, nil, sub)
            t:SetColorTexture(r, g, b, a or 1)
            if side == "TOP" or side == "BOTTOM" then
                t:SetPoint(side .. "LEFT", inset, side == "TOP" and -inset or inset)
                t:SetPoint(side .. "RIGHT", -inset, side == "TOP" and -inset or inset)
                t:SetHeight(1)
            else
                t:SetPoint("TOP" .. side, side == "LEFT" and inset or -inset, -inset)
                t:SetPoint("BOTTOM" .. side, side == "LEFT" and inset or -inset, inset)
                t:SetWidth(1)
            end
        end
    end
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", 1, -1); bg:SetPoint("BOTTOMRIGHT", -1, 1)
    bg:SetColorTexture(1, 1, 1, 1)
    bg:SetGradient("VERTICAL", CreateColor(bottom[1], bottom[2], bottom[3], bottom[4] or 1), CreateColor(top[1], top[2], top[3], top[4] or 1))
    edge("BORDER", 0, 0, 0, 0, 0, 1)
    edge("BORDER", 1, 1, GOLD[1], GOLD[2], GOLD[3], 1)
end

local function Bar(parent, h)
    local b = CreateFrame("StatusBar", nil, parent)
    b:SetStatusBarTexture(BAR)
    b:SetHeight(h)
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(0.03, 0.03, 0.03, 0.9)
    local edge = b:CreateTexture(nil, "BACKGROUND", nil, -1)
    edge:SetPoint("TOPLEFT", -1, 1); edge:SetPoint("BOTTOMRIGHT", 1, -1); edge:SetColorTexture(0, 0, 0, 1)
    local shine = b:CreateTexture(nil, "OVERLAY")
    shine:SetPoint("TOPLEFT"); shine:SetPoint("TOPRIGHT"); shine:SetHeight(1)
    shine:SetColorTexture(1, 1, 1, 0.10)
    local function Text(size, justify)
        local fs = b:CreateFontString(nil, "OVERLAY")
        fs:SetFont(STANDARD_TEXT_FONT, size, "OUTLINE")
        fs:SetShadowColor(0, 0, 0, 1); fs:SetShadowOffset(1, -1)
        fs:SetJustifyH(justify)
        return fs
    end
    b.center = Text(h >= 14 and 11 or 9, "CENTER")
    b.center:SetPoint("CENTER", 0, 0)
    b.right = Text(10, "RIGHT")
    b.right:SetPoint("RIGHT", -4, 0)
    b.right:SetTextColor(0.9, 0.9, 0.9)
    return b
end

local function Create(unit, holderKey, default, mirror)
    local hd = NZR:Holder(holderKey, unit == "player" and "Joueur" or "Cible", PANEL_W + PORT - 12, PORT + 6, default)
    local f = CreateFrame("Button", "NZRF_UF_" .. unit, UIParent, "SecureUnitButtonTemplate")
    f.unit, f.mirror = unit, mirror
    f:SetSize(PANEL_W + PORT - 12, PORT + 6)
    f:SetPoint("CENTER", hd, "CENTER")
    f:SetAttribute("unit", unit)
    f:SetAttribute("*type1", "target")
    f:SetAttribute("*type2", "togglemenu")
    f:RegisterForClicks("AnyUp")
    f:SetScale(DB().ufScale or 1)

    -- panneau : bandeau du nom (brun doré) + boîte des barres (sombre), comme Forever
    local p = CreateFrame("Frame", nil, f)
    p:SetSize(PANEL_W, PANEL_H)
    if mirror then p:SetPoint("RIGHT", f, "RIGHT", -(PORT - 12), 0) else p:SetPoint("LEFT", f, "LEFT", PORT - 12, 0) end
    f.panel = p

    local nameBox = CreateFrame("Frame", nil, p)
    nameBox:SetPoint("TOPLEFT"); nameBox:SetPoint("TOPRIGHT"); nameBox:SetHeight(20)
    ForeverBox(nameBox, { 0.30, 0.22, 0.12, 0.95 }, { 0.16, 0.11, 0.06, 0.95 })
    f.name = nameBox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.name:SetPoint("LEFT", mirror and 8 or 16, 0)
    f.name:SetPoint("RIGHT", mirror and -16 or -8, 0)
    f.name:SetJustifyH("CENTER")
    f.name:SetWordWrap(false)

    local barBox = CreateFrame("Frame", nil, p)
    barBox:SetPoint("TOPLEFT", nameBox, "BOTTOMLEFT", 0, -1); barBox:SetPoint("TOPRIGHT", nameBox, "BOTTOMRIGHT", 0, -1)
    barBox:SetHeight(PANEL_H - 21)
    ForeverBox(barBox, { 0.05, 0.05, 0.05, 0.85 }, { 0.02, 0.02, 0.02, 0.85 })
    f.barBox = barBox

    local l, r = mirror and 4 or 12, mirror and -12 or -4
    f.health = Bar(barBox, 15)
    f.health:SetPoint("TOPLEFT", l, -4); f.health:SetPoint("TOPRIGHT", r, -4)
    f.power = Bar(barBox, 9)
    f.power:SetPoint("TOPLEFT", f.health, "BOTTOMLEFT", 0, -2); f.power:SetPoint("TOPRIGHT", f.health, "BOTTOMRIGHT", 0, -2)

    -- portrait rond ou carré, cerclé d'or
    local pf = CreateFrame("Frame", nil, f)
    pf:SetSize(PORT, PORT)
    pf:SetFrameLevel(p:GetFrameLevel() + 3)
    if mirror then pf:SetPoint("RIGHT", f, "RIGHT", 0, 0) else pf:SetPoint("LEFT", f, "LEFT", 0, 0) end
    local square = DB().ufPortrait == "square"
    f.portrait = pf:CreateTexture(nil, "ARTWORK")
    f.portrait:SetPoint("TOPLEFT", 5, -5); f.portrait:SetPoint("BOTTOMRIGHT", -5, 5)
    local mask = pf:CreateMaskTexture()
    mask:SetTexture(MEDIA .. (square and "mask_square" or "mask_round"), "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(f.portrait)
    f.portrait:AddMaskTexture(mask)
    local back = pf:CreateTexture(nil, "BACKGROUND")
    back:SetAllPoints(f.portrait); back:SetColorTexture(0.05, 0.04, 0.03, 1); back:AddMaskTexture(mask)
    local ring = pf:CreateTexture(nil, "OVERLAY")
    ring:SetAllPoints(); ring:SetTexture(MEDIA .. (square and "ring_square" or "ring_round"))

    -- pastille de niveau
    local lv = CreateFrame("Frame", nil, pf)
    lv:SetSize(26, 26)
    lv:SetFrameLevel(pf:GetFrameLevel() + 2)
    if mirror then lv:SetPoint("CENTER", pf, "BOTTOMRIGHT", -6, 6) else lv:SetPoint("CENTER", pf, "BOTTOMLEFT", 6, 6) end
    local lvt = lv:CreateTexture(nil, "ARTWORK"); lvt:SetAllPoints(); lvt:SetTexture(MEDIA .. "level")
    f.level = lv:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.level:SetPoint("CENTER", 0, 0)

    -- élite / rare : petit mot doré sous le nom
    f.tag = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.tag:SetPoint("BOTTOM", p, "TOP", 0, 2)
    f.tag:SetTextColor(1, 0.82, 0)

    frames[unit] = f
    return f
end

---------------------------------------------------------------------------
-- Mises à jour
---------------------------------------------------------------------------
local function Fmt(v)
    if DB().ufShort ~= false then return NZR.Abbrev(v) end
    if plain(v) then return tostring(math.floor(v + 0.5)) end
    return v
end

local function Percent(unit, cur, max, powerType)
    if not powerType and UnitHealthPercent and CurveConstants and CurveConstants.ScaleTo100 then
        local ok, p = pcall(UnitHealthPercent, unit, true, CurveConstants.ScaleTo100)
        if ok and p ~= nil then
            local ok2, s = pcall(string.format, "%.0f %%", p)
            if ok2 then return s end
        end
    end
    if plain(cur) and plain(max) and max > 0 then return ("%.0f %%"):format(cur / max * 100) end
end

local function SetBarText(bar, unit, cur, max, isPower)
    local mode = DB().ufText or "both"
    local pct = Percent(unit, cur, max, isPower)
    local values
    local ok, s = pcall(string.format, "%s / %s", Fmt(cur), Fmt(max))
    values = ok and s or nil
    if mode == "none" then
        bar.center:SetText(""); bar.right:SetText("")
    elseif mode == "percent" then
        NZR.SafeText(bar.center, pct or ""); bar.right:SetText("")
    elseif mode == "values" then
        NZR.SafeText(bar.center, values or ""); bar.right:SetText("")
    else
        NZR.SafeText(bar.center, values or "")
        NZR.SafeText(bar.right, isPower and "" or (pct or ""))
    end
end

local function UpdateHealth(f)
    local u = f.unit
    if not UnitExists(u) then return end
    local cur, max = UnitHealth(u), UnitHealthMax(u)
    f.health:SetMinMaxValues(0, max)
    f.health:SetValue(cur)
    f.health:SetStatusBarColor(HealthRGB(u))
    local okd, dead = pcall(UnitIsDeadOrGhost, u)
    if okd and plain(dead) and dead then
        f.health.center:SetText(UnitIsGhost(u) and "Fantôme" or "Mort"); f.health.right:SetText("")
        return
    end
    SetBarText(f.health, u, cur, max)
end

local function UpdatePower(f)
    local u = f.unit
    if not UnitExists(u) then return end
    local max = UnitPowerMax(u)
    local hasPower
    if plain(max) then hasPower = max > 0; f.lastHasPower = hasPower
    else hasPower = f.lastHasPower ~= false end
    f.power:SetShown(hasPower)
    f.barBox:SetHeight(hasPower and PANEL_H - 21 or PANEL_H - 32)
    if not hasPower then return end
    local cur = UnitPower(u)
    f.power:SetMinMaxValues(0, max)
    f.power:SetValue(cur)
    local _, token = UnitPowerType(u)
    local c = plain(token) and PowerBarColor and PowerBarColor[token]
    if c then f.power:SetStatusBarColor(c.r, c.g, c.b) else f.power:SetStatusBarColor(0, 0.4, 1) end
    SetBarText(f.power, u, cur, max, true)
end

local function UpdateInfo(f)
    local u = f.unit
    if not UnitExists(u) then return end
    f.lastHasPower = nil
    NZR.SafeText(f.name, UnitName(u))
    if UnitIsPlayer(u) and DB().ufColor == "class" then
        local r, g, b = ClassRGB(u); if r then f.name:SetTextColor(r, g, b) end
    else
        f.name:SetTextColor(1, 0.82, 0)
    end
    local lvl = UnitLevel(u)
    if plain(lvl) then
        f.level:SetText(lvl > 0 and lvl or "??")
        local diff = (u ~= "player") and GetCreatureDifficultyColor and GetCreatureDifficultyColor(lvl > 0 and lvl or 999)
        if diff then f.level:SetTextColor(diff.r, diff.g, diff.b) else f.level:SetTextColor(1, 0.82, 0) end
    else
        NZR.SafeText(f.level, lvl)
    end
    local okc, cl = pcall(UnitClassification, u)
    local tag = ""
    if okc and plain(cl) then
        if cl == "worldboss" then tag = "Boss" elseif cl == "elite" then tag = "Élite"
        elseif cl == "rareelite" then tag = "Rare élite" elseif cl == "rare" then tag = "Rare" end
    end
    f.tag:SetText(tag)
    SetPortraitTexture(f.portrait, u)
end

local function UpdateAll(f)
    pcall(UpdateInfo, f); pcall(UpdateHealth, f); pcall(UpdatePower, f)
end
NZR.FramesRefresh = function() for _, f in pairs(frames) do UpdateAll(f) end end

local function Events(f)
    local u = f.unit
    for _, ev in ipairs({ "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_POWER_UPDATE", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER",
                          "UNIT_NAME_UPDATE", "UNIT_LEVEL", "UNIT_PORTRAIT_UPDATE", "UNIT_MODEL_CHANGED", "UNIT_FACTION" }) do
        pcall(f.RegisterUnitEvent, f, ev, u)
    end
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    if u == "target" then f:RegisterEvent("PLAYER_TARGET_CHANGED") end
    f:SetScript("OnEvent", function(self, ev)
        if ev == "UNIT_HEALTH" or ev == "UNIT_MAXHEALTH" then pcall(UpdateHealth, self)
        elseif ev == "UNIT_POWER_UPDATE" or ev == "UNIT_MAXPOWER" or ev == "UNIT_DISPLAYPOWER" then pcall(UpdatePower, self)
        else UpdateAll(self) end
    end)
end

function M:Init()
    if NZR.withUI or not DB().unitFrames then return end
    local pf = Create("player", "uf_player", { "CENTER", "CENTER", -260, -170 }, false)
    local tf = Create("target", "uf_target", { "CENTER", "CENTER", 260, -170 }, true)
    HideBlizzard(PlayerFrame)
    HideBlizzard(TargetFrame)
    RegisterUnitWatch(pf)
    RegisterUnitWatch(tf)
    Events(pf); Events(tf)
    UpdateAll(pf)
    NZR.FramesScale = function()
        if InCombatLockdown() then return end
        for _, f in pairs(frames) do f:SetScale(DB().ufScale or 1) end
    end
end
