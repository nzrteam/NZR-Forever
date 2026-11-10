-- NZR Forever - Temps de respawn (facultatif, désactivé par défaut)
-- Le jeu ne donne pas le temps de respawn d'un monstre : NZR l'apprend.
-- Quand un monstre suivi meurt sous tes yeux, un chrono démarre à l'endroit où tu es ;
-- quand il réapparaît, le temps est noté. Dès qu'un temps est connu, NZR annonce le
-- retour : fenêtre, repère dans le monde avec le minuteur, minicarte, grande carte,
-- ligne dans l'infobulle et petit son.
local _, NZR = ...
local M = NZR:Module("Respawn")
local plain = NZR.plain

local function DB() return NZR.db end
local MAX_SAMPLES, MAX_ROWS, KEEP_ALIVE = 8, 8, 60
local WIN_W, ROW_H, PAD = 214, 20, 14

local data                  -- NZRF_DB.respawnData = { npcs, active, watch }
local aliveGUID, npcGuids = {}, {}
local win, rows, holder = nil, {}, nil
local ticker
local ourWP, prevQuest      -- repère posé par NZR (pour ne jamais effacer celui du joueur)
local label                 -- minuteur au-dessus du repère dans le monde
local mmPins, wmPins = {}, {}
local userHidden

---------------------------------------------------------------------------
-- Outils
---------------------------------------------------------------------------
local function Now() return GetServerTime and GetServerTime() or time() end

local function Clock(s)
    s = math.max(0, math.floor(s + 0.5))
    if s >= 3600 then return ("%d:%02d:%02d"):format(s / 3600, (s % 3600) / 60, s % 60) end
    return ("%d:%02d"):format(s / 60, s % 60)
end

local function Ensure()
    local db = DB()
    db.respawnData = db.respawnData or {}
    data = db.respawnData
    data.npcs = data.npcs or {}
    data.active = data.active or {}
    data.watch = data.watch or {}
    data.ignore = data.ignore or {}     -- monstres retirés à la main : plus suivis automatiquement
end

-- GUID de créature -> numéro du monstre (rien si secret ou pas une créature)
local function UnitNPC(unit)
    local ok, guid = pcall(UnitGUID, unit)
    if not ok or not plain(guid) or type(guid) ~= "string" then return end
    local typ, _, _, _, _, npc = strsplit("-", guid)
    if typ ~= "Creature" and typ ~= "Vehicle" then return end
    npc = tonumber(npc)
    if npc then return npc, guid end
end

local function SafeName(unit)
    local ok, n = pcall(UnitName, unit)
    if ok and plain(n) and n ~= "" then return n end
end

-- icône d'un monstre : son portrait (pris quand il meurt sous tes yeux), sinon son type
local portraits = {}            -- [clé du chrono] = texture portrait (session en cours)
local portraitHost
local FAMILY = {
    ["araignée"] = "Spider", spider = "Spider", ["loup"] = "Wolf", wolf = "Wolf", ["ours"] = "Bear", bear = "Bear",
    ["sanglier"] = "Boar", boar = "Boar", ["félin"] = "Cat", cat = "Cat", ["raptor"] = "Raptor",
    ["crabe"] = "Crab", crab = "Crab", ["gorille"] = "Gorilla", gorilla = "Gorilla", ["chauve-souris"] = "Bat", bat = "Bat",
    ["chouette"] = "Owl", owl = "Owl", ["oiseau charognard"] = "Vulture", ["carrion bird"] = "Vulture",
    ["hyène"] = "Hyena", hyena = "Hyena", ["crocilisque"] = "Crocolisk", crocolisk = "Crocolisk",
    ["scorpide"] = "Scorpid", scorpid = "Scorpid", ["tortue"] = "Turtle", turtle = "Turtle",
    ["haut-trotteur"] = "TallStrider", ["tallstrider"] = "TallStrider", ["serpent des vents"] = "WindSerpent", ["wind serpent"] = "WindSerpent",
}
local TYPE = {
    ["humanoïde"] = "INV_Misc_Head_Human_01", humanoid = "INV_Misc_Head_Human_01",
    ["bête"] = "Ability_Hunter_Pet_Wolf", beast = "Ability_Hunter_Pet_Wolf",
    ["démon"] = "Spell_Shadow_SummonFelHunter", demon = "Spell_Shadow_SummonFelHunter",
    ["draconien"] = "INV_Misc_Head_Dragon_01", dragonkin = "INV_Misc_Head_Dragon_01",
    ["élémentaire"] = "Spell_Nature_EarthElemental_Totem", elemental = "Spell_Nature_EarthElemental_Totem",
    ["mort-vivant"] = "Spell_Shadow_RaiseDead", undead = "Spell_Shadow_RaiseDead",
    ["mécanique"] = "INV_Misc_Gear_01", mechanical = "INV_Misc_Gear_01",
    ["géant"] = "Ability_Warrior_Rampage", giant = "Ability_Warrior_Rampage",
}
local function TypeIcon(e)
    local fam = e.fam and FAMILY[e.fam:lower()]
    if fam then return "Interface\\Icons\\Ability_Hunter_Pet_" .. fam end
    local t = e.ctype and TYPE[e.ctype:lower()]
    if t then return "Interface\\Icons\\" .. t end
    return "Interface\\TargetingFrame\\UI-TargetingFrame-Skull"
end
local function TakePortrait(key, unit)
    if not SetPortraitTexture then return end
    portraitHost = portraitHost or CreateFrame("Frame", nil, UIParent)
    local tex = portraits[key] or portraitHost:CreateTexture(nil, "ARTWORK")
    if pcall(SetPortraitTexture, tex, unit) then
        tex:SetTexCoord(0.12, 0.88, 0.12, 0.88)
        tex:Hide()
        portraits[key] = tex
    end
end
local function DropPortrait(key)
    local tex = portraits[key]
    if tex then tex:Hide(); tex:SetParent(portraitHost); portraits[key] = nil end
end

local function Bool(fn, ...)
    local ok, v = pcall(fn, ...)
    return ok and plain(v) and v and true or false
end

local function InInstance()
    local ok, inside, kind = pcall(IsInInstance)
    return ok and inside and (kind == "party" or kind == "raid" or kind == "scenario")
end

