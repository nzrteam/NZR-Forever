-- NZR Forever - Cadres joueur / cible au style du jeu, plus lisibles
-- Portrait rond ou carré cerclé d'or, pastille de niveau, nom doré, barres du
-- jeu en relief et texte centré bien contrasté. Plusieurs styles de texte et la
-- couleur de classe en option. Désactivé de base (Réglages > Cadres).
local _, NZR = ...
local M = NZR:Module("Frames")
local plain = NZR.plain
local MEDIA = "Interface\\AddOns\\NZRForever\\Media\\uf\\"
local BAR = "Interface\\TargetingFrame\\UI-StatusBar"

local PANEL_W, PORT, PANEL_H = 214, 60, 58
local frames = {}
local AURA_SIZE, AURA_PER_ROW, AURA_MAX = 21, 8, 16

-- police des chiffres (réglage « Police » et « Taille du texte »)
local fontStrings = {}
local function GameBarFont()
    local obj = _G.TextStatusBarText
    local f = obj and obj.GetFont and obj:GetFont()
    return f or STANDARD_TEXT_FONT
end
function NZR.FramesFont(fs)
    if fs then fontStrings[fs] = true end
    for s in pairs(fs and { [fs] = true } or fontStrings) do
        local size = math.floor((s.nzrSize or 10) * (NZR.db.ufFontSize or 1) + 0.5)
        local path = NZR.FontPath(NZR.db.ufFont, GameBarFont())
        local flags, shadow = NZR.OutlineFlags(NZR.db.ufOutline or "shadow")
        if not pcall(s.SetFont, s, path, size, flags) then pcall(s.SetFont, s, STANDARD_TEXT_FONT, size, flags) end
        NZR.ApplyShadow(s, shadow)
    end
end

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

-- nuance : < 100 % = plus foncé, > 100 % = plus clair
local function Shade(r, g, b, s)
    s = s or 1
    if s <= 1 then return r * s, g * s, b * s end
    local t = math.min(1, s - 1)
    return r + (1 - r) * t, g + (1 - g) * t, b + (1 - b) * t
end

local function BaseHealthRGB(unit)
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

