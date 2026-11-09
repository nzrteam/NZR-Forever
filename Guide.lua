-- NZR Forever - Guide de progression (facultatif, désactivé par défaut)
-- Petite icône discrète -> fenêtre du jeu avec le build à suivre selon ton niveau :
-- les talents à prendre, ceux déjà pris, et le prochain point à mettre.
local _, NZR = ...
local M = NZR:Module("Guide")
local plain = NZR.plain

local function DB() return NZR.db end
local ROWS, COLS, CELL, ICON = 7, 4, 44, 34
local W, H = 660, 640

local data            -- NZR.GuideData[classe]
local win, btn

---------------------------------------------------------------------------
-- Calcul du build (mêmes règles que le calculateur)
---------------------------------------------------------------------------
local function Decode(code)
    local ranks = {}
    local parts = {}
    for s in ((code or "") .. "-"):gmatch("([^-]*)-") do parts[#parts + 1] = s end
    for ti, tree in ipairs(data.trees) do
        ranks[ti] = {}
        local s = parts[ti] or ""
        for i, t in ipairs(tree.talents) do
            local idx = (t.r - 1) * COLS + t.c
            ranks[ti][i] = math.min(tonumber(s:sub(idx, idx)) or 0, t.max)
        end
    end
    return ranks
end

local function ReqIndex(ti, t)
    if not t.req then return nil end
    for j, x in ipairs(data.trees[ti].talents) do if x.n == t.req then return j end end
end

-- un talent en ligne N demande 5 x (N - 1) points plus haut dans l'arbre, et son prérequis au max
local function Valid(r)
    for ti, tree in ipairs(data.trees) do
        for i, t in ipairs(tree.talents) do
            if r[ti][i] > 0 then
                local below = 0
                for j, x in ipairs(tree.talents) do if x.r < t.r then below = below + r[ti][j] end end
                if below < (t.r - 1) * 5 then return false end
                local q = ReqIndex(ti, t)
                if q and r[ti][q] < tree.talents[q].max then return false end
            end
        end
    end
    return true
end

local function Spent(r)
    local s = 0
    for _, tr in ipairs(r) do for _, v in ipairs(tr) do s = s + v end end
    return s
end

-- le build à un niveau donné : on retire les talents les plus bas d'abord
local function AtLevel(full, level)
    local r = {}
    for ti, tr in ipairs(full) do r[ti] = {}; for i, v in ipairs(tr) do r[ti][i] = v end end
    local budget = math.max(0, math.min(51, level - 9))
    local guard = 0
    while Spent(r) > budget and guard < 200 do
        guard = guard + 1
        local order = {}
        for ti, tree in ipairs(data.trees) do
            for i, t in ipairs(tree.talents) do
                if r[ti][i] > 0 then order[#order + 1] = { ti = ti, i = i, row = t.r } end
            end
        end
        -- même ordre que le calculateur : ligne la plus basse d'abord, puis l'ordre des arbres et des talents
        table.sort(order, function(a, b)
            if a.row ~= b.row then return a.row > b.row end
            if a.ti ~= b.ti then return a.ti < b.ti end
            return a.i < b.i
        end)
        local hit
        for _, o in ipairs(order) do
            r[o.ti][o.i] = r[o.ti][o.i] - 1
            if Valid(r) then hit = o; break end
            r[o.ti][o.i] = r[o.ti][o.i] + 1
        end
        if not hit then break end
    end
    return r
end

---------------------------------------------------------------------------
-- Tes talents actuels (si le jeu les donne)
---------------------------------------------------------------------------
local function CurrentRanks()
    if not (GetNumTalentTabs and GetTalentInfo and GetNumTalents) then return nil end
    local byName = {}
    local okT, tabs = pcall(GetNumTalentTabs)
    if not okT or not plain(tabs) or tabs < 1 then return nil end
    for tab = 1, tabs do
        local okN, n = pcall(GetNumTalents, tab)
        if okN and plain(n) then
            for i = 1, n do
                local ok, name, _, _, _, rank = pcall(GetTalentInfo, tab, i)
                if ok and plain(name) and name then byName[name] = { rank = rank or 0, tab = tab, idx = i } end
            end
        end
    end
    local cur, found = {}, false
    for ti, tree in ipairs(data.trees) do
        cur[ti] = {}
        for i, t in ipairs(tree.talents) do
            local g = byName[t.n]
            cur[ti][i] = g and g.rank or 0
            if g then found = true; t.gTab, t.gIdx = g.tab, g.idx end
        end
    end
    return found and cur or nil
end

local function Unspent()
    if UnitCharacterPoints then
        local ok, n = pcall(UnitCharacterPoints, "player")
        if ok and plain(n) then return n end
    end
    if GetUnspentTalentPoints then
        local ok, n = pcall(GetUnspentTalentPoints)
        if ok and plain(n) then return n end
    end
end

---------------------------------------------------------------------------
-- Choix du build et du niveau
---------------------------------------------------------------------------
local function PlayerLevel()
    local l = UnitLevel("player")
    return plain(l) and l or 60
end

local function ShownLevel()
    if DB().guideAuto ~= false then return PlayerLevel() end
    return DB().guideLevel or PlayerLevel()
end

local function BuildIndex()
    local id = DB().guideBuild
    if id == "ret" or not id then
        -- Vindicte : 10-30 puis 31-60 selon le niveau affiché
        return ShownLevel() <= 30 and 1 or 2
    end
    for i, b in ipairs(data.builds) do if b.id == id then return i end end
    return 1
end

---------------------------------------------------------------------------
-- Fenêtre
---------------------------------------------------------------------------
local cells = {}       -- [ti][i] = bouton

local function Tab(parent, text, x)
    local ok, t = pcall(CreateFrame, "Button", nil, parent, "PanelTopTabButtonTemplate")
    if not ok or not t then ok, t = pcall(CreateFrame, "Button", nil, parent, "PanelTabButtonTemplate") end
    if not ok or not t then t = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate"); t:SetSize(150, 22) end
    t:SetText(text)
    if PanelTemplates_TabResize then pcall(PanelTemplates_TabResize, t, 12) end
    t:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -26)
    return t
end

local function SelectTab(t, on)
    if on then
        if PanelTemplates_SelectTab then pcall(PanelTemplates_SelectTab, t) end
    else
        if PanelTemplates_DeselectTab then pcall(PanelTemplates_DeselectTab, t) end
    end
end

local Refresh

local function MakeCell(parent, ti, i, t)
    local c = CreateFrame("Button", nil, parent)
    c:SetSize(ICON, ICON)
    c:SetPoint("TOPLEFT", parent, "TOPLEFT", 14 + (t.c - 1) * CELL, -34 - (t.r - 1) * CELL)
    c.icon = c:CreateTexture(nil, "ARTWORK")
    c.icon:SetPoint("TOPLEFT", 2, -2); c.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    c.icon:SetTexture("Interface\\Icons\\" .. t.icon)
    c.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    c.edge = c:CreateTexture(nil, "BACKGROUND")
    c.edge:SetAllPoints(); c.edge:SetColorTexture(0, 0, 0, 1)
    c.glow = c:CreateTexture(nil, "OVERLAY")
    c.glow:SetPoint("TOPLEFT", -3, 3); c.glow:SetPoint("BOTTOMRIGHT", 3, -3)
    c.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    c.glow:SetBlendMode("ADD")
    c.glow:SetTexCoord(0.2, 0.8, 0.2, 0.8)
    c.glow:Hide()
    local bb = CreateFrame("Frame", nil, c)
    bb:SetSize(28, 13); bb:SetPoint("BOTTOMRIGHT", 6, -5)
    bb:SetFrameLevel(c:GetFrameLevel() + 3)
    local bbg = bb:CreateTexture(nil, "BACKGROUND"); bbg:SetAllPoints(); bbg:SetColorTexture(0, 0, 0, 0.85)
    c.badge = bb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    c.badge:SetPoint("CENTER", 0, 0)
    c.badgeBox = bb
    c.ti, c.i, c.t = ti, i, t
    c:SetScript("OnEnter", function(s)
        GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
        local shown = false
        if s.t.gTab and GameTooltip.SetTalent then
            shown = pcall(GameTooltip.SetTalent, GameTooltip, s.t.gTab, s.t.gIdx)
        end
        if not shown then
            GameTooltip:AddLine(s.t.n, 1, 0.82, 0)
            GameTooltip:AddLine(("Rang maximum : %d"):format(s.t.max), 1, 1, 1)
        end
        GameTooltip:AddLine(" ")
        if (s.target or 0) > 0 then
            GameTooltip:AddLine(("Build : %d / %d à ce niveau"):format(s.target, s.t.max), 0.4, 1, 0.4)
        else
            GameTooltip:AddLine("Pas dans le build à ce niveau", 0.6, 0.6, 0.6)
        end
        if s.cur then GameTooltip:AddLine(("Tu as : %d / %d"):format(s.cur, s.t.max), 1, 1, 1) end
        if s.t.req then GameTooltip:AddLine("Demande : " .. s.t.req, 0.8, 0.8, 0.8) end
        GameTooltip:Show()
    end)
    c:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return c
end

local function BuildTree(parent, ti, tree, x)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(COLS * CELL + 20, 34 + ROWS * CELL + 4)
    f:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -140)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(0, 0, 0, 0.35)
    local edge = f:CreateTexture(nil, "BACKGROUND", nil, -1)
    edge:SetPoint("TOPLEFT", -1, 1); edge:SetPoint("BOTTOMRIGHT", 1, -1); edge:SetColorTexture(0.45, 0.36, 0.18, 0.7)
    local ic = f:CreateTexture(nil, "ARTWORK")
    ic:SetSize(20, 20); ic:SetPoint("TOPLEFT", 8, -6)
    ic:SetTexture("Interface\\Icons\\" .. tree.icon); ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("LEFT", ic, "RIGHT", 6, 0)
    f.title:SetText(tree.name)
    f.pts = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.pts:SetPoint("TOPRIGHT", -10, -9)
    cells[ti] = {}
    for i, t in ipairs(tree.talents) do cells[ti][i] = MakeCell(f, ti, i, t) end
    -- traits de prérequis
    f.lines = {}
    for i, t in ipairs(tree.talents) do
        local q = ReqIndex(ti, t)
        if q then
            local a, b = tree.talents[q], t
            local ln = f:CreateTexture(nil, "BORDER")
            if a.c == b.c then
                ln:SetWidth(3)
                ln:SetPoint("TOP", cells[ti][q], "BOTTOM", 0, 0)
                ln:SetPoint("BOTTOM", cells[ti][i], "TOP", 0, 0)
            else
                ln:SetHeight(3)
                ln:SetPoint("LEFT", cells[ti][q], "RIGHT", 0, 0)
                ln:SetPoint("RIGHT", cells[ti][i], "LEFT", 0, 0)
            end
            f.lines[#f.lines + 1] = { tex = ln, i = i }
        end
    end
    return f
end

---------------------------------------------------------------------------
-- Onglet Leveling : feuille de route par niveau, zone mise en avant, flèche vers la zone
---------------------------------------------------------------------------
local ROW_H = 24
local mapCache

local function Norm(s)
    s = (s or ""):lower()
    local map = { ["é"] = "e", ["è"] = "e", ["ê"] = "e", ["ë"] = "e", ["à"] = "a", ["â"] = "a", ["î"] = "i", ["ï"] = "i",
                  ["ô"] = "o", ["û"] = "u", ["ù"] = "u", ["ç"] = "c", ["É"] = "e", ["Â"] = "a" }
    for k, v in pairs(map) do s = s:gsub(k, v) end
    return (s:gsub("[^%w]", ""))
end

local function FindMap(name)
    if not (C_Map and C_Map.GetMapChildrenInfo) then return nil end
    if not mapCache then
        mapCache = {}
        for _, root in ipairs({ 947, 946, 1414, 1415, 12, 13 }) do
            local ok, list = pcall(C_Map.GetMapChildrenInfo, root, nil, true)
            if ok and type(list) == "table" then
                for _, m in ipairs(list) do
                    local key = Norm(m.name)
                    -- on garde la vraie zone (type 3) plutôt qu'un sous-lieu du même nom
                    if key ~= "" and (not mapCache[key] or m.mapType == 3) then mapCache[key] = m.mapID end
                end
            end
        end
    end
    local key = Norm(name)
    if mapCache[key] then return mapCache[key] end
    for k, id in pairs(mapCache) do
        if k:find(key, 1, true) or key:find(k, 1, true) and #k > 5 then return id end
    end
end

local function ValidMap(id)
    if not id or not (C_Map and C_Map.GetMapInfo) then return nil end
    local ok, info = pcall(C_Map.GetMapInfo, id)
    return ok and info and id or nil
end

local function PointTo(name, fallbackId, alias)
    local id = FindMap(name)
    if not id and alias then for _, a in ipairs(alias) do id = id or FindMap(a) end end
    id = id or ValidMap(fallbackId)
    if not id then NZR:Print(("« %s » introuvable sur la carte de ce client."):format(name)); return end
    if NZR.CompassPointTo then
        NZR.CompassPointTo(id, 0.5, 0.5, name, "Guide de leveling")
        NZR:Print(("flèche vers %s."):format(name))
    elseif TomTom and TomTom.AddWaypoint then
        pcall(TomTom.AddWaypoint, TomTom, id, 0.5, 0.5, { title = name })
        NZR:Print(("flèche vers %s."):format(name))
    elseif C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates then
        pcall(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(id, 0.5, 0.5))
        if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true) end
        NZR:Print(("repère posé sur %s (carte du monde)."):format(name))
    end
