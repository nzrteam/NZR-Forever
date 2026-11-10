------------------------------------------------------------------------------
-- Forever Compass (WoW Forever, client 12.x)
-- Flèche ou boussole indépendante, à placer où tu veux.
-- Cibles : /fc goto, point posé sur la carte, quête suivie, quête la plus proche,
-- et les points « TomTom » envoyés par Questie (ou un autre addon) si TomTom
-- n'est pas installé. Indique seulement la direction : rien n'est automatisé.
-- Réglages : Échap > Options > AddOns > Forever Compass (ou /fc).
------------------------------------------------------------------------------
-- Module de NZR Forever (désactivé de base). Même code que l'addon Forever Compass,
-- qui reste disponible seul ; si les deux sont installés, c'est l'addon seul qui sert.
local _, NZR = ...
local MOD = NZR:Module("Compass")
local MEDIA = "Interface\\AddOns\\NZRForever\\Media\\compass\\"
local YARD_TO_M = 0.9144

local defaults = {
    format = "arrow",                 -- "arrow" ou "bar"
    arrow = "gem", size = 72,
    colorMode = "native",             -- "native" (couleurs du jeu), "dynamic" (vert devant, rouge derrière), "gold", "white", "custom"
    color = { 1, 0.82, 0 },
    barWidth = 360,
    bg = "none",                      -- "none", "tooltip", "dialog"
    scale = 1, alpha = 1, fontSize = 12,
    showTitle = true, showSub = true, showDist = true, unit = "m",
    hideNoTarget = true, locked = false,
    useMapPin = true, useSuperTrack = true, useNearest = false, tomtom = true,
    arriveClear = true, invert = false, corpse = true,
    point = "CENTER", x = 0, y = 220,
}

-- flèches du jeu d'abord (atlas Blizzard), puis les nôtres
local ARROWS = {
    { "gem", "Gemme" }, { "rune", "Rune" }, { "needle", "Aiguille" }, { "gold", "Dorée" },
    { "classic", "Simple" },
}
local ARROW_ART = {
    gem     = { file = MEDIA .. "gemme" },
    rune    = { file = MEDIA .. "rune" },
    needle  = { file = MEDIA .. "needle" },
    gold    = { file = MEDIA .. "gold" },
    nav     = { atlas = "Navigation-Tracked-Arrow" },
    quest   = { atlas = "MiniMap-QuestArrow" },
    player  = { file = "Interface\\Minimap\\MinimapArrow" },
    classic = { file = MEDIA .. "simple" },
}
local function SetArrowArt(tex, id)
    local art = ARROW_ART[id] or ARROW_ART.nav
    if art.atlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(art.atlas) then
        tex:SetAtlas(art.atlas, false)
        return true
    end
    tex:SetTexture(art.file or (MEDIA .. "classic"))
    return art.file ~= nil
end

local DB
local FC = CreateFrame("Frame", "NZRF_CompassFrame", UIParent)
FC:Hide()
FC:SetFrameStrata("MEDIUM")
FC:SetClampedToScreen(true)
FC:SetMovable(true)
FC:EnableMouse(true)
FC:RegisterForDrag("LeftButton")
FC.manual = nil          -- cible manuelle : { map=, x=, y=, title=, uid= }
FC.preview = false       -- affichée pendant les réglages même sans cible

local function plain(v)
    if issecretvalue and issecretvalue(v) then return false end
    return v ~= nil
end

------------------------------------------------------------------------------
-- Visuel
------------------------------------------------------------------------------
local bgTex = FC:CreateTexture(nil, "BACKGROUND")
bgTex:SetPoint("TOPLEFT", 3, -3); bgTex:SetPoint("BOTTOMRIGHT", -3, 3)
local border = CreateFrame("Frame", nil, FC, "NineSlicePanelTemplate")
border:SetAllPoints()

-- mode flèche
local arrowTex = FC:CreateTexture(nil, "ARTWORK")
local title = FC:CreateFontString(nil, "OVERLAY", "GameFontNormal")
local sub = FC:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
local dist = FC:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
dist:SetTextColor(1, 1, 1)
title:SetWordWrap(false); sub:SetWordWrap(false)

-- mode boussole : bande, graduations, lettres, repère de la cible
local bar = CreateFrame("Frame", nil, FC)
bar:SetClipsChildren(true)
local barLine = bar:CreateTexture(nil, "ARTWORK")
barLine:SetColorTexture(1, 1, 1, 0.18); barLine:SetHeight(1)
barLine:SetPoint("LEFT", 0, -6); barLine:SetPoint("RIGHT", 0, -6)
local center = bar:CreateTexture(nil, "OVERLAY")
center:SetTexture(MEDIA .. "notch"); center:SetSize(10, 7)
center:SetPoint("TOP", bar, "TOP", 0, 0)
local marker = bar:CreateTexture(nil, "OVERLAY", nil, 2)
marker:SetTexture(MEDIA .. "diamond"); marker:SetSize(14, 14)
local edgeL = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); edgeL:SetText("<"); edgeL:SetPoint("LEFT", 3, -6)
local edgeR = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); edgeR:SetText(">"); edgeR:SetPoint("RIGHT", -3, -6)

local LETTERS = { { 0, "N" }, { math.pi / 4, "NO" }, { math.pi / 2, "O" }, { 3 * math.pi / 4, "SO" },
                  { math.pi, "S" }, { 5 * math.pi / 4, "SE" }, { 3 * math.pi / 2, "E" }, { 7 * math.pi / 4, "NE" } }
