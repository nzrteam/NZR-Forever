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
local WIN_W, ROW_H = 200, 19

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

-- suivi ? renvoie aussi si c'est un monstre « courant » (plusieurs du même nom autour)
local function IsWatched(unit, npc, guid)
    if data.watch[npc] then return true, false end
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
local function Stats(npc, e)
    if e and e.npc then npc = e.npc end
    local s = (e and e.test) or (data.npcs[npc] and data.npcs[npc].s)
    if not s or #s == 0 then return end
    local lo, hi, sum = math.huge, 0, 0
    for _, v in ipairs(s) do lo = math.min(lo, v); hi = math.max(hi, v); sum = sum + v end
    return lo, sum / #s, hi, #s
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
    r:SetSize(WIN_W - 24, ROW_H - 1)
    r:SetPoint("TOPLEFT", win, "TOPLEFT", 12, -30 - (i - 1) * ROW_H)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r.state = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.state:SetPoint("TOPRIGHT", 0, -2)
    r.state:SetJustifyH("RIGHT")
    r.name = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    r.name:SetPoint("TOPLEFT", 0, -2)
    r.name:SetPoint("RIGHT", r.state, "LEFT", -6, 0)
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
    r.bg = r:CreateTexture(nil, "ARTWORK")
    r.bg:SetPoint("BOTTOMLEFT", 0, 1); r.bg:SetPoint("BOTTOMRIGHT", 0, 1); r.bg:SetHeight(3)
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
        data.watch[npc] = true
        NZR:Print(nm .. " suivi : quand tu le verras mourir, le chrono démarre.")
    end
end