local QUEST_LINES
local function UnitIsQuest(unit)
    if C_QuestLog and C_QuestLog.UnitIsRelatedToActiveQuest then
        local ok, r = pcall(C_QuestLog.UnitIsRelatedToActiveQuest, unit)
        if ok and plain(r) and r then return true end
    end
    -- sur Forever : les lignes « quête » de l'infobulle du monstre
    if not QUEST_LINES then
        QUEST_LINES = {}
        local T = Enum and Enum.TooltipDataLineType
        if T then for _, k in ipairs({ "QuestObjective", "QuestTitle", "QuestPlayer" }) do if T[k] then QUEST_LINES[T[k]] = true end end end
    end
    if C_TooltipInfo and C_TooltipInfo.GetUnit then
        local ok, d = pcall(C_TooltipInfo.GetUnit, unit)
        if ok and d and d.lines then
            for _, line in ipairs(d.lines) do
                if line.type and plain(line.type) and QUEST_LINES[line.type] then return true end
            end
        end
    end
    return false
end
local questGUID = {}
local firstPos = {}
local idlePos = {}     -- [guid] = ta position quand tu es passé tout près de lui, tranquille (≈ son point)

-- le jeu dit seulement (hors combat) si un monstre est à moins de ~10 m (3) ou ~28 m (4) de toi
local function Near(unit, idx)
    if not CheckInteractDistance then return nil end
    local ok, r = pcall(CheckInteractDistance, unit, idx)
    if ok and plain(r) then return r and true or false end
    return nil
end    -- [guid] = ta position au premier coup échangé (≈ là où il attendait)

-- suivi ? renvoie aussi si c'est un monstre « courant » (plusieurs du même nom autour)
local function IsWatched(unit, npc, guid)
    if data.watch[npc] then return true, false end
    if data.ignore[npc] then return false end
    local db = DB()
    if db.respawnAuto ~= false then
        local ok, c = pcall(UnitClassification, unit)
        if ok and plain(c) and (c == "elite" or c == "rare" or c == "rareelite" or c == "worldboss") then return true, false end
    end
    if db.respawnQuest ~= false and questGUID[guid] then return true, true end
    -- tes victimes : un monstre mort que ni personne d'autre n'avait tagué
    if db.respawnMine ~= false then
        local okT, denied = pcall(UnitIsTapDenied, unit)
        if okT and plain(denied) and not denied then return true, true end
    end
    return false
end

