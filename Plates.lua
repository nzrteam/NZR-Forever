-- NZR Forever - Barres au-dessus des monstres (barres de nom)
-- On garde le look de WoW Forever (bord, case de niveau, police, opacité) :
-- seuls le texte de la barre de vie et, en option, sa couleur changent.
-- Désactivé de base (Réglages > Cadres > Barres au-dessus des monstres).
local _, NZR = ...
local M = NZR:Module("Plates")
local plain = NZR.plain

local function DB() return NZR.db end

local function StatusBars(frame, list, depth)
    if depth > 5 then return list end
    for _, c in ipairs({ frame:GetChildren() }) do
        if c.GetObjectType and c:GetObjectType() == "StatusBar" then table.insert(list, c) end
        StatusBars(c, list, depth + 1)
    end
    return list
end

local function HealthBar(plate)
    local best, bw
    for _, b in ipairs(StatusBars(plate, {}, 0)) do
        local ok, w = pcall(b.GetWidth, b)
        if ok and plain(w) and b:IsShown() and (not bw or w > bw) then best, bw = b, w end
    end
    return best
end

local function TextOf(fs)
    local ok, t = pcall(fs.GetText, fs)
    if ok and plain(t) then return t end
end

-- un texte est « sur la barre » si son centre est dans la barre (pas le niveau, pas le nom)
local function Inside(r, bar)
    local ok1, x, y = pcall(r.GetCenter, r)
    local ok2, l, rr, t, b = pcall(function() return bar:GetLeft(), bar:GetRight(), bar:GetTop(), bar:GetBottom() end)
    if not (ok1 and ok2) or not (plain(x) and plain(y) and plain(l) and plain(rr) and plain(t) and plain(b)) then return false end
    return x >= l and x <= rr and y >= b - 1 and y <= t + 1
end

-- textes du jeu posés sur la barre (valeur, %) : on les cherche dans toute la barre
-- de nom, on les éteint et on garde leur police pour les nôtres
local function LooksLikeHealth(r)
    local t = TextOf(r)
    if not t then return false end
    return t:find("%d") ~= nil and (t:find("%%") ~= nil or t:match("^[%d%s%.,kKmM/]+$") ~= nil)
end

-- la case de niveau : un nombre seul, hors de la barre
local function IsLevel(r)
    local t = TextOf(r)
    return t and t:match("^%s*%d+%s*$") ~= nil and #t:gsub("%s", "") <= 2
end

local function Mute(r)
    r:SetAlpha(0)
    if not r.nzrMuted then
        r.nzrMuted = true
        hooksecurefunc(r, "SetAlpha", function(s, a)
            if s.nzrMuted and DB().plates and a ~= 0 then s:SetAlpha(0) end
        end)
    end
end

local function MuteGameText(plate, bar)
    local font, size, flags
    local found = 0
    local function take(r)
        if not font then font, size, flags = r:GetFont() end
        Mute(r)
        found = found + 1
    end
    -- 1) tout texte rangé dans la barre de vie elle-même (ou ses sous-cadres) = texte de vie
    local function under(f, depth)
        if depth > 4 then return end
        for _, r in ipairs({ f:GetRegions() }) do
            if r.GetObjectType and r:GetObjectType() == "FontString" and not r.nzrOwn then take(r) end
        end
        for _, c in ipairs({ f:GetChildren() }) do under(c, depth + 1) end
    end
    under(bar, 0)
    -- 2) ailleurs dans la barre de nom : seulement ce qui est posé sur la barre ou ressemble à de la vie
    local function scan(f, depth)
        if depth > 6 or f == bar then return end
        for _, r in ipairs({ f:GetRegions() }) do
            if r.GetObjectType and r:GetObjectType() == "FontString" and not r.nzrOwn and not r.nzrMuted then
                if Inside(r, bar) or (LooksLikeHealth(r) and not IsLevel(r)) then take(r) end
            end
        end
        for _, c in ipairs({ f:GetChildren() }) do scan(c, depth + 1) end
    end
    scan(plate, 0)
    return font, size, flags, found
end

-- /nzr plaque : décrit les textes de la barre de ta cible (pour régler ce module)
function NZR.InspectPlateText()
    local plate = C_NamePlate.GetNamePlateForUnit("target")
    if not plate then NZR:Print("cible un monstre dont la barre est affichée (touche V), puis recommence.") return end
    local bar = plate.nzrBar or HealthBar(plate)
    local lines = { "Barre de vie : " .. tostring(bar and (bar:GetDebugName() or "?")) }
    local function scan(f, depth, path)
        if depth > 7 then return end
        for _, r in ipairs({ f:GetRegions() }) do
            if r.GetObjectType and r:GetObjectType() == "FontString" then
                local t = TextOf(r)
                lines[#lines + 1] = ("%s | texte=%s | sur la barre=%s | dans la barre=%s | caché=%s | à nous=%s"):format(
                    path, t and ("« " .. t .. " »") or "secret/vide", tostring(bar and Inside(r, bar)),
                    tostring(f == bar), tostring(r.nzrMuted == true), tostring(r.nzrOwn == true))
            end
        end
        for i, c in ipairs({ f:GetChildren() }) do
            local key = c.GetParentKey and c:GetParentKey() or c:GetObjectType()
            scan(c, depth + 1, path .. ">" .. tostring(key or i))
        end
    end
    scan(plate, 0, "plaque")
    if NZR.ShowCopy then NZR:ShowCopy("Barre de la cible", table.concat(lines, "\n")) else for _, l in ipairs(lines) do print(l) end end
