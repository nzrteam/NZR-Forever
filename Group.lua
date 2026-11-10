-- NZR Forever - Cadres de groupe et de raid (facultatif, désactivé par défaut)
-- Même habillage que nos cadres : fenêtre du jeu (métal doré, fond pierre),
-- cases propres à l'intérieur. Les boutons sont sécurisés : clic gauche = cibler,
-- clic droit = menu, comme les cadres du jeu.
local _, NZR = ...
local M = NZR:Module("Group")
local plain = NZR.plain

local function DB() return NZR.db end
local UF                                  -- outils partagés (Frames.lua)

local buttons = {}                        -- tous les boutons créés
local byUnit = {}                         -- unité -> { boutons }
local headers = {}
local fullNames = {}                      -- prénom -> nom complet déjà vu
local nameTick
local boxes = {}

---------------------------------------------------------------------------
-- Tailles
---------------------------------------------------------------------------
local function PartyBig() return DB().grpPartyStyle ~= "compact" end
local function CellSize(kind)
    local s = DB().grpCellScale or 1
    if kind == "party" and PartyBig() then return math.floor(228 * s), math.floor(60 * s) end
    return math.floor(84 * s), math.floor(42 * s)
end

---------------------------------------------------------------------------
-- Police (réglages « Police », « Taille », « Contour » des cadres)
---------------------------------------------------------------------------
local function SetFont(fs, size)
    fs.nzrSize = size
    local path = NZR.FontPath(DB().ufFont, STANDARD_TEXT_FONT)
    local flags, shadow = NZR.OutlineFlags(DB().ufOutline or "shadow")
    local sz = math.floor(size * (DB().ufFontSize or 1) + 0.5)
    if not pcall(fs.SetFont, fs, path, sz, flags) then pcall(fs.SetFont, fs, STANDARD_TEXT_FONT, sz, flags) end
    NZR.ApplyShadow(fs, shadow)
end