-- temps connus : rapide, moyen, lent, nombre
-- point d'apparition : case d'environ 10 m sur la carte ; on regarde aussi les cases voisines
local CELL = 0.005
local function SpotSamples(npc, e)
    if not (e and e.map and e.x and data.spots) then return end
    local gx, gy = math.floor(e.x / CELL + 0.5), math.floor(e.y / CELL + 0.5)
    local out
    for dx = -1, 1 do for dy = -1, 1 do
        local list = data.spots[("%d:%d:%d:%d"):format(npc, e.map, gx + dx, gy + dy)]
        if list then out = out or {}; for _, v in ipairs(list) do out[#out + 1] = v end end
    end end
    return out
end
local function AddSpotSample(npc, e, el)
    if not (e.map and e.x) then return end
    data.spots = data.spots or {}
    local key = ("%d:%d:%d:%d"):format(npc, e.map, math.floor(e.x / CELL + 0.5), math.floor(e.y / CELL + 0.5))
    local list = data.spots[key] or {}
    data.spots[key] = list
    table.insert(list, el)
    while #list > MAX_SAMPLES do table.remove(list, 1) end
end

local function Stats(npc, e)
    if e and e.npc then npc = e.npc end
    -- le temps de CE point d'apparition s'il est connu, sinon celui du monstre en général
    local s = (e and e.test) or SpotSamples(npc, e) or (data.npcs[npc] and data.npcs[npc].s)
    if not s or #s == 0 then return end
    -- médiane plutôt que moyenne : un relevé faux ne fait pas sauter les chronos
    local t = {}
    for i, v in ipairs(s) do t[i] = v end
    table.sort(t)
    local n = #t
    local mid = (n % 2 == 1) and t[(n + 1) / 2] or (t[n / 2] + t[n / 2 + 1]) / 2
    return t[1], mid, t[n], n
end

---------------------------------------------------------------------------
-- Position (la tienne au moment de la mort : le jeu ne donne pas celle du monstre)
---------------------------------------------------------------------------
local sizeCache = {}
local function MapSize(map)
    local c = sizeCache[map]
    if c ~= nil then if c then return c[1], c[2] end return end
    sizeCache[map] = false
    if not (C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return end
    local ok1, _, tl = pcall(C_Map.GetWorldPosFromMapPos, map, CreateVector2D(0, 0))
    local ok2, _, br = pcall(C_Map.GetWorldPosFromMapPos, map, CreateVector2D(1, 1))
    if ok1 and ok2 and tl and br then
        local okA, w = pcall(function() return math.abs(tl.y - br.y) end)
        local okB, h = pcall(function() return math.abs(tl.x - br.x) end)
        if okA and okB and w > 0 and h > 0 then sizeCache[map] = { w, h }; return w, h end
    end
end

local function PlayerOn(map)
    if not (C_Map and C_Map.GetPlayerMapPosition) then return end
    local ok, p = pcall(C_Map.GetPlayerMapPosition, map, "player")
    if not ok or not p then return end
    local ok2, x, y = pcall(p.GetXY, p)
    if ok2 and plain(x) and plain(y) and (x ~= 0 or y ~= 0) then return x, y end
end

local function PlayerSpot()
    if not (C_Map and C_Map.GetBestMapForUnit) then return end
    local ok, map = pcall(C_Map.GetBestMapForUnit, "player")
    if not ok or not plain(map) or not map then return end
    local x, y = PlayerOn(map)
    if x then return map, x, y end
end

-- écart en mètres entre toi et le point (est, sud)
local function Offset(e)
    if not e.map then return end
    local px, py = PlayerOn(e.map)
    if not px then return end
    local w, h = MapSize(e.map)
    if not w then return end
    return (e.x - px) * w, (e.y - py) * h
end

---------------------------------------------------------------------------
-- Repère dans le monde (celui de Ctrl+clic sur la carte) + minuteur au-dessus
---------------------------------------------------------------------------
local function WPMatches(cur, e)
    if not cur or not cur.position then return false end
    local ok, r = pcall(function()
        return cur.uiMapID == e.map and math.abs(cur.position.x - e.x) < 0.0005 and math.abs(cur.position.y - e.y) < 0.0005
    end)
    return ok and r
end

local function CurrentWP()
    if not (C_Map and C_Map.HasUserWaypoint) then return end
    if not Bool(C_Map.HasUserWaypoint) then return end
    local ok, cur = pcall(C_Map.GetUserWaypoint)
    if ok then return cur end
end

local function ClearWaypoint()
    if not ourWP then return end
    local cur = CurrentWP()
    if cur and WPMatches(cur, ourWP) then
        pcall(C_Map.ClearUserWaypoint)
        if prevQuest and C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID then
            pcall(C_SuperTrack.SetSuperTrackedQuestID, prevQuest)
        end
    end
    ourWP, prevQuest = nil, nil
    if label then label:Hide() end
end

local function SetWaypoint(npc, e, force)
    if DB().respawnWaypoint == false or not e.map then return end
    if not (C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates) then return end
    if C_Map.CanSetUserWaypointOnMap and not Bool(C_Map.CanSetUserWaypointOnMap, e.map) then return end
    local cur = CurrentWP()
    if ourWP and ourWP.npc == npc and cur and WPMatches(cur, ourWP) then return end
    -- ton propre repère passe avant, sauf si tu cliques toi-même sur le monstre
    if cur and not (ourWP and WPMatches(cur, ourWP)) and not force then return end
    if not ourWP and C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID then
        local ok, q = pcall(C_SuperTrack.GetSuperTrackedQuestID)
        prevQuest = ok and plain(q) and q and q > 0 and q or nil
    end
    local ok = pcall(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(e.map, e.x, e.y))
    if not ok then return end
    if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true) end
    ourWP = { npc = npc, map = e.map, x = e.x, y = e.y }
end

local function BuildLabel()
    label = CreateFrame("Frame", nil, UIParent)
    label:SetSize(1, 1)
    label:SetFrameStrata("HIGH")
    label.name = label:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label.name:SetPoint("BOTTOM", label, "CENTER", 0, 2)
    label.time = label:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label.time:SetPoint("TOP", label, "CENTER", 0, 0)
    for _, fs in ipairs({ label.name, label.time }) do fs:SetShadowColor(0, 0, 0, 1); fs:SetShadowOffset(1, -1) end
    label:Hide()
end

---------------------------------------------------------------------------
-- Texte d'état d'un chrono
---------------------------------------------------------------------------
local function State(npc, e, now)
    local lo, avg, hi, n = Stats(npc, e)
    local el = now - e.t
    local st = { elapsed = el, n = n, lo = lo, avg = avg, hi = hi }
    if e.alive then
        st.text, st.r, st.g, st.b, st.pct = "vivant", 0.5, 0.86, 0.42, 1
    elseif not avg then
        st.text, st.r, st.g, st.b, st.pct = "?", 0.79, 0.73, 0.54, 0
        st.long = "temps inconnu : appris à son retour"
    elseif el < avg then
        st.left = avg - el
        st.text, st.r, st.g, st.b, st.pct = Clock(st.left), 1, 1, 1, el / avg
        st.long = "revient dans " .. Clock(st.left)
    elseif el < hi then
        st.text, st.r, st.g, st.b, st.pct = "bientôt", 1, 0.82, 0, 1
        st.long = "bientôt (au plus tard " .. Clock(hi - el) .. ")"
    else
        st.text, st.r, st.g, st.b, st.pct = "attendu", 1, 0.82, 0, 1
        st.long = "devrait déjà être là"
    end
    st.long = st.long or st.text
    return st
end

local function Sub(npc, e, st)
    if e.alive then
        if st.n then return ("rapide %s · moyen %s · lent %s (%d relevé%s)"):format(Clock(st.lo), Clock(st.avg), Clock(st.hi), st.n, st.n > 1 and "s" or "") end
        return "réapparu"
    end
    local s = "mort il y a " .. Clock(st.elapsed)
    if not st.n then return s .. " · en apprentissage…" end
    return s .. (e.zone and (" · " .. e.zone) or "")
end

---------------------------------------------------------------------------
-- Fenêtre
---------------------------------------------------------------------------
local Refresh

local function SortedActive()
    local list, now = {}, Now()
    for npc, e in pairs(data.active) do
        local st = State(npc, e, now)
        list[#list + 1] = { npc = npc, e = e, st = st, key = e.alive and 1e9 + e.alive or (st.left or (st.avg and 0) or 5e8 - (now - e.t)) }
    end
    table.sort(list, function(a, b) return a.key < b.key end)
    return list
end

local function RowTooltip(row)
    GameTooltip:SetOwner(row, "ANCHOR_LEFT")
    GameTooltip:AddLine(row.nm or "Respawn", 1, 0.82, 0)
    if row.e then
        local st = State(row.npc, row.e, Now())
        GameTooltip:AddLine(st.long, st.r, st.g, st.b)
        GameTooltip:AddLine(Sub(row.npc, row.e, st), 0.7, 0.7, 0.7)
    end
    local lo, avg, hi, n = Stats(row.npc, row.e)
    if n then GameTooltip:AddLine(("Rapide %s · moyen %s · lent %s"):format(Clock(lo), Clock(avg), Clock(hi)), 1, 1, 1) end
    GameTooltip:AddLine("Clic gauche : repère et flèche vers l'endroit", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("Clic droit : retirer ce chrono", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("Maj + clic droit : oublier ce monstre", 0.8, 0.8, 0.8)
    GameTooltip:Show()
end

local function MakeRow(i)
    local r = CreateFrame("Button", nil, win)
    r:SetSize(WIN_W - PAD * 2, ROW_H - 1)
    r:SetPoint("TOPLEFT", win, "TOPLEFT", PAD, -32 - (i - 1) * ROW_H)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r:RegisterForDrag("LeftButton")
    r:SetScript("OnDragStart", function() local f = win:GetScript("OnDragStart"); if f then f(win) end end)
    r:SetScript("OnDragStop", function() local f = win:GetScript("OnDragStop"); if f then f(win) end end)
    r.slot = CreateFrame("Frame", nil, r)
    r.slot:SetSize(15, 15)
    r.slot:SetPoint("TOPLEFT", 0, -1)
    r.edge = r.slot:CreateTexture(nil, "BACKGROUND")
    r.edge:SetPoint("TOPLEFT", -1, 1); r.edge:SetPoint("BOTTOMRIGHT", 1, -1)
    r.edge:SetColorTexture(0.55, 0.43, 0.18, 1)
    r.icon = r.slot:CreateTexture(nil, "ARTWORK")
    r.icon:SetAllPoints()
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    r.state = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.state:SetPoint("TOPRIGHT", 0, -3)
    r.state:SetJustifyH("RIGHT")
    r.name = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    r.name:SetPoint("TOPLEFT", r.slot, "TOPRIGHT", 5, -2)
    r.name:SetPoint("RIGHT", r.state, "LEFT", -6, 0)
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
    r.bg = r:CreateTexture(nil, "ARTWORK")
    r.bg:SetPoint("BOTTOMLEFT", r.slot, "BOTTOMRIGHT", 5, -2); r.bg:SetPoint("BOTTOMRIGHT", 0, 1); r.bg:SetHeight(3)
    r.bg:SetColorTexture(0.23, 0.19, 0.12, 0.9)
    r.bar = CreateFrame("StatusBar", nil, r)
    r.bar:SetPoint("TOPLEFT", r.bg); r.bar:SetPoint("BOTTOMRIGHT", r.bg)
    r.bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    r.bar:SetMinMaxValues(0, 1)
    r.hl = r:CreateTexture(nil, "HIGHLIGHT")
    r.hl:SetAllPoints(); r.hl:SetColorTexture(1, 0.82, 0, 0.07)
    r:SetScript("OnEnter", RowTooltip)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    r:SetScript("OnClick", function(self, btn)
        if not self.npc then return end
        local e = data.active[self.npc]
        if btn == "LeftButton" then
            if e and e.map then
                SetWaypoint(self.npc, e, true)
                if NZR.CompassPointTo then pcall(NZR.CompassPointTo, e.map, e.x, e.y, self.nm, "Respawn") end
            else
                NZR:Print("pas de position pour ce monstre (en donjon, ou carte inconnue).")
            end
        elseif IsShiftKeyDown() then
            local id = e and e.npc or self.npc
            for k, x in pairs(data.active) do if (x.npc or k) == id then data.active[k] = nil end end
            data.npcs[id] = nil
            data.watch[id] = nil
            if data.spots then for k in pairs(data.spots) do if k:match("^(%-?%d+):") == tostring(id) then data.spots[k] = nil end end end
            if ourWP and not data.active[ourWP.npc] then ClearWaypoint() end
            NZR:Print((self.nm or "monstre") .. " oublié.")
        else
            data.active[self.npc] = nil
            if ourWP and ourWP.npc == self.npc then ClearWaypoint() end
        end
        Refresh()
    end)
    rows[i] = r
    return r
end

local function TargetInList()
    if not UnitExists("target") then return end
    local npc = UnitNPC("target")
    if not npc then return end
    if data.watch[npc] then return npc end
    for _, e in pairs(data.active) do if e.npc == npc then return npc end end
end

local function RemoveTarget(npc)
    data.watch[npc] = nil
    data.ignore[npc] = true
    for k, e in pairs(data.active) do if e.npc == npc then data.active[k] = nil end end
    if ourWP and not data.active[ourWP.npc] then ClearWaypoint() end
    local nm = (data.npcs[npc] and data.npcs[npc].n) or SafeName("target") or "monstre"
    NZR:Print(nm .. " retiré de la liste Respawn.")
end

local function AddTarget()
    if not UnitExists("target") then NZR:Print("cible d'abord le monstre à suivre.") return end
    local npc = UnitNPC("target")
    if not npc then NZR:Print("ce n'est pas un monstre que NZR peut suivre.") return end
    local nm = SafeName("target") or ("#" .. npc)
    data.npcs[npc] = data.npcs[npc] or { s = {} }
    data.npcs[npc].n = nm
    if data.watch[npc] then
        data.watch[npc] = nil
        NZR:Print(nm .. " n'est plus suivi.")
    else
        data.watch[npc] = true; data.ignore[npc] = nil
        NZR:Print(nm .. " suivi : quand tu le verras mourir, le chrono démarre.")
    end
end

-- icône (comme celle du guide) quand la fenêtre est réduite ou qu'aucun monstre n'est suivi
local launcher
local forceOpen      -- tu as rouvert la fenêtre à la main (même vide)
local function BuildLauncher()
    local b = CreateFrame("Button", "NZRF_RespawnButton", UIParent)
    b:SetSize(30, 30)
    b:SetFrameStrata("MEDIUM")
    b:SetClampedToScreen(true); b:SetMovable(true)
    if b.SetDontSavePosition then b:SetDontSavePosition(true) end
    b:RegisterForDrag("LeftButton")
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local ic = b:CreateTexture(nil, "ARTWORK")
    ic:SetPoint("TOPLEFT", 4, -4); ic:SetPoint("BOTTOMRIGHT", -4, 4)
    ic:SetTexture("Interface\\Icons\\INV_Misc_PocketWatch_01")
    ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local ring = b:CreateTexture(nil, "OVERLAY")
    ring:SetAllPoints(); ring:SetTexture("Interface\\AddOns\\NZRForever\\Media\\uf\\ring_square")
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetPoint("TOPLEFT", 4, -4); hl:SetPoint("BOTTOMRIGHT", -4, 4); hl:SetColorTexture(1, 0.82, 0, 0.25)
    b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    b.count:SetPoint("BOTTOMRIGHT", -3, 3)
    local p = NZRF_DB.pos.respawnIcon
    if p then b:SetPoint(p[1], UIParent, p[2], p[3], p[4]) else b:SetPoint("TOPRIGHT", holder, "TOPRIGHT", 0, 0) end
    b:SetScript("OnDragStart", function(self) self:StartMoving() end)
    b:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local l, t = self:GetLeft(), self:GetTop()
        if l and t then
            self:ClearAllPoints()
            self:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l, t)
            NZRF_DB.pos.respawnIcon = { "TOPLEFT", "BOTTOMLEFT", l, t }
        end
    end)
    b:SetScript("OnClick", function(_, btn)
        if btn == "RightButton" then NZR:ToggleOptions(true) return end
        userHidden, forceOpen = nil, true
        pcall(Refresh)
    end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Respawn")
        GameTooltip:AddLine("Clic : ouvrir la fenêtre des temps de respawn.", 1, 1, 1, true)
        GameTooltip:AddLine("Clic droit : réglages NZR Forever. Glisser : déplacer.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:Hide()
    launcher = b
end

local function BuildWindow()
    holder = NZR:Holder("respawn", "Respawn", WIN_W, 70, { "TOPRIGHT", "TOPRIGHT", -230, -260 })
    win = CreateFrame("Frame", "NZRF_Respawn", UIParent)
    win:SetSize(WIN_W, 50)
    win:SetFrameStrata("MEDIUM")
    -- la fenêtre suit le bloc « Respawn » (mode édition) mais reste accrochée à l'écran,
    -- pour pouvoir aussi la glisser directement à la souris
    local function Anchor()
        local l, t = holder:GetLeft(), holder:GetTop()
        if not (l and t) then win:ClearAllPoints(); win:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0) return end
        local k = UIParent:GetEffectiveScale() / win:GetEffectiveScale()
        win:ClearAllPoints()
        win:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l * k, t * k)
    end
    win.Anchor = Anchor
    win:SetMovable(true)
    if win.SetDontSavePosition then win:SetDontSavePosition(true) end
    win:SetClampedToScreen(true)
    win:EnableMouse(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", function(self) self:StartMoving() end)
    win:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if self.SetUserPlaced then pcall(self.SetUserPlaced, self, false) end
        local k = self:GetEffectiveScale() / UIParent:GetEffectiveScale()
        local l, t = self:GetLeft(), self:GetTop()
        if l and t then
            holder:ClearAllPoints()
            holder:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l * k, t * k)
            NZRF_DB.pos[holder.key] = { "TOPLEFT", "BOTTOMLEFT", l * k, t * k }
        end
        Anchor()
    end)
    Anchor()
    local over, ttl = NZR:WowFrame(win, "Respawn", DB().meterAlpha or 0.95, 0.9)
    if ttl then ttl:SetFontObject("GameFontNormal") end        -- titre lisible
    local add = CreateFrame("Button", nil, over)
    add:SetSize(16, 16)
    add:SetPoint("TOPLEFT", over, "TOPLEFT", 12, -3)    -- dans le bandeau du titre (cadre à 90 %)           -- même hauteur que le titre
    add:SetNormalTexture("Interface\\Buttons\\UI-PlusButton-Up")
    add:SetPushedTexture("Interface\\Buttons\\UI-PlusButton-Down")
    add:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight", "ADD")
    -- « + » : suivre ta cible ; devient une croix si ta cible est déjà dans la liste
    function add:Sync()
        local inList = TargetInList()
        if inList == self.state then return end
        self.state = inList
        if inList then
            self:SetNormalTexture("Interface\\Buttons\\UI-StopButton")
            self:SetPushedTexture("Interface\\Buttons\\UI-StopButton")
        else
            self:SetNormalTexture("Interface\\Buttons\\UI-PlusButton-Up")
            self:SetPushedTexture("Interface\\Buttons\\UI-PlusButton-Down")
        end
    end
    add.state = false
    add:SetScript("OnClick", function(self)
        local npc = TargetInList()
        if npc then RemoveTarget(npc) else AddTarget() end
        self:Sync(); pcall(Refresh)
    end)
    add:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        if TargetInList() then
            GameTooltip:AddLine("Retirer ma cible", 1, 0.82, 0)
            GameTooltip:AddLine("Ce monstre ne sera plus suivi et ses chronos disparaissent.", 1, 1, 1, true)
        else
            GameTooltip:AddLine("Suivre ma cible", 1, 0.82, 0)
            GameTooltip:AddLine("Ajoute le monstre ciblé à la liste. Aussi : /nzr respawn", 1, 1, 1, true)
        end
        GameTooltip:Show()
    end)
    win.add = add
    add:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- petit trait « – » : réduire la fenêtre en icône
    local mini = CreateFrame("Button", nil, over)
    mini:SetSize(16, 16)
    mini:SetPoint("TOPRIGHT", over, "TOPRIGHT", -12, -3)
    mini:SetNormalTexture("Interface\\Buttons\\UI-MinusButton-Up")
    mini:SetPushedTexture("Interface\\Buttons\\UI-MinusButton-Down")
    mini:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight", "ADD")
    mini:SetScript("OnClick", function() userHidden, forceOpen = true, nil; pcall(Refresh) end)
    mini:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Réduire en icône", 1, 0.82, 0)
        GameTooltip:Show()
    end)
    mini:SetScript("OnLeave", function() GameTooltip:Hide() end)
    win.more = over:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    win.empty = over:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    win.empty:SetPoint("TOP", 0, -40)
    win.empty:SetWidth(WIN_W - PAD * 2); win.empty:SetJustifyH("CENTER")
    win.empty:SetText("Aucun chrono en cours")
    win.hint = over:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    win.hint:SetPoint("BOTTOM", 0, 12)
    win.hint:SetWidth(WIN_W - PAD * 2); win.hint:SetJustifyH("CENTER"); win.hint:SetWordWrap(true)
    win.hint:SetText("Clic : flèche · Clic droit : retirer")
    win:Hide()