end

local function RouteFor()
    local faction = UnitFactionGroup("player")
    local f = faction == "Horde" and "H" or "A"
    local _, race = UnitRace("player")
    local out = {}
    for _, e in ipairs(NZR.GuideData.ROUTE or {}) do
        if not e.f or e.f == f then
            local name, id = e[3], e.id
            if e.start then
                local s = (NZR.GuideData.START or {})[race]
                if s then name, id = s[1], s[2] end
            end
            out[#out + 1] = { min = e[1], max = e[2], name = name, d = e.d, zone = e.zone, zid = e.zid,
                id = id, alias = e.alias, start = e.start, rec = e.rec, new = e.new, known = not e.start or id ~= nil }
        end
    end
    return out
end

local function BuildLeveling(pg)
    local lv = {}
    win.lv = lv
    lv.head = pg:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lv.head:SetPoint("TOPLEFT", 18, -62)
    lv.sub = pg:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lv.sub:SetPoint("TOPLEFT", lv.head, "BOTTOMLEFT", 0, -4)
    lv.sub:SetPoint("RIGHT", pg, "RIGHT", -18, 0); lv.sub:SetJustifyH("LEFT")

    local box = CreateFrame("Frame", nil, pg)
    box:SetPoint("TOPLEFT", 14, -100); box:SetPoint("BOTTOMRIGHT", -14, 34)
    local bg = box:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0, 0, 0, 0.35)
    local edge = box:CreateTexture(nil, "BACKGROUND", nil, -1)
    edge:SetPoint("TOPLEFT", -1, 1); edge:SetPoint("BOTTOMRIGHT", 1, -1); edge:SetColorTexture(0.45, 0.36, 0.18, 0.7)
    local scroll = CreateFrame("ScrollFrame", "NZRF_GuideRoute", box, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 4, -4); scroll:SetPoint("BOTTOMRIGHT", -26, 4)
    local list = CreateFrame("Frame", nil, scroll)
    list:SetSize(W - 70, 10)
    scroll:SetScrollChild(list)
    lv.scroll, lv.list, lv.rows = scroll, list, {}

    local note = pg:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    note:SetPoint("BOTTOMLEFT", 16, 12); note:SetPoint("RIGHT", pg, "RIGHT", -16, 0); note:SetJustifyH("LEFT")
    note:SetText("Repères de niveau généraux ; le pas à pas quête par quête reste le travail de RestedXP et Questie.")