---------------------------------------------------------------------------
-- Une case
---------------------------------------------------------------------------
local function Style(b, kind)
    if b.nzr then return end
    b.nzr, b.kind = true, kind
    local big = kind == "party" and PartyBig()

    local bg = b:CreateTexture(nil, "BACKGROUND", nil, -8)
    bg:SetAllPoints(); bg:SetColorTexture(0, 0, 0, 0.9)
    local inner = b:CreateTexture(nil, "BACKGROUND", nil, -7)
    inner:SetPoint("TOPLEFT", 1, -1); inner:SetPoint("BOTTOMRIGHT", -1, 1)
    inner:SetColorTexture(0.09, 0.08, 0.07, 1)

    -- cases larges : portrait encadré + niveau à gauche, comme nos cadres
    local X0 = big and 52 or 1
    if big then
        local MEDIA = "Interface\\AddOns\\NZRForever\\Media\\uf\\"
        local square = DB().ufPortrait == "square"
        local pf = CreateFrame("Frame", nil, b)
        pf:SetSize(40, 40); pf:SetPoint("TOPLEFT", b, "TOPLEFT", 6, -2)
        pf:SetFrameLevel(b:GetFrameLevel() + 2)
        local port = pf:CreateTexture(nil, "ARTWORK")
        port:SetPoint("TOPLEFT", 4, -4); port:SetPoint("BOTTOMRIGHT", -4, 4)
        local mask = pf:CreateMaskTexture()
        mask:SetTexture(MEDIA .. (square and "mask_square" or "mask_round"), "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(port); port:AddMaskTexture(mask)
        local back = pf:CreateTexture(nil, "BACKGROUND")
        back:SetAllPoints(port); back:SetColorTexture(0.05, 0.04, 0.03, 1); back:AddMaskTexture(mask)
        if square then
            local host = CreateFrame("Frame", nil, pf)
            host:SetScale(0.5); host:SetPoint("TOPLEFT"); host:SetSize(40 / 0.5, 40 / 0.5)
            local ns = CreateFrame("Frame", nil, host, "NineSlicePanelTemplate")
            ns:SetAllPoints()
            if not (NineSliceUtil and pcall(NineSliceUtil.ApplyLayoutByName, ns, "Dialog")) then ns:Hide() end
            if ns.Center then ns.Center:Hide() end
            ns:SetFrameLevel(pf:GetFrameLevel() + 1)
        else
            local ring = pf:CreateTexture(nil, "OVERLAY")
            ring:SetAllPoints(); ring:SetTexture(MEDIA .. "ring_round")
        end
        b.port = port
        -- niveau dans un petit cadre doré, centré sous le portrait
        local lv = CreateFrame("Frame", nil, pf)
        lv:SetSize(32, 16); lv:SetPoint("TOP", pf, "BOTTOM", 0, -1)   -- sous le portrait, sans le cacher
        lv:SetFrameLevel(pf:GetFrameLevel() + 4)
        -- petit cadre net : fond sombre + liseré doré d'1 px (le bord « Dialog » est trop épais à cette taille)
        local lbg = lv:CreateTexture(nil, "BACKGROUND"); lbg:SetAllPoints()
        lbg:SetColorTexture(0.05, 0.04, 0.03, 0.95)
        for _, side in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true },
                                { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
            local t = lv:CreateTexture(nil, "BORDER")
            t:SetPoint(side[1]); t:SetPoint(side[2])
            if side[3] then t:SetHeight(1) else t:SetWidth(1) end
            t:SetColorTexture(0.78, 0.62, 0.28, 1)
        end
        local ltop = CreateFrame("Frame", nil, lv); ltop:SetAllPoints(); ltop:SetFrameLevel(lv:GetFrameLevel() + 3)
        b.level = ltop:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        b.level:SetPoint("CENTER", 0, 0); b.level:SetJustifyH("CENTER"); b.level:SetJustifyV("MIDDLE")
        -- fond un peu plus sombre derrière le portrait
        local col = b:CreateTexture(nil, "BACKGROUND", nil, -6)
        col:SetPoint("TOPLEFT", 1, -1); col:SetPoint("BOTTOMLEFT", 1, 1); col:SetWidth(X0 - 2)
        col:SetColorTexture(0.04, 0.035, 0.03, 1)
    end

    -- vie
    local hp = CreateFrame("StatusBar", nil, b)
    hp:SetStatusBarTexture(UF.BAR)
    -- cases larges : bandeau du nom, vie, mana, puis une ligne pour les buffs / débuffs
    local hasPow = DB().grpPower ~= false
    hp:SetPoint("TOPLEFT", X0, big and -14 or -1)
    if big then hp:SetPoint("BOTTOMRIGHT", -1, hasPow and 23 or 18)
    else hp:SetPoint("BOTTOMRIGHT", -1, hasPow and 4 or 1) end
    hp:SetMinMaxValues(0, 1); hp:SetValue(1)
    local hbg = hp:CreateTexture(nil, "BACKGROUND")
    hbg:SetAllPoints(); hbg:SetColorTexture(0.16, 0.05, 0.04, 1)
    b.health = hp

    -- soins en approche (coupés au bord de la barre)
    local clip = CreateFrame("Frame", nil, hp)
    clip:SetAllPoints(); clip:SetClipsChildren(true)
    local pred = CreateFrame("StatusBar", nil, clip)
    local fill = hp:GetStatusBarTexture()
    pred:SetPoint("TOPLEFT", fill, "TOPRIGHT"); pred:SetPoint("BOTTOMLEFT", fill, "BOTTOMRIGHT")
    pred:SetStatusBarTexture(UF.BAR); pred:SetStatusBarColor(0, 0.83, 0, 0.55)
    pred:SetMinMaxValues(0, 1); pred:SetValue(0)
    local function psize() local w = hp:GetWidth(); if w and w > 0 then pred:SetWidth(w) end end
    psize(); hp:HookScript("OnSizeChanged", psize)
    b.pred = pred

    -- mana / énergie (fine, en bas)
    local pw = CreateFrame("StatusBar", nil, b)
    pw:SetStatusBarTexture(UF.BAR)
    pw:SetPoint("TOPLEFT", hp, "BOTTOMLEFT", 0, -1); pw:SetPoint("TOPRIGHT", hp, "BOTTOMRIGHT", 0, -1)
    pw:SetHeight(big and 4 or 3)
    pw:SetMinMaxValues(0, 1); pw:SetValue(1)
    local pbg = pw:CreateTexture(nil, "BACKGROUND")
    pbg:SetAllPoints(); pbg:SetColorTexture(0, 0, 0, 1)
    pw:SetShown(DB().grpPower ~= false)
    b.power = pw

    -- textes au-dessus des barres
    local top = CreateFrame("Frame", nil, b)
    top:SetAllPoints(); top:SetFrameLevel(hp:GetFrameLevel() + 4)
    b.top = top
    b.name = top:CreateFontString(nil, "OVERLAY")
    SetFont(b.name, big and 11 or 10)
    b.name:SetWordWrap(false)
    b.info = top:CreateFontString(nil, "OVERLAY")
    SetFont(b.info, big and 11 or 9)
    if big then
        -- nom doré dans le bandeau du haut, vie au centre de la barre
        b.name:SetPoint("TOPLEFT", X0 + 3, -1); b.name:SetPoint("TOPRIGHT", -24, -1); b.name:SetHeight(13)
        b.name:SetJustifyH("LEFT")
        b.info:SetPoint("CENTER", hp, "CENTER", 0, 0)
    else
        b.name:SetPoint("TOPLEFT", hp, "TOPLEFT", 3, -4); b.name:SetPoint("TOPRIGHT", hp, "TOPRIGHT", -3, -4)
        b.name:SetJustifyH("CENTER")
        b.info:SetPoint("CENTER", hp, "CENTER", 0, -3)
    end

    -- rôle, chef, marque
    b.role = top:CreateTexture(nil, "OVERLAY")
    b.role:SetSize(12, 12)
    if big then b.role:SetPoint("TOPRIGHT", -4, -1) else b.role:SetPoint("TOPLEFT", 2, -2) end
    b.lead = top:CreateTexture(nil, "OVERLAY")
    b.lead:SetSize(11, 11); b.lead:SetTexture("Interface\\GroupFrame\\UI-Group-LeaderIcon")
    b.lead:SetPoint("BOTTOMLEFT", b, "TOPLEFT", big and X0 + 2 or 2, -5)
    b.mark = top:CreateTexture(nil, "OVERLAY")
    b.mark:SetSize(14, 14); b.mark:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    b.mark:SetPoint("CENTER", b, "TOP", 0, -2)

    -- petites icônes : buffs en bas à gauche, débuffs en bas à droite (comme le jeu)
    local isz = big and 16 or 11
    local function Icon(list, i, corner, dir)
        local d = CreateFrame("Frame", nil, top)
        d:SetSize(isz, isz)
        -- grandes cases : sous les barres ; cases de raid : dans les coins du bas
        local anchor = big and b or hp
        if i == 1 then d:SetPoint(corner, anchor, corner, corner:find("LEFT") and (big and X0 + 1 or 2) or -2, big and 2 or 1)
        else d:SetPoint(dir == 1 and "LEFT" or "RIGHT", list[i - 1], dir == 1 and "RIGHT" or "LEFT", dir, 0) end
        d.edge = d:CreateTexture(nil, "BACKGROUND"); d.edge:SetAllPoints()
        d.icon = d:CreateTexture(nil, "ARTWORK")
        d.icon:SetPoint("TOPLEFT", 1, -1); d.icon:SetPoint("BOTTOMRIGHT", -1, 1)
        d.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        d.cd = CreateFrame("Cooldown", nil, d, "CooldownFrameTemplate")
        d.cd:SetAllPoints(d.icon); d.cd:SetReverse(true); d.cd:SetDrawEdge(false)
        if d.cd.SetHideCountdownNumbers then d.cd:SetHideCountdownNumbers(true) end
        d.count = d:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
        d.count:SetPoint("BOTTOMRIGHT", 2, -1)
        d:Hide()
        list[i] = d
    end
    b.debuffs, b.buffs = {}, {}
    for i = 1, 3 do Icon(b.debuffs, i, "BOTTOMRIGHT", -1) end
    for i = 1, (big and 7 or 3) do Icon(b.buffs, i, "BOTTOMLEFT", 1) end

    -- liseré : cible (blanc) ou menace (rouge)
    b.hl = top:CreateTexture(nil, "OVERLAY", nil, 2)
    b.hl:SetPoint("TOPLEFT", -1, 1); b.hl:SetPoint("BOTTOMRIGHT", 1, -1)
    b.hl:SetColorTexture(1, 1, 1, 0); b.hl:Hide()
    local function edge(p1, p2, horiz)
        local t = top:CreateTexture(nil, "OVERLAY", nil, 3)
        t:SetPoint(p1); t:SetPoint(p2)
        if horiz then t:SetHeight(2) else t:SetWidth(2) end
        return t
    end
    b.frame = { edge("TOPLEFT", "TOPRIGHT", true), edge("BOTTOMLEFT", "BOTTOMRIGHT", true),
                edge("TOPLEFT", "BOTTOMLEFT"), edge("TOPRIGHT", "BOTTOMRIGHT") }
    for _, t in ipairs(b.frame) do t:Hide() end

    b:HookScript("OnEnter", function(s)
        if not s.unit then return end
        GameTooltip_SetDefaultAnchor(GameTooltip, s)
        GameTooltip:SetUnit(s.unit)
        GameTooltip:Show()
    end)
    b:HookScript("OnLeave", function() GameTooltip:Hide() end)
    table.insert(buttons, b)
end

---------------------------------------------------------------------------
-- Mises à jour
---------------------------------------------------------------------------
local function HealthColor(u)
    local r, g, b = 0.1, 0.8, 0.1
    if DB().grpColor ~= "green" then
        local cr, cg, cb = UF.ClassRGB(u)
        if cr then r, g, b = cr, cg, cb end
    end
    return UF.Shade(r, g, b, DB().ufHealthShade)
end

local function UpdateHealth(b)
    local u = b.unit
    if not u or not UnitExists(u) then return end
    local cur, max = UnitHealth(u), UnitHealthMax(u)
    b.health:SetMinMaxValues(0, max); b.health:SetValue(cur)
    b.health:SetStatusBarColor(HealthColor(u))
    -- soins en approche
    b.pred:SetMinMaxValues(0, max)
    local inc
    if UnitGetIncomingHeals then local ok, v = pcall(UnitGetIncomingHeals, u); if ok then inc = v end end
    if inc == nil or not pcall(b.pred.SetValue, b.pred, inc) then b.pred:SetValue(0) end

    -- texte : mort / fantôme / déconnecté, sinon % (ou valeurs en grand)
    local okC, conn = pcall(UnitIsConnected, u)
    local okD, dead = pcall(UnitIsDead, u)
    local okG, ghost = pcall(UnitIsGhost, u)
    if okC and plain(conn) ~= nil and conn == false then
        b.info:SetText("|cff999999Déconnecté|r"); b.health:SetStatusBarColor(0.35, 0.35, 0.35)
    elseif okG and plain(ghost) and ghost then
        b.info:SetText("|cffaaaaaaFantôme|r")
    elseif okD and plain(dead) and dead then
        b.info:SetText("|cffff5050Mort|r")
    else
        local mode = DB().grpText or "percent"
        if mode == "none" then b.info:SetText("")
        elseif mode == "values" or (b.kind == "party" and PartyBig() and mode == "auto") then
            local ok, s = pcall(string.format, "%s / %s", UF.Fmt(cur), UF.Fmt(max))
            NZR.SafeText(b.info, ok and s or "")
        else
            NZR.SafeText(b.info, UF.Percent(u, cur, max) or "")
        end
    end
end

local function UpdatePower(b)
    local u = b.unit
    if not u or not UnitExists(u) or DB().grpPower == false then return end
    local ptype, token = UnitPowerType(u)
    b.power:SetMinMaxValues(0, UnitPowerMax(u, ptype)); b.power:SetValue(UnitPower(u, ptype))
    local c = plain(token) and PowerBarColor and PowerBarColor[token]
    if c then b.power:SetStatusBarColor(c.r, c.g, c.b) else b.power:SetStatusBarColor(0, 0.4, 1) end
end

local function UpdateName(b)
    local u = b.unit
    if not u or not UnitExists(u) then return end
    -- nom complet (prénom + nom, comme au-dessus des têtes) ou prénom seul
    local n = NZR.FullName and NZR.FullName(u) or UnitName(u) or ""
    if plain(n) and DB().grpName == "first" then n = n:match("^(%S+)") or n end
    NZR.SafeText(b.name, n)
    if DB().grpNameColor == "class" then
        local r, g, bb = UF.ClassRGB(u)
        if r then b.name:SetTextColor(r, g, bb) else b.name:SetTextColor(1, 1, 1) end
    elseif b.kind == "party" and PartyBig() then
        b.name:SetTextColor(1, 0.82, 0)
    else
        b.name:SetTextColor(1, 1, 1)
    end
end

local ROLE = { TANK = { 0, 19/64, 22/64, 41/64 }, HEALER = { 20/64, 39/64, 1/64, 20/64 }, DAMAGER = { 20/64, 39/64, 22/64, 41/64 } }
local function UpdateIcons(b)
    local u = b.unit
    if not u or not UnitExists(u) then return end
    local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(u)
    local tc = role and ROLE[role]
    if tc and DB().grpRole ~= false then
        b.role:SetTexture("Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES")
        b.role:SetTexCoord(tc[1], tc[2], tc[3], tc[4]); b.role:Show()
    else b.role:Hide() end
    b.lead:SetShown(UnitIsGroupLeader and UnitIsGroupLeader(u) or false)
    local idx = GetRaidTargetIndex(u)
    if idx and plain(idx) then SetRaidTargetIconTexture(b.mark, idx); b.mark:Show() else b.mark:Hide() end
end

local DEBUFF_RGB = { Magic = { 0.2, 0.6, 1 }, Curse = { 0.6, 0, 1 }, Disease = { 0.6, 0.4, 0 }, Poison = { 0, 0.6, 0 } }

local function SetIcon(d, u, a)
    d.id = a.auraInstanceID
    pcall(d.icon.SetTexture, d.icon, a.icon)
    d.count:SetText("")
    if a.applications ~= nil and not (plain(a.applications) and a.applications <= 1) then
        local ok, s = pcall(string.format, "%d", a.applications)
        if ok then NZR.SafeText(d.count, s) end
    end
    d.cd:Hide()
    local done = false
    if C_UnitAuras.GetAuraDuration and d.cd.SetCooldownFromDurationObject and a.auraInstanceID then
        local ok, dur = pcall(C_UnitAuras.GetAuraDuration, u, a.auraInstanceID)
        if ok and dur and pcall(d.cd.SetCooldownFromDurationObject, d.cd, dur) then d.cd:Show(); done = true end
    end
    if not done and plain(a.duration) and plain(a.expirationTime) and a.duration > 0 then
        d.cd:SetCooldown(a.expirationTime - a.duration, a.duration); d.cd:Show()
    end
    d:Show()
end

local function Fill(list, u, filters, stopAfterFirst)
    local n = 0
    for fi, filter in ipairs(filters) do
        for i = 1, 40 do
            if n >= #list then break end
            local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, u, i, filter)
            if not ok or not a then break end
            -- en combat l'identifiant peut être « secret » : on ne compare que s'il est lisible
            local dup = false
            if plain(a.auraInstanceID) then
                for j = 1, n do if plain(list[j].id) and list[j].id == a.auraInstanceID then dup = true end end
            end
            if not dup then
                n = n + 1
                SetIcon(list[n], u, a)
                list[n].aura = a
            end
        end
        if stopAfterFirst and fi == 1 then break end
    end
    for i = n + 1, #list do list[i]:Hide(); list[i].id = nil end
    return n