local function HealthRGB(unit)
    local r, g, b = BaseHealthRGB(unit)
    return Shade(r, g, b, DB().ufHealthShade)
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
        fs.nzrSize = size
        NZR.FramesFont(fs)
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

    -- même cadre que le DPS meter (fenêtre du jeu en réduit) : le nom dans la barre de titre
    local SCALE = 0.58                          -- assez petit pour que les pièces du jeu tiennent sans dépasser
    local over = NZR:WowFrame(p, nil, 0.9, SCALE)
    over:SetFrameLevel(p:GetFrameLevel() + 6)
    local barBox = over
    f.barBox = barBox
    f.name = barBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.name:SetPoint("TOPLEFT", mirror and 8 or 14, -1)
    f.name:SetPoint("TOPRIGHT", mirror and -14 or -8, -1)
    f.name:SetHeight(12)
    f.name:SetJustifyH("CENTER")
    f.name:SetWordWrap(false)

    local l, r = mirror and 9 or 16, mirror and -16 or -9
    f.health = Bar(barBox, 16)
    f.health:SetPoint("TOPLEFT", l, -20); f.health:SetPoint("TOPRIGHT", r, -20)
    -- soins en approche (les tiens et ceux des autres), comme le cadre du jeu :
    -- une barre verte claire qui part du bout de la vie ; coupée au bord de la barre
    do
        local hb = f.health
        local clip = CreateFrame("Frame", nil, hb)
        clip:SetAllPoints(); clip:SetClipsChildren(true)
        clip:SetFrameLevel(hb:GetFrameLevel() + 1)
        local pred = CreateFrame("StatusBar", nil, clip)
        local fill = hb:GetStatusBarTexture()
        pred:SetPoint("TOPLEFT", fill, "TOPRIGHT", 0, 0)
        pred:SetPoint("BOTTOMLEFT", fill, "BOTTOMRIGHT", 0, 0)
        pred:SetStatusBarTexture(BAR)
        pred:SetStatusBarColor(0, 0.83, 0, 0.55)
        pred:SetMinMaxValues(0, 1); pred:SetValue(0)
        local function size() local w = hb:GetWidth(); if w and w > 0 then pred:SetWidth(w) end end
        size(); hb:HookScript("OnSizeChanged", size)
        hb.pred = pred
        -- le texte reste au-dessus de la prévision
        local txt = CreateFrame("Frame", nil, hb)
        txt:SetAllPoints(); txt:SetFrameLevel(hb:GetFrameLevel() + 3)
        hb.center:SetParent(txt); hb.right:SetParent(txt)
    end
    f.power = Bar(barBox, 10)
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
    if square then
        local nsH = CreateFrame("Frame", nil, pf)
        nsH:SetScale(0.5)
        nsH:SetPoint("TOPLEFT", pf, "TOPLEFT", 0, 0)
        nsH:SetSize(PORT / 0.5, PORT / 0.5)
        local ns = CreateFrame("Frame", nil, nsH, "NineSlicePanelTemplate")
        ns:SetAllPoints()
        if not (NineSliceUtil and pcall(NineSliceUtil.ApplyLayoutByName, ns, "Dialog")) then ns:Hide() end
        if ns.Center then ns.Center:Hide() end
        ns:SetFrameLevel(pf:GetFrameLevel() + 1)
        f.portrait:ClearAllPoints()
        f.portrait:SetPoint("TOPLEFT", 4, -4); f.portrait:SetPoint("BOTTOMRIGHT", -4, 4)
        mask:SetAllPoints(f.portrait)
    else
        local ring = pf:CreateTexture(nil, "OVERLAY")
        ring:SetAllPoints(); ring:SetTexture(MEDIA .. "ring_round")
    end

    -- niveau : petite boîte au même bord doré, chiffre centré
    local lv = CreateFrame("Frame", nil, pf)
    lv:SetSize(24, 20)
    lv:SetFrameLevel(pf:GetFrameLevel() + 4)
    if mirror then lv:SetPoint("CENTER", pf, "BOTTOMRIGHT", -4, 4) else lv:SetPoint("CENTER", pf, "BOTTOMLEFT", 4, 4) end
    local lvbg = lv:CreateTexture(nil, "BACKGROUND")
    lvbg:SetPoint("TOPLEFT", 2, -2); lvbg:SetPoint("BOTTOMRIGHT", -2, 2); lvbg:SetColorTexture(0.05, 0.04, 0.03, 0.95)
    local lvH = CreateFrame("Frame", nil, lv)
    lvH:SetScale(0.5); lvH:SetPoint("TOPLEFT", lv, "TOPLEFT", 0, 0); lvH:SetSize(24 / 0.5, 20 / 0.5)
    local lvns = CreateFrame("Frame", nil, lvH, "NineSlicePanelTemplate")
    lvns:SetAllPoints()
    if not (NineSliceUtil and pcall(NineSliceUtil.ApplyLayoutByName, lvns, "Dialog")) then lvns:Hide() end
    if lvns.Center then lvns.Center:Hide() end
    local lvTop = CreateFrame("Frame", nil, lv); lvTop:SetAllPoints(); lvTop:SetFrameLevel(lv:GetFrameLevel() + 3)
    f.level = lvTop:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.level:SetPoint("TOPLEFT", 0, 0); f.level:SetPoint("BOTTOMRIGHT", 0, 0)
    f.level:SetJustifyH("CENTER"); f.level:SetJustifyV("MIDDLE")

    -- élite / rare : petit mot doré sous le nom
    f.tag = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.tag:SetPoint("BOTTOM", p, "TOP", 0, 2)
    f.tag:SetTextColor(1, 0.82, 0)

    if unit == "target" then
        f.auraBox = CreateFrame("Frame", nil, f)
        f.auraBox:SetSize(AURA_PER_ROW * (AURA_SIZE + 3), 1)
        f.auraBox:SetPoint("TOPLEFT", p, "BOTTOMLEFT", 4, -4)
    end
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
        -- tout au centre (« 766 / 766   100 % ») : aligné avec la mana en dessous
        local both = values
        if not isPower and values and pct then
            local ok2, s2 = pcall(string.format, "%s  |cffa0a0a0·|r  %s", values, pct)
            if ok2 then both = s2 end
        end
        NZR.SafeText(bar.center, both or ""); bar.right:SetText("")
    end
end