end

local function Color(bar, unit)
    if DB().npColor ~= "red" then return end
    local r, g, b
    local okT, tapped = pcall(UnitIsTapDenied, unit)
    local okA, atk = pcall(UnitCanAttack, "player", unit)
    if okT and plain(tapped) and tapped then r, g, b = 0.5, 0.5, 0.5
    elseif okA and plain(atk) and atk then r, g, b = 0.8, 0.1, 0.08
    else return end
    bar.nzrColoring = true
    bar:SetStatusBarColor(r, g, b)
    bar.nzrColoring = nil
end

local function Percent(unit, cur, max)
    if UnitHealthPercent and CurveConstants and CurveConstants.ScaleTo100 then
        local ok, p = pcall(UnitHealthPercent, unit, true, CurveConstants.ScaleTo100)
        if ok and p ~= nil then
            local ok2, s = pcall(string.format, "%.0f%%", p)
            if ok2 then return s end
        end
    end
    if plain(cur) and plain(max) and max > 0 then return ("%.0f%%"):format(cur / max * 100) end
end

local function UpdateText(plate)
    local bar, unit = plate.nzrBar, plate.nzrUnit
    -- le jeu peut créer ou réafficher son texte plus tard : on revérifie
    if bar and (plate.nzrFound or 0) == 0 then
        local _, _, _, found = MuteGameText(plate, bar)
        plate.nzrFound = found
    end
    if bar.nzrGF then
        local gf = bar.nzrGF
        local path = NZR.FontPath(DB().npFont, gf[1])
        local sz = math.floor((gf[2] or 10) * (DB().npFontSize or 1) + 0.5)
        for _, fs in ipairs({ bar.nzrC, bar.nzrR }) do
            local flags, shadow = NZR.OutlineFlags(DB().npOutline or "game", gf[3])
            if not pcall(fs.SetFont, fs, path, sz, flags) then pcall(fs.SetFont, fs, gf[1], sz, flags) end
            if DB().npOutline and DB().npOutline ~= "game" then NZR.ApplyShadow(fs, shadow) end
        end
    end
    if not bar or not unit or not UnitExists(unit) then return end
    local mode = DB().npText or "both"
    local cur, max = UnitHealth(unit), UnitHealthMax(unit)
    local val = NZR.Abbrev(cur)
    local pct = Percent(unit, cur, max)
    if mode == "none" then bar.nzrC:SetText(""); bar.nzrR:SetText("")
    elseif mode == "values" then NZR.SafeText(bar.nzrC, val); bar.nzrR:SetText("")
    elseif mode == "percent" then NZR.SafeText(bar.nzrC, pct or ""); bar.nzrR:SetText("")
    else NZR.SafeText(bar.nzrC, val); NZR.SafeText(bar.nzrR, pct or "") end
end

local function Style(plate, unit)
    if not plate or (plate.IsForbidden and plate:IsForbidden()) then return end
    plate.nzrUnit = unit or plate.nzrUnit
    local bar = plate.nzrBar or HealthBar(plate)
    if not bar then return end
    plate.nzrBar = bar
    if not bar.nzrC then
        local font, size, flags, found = MuteGameText(plate, bar)
        plate.nzrFound = found
        font = font or STANDARD_TEXT_FONT
        size = size or 10
        flags = flags or "OUTLINE"
        bar.nzrGF = { font, size, flags }        -- police d'origine du jeu
        bar.nzrC = bar:CreateFontString(nil, "OVERLAY"); bar.nzrC.nzrOwn = true
        bar.nzrC:SetFont(font, size, flags); bar.nzrC:SetPoint("CENTER", 0, 0)
        bar.nzrR = bar:CreateFontString(nil, "OVERLAY"); bar.nzrR.nzrOwn = true
        bar.nzrR:SetFont(font, size, flags); bar.nzrR:SetPoint("RIGHT", -3, 0)
        hooksecurefunc(bar, "SetStatusBarColor", function(b)
            if b.nzrColoring or not plate.nzrUnit then return end
            Color(b, plate.nzrUnit)
        end)
    else
        local _, _, _, found = MuteGameText(plate, bar)
        plate.nzrFound = (plate.nzrFound or 0) + found
    end
    Color(bar, plate.nzrUnit)
    UpdateText(plate)
end

function M:Init()
    if NZR.withUI or not DB().plates or not C_NamePlate then return end
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    ev:RegisterEvent("UNIT_HEALTH")
    ev:RegisterEvent("UNIT_MAXHEALTH")
    ev:SetScript("OnEvent", function(_, e, unit)
        if not unit or not unit:find("^nameplate") then return end
        local plate = C_NamePlate.GetNamePlateForUnit(unit)
        if not plate then return end
        if e == "NAME_PLATE_UNIT_ADDED" then
            pcall(Style, plate, unit)
            C_Timer.After(0.1, function() pcall(Style, plate, unit) end)
        else
            pcall(UpdateText, plate)
        end
    end)
    NZR.PlatesRefresh = function()
        for _, p in ipairs(C_NamePlate.GetNamePlates() or {}) do pcall(Style, p) end
    end
end