end

local function UpdateAuras(b)
    local u = b.unit
    local ok = u and UnitExists(u) and C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
    -- débuffs : ceux que je peux dissiper d'abord (ou tous si réglé)
    if ok and DB().grpDebuffs ~= false then
        Fill(b.debuffs, u, { "HARMFUL|RAID", "HARMFUL" }, DB().grpDebuffAll ~= true)
        for _, d in ipairs(b.debuffs) do
            if d:IsShown() and d.aura then
                local t = plain(d.aura.dispelName) and DEBUFF_RGB[d.aura.dispelName]
                if t then d.edge:SetColorTexture(t[1], t[2], t[3], 1) else d.edge:SetColorTexture(0.8, 0.1, 0.1, 1) end
            end
        end
    else for _, d in ipairs(b.debuffs) do d:Hide() end end
    -- buffs : les miens (bénédictions, soins sur la durée…), ou tous si réglé
    if ok and DB().grpBuffs ~= "none" then
        Fill(b.buffs, u, { DB().grpBuffs == "all" and "HELPFUL" or "HELPFUL|PLAYER" })
        for _, d in ipairs(b.buffs) do d.edge:SetColorTexture(0, 0, 0, 1) end
    else for _, d in ipairs(b.buffs) do d:Hide() end end
end