end

---------------------------------------------------------------------------
-- Minicarte et grande carte
---------------------------------------------------------------------------
local OUT = { [0] = 466 + 2 / 3, 400, 333 + 1 / 3, 266 + 2 / 3, 200, 133 + 1 / 3 }
local IN = { [0] = 300, 240, 180, 120, 80, 50 }
local SKULL = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull"

local function PinTooltip(p)
    if not p.npc then return end
    local e = data.active[p.npc]; if not e then return end
    local st = State(p.npc, e, Now())
    GameTooltip:SetOwner(p, "ANCHOR_RIGHT")
    GameTooltip:AddLine(p.nm or "Respawn", 1, 0.82, 0)
    GameTooltip:AddLine(st.long, st.r, st.g, st.b)
    GameTooltip:AddLine(Sub(p.npc, e, st), 0.7, 0.7, 0.7)
    GameTooltip:Show()
end

local function NewPin(parent, size)
    local p = CreateFrame("Frame", nil, parent)
    p:SetSize(size, size)
    p.icon = p:CreateTexture(nil, "OVERLAY")
    p.icon:SetAllPoints()
    p.icon:SetTexture(SKULL)
    p.text = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    p.text:SetPoint("TOP", p, "BOTTOM", 0, -1)
    p:EnableMouse(true)
    p:SetScript("OnEnter", PinTooltip)
    p:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return p
