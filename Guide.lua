-- NZR Forever - Guide de progression (facultatif, désactivé par défaut)
-- Petite icône discrète -> fenêtre du jeu avec le build à suivre selon ton niveau :
-- les talents à prendre, ceux déjà pris, et le prochain point à mettre.
local _, NZR = ...
local M = NZR:Module("Guide")
local plain = NZR.plain

local function DB() return NZR.db end
local ROWS, COLS, CELL, ICON = 7, 4, 44, 34
local W, H = 660, 610

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
        table.sort(order, function(a, b)
            if a.row ~= b.row then return a.row > b.row end
            if a.ti ~= b.ti then return a.ti > b.ti end
            return a.i > b.i
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
    f:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -112)
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
    local over = NZR:WowFrame(win, "Guide de progression", 0.97)
    win.over = over
    local close = CreateFrame("Button", nil, over, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 1)
    close:SetScript("OnClick", function() win:Hide() end)
    tinsert(UISpecialFrames, "NZRF_Guide")

    if not data then
        local msg = over:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        msg:SetPoint("CENTER")
        msg:SetText("Pas encore de guide pour ta classe.\nPour l'instant : Paladin.")
        win:SetSize(360, 140)
        return
    end

    -- onglets des builds
    win.tabs = {}
    local x = 12
    for i, b in ipairs(data.builds) do
        local t = Tab(over, b.name, x)
        t:SetScript("OnClick", function()
            DB().guideBuild = b.id
            PlaySound(841); Refresh()
        end)
        win.tabs[i] = t
        x = x + (t:GetWidth() or 150) + 4
    end

    -- ligne d'info
    win.role = over:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    win.role:SetPoint("TOPLEFT", 18, -62)
    win.info = over:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    win.info:SetPoint("TOPLEFT", win.role, "BOTTOMLEFT", 0, -4)
    win.next = over:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    win.next:SetPoint("TOPLEFT", win.info, "BOTTOMLEFT", 0, -4)
    win.next:SetTextColor(0.35, 1, 0.35)

    -- niveau : auto (le tien) ou choisi
    local auto = CreateFrame("CheckButton", nil, over, "UICheckButtonTemplate")
    auto:SetSize(24, 24)
    auto:SetPoint("TOPRIGHT", -150, -58)
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
    prev:SetPoint("TOPRIGHT", -96, -82)
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
    win.tip:SetPoint("TOPLEFT", 18, -112 - (34 + ROWS * CELL + 4) - 12)
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

Refresh = function()
    if not win or not data or not win:IsShown() then return end
    local bi = BuildIndex()
    local build = data.builds[bi]
    for i, t in ipairs(win.tabs) do
        local on = (i == bi)
        SelectTab(t, on)
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
        GameTooltip:AddLine("Le build à suivre selon ton niveau. Glisser : déplacer.", 1, 1, 1, true)
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
                         "SPELLS_CHANGED", "PLAYER_ENTERING_WORLD" }) do pcall(ev.RegisterEvent, ev, e) end
    ev:SetScript("OnEvent", function() C_Timer.After(0.2, function() pcall(Refresh) end) end)
end

-- pour les tests hors jeu
NZR.GuideInternals = { Decode = Decode, AtLevel = AtLevel, Valid = Valid, Spent = Spent,
    SetData = function(d) data = d end }