local function UpdateBorder(b)
    local u = b.unit
    local r, g, bl, show
    if u and UnitExists(u) and UnitIsUnit(u, "target") then r, g, bl, show = 1, 1, 1, true end
    if not show and u and UnitExists(u) and UnitThreatSituation then
        local ok, t = pcall(UnitThreatSituation, u)
        if ok and plain(t) and t >= 2 then r, g, bl, show = 1, 0.15, 0.1, true end
    end
    for _, t in ipairs(b.frame) do
        if show then t:SetColorTexture(r, g, bl, 0.9); t:Show() else t:Hide() end
    end
end

local function UpdatePortrait(b)
    local u = b.unit
    if not b.port or not u or not UnitExists(u) then return end
    pcall(SetPortraitTexture, b.port, u)
    local okC, conn = pcall(UnitIsConnected, u)
    b.port:SetDesaturated(okC and plain(conn) ~= nil and conn == false)
    local okL, lv = pcall(UnitLevel, u)
    if okL and plain(lv) then
        b.level:SetText(lv > 0 and lv or "??")
        b.level:SetTextColor(1, 0.82, 0)
    else
        b.level:SetText("")
    end
end

local function UpdateButton(b)
    if not b.unit or not UnitExists(b.unit) then return end
    pcall(UpdatePortrait, b)
    pcall(UpdateName, b); pcall(UpdateHealth, b); pcall(UpdatePower, b)
    pcall(UpdateIcons, b); pcall(UpdateAuras, b); pcall(UpdateBorder, b)