end

local function UpdateMinimap(list)
    local n = 0
    if DB().respawnMinimap ~= false and Minimap and Minimap:IsShown() then
        local okZ, zoom = pcall(Minimap.GetZoom, Minimap)
        zoom = okZ and zoom or 0
        local okC, cv = pcall(GetCVar, "minimapZoom")
        local indoor = not (okC and tonumber(cv) == zoom)
        local diam = (indoor and IN or OUT)[zoom] or 300
        local half = Minimap:GetWidth() / 2
        local ppy = half / (diam / 2)
        local rotate = GetCVar and GetCVar("rotateMinimap") == "1"
        local facing = rotate and GetPlayerFacing and select(2, pcall(GetPlayerFacing))
        if rotate and not (plain(facing) and type(facing) == "number") then facing = nil end
        local square = GetMinimapShape and GetMinimapShape() == "SQUARE"
        for _, it in ipairs(list) do
            local de, ds = Offset(it.e)
            if de and not it.e.alive then
                local ex, ny = de, -ds
                if facing then
                    local c, s = math.cos(facing), math.sin(facing)
                    ex, ny = ex * c + ny * s, -ex * s + ny * c
                end
                local px, py = ex * ppy, ny * ppy
                local edge = false
                if square then
                    local lim = half - 6
                    if math.abs(px) > lim or math.abs(py) > lim then
                        local k = lim / math.max(math.abs(px), math.abs(py)); px, py = px * k, py * k; edge = true
                    end
                else
                    local d, lim = math.sqrt(px * px + py * py), half - 6
                    if d > lim then px, py = px * lim / d, py * lim / d; edge = true end
                end
                n = n + 1
                local p = mmPins[n] or NewPin(Minimap, 14)
                mmPins[n] = p
                p:SetFrameLevel(Minimap:GetFrameLevel() + 6)
                p:ClearAllPoints()
                p:SetPoint("CENTER", Minimap, "CENTER", px, py)
                p:SetAlpha(edge and 0.6 or 1)
                p.npc, p.nm = it.npc, it.nm
                p.icon:SetVertexColor(1, 0.82, 0)
                p.text:SetText("")
                p:Show()
            end
        end
    end
    for i = n + 1, #mmPins do mmPins[i]:Hide() end
