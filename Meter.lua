-- NZR Forever - DPS meter (style Meterion) : vue Tableau (colonnes au choix) et vue Barres
-- Source : le compteur intégré de Blizzard (C_DamageMeter), seule source autorisée
-- sur WoW Forever. En combat les chiffres peuvent être "secrets" : on les affiche
-- sans calcul. La vue Tableau doit rassembler plusieurs listes par joueur ; si le
-- jeu cache les noms/identifiants, elle bascule d'elle-même sur la vue Barres.
-- Tous les réglages (colonnes, tri, taille, couleurs…) s'appliquent en direct.
local _, NZR = ...
local M = NZR:Module("Meter")
local C = NZR.C
-- palette propre au meter : « noir » (sobre, translucide) ou « violet » (NZR)
local MA, MA2 = C.accent, C.accent2
local P = {}
local function SetupPalette()
    local th = NZR.db.meterTheme or "jeu"
    local noir = th == "noir" or th == "jeu"
    P.noir, P.jeu = noir, th == "jeu"
    if P.jeu then
        -- « Jeu » : bord et fond des infobulles de WoW, touches dorées, police du jeu
        MA, MA2 = { 1, 0.82, 0 }, { 1, 0.92, 0.55 }
        P.win, P.winEdge = { 0.03, 0.03, 0.05 }, { 0, 0, 0, 0 }
        P.card, P.cardEdge, P.meEdge = { 1, 1, 1, 0.03 }, { 1, 1, 1, 0.06 }, { 1, 0.82, 0, 0.45 }
        P.sep = { 1, 1, 1, 0.07 }
        P.tag, P.tagEdge = { 0, 0, 0, 0.5 }, { 1, 0.82, 0, 0.6 }
        P.meTint = 0.05
    elseif noir then
        MA, MA2 = { 0.78, 0.78, 0.82 }, { 1, 1, 1 }
        P.win, P.winEdge = { 0, 0, 0 }, { 1, 1, 1, 0.07 }
        P.card, P.cardEdge, P.meEdge = { 1, 1, 1, 0.035 }, { 1, 1, 1, 0.06 }, { 1, 1, 1, 0.22 }
        P.sep = { 1, 1, 1, 0.06 }
        P.tag, P.tagEdge = { 1, 1, 1, 0.1 }, { 1, 1, 1, 0.14 }
        P.meTint = 0.06
    else
        MA, MA2 = C.accent, C.accent2
        P.win, P.winEdge = { 0.07, 0.066, 0.094 }, { 0.17, 0.157, 0.21, 1 }
        P.card, P.cardEdge = { 0.114, 0.106, 0.145, 0.96 }, { 0.16, 0.15, 0.22, 1 }
        P.meEdge = { C.accent[1] * 0.75, C.accent[2] * 0.75, C.accent[3] * 0.75, 1 }
        P.sep = { 0.114, 0.098, 0.149, 1 }
        P.tag, P.tagEdge = { C.accent[1], C.accent[2], C.accent[3], 1 }, { C.accent2[1], C.accent2[2], C.accent2[3], 0.6 }
        P.meTint = 0.14
    end
end
local issecret, plain = NZR.issecret, NZR.plain

local MEDIA = "Interface\\AddOns\\NZRForever\\Media\\"
local HEADER_H, SUB_H, FOOTER_H = 32, 24, 26
local BAR_ROW_H = 22
local ROW_SIZES = { compact = 24, normal = 30, large = 36 }

-- vue Barres : un classement à la fois
local MODES = {
    { key = "DamageDone",  tab = "Dégâts", label = "Dégâts infligés", ps = true },
    { key = "Dps",         tab = "DPS",    label = "Dégâts par seconde", main = "ps" },
    { key = "HealingDone", tab = "Soins",  label = "Soins prodigués", ps = true },
    { key = "Hps",         tab = "HPS",    label = "Soins par seconde", main = "ps" },
    { key = "Absorbs",     tab = "Abs.",   label = "Absorptions" },
    { key = "DamageTaken", tab = "Subis",  label = "Dégâts subis", ps = true },
    { key = "Interrupts",  tab = "Int.",   label = "Interruptions" },
    { key = "Dispels",     tab = "Disp.",  label = "Dissipations" },
}

-- vue Tableau : toutes les colonnes possibles (affichées selon les réglages)
local COLUMNS = {
    { id = "dps",   type = "DamageDone",  field = "amountPerSecond", label = "DPS",    long = "Dégâts par seconde", icon = "sword",  w = 62, big = true },
    { id = "dmg",   type = "DamageDone",  field = "totalAmount",     label = "Dégâts", long = "Dégâts infligés",    icon = "bolt",   w = 64 },
    { id = "heal",  type = "HealingDone", field = "totalAmount",     label = "Soins",  long = "Soins prodigués",    icon = "heart",  w = 58, color = { 0.50, 0.85, 0.56 }, text = { 0.61, 0.89, 0.66 } },
    { id = "hps",   type = "HealingDone", field = "amountPerSecond", label = "HPS",    long = "Soins par seconde",  icon = "heart",  w = 54, color = { 0.50, 0.85, 0.56 }, text = { 0.61, 0.89, 0.66 } },
    { id = "abs",   type = "Absorbs",     field = "totalAmount",     label = "Abs.",   long = "Absorptions",        icon = "shield", w = 54, color = { 0.55, 0.75, 1.00 } },
    { id = "taken", type = "DamageTaken", field = "totalAmount",     label = "Subis",  long = "Dégâts subis",       icon = "shield", w = 58, color = { 0.91, 0.60, 0.42 } },
    { id = "int",   type = "Interrupts",  field = "totalAmount",     label = "Int.",   long = "Interruptions",      icon = "hand",   w = 42 },
    { id = "disp",  type = "Dispels",     field = "totalAmount",     label = "Disp.",  long = "Dissipations",       icon = "cross",  w = 46 },
    { id = "death", type = "Deaths",      field = "totalAmount",     label = "Morts",  long = "Morts",              icon = "skull",  w = 46, dead = true },
}
NZR.METER_COLUMNS = COLUMNS

local MODE_COL = { DamageDone = "dmg", Dps = "dps", HealingDone = "heal", Hps = "hps",
                   Absorbs = "abs", DamageTaken = "taken", Interrupts = "int", Dispels = "disp" }

local DEFAULT_COLS = { dps = true, dmg = true, heal = true, taken = true, int = true, death = true }

local win
local modes, cols, visible = {}, {}, {}
local barRows, tabRows = {}, {}
local lastCombat = 0

local function DM() return C_DamageMeter end