local function UpdateHealth(f)
    local u = f.unit
    if not UnitExists(u) then return end
    local cur, max = UnitHealth(u), UnitHealthMax(u)
    f.health:SetMinMaxValues(0, max)
    f.health:SetValue(cur)
    f.health:SetStatusBarColor(HealthRGB(u))
    if f.health.pred then
        local p = f.health.pred
        p:SetMinMaxValues(0, max)
        local inc
        if UnitGetIncomingHeals then
            local ok, v = pcall(UnitGetIncomingHeals, u); if ok then inc = v end
        end
        if inc == nil and CreateUnitHealPredictionCalculator and UnitGetDetailedHealPrediction then
            -- API récente : calculateur de prévision (valeurs possiblement secrètes, passées telles quelles)
            f.healCalc = f.healCalc or select(2, pcall(CreateUnitHealPredictionCalculator))
            local calc = f.healCalc
            if calc and pcall(UnitGetDetailedHealPrediction, u, "player", calc) and calc.GetIncomingHeals then
                local ok, v = pcall(calc.GetIncomingHeals, calc); if ok then inc = v end
            end
        end
        if inc == nil or not pcall(p.SetValue, p, inc) then p:SetValue(0) end
    end
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
    if not UnitIsPlayer(u) then
        local _, ptok = UnitPowerType(u)
        local okc, _, cls = pcall(UnitClass, u)
        if plain(ptok) and ptok == "MANA" and okc and plain(cls) and (cls == "WARRIOR" or cls == "ROGUE") then
            f.power:Hide()
            return
        end
    end
    local hasPower
    if plain(max) then hasPower = max > 0; f.lastHasPower = hasPower
    else hasPower = f.lastHasPower ~= false end
    f.power:SetShown(hasPower)
    f.power:SetShown(hasPower)            -- la hauteur ne change pas : le bord reste entier
    if not hasPower then return end
    local cur = UnitPower(u)
    f.power:SetMinMaxValues(0, max)
    f.power:SetValue(cur)
    local _, token = UnitPowerType(u)
    local r, g, b = 0, 0.4, 1
    local c = plain(token) and PowerBarColor and PowerBarColor[token]
    if c then r, g, b = c.r, c.g, c.b end
    if DB().ufPowerColor == "class" and UnitIsPlayer(u) then
        local cr, cg, cb = ClassRGB(u)
        if cr then r, g, b = cr, cg, cb end
    end
    f.power:SetStatusBarColor(Shade(r, g, b, DB().ufPowerShade))
    SetBarText(f.power, u, cur, max, true)
end

local function UpdateInfo(f)
    local u = f.unit
    if not UnitExists(u) then return end
    f.lastHasPower = nil
    -- nom complet (avec le titre, comme le jeu) ou juste le prénom ; toujours doré comme l'UI de WoW
    local name = UnitName(u)
    if DB().ufName == "full" and UnitIsPlayer(u) then
        local ok, full = pcall(UnitPVPName, u)
        if ok and full and plain(full) and full ~= "" then name = full end
    elseif plain(name) then
        name = name:match("^(%S+)") or name
    end
    NZR.SafeText(f.name, name)
    f.name:SetTextColor(1, 0.82, 0)
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

---------------------------------------------------------------------------
-- Buffs et débuffs sous le cadre de la cible (comme le cadre du jeu)
---------------------------------------------------------------------------