local function BuildWindow()
    holder = NZR:Holder("respawn", "Respawn", WIN_W, 70, { "TOPRIGHT", "TOPRIGHT", -230, -260 })
    win = CreateFrame("Frame", "NZRF_Respawn", UIParent)
    win:SetSize(WIN_W, 50)
    win:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
    win:SetFrameStrata("MEDIUM")
    -- se déplace directement à la souris (titre ou fond), sans passer par le mode édition
    win:SetMovable(true)
    win:SetClampedToScreen(true)
    win:EnableMouse(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", function(self) if not InCombatLockdown() or not self:IsProtected() then self:StartMoving() end end)
    win:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local sc = self:GetEffectiveScale() / UIParent:GetEffectiveScale()
        local l, t = self:GetLeft(), self:GetTop()
        if l and t then
            holder:ClearAllPoints()
            holder:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l * sc, t * sc)
            NZRF_DB.pos[holder.key] = { "TOPLEFT", "BOTTOMLEFT", l * sc, t * sc }
        end
        self:ClearAllPoints()
        self:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
    end)
    local over = NZR:WowFrame(win, "Respawn", DB().meterAlpha or 0.95)
    local add = CreateFrame("Button", nil, over)
    add:SetSize(18, 18)
    add:SetPoint("TOPLEFT", 6, -2)
    add:SetNormalTexture("Interface\\Buttons\\UI-PlusButton-Up")
    add:SetPushedTexture("Interface\\Buttons\\UI-PlusButton-Down")
    add:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight", "ADD")
    add:SetScript("OnClick", AddTarget)
    add:SetScript("OnEnter", function(s)
        GameTooltip:SetOwner(s, "ANCHOR_LEFT")
        GameTooltip:AddLine("Suivre ma cible", 1, 0.82, 0)
        GameTooltip:AddLine("Ajoute (ou retire) le monstre ciblé. Aussi : /nzr respawn", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    add:SetScript("OnLeave", function() GameTooltip:Hide() end)
    local close = CreateFrame("Button", nil, over, "UIPanelCloseButton")
    close:SetSize(22, 22)
    close:SetPoint("TOPRIGHT", 1, 0)
    close:SetScript("OnClick", function() userHidden = true; win:Hide() end)
    win.more = over:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
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
    local want = #list > 0 and not userHidden and not editing
    if want then
        local shown = math.min(#list, MAX_ROWS)
        for i = 1, shown do
            local it, r = list[i], rows[i] or MakeRow(i)
            r.npc, r.e, r.nm = it.npc, it.e, it.nm
            r.name:SetText(it.nm)
            r.state:SetText(it.st.text)
            r.state:SetTextColor(it.st.r, it.st.g, it.st.b)
            r.bar:SetValue(it.st.pct or 0)
            if it.e.alive then r.bar:SetStatusBarColor(0.3, 0.6, 0.23) else r.bar:SetStatusBarColor(0.78, 0.63, 0.25) end
            r:Show()
        end
        for i = shown + 1, #rows do rows[i]:Hide() end
        local extra = #list - shown
        if extra > 0 then
            win.more:SetText(("+ %d autre%s"):format(extra, extra > 1 and "s" or ""))
            win.more:SetPoint("TOPLEFT", win, "TOPLEFT", 12, -32 - shown * ROW_H)
            win.more:Show()
        else
            win.more:Hide()
        end
        win:SetScale(DB().respawnScale or 1)
        win:SetHeight(math.max(66, 44 + shown * ROW_H + (extra > 0 and 14 or 0)))
        win:Show()
    else
        win:Hide()
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
    local best, bestK, bestD
    local now = Now()
    for k, e in pairs(data.active) do
        if e.npc == npc and not e.alive and not e.test and guid ~= e.guid and not (e.before and e.before[guid])
           and now - e.t >= (e.common and 25 or 10) then
            local de, ds = Offset(e)
            local d = de and math.sqrt(de * de + ds * ds) or 0
            if d <= (e.common and 40 or 90) and (not bestD or d < bestD) then best, bestK, bestD = e, k, d end
        end
    end
    if best then
        local el = now - best.t
        local rec = data.npcs[npc] or { s = {} }
        data.npcs[npc] = rec
        rec.n = rec.n or best.n
        if el <= 3600 then
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
    local map, x, y = PlayerSpot()
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
    data.active[guid] = { npc = npc, t = Now(), guid = guid, map = map, x = x, y = y, zone = zone, before = before, n = nm, common = common or nil }
    -- pas plus de 40 chronos : on oublie les plus vieux
    local n, oldK, oldT = 0, nil, math.huge
    for k, x in pairs(data.active) do n = n + 1; if x.t < oldT then oldK, oldT = k, x.t end end
    if n > 40 and oldK then data.active[oldK] = nil end
    userHidden = nil
    Wake()
end

local function Check(unit)
    if Bool(UnitIsDead, unit) then SeenDead(unit) else SeenAlive(unit) end
end

local function Cleanup()
    local t = GetTime()
    for g, v in pairs(aliveGUID) do if t - v > 900 then aliveGUID[g] = nil; questGUID[g] = nil end end
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
        wipe(data.active); wipe(data.npcs); wipe(data.watch)
        NZR:Print("temps de respawn oubliés.")
        Refresh()
    elseif arg == "voir" or arg == "show" then
        userHidden = nil; Wake()
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
    BuildLabel()

    local ev = CreateFrame("Frame")
    ev:RegisterEvent("UNIT_HEALTH")
    ev:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    ev:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
    ev:RegisterEvent("PLAYER_TARGET_CHANGED")
    ev:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:SetScript("OnEvent", function(_, e, unit)
        if e == "UNIT_HEALTH" then
            if unit == "target" or (unit and unit:sub(1, 9) == "nameplate") then
                if Bool(UnitIsDead, unit) then pcall(SeenDead, unit) end
            end
        elseif e == "NAME_PLATE_UNIT_ADDED" or e == "NAME_PLATE_UNIT_REMOVED" then
            pcall(Check, unit)
        elseif e == "PLAYER_TARGET_CHANGED" then
            if UnitExists("target") then pcall(SeenAlive, "target") end
        elseif e == "UPDATE_MOUSEOVER_UNIT" then
            pcall(SeenAlive, "mouseover")
        elseif e == "PLAYER_ENTERING_WORLD" then
            if next(data.active) then Wake() end
        end
    end)
    C_Timer.NewTicker(60, Cleanup)

    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        pcall(TooltipDataProcessor.AddTooltipPostCall, Enum.TooltipDataType.Unit, function(tt, d) pcall(OnTooltip, tt, d) end)
    end
    if WorldMapFrame then
        WorldMapFrame:HookScript("OnShow", function() if next(data.active) then Wake() end end)
    end
    table.insert(NZR.editHooks, function() pcall(Refresh) end)
    if next(data.active) then Wake() end
end