-- vrai seulement si la valeur est vraiment absente (une valeur secrète n'est jamais "absente")
local function isnil(v)
    if issecret(v) then return false end
    return v == nil
end
local function DB() return NZR.db end
local function Table() return DB().meterView ~= "bars" end
local function RowH() return ROW_SIZES[DB().meterRowSize or "normal"] or 30 end

local function ModeShown(i)
    local m = modes[i]
    if not m then return false end
    local id = MODE_COL[m.key]
    local chosen = DB().meterCols or {}
    local any = false
    for _, v in pairs(chosen) do if v then any = true break end end
    return (not any) or (id and chosen[id]) and true or false
end

local function CurrentMode()
    local i = DB().meterMode
    if not ModeShown(i) then
        for j = 1, #modes do if ModeShown(j) then i = j break end end
        DB().meterMode = i
    end
    return modes[i]
end

local function Session(typeKey)
    local dm = DM()
    if not dm or not dm.GetCombatSessionFromType or not Enum.DamageMeterSessionType then return nil end
    local t = Enum.DamageMeterType and Enum.DamageMeterType[typeKey]
    if t == nil then return nil end
    local stype = DB().meterOverall and Enum.DamageMeterSessionType.Overall or Enum.DamageMeterSessionType.Current
    local ok, s = pcall(dm.GetCombatSessionFromType, stype, t)
    if ok then return s end
end

local function Sources(s)
    local list = s and s.combatSources
    return (type(list) == "table") and list or nil
end

-- clé pour regrouper un joueur entre les listes (dégâts, soins, subis…).
-- Forever peut garder noms et identifiants cachés : on se rabat sur "c'est moi",
-- puis sur "seul dans la liste" (solo).
local function KeyOf(src, single)
    local g, n = src.sourceGUID, src.name
    if plain(g) then return g end
    if plain(n) then return n end
    local me = src.isLocalPlayer
    if plain(me) and me == true then return "@player" end
    if single then return "@solo" end
    return nil
end

local function ClassColor(src)
    local cls = src.classFilename
    local cc = plain(cls) and (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[cls]
    if cc then return cc.r, cc.g, cc.b end
    return MA[1], MA[2], MA[3]
end

local function BarColor(src)
    if DB().meterBarColor == "accent" then return MA[1], MA[2], MA[3] end
    return ClassColor(src)
end

local function SetSourceIcon(tex, src)
    if not DB().meterIcons then tex:Hide() return end
    local shown = false
    if not isnil(src.specIconID) then shown = pcall(tex.SetTexture, tex, src.specIconID) end
    local cls = src.classFilename
    if not shown and plain(cls) then shown = pcall(tex.SetAtlas, tex, "classicon-" .. strlower(cls)) end
    tex:SetShown(shown)
end

local function ShortName(src)
    local n = src.name
    if plain(n) and Ambiguate then n = Ambiguate(n, "short") end
    return n
end

local function Tip(frame, title, text)
    frame:HookScript("OnEnter", function(s)
        GameTooltip:SetOwner(s, "ANCHOR_TOP")
        GameTooltip:AddLine(title)
        if text then GameTooltip:AddLine(text, 0.75, 0.73, 0.8, true) end
        GameTooltip:Show()
    end)
    frame:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

local function Icon(parent, name, size, color)
    local t = parent:CreateTexture(nil, "OVERLAY")
    t:SetTexture(MEDIA .. name)
    t:SetSize(size, size)
    local c = color or C.dim
    t:SetVertexColor(c[1], c[2], c[3], 1)
    return t
end

local function FormatTime(d) return ("%d:%02d"):format(math.floor(d / 60), math.floor(d % 60)) end

---------------------------------------------------------------------------
-- Colonnes visibles et largeur
---------------------------------------------------------------------------
function NZR_DEBUG_CV() local r = tabRows[1]; local c = 0; if r then for _ in pairs(r.cells) do c = c + 1 end end; return #cols, #visible, c, r and r.__kind end
local function ComputeVisible()
    wipe(visible)
    local chosen = DB().meterCols
    for ci, col in ipairs(cols) do
        if chosen[col.id] then table.insert(visible, ci) end
    end
end

local function TableWidth()
    local w = 14 + 6 + (DB().meterIcons and 28 or 6) + 140 + 16
    if DB().meterShare then w = w + 40 end
    for _, ci in ipairs(visible) do w = w + cols[ci].w end
    return w
end

---------------------------------------------------------------------------
-- Vue Tableau
---------------------------------------------------------------------------
local function CreateTabRow(i)
    local r = CreateFrame("Frame", nil, win.body)

    local sep = r:CreateTexture(nil, "BACKGROUND")
    sep:SetColorTexture(1, 1, 1, 0.035)
    sep:SetHeight(1)
    sep:SetPoint("BOTTOMLEFT"); sep:SetPoint("BOTTOMRIGHT")

    r.meBG = r:CreateTexture(nil, "BACKGROUND", nil, 1)
    r.meBG:SetTexture(NZR.TEX)
    r.meBG:SetAllPoints()
    r.meBG:SetGradient("HORIZONTAL", CreateColor(MA[1], MA[2], MA[3], P.meTint), CreateColor(MA[1], MA[2], MA[3], 0))
    r.meBar = r:CreateTexture(nil, "ARTWORK")
    r.meBar:SetColorTexture(MA[1], MA[2], MA[3], 1)
    r.meBar:SetPoint("TOPLEFT"); r.meBar:SetPoint("BOTTOMLEFT"); r.meBar:SetWidth(2)

    r.rank = NZR:Text(r, 10, { 0.44, 0.41, 0.50 }, "RIGHT")
    r.rank:SetPoint("LEFT", 2, 0); r.rank:SetWidth(14)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    r.iconEdge = r:CreateTexture(nil, "BORDER")
    r.iconEdge:SetColorTexture(0, 0, 0, 1)
    r.iconEdge:SetPoint("TOPLEFT", r.icon, -1, 1); r.iconEdge:SetPoint("BOTTOMRIGHT", r.icon, 1, -1)

    r.cells = {}
    for ci, col in ipairs(cols) do
        r.cells[ci] = NZR:Text(r, col.big and 13 or 11.5, col.text or { 0.84, 0.82, 0.89 }, "RIGHT", col.big)
    end
    r.pct = NZR:Text(r, 10, C.dim, "RIGHT")
    r.pct:SetWidth(34)

    r.name = NZR:Text(r, 12, nil, "LEFT", true)
    r.crown = Icon(r, "crown", 11, { 0.95, 0.79, 0.30 })

    r.share = CreateFrame("StatusBar", nil, r)
    r.share:SetStatusBarTexture(NZR.TEX)
    r.share:SetHeight(3)
    local sbg = r.share:CreateTexture(nil, "BACKGROUND")
    sbg:SetAllPoints(); sbg:SetColorTexture(1, 1, 1, 0.06)

    r:Hide()
    r.layoutKey = nil
    tabRows[i] = r
    return r
end

-- place les éléments d'une ligne selon les réglages actuels
local function LayoutTabRow(r, i, key)
    if r.layoutKey == key then return end
    r.layoutKey = key
    local h = RowH()
    r:ClearAllPoints()
    r:SetHeight(h)
    r:SetPoint("TOPLEFT", 0, -(i - 1) * h)
    r:SetPoint("TOPRIGHT", 0, -(i - 1) * h)
    local isz = math.max(14, h - 10)
    r.icon:SetSize(isz, isz)
    r.icon:ClearAllPoints()
    r.icon:SetPoint("LEFT", r.rank, "RIGHT", 6, 0)
    r.iconEdge:SetShown(DB().meterIcons)

    for _, fs in pairs(r.cells) do fs:Hide() end
    local x = -8
    for idx = #visible, 1, -1 do
        local ci = visible[idx]
        local fs = r.cells[ci]
        if fs and cols[ci] then
            fs:ClearAllPoints()
            fs:SetWidth(cols[ci].w)
            fs:SetPoint("RIGHT", r, "RIGHT", x, 0)
            fs:Show()
            x = x - cols[ci].w
        end
    end
    r.pct:ClearAllPoints()
    r.pct:SetPoint("RIGHT", r, "RIGHT", x - 2, 0)
    r.pct:SetShown(DB().meterShare)
    local rightOfName = DB().meterShare and r.pct or nil

    local leftAnchor = DB().meterIcons and r.icon or r.rank
    local small = h <= 24
    r.name:ClearAllPoints()
    if small then
        r.name:SetPoint("LEFT", leftAnchor, "RIGHT", 8, 0)
    else
        r.name:SetPoint("TOPLEFT", leftAnchor, "TOPRIGHT", 8, 1)
    end
    if rightOfName then r.name:SetPoint("RIGHT", rightOfName, "LEFT", -22, 0)
    else r.name:SetPoint("RIGHT", r, "RIGHT", x - 22, 0) end

    r.share:ClearAllPoints()
    r.share:SetShown(not small)
    r.share:SetPoint("BOTTOMLEFT", leftAnchor, "BOTTOMRIGHT", 8, 0)
    if rightOfName then r.share:SetPoint("RIGHT", rightOfName, "LEFT", -12, 0)
    else r.share:SetPoint("RIGHT", r, "RIGHT", x - 12, 0) end
end

-- réunit toutes les listes du compteur par joueur : data[clé] = { src, v[colonne] }
local function Gather()
    local data, order, seen = {}, {}, {}
    local sessions = {}
    local partial = false
    for ci, col in ipairs(cols) do
        local s = sessions[col.type]
        if s == nil then s = Session(col.type) or false; sessions[col.type] = s end
        local list = s and Sources(s)
        if list then
            local single = (#list == 1)
            for idx, src in ipairs(list) do
                local k = KeyOf(src, single)
                if not k then
                    if col.type == "DamageDone" then k = "@dd" .. idx else partial = true end
                end
                if k then
                    local d = data[k]
                    if not d then d = { src = src, v = {} }; data[k] = d end
                    d.v[ci] = src[col.field]
                    if not seen[k] and col.type == "DamageDone" then seen[k] = true; table.insert(order, k) end
                end
            end
        end
    end
    for k in pairs(data) do if not seen[k] then seen[k] = true; table.insert(order, k) end end
    return data, order, sessions, partial
end

local function RenderTable(maxRows)
    -- 1) une liste par type de compteur, réunies par joueur
    local data, order, sessions, partial = Gather()
    win.partial = partial

    -- 2) tri sur la colonne choisie (si les chiffres sont lisibles)
    local sortCi
    for ci, col in ipairs(cols) do if col.id == DB().meterSort then sortCi = ci end end
    if sortCi then
        local ok = true
        for _, k in ipairs(order) do
            local v = data[k].v[sortCi]
            if not isnil(v) and not plain(v) then ok = false break end
        end
        if ok then
            table.sort(order, function(a, b)
                local va, vb = data[a].v[sortCi], data[b].v[sortCi]
                if isnil(va) then va = 0 end
                if isnil(vb) then vb = 0 end
                return va > vb
            end)
        end
    end

    -- 3) totaux
    local totals, dmgCi = {}, nil
    for ci, col in ipairs(cols) do
        if col.id == "dmg" then dmgCi = ci end
        local sum = 0
        for _, k in ipairs(order) do
            local v = data[k].v[ci]
            if isnil(v) then
            elseif plain(v) then sum = sum + v
            else sum = nil break end
        end
        totals[ci] = sum
    end
    local shareCi = sortCi or dmgCi
    local shareTotal = shareCi and totals[shareCi]
    local maxAmount = sessions.DamageDone and sessions.DamageDone.maxAmount

    -- 4) lignes
    local n = #order
    local layoutKey = table.concat(visible, ",") .. "|" .. RowH() .. tostring(DB().meterIcons) .. tostring(DB().meterShare)
    for i = 1, math.max(maxRows, #tabRows) do
        local k = (i <= maxRows) and order[i]
        if k then
            local r = tabRows[i] or CreateTabRow(i)
            LayoutTabRow(r, i, layoutKey)
            local d = data[k]
            local src = d.src
            local cr, cg, cb = ClassColor(src)
            r.rank:SetText(i)
            r.rank:SetShown(DB().meterRank)
            SetSourceIcon(r.icon, src)
            NZR.SafeText(r.name, ShortName(src))
            r.name:SetTextColor(cr, cg, cb)
            r.crown:ClearAllPoints()
            r.crown:SetPoint("LEFT", r.name, "LEFT", math.min(r.name:GetStringWidth() + 5, math.max(0, r.name:GetWidth() - 12)), 0)
            r.crown:SetShown(DB().meterCrown and i == 1 and n > 1)
            local br, bg, bb = BarColor(src)
            r.share:SetStatusBarColor(br, bg, bb, 0.85)
            local amt = shareCi and d.v[shareCi]
            if shareTotal and shareTotal > 0 and plain(amt) then
                r.share:SetMinMaxValues(0, shareTotal); r.share:SetValue(amt)
                r.pct:SetFormattedText("%d%%", math.floor(amt / shareTotal * 100 + 0.5))
            else
                pcall(r.share.SetMinMaxValues, r.share, 0, maxAmount or 1)
                local sv = d.v[dmgCi or 0]
                if isnil(sv) then sv = 0 end
                pcall(r.share.SetValue, r.share, sv)
                r.pct:SetText("")
            end
            for _, ci in ipairs(visible) do
                local col, v, fs = cols[ci], d.v[ci], r.cells[ci]
                if not (col and fs) then
                elseif isnil(v) then
                    fs:SetText("—"); fs:SetTextColor(0.30, 0.28, 0.35)
                else
                    NZR.SafeText(fs, NZR.Abbrev(v, col.field == "amountPerSecond"))
                    local tc = col.text or (col.big and C.text) or { 0.84, 0.82, 0.89 }
                    if plain(v) and v == 0 then tc = { 0.30, 0.28, 0.35 }
                    elseif col.dead and plain(v) and v > 0 then tc = { 1, 0.48, 0.52 } end
                    fs:SetTextColor(tc[1], tc[2], tc[3])
                end
            end
            local me = src.isLocalPlayer
            local isMe = plain(me) and me == true
            r.meBG:SetShown(isMe); r.meBar:SetShown(isMe)
            r:Show()
        elseif tabRows[i] then
            tabRows[i]:Hide()
        end
    end
    for _, r in ipairs(barRows) do r:Hide() end

    -- 5) pied
    win.footLabel:SetText(n > 0 and ("Groupe  |cff8f88a0" .. n .. (n > 1 and " joueurs" or " joueur") .. "|r") or "")
    for _, fs in pairs(win.footCells) do fs:SetText("") end
    for _, ci in ipairs(visible) do
        local t = totals[ci]
        win.footCells[ci]:SetText((n > 0 and t) and NZR.Abbrev(t) or "")
    end
    win.empty:SetShown(n == 0)
    win.count:SetText(n > maxRows and ("+" .. (n - maxRows)) or "")
    return true