end

local function UpdateWorldMap(list)
    local n = 0
    local wm = WorldMapFrame
    local sc = wm and type(wm.ScrollContainer) == "table" and wm.ScrollContainer
    if DB().respawnMap ~= false and sc and type(sc.Child) == "table" and wm:IsShown() then
        local canvas = sc.Child
        local okM, shown = pcall(wm.GetMapID, wm)
        local okS, cs = pcall(sc.GetCanvasScale, sc)
        cs = (okS and cs and cs > 0) and cs or 1
        local W, H = canvas:GetSize()
        if okM and shown and W and W > 0 then
            for _, it in ipairs(list) do
                local e = it.e
                if e.map == shown and not e.alive then
                    n = n + 1
                    local p = wmPins[n] or NewPin(canvas, 20)
                    wmPins[n] = p
                    p:SetFrameLevel(canvas:GetFrameLevel() + 500)
                    p:SetScale(1 / cs)
                    p:ClearAllPoints()
                    p:SetPoint("CENTER", canvas, "TOPLEFT", e.x * W * cs, -e.y * H * cs)
                    p.npc, p.nm = it.npc, it.nm
                    p.icon:SetVertexColor(1, 0.82, 0)
                    p.text:SetText(it.st.left and Clock(it.st.left) or (it.st.avg and "bientôt" or "?"))
                    p:Show()
                end
            end
        end
    end
    for i = n + 1, #wmPins do wmPins[i]:Hide() end
end

---------------------------------------------------------------------------
-- Boucle (seulement quand un chrono tourne)
---------------------------------------------------------------------------
local function Alert(npc, e)
    local nm = (data.npcs[e.npc or npc] and data.npcs[e.npc or npc].n) or e.n or "Monstre"
    local msg = nm .. " devrait réapparaître !"
    pcall(UIErrorsFrame.AddMessage, UIErrorsFrame, msg, 1, 0.82, 0)
    if DB().respawnSound ~= false then pcall(PlaySound, SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959, "Master") end
end

local function Prune(now)
    for npc, e in pairs(data.active) do
        local _, avg, hi = Stats(npc, e)
        local el = now - e.t
        if e.alive then
            if now - e.alive > KEEP_ALIVE then data.active[npc] = nil end
        elseif e.test and el > 32 then
            data.active[npc] = nil
        elseif (hi and el > hi * 1.5 + 120) or (not hi and el > 1800) then
            data.active[npc] = nil          -- jamais revu : on arrête d'attendre
        elseif avg and el >= avg and not e.warned then
            e.warned = true
            Alert(npc, e)
        end
    end
    for k in pairs(portraits) do if not data.active[k] then DropPortrait(k) end end
    if ourWP and not (data.active[ourWP.npc] and not data.active[ourWP.npc].alive) then ClearWaypoint() end
end