end

local function Remap()
    wipe(byUnit)
    for _, b in ipairs(buttons) do
        local u = b:GetAttribute("unit")
        b.unit = u
        if u and b:IsVisible() then
            byUnit[u] = byUnit[u] or {}
            table.insert(byUnit[u], b)
            UpdateButton(b)
        end
    end
    -- le cadre doré seulement s'il y a au moins une case (pas pendant une invitation en attente)
    for kind, hdr in pairs(headers) do
        local n = 0
        for _, b in ipairs(buttons) do
            if b.kind == kind and b:IsVisible() and b:GetAttribute("unit") then n = n + 1 end
        end
        if boxes[kind] then boxes[kind]:SetShown(hdr:IsShown() and n > 0) end
    end
end

local function ForUnit(u, fn)
    local list = u and byUnit[u]
    if list then for _, b in ipairs(list) do pcall(fn, b) end end
end

-- distance : à moitié transparent hors de portée de soin
local function UpdateRange()
    for _, b in ipairs(buttons) do
        if b.unit and b:IsVisible() then
            local ok, inRange, checked = pcall(UnitInRange, b.unit)
            if ok then
                if b.SetAlphaFromBoolean and not plain(inRange) then
                    pcall(b.SetAlphaFromBoolean, b, inRange, 1, 0.45)
                elseif plain(checked) and checked and plain(inRange) then
                    b:SetAlpha(inRange and 1 or 0.45)
                else
                    b:SetAlpha(1)
                end
            end
        end
    end