local function AuraButton(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(AURA_SIZE, AURA_SIZE)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 1, -1); b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.edge = b:CreateTexture(nil, "BACKGROUND")
    b.edge:SetAllPoints(); b.edge:SetColorTexture(0, 0, 0, 1)
    b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    b.cd:SetAllPoints(b.icon); b.cd:SetReverse(true); b.cd:SetDrawEdge(false)
    if b.cd.SetHideCountdownNumbers then b.cd:SetHideCountdownNumbers(true) end
    b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    b.count:SetPoint("BOTTOMRIGHT", 2, -1)
    b:SetScript("OnEnter", function(s)
        if not s.auraID then return end
        GameTooltip:SetOwner(s, "ANCHOR_BOTTOMRIGHT")
        if GameTooltip.SetUnitAuraByAuraInstanceID then
            pcall(GameTooltip.SetUnitAuraByAuraInstanceID, GameTooltip, s.unit, s.auraID)
        elseif s.index then
            pcall(s.harmful and GameTooltip.SetUnitDebuff or GameTooltip.SetUnitBuff, GameTooltip, s.unit, s.index)
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:EnableMouse(true)
    return b
end

local function FillAuras(f, list, filter, harmful)
    local u, n = f.unit, 0
    for i = 1, 40 do
        if n >= AURA_MAX then break end
        local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, u, i, filter)
        if not ok or not a then break end
        n = n + 1
        local b = list[n] or AuraButton(f.auraBox); list[n] = b
        b.unit, b.index, b.harmful, b.auraID = u, i, harmful, a.auraInstanceID
        pcall(b.icon.SetTexture, b.icon, a.icon)
        -- nombre de charges (peut être secret : passé tel quel)
        b.count:SetText("")
        if a.applications ~= nil then
            local okc, s = pcall(string.format, "%d", a.applications)
            if okc and not (NZR.plain(a.applications) and a.applications <= 1) then NZR.SafeText(b.count, s) end
        end
        -- temps restant
        b.cd:Hide()
        local done = false
        if C_UnitAuras.GetAuraDuration and b.cd.SetCooldownFromDurationObject and a.auraInstanceID then
            local okd, d = pcall(C_UnitAuras.GetAuraDuration, u, a.auraInstanceID)
            if okd and d and pcall(b.cd.SetCooldownFromDurationObject, b.cd, d) then b.cd:Show(); done = true end
        end
        if not done and NZR.plain(a.duration) and NZR.plain(a.expirationTime) and a.duration > 0 then
            b.cd:SetCooldown(a.expirationTime - a.duration, a.duration); b.cd:Show()
        end
        -- bord rouge pour les débuffs, comme le jeu
        if harmful then b.edge:SetColorTexture(0.8, 0.1, 0.1, 1) else b.edge:SetColorTexture(0, 0, 0, 1) end
        b:Show()
    end
    for i = n + 1, #list do list[i]:Hide(); list[i].auraID = nil end
    return n
end

local function LayoutAuras(f, list, n, startRow)
    local rows = 0
    for i = 1, n do
        local b = list[i]
        local r, c = math.floor((i - 1) / AURA_PER_ROW), (i - 1) % AURA_PER_ROW
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", f.auraBox, "TOPLEFT", c * (AURA_SIZE + 3), -(startRow + r) * (AURA_SIZE + 3))
        rows = r + 1
    end
    return rows
end

local function UpdateAuras(f)
    if not f.auraBox then return end
    if DB().ufAuras == false or not UnitExists(f.unit) or not C_UnitAuras or not C_UnitAuras.GetAuraDataByIndex then
        f.auraBox:Hide(); return
    end
    f.auraBox:Show()
    f.buffs, f.debuffs = f.buffs or {}, f.debuffs or {}
    local nb = FillAuras(f, f.buffs, "HELPFUL", false)
    local nd = FillAuras(f, f.debuffs, "HARMFUL", true)
    -- ennemi : débuffs d'abord (ceux qui comptent en combat), sinon buffs d'abord
    local okA, hostile = pcall(UnitCanAttack, "player", f.unit)
    hostile = okA and NZR.plain(hostile) and hostile
    if hostile then
        local r = LayoutAuras(f, f.debuffs, nd, 0)
        LayoutAuras(f, f.buffs, nb, r)
    else
        local r = LayoutAuras(f, f.buffs, nb, 0)
        LayoutAuras(f, f.debuffs, nd, r)
    end
end

local function UpdateAll(f)
    pcall(UpdateInfo, f); pcall(UpdateHealth, f); pcall(UpdatePower, f); pcall(UpdateAuras, f)
end
NZR.FramesRefresh = function() NZR.FramesFont(); for _, f in pairs(frames) do UpdateAll(f) end end

local function Events(f)
    local u = f.unit
    for _, ev in ipairs({ "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_POWER_UPDATE", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER", "UNIT_HEAL_PREDICTION", "UNIT_AURA",
                          "UNIT_NAME_UPDATE", "UNIT_LEVEL", "UNIT_PORTRAIT_UPDATE", "UNIT_MODEL_CHANGED", "UNIT_FACTION" }) do
        pcall(f.RegisterUnitEvent, f, ev, u)
    end
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    if u == "target" then f:RegisterEvent("PLAYER_TARGET_CHANGED") end
    f:SetScript("OnEvent", function(self, ev)
        if ev == "UNIT_HEALTH" or ev == "UNIT_MAXHEALTH" or ev == "UNIT_HEAL_PREDICTION" then pcall(UpdateHealth, self)
        elseif ev == "UNIT_AURA" then pcall(UpdateAuras, self)
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

-- outils partagés avec les cadres de groupe et de raid (Group.lua)
NZR.UF = { BAR = BAR, ClassRGB = ClassRGB, Shade = Shade, Percent = Percent, Fmt = Fmt, HideBlizzard = HideBlizzard }