Refresh = function()
    if not data then return end
    local now = Now()
    Prune(now)
    local list = SortedActive()
    for _, it in ipairs(list) do
        local id = it.e.npc or it.npc
        it.nm = (data.npcs[id] and data.npcs[id].n) or it.e.n or ("#" .. tostring(id))
    end

    -- fenêtre
    local editing = NZR.editing
    for _, tex in pairs(portraits) do tex:Hide() end
    -- fenêtre : quand un monstre est suivi (ou rouverte à la main) ; sinon l'icône
    local want = not userHidden and not editing and (#list > 0 or forceOpen)
    if want then
        local shown = math.min(#list, MAX_ROWS)
        for i = 1, shown do
            local it, r = list[i], rows[i] or MakeRow(i)
            r.npc, r.e, r.nm = it.npc, it.e, it.nm
            r.name:SetText(it.nm)
            local por = portraits[it.npc]
            if por then
                por:SetParent(r.slot); por:ClearAllPoints(); por:SetAllPoints(r.slot); por:SetDrawLayer("OVERLAY"); por:Show()
                r.icon:Hide(); r.por = por
            else
                r.icon:SetTexture(TypeIcon(it.e)); r.icon:Show(); r.por = nil
            end
            r.state:SetText(it.st.text)
            r.state:SetTextColor(it.st.r, it.st.g, it.st.b)
            r.bar:SetValue(it.st.pct or 0)
            if it.e.alive then r.bar:SetStatusBarColor(0.3, 0.6, 0.23) else r.bar:SetStatusBarColor(0.78, 0.63, 0.25) end
            r:Show()
        end
        for i = shown + 1, #rows do rows[i]:Hide() end
        local extra = #list - shown
        if #list == 0 then
            win.empty:Show()
            win.hint:SetText("Cible un monstre\npuis clique sur +")
        else
            win.empty:Hide()
            win.hint:SetText("Clic : flèche · Clic droit : retirer")
        end
        if extra > 0 then
            win.more:SetText(("+ %d autre%s"):format(extra, extra > 1 and "s" or ""))
            win.more:SetPoint("TOPLEFT", win, "TOPLEFT", PAD, -34 - shown * ROW_H)
            win.more:Show()
        else
            win.more:Hide()
        end
        local sc = DB().respawnScale or 1
        if win:GetScale() ~= sc then win:SetScale(sc); win.Anchor() end
        -- hauteur minimale : en dessous, le cadre doré du jeu ne dessine plus son bas
        local h = 46 + math.max(shown, 1) * ROW_H + (extra > 0 and 14 or 0)
        win.hint:SetShown(h + 22 <= 118)
        win:SetHeight(math.max(118, h))
        win:Show()
    else
        win:Hide()
    end
    if win.add then pcall(win.add.Sync, win.add) end
    if launcher then
        launcher:SetShown(not want and not editing)
        local n = 0
        for _, it in ipairs(list) do if not it.e.alive then n = n + 1 end end
        launcher.count:SetText(n > 0 and n or "")
    end

    -- repère dans le monde : le prochain à revenir sur ta carte
    if DB().respawnWaypoint ~= false and not ourWP then
        for _, it in ipairs(list) do
            if not it.e.alive and it.e.map and Offset(it.e) then SetWaypoint(it.npc, it.e, false); break end
        end
    end
    if ourWP and label then
        local st = _G.SuperTrackedFrame
        local tracking = C_SuperTrack and C_SuperTrack.IsSuperTrackingUserWaypoint and Bool(C_SuperTrack.IsSuperTrackingUserWaypoint)
        local e = data.active[ourWP.npc]
        if e and st and st:IsShown() and tracking then
            local s = State(ourWP.npc, e, now)
            label:ClearAllPoints()
            label:SetPoint("BOTTOM", st, "TOP", 0, 14)
            label.name:SetText((data.npcs[e.npc or 0] and data.npcs[e.npc or 0].n) or e.n or "")
            label.time:SetText(s.left and Clock(s.left) or (s.avg and "maintenant" or "?"))
            label:Show()
        else
            label:Hide()
        end
    elseif label then
        label:Hide()
    end

    UpdateMinimap(list)
    UpdateWorldMap(list)

    if #list == 0 and ticker then ticker:Cancel(); ticker = nil end
end

local function Wake()
    if not ticker then ticker = C_Timer.NewTicker(0.5, function() pcall(Refresh) end) end
    pcall(Refresh)
end

---------------------------------------------------------------------------
-- Ce qu'on voit : vivant, mort, réapparu
---------------------------------------------------------------------------
local function SeenAlive(unit)
    local npc, guid = UnitNPC(unit)
    if not npc then return end
    if Bool(UnitIsDead, unit) then return end
    if not Bool(UnitCanAttack, "player", unit) then return end
    local t = GetTime()
    aliveGUID[guid] = t
    npcGuids[npc] = npcGuids[npc] or {}
    npcGuids[npc][guid] = t
    if DB().respawnQuest ~= false and questGUID[guid] == nil then questGUID[guid] = UnitIsQuest(unit) end
    -- réapparition d'un monstre qu'on attendait ? (le plus proche de ceux de ce type)
    -- un monstre qui vient de réapparaître : pleine vie et pas en combat
    local okH, hp = pcall(UnitHealth, unit); local okM, mx = pcall(UnitHealthMax, unit)
    local full = okH and okM and plain(hp) and plain(mx) and mx > 0 and hp >= mx
    if not full or Bool(UnitAffectingCombat, unit) then return end
    local near = Near(unit, 4)
    if near == false then return end          -- trop loin de toi pour savoir d'où il vient
    local best, bestK, bestD
    local now = Now()
    for k, e in pairs(data.active) do
        if e.npc == npc and not e.alive and not e.test and guid ~= e.guid and not (e.before and e.before[guid])
           and now - e.t >= (e.common and 30 or 10) then
            local de, ds = Offset(e)
            local d = de and math.sqrt(de * de + ds * ds) or 0
            if d <= (e.common and (near and 20 or 25) or 90) and (not bestD or d < bestD) then best, bestK, bestD = e, k, d end
        end
    end
    if best then
        local el = now - best.t
        local rec = data.npcs[npc] or { s = {} }
        data.npcs[npc] = rec
        rec.n = rec.n or best.n
        -- relevé trop différent de ce qu'on sait déjà (moins de la moitié) : sans doute un autre
        local _, med, _, n = Stats(npc)
        local plausible = not (med and n and n >= 2 and el < med * 0.5)
        if el <= 3600 and plausible then
            AddSpotSample(npc, best, el)
            table.insert(rec.s, el)
            while #rec.s > MAX_SAMPLES do table.remove(rec.s, 1) end
        end
        best.alive = now
        if ourWP and ourWP.npc == bestK then ClearWaypoint() end
        Wake()
    end
end

local function SeenDead(unit)
    local npc, guid = UnitNPC(unit)
    if not npc or not aliveGUID[guid] then return end      -- pas vu vivant : on ne sait pas quand il est mort
    aliveGUID[guid] = nil
    if InInstance() then return end
    local watched, common = IsWatched(unit, npc, guid)
    questGUID[guid] = nil
    if not watched or data.active[guid] then return end
    local map, x, y
    local fp = idlePos[guid] or firstPos[guid]
    if fp then map, x, y = fp[1], fp[2], fp[3] else map, x, y = PlayerSpot() end
    firstPos[guid], idlePos[guid] = nil, nil
    local before = {}
    for g in pairs(npcGuids[npc] or {}) do if g ~= guid then before[g] = true end end
    local nm = SafeName(unit)
    data.npcs[npc] = data.npcs[npc] or { s = {} }
    if nm then data.npcs[npc].n = nm end
    local zone
    if map and C_Map.GetMapInfo then
        local ok, info = pcall(C_Map.GetMapInfo, map)
        zone = ok and info and plain(info.name) and info.name or nil
    end
    local okT, ctype = pcall(UnitCreatureType, unit)
    local okF, fam = pcall(UnitCreatureFamily, unit)
    data.active[guid] = { npc = npc, t = Now(), guid = guid, map = map, x = x, y = y, zone = zone, before = before, n = nm, common = common or nil,
                          ctype = okT and plain(ctype) and ctype or nil, fam = okF and plain(fam) and fam or nil }
    TakePortrait(guid, unit)
    -- pas plus de 40 chronos : on oublie les plus vieux
    local n, oldK, oldT = 0, nil, math.huge
    for k, x in pairs(data.active) do n = n + 1; if x.t < oldT then oldK, oldT = k, x.t end end
    if n > 40 and oldK then data.active[oldK] = nil end
    Wake()
end

-- premier coup entre toi et ce monstre : on note où tu es
local function FirstHit(unit)
    local npc, guid = UnitNPC(unit)
    if not npc or firstPos[guid] or Bool(UnitIsDead, unit) then return end
    local map, x, y = PlayerSpot()
    if map then firstPos[guid] = { map, x, y } end
end

local function Check(unit)
    if Bool(UnitIsDead, unit) then SeenDead(unit) else SeenAlive(unit) end
end

local function Cleanup()
    local t = GetTime()
    for g, v in pairs(aliveGUID) do if t - v > 900 then aliveGUID[g] = nil; questGUID[g] = nil; firstPos[g] = nil; idlePos[g] = nil end end
    for npc, set in pairs(npcGuids) do
        for g, v in pairs(set) do if t - v > 900 then set[g] = nil end end
        if not next(set) then npcGuids[npc] = nil end
    end
end

---------------------------------------------------------------------------
-- Infobulle
---------------------------------------------------------------------------
local function OnTooltip(tt, d)
    if tt ~= GameTooltip or DB().respawnTip == false or not d then return end
    local guid = d.guid
    if not plain(guid) or type(guid) ~= "string" then return end
    local typ, _, _, _, _, npc = strsplit("-", guid)
    if typ ~= "Creature" and typ ~= "Vehicle" then return end
    npc = tonumber(npc)
    if not npc then return end
    local e = data.active[guid]
    if e and not e.alive then
        local st = State(npc, e, Now())
        tt:AddLine("|TInterface\\TargetingFrame\\UI-TargetingFrame-Skull:12|t Respawn : " .. st.long, 0.78, 0.63, 0.25)
        return
    end
    local _, avg, _, n = Stats(npc)
    if avg then
        tt:AddLine(("Respawn ≈ %s (%d relevé%s)"):format(Clock(avg), n, n > 1 and "s" or ""), 0.78, 0.63, 0.25)
    elseif data.watch[npc] then
        tt:AddLine("Respawn : suivi, temps pas encore connu", 0.6, 0.55, 0.4)
    end
end

---------------------------------------------------------------------------
-- Commandes et essai
---------------------------------------------------------------------------
function NZR.RespawnTest()
    if not data then NZR:Print("active « Temps de respawn » (Quêtes), puis recharge.") return end
    local map, x, y = PlayerSpot()
    data.active.test = { npc = -1, t = Now(), guid = "test", map = map, x = x, y = y, n = "Essai de respawn", test = { 15, 20, 25 } }
    userHidden = nil
    if map then SetWaypoint("test", data.active.test, true) end
    NZR:Print("essai : un faux monstre « revient » dans 20 s, ici même." .. (map and "" or " (pas de position ici : pas de repère)"))
    Wake()
end

function NZR.RespawnCmd(arg)
    if not data then NZR:Print("active « Temps de respawn » dans /nzr > Quêtes, puis recharge.") return end
    arg = arg or ""
    if arg == "test" or arg == "essai" then NZR.RespawnTest()
    elseif arg == "oublie" or arg == "reset" then
        ClearWaypoint()
        wipe(data.active); wipe(data.npcs); wipe(data.watch); wipe(data.ignore); data.spots = {}
        NZR:Print("temps de respawn oubliés.")
        Refresh()
    elseif arg == "voir" or arg == "show" then
        userHidden, forceOpen = nil, true; Wake()
    else
        AddTarget()
    end
end

function NZR.RespawnForget()
    if NZR.RespawnCmd then NZR.RespawnCmd("oublie") end
end

---------------------------------------------------------------------------
function M:Init()
    if not DB().respawn then return end
    Ensure()
    -- les essais d'une session précédente ne restent pas
    data.active[-1] = nil; data.active.test = nil
    -- anciennes sauvegardes : un chrono par numéro de monstre
    for k, e in pairs(data.active) do
        if type(k) == "number" then data.active[k] = nil; if e.guid then e.npc = k; data.active[e.guid] = e end end
    end
    BuildWindow()
    BuildLauncher()
    BuildLabel()

    local ev = CreateFrame("Frame")
    ev:RegisterEvent("UNIT_HEALTH")
    ev:RegisterEvent("UNIT_COMBAT")
    ev:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    ev:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
    ev:RegisterEvent("PLAYER_TARGET_CHANGED")
    ev:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:SetScript("OnEvent", function(_, e, unit)
        if e == "UNIT_COMBAT" then
            if unit == "target" or (unit and unit:sub(1, 9) == "nameplate") then pcall(FirstHit, unit) end
        elseif e == "UNIT_HEALTH" then
            if unit == "target" or (unit and unit:sub(1, 9) == "nameplate") then
                if Bool(UnitIsDead, unit) then pcall(SeenDead, unit) end
            end
        elseif e == "NAME_PLATE_UNIT_ADDED" or e == "NAME_PLATE_UNIT_REMOVED" then
            pcall(Check, unit)
        elseif e == "PLAYER_TARGET_CHANGED" then
            if UnitExists("target") then pcall(SeenAlive, "target") end
            if win and win.add then pcall(win.add.Sync, win.add) end
        elseif e == "UPDATE_MOUSEOVER_UNIT" then
            pcall(SeenAlive, "mouseover")
        elseif e == "PLAYER_ENTERING_WORLD" then
            if next(data.active) then Wake() end
        end
    end)
    C_Timer.NewTicker(60, Cleanup)
    -- toutes les secondes : monstres tranquilles tout près de toi (point d'apparition)
    -- et réapparitions dans ton entourage
    C_Timer.NewTicker(1, function()
        if InInstance() then return end
        for i = 1, 40 do
            local u = "nameplate" .. i
            if UnitExists(u) and not Bool(UnitIsDead, u) then
                local npc, guid = UnitNPC(u)
                if npc and not Bool(UnitAffectingCombat, u) then
                    if not idlePos[guid] and Near(u, 3) then
                        local map, x, y = PlayerSpot()
                        if map then idlePos[guid] = { map, x, y } end
                    end
                    if next(data.active) then pcall(SeenAlive, u) end
                end
            end
        end
    end)

    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        pcall(TooltipDataProcessor.AddTooltipPostCall, Enum.TooltipDataType.Unit, function(tt, d) pcall(OnTooltip, tt, d) end)
    end
    if WorldMapFrame then
        WorldMapFrame:HookScript("OnShow", function() if next(data.active) then Wake() end end)
    end
    table.insert(NZR.editHooks, function(on) if not on and win then pcall(win.Anchor) end; pcall(Refresh) end)
    C_Timer.After(1, function() pcall(Refresh) end)
    if next(data.active) then Wake() end
end