end

---------------------------------------------------------------------------
-- Vue Détaillé (cartes façon Meterion)
---------------------------------------------------------------------------
local CARD_H, CARD_GAP = 50, 5
local cardRows = {}
local INFO = {   -- id de colonne -> libellé sous le nom
    { id = "dmg",   label = "Total", icon = "bolt",   color = { 0.66, 0.63, 0.72 } },
    { id = "heal",  label = "Soins", icon = "heart",  color = { 0.50, 0.85, 0.56 }, text = { 0.61, 0.89, 0.66 } },
    { id = "hps",   label = "HPS",   icon = "heart",  color = { 0.50, 0.85, 0.56 }, text = { 0.61, 0.89, 0.66 } },
    { id = "taken", label = "Subis", icon = "shield", color = { 0.91, 0.60, 0.42 } },
    { id = "abs",   label = "Abs.",  icon = "shield", color = { 0.55, 0.75, 1.00 } },
    { id = "int",   label = "",      icon = "hand",   color = { 0.66, 0.63, 0.72 } },
    { id = "disp",  label = "",      icon = "cross",  color = { 0.66, 0.63, 0.72 } },
    { id = "death", label = "",      icon = "skull",  color = { 1.00, 0.48, 0.52 } },
}
local DEFAULT_INFO = { dmg = true, heal = true, taken = true, int = true }

local function ColIndex(id)
    for ci, col in ipairs(cols) do if col.id == id then return ci end end
end

local function CreateCard(i)
    local c = CreateFrame("Frame", nil, win.body)
    NZR:FlatBackdrop(c, true, 1, true)
    c:SetBackdropColor(unpack(P.card))
    c:SetBackdropBorderColor(unpack(P.cardEdge))
    c:SetHeight(CARD_H)

    c.fill = CreateFrame("StatusBar", nil, c)
    c.fill:SetPoint("TOPLEFT", 2, -2); c.fill:SetPoint("BOTTOMRIGHT", -2, 2)
    c.fill:SetStatusBarTexture(NZR.TEX)
    c.fill:SetMinMaxValues(0, 1); c.fill:SetValue(0)

    local over = CreateFrame("Frame", nil, c)
    over:SetAllPoints()
    over:SetFrameLevel(c.fill:GetFrameLevel() + 2)

    c.av = over:CreateTexture(nil, "ARTWORK")
    c.av:SetSize(32, 32)
    c.av:SetPoint("LEFT", 9, 0)
    c.av:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local mask = over.CreateMaskTexture and over:CreateMaskTexture()
    if mask then
        mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(c.av)
        c.av:AddMaskTexture(mask)
    end
    c.ring = over:CreateTexture(nil, "OVERLAY")
    c.ring:SetTexture(MEDIA .. "circle_edge")
    c.ring:SetPoint("TOPLEFT", c.av, -2, 2); c.ring:SetPoint("BOTTOMRIGHT", c.av, 2, -2)

    c.name = NZR:Text(over, 13, nil, "LEFT", true)
    c.name:SetPoint("TOPLEFT", c.av, "TOPRIGHT", 10, 1)
    c.moi = CreateFrame("Frame", nil, over)
    c.moi:SetSize(28, 14)
    NZR:FlatBackdrop(c.moi, true, 1, 3)
    c.moi:SetBackdropColor(0.95, 0.79, 0.30, 1); c.moi:SetBackdropBorderColor(0.95, 0.79, 0.30, 1)
    c.moi:SetPoint("LEFT", c.name, "RIGHT", 6, 0)
    local mt = NZR:Text(c.moi, 9, { 0.1, 0.09, 0.13 }, "CENTER", true)
    mt:SetPoint("CENTER", 0, 0); mt:SetText("MOI"); mt:SetShadowOffset(0, 0)
    c.cls = NZR:Text(over, 10.5, C.dim, "LEFT")

    c.dps = NZR:Text(over, 19, nil, "RIGHT", true)
    c.dps:SetPoint("TOPRIGHT", -12, -6)
    c.dpsLbl = NZR:Text(over, 9.5, C.dim, "RIGHT", true)
    c.dpsLbl:SetPoint("BOTTOMRIGHT", c.dps, "BOTTOMLEFT", -5, 3)
    c.dpsLbl:SetText("DPS")
    c.pct = NZR:Text(over, 10.5, C.dim, "RIGHT")
    c.pct:SetPoint("TOPRIGHT", c.dps, "BOTTOMRIGHT", 0, -1)

    c.info = {}
    for j = 1, #INFO do
        local ic = over:CreateTexture(nil, "ARTWORK")
        ic:SetSize(11, 11)
        local fs = NZR:Text(over, 10.5, { 0.66, 0.63, 0.72 }, "LEFT")
        c.info[j] = { icon = ic, text = fs }
    end
    c:Hide()
    cardRows[i] = c
    return c
end

local function FillCard(c, i, d, n, dpsCi, dmgCi, total, maxAmount)
    local src = d.src
    c:ClearAllPoints()
    c:SetPoint("TOPLEFT", 0, -(i - 1) * (CARD_H + CARD_GAP))
    c:SetPoint("TOPRIGHT", 0, -(i - 1) * (CARD_H + CARD_GAP))

    local cr, cg, cb = ClassColor(src)
    local br, bg, bb = BarColor(src)
    -- fond de la carte à la couleur de la classe, rempli selon la part
    local ft = c.fill:GetStatusBarTexture()
    if ft then ft:SetGradient("HORIZONTAL", CreateColor(br, bg, bb, 0.30), CreateColor(br, bg, bb, 0.07)) end
    local amt = dmgCi and d.v[dmgCi]
    if total and total > 0 and plain(amt) then
        c.fill:SetMinMaxValues(0, total); c.fill:SetValue(amt)
        c.pct:SetFormattedText("%.1f %%", amt / total * 100)
    else
        pcall(c.fill.SetMinMaxValues, c.fill, 0, maxAmount or 1)
        if not isnil(amt) then pcall(c.fill.SetValue, c.fill, amt) end
        c.pct:SetText("")
    end
    c.pct:SetShown(DB().meterShare)
    c.fill:SetShown(DB().meterCardFill ~= false)

    SetSourceIcon(c.av, src)
    c.ring:SetVertexColor(cr, cg, cb, 1)
    c.ring:SetShown(c.av:IsShown())

    NZR.SafeText(c.name, ShortName(src))
    c.name:SetWidth(0)
    local okw, w = pcall(c.name.GetStringWidth, c.name)
    if okw and plain(w) and w > 150 then c.name:SetWidth(150) end

    local me = src.isLocalPlayer
    local isMe = plain(me) and me == true
    c.moi:SetShown(isMe)
    if isMe then c:SetBackdropBorderColor(unpack(P.meEdge))
    else c:SetBackdropBorderColor(unpack(P.cardEdge)) end

    local cls = src.classFilename
    local loc = plain(cls) and LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[cls]
    if not loc and isMe then loc = UnitClass("player") end
    c.cls:ClearAllPoints()
    c.cls:SetPoint("LEFT", isMe and c.moi or c.name, "RIGHT", 6, 0)
    c.cls:SetPoint("RIGHT", c.dpsLbl, "LEFT", -6, 0)          -- jamais sous « DPS »
    c.cls:SetWordWrap(false)
    c.cls:SetText(loc or "")
    c.cls:SetTextColor(cr, cg, cb)

    local dv = dpsCi and d.v[dpsCi]
    if isnil(dv) then c.dps:SetText("—") else NZR.SafeText(c.dps, NZR.Abbrev(dv, true)) end

    -- ligne de détails sous le nom
    local chosen = DB().meterInfo or DEFAULT_INFO
    local prev
    for j, info in ipairs(INFO) do
        local slot = c.info[j]
        local ci = ColIndex(info.id)
        local v = ci and d.v[ci]
        if chosen[info.id] and ci then
            slot.icon:SetTexture(MEDIA .. info.icon)
            slot.icon:SetVertexColor(info.color[1], info.color[2], info.color[3])
            slot.icon:ClearAllPoints()
            if prev then slot.icon:SetPoint("LEFT", prev, "RIGHT", 9, 0)
            else slot.icon:SetPoint("BOTTOMLEFT", c.av, "BOTTOMRIGHT", 10, 1) end
            slot.text:ClearAllPoints()
            slot.text:SetPoint("LEFT", slot.icon, "RIGHT", 3, 0)
            local val = isnil(v) and "—" or NZR.Abbrev(v, info.id == "hps")
            local ok, s = pcall(string.format, "%s%s%s", info.label, info.label ~= "" and " " or "", val)
            NZR.SafeText(slot.text, ok and s or val)
            local tc = info.text or { 0.66, 0.63, 0.72 }
            slot.text:SetTextColor(tc[1], tc[2], tc[3])
            slot.icon:Show(); slot.text:Show()
            prev = slot.text
        else
            slot.icon:Hide(); slot.text:Hide()
        end
    end
    c:Show()