end

local function LevelRow(i)
    local lv = win.lv
    if lv.rows[i] then return lv.rows[i] end
    local r = CreateFrame("Frame", nil, lv.list)
    r:SetHeight(ROW_H)
    r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H); r:SetPoint("RIGHT", lv.list, "RIGHT", 0, 0)
    r.bg = r:CreateTexture(nil, "BACKGROUND"); r.bg:SetAllPoints()
    r.range = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    r.range:SetPoint("LEFT", 8, 0); r.range:SetWidth(54); r.range:SetJustifyH("LEFT")
    r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(16, 16); r.icon:SetPoint("LEFT", 62, 0)
    r.name = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    r.name:SetPoint("LEFT", r.icon, "RIGHT", 6, 0); r.name:SetJustifyH("LEFT")
    r.where = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    r.where:SetPoint("LEFT", r.name, "RIGHT", 8, 0)
    r.go = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
    r.go:SetSize(70, 20); r.go:SetPoint("RIGHT", -6, 0); r.go:SetText("Flèche")
    r.go:SetScript("OnClick", function(s) PointTo(s.target, s.targetId, s.alias) end)
    r.tag = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    r.tag:SetPoint("RIGHT", r.go, "LEFT", -10, 0)
    lv.rows[i] = r
    return r
end