end

---------------------------------------------------------------------------
-- En-têtes sécurisés (le jeu place les cases, même en combat)
---------------------------------------------------------------------------
local function InitConfig(w, h)
    return ([[
        self:SetWidth(%d); self:SetHeight(%d)
        self:SetAttribute("*type1", "target")
        self:SetAttribute("*type2", "togglemenu")
    ]]):format(w, h)
end

local function MakeHeader(kind, name, holder)
    local w, h = CellSize(kind)
    local hdr = CreateFrame("Frame", name, UIParent, "SecureGroupHeaderTemplate")
    hdr.kind = kind
    hdr:SetAttribute("template", "SecureUnitButtonTemplate")
    hdr:SetAttribute("initialConfigFunction", InitConfig(w, h))
    hdr:SetAttribute("point", "TOP")
    hdr:SetAttribute("yOffset", -4)
    hdr:SetAttribute("sortMethod", "INDEX")
    if kind == "party" then
        hdr:SetAttribute("showParty", true)
        hdr:SetAttribute("showPlayer", true)
        hdr:SetAttribute("showSolo", false)
        hdr:SetAttribute("showRaid", false)
    else
        hdr:SetAttribute("showRaid", true)
        hdr:SetAttribute("groupBy", "GROUP")
        hdr:SetAttribute("groupingOrder", "1,2,3,4,5,6,7,8")
        hdr:SetAttribute("groupFilter", "1,2,3,4,5,6,7,8")
        hdr:SetAttribute("maxColumns", 8)
        hdr:SetAttribute("unitsPerColumn", 5)
        hdr:SetAttribute("columnSpacing", 4)
        hdr:SetAttribute("columnAnchorPoint", "LEFT")
    end
    hdr:SetPoint("TOPLEFT", holder, "TOPLEFT", 10, -28)

    -- habillage : fenêtre du jeu autour des cases (suit la taille du groupe)
    local box = CreateFrame("Frame", nil, UIParent)
    box:SetFrameStrata("LOW")
    box:SetPoint("TOPLEFT", hdr, "TOPLEFT", -10, 28)
    box:SetPoint("BOTTOMRIGHT", hdr, "BOTTOMRIGHT", 10, -10)
    NZR:WowFrame(box, kind == "party" and "Groupe" or "Raid", DB().grpAlpha or 0.9)
    box:Hide()
    hdr:HookScript("OnShow", function() C_Timer.After(0.1, function() pcall(Remap) end) end)
    hdr:HookScript("OnHide", function() box:Hide() end)
    hdr:SetFrameStrata("LOW"); hdr:SetFrameLevel(box:GetFrameLevel() + 10)
    boxes[kind] = box

    -- les cases se créent à la volée : on les habille dès qu'elles existent
    hdr:HookScript("OnAttributeChanged", function(self, attr)
        if type(attr) == "string" and attr:match("^child%d+$") then
            local b = self:GetAttribute(attr)
            if b then
                -- une erreur d'habillage ne doit jamais casser le placement des cases par le jeu
                local ok, err = pcall(Style, b, kind)
                if not ok and NZR.LogError then pcall(NZR.LogError, NZR, err, "Group") end
                pcall(b.SetFrameLevel, b, self:GetFrameLevel() + 1)
            end
        end
    end)
    headers[kind] = hdr
    return hdr