end

local function RenderCards(maxCards)
    local data, order, sessions, partial = Gather()
    win.partial = partial
    local dpsCi, dmgCi = ColIndex("dps"), ColIndex("dmg")
    -- tri (si lisible) sur la colonne choisie, sinon ordre du jeu
    local sortCi = ColIndex(DB().meterSort or "dps") or dpsCi
    if sortCi then
        local ok = true
        for _, k in ipairs(order) do
            local v = data[k].v[sortCi]
            if not isnil(v) and not plain(v) then ok = false break end
        end
        if ok then
            table.sort(order, function(a, b)
                local va, vb = data[a].v[sortCi], data[b].v[sortCi]
                if isnil(va) then va = 0 end
                if isnil(vb) then vb = 0 end
                return va > vb
            end)
        end
    end
    local total, totalPS = 0, 0
    for _, k in ipairs(order) do
        local a = dmgCi and data[k].v[dmgCi]
        local p = dpsCi and data[k].v[dpsCi]
        if total then if isnil(a) then elseif plain(a) then total = total + a else total = nil end end
        if totalPS then if isnil(p) then elseif plain(p) then totalPS = totalPS + p else totalPS = nil end end
    end
    local maxAmount = sessions.DamageDone and sessions.DamageDone.maxAmount
    local n = #order
    for i = 1, math.max(maxCards, #cardRows) do
        local k = (i <= maxCards) and order[i]
        if k then
            local c = cardRows[i] or CreateCard(i)
            local ok, err = pcall(FillCard, c, i, data[k], n, dpsCi, dmgCi, total, maxAmount)
            if not ok then
                c:Hide()
                if NZR.LogError and err ~= win.lastCardErr then win.lastCardErr = err; pcall(NZR.LogError, NZR, err, "Meter") end
            end
        elseif cardRows[i] then
            cardRows[i]:Hide()
        end
    end
    for _, r in ipairs(tabRows) do r:Hide() end
    for _, r in ipairs(barRows) do r:Hide() end
    -- pied
    local parts = {}
    if totalPS and n > 0 then table.insert(parts, "DPS du groupe  |cffece9f3" .. NZR.Abbrev(totalPS, true) .. "|r") end
    if total and n > 0 then table.insert(parts, "Total  |cffece9f3" .. NZR.Abbrev(total) .. "|r") end
    win.footLabel:SetText(table.concat(parts, "     "))
    for _, fs in pairs(win.footCells) do fs:SetText("") end
    win.count:ClearAllPoints()
    win.count:SetPoint("RIGHT", win.foot, "RIGHT", -16, 0)
    win.count:SetText(n > 0 and (n .. (n > 1 and " joueurs" or " joueur")) or "")
    win.empty:SetShown(n == 0)
    return true
end

-- barre de vie de la cible (vue Détaillé)
-- le contenu commence juste sous le titre, sauf s'il y a une ligne à montrer dessous
-- (colonnes du Tableau, onglets des Barres, vie de la cible en Détaillé)
local function SubShown()
    local v = DB().meterView
    if v == "cards" then return DB().meterTargetBar ~= false and UnitExists("target") end
    return true
end
function NZR.MeterAnchorBody()
    if not win or not win.body then return end
    local collapse = not SubShown()
    if win.bodyCollapsed == collapse then return end
    win.bodyCollapsed = collapse
    if win.ssep then win.ssep:SetShown(not collapse) end   -- pas de trait au travers des cartes
    -- teinte « Jeu » : le cadre doré du jeu est plus épais, on reste à l'intérieur
    local inX = win.nzrRock and 7 or 2
    win.body:ClearAllPoints()
    win.body:SetPoint("TOPLEFT", win.colHead, collapse and "TOPLEFT" or "BOTTOMLEFT", inX, collapse and -4 or -2)
    win.body:SetPoint("BOTTOMRIGHT", -inX, DB().meterFooter and (FOOTER_H + 1) or (win.nzrRock and 6 or 3))
end

local function UpdateTargetBar()
    local t = win.tgt
    if not t then return end
    local show = DB().meterView == "cards" and DB().meterTargetBar ~= false and UnitExists("target")
    t.inner:SetShown(show and true or false)
    if not show then return end
    local cur, max = UnitHealth("target"), UnitHealthMax("target")
    t.bar:SetMinMaxValues(0, max); t.bar:SetValue(cur)
    local ok, s = pcall(string.format, "%s / %s", NZR.Abbrev(cur), NZR.Abbrev(max))
    NZR.SafeText(t.left, ok and s or NZR.Abbrev(cur))
    local pctText
    if UnitHealthPercent and CurveConstants and CurveConstants.ScaleTo100 then
        local okp, p = pcall(UnitHealthPercent, "target", true, CurveConstants.ScaleTo100)
        if okp and p ~= nil then local ok2, s2 = pcall(string.format, "%.0f %%", p); if ok2 then pctText = s2 end end
    end
    if not pctText and plain(cur) and plain(max) and max > 0 then pctText = ("%.0f %%"):format(cur / max * 100) end
    NZR.SafeText(t.right, pctText or "")
end

---------------------------------------------------------------------------
-- Vue Barres
---------------------------------------------------------------------------
local function CreateBarRow(i)
    local r = CreateFrame("Frame", nil, win.body)
    r:SetHeight(BAR_ROW_H - 2)
    r:SetPoint("TOPLEFT", 0, -(i - 1) * BAR_ROW_H)
    r:SetPoint("TOPRIGHT", 0, -(i - 1) * BAR_ROW_H)
    r.bar = NZR:Bar(r)
    r.bar:SetAllPoints()
    r.bar.bg:SetColorTexture(1, 1, 1, 0.03)
    r.me = r:CreateTexture(nil, "OVERLAY", nil, 6)
    r.me:SetColorTexture(MA[1], MA[2], MA[3], 1)
    r.me:SetPoint("TOPLEFT"); r.me:SetPoint("BOTTOMLEFT"); r.me:SetWidth(2)
    local over = CreateFrame("Frame", nil, r.bar)
    over:SetAllPoints()
    over:SetFrameLevel(r.bar:GetFrameLevel() + 2)
    r.rank = NZR:Text(over, 10, C.dim, "RIGHT")
    r.rank:SetPoint("LEFT", 2, 0); r.rank:SetWidth(14)
    r.icon = over:CreateTexture(nil, "OVERLAY")
    r.icon:SetSize(BAR_ROW_H - 6, BAR_ROW_H - 6)
    r.icon:SetPoint("LEFT", r.rank, "RIGHT", 4, 0)
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    r.total = NZR:Text(over, 12, nil, "RIGHT", true)
    r.total:SetPoint("RIGHT", -6, 0)
    r.ps = NZR:Text(over, 11, { 0.82, 0.79, 0.88 }, "RIGHT")
    r.ps:SetPoint("RIGHT", r.total, "LEFT", -7, 0)
    r.pct = NZR:Text(over, 10, C.dim, "RIGHT")
    r.pct:SetPoint("RIGHT", r.ps, "LEFT", -7, 0)
    r.name = NZR:Text(over, 12)
    r.name:SetPoint("LEFT", r.icon, "RIGHT", 5, 0)
    r.name:SetPoint("RIGHT", r.pct, "LEFT", -6, 0)
    r:Hide()
    barRows[i] = r
    return r
end

local function RenderBars(maxRows)
    local mode = CurrentMode()
    local s = mode and Session(mode.key)
    local list = Sources(s)
    local n = list and #list or 0
    local maxAmount = s and s.maxAmount
    if not issecret(maxAmount) and maxAmount == nil and n > 0 then maxAmount = list[1].totalAmount end

    local total = 0
    for i = 1, n do
        local a = list[i].totalAmount
        if plain(a) then total = total + a else total = nil break end
    end

    for i = 1, math.max(maxRows, #barRows) do
        local src = (i <= maxRows) and list and list[i]
        if src then
            local r = barRows[i] or CreateBarRow(i)
            local ok = pcall(function()
                r.rank:SetText(i)
                r.rank:SetShown(DB().meterRank)
                NZR.SafeText(r.name, ShortName(src))
                local cr, cg, cb = BarColor(src)
                NZR:SetBarColor(r.bar, cr * 0.85, cg * 0.85, cb * 0.85, 0.85)
                SetSourceIcon(r.icon, src)
                pcall(r.bar.SetMinMaxValues, r.bar, 0, maxAmount)
                pcall(r.bar.SetValue, r.bar, src.totalAmount)
                local isRate = (mode.main == "ps")
                local main, second = src.totalAmount, nil
                if mode.ps then second = src.amountPerSecond end
                if isRate then main, second = src.amountPerSecond, src.totalAmount end
                NZR.SafeText(r.total, NZR.Abbrev(main, isRate))
                if not isnil(second) then NZR.SafeText(r.ps, NZR.Abbrev(second, not isRate)); r.ps:Show() else r.ps:Hide() end
                local a = src.totalAmount
                if DB().meterShare and total and total > 0 and plain(a) then
                    r.pct:SetFormattedText("%d%%", math.floor(a / total * 100 + 0.5))
                else r.pct:SetText("") end
                local me = src.isLocalPlayer
                r.me:SetShown(plain(me) and me == true)
            end)
            r:SetShown(ok)
        elseif barRows[i] then
            barRows[i]:Hide()
        end
    end
    for _, r in ipairs(tabRows) do r:Hide() end
    win.footLabel:SetText(total and total > 0 and ("Groupe  " .. NZR.Abbrev(total)) or (InCombatLockdown() and "|cff8f88a0En combat…|r" or ""))
    for _, fs in pairs(win.footCells) do fs:SetText("") end
    win.empty:SetShown(n == 0)
    win.count:ClearAllPoints()
    win.count:SetPoint("RIGHT", win.foot, "RIGHT", -16, 0)
    win.count:SetText(n > maxRows and ("+" .. (n - maxRows)) or "")
end

---------------------------------------------------------------------------
-- En-tête de colonnes (cliquable pour trier) et pied
---------------------------------------------------------------------------
local Render

local function LayoutHeader()
    for _, cell in pairs(win.colCells) do cell:Hide() end
    for _, fs in pairs(win.footCells) do fs:Hide() end
    local x = -8
    for idx = #visible, 1, -1 do
        local ci = visible[idx]
        local col, cell, fs = cols[ci], win.colCells[ci], win.footCells[ci]
        cell:ClearAllPoints()
        cell:SetSize(col.w, SUB_H)
        cell:SetPoint("RIGHT", win.colHead, "RIGHT", x, 0)
        cell:Show()
        local on = (col.id == DB().meterSort)
        cell.label:SetTextColor(on and C.text[1] or C.dim[1], on and C.text[2] or C.dim[2], on and C.text[3] or C.dim[3])
        cell.line:SetShown(on)
        fs:ClearAllPoints()
        fs:SetWidth(col.w)
        fs:SetPoint("RIGHT", win.foot, "RIGHT", x + 1, 0)
        fs:Show()
        x = x - col.w
    end
    win.count:ClearAllPoints()
    win.count:SetPoint("RIGHT", win.foot, "RIGHT", x - 40, 0)
end

local function CreateColumnHeader(parent)
    local h = CreateFrame("Frame", nil, parent)
    local bg = h:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(1, 1, 1, 0.015)
    local who = NZR:Text(h, 10, C.dim, "LEFT", true)
    who:SetPoint("LEFT", 10, 0)
    who:SetText("Joueur")
    win.colCells = {}
    for ci, col in ipairs(cols) do
        local cell = CreateFrame("Button", nil, h)
        cell.label = NZR:Text(cell, 10, C.dim, "RIGHT", true)
        cell.label:SetPoint("RIGHT")
        cell.label:SetText(col.label)
        local ic = Icon(cell, col.icon, 12, col.color or (col.id == "dps" and MA2) or C.dim)
        ic:SetPoint("RIGHT", cell.label, "LEFT", -4, 0)
        cell.line = cell:CreateTexture(nil, "OVERLAY")
        cell.line:SetColorTexture(MA[1], MA[2], MA[3], 1)
        cell.line:SetHeight(2)
        cell.line:SetPoint("BOTTOMRIGHT", 0, 0)
        cell.line:SetPoint("BOTTOMLEFT", ic, "BOTTOMLEFT", 0, -5)
        cell:SetScript("OnClick", function()
            DB().meterSort = col.id
            LayoutHeader()
            Render()
        end)
        Tip(cell, col.long, "Clic : trier sur cette colonne.")
        cell:Hide()
        win.colCells[ci] = cell
    end
    return h
end

---------------------------------------------------------------------------
-- Rendu commun
---------------------------------------------------------------------------
Render = function()
    if not win or not win:IsShown() then return end
    local view = DB().meterView or "cards"
    NZR.MeterAnchorBody()
    local bodyH = win:GetHeight() - HEADER_H - (SubShown() and SUB_H or 0) - (DB().meterFooter and FOOTER_H or 0) - 4
    local function logErr(ok, res)
        if not ok and NZR.LogError and res ~= win.lastErr then
            win.lastErr = res
            pcall(NZR.LogError, NZR, res, "Meter")
        end
    end

    local shown = "bars"
    if view == "cards" then
        local ok, res = pcall(RenderCards, math.max(1, math.floor((bodyH + CARD_GAP) / (CARD_H + CARD_GAP))))
        logErr(ok, res)
        if ok and res then shown = "cards" end
    elseif view == "table" and #visible > 0 then
        local ok, res = pcall(RenderTable, math.max(1, math.floor(bodyH / RowH())))
        logErr(ok, res)
        if ok and res then shown = "table" end
    end
    if shown == "bars" then
        for _, c in ipairs(cardRows) do c:Hide() end
        pcall(RenderBars, math.max(1, math.floor(bodyH / BAR_ROW_H)))
    end
    win.colHead:SetShown(shown == "table")
    win.tabsBar:SetShown(shown == "bars")
    win.tgt:SetShown(shown == "cards")
    if shown == "cards" then pcall(UpdateTargetBar) end

    -- titre : ce que tu combats (Détaillé), sinon le mode
    local mode = CurrentMode()
    local title = (shown == "bars") and (mode and mode.label or "Dégâts") or "Combat"
    if shown == "cards" and UnitExists("target") then
        local okn, tn = pcall(UnitName, "target")
        if okn and tn ~= nil then title = tn end
    end
    NZR.SafeText(win.title, title)
    local w = win:GetWidth()
    if view == "table" and #visible == 0 then
        win.empty:SetText("Aucune colonne choisie\n|cff8f88a0Clic droit ici pour en ajouter|r")
        win.empty:Show()
    else
        win.empty:SetText("En attente de combat…")
    end
    if shown == "bars" and view ~= "bars" then
        win.note:SetText("Vue Barres (erreur, voir /nzr erreurs)")
        win.note:Show()
    elseif shown ~= "bars" and win.partial then
        win.note:SetText("Noms cachés par le jeu : détails partiels pour les autres")
        win.note:Show()
    else
        win.note:Hide()
    end
    win.segPill:Select(DB().meterOverall and 2 or 1)
    for i, t in ipairs(win.tabs) do t:SetActive(i == DB().meterMode) end

    local s = Session("DamageDone")
    local d = s and s.durationSeconds
    local showClock = plain(d) and d > 0 and w >= 360
    win.clock:SetText(showClock and FormatTime(d) or "")
    win.clock:SetShown(showClock)
    win.clockIcon:SetShown(showClock)
end
---------------------------------------------------------------------------
-- Fenêtre
---------------------------------------------------------------------------
local function SavePos()
    local p, _, rp, x, y = win:GetPoint()
    DB().pos.meter = { p, rp, x, y }
    local v = DB().meterView
    if v == "cards" then DB().meterCW, DB().meterCH = win:GetSize()
    elseif v == "table" then DB().meterTW, DB().meterTH = win:GetSize()
    else DB().meterW, DB().meterH = win:GetSize() end
end

local function ApplySize()
    local v = DB().meterView
    if v == "cards" then win:SetSize(math.max(DB().meterCW or 430, 330), DB().meterCH or 330)
    elseif v == "table" then win:SetSize(math.max(DB().meterTW or TableWidth(), 330), DB().meterTH or 210)
    else win:SetSize(math.max(DB().meterW or 340, 330), DB().meterH or 180) end
end

local function PlaceWin()
    local p = DB().pos.meter or { "LEFT", "LEFT", 20, -60 }
    win:ClearAllPoints()
    win:SetPoint(p[1], UIParent, p[2], p[3], p[4])
end

-- applique tous les réglages (appelé par la fenêtre de réglages)
local function ApplySettings(resize)
    if not win then return end
    ComputeVisible()
    if resize and DB().meterView == "table" then
        DB().meterTW = math.max(TableWidth(), 260)
        win:SetWidth(DB().meterTW)
    end
    if win.nzrRock then
        win.nzrAlpha = 0
        NZR:WowFrameAlpha(win, DB().meterAlpha or 0.85)
    else
        win.nzrAlpha = DB().meterAlpha or 0.88
    end
    NZR:ApplyOpacity()
    win.foot:SetShown(DB().meterFooter)
    win.bodyCollapsed = nil
    NZR.MeterAnchorBody()
    win.grip:SetShown(not DB().meterLock or NZR.editing)
    if win.lock then win.lock.Refresh() end
    for _, r in ipairs(tabRows) do r.layoutKey = nil end
    LayoutHeader()
    win.tabsBar:Layout()
    Render()
end

-- affichage automatique : en combat, en groupe, ou dans les 20 s après un combat
-- meter réduit : une petite icône à la place, un clic le rouvre
local mini
-- meter réduit : les barres de sorts / buffs collées à sa droite vont à l'emplacement choisi
-- (bloc « Barres, meter réduit » à placer avec Déplacer), l'icône DPS au-dessus
local BAR_NAMES = { "MainMenuBar", "MainActionBar", "MultiBarBottomLeft", "MultiBarBottomRight",
    "MultiBarRight", "MultiBarLeft", "MultiBar5", "MultiBar6", "MultiBar7", "StanceBar", "StanceBarFrame",
    "PetActionBar", "PetActionBarFrame", "PossessActionBar", "PossessBarFrame", "MultiCastActionBarFrame",
}
-- à suivre aussi, au choix (réglages du meter)
local BUFF_NAMES = { "BuffFrame", "DebuffFrame", "BuffIconCooldownViewer", "BuffBarCooldownViewer" }
local CD_NAMES = { "EssentialCooldownViewer", "UtilityCooldownViewer" }
local shifted = nil          -- { [frame] = points d'origine }, nil = rien de décalé
local shiftTop, shiftLeft
local shiftHolder
local function ShiftHolder()
    if not shiftHolder then
        shiftHolder = NZR:Holder("meterbars", "Barres quand le meter est réduit", 300, 260, { "TOPLEFT", "TOPLEFT", 12, -330 })
        shiftHolder:HookScript("OnDragStop", function()
            DB().meterBarsPos = nil          -- le bloc placé à la main reprend la main
            if shifted and NZR.MeterShiftRefresh then NZR.MeterShiftRefresh(true) end
        end)
    end
    return shiftHolder
end
-- au chargement, on attend que le jeu ait posé ses barres (mode Édition) avant de décaler
local shiftReady = false
local function ShiftBars(on)
    if DB().meterShiftBars then ShiftHolder() end   -- le bloc existe pour pouvoir le placer
    if on and not DB().meterShiftBars then on = false end
    if on and not shiftReady then return end
    if on == (shifted ~= nil) then return end
    if InCombatLockdown() then return end          -- réessayé à la sortie du combat (minuterie)
    if not on then
        for f, pts in pairs(shifted) do
            f:ClearAllPoints()
            for _, pt in ipairs(pts) do pcall(f.SetPoint, f, unpack(pt)) end
            if f.nzrCollapsed then f.nzrCollapsed = nil; f:SetAlpha(1); pcall(f.Show, f) end
        end
        shifted = nil
        return
    end
    if not win then return end
    local wl, wr, wt, wb = win:GetLeft(), win:GetRight(), win:GetTop(), win:GetBottom()
    if not (wl and wr) then return end
    local list, minLeft, top, maxRight, bottom = {}, nil, nil, nil, nil
    local seen = {}
    local names = {}
    for _, n in ipairs(BAR_NAMES) do names[#names + 1] = n end
    if DB().meterShiftBuffs ~= false then for _, n in ipairs(BUFF_NAMES) do names[#names + 1] = n end end
    if DB().meterShiftCD ~= false then for _, n in ipairs(CD_NAMES) do names[#names + 1] = n end end
    for _, n in ipairs(names) do
        local f = _G[n]
        if f and not seen[f] and f.IsShown and f:IsShown() and f.GetLeft then
            seen[f] = true
            local l, r, t, b = f:GetLeft(), f:GetRight(), f:GetTop(), f:GetBottom()
            -- juste à droite du meter et à peu près à la même hauteur
            if l and r and t and b and l >= wr - 12 and l <= wr + 90 and t >= wb - 260 and b <= wt + 260 then
                table.insert(list, f)
                minLeft, maxRight = math.min(minLeft or l, l), math.max(maxRight or r, r)
                top, bottom = math.max(top or t, t), math.min(bottom or b, b)
            end
        end
    end
    shifted = {}
    if #list == 0 then return end
    -- destination : le bloc à placer (sa taille suit celle des barres)
    local hd = ShiftHolder()
    hd:SetSize(maxRight - minLeft, top - bottom)
    local tl, tt = hd:GetLeft(), hd:GetTop()
    -- l'icône DPS a été glissée : les barres la suivent, juste en dessous
    local bp = DB().meterBarsPos
    if bp then tl, tt = bp[1], bp[2] end
    if not (tl and tt) then tl, tt = wl, wt end
    local dx, dy = minLeft - tl, top - tt
    -- une barre accrochée à une autre barre déplacée suit déjà toute seule :
    -- on ne décale que les points accrochés à autre chose (sinon elle bouge deux fois)
    local set = {}
    for _, f in ipairs(list) do set[f] = true end
    local function follows(rel)
        local r, guard = rel, 0
        while r and r ~= UIParent and guard < 20 do
            if set[r] then return true end
            r = r.GetParent and r:GetParent() or nil
            guard = guard + 1
        end
        return false
    end
    for _, f in ipairs(list) do
        local pts = {}
        for i = 1, f:GetNumPoints() do
            local a, rel, r, x, y = f:GetPoint(i)
            pts[i] = { a, rel, r, x, y }
        end
        shifted[f] = pts
        f:ClearAllPoints()
        for _, pt in ipairs(pts) do
            if follows(pt[2]) then pcall(f.SetPoint, f, pt[1], pt[2], pt[3], pt[4] or 0, pt[5] or 0)
            else pcall(f.SetPoint, f, pt[1], pt[2], pt[3], (pt[4] or 0) - dx, (pt[5] or 0) - dy) end
        end
    end
    shiftTop, shiftLeft = tt, tl
end

local function ShowMini(show)
    if show and not mini then
        mini = CreateFrame("Button", "NZRF_MeterMini", UIParent)
        mini:SetSize(36, 36)
        mini:SetFrameStrata("MEDIUM")
        mini:SetClampedToScreen(true)
        mini:SetMovable(true)
        mini:RegisterForDrag("LeftButton")
        local ic = mini:CreateTexture(nil, "ARTWORK")
        ic:SetPoint("TOPLEFT", 4, -4); ic:SetPoint("BOTTOMRIGHT", -4, 4)
        ic:SetTexture("Interface\\Icons\\Ability_DualWield")
        ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        local ring = mini:CreateTexture(nil, "OVERLAY")
        ring:SetAllPoints(); ring:SetTexture("Interface\\AddOns\\NZRForever\\Media\\uf\\ring_square")
        local hl = mini:CreateTexture(nil, "HIGHLIGHT"); hl:SetPoint("TOPLEFT", 4, -4); hl:SetPoint("BOTTOMRIGHT", -4, 4)
        hl:SetColorTexture(1, 0.82, 0, 0.25)
        mini.label = mini:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        mini.label:SetPoint("TOP", mini, "BOTTOM", 0, -1)
        mini.label:SetText("DPS")
        local p = DB().meterMiniPos
        if p then mini:SetPoint(p[1], UIParent, p[2], p[3], p[4])
        elseif win then mini:SetPoint("TOPLEFT", win, "TOPLEFT", 0, 0)
        else mini:SetPoint("CENTER") end
        mini:SetScript("OnDragStart", mini.StartMoving)
        mini:SetScript("OnDragStop", function(s)
            s:StopMovingOrSizing()
            local a, _, r, x, y = s:GetPoint()
            DB().meterMiniPos = { a, r, x, y }
            -- barres décalées : elles suivent l'icône (placées juste en dessous)
            if shifted and s:GetLeft() then
                DB().meterBarsPos = { s:GetLeft(), s:GetBottom() - 16 }
                if NZR.MeterShiftRefresh then NZR.MeterShiftRefresh(true) end
            end
        end)
        -- petite flèche : replier / déplier les barres décalées (comme celle des buffs)
        local ar = CreateFrame("Button", nil, mini)
        ar:SetSize(18, 18)
        ar:SetPoint("LEFT", mini, "RIGHT", 3, 0)
        ar.tex = ar:CreateTexture(nil, "ARTWORK"); ar.tex:SetAllPoints()
        ar:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
        ar:SetScript("OnClick", function()
            DB().meterBarsCollapsed = not DB().meterBarsCollapsed
            if NZR.MeterBarsCollapse then NZR.MeterBarsCollapse() end
        end)
        ar:SetScript("OnEnter", function(s)
            GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
            GameTooltip:AddLine(DB().meterBarsCollapsed and "Afficher les barres" or "Cacher les barres")
            GameTooltip:AddLine("Barres, buffs et temps de recharge choisis dans les réglages du meter.", 1, 1, 1, true)
            GameTooltip:Show()
        end)
        ar:SetScript("OnLeave", function() GameTooltip:Hide() end)
        mini.arrow = ar
        mini:SetScript("OnClick", function()
            DB().meterMin = false
            mini:Hide()
            if win then win:Show(); Render() end
        end)
        mini:SetScript("OnEnter", function(s)
            GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
            GameTooltip:AddLine("DPS meter")
            GameTooltip:AddLine("Clic : afficher le meter. Glisser : déplacer l'icône.", 1, 1, 1, true)
            GameTooltip:Show()
        end)
        mini:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    ShiftBars(show)
    if mini then
        -- barres décalées : l'icône se pose au-dessus d'elles, en haut à gauche
        if show and shifted and shiftTop and not mini.nzrDocked then
            mini:ClearAllPoints()
            mini:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", shiftLeft, shiftTop + 16)
            mini.nzrDocked = true
        elseif (not show or not shifted) and mini.nzrDocked then
            mini.nzrDocked = nil
            mini:ClearAllPoints()
            local p = DB().meterMiniPos
            if p then mini:SetPoint(p[1], UIParent, p[2], p[3], p[4])
            elseif win then mini:SetPoint("TOPLEFT", win, "TOPLEFT", 0, 0) end
        end
        mini:SetShown(show)
        if NZR.MeterBarsCollapse then NZR.MeterBarsCollapse() end
    end
end

-- replier : invisibles et (hors combat) cachées ; déplier : comme avant
NZR.MeterBarsCollapse = function()
    local hide = DB().meterBarsCollapsed and shifted ~= nil
    if shifted then
        for f in pairs(shifted) do
            if hide then
                f.nzrCollapsed = true; f:SetAlpha(0)
                if not InCombatLockdown() then pcall(f.Hide, f) end
            elseif f.nzrCollapsed then
                f.nzrCollapsed = nil; f:SetAlpha(1)
                if not InCombatLockdown() then pcall(f.Show, f) end
            end
        end
    end
    if mini and mini.arrow then
        mini.arrow:SetShown(shifted ~= nil and next(shifted) ~= nil)
        mini.arrow.tex:SetTexture(DB().meterBarsCollapsed and "Interface\\Buttons\\Arrow-Down-Up" or "Interface\\Buttons\\Arrow-Up-Up")
    end
end

NZR.MeterShiftRefresh = function(redo)
    if redo and shifted then ShiftBars(false); if mini then mini.nzrDocked = nil end end
    ShowMini(DB().meterMin and true or false)
end

local function UpdateVisibility()
    if not win then return end
    if DB().meterMin then
        if win:IsShown() then win:Hide() end
        ShowMini(true)
        return
    end
    ShowMini(false)
    if not DB().meterAuto then
        if not win:IsShown() then win:Show(); Render() end
        return
    end
    local show = InCombatLockdown() or IsInGroup() or (GetTime() - lastCombat < 20) or (NZRF_Options and NZRF_Options:IsShown())
    if show and not win:IsShown() then win:Show(); Render()
    elseif not show and win:IsShown() then win:Hide() end
end

local function Pill(parent, labels, onPick, tips)
    local f = CreateFrame("Frame", nil, parent)
    NZR:FlatBackdrop(f, true, 1, 5)
    f:SetBackdropColor(1, 1, 1, 0.04)
    f:SetBackdropBorderColor(1, 1, 1, 0.09)
    f:SetHeight(20)
    f.btns = {}
    local BW = 52
    for i, label in ipairs(labels) do
        local b = CreateFrame("Button", nil, f)
        b:SetSize(BW, 18)
        b:SetPoint("LEFT", 1 + (i - 1) * BW, 0)
        b.bg = b:CreateTexture(nil, "BACKGROUND")
        b.bg:SetPoint("TOPLEFT", 1, -1); b.bg:SetPoint("BOTTOMRIGHT", -1, 1)
        NZR:RoundTex(b.bg, 3, MA[1], MA[2], MA[3], 0.28)
        b.text = b:CreateFontString(nil, "OVERLAY")
        b.text:SetFont(NZR.FONT_BOLD, 11, "")
        b.text:SetShadowColor(0, 0, 0, 1); b.text:SetShadowOffset(1, -1)
        b.text:SetPoint("CENTER", 0, 0)
        b.text:SetText(label)
        b.line = { SetShown = function() end }
        b:SetScript("OnClick", function() onPick(i) end)
        b:SetScript("OnEnter", function(s) if not s.on then s.text:SetTextColor(1, 1, 1) end end)
        b:SetScript("OnLeave", function(s) local c = s.on and { 1, 1, 1 } or C.dim; s.text:SetTextColor(c[1], c[2], c[3]) end)
        if tips and tips[i] then Tip(b, label, tips[i]) end
        f.btns[i] = b
    end
    f:SetWidth(2 + #labels * BW)
    f.Select = function(s, idx)
        for i, b in ipairs(s.btns) do
            b.on = (i == idx)
            b.bg:SetShown(b.on)
            local c = b.on and { 1, 1, 1 } or C.dim
            b.text:SetTextColor(c[1], c[2], c[3])
        end
    end
    f:Select(1)
    return f
end

local function ResetData()
    local dm = DM()
    local ok = dm and dm.ResetAllCombatSessions and pcall(dm.ResetAllCombatSessions)
    NZR:Print(ok and "DPS meter vidé." or "impossible de vider ici (utilise celui du compteur Blizzard).")
    C_Timer.After(0.1, Render)
end

local function CreateModeTabs(parent)
    local bar = CreateFrame("Frame", nil, parent)
    win.tabs = {}
    for i, m in ipairs(modes) do
        local t = CreateFrame("Button", nil, bar)
        t:SetHeight(SUB_H)
        t.text = NZR:Text(t, 10.5, C.dim, "CENTER", true)
        t.text:SetAllPoints()
        t.text:SetText(m.tab)
        t.line = t:CreateTexture(nil, "OVERLAY")
        t.line:SetColorTexture(MA[1], MA[2], MA[3], 1)
        t.line:SetHeight(2)
        t.line:SetPoint("BOTTOMLEFT", 4, 0); t.line:SetPoint("BOTTOMRIGHT", -4, 0)
        t.SetActive = function(s, on)
            s.active = on
            s.line:SetShown(on)
            local c = on and C.text or C.dim
            s.text:SetTextColor(c[1], c[2], c[3])
        end
        t:SetScript("OnClick", function() DB().meterMode = i; Render() end)
        t:SetScript("OnEnter", function(s) if not s.active then s.text:SetTextColor(MA2[1], MA2[2], MA2[3]) end end)
        t:SetScript("OnLeave", function(s) s:SetActive(s.active) end)
        Tip(t, m.label)
        win.tabs[i] = t
    end
    bar.Layout = function(self)
        local w = self:GetWidth() or 0
        local shown = {}
        for i, t in ipairs(win.tabs) do
            if ModeShown(i) then table.insert(shown, t) else t:Hide() end
        end
        if #shown == 0 or w <= 0 then return end
        local tw = w / #shown
        for i, t in ipairs(shown) do
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", self, "TOPLEFT", (i - 1) * tw, 0)
            t:SetWidth(tw)
            t:Show()
        end
    end
    bar:SetScript("OnSizeChanged", function(self) self:Layout() end)
    return bar
end

local function CreateWindow()
    win = CreateFrame("Frame", "NZRF_Meter", UIParent, "BackdropTemplate")
    win:SetFrameStrata("LOW")
    win:SetMovable(true)
    win:SetResizable(true)
    win:SetClampedToScreen(true)
    win:EnableMouse(true)
    if win.SetResizeBounds then win:SetResizeBounds(330, 100, 900, 700) end
    NZR:Skin(win, DB().meterAlpha or 0.92, nil, true)
    win:SetBackdropColor(P.win[1], P.win[2], P.win[3], DB().meterAlpha or 0.92)
    win:SetBackdropBorderColor(unpack(P.winEdge))
    if P.jeu then
        -- même cadre que les fenêtres du jeu et les réglages NZR Forever
        NZR:WowFrame(win, nil, DB().meterAlpha or 0.85)
        win:SetBackdropColor(0, 0, 0, 0)
        win:SetBackdropBorderColor(0, 0, 0, 0)
        win.nzrAlpha = 0
    end
    PlaceWin()

    -- en-tête
    local head = CreateFrame("Frame", nil, win, "BackdropTemplate")
    if P.jeu then
        head:SetPoint("TOPLEFT", 4, 0); head:SetPoint("TOPRIGHT", -4, 0)
        head:SetHeight(22)
    else
        head:SetPoint("TOPLEFT", 1, -1); head:SetPoint("TOPRIGHT", -1, -1)
        head:SetHeight(HEADER_H)
    end
    NZR:FlatBackdrop(head, false, 1)
    head:SetBackdropBorderColor(0, 0, 0, 0)
    head:EnableMouse(true)
    head:RegisterForDrag("LeftButton")
    head:SetScript("OnDragStart", function() if not DB().meterLock or NZR.editing then win:StartMoving() end end)
    head:SetScript("OnDragStop", function() win:StopMovingOrSizing(); SavePos() end)
    head:SetScript("OnMouseUp", function(_, btn)
        if btn == "RightButton" and NZR.ToggleOptions then NZR:ToggleOptions(true, "meter") end
    end)
    if not P.noir then NZR:AccentLine(win, "TOP", 2, 1) end
    local hsep = head:CreateTexture(nil, "ARTWORK")
    hsep:SetColorTexture(unpack(P.sep))
    hsep:SetHeight(1); hsep:SetPoint("BOTTOMLEFT"); hsep:SetPoint("BOTTOMRIGHT")

    local tagBox = CreateFrame("Frame", nil, head)
    tagBox:SetSize(1, 22); tagBox:SetPoint("LEFT", 2, 0)       -- plus de logo NZR : le titre commence à gauche
    NZR:FlatBackdrop(tagBox, true, 1, 5)
    tagBox:SetBackdropColor(unpack(P.tag))
    tagBox:SetBackdropBorderColor(unpack(P.tagEdge))
    tagBox:SetAlpha(0)

    win.title = NZR:Text(head, 12.5, nil, "LEFT", true)
    if P.jeu then win.title:SetFontObject(GameFontNormal); win.title:SetTextColor(1, 0.82, 0) end
    win.title:SetPoint("LEFT", tagBox, "RIGHT", 9, 0)
    win.clock = NZR:Text(head, 11.5, { 0.79, 0.76, 0.84 }, "RIGHT")
    win.clockIcon = Icon(head, "clock", 12, { 0.79, 0.76, 0.84 })

    local reset = CreateFrame("Button", nil, head)
    reset:SetSize(16, 16)
    reset:SetPoint("RIGHT", -9, 0)
    reset.icon = Icon(reset, "refresh", 15)
    reset.icon:SetAllPoints()
    reset:SetScript("OnEnter", function(s) s.icon:SetVertexColor(MA2[1], MA2[2], MA2[3]) end)
    reset:SetScript("OnLeave", function(s) s.icon:SetVertexColor(C.dim[1], C.dim[2], C.dim[3]) end)
    reset:SetScript("OnClick", ResetData)
    Tip(reset, "Vider le compteur", "Remet tous les combats à zéro.")

    win.segPill = Pill(head, { "Actuel", "Global" }, function(i)
        DB().meterOverall = (i == 2); Render()
    end, { "Le combat en cours ou le dernier.", "Tous les combats depuis la dernière remise à zéro." })
    win.segPill:SetPoint("RIGHT", reset, "LEFT", -9, 0)
    local minBtn = CreateFrame("Button", nil, head)
    minBtn:SetSize(16, 16)
    minBtn.icon = minBtn:CreateTexture(nil, "OVERLAY")
    minBtn.icon:SetSize(10, 2); minBtn.icon:SetPoint("CENTER", 0, -3)
    minBtn.icon:SetColorTexture(1, 1, 1, 1)
    minBtn.icon:SetVertexColor(C.dim[1], C.dim[2], C.dim[3])
    minBtn:SetScript("OnEnter", function(s) s.icon:SetVertexColor(MA2[1], MA2[2], MA2[3]) end)
    minBtn:SetScript("OnLeave", function(s) s.icon:SetVertexColor(C.dim[1], C.dim[2], C.dim[3]) end)
    minBtn:SetScript("OnClick", function()
        DB().meterMin = true
        win:Hide()
        ShowMini(true)
    end)
    Tip(minBtn, "Réduire le meter", "Le meter devient une petite icône. Clique dessus pour le rouvrir.")
    local gear = CreateFrame("Button", nil, head)
    gear:SetSize(16, 16)
    minBtn:SetPoint("RIGHT", reset, "LEFT", -6, 0)
    gear:SetPoint("RIGHT", minBtn, "LEFT", -6, 0)
    gear.icon = Icon(gear, "m_gear", 15)
    gear.icon:SetAllPoints()
    gear:SetScript("OnEnter", function(s) s.icon:SetVertexColor(MA2[1], MA2[2], MA2[3]) end)
    gear:SetScript("OnLeave", function(s) s.icon:SetVertexColor(C.dim[1], C.dim[2], C.dim[3]) end)
    gear:SetScript("OnClick", function() if NZR.ToggleOptions then NZR:ToggleOptions(true, "meter") end end)
    Tip(gear, "Réglages du meter", "Disposition (Détaillé, Tableau, Barres), infos affichées, couleurs…")
    win.segPill:ClearAllPoints()
    win.segPill:SetPoint("RIGHT", gear, "LEFT", -9, 0)
    win.viewPill = { Select = function() end }
    Tip(head, "DPS meter NZR", "Glisser : déplacer. Clic droit : réglages du meter.")
    win.clock:SetPoint("RIGHT", win.segPill, "LEFT", -10, 0)
    win.clockIcon:SetPoint("RIGHT", win.clock, "LEFT", -4, 0)
    win.title:SetPoint("RIGHT", win.clockIcon, "LEFT", -8, 0)

    -- sous-en-tête : colonnes (Tableau) ou onglets de modes (Barres)
    win.colHead = CreateColumnHeader(win)
    win.colHead:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, 0)
    win.colHead:SetPoint("TOPRIGHT", head, "BOTTOMRIGHT", 0, 0)
    win.colHead:SetHeight(SUB_H)
    win.tgt = CreateFrame("Frame", nil, win)
    win.tgt:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 7, 0)
    win.tgt:SetPoint("TOPRIGHT", head, "BOTTOMRIGHT", -7, 0)
    win.tgt:SetHeight(SUB_H)
    win.tgt.inner = CreateFrame("Frame", nil, win.tgt)
    win.tgt.inner:SetAllPoints()
    -- vie de la cible : barre aux coins légèrement arrondis, texte dedans
    local box = CreateFrame("Frame", nil, win.tgt.inner)
    box:SetPoint("TOPLEFT", 0, -4); box:SetPoint("TOPRIGHT", 0, -4); box:SetHeight(17)
    NZR:FlatBackdrop(box, true, 1, 3)
    box:SetBackdropColor(0.04, 0.035, 0.05, 0.85)
    box:SetBackdropBorderColor(unpack(P.meEdge or P.cardEdge))
    local tb = CreateFrame("StatusBar", nil, box)
    tb:SetPoint("TOPLEFT", 2, -2); tb:SetPoint("BOTTOMRIGHT", -2, 2)     -- dans le bord arrondi
    tb:SetStatusBarTexture(NZR.TEX)
    tb:GetStatusBarTexture():SetGradient("HORIZONTAL", CreateColor(0.80, 0.16, 0.14, 1), CreateColor(0.62, 0.10, 0.09, 1))
    local shine = tb:CreateTexture(nil, "OVERLAY")
    shine:SetPoint("TOPLEFT", 2, 0); shine:SetPoint("TOPRIGHT", -2, 0); shine:SetHeight(1)
    shine:SetColorTexture(1, 1, 1, 0.12)
    win.tgt.bar = tb
    local txt = CreateFrame("Frame", nil, box)
    txt:SetAllPoints(); txt:SetFrameLevel(tb:GetFrameLevel() + 2)
    win.tgt.left = NZR:Text(txt, 10.5, nil, "LEFT", true)
    win.tgt.left:SetPoint("LEFT", 7, 0)
    win.tgt.right = NZR:Text(txt, 10.5, nil, "RIGHT", true)
    win.tgt.right:SetPoint("RIGHT", -7, 0)
    win.tgt:Hide()

    win.tabsBar = CreateModeTabs(win)
    win.tabsBar:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, 0)
    win.tabsBar:SetPoint("TOPRIGHT", head, "BOTTOMRIGHT", 0, 0)
    win.tabsBar:SetHeight(SUB_H)
    local ssep = win:CreateTexture(nil, "ARTWORK")
    ssep:SetColorTexture(0.114, 0.098, 0.149, 1)
    ssep:SetHeight(1)
    ssep:SetPoint("TOPLEFT", win.colHead, "BOTTOMLEFT"); ssep:SetPoint("TOPRIGHT", win.colHead, "BOTTOMRIGHT")
    win.ssep = ssep

    -- corps
    win.body = CreateFrame("Frame", nil, win)
    win.empty = NZR:Text(win.body, 11, C.dim, "CENTER")
    win.empty:SetPoint("CENTER", 0, 4)
    win.empty:SetText("En attente de combat…")
    win.note = NZR:Text(win.body, 10, C.dim, "RIGHT")
    win.note:SetPoint("BOTTOMRIGHT", -4, 2)
    win.note:SetText("Vue Barres pendant le combat")

    -- pied : total du groupe
    local foot = CreateFrame("Frame", nil, win)
    foot:SetPoint("BOTTOMLEFT", 1, 1); foot:SetPoint("BOTTOMRIGHT", -1, 1)
    foot:SetHeight(FOOTER_H)
    local fbg = foot:CreateTexture(nil, "BACKGROUND")
    fbg:SetColorTexture(1, 1, 1, 0.06)
    fbg:SetHeight(1); fbg:SetPoint("TOPLEFT", 8, 0); fbg:SetPoint("TOPRIGHT", -8, 0)
    win.foot = foot
    win.footLabel = NZR:Text(foot, 11, nil, "LEFT")
    win.footLabel:SetPoint("LEFT", 10, 0)
    win.footCells = {}
    for ci, col in ipairs(cols) do
        win.footCells[ci] = NZR:Text(foot, col.big and 12 or 11, col.text or C.text, "RIGHT", true)
    end
    win.count = NZR:Text(foot, 10.5, C.dim, "RIGHT")

    local grip = CreateFrame("Button", nil, win)
    grip:SetSize(10, 10)
    grip:SetPoint("BOTTOMRIGHT", -1, 1)
    grip:SetFrameLevel(foot:GetFrameLevel() + 3)
    local gt = grip:CreateTexture(nil, "OVERLAY")
    gt:SetAllPoints()
    gt:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    gt:SetVertexColor(MA[1], MA[2], MA[3], 0.6)
    grip:SetScript("OnMouseDown", function() if not DB().meterLock or NZR.editing then win:StartSizing("BOTTOMRIGHT") end end)
    grip:SetScript("OnMouseUp", function() win:StopMovingOrSizing(); SavePos(); Render() end)
    win.grip = grip
    win:SetScript("OnSizeChanged", function() Render() end)

    ApplySize()
end

local METER_DEFAULTS = {
    meterView = "cards", meterSort = "dps", meterTargetBar = true, meterCardFill = true, meterRowSize = "normal", meterBarColor = "class",
    meterIcons = true, meterCrown = true, meterRank = true, meterShare = true, meterFooter = true,
    meterTheme = "jeu", meterAlpha = 0.85, meterAuto = false, meterLock = false,
}

function M:Init()
    SetupPalette()
    for k, v in pairs(METER_DEFAULTS) do
        if NZR.db[k] == nil then NZR.db[k] = v end
    end
    if (NZR.db.meterV09 or 0) < 1 then           -- passage au style Meterion
        NZR.db.meterV09 = 1
        NZR.db.meterView = "cards"
        NZR.db.meterSort = "dps"
    end
    if type(NZR.db.meterInfo) ~= "table" then
        NZR.db.meterInfo = {}
        for k, v in pairs(DEFAULT_INFO) do NZR.db.meterInfo[k] = v end
    end
    if type(NZR.db.meterCols) ~= "table" then
        NZR.db.meterCols = {}
        for k, v in pairs(DEFAULT_COLS) do NZR.db.meterCols[k] = v end
    end
    if not NZR.db.meter then return end

    if win then return end          -- jamais deux fois
    wipe(modes); wipe(cols)
    local dm = DM()
    if dm and Enum.DamageMeterType then
        for _, m in ipairs(MODES) do
            if Enum.DamageMeterType[m.key] ~= nil then table.insert(modes, m) end
        end
        for _, c in ipairs(COLUMNS) do
            if Enum.DamageMeterType[c.type] ~= nil then
                c.available = true
                table.insert(cols, c)
            end
        end
    end
    ComputeVisible()

    CreateWindow()
    NZR.ResetMeterData = ResetData
    NZR.ResetMeterPos = function() DB().pos.meter = nil; PlaceWin() end
    NZR.MeterRefresh = function(resize) ApplySettings(resize) end
    NZR.MeterApplySize = function() ApplySize(); Render() end
    win.lock = NZR:AddLock(win, {
        get = function() return DB().meterLock end,
        set = function(v) DB().meterLock = v; ApplySettings(false) end,
    })
    ApplySettings(false)

    if #modes == 0 then
        win.empty:SetText("API du compteur introuvable\n(C_DamageMeter)")
        return
    end

    local ev = CreateFrame("Frame")
    for _, e in ipairs({ "DAMAGE_METER_COMBAT_SESSION_UPDATED", "DAMAGE_METER_CURRENT_SESSION_UPDATED",
                         "DAMAGE_METER_RESET", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
                         "PLAYER_ENTERING_WORLD", "GROUP_ROSTER_UPDATE", "PLAYER_TARGET_CHANGED" }) do
        pcall(ev.RegisterEvent, ev, e)
    end
    local pending = false
    ev:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:SetScript("OnEvent", function(_, e)
        if e == "EDIT_MODE_LAYOUTS_UPDATED" or e == "PLAYER_ENTERING_WORLD" then
            -- le jeu (re)pose ses barres : on remet les nôtres d'origine, puis on redécale un peu après
            if e == "EDIT_MODE_LAYOUTS_UPDATED" then shifted = nil      -- le jeu a déjà tout replacé
            elseif shifted and not InCombatLockdown() then ShiftBars(false) end
            shiftReady = false
            C_Timer.After(e == "PLAYER_ENTERING_WORLD" and 2 or 0.5, function()
                shiftReady = true
                if mini then mini.nzrDocked = nil end
                ShowMini(DB().meterMin and true or false)
            end)
        end
        if e == "PLAYER_REGEN_ENABLED" or e == "PLAYER_REGEN_DISABLED" then lastCombat = GetTime() end
        UpdateVisibility()
        if pending then return end
        pending = true
        C_Timer.After(0.15, function() pending = false; Render() end)
    end)
    C_Timer.NewTicker(0.5, function() UpdateVisibility(); Render() end)
    UpdateVisibility()
    Render()
end