local function CreateWindow()
    win = CreateFrame("Frame", "NZRF_Guide", UIParent)
    win:SetSize(W, H)
    win:SetPoint("CENTER")
    win:SetFrameStrata("HIGH")
    win:SetToplevel(true)
    win:SetMovable(true); win:EnableMouse(true); win:SetClampedToScreen(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", win.StopMovingOrSizing)
    local root = NZR:WowFrame(win, "Guide de progression", 0.97)
    win.over = root
    local close = CreateFrame("Button", nil, root, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 1)
    close:SetScript("OnClick", function() win:Hide() end)
    tinsert(UISpecialFrames, "NZRF_Guide")

    -- deux onglets : Talents / Leveling
    win.pages, win.pageTabs = {}, {}
    local x = 12
    for i, name in ipairs({ "Talents", "Leveling" }) do
        local pg = CreateFrame("Frame", nil, root)
        pg:SetAllPoints(); pg:Hide()
        win.pages[i] = pg
        local t = Tab(root, name, x)
        t:SetScript("OnClick", function() DB().guidePage = i; PlaySound(841); Refresh() end)
        win.pageTabs[i] = t
        x = x + (t:GetWidth() or 120) + 4
    end
    BuildLeveling(win.pages[2])
    local over = win.pages[1]

    if not data then
        local msg = over:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        msg:SetPoint("CENTER")
        msg:SetText("Pas encore de build pour ta classe (Paladin pour l'instant).\nL'onglet Leveling marche pour toutes les classes.")
        return
    end

    -- choix du build
    win.tabs = {}
    local bx = 14
    for i, b in ipairs(data.builds) do
        local t = CreateFrame("Button", nil, over, "UIPanelButtonTemplate")
        t:SetSize(140, 22)
        t:SetPoint("TOPLEFT", bx, -60)
        t:SetText(b.name)
        t:SetScript("OnClick", function()
            DB().guideBuild = b.id
            PlaySound(841); Refresh()
        end)
        win.tabs[i] = t
        bx = bx + 144
    end

    -- ligne d'info
    win.role = over:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    win.role:SetPoint("TOPLEFT", 18, -90)
    win.info = over:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    win.info:SetPoint("TOPLEFT", win.role, "BOTTOMLEFT", 0, -4)
    win.next = over:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    win.next:SetPoint("TOPLEFT", win.info, "BOTTOMLEFT", 0, -4)
    win.next:SetTextColor(0.35, 1, 0.35)

    -- niveau : auto (le tien) ou choisi
    local auto = CreateFrame("CheckButton", nil, over, "UICheckButtonTemplate")
    auto:SetSize(24, 24)
    auto:SetPoint("TOPRIGHT", -150, -86)
    auto.label = over:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    auto.label:SetPoint("LEFT", auto, "RIGHT", 2, 0)
    auto.label:SetText("Mon niveau")
    auto:SetScript("OnClick", function(s)
        DB().guideAuto = s:GetChecked() and true or false
        if not DB().guideAuto then DB().guideLevel = PlayerLevel() end
        Refresh()
    end)
    win.auto = auto
    local function arrow(dir)
        local b = CreateFrame("Button", nil, over)
        b:SetSize(24, 24)
        local base = dir < 0 and "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-" or "Interface\\Buttons\\UI-SpellbookIcon-NextPage-"
        b:SetNormalTexture(base .. "Up"); b:SetPushedTexture(base .. "Down"); b:SetDisabledTexture(base .. "Disabled")
        b:SetScript("OnClick", function()
            DB().guideAuto = false
            DB().guideLevel = math.max(10, math.min(60, ShownLevel() + dir))
            Refresh()
        end)
        return b
    end
    local prev, nextB = arrow(-1), arrow(1)
    prev:SetPoint("TOPRIGHT", -96, -108)
    win.lvl = over:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    win.lvl:SetPoint("LEFT", prev, "RIGHT", 2, 0); win.lvl:SetWidth(40)
    nextB:SetPoint("LEFT", win.lvl, "RIGHT", 2, 0)
    local lt = over:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lt:SetPoint("RIGHT", prev, "LEFT", -2, 0); lt:SetText("Niveau")

    -- les trois arbres
    win.trees = {}
    local tw = COLS * CELL + 20
    local gap = math.floor((W - 3 * tw) / 4)
    for ti, tree in ipairs(data.trees) do
        win.trees[ti] = BuildTree(over, ti, tree, gap + (ti - 1) * (tw + gap))
    end

    -- conseil du build, caractéristiques, source
    win.tip = over:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    win.tip:SetPoint("TOPLEFT", 18, -140 - (34 + ROWS * CELL + 4) - 12)
    win.tip:SetPoint("RIGHT", over, "RIGHT", -18, 0)
    win.tip:SetJustifyH("LEFT"); win.tip:SetSpacing(2)
    win.stats = over:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    win.stats:SetPoint("TOPLEFT", win.tip, "BOTTOMLEFT", 0, -8)
    win.stats:SetPoint("RIGHT", over, "RIGHT", -18, 0)
    win.stats:SetJustifyH("LEFT"); win.stats:SetSpacing(2)
    win.stats:SetText("|cffffd100Caractéristiques :|r " .. (data.stats or ""))
    local src = over:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    src:SetPoint("BOTTOMRIGHT", -14, 10)
    src:SetText("Builds : conquestcapped.com · arbres : wowforevertools")
end

local RefreshLeveling
Refresh = function()
    if not win or not win:IsShown() then return end
    local page = DB().guidePage or 1
    for i, pg in ipairs(win.pages) do pg:SetShown(i == page); SelectTab(win.pageTabs[i], i == page) end
    if page == 2 then RefreshLeveling(); return end
    if not data then return end
    local bi = BuildIndex()
    local build = data.builds[bi]
    for i, t in ipairs(win.tabs) do
        if i == bi then t:LockHighlight(); t:SetAlpha(1) else t:UnlockHighlight(); t:SetAlpha(0.75) end
    end
    local level = ShownLevel()
    win.auto:SetChecked(DB().guideAuto ~= false)
    win.lvl:SetText(level)

    local target = AtLevel(Decode(build.code), level)
    local cur = CurrentRanks()
    local per = {}
    for ti, tree in ipairs(data.trees) do
        local s = 0
        for i, t in ipairs(tree.talents) do
            local c = cells[ti][i]
            local want, have = target[ti][i], cur and cur[ti][i]
            s = s + want
            c.target, c.cur = want, have
            c.glow:Hide()
            if want == 0 and not (have and have > 0) then
                c.icon:SetDesaturated(true); c.icon:SetAlpha(0.35)
                c.edge:SetColorTexture(0, 0, 0, 1)
                c.badge:SetText(""); c.badgeBox:Hide()
            else
                c.icon:SetDesaturated(false); c.icon:SetAlpha(1)
                c.badgeBox:Show()
                if have and have < want then
                    -- à prendre
                    c.edge:SetColorTexture(0.2, 0.9, 0.2, 1)
                    c.glow:SetVertexColor(0.3, 1, 0.3); c.glow:Show()
                    c.badge:SetText(("|cff55ff55%d/%d|r"):format(have, want))
                else
                    c.edge:SetColorTexture(1, 0.82, 0, 1)
                    c.badge:SetText(("|cffffd100%d/%d|r"):format(want, t.max))
                end
            end
        end
        for _, ln in ipairs(win.trees[ti].lines) do
            if target[ti][ln.i] > 0 then ln.tex:SetColorTexture(1, 0.82, 0, 0.9)
            else ln.tex:SetColorTexture(0.4, 0.4, 0.4, 0.6) end
        end
        per[ti] = s
        win.trees[ti].pts:SetText(s)
    end

    win.role:SetText(("%s  |cffaaaaaa· %s|r"):format(build.name, build.role or ""))
    local total = per[1] + per[2] + per[3]
    win.info:SetText(("Niveau %d : %d points  (%s %d / %s %d / %s %d)"):format(level, total,
        data.trees[1].name, per[1], data.trees[2].name, per[2], data.trees[3].name, per[3]))

    -- prochain point à mettre (le plus haut dans l'arbre d'abord)
    local nextTxt
    if cur then
        for row = 1, ROWS do
            for ti, tree in ipairs(data.trees) do
                for i, t in ipairs(tree.talents) do
                    if not nextTxt and t.r == row and cur[ti][i] < target[ti][i] then
                        nextTxt = ("Prochain point : %s (%s, rang %d)"):format(t.n, tree.name, cur[ti][i] + 1)
                    end
                end
            end
        end
        local un = Unspent()
        if nextTxt then
            if un and un > 0 then nextTxt = nextTxt .. ("  |cffffd100— %d point(s) à dépenser|r"):format(un) end
        else
            nextTxt = "|cffffd100Tu suis le build à ce niveau.|r"
        end
    else
        nextTxt = "|cffaaaaaaTes talents actuels ne sont pas lisibles ici : suis les cases dorées.|r"
    end
    win.next:SetText(nextTxt)
    win.tip:SetText("|cffffd100Conseil :|r " .. (build.tip or ""))
end

RefreshLeveling = function()
    local lv = win.lv
    local level = PlayerLevel()
    local route = RouteFor()
    local here = GetZoneText and GetZoneText() or ""
    local firstCur, hereInfo
    for i, e in ipairs(route) do
        local r = LevelRow(i)
        r:Show()
        r.range:SetText(e.min == e.max and tostring(e.min) or (e.min .. "-" .. e.max))
        r.name:SetText(e.name)
        r.icon:SetTexture(e.d and "Interface\\Minimap\\Dungeon" or "Interface\\Icons\\INV_Misc_Map_01")
        if not e.d then r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) else r.icon:SetTexCoord(0, 1, 0, 1) end
        r.where:SetText(e.d and ("Donjon · " .. (e.zone or "")) or "")
        r.go.target = e.d and e.zone or e.name
        r.go.targetId = e.d and e.zid or e.id
        r.go.alias = not e.d and e.alias or nil
        r.go:SetShown(e.known)
        local tags = {}
        if e.new then tags[#tags + 1] = "|cff4fc3ffNouveau|r" end
        if e.rec then tags[#tags + 1] = "|cffffd100Conseillé|r" elseif not e.d and not e.start then tags[#tags + 1] = "|cff999999Alternative|r" end
        r.tag:SetText(table.concat(tags, "  "))
        local cur = level >= e.min and level <= e.max
        local past = level > e.max
        if cur then
            r.bg:SetColorTexture(1, 0.82, 0, 0.16)
            r.name:SetTextColor(1, 0.82, 0); r.range:SetTextColor(1, 1, 1)
            firstCur = firstCur or i
        elseif past then
            r.bg:SetColorTexture(0, 0, 0, 0)
            r.name:SetTextColor(0.5, 0.5, 0.5); r.range:SetTextColor(0.5, 0.5, 0.5)
        else
            r.bg:SetColorTexture(1, 1, 1, (i % 2 == 0) and 0.03 or 0)
            r.name:SetTextColor(0.9, 0.9, 0.9); r.range:SetTextColor(0.8, 0.8, 0.8)
        end
        if Norm(e.name) == Norm(here) and not e.d then hereInfo = e end
    end
    for i = #route + 1, #lv.rows do lv.rows[i]:Hide() end
    lv.list:SetHeight(#route * ROW_H + 4)

    lv.head:SetText(("Niveau %d · %s"):format(level, UnitFactionGroup("player") == "Horde" and "Horde" or "Alliance"))
    local sub
    if hereInfo then
        if level < hereInfo.min then sub = ("Tu es en %s (%d-%d) : un peu tôt, attention."):format(here, hereInfo.min, hereInfo.max)
        elseif level > hereInfo.max then sub = ("Tu es en %s (%d-%d) : tu peux passer à la suite, en doré."):format(here, hereInfo.min, hereInfo.max)
        else sub = ("Tu es en %s (%d-%d) : bonne zone pour ton niveau."):format(here, hereInfo.min, hereInfo.max) end
    else
        sub = "En doré : les zones et donjons faits pour ton niveau. « Flèche » pointe vers la zone."
    end
    lv.sub:SetText(sub)
    if firstCur and not lv.scrolled then
        lv.scrolled = true
        local y = math.max(0, (firstCur - 3) * ROW_H)
        C_Timer.After(0, function() pcall(lv.scroll.SetVerticalScroll, lv.scroll, y) end)
    end
end

function NZR.GuideToggle()
    if not win then CreateWindow() end
    if win:IsShown() then win:Hide() else win:Show(); Refresh() end
end

---------------------------------------------------------------------------
-- Petite icône (livre doré), à glisser où tu veux
---------------------------------------------------------------------------
local function CreateButton()
    btn = CreateFrame("Button", "NZRF_GuideButton", UIParent)
    btn:SetSize(30, 30)
    btn:SetFrameStrata("MEDIUM")
    btn:SetClampedToScreen(true); btn:SetMovable(true)
    btn:RegisterForDrag("LeftButton")
    local ic = btn:CreateTexture(nil, "ARTWORK")
    ic:SetPoint("TOPLEFT", 4, -4); ic:SetPoint("BOTTOMRIGHT", -4, 4)
    ic:SetTexture("Interface\\Icons\\INV_Misc_Book_11")
    ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local ring = btn:CreateTexture(nil, "OVERLAY")
    ring:SetAllPoints(); ring:SetTexture("Interface\\AddOns\\NZRForever\\Media\\uf\\ring_square")
    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetPoint("TOPLEFT", 4, -4); hl:SetPoint("BOTTOMRIGHT", -4, 4); hl:SetColorTexture(1, 0.82, 0, 0.25)
    local p = DB().guideBtnPos
    if p then btn:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    elseif Minimap then btn:SetPoint("TOPRIGHT", Minimap, "BOTTOMLEFT", -2, -2)
    else btn:SetPoint("TOPRIGHT", -220, -230) end
    btn:SetScript("OnDragStart", btn.StartMoving)
    btn:SetScript("OnDragStop", function(s)
        s:StopMovingOrSizing()
        local a, _, r, x, y = s:GetPoint()
        DB().guideBtnPos = { a, r, x, y }
    end)
    btn:SetScript("OnClick", function() NZR.GuideToggle() end)
    btn:SetScript("OnEnter", function(s)
        GameTooltip:SetOwner(s, "ANCHOR_LEFT")
        GameTooltip:AddLine("Guide de progression")
        GameTooltip:AddLine("Talents à suivre et zones de leveling selon ton niveau. Glisser : déplacer.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

function M:Init()
    if NZR.withUI or not DB().guide then return end
    local _, cls = UnitClass("player")
    data = NZR.GuideData and plain(cls) and NZR.GuideData[cls] or nil
    CreateButton()
    local ev = CreateFrame("Frame")
    for _, e in ipairs({ "PLAYER_LEVEL_UP", "CHARACTER_POINTS_CHANGED", "PLAYER_TALENT_UPDATE",
                         "SPELLS_CHANGED", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA" }) do pcall(ev.RegisterEvent, ev, e) end
    ev:SetScript("OnEvent", function() C_Timer.After(0.2, function() pcall(Refresh) end) end)
end

-- pour les tests hors jeu
NZR.GuideInternals = { Decode = Decode, AtLevel = AtLevel, Valid = Valid, Spent = Spent,
    SetData = function(d) data = d end }