local letters, ticks = {}, {}
for i, l in ipairs(LETTERS) do
    local fs = bar:CreateFontString(nil, "ARTWORK", (#l[2] == 1) and "GameFontNormal" or "GameFontHighlightSmall")
    fs:SetText(l[2]); fs.angle = l[1]
    if l[2] ~= "N" and #l[2] == 1 then fs:SetTextColor(0.95, 0.95, 0.95) end
    letters[i] = fs
end
for i = 0, 23 do
    local t = bar:CreateTexture(nil, "ARTWORK")
    t:SetColorTexture(1, 1, 1, (i % 2 == 0) and 0.45 or 0.25)
    t:SetSize(1, (i % 2 == 0) and 6 or 4)
    t.angle = i * math.pi / 12
    ticks[#ticks + 1] = t
end

local function ApplyBackground()
    local ok = NineSliceUtil and DB.bg ~= "none" and pcall(NineSliceUtil.ApplyLayoutByName, border,
        DB.bg == "dialog" and "Dialog" or "TooltipDefaultLayout")
    border:SetShown(ok and true or false)
    if ok and border.Center then border.Center:Hide() end
    if DB.bg == "none" then bgTex:Hide()
    else
        bgTex:Show()
        bgTex:SetColorTexture(0.03, 0.03, 0.04, DB.bg == "dialog" and 0.92 or 0.82)
    end
end

local function SetFont(fs, size, flags)
    local f = fs:GetFont() or STANDARD_TEXT_FONT
    fs:SetFont(f, size, flags or "")
end

local function Apply()
    if not DB then return end
    FC:SetScale(DB.scale)
    FC:SetAlpha(DB.alpha)
    ApplyBackground()
    SetFont(title, DB.fontSize, "OUTLINE")
    SetFont(dist, DB.fontSize, "OUTLINE")
    SetFont(sub, math.max(8, DB.fontSize - 2), "OUTLINE")
    if not SetArrowArt(arrowTex, DB.arrow) then SetArrowArt(arrowTex, "classic") end
    title:ClearAllPoints(); sub:ClearAllPoints(); dist:ClearAllPoints(); arrowTex:ClearAllPoints()

    if DB.format == "bar" then
        arrowTex:Hide(); bar:Show()
        local w = DB.barWidth
        bar:ClearAllPoints()
        bar:SetPoint("TOP", FC, "TOP", 0, -6)
        bar:SetSize(w, 30)
        local h = 6 + 30
        local last = bar
        if DB.showTitle then title:SetPoint("TOP", last, "BOTTOM", 0, -2); title:Show(); last = title; h = h + DB.fontSize + 4 else title:Hide() end
        if DB.showDist then
            dist:SetPoint("TOP", last, "BOTTOM", 0, -2); dist:Show(); h = h + DB.fontSize + 4
        else dist:Hide() end
        sub:Hide()
        title:SetWidth(w - 20)
        FC:SetSize(w + 16, h + 8)
    else
        bar:Hide(); arrowTex:Show()
        arrowTex:SetSize(DB.size, DB.size)
        arrowTex:SetPoint("TOP", FC, "TOP", 0, -10)
        local h = 10 + DB.size + 6
        local last = arrowTex
        if DB.showTitle then title:SetPoint("TOP", last, "BOTTOM", 0, -2); title:Show(); last = title; h = h + DB.fontSize + 4 else title:Hide() end
        if DB.showSub then sub:SetPoint("TOP", last, "BOTTOM", 0, -1); sub:Show(); last = sub; h = h + DB.fontSize + 2 else sub:Hide() end
        if DB.showDist then dist:SetPoint("TOP", last, "BOTTOM", 0, -2); dist:Show(); h = h + DB.fontSize + 4 else dist:Hide() end
        local w = (DB.bg == "none") and math.max(DB.size + 20, 150) or math.max(DB.size + 40, 170)
        title:SetWidth(w - 16); sub:SetWidth(w - 16)
        FC:SetSize(w, h + 6)
    end
    FC:EnableMouse(not DB.locked)
end

------------------------------------------------------------------------------
-- Positions : coordonnées « monde » (fonctionne aussi entre deux cartes d'un continent)
------------------------------------------------------------------------------
local function PlayerMapPos()
    local map = C_Map.GetBestMapForUnit("player")
    if not map then return end
    local p = C_Map.GetPlayerMapPosition(map, "player")
    if not p then return end
    local x, y = p:GetXY()
    if not plain(x) or not plain(y) or (x == 0 and y == 0) then return end
    return map, x, y
end

local function World(map, x, y)
    if not (C_Map.GetWorldPosFromMapPos and CreateVector2D) then return end
    local ok, cont, pos = pcall(C_Map.GetWorldPosFromMapPos, map, CreateVector2D(x, y))
    if ok and cont and pos then
        local wx, wy = pos:GetXY()
        return cont, wx, wy          -- wx vers le nord, wy vers l'ouest
    end
end

-- distance (yards) et angle (radians, sens anti-horaire depuis le nord)
local function Vector(pmap, px, py, tmap, tx, ty)
    local c1, ax, ay = World(pmap, px, py)
    local c2, bx, by = World(tmap, tx, ty)
    if c1 and c2 and c1 == c2 then
        local dn, dw = bx - ax, by - ay
        return math.sqrt(dn * dn + dw * dw), math.atan2(dw, dn)
    end
    if pmap ~= tmap then return end
    local w, h = C_Map.GetMapWorldSize(pmap)
    if not w or w == 0 then return end
    local dx, dy = (tx - px) * w, (ty - py) * h          -- x vers l'est, y vers le sud
    return math.sqrt(dx * dx + dy * dy), math.atan2(-dx, -dy)
end

------------------------------------------------------------------------------
-- Cibles
------------------------------------------------------------------------------
local function QuestTitle(qid)
    return (C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(qid)) or "Quête"
end

local function QuestObjective(qid)
    local obj = C_QuestLog.GetQuestObjectives and C_QuestLog.GetQuestObjectives(qid)
    if obj then
        for _, o in ipairs(obj) do
            if not o.finished and o.text then return o.text end
        end
    end
    if obj and #obj > 0 and C_QuestLog.IsComplete and C_QuestLog.IsComplete(qid) then return "À rendre" end
    return ""
end

local SearchQuest
-- Recherche d'une quête sur tout le continent (la minicarte la montre même ailleurs).
-- Résultat gardé quelques secondes pour ne rien coûter en jeu.
local questCache = {}
local function FindOnMaps(qid, maps)
    for _, m in ipairs(maps) do
        local list = C_QuestLog.GetQuestsOnMap and C_QuestLog.GetQuestsOnMap(m)
        if list then
            for _, q in ipairs(list) do
                if q.questID == qid and q.x and q.y then return m, q.x, q.y end
            end
        end
    end
end

SearchQuest = function(map, qid)
    local c = questCache[qid]
    if c and GetTime() - c.t < 4 then
        if c.m then return c.m, c.x, c.y end
        return
    end
    local maps, seen = {}, {}
    local function add(m) if m and m > 0 and not seen[m] then seen[m] = true; maps[#maps + 1] = m end end
    add((GetQuestUiMapID and GetQuestUiMapID(qid)) or nil)
    if C_TaskQuest and C_TaskQuest.GetQuestZoneID then add(C_TaskQuest.GetQuestZoneID(qid)) end
    -- parents jusqu'au continent
    local cont
    local m = map
    for _ = 1, 6 do
        local info = C_Map.GetMapInfo and C_Map.GetMapInfo(m)
        if not info then break end
        add(info.mapID)
        if info.mapType == (Enum.UIMapType and Enum.UIMapType.Continent or 2) then cont = info.mapID; break end
        if not info.parentMapID or info.parentMapID == 0 then break end
        m = info.parentMapID
    end
    -- toutes les zones et villes du continent
    if cont and C_Map.GetMapChildrenInfo then
        local kids = C_Map.GetMapChildrenInfo(cont, nil, true)
        if kids then for _, k in ipairs(kids) do add(k.mapID) end end
    end
    local fm, fx, fy = FindOnMaps(qid, maps)
    questCache[qid] = { t = GetTime(), m = fm, x = fx, y = fy }
    return fm, fx, fy
end

local function QuestOnMap(map, qid)
    local list = C_QuestLog.GetQuestsOnMap and C_QuestLog.GetQuestsOnMap(map)
    if list then
        for _, q in ipairs(list) do
            if q.questID == qid and q.x and q.y then return map, q.x, q.y end
        end
    end
    if C_QuestLog.GetNextWaypoint then
        local wmap, wx, wy = C_QuestLog.GetNextWaypoint(qid)
        if wmap and wx then return wmap, wx, wy end
    end
    return SearchQuest(map, qid)
end

-- position du cadavre (sur ta carte, sinon sur ses cartes parentes)
local function CorpseTarget(map)
    -- plan B : l'endroit où tu es mort, noté au moment de la mort
    local function saved()
        local d = DB.deathPos
        if d then return d.map, d.x, d.y end
    end
    if not (C_DeathInfo and C_DeathInfo.GetCorpseMapPosition) then return saved() end
    local m = map
    for _ = 1, 5 do
        local pos = C_DeathInfo.GetCorpseMapPosition(m)
        if pos then
            local x, y = pos:GetXY()
            if x and (x ~= 0 or y ~= 0) then return m, x, y end
        end
        local info = C_Map.GetMapInfo and C_Map.GetMapInfo(m)
        if not info or not info.parentMapID or info.parentMapID == 0 then break end
        m = info.parentMapID
    end
    return saved()
end

local function IsDead()
    -- fantôme (esprit libéré) : avant ça, tu es déjà sur ton corps
    if UnitIsGhost then return UnitIsGhost("player") and true or false end
    return UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") and DB.deathPos ~= nil
end

local function Target(map, px, py)
    FC.noPos = nil
    FC.isCorpse = nil
    if DB.corpse and IsDead() then
        local m, x, y = CorpseTarget(map)
        if m then
            FC.isCorpse = true
            return m, x, y, "Ton cadavre", "Va le récupérer"
        end
    end
    if FC.manual then
        local m = FC.manual
        return m.map, m.x, m.y, m.title or "Cible", m.sub or "", true
    end
    if DB.useMapPin and C_Map.HasUserWaypoint and C_Map.HasUserWaypoint() then
        local wp = C_Map.GetUserWaypoint()
        if wp and wp.position then
            local x, y = wp.position:GetXY()
            return wp.uiMapID, x, y, "Point sur la carte", ""
        end
    end
    if DB.useSuperTrack then
        local qid = C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID and C_SuperTrack.GetSuperTrackedQuestID()
        if qid and qid > 0 then
            local m, x, y = QuestOnMap(map, qid)
            if m then return m, x, y, QuestTitle(qid), QuestObjective(qid) end
            FC.noPos = QuestTitle(qid)
        end
    end
    if DB.useNearest then
        local list = C_QuestLog.GetQuestsOnMap and C_QuestLog.GetQuestsOnMap(map)
        local best, bx, by, bid
        if list then
            for _, q in ipairs(list) do
                if q.x and q.y then
                    local d = (q.x - px) ^ 2 + (q.y - py) ^ 2
                    if not best or d < best then best, bx, by, bid = d, q.x, q.y, q.questID end
                end
            end
        end
        if bid then return map, bx, by, QuestTitle(bid), QuestObjective(bid) end
    end
end

------------------------------------------------------------------------------
-- Mise à jour
------------------------------------------------------------------------------
-- rotation par coordonnées de texture (marche partout, même si SetRotation est ignoré)
local function RotateTex(tex, a)          -- a > 0 = sens anti-horaire
    local c, s = math.cos(a), math.sin(a)
    local function uv(x, y)
        local xr = x * c + y * s
        local yr = -x * s + y * c
        return 0.5 + xr, 0.5 - yr
    end
    local ulx, uly = uv(-0.5, 0.5)
    local llx, lly = uv(-0.5, -0.5)
    local urx, ury = uv(0.5, 0.5)
    local lrx, lry = uv(0.5, -0.5)
    tex:SetTexCoord(ulx, uly, llx, lly, urx, ury, lrx, lry)
end

local function NormAngle(a)
    a = a % (2 * math.pi)
    if a > math.pi then a = a - 2 * math.pi end
    return a
end

local function ArrowColor(rel)
    if FC.isCorpse then return 1, 0.15, 0.12 end
    if DB.colorMode == "native" then return 1, 1, 1 end
    if DB.colorMode == "gold" then return 1, 0.82, 0
    elseif DB.colorMode == "white" then return 1, 1, 1
    elseif DB.colorMode == "custom" then return DB.color[1], DB.color[2], DB.color[3] end
    -- vert devant → jaune sur le côté → rouge derrière
    local t = math.abs(NormAngle(rel)) / math.pi
    if t < 0.5 then return 0.2 + t * 1.6, 1, 0.2 end
    return 1, 1 - (t - 0.5) * 1.6, 0.2
end

local function FormatDist(yards)
    if DB.unit == "yd" then
        return yards >= 1000 and ("%.1f k yd"):format(yards / 1000) or ("%d yd"):format(math.floor(yards))
    end
    local m = yards * YARD_TO_M
    return m >= 1000 and ("%.1f km"):format(m / 1000) or ("%d m"):format(math.floor(m))
end

local FOV = math.pi                       -- la boussole montre 180°
local function BarX(rel, w)               -- rel > 0 = à gauche
    return -rel / (FOV / 2) * (w / 2)
end

local function SetVisible(on)
    if on then
        FC:SetAlpha(DB.alpha)
        FC:EnableMouse(not DB.locked)
    else
        FC:SetAlpha(0)
        FC:EnableMouse(false)          -- invisible = on clique au travers
    end
end

local function ShowEmpty(text)
    -- sans quête suivie : rien à l'écran (sauf réglages ouverts, pour la placer)
    if DB.hideNoTarget and not FC.preview then SetVisible(false); return end
    SetVisible(true)
    title:SetText(text or "Aucune cible")
    sub:SetText("|cff888888/fc goto 45.2 63.1|r")
    dist:SetText("")
    arrowTex:SetVertexColor(0.5, 0.5, 0.5); arrowTex:SetAlpha(0.35); RotateTex(arrowTex, 0)
    marker:Hide(); edgeL:Hide(); edgeR:Hide()
end

local arrivedAt
local acc = 0
local function Update(self, e)
    acc = acc + e
    if acc < 0.03 or not DB then return end
    acc = 0
    local map, px, py = PlayerMapPos()
    if not map then return ShowEmpty("Position inconnue") end
    -- la cible bouge rarement : on la recalcule 4 fois par seconde, la flèche tourne à chaque image
    local now = GetTime()
    local tc = FC.tcache
    if not tc or now - tc.t > 0.25 or tc.manual ~= FC.manual then
        local a, b, c, d, f, g = Target(map, px, py)
        tc = { t = now, manual = FC.manual, a, b, c, d, f, g, noPos = FC.noPos, corpse = FC.isCorpse }
        FC.tcache = tc
    end
    FC.noPos, FC.isCorpse = tc.noPos, tc.corpse
    local tmap, tx, ty, name, desc, isManual = tc[1], tc[2], tc[3], tc[4], tc[5], tc[6]
    if not tmap then
        if FC.noPos then
            SetVisible(true)
            title:SetText(FC.noPos)
            sub:SetText("Pas de position ici : ouvre la carte de sa zone")
            dist:SetText("")
            arrowTex:SetVertexColor(0.5, 0.5, 0.5); arrowTex:SetAlpha(0.35); RotateTex(arrowTex, 0)
            marker:Hide(); edgeL:Hide(); edgeR:Hide()
            return
        end
        return ShowEmpty()
    end
    local yards, angle = Vector(map, px, py, tmap, tx, ty)
    if not yards then return ShowEmpty(name and (name .. " (autre zone)")) end
    SetVisible(true)
    title:SetText(name or "")
    sub:SetText(desc or "")
    if FC.isCorpse then title:SetTextColor(1, 0.25, 0.2) else title:SetTextColor(1, 0.82, 0) end
    local facing = GetPlayerFacing and GetPlayerFacing()
    local hasFacing = facing and plain(facing)
    local rel = hasFacing and NormAngle(angle - facing) or 0
    if DB.invert then rel = -rel end

    if FC.isCorpse and yards < 30 then
        dist:SetText("|cff33ff55Tu peux ressusciter !|r")
    elseif yards < 8 then
        dist:SetText("|cff33ff55Arrivé !|r")
        if isManual and DB.arriveClear then
            arrivedAt = arrivedAt or GetTime()
            if GetTime() - arrivedAt > 3 then FC.manual = nil; arrivedAt = nil end
        end
    else
        arrivedAt = nil
        dist:SetText(FormatDist(yards))
    end

    local r, g, b = ArrowColor(rel)
    if DB.format == "bar" then
        local w = DB.barWidth
        local heading = hasFacing and facing or 0
        for _, fs in ipairs(letters) do
            local x = BarX(NormAngle(fs.angle - heading), w)
            fs:ClearAllPoints(); fs:SetPoint("CENTER", bar, "CENTER", x, 5)
            fs:SetShown(math.abs(x) < w / 2 - 6)
        end
        for _, t in ipairs(ticks) do
            local x = BarX(NormAngle(t.angle - heading), w)
            t:ClearAllPoints(); t:SetPoint("BOTTOM", bar, "CENTER", x, -6)
            t:SetShown(math.abs(x) < w / 2 - 2)
        end
        if hasFacing then
            local x = BarX(rel, w)
            local lim = w / 2 - 10
            edgeL:SetShown(x < -lim); edgeR:SetShown(x > lim)
            if DB.colorMode == "native" and not FC.isCorpse then r, g, b = 1, 0.82, 0 end
            edgeL:SetTextColor(r, g, b); edgeR:SetTextColor(r, g, b)
            marker:SetShown(math.abs(x) <= lim)
            marker:ClearAllPoints(); marker:SetPoint("CENTER", bar, "CENTER", x, -6)
            if DB.colorMode == "native" and not FC.isCorpse then marker:SetVertexColor(1, 0.82, 0) else marker:SetVertexColor(r, g, b) end
        else
            marker:Hide(); edgeL:Hide(); edgeR:Hide()
        end
    else
        arrowTex:SetAlpha(hasFacing and 1 or 0.35)
        RotateTex(arrowTex, rel)
        FC.lastRel, FC.lastAngle = rel, angle
        arrowTex:SetVertexColor(r, g, b)
    end
end
FC:SetScript("OnUpdate", function(self, e)
    local ok, err = pcall(Update, self, e)
    if not ok then FC.lastErr = err end
    if not ok and not FC.errShown then
        FC.errShown = true
        print("|cffffd100Forever Compass|r : " .. tostring(err))
    end
end)

------------------------------------------------------------------------------
-- Déplacement (clic droit = réglages)
------------------------------------------------------------------------------
local category
local function OpenOptions()
    if category and Settings and Settings.OpenToCategory then
        pcall(Settings.OpenToCategory, category:GetID())
    end
end

FC:SetScript("OnDragStart", function(self) if DB and (not DB.locked or NZR.editing) then self:StartMoving() end end)
FC:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local p, _, _, x, y = self:GetPoint()
    DB.point, DB.x, DB.y = p, x, y
end)
-- clic droit = réglages ; clic gauche sur une cible posée à la main = retour à la quête suivie
FC:SetScript("OnMouseUp", function(_, btn)
    if btn == "RightButton" then OpenOptions()
    elseif btn == "LeftButton" and FC.manual then FC.manual = nil; NZR:Print("flèche : retour à ta quête.") end
end)
FC:SetScript("OnEnter", function(self)
    if not DB or DB.locked then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine("Forever Compass")
    GameTooltip:AddLine("Glisser : déplacer. Clic droit : réglages.", 1, 1, 1, true)
    GameTooltip:AddLine("Verrouille-la dans les réglages pour cliquer au travers.", 0.7, 0.7, 0.7, true)
    GameTooltip:Show()
end)
FC:SetScript("OnLeave", function() GameTooltip:Hide() end)

------------------------------------------------------------------------------
-- Compatibilité Questie (et autres) : si TomTom n'est pas là, on reçoit ses points
------------------------------------------------------------------------------
local uidCount = 0
local function SetManual(map, x, y, name, desc)
    uidCount = uidCount + 1
    FC.manual = { map = map, x = x, y = y, title = name, sub = desc, uid = { id = uidCount } }
    return FC.manual.uid
end

local function TomTomInstalled()
    if not C_AddOns then return false end
    if C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("TomTom") then return true end
    if C_AddOns.GetAddOnEnableState then
        local ok, st = pcall(C_AddOns.GetAddOnEnableState, "TomTom", UnitName("player"))
        if ok and type(st) == "number" and st > 0 then return true end
    end
    return false
end

local function InstallTomTomBridge()
    if TomTom or not DB.tomtom or TomTomInstalled() then return end
    local T = { ForeverCompass = true, profile = { arrow = {}, persistence = {} }, db = { profile = { arrow = {}, persistence = {} } } }
    function T:AddWaypoint(map, x, y, opts)
        if type(map) ~= "number" or type(x) ~= "number" or type(y) ~= "number" then return end
        if x > 1 then x = x / 100 end
        if y > 1 then y = y / 100 end
        local t = type(opts) == "table" and opts.title or nil
        return SetManual(map, x, y, t or "Point", (type(opts) == "table" and opts.from) or "")
    end
    function T:AddMFWaypoint(map, _, x, y, opts) return T:AddWaypoint(map, x, y, opts) end
    function T:RemoveWaypoint(uid) if FC.manual and (uid == nil or FC.manual.uid == uid) then FC.manual = nil end end
    function T:ClearWaypoint(uid) T:RemoveWaypoint(uid) end
    function T:RemoveAllWaypoints() FC.manual = nil end
    function T:SetClosestWaypoint() end
    function T:SetCrazyArrow(uid) end
    function T:IsValidWaypoint(uid) return FC.manual ~= nil and FC.manual.uid == uid end
    function T:WaypointExists() return FC.manual ~= nil end
    function T:GetKey() return nil end
    function T:GetDistanceToWaypoint(uid)
        if not FC.manual then return end
        local map, px, py = PlayerMapPos()
        if not map then return end
        local d = Vector(map, px, py, FC.manual.map, FC.manual.x, FC.manual.y)
        return d
    end
    function T:GetDirectionToWaypoint() return nil end
    TomTom = T
end

------------------------------------------------------------------------------
-- Réglages : Échap > Options > AddOns > Forever Compass (contrôles du jeu)
------------------------------------------------------------------------------
local controls = {}

local function Check(parent, label, key, x, y, onChange)
    local c = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    c:SetSize(26, 26)
    c:SetPoint("TOPLEFT", x, y)
    local t = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    t:SetPoint("LEFT", c, "RIGHT", 2, 0); t:SetText(label)
    c:SetScript("OnClick", function(s)
        DB[key] = s:GetChecked() and true or false
        if onChange then onChange() end
        Apply()
    end)
    c.Refresh = function(s) s:SetChecked(DB[key] and true or false) end
    table.insert(controls, c)
    return c
end

local function Radio(parent, label, key, list, x, y)
    local l = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    l:SetPoint("TOPLEFT", x, y); l:SetText(label)
    local f = CreateFrame("Frame", nil, parent)
    f:SetPoint("TOPLEFT", x, y - 18); f:SetSize(500, 22)
    f.btns = {}
    local cx = 0
    for _, ch in ipairs(list) do
        local b = CreateFrame("CheckButton", nil, f, "UIRadioButtonTemplate")
        b:SetSize(18, 18); b:SetPoint("LEFT", cx, 0)
        local t = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        t:SetPoint("LEFT", b, "RIGHT", 2, 0); t:SetText(ch[2])
        b.value, b.label = ch[1], t
        cx = cx + 22 + math.ceil(t:GetStringWidth()) + 14
        b:SetScript("OnClick", function() DB[key] = b.value; f:Refresh(); Apply() end)
        table.insert(f.btns, b)
    end
    function f:Refresh()
        for _, b in ipairs(self.btns) do
            b:SetChecked(DB[key] == b.value)
            if DB[key] == b.value then b.label:SetTextColor(1, 0.82, 0) else b.label:SetTextColor(0.9, 0.9, 0.9) end
        end
    end
    table.insert(controls, f)
    return f
end

local function Slider(parent, label, key, min, max, step, fmt, x, y)
    local l = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    l:SetPoint("TOPLEFT", x, y); l:SetText(label)
    local v = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    local s = CreateFrame("Slider", nil, parent)
    s:SetOrientation("HORIZONTAL")
    s:SetPoint("TOPLEFT", x, y - 20); s:SetSize(200, 17)
    local track = s:CreateTexture(nil, "BACKGROUND")
    track:SetPoint("LEFT"); track:SetPoint("RIGHT"); track:SetHeight(8)
    if not (pcall(track.SetAtlas, track, "Minimal_SliderBar_Middle", false) and track:GetAtlas()) then
        track:SetColorTexture(0.15, 0.15, 0.16, 1)
    end
    s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    s:GetThumbTexture():SetSize(32, 32)
    v:SetPoint("LEFT", s, "RIGHT", 10, 0)
    s:SetMinMaxValues(min, max); s:SetValueStep(step); s:SetObeyStepOnDrag(true)
    s:SetScript("OnValueChanged", function(_, val)
        val = math.floor(val / step + 0.5) * step
        DB[key] = val
        v:SetText(fmt(val))
        Apply()
    end)
    s.Refresh = function(self) self:SetValue(DB[key]); v:SetText(fmt(DB[key])) end
    table.insert(controls, s)
    return s
end

local function Button(parent, text, x, y, onClick, w)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w or 150, 22); b:SetPoint("TOPLEFT", x, y)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

local function PickColor(after)
    local c = DB.color
    local function set(r, g, b) DB.color = { r, g, b }; DB.colorMode = "custom"; Apply(); if after then after() end end
    if ColorPickerFrame and ColorPickerFrame.SetupColorPickerAndShow then
        ColorPickerFrame:SetupColorPickerAndShow({
            r = c[1], g = c[2], b = c[3], hasOpacity = false,
            swatchFunc = function() set(ColorPickerFrame:GetColorRGB()) end,
            cancelFunc = function(prev) if prev then set(prev.r, prev.g, prev.b) end end,
        })
    end
end

local function BuildOptions()
    local panel = CreateFrame("Frame")
    panel:Hide()
    local scroll = CreateFrame("ScrollFrame", "NZRF_CompassOptionsScroll", panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, -4); scroll:SetPoint("BOTTOMRIGHT", -28, 4)
    local p = CreateFrame("Frame", nil, scroll)
    p:SetSize(600, 760)
    scroll:SetScrollChild(p)

    local t = p:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    t:SetPoint("TOPLEFT", 16, -16); t:SetText("Forever Compass")
    local d = p:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    d:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -6); d:SetWidth(560); d:SetJustifyH("LEFT")
    d:SetText("Une flèche ou une boussole à placer où tu veux. Tout s'applique tout de suite. "
        .. "Glisse-la pour la déplacer, clic droit dessus pour revenir ici.")

    local y = -64
    Radio(p, "Format", "format", { { "arrow", "Flèche" }, { "bar", "Boussole (bande)" } }, 16, y); y = y - 50
    Radio(p, "Style de la flèche", "arrow", ARROWS, 16, y); y = y - 50
    Radio(p, "Couleur", "colorMode", { { "native", "Du jeu" }, { "dynamic", "Selon la direction" }, { "gold", "Dorée" }, { "custom", "Perso" } }, 16, y)
    Button(p, "Choisir la couleur…", 420, y - 16, function() PickColor(function() for _, c in ipairs(controls) do if c.Refresh then c:Refresh() end end end) end, 150)
    y = y - 50
    Radio(p, "Fond et contour", "bg", { { "none", "Aucun" }, { "tooltip", "Infobulle" }, { "dialog", "Fenêtre" } }, 16, y); y = y - 56

    Slider(p, "Taille de la flèche", "size", 24, 128, 2, function(v) return ("%d"):format(v) end, 16, y)
    Slider(p, "Largeur de la boussole", "barWidth", 200, 700, 10, function(v) return ("%d"):format(v) end, 310, y); y = y - 56
    Slider(p, "Échelle", "scale", 0.5, 2, 0.05, function(v) return ("%d %%"):format(math.floor(v * 100 + 0.5)) end, 16, y)
    Slider(p, "Opacité", "alpha", 0.2, 1, 0.05, function(v) return ("%d %%"):format(math.floor(v * 100 + 0.5)) end, 310, y); y = y - 56
    Slider(p, "Taille du texte", "fontSize", 8, 20, 1, function(v) return ("%d"):format(v) end, 16, y)
    Radio(p, "Distance en", "unit", { { "m", "Mètres" }, { "yd", "Yards" } }, 310, y); y = y - 60

    local s1 = p:CreateFontString(nil, "ARTWORK", "GameFontNormal"); s1:SetPoint("TOPLEFT", 16, y); s1:SetText("Infos sous la flèche (facultatif)"); y = y - 20
    Check(p, "Nom de la cible", "showTitle", 16, y); Check(p, "Objectif de la quête", "showSub", 310, y); y = y - 28
    Check(p, "Distance", "showDist", 16, y); Check(p, "Cacher quand aucune quête n'est suivie", "hideNoTarget", 310, y); y = y - 28
    Check(p, "Verrouiller (clics au travers)", "locked", 16, y); y = y - 40

    local s2 = p:CreateFontString(nil, "ARTWORK", "GameFontNormal"); s2:SetPoint("TOPLEFT", 16, y); s2:SetText("Que viser ? (dans cet ordre)"); y = y - 20
    Check(p, "Point posé sur la carte (Ctrl+clic)", "useMapPin", 16, y); Check(p, "Quête suivie (clic dans le suivi)", "useSuperTrack", 310, y); y = y - 28
    Check(p, "Sinon la quête la plus proche (sans rien suivre)", "useNearest", 16, y)
    Check(p, "Points de Questie / « TomTom »", "tomtom", 310, y, function()
        if DB.tomtom then InstallTomTomBridge() end
    end); y = y - 28
    Check(p, "Effacer un point manuel une fois arrivé", "arriveClear", 16, y)
    Check(p, "Inverser le sens de la flèche", "invert", 310, y); y = y - 28
    Check(p, "Mort : flèche rouge vers ton cadavre", "corpse", 16, y); y = y - 40

    Button(p, "Effacer la cible", 16, y, function() FC.manual = nil end)
    Button(p, "Remettre au centre", 176, y, function()
        DB.point, DB.x, DB.y = "CENTER", 0, 220
        FC:ClearAllPoints(); FC:SetPoint("CENTER", UIParent, "CENTER", 0, 220)
    end)
    Button(p, "Tout réinitialiser", 336, y, function()
        for k, v in pairs(defaults) do DB[k] = (type(v) == "table") and { unpack(v) } or v end
        FC:ClearAllPoints(); FC:SetPoint(DB.point, UIParent, DB.point, DB.x, DB.y)
        for _, c in ipairs(controls) do if c.Refresh then c:Refresh() end end
        Apply()
    end); y = y - 40

    local help = p:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    help:SetPoint("TOPLEFT", 16, y); help:SetWidth(560); help:SetJustifyH("LEFT")
    help:SetText("|cffffd100/fc goto 45.2 63.1 Nom|r : viser des coordonnées de ta zone.   |cffffd100/fc here|r : repère à ta position.\n"
        .. "|cffffd100/fc clear|r : effacer.   |cffffd100/fc lock|r, |cffffd100/fc unlock|r : verrouiller.\n"
        .. "Questie : clic droit sur un objectif > « TomTom » envoie le point ici (si TomTom n'est pas installé).")

    panel:SetScript("OnShow", function()
        FC.preview = true
        for _, c in ipairs(controls) do if c.Refresh then c:Refresh() end end
    end)
    panel:SetScript("OnHide", function() FC.preview = false end)

    if Settings and Settings.RegisterCanvasLayoutCategory then
        category = Settings.RegisterCanvasLayoutCategory(panel, "NZR Forever : flèche")
        Settings.RegisterAddOnCategory(category)
    end
end

------------------------------------------------------------------------------
-- Commandes
------------------------------------------------------------------------------
local function RegisterSlash()
SLASH_NZRFCOMPASS1 = "/fc"
SLASH_NZRFCOMPASS2 = "/fcompass"
SlashCmdList["NZRFCOMPASS"] = function(msg)
    local cmd, rest = (msg or ""):match("^(%S*)%s*(.*)$")
    cmd = (cmd or ""):lower()
    if cmd == "goto" or cmd == "way" then
        local x, y, name = rest:match("^([%d%.]+)[%s,]+([%d%.]+)%s*(.*)$")
        x, y = tonumber(x), tonumber(y)
        local map = PlayerMapPos()
        if not x or not y or not map then print("|cffffd100Forever Compass|r : /fc goto 45.2 63.1 [nom]") return end
        if x > 1 then x = x / 100 end
        if y > 1 then y = y / 100 end
        SetManual(map, x, y, (name ~= "" and name) or ("%.1f, %.1f"):format(x * 100, y * 100))
    elseif cmd == "here" then
        local map, px, py = PlayerMapPos()
        if map then SetManual(map, px, py, "Repère") end
    elseif cmd == "clear" then
        FC.manual = nil
    elseif cmd == "debug" then
        local map, px, py = PlayerMapPos()
        print("|cffffd100Forever Compass|r debug :")
        print("  format=" .. tostring(DB.format) .. " flèche=" .. tostring(DB.arrow) .. " taille=" .. tostring(DB.size))
        print("  texture=" .. tostring(arrowTex:GetTexture()) .. " atlas=" .. tostring(arrowTex.GetAtlas and arrowTex:GetAtlas()) ..
              " visible=" .. tostring(arrowTex:IsVisible()) .. " alpha=" .. tostring(arrowTex:GetAlpha()))
        print("  carte=" .. tostring(map) .. " pos=" .. tostring(px) .. "," .. tostring(py) .. " orientation=" .. tostring(GetPlayerFacing and GetPlayerFacing()))
        local tmap, tx, ty, name = Target(map or 0, px or 0, py or 0)
        print("  cible=" .. tostring(name) .. " carte=" .. tostring(tmap) .. " " .. tostring(tx) .. "," .. tostring(ty))
        local qid = C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID and C_SuperTrack.GetSuperTrackedQuestID()
        if qid and qid > 0 then
            local wm, wx, wy = nil, nil, nil
            if C_QuestLog.GetNextWaypoint then wm, wx, wy = C_QuestLog.GetNextWaypoint(qid) end
            print("  quête suivie=" .. qid .. " étape suivante du jeu=" .. tostring(wm) .. " " .. tostring(wx) .. "," .. tostring(wy))
            local cm = C_Map.GetMapInfo and tmap and C_Map.GetMapInfo(tmap)
            print("  trouvée sur la carte : " .. tostring(cm and cm.name))
        end
        print("  angle cible=" .. tostring(FC.lastAngle) .. " relatif=" .. tostring(FC.lastRel) .. " erreur=" .. tostring(FC.lastErr))
        local cm, cx, cy = CorpseTarget(map or 0)
        print("  mort=" .. tostring(UnitIsDeadOrGhost and UnitIsDeadOrGhost("player")) .. " fantôme=" .. tostring(UnitIsGhost and UnitIsGhost("player")) ..
              " cadavre=" .. tostring(cm) .. " " .. tostring(cx) .. "," .. tostring(cy) .. " option=" .. tostring(DB.corpse))
        print("  TomTom=" .. tostring(TomTom and (TomTom.ForeverCompass and "pont Forever Compass" or "vrai TomTom") or "absent"))
    elseif cmd == "inverse" or cmd == "invert" then
        DB.invert = not DB.invert
        print("|cffffd100Forever Compass|r : sens " .. (DB.invert and "inversé" or "normal") .. ".")
    elseif cmd == "lock" then
        DB.locked = true; Apply(); print("|cffffd100Forever Compass|r : verrouillée.")
    elseif cmd == "unlock" then
        DB.locked = false; Apply(); print("|cffffd100Forever Compass|r : déverrouillée. Ouvre les réglages (/fc) pour la voir et la placer.")
    else
        OpenOptions()
    end
end
-- /way comme TomTom, si personne ne l'utilise déjà
if not SlashCmdList["TOMTOM_WAY"] and not _G.SLASH_WAY1 then
    SLASH_FCWAY1 = "/way"
    SlashCmdList["FCWAY"] = function(msg) SlashCmdList["NZRFCOMPASS"]("goto " .. (msg or "")) end
end

end

------------------------------------------------------------------------------
-- Chargement
------------------------------------------------------------------------------
local function Start(self)
        NZR.db.compassCfg = NZR.db.compassCfg or {}
        DB = NZR.db.compassCfg
        -- anciennes valeurs (première version) : numéros → noms
        if type(DB.arrow) == "number" then DB.arrow = nil end
        if type(DB.bg) == "number" then DB.bg = nil end
        DB.zoneWidth = nil
        if not DB.v24 then
            DB.v24 = true
            DB.useNearest, DB.hideNoTarget = false, true
        end
        if not DB.v23 then
            DB.v23 = true
            DB.arrow, DB.size = "gem", 72
            DB.showTitle, DB.showSub, DB.showDist = true, true, true
        end
        if not DB.v22 then
            DB.v22 = true
            if DB.arrow == "nav" then DB.arrow = "gold" end
        end
        if not DB.v21 then
            DB.v21 = true
            DB.arrow, DB.bg, DB.colorMode, DB.size = nil, nil, nil, nil
            DB.showTitle, DB.showSub = nil, nil
        end
        for k, v in pairs(defaults) do
            if DB[k] == nil then DB[k] = (type(v) == "table") and { unpack(v) } or v end
        end
        self:ClearAllPoints()
        self:SetPoint(DB.point, UIParent, DB.point, DB.x, DB.y)
        Apply()
        BuildOptions()
        InstallTomTomBridge()
end

local function OnEvent(self, event)
    -- tu choisis / suis une autre quête : la cible posée par le guide s'efface
    if event == "SUPER_TRACKING_CHANGED" or event == "QUEST_WATCH_LIST_CHANGED" or event == "QUEST_ACCEPTED" then
        if FC.manual and FC.manual.sub == "Guide de leveling" then FC.manual = nil end
        return
    end
    if event == "PLAYER_DEAD" then
        local map, x, y = PlayerMapPos()
        if map then DB.deathPos = { map = map, x = x, y = y } end
    elseif (event == "PLAYER_ALIVE" or event == "PLAYER_UNGHOST") then
        if not (UnitIsDeadOrGhost and UnitIsDeadOrGhost("player")) then DB.deathPos = nil end
    end
end

function MOD:Init()
    if NZR.withUI or not NZR.db.compass then return end
    local standalone = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("ForeverCompass")
    if standalone then
        NZR:Print("flèche : l'addon Forever Compass est déjà actif, c'est lui qui sert.")
        return
    end
    Start(FC)
    FC:Show()
    RegisterSlash()
    FC:RegisterEvent("PLAYER_DEAD")
    FC:RegisterEvent("PLAYER_ALIVE")
    FC:RegisterEvent("PLAYER_UNGHOST")
    for _, e in ipairs({ "SUPER_TRACKING_CHANGED", "QUEST_WATCH_LIST_CHANGED", "QUEST_ACCEPTED" }) do pcall(FC.RegisterEvent, FC, e) end
    FC:SetScript("OnEvent", OnEvent)
    NZR.CompassOpen = OpenOptions
    -- cible posée par un autre module (ex. guide de leveling : centre d'une zone)
    NZR.CompassClear = function() FC.manual = nil end
    NZR.CompassEdit = function(on) FC:EnableMouse(on or not DB.locked); if on then FC:Show() end end
    NZR.CompassPointTo = function(map, x, y, name, desc)
        SetManual(map, x, y, name, desc)
        FC:Show()
        return true
    end
end