end

-- les cases du jeu (groupe et raid) : on les met de côté
local function HideBlizzard()
    if InCombatLockdown() then return end
    for _, n in ipairs({ "PartyFrame", "CompactPartyFrame", "CompactRaidFrameContainer" }) do
        local f = _G[n]
        if f then UF.HideBlizzard(f) end
    end
    for i = 1, 4 do local f = _G["PartyMemberFrame" .. i]; if f then UF.HideBlizzard(f) end end
end

function M:Init()
    if NZR.withUI or not DB().groupFrames then return end
    UF = NZR.UF
    if not UF then return end
    local holder = NZR:Holder("group", "Groupe et raid", 200, 220, { "TOPLEFT", "TOPLEFT", 24, -170 })
    local party = MakeHeader("party", "NZRF_PartyHeader", holder)
    local raid = MakeHeader("raid", "NZRF_RaidHeader", holder)
    -- toutes les cases créées tout de suite (hors combat), pour pouvoir les habiller
    for hdr, n in pairs({ [party] = 5, [raid] = 40 }) do
        -- le jeu ne crée les cases que s'il a au moins une unité à montrer : on fait comme si
        -- on était seul en groupe le temps de les créer (en combat, il ne peut plus en créer)
        hdr:SetAttribute("showSolo", true)
        hdr:SetAttribute("showPlayer", true)
        hdr:Show()
        hdr:SetAttribute("startingIndex", -n + 1)
        hdr:SetAttribute("startingIndex", 1)
        hdr:Hide()
        hdr:SetAttribute("showSolo", false)
        if hdr.kind == "raid" then hdr:SetAttribute("showPlayer", nil) end
    end
    -- clic droit = menu du jeu (inviter, chuchoter, inspecter…) : les cases écoutent aussi le clic droit
    for _, b in ipairs(buttons) do pcall(b.RegisterForClicks, b, "AnyUp") end
    RegisterAttributeDriver(party, "state-visibility", "[group:raid] hide; [group:party] show; hide")
    RegisterAttributeDriver(raid, "state-visibility", "[group:raid] show; hide")
    for _, h in pairs(headers) do h:SetScale(DB().grpScale or 1); boxes[h.kind]:SetScale(DB().grpScale or 1) end
    HideBlizzard()

    local ev = CreateFrame("Frame")
    for _, e in ipairs({ "GROUP_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD", "PLAYER_TARGET_CHANGED",
                         "PARTY_LEADER_CHANGED", "RAID_TARGET_UPDATE", "PLAYER_ROLES_ASSIGNED",
                         "PLAYER_REGEN_ENABLED" }) do ev:RegisterEvent(e) end
    for _, e in ipairs({ "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_HEAL_PREDICTION", "UNIT_POWER_UPDATE",
                         "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER", "UNIT_NAME_UPDATE", "UNIT_CONNECTION",
                         "UNIT_FLAGS", "UNIT_AURA", "UNIT_THREAT_SITUATION_UPDATE",
                         "UNIT_PORTRAIT_UPDATE", "UNIT_MODEL_CHANGED", "UNIT_LEVEL" }) do ev:RegisterEvent(e) end
    ev:SetScript("OnEvent", function(_, e, u)
        if e == "UNIT_HEALTH" or e == "UNIT_MAXHEALTH" or e == "UNIT_HEAL_PREDICTION"
           or e == "UNIT_CONNECTION" or e == "UNIT_FLAGS" then ForUnit(u, UpdateHealth)
        elseif e == "UNIT_POWER_UPDATE" or e == "UNIT_MAXPOWER" or e == "UNIT_DISPLAYPOWER" then ForUnit(u, UpdatePower)
        elseif e == "UNIT_AURA" then ForUnit(u, UpdateAuras)
        elseif e == "UNIT_NAME_UPDATE" then ForUnit(u, UpdateName)
        elseif e == "UNIT_PORTRAIT_UPDATE" or e == "UNIT_MODEL_CHANGED" or e == "UNIT_LEVEL" then ForUnit(u, UpdatePortrait)
        elseif e == "UNIT_THREAT_SITUATION_UPDATE" then ForUnit(u, UpdateBorder)
        elseif e == "PLAYER_TARGET_CHANGED" then for _, b in ipairs(buttons) do pcall(UpdateBorder, b) end
        elseif e == "RAID_TARGET_UPDATE" or e == "PARTY_LEADER_CHANGED" or e == "PLAYER_ROLES_ASSIGNED" then
            for _, b in ipairs(buttons) do pcall(UpdateIcons, b) end
        else
            if e == "PLAYER_REGEN_ENABLED" or e == "PLAYER_ENTERING_WORLD" then HideBlizzard() end
            C_Timer.After(0.1, Remap)
        end
    end)
    -- les boutons changent d'unité quand le groupe bouge
    local t = 0
    ev:SetScript("OnUpdate", function(_, el)
        t = t + el
        if t < 0.25 then return end
        t = 0
        local changed = false
        for _, b in ipairs(buttons) do
            if b:GetAttribute("unit") ~= b.unit then changed = true; break end
        end
        if changed then Remap() end
        UpdateRange()
        nameTick = (nameTick or 0) + 1
        if nameTick >= 20 then nameTick = 0; for _, b in ipairs(buttons) do if b.unit then pcall(UpdateName, b) end end end
    end)

    NZR.GroupRefresh = function()
        for _, b in ipairs(buttons) do
            for _, fs in ipairs({ b.name, b.info }) do SetFont(fs, fs.nzrSize or 10) end
            UpdateButton(b)
        end
        if not InCombatLockdown() then
            for _, h in pairs(headers) do h:SetScale(DB().grpScale or 1); boxes[h.kind]:SetScale(DB().grpScale or 1) end
        end
        for _, bx in pairs(boxes) do if NZR.WowFrameAlpha then NZR:WowFrameAlpha(bx, DB().grpAlpha or 0.9) end end
    end
end

-- pour les tests hors jeu
NZR.GroupInternals = { Style = Style, Update = function(b) b.unit = b:GetAttribute("unit"); UpdateButton(b) end }
