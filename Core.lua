-- NZR Forever - Core : palette, helpers, positions, commandes
local ADDON, NZR = ...
_G.NZRF = NZR

NZR.version = "1.0.4"
NZR.TEX  = "Interface\\Buttons\\WHITE8x8"
NZR.FONT      = "Interface\\AddOns\\NZRForever\\Fonts\\Inter-Medium.ttf"
NZR.FONT_BOLD = "Interface\\AddOns\\NZRForever\\Fonts\\Inter-SemiBold.ttf"

-- Palette NZR : fond très sombre, bordure discrète, touche de violet
NZR.C = {
    bg      = { 0.043, 0.039, 0.063, 0.86 },
    bg2     = { 0.070, 0.062, 0.095, 0.95 },
    border  = { 0.141, 0.122, 0.184, 1 },
    accent  = { 0.608, 0.420, 0.949, 1 },   -- #9b6bf2
    accent2 = { 0.780, 0.640, 1.000, 1 },   -- lavande (canalisations)
    text    = { 0.920, 0.905, 0.950 },
    dim     = { 0.600, 0.580, 0.660 },
    red     = { 0.900, 0.250, 0.300 },
    grey    = { 0.550, 0.550, 0.580 },
}

local defaults = {
    theme = false, auras = false, tooltips = false, tooltipCursor = false, moveTooltip = false, moveBags = false, moveMap = false, moveWindows = true, squareMinimap = false, compass = false, paladin = false, questHL = false, unitFrames = false, plates = false, npText = "both", npColor = "game", ufPortrait = "round", ufText = "both", ufName = "full", ufColor = "green", ufShort = true, ufScale = 1, ufFont = "game", ufFontSize = 1, ufOutline = "shadow", ufHealthShade = 1, ufPowerColor = "game", ufPowerShade = 1, ufAuras = true, groupFrames = false, guide = false, guideAuto = true, sct = false, sctIn = true, sctOut = true, sctHeal = true, sctNotice = true, sctHideBlizz = true, sctSize = 1, sctOthers = false, sctPower = true, sctKill = true, sctFont = "game", meterShiftBars = false, reopenWindows = false, mmButtonsSave = false, meterShiftBuffs = true, meterShiftCD = true, grpPartyStyle = "big", grpColor = "class", grpNameColor = "default", grpName = "full", grpText = "auto", grpPower = true, grpRole = true, grpDebuffs = true, grpDebuffAll = false, grpBuffs = "mine", grpCellScale = 1, grpScale = 1, grpAlpha = 0.9, npFont = "game", npFontSize = 1, npOutline = "game", hlStyle = "ping", hlColor = "gold", hlSize = 1, hlObjects = true, hlNPCs = true, hlMobs = true, hlCombat = true, hlSound = false, blessGreater = true, blessSolo = true, blessLock = false, blessScale = 1, menuButton = true, tooltipOpaque = true, tooltipAlpha = 1, lootAll = true, lootAutoClose = true, lootKey = "E",
    accent = "violet", font = "inter", damageFont = false,
    meter = true, meterMode = 1, meterOverall = false, meterW = 300, meterH = 180,
    scale = 1, opacity = 1,
    pos = {}, panelPos = {},
}

---------------------------------------------------------------------------
-- Valeurs secrètes (WoW Forever / Midnight) : on n'en fait jamais de calcul,
-- on les passe directement aux barres et aux textes.
---------------------------------------------------------------------------
local issecret = issecretvalue or function() return false end
NZR.issecret = issecret

function NZR.plain(v)            -- vraie valeur lisible et non nil
    if issecret(v) then return false end
    return v ~= nil
end

function NZR.Abbrev(v, rate)
    if not issecret(v) and v == nil then return "" end
    -- valeur secrète "par seconde" : une décimale (sinon le jeu l'affiche brute)
    if rate and issecret(v) then
        local ok, s = pcall(string.format, "%.1f", v)
        if ok and s ~= nil then return s end
    end
    if not issecret(v) and type(v) ~= "number" then return tostring(v) end
    -- nombre lisible : on l'arrondit nous-mêmes (pas de 0.8562874251497)
    if not issecret(v) then
        if v < 100 then return (("%.1f"):format(v):gsub("%.0$", "")) end
        if v < 10000 then return ("%d"):format(math.floor(v + 0.5)) end
        if v < 1e6 then return (("%.1fk"):format(v / 1e3):gsub("%.0k$", "k")) end
        return (("%.2fM"):format(v / 1e6))
    end
    local ok, s = pcall(AbbreviateNumbers, v)
    if ok and s ~= nil then return s end
    ok, s = pcall(AbbreviateLargeNumbers, v)
    if ok and s ~= nil then return s end
    return v
end

function NZR.SafeText(fs, v)
    if not pcall(fs.SetText, fs, v) then fs:SetText("") end
end

function NZR:Print(msg)
    print("|cff9b6bf2NZR|r " .. msg)
end

---------------------------------------------------------------------------
-- Helpers visuels
---------------------------------------------------------------------------
NZR.skinned = {}

-- opacité globale des fonds (fenêtre d'options)
function NZR:ApplyOpacity()
    local o = NZRF_DB.opacity or 1
    for _, f in ipairs(self.skinned) do
        local r, g, b = f:GetBackdropColor()
        f:SetBackdropColor(r, g, b, math.min(1, f.nzrAlpha * o))
    end
end

-- taille des cadres NZR (joueur, cible, incantations)
function NZR:ApplyScale()
    if InCombatLockdown() then self.pendingScale = true; return end
    self.pendingScale = false
    local s = NZRF_DB.scale or 1
    for _, f in ipairs({ self.playerFrame, self.targetFrame, self.playerCast, self.targetCast }) do
        if f then f:SetScale(s) end
    end
    for _, hd in pairs(self.holders) do
        if hd.scaled ~= false then hd:SetSize(hd.baseW * s, hd.baseH * s) end
    end
end

-- Fond + bordure en simples textures. On n'utilise plus le système de fond du jeu
-- (BackdropTemplate) : il recalcule ses bords à chaque changement de taille et
-- plante quand la taille dépend d'un texte "secret" en combat.
-- rounded = coins arrondis (texture 9-slice), sinon bords nets de 1 px.
local MEDIA_PATH = "Interface\\AddOns\\NZRForever\\Media\\"

-- coins arrondis : 3 (petits éléments), 5 (cadres, barres), 8 (fenêtres)
local RADII = { [3] = 4, [5] = 6, [8] = 9 }
local function radiusOf(rounded)
    if rounded == true then return 8 end
    if type(rounded) == "number" then
        if rounded <= 3 then return 3 elseif rounded <= 5 then return 5 end
        return 8
    end
end
NZR.radiusOf = radiusOf

local function slice(t, file, m)
    t:SetTexture(MEDIA_PATH .. file)
    if t.SetTextureSliceMargins then
        m = m or 9
        t:SetTextureSliceMargins(m, m, m, m)
        if t.SetTextureSliceMode then
            pcall(t.SetTextureSliceMode, t, (Enum.UITextureSliceMode and Enum.UITextureSliceMode.Stretched) or 0)
        end
        return true
    end
    return false
end

function NZR:FlatBackdrop(f, withBg, edge, rounded)
    if f.nzrFlat then return f end
    f.nzrFlat = true
    edge = edge or 1
    local bg = f:CreateTexture(nil, "BACKGROUND", nil, -8)
    local edges = {}
    local rad = radiusOf(rounded)
    local roundOK = rad and bg.SetTextureSliceMargins ~= nil
    if roundOK then
        slice(bg, "r" .. rad .. "_fill", RADII[rad])
        bg:SetAllPoints()
        local e = f:CreateTexture(nil, "BACKGROUND", nil, -7)
        slice(e, "r" .. rad .. "_edge", RADII[rad])
        e:SetAllPoints()
        edges[1] = e
    else
        bg:SetTexture(self.TEX)
        bg:SetAllPoints()
        local function line(p1, p2, horiz)
            local t = f:CreateTexture(nil, "BACKGROUND", nil, -7)
            t:SetTexture(self.TEX)
            t:SetPoint(p1); t:SetPoint(p2)
            if horiz then t:SetHeight(edge) else t:SetWidth(edge) end
            table.insert(edges, t)
        end
        line("TOPLEFT", "TOPRIGHT", true)
        line("BOTTOMLEFT", "BOTTOMRIGHT", true)
        line("TOPLEFT", "BOTTOMLEFT", false)
        line("TOPRIGHT", "BOTTOMRIGHT", false)
    end
    bg:SetShown(withBg ~= false)
    f.nzrBgTex, f.nzrEdges, f.nzrRounded = bg, edges, roundOK and rad or nil
    f.nzrBgC, f.nzrEdgeC = { 0, 0, 0, 0.8 }, { 0, 0, 0, 1 }
    bg:SetVertexColor(0, 0, 0, 0.8)
    for _, t in ipairs(edges) do t:SetVertexColor(0, 0, 0, 1) end
    f.SetBackdropColor = function(s, r, g, b, a)
        s.nzrBgC = { r, g, b, a or 1 }
        s.nzrBgTex:SetVertexColor(r, g, b, a or 1)
    end
    f.GetBackdropColor = function(s) local c = s.nzrBgC; return c[1], c[2], c[3], c[4] end
    f.SetBackdropBorderColor = function(s, r, g, b, a)
        s.nzrEdgeC = { r, g, b, a or 1 }
        for _, t in ipairs(s.nzrEdges) do t:SetVertexColor(r, g, b, a or 1) end
    end
    f.GetBackdropBorderColor = function(s) local c = s.nzrEdgeC; return c[1], c[2], c[3], c[4] end
    f.SetBackdrop = function() end      -- appels oubliés : sans effet
    return f
end

-- texture arrondie (9-slice) : bords des barres, cases…
function NZR:RoundTex(t, radius, r, g, b, a)
    local rad = radiusOf(radius or 3)
    if not slice(t, "r" .. rad .. "_fill", RADII[rad]) then t:SetTexture(self.TEX) end
    if r then t:SetVertexColor(r, g, b, a or 1) end
    return t
end

-- masque à coins arrondis (icônes, cases d'objets, boutons d'action)
function NZR:RoundMask(parent, anchor, inset)
    if not parent.CreateMaskTexture then return end
    local m = parent:CreateMaskTexture()
    m:SetTexture(MEDIA_PATH .. "r3_fill", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    inset = inset or 0
    m:SetPoint("TOPLEFT", anchor or parent, "TOPLEFT", inset, -inset)
    m:SetPoint("BOTTOMRIGHT", anchor or parent, "BOTTOMRIGHT", -inset, inset)
    return m
end

function NZR:Mask(m, ...)
    if not m then return end
    for i = 1, select("#", ...) do
        local t = select(i, ...)
        if t and t.AddMaskTexture then pcall(t.AddMaskTexture, t, m) end
    end
end

-- bouton carré (action, sac, aura) : coins arrondis sur tout ce qu'il affiche
function NZR:RoundButton(b, outer, inner)
    local mo = self:RoundMask(b, b, 0)
    local mi = self:RoundMask(b, b, 1)
    self:Mask(mo, unpack(outer or {}))
    self:Mask(mi, unpack(inner or {}))
    b.nzrMaskOuter, b.nzrMaskInner = mo, mi
    return mo, mi
end

-- cadre comme les fenêtres du jeu (et la fenêtre des réglages NZR Forever) :
-- fond de pierre sombre, bord en métal avec barre de titre, titre doré
-- Cadre des fenêtres du jeu (même que le meter et les réglages) : fond de pierre,
-- bord en métal avec barre de titre, titre doré. scale < 1 = même cadre en réduit
-- (pour les petits éléments : coins plus petits, rien ne dépasse).
function NZR:WowFrame(f, title, alpha, scale)
    local host = f
    if scale and scale < 1 then
        host = CreateFrame("Frame", nil, f)
        host:SetScale(scale)
        host:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
        local function size()
            local w, h = f:GetSize()
            if w and h then host:SetSize(w / scale, h / scale) end
        end
        size()
        f:HookScript("OnSizeChanged", size)
        host:SetFrameLevel(f:GetFrameLevel())
    end
    local bg = host:CreateTexture(nil, "BACKGROUND", nil, -7)
    bg:SetTexture("Interface\\FrameGeneral\\UI-Background-Rock", "REPEAT", "REPEAT")
    bg:SetHorizTile(true); bg:SetVertTile(true)
    bg:SetPoint("TOPLEFT", 2, -21); bg:SetPoint("BOTTOMRIGHT", -2, 2)
    bg:SetAlpha(alpha or 1)
    local dark = host:CreateTexture(nil, "BACKGROUND", nil, -8)
    dark:SetPoint("TOPLEFT", 2, -2); dark:SetPoint("BOTTOMRIGHT", -2, 2)
    dark:SetColorTexture(0, 0, 0, (alpha or 1) * 0.6)
    local ns = CreateFrame("Frame", nil, host, "NineSlicePanelTemplate")
    ns:SetAllPoints()
    ns:SetFrameLevel(host:GetFrameLevel() + 1)
    local ok = NineSliceUtil and pcall(NineSliceUtil.ApplyLayoutByName, ns, "ButtonFrameTemplateNoPortrait")
    if not ok and NineSliceUtil then pcall(NineSliceUtil.ApplyLayoutByName, ns, "TooltipDefaultLayout") end
    if ns.Center then ns.Center:Hide() end
    -- tout ce qu'on pose ensuite passe au-dessus du bord
    local over = CreateFrame("Frame", nil, f)
    over:SetAllPoints()
    over:SetFrameLevel(ns:GetFrameLevel() + 2)
    local t
    if title then
        t = over:CreateFontString(nil, "OVERLAY", scale and scale < 1 and "GameFontNormalSmall" or "GameFontNormal")
        t:SetPoint("TOP", 0, -5 * (scale or 1))
        t:SetText(title)
    end
    f.nzrRock, f.nzrDark, f.nzrMetal, f.nzrTitle, f.nzrOver = bg, dark, ns, t, over
    return over, t
end

function NZR:WowFrameAlpha(f, a)
    if f.nzrRock then f.nzrRock:SetAlpha(a) end
    if f.nzrDark then f.nzrDark:SetAlpha(1); f.nzrDark:SetColorTexture(0, 0, 0, a * 0.6) end
end

function NZR:Skin(f, alpha, noBorder, rounded)
    self:FlatBackdrop(f, true, 1, rounded)
    local c = self.C
    f.nzrAlpha = alpha or c.bg[4]
    if not f.nzrSkinned then
        f.nzrSkinned = true
        table.insert(self.skinned, f)
    end
    f:SetBackdropColor(c.bg[1], c.bg[2], c.bg[3], f.nzrAlpha * ((NZRF_DB and NZRF_DB.opacity) or 1))
    if noBorder then
        f:SetBackdropBorderColor(0, 0, 0, 0)
    else
        f:SetBackdropBorderColor(c.border[1], c.border[2], c.border[3], 1)
    end
end

-- bande de couleur en haut d'un cadre arrondi (coins du haut arrondis, bas droit)
function NZR:RoundTop(f, height, r, g, b, a)
    local top = f:CreateTexture(nil, "BACKGROUND", nil, -6)
    local ok = slice(top, "r8_fill", 9)
    top:SetPoint("TOPLEFT", 1, -1); top:SetPoint("TOPRIGHT", -1, -1)
    top:SetHeight(height)
    top:SetVertexColor(r, g, b, a or 1)
    if ok then
        local cover = f:CreateTexture(nil, "BACKGROUND", nil, -5)
        cover:SetTexture(self.TEX)
        cover:SetVertexColor(r, g, b, a or 1)
        cover:SetPoint("BOTTOMLEFT", top, "BOTTOMLEFT"); cover:SetPoint("BOTTOMRIGHT", top, "BOTTOMRIGHT")
        cover:SetHeight(math.min(12, height / 2))
    else
        top:SetTexture(self.TEX); top:SetVertexColor(r, g, b, a or 1)
    end
    return top
end

-- Liseré violet qui s'estompe (signature NZR)
-- trait avec un fondu doux à chaque bout. Renvoie un repère invisible : on peut
-- le replacer (SetPoint), le recolorer (SetGradient) ou le cacher comme une texture.
function NZR:FadeLine(parent, layer, sub)
    local t = parent:CreateTexture(nil, layer or "OVERLAY", nil, sub or 7)
    t:SetTexture(self.TEX)
    t:SetVertexColor(0, 0, 0, 0)
    local mid = parent:CreateTexture(nil, layer or "OVERLAY", nil, sub or 7)
    local l = parent:CreateTexture(nil, layer or "OVERLAY", nil, sub or 7)
    local r = parent:CreateTexture(nil, layer or "OVERLAY", nil, sub or 7)
    for _, p in ipairs({ mid, l, r }) do p:SetTexture(self.TEX) end
    local F = 30
    local function place()
        l:ClearAllPoints(); r:ClearAllPoints(); mid:ClearAllPoints()
        l:SetPoint("TOPLEFT", t, "TOPLEFT"); l:SetPoint("BOTTOMLEFT", t, "BOTTOMLEFT"); l:SetWidth(F)
        r:SetPoint("TOPRIGHT", t, "TOPRIGHT"); r:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT"); r:SetWidth(F)
        mid:SetPoint("TOPLEFT", l, "TOPRIGHT"); mid:SetPoint("BOTTOMRIGHT", r, "BOTTOMLEFT")
    end
    place()
    -- longueur du fondu : environ 18 % de la largeur, entre 8 et 70 px
    parent:HookScript("OnSizeChanged", function(_, w)
        if type(w) ~= "number" or issecretvalue and issecretvalue(w) then return end
        local nf = math.max(8, math.min(70, math.floor(w * 0.18)))
        if nf ~= F then F = nf; l:SetWidth(F); r:SetWidth(F) end
    end)
    t.SetGradient = function(_, _, c1, c2)
        local function rgba(c)
            if c.GetRGBA then return c:GetRGBA() end
            return c.r or c[1] or 1, c.g or c[2] or 1, c.b or c[3] or 1, c.a or c[4] or 1
        end
        local r1, g1, b1 = rgba(c1)
        local r2, g2, b2 = rgba(c2)
        mid:SetGradient("HORIZONTAL", c1, c2)
        l:SetGradient("HORIZONTAL", CreateColor(r1, g1, b1, 0), c1)
        r:SetGradient("HORIZONTAL", c2, CreateColor(r2, g2, b2, 0))
    end
    local hide, show = t.Hide, t.Show
    t.Hide = function(s) hide(s); mid:Hide(); l:Hide(); r:Hide() end
    t.Show = function(s) show(s); mid:Show(); l:Show(); r:Show() end
    t.SetShown = function(s, v) if v then s:Show() else s:Hide() end end
    return t
end

function NZR:AccentLine(f, where, height, alpha)
    local t = self:FadeLine(f)
    t:SetHeight(height or 1)
    local y = (where == "BOTTOM") and 1 or -1
    local x = f.nzrRounded and (f.nzrRounded + 2) or 1      -- sur un cadre arrondi, le liseré évite les coins
    t:SetPoint(where .. "LEFT", f, where .. "LEFT", x, y)
    t:SetPoint(where .. "RIGHT", f, where .. "RIGHT", -x, y)
    local a, b2 = self.C.accent, self.C.accent2
    t:SetGradient("HORIZONTAL", CreateColor(a[1], a[2], a[3], alpha or 0.95), CreateColor(b2[1], b2[2], b2[3], alpha or 0.95))
    return t
end

function NZR:Text(parent, size, color, justify, bold)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    if not fs:SetFont(bold and self.FONT_BOLD or self.FONT, size or 12, "") then
        fs:SetFont(STANDARD_TEXT_FONT, size or 12, "")
    end
    fs:SetShadowColor(0, 0, 0, 0.95)
    fs:SetShadowOffset(1, -1)
    local c = color or self.C.text
    fs:SetTextColor(c[1], c[2], c[3])
    fs:SetJustifyH(justify or "LEFT")
    fs:SetWordWrap(false)
    return fs
end

-- polices de boutons NZR (le jeu les remet à chaque changement d'état : on fournit les nôtres)
function NZR:ButtonFonts()
    if self.fontBtn then return self.fontBtn, self.fontBtnHi, self.fontBtnOff end
    local n = CreateFont("NZRF_FontButton")
    n:SetFont(self.FONT_BOLD, 12, ""); n:SetTextColor(self.C.text[1], self.C.text[2], self.C.text[3]); n:SetShadowOffset(1, -1)
    local h = CreateFont("NZRF_FontButtonHi")
    h:SetFont(self.FONT_BOLD, 12, ""); h:SetTextColor(1, 1, 1); h:SetShadowOffset(1, -1)
    local d = CreateFont("NZRF_FontButtonOff")
    d:SetFont(self.FONT_BOLD, 12, ""); d:SetTextColor(0.42, 0.40, 0.48); d:SetShadowOffset(1, -1)
    self.fontBtn, self.fontBtnHi, self.fontBtnOff = n, h, d
    return n, h, d
end

function NZR:ApplyButtonFonts(b)
    local n, h, d = self:ButtonFonts()
    if b.SetNormalFontObject then
        pcall(b.SetNormalFontObject, b, n)
        pcall(b.SetHighlightFontObject, b, h)
        pcall(b.SetDisabledFontObject, b, d)
    end
end

function NZR:Bar(parent)
    local b = CreateFrame("StatusBar", nil, parent)
    b:SetStatusBarTexture(self.TEX)
    b:SetMinMaxValues(0, 1)
    b:SetValue(0)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.bg:SetColorTexture(0.025, 0.022, 0.035, 0.92)
    -- léger reflet sur la moitié haute
    b.shine = b:CreateTexture(nil, "OVERLAY")
    b.shine:SetTexture(self.TEX)
    b.shine:SetPoint("TOPLEFT")
    b.shine:SetPoint("TOPRIGHT")
    b.shine:SetPoint("BOTTOM", b, "CENTER")
    b.shine:SetGradient("VERTICAL", CreateColor(1, 1, 1, 0), CreateColor(1, 1, 1, 0.07))
    return b
end

function NZR:SetBarColor(b, r, g, bl, a)
    local t = b:GetStatusBarTexture()
    if t then
        t:SetGradient("VERTICAL", CreateColor(r * 0.55, g * 0.55, bl * 0.55, a or 1), CreateColor(r, g, bl, a or 1))
    end
end

-- Cadre 1px autour d'une texture (icônes)
function NZR:IconBorder(parent, icon)
    local bd = parent:CreateTexture(nil, "BACKGROUND", nil, -7)
    self:RoundTex(bd, 3, self.C.border[1], self.C.border[2], self.C.border[3], 1)
    self:Mask(self:RoundMask(parent, icon, 0), icon)
    bd:SetPoint("TOPLEFT", icon, "TOPLEFT", -1, 1)
    bd:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 1, -1)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    return bd
end

---------------------------------------------------------------------------
-- Ancres déplaçables (/nzr unlock)
---------------------------------------------------------------------------
NZR.holders = {}

local function SaveHolder(hd)
    local p, _, rp, x, y = hd:GetPoint()
    NZRF_DB.pos[hd.key] = { p, rp, x, y }
end

function NZR:PlaceHolder(hd)
    local p = NZRF_DB.pos[hd.key] or hd.default
    hd:ClearAllPoints()
    hd:SetPoint(p[1], UIParent, p[2], p[3], p[4])
end

function NZR:Holder(key, label, w, h, default)
    local hd = CreateFrame("Frame", "NZRF_Holder_" .. key, UIParent, "BackdropTemplate")
    hd:SetSize(w, h)
    hd.baseW, hd.baseH = w, h
    hd:SetMovable(true)
    hd:SetClampedToScreen(true)
    hd:SetFrameStrata("DIALOG")
    hd:RegisterForDrag("LeftButton")
    hd.key, hd.default = key, default
    self:FlatBackdrop(hd, true, 1, 5)
    hd.label = self:Text(hd, 11, nil, "CENTER")
    hd.label:SetPoint("CENTER")
    hd.label:SetText(label)
    hd:SetScript("OnDragStart", hd.StartMoving)
    hd:SetScript("OnDragStop", function(s) s:StopMovingOrSizing(); SaveHolder(s) end)
    self:PlaceHolder(hd)
    self.holders[key] = hd
    self:ShowHolder(hd, false)
    return hd
end

function NZR:ShowHolder(hd, show)
    if show then
        -- bloc doré, comme le jeu (mode édition)
        hd:SetBackdropColor(1, 0.82, 0, 0.18)
        hd:SetBackdropBorderColor(1, 0.82, 0, 1)
        hd.label:Show()
        hd:EnableMouse(true)
    else
        hd:SetBackdropColor(0, 0, 0, 0)
        hd:SetBackdropBorderColor(0, 0, 0, 0)
        hd.label:Hide()
        hd:EnableMouse(false)
    end
end

---------------------------------------------------------------------------
-- Mode édition NZR : tout ce qui se déplace s'affiche d'un coup, avec une barre
-- d'outils (grille, positions par défaut, terminer). /nzr edit, ou l'onglet Édition.
---------------------------------------------------------------------------
local editBar, editGrid

local function BuildGrid()
    editGrid = CreateFrame("Frame", nil, UIParent)
    editGrid:SetAllPoints(); editGrid:SetFrameStrata("BACKGROUND"); editGrid:Hide()
    local step = 40
    local w, h = UIParent:GetWidth(), UIParent:GetHeight()
    local function line(vertical, off, center)
        local t = editGrid:CreateTexture(nil, "OVERLAY")
        if center then t:SetColorTexture(1, 0.82, 0, 0.45) else t:SetColorTexture(1, 1, 1, 0.08) end
        if vertical then
            t:SetWidth(center and 2 or 1); t:SetPoint("TOP", editGrid, "TOP", off, 0); t:SetPoint("BOTTOM", editGrid, "BOTTOM", off, 0)
        else
            t:SetHeight(center and 2 or 1); t:SetPoint("LEFT", editGrid, "LEFT", 0, off); t:SetPoint("RIGHT", editGrid, "RIGHT", 0, off)
        end
    end
    for x = 0, w / 2, step do line(true, x, x == 0); if x > 0 then line(true, -x) end end
    for y = 0, h / 2, step do line(false, y, y == 0); if y > 0 then line(false, -y) end end
end

local function BuildBar()
    editBar = CreateFrame("Frame", "NZRF_EditBar", UIParent)
    editBar:SetSize(470, 86)
    editBar:SetPoint("TOP", 0, -60)
    editBar:SetFrameStrata("FULLSCREEN_DIALOG")
    editBar:SetMovable(true); editBar:EnableMouse(true); editBar:RegisterForDrag("LeftButton")
    editBar:SetScript("OnDragStart", editBar.StartMoving)
    editBar:SetScript("OnDragStop", editBar.StopMovingOrSizing)
    local over = NZR:WowFrame(editBar, "Mode édition NZR", 0.97)
    local t = over:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    t:SetPoint("TOP", 0, -28); t:SetWidth(440)
    t:SetText("Glisse les blocs dorés (cadres, groupe, meter, barres, flèche, texte de combat…).")
    local function btn(label, x, w, fn)
        local b = CreateFrame("Button", nil, over, "UIPanelButtonTemplate")
        b:SetSize(w, 22); b:SetPoint("BOTTOMLEFT", x, 10); b:SetText(label)
        b:SetScript("OnClick", fn)
        return b
    end
    editBar.grid = btn("Grille", 14, 110, function()
        if not editGrid then BuildGrid() end
        editGrid:SetShown(not editGrid:IsShown())
    end)
    btn("Positions par défaut", 130, 170, function()
        for key, hd in pairs(NZR.holders) do NZRF_DB.pos[key] = nil; NZR:PlaceHolder(hd) end
        NZR:Print("positions des blocs remises par défaut.")
    end)
    btn("Terminer", 346, 110, function() NZR:SetUnlocked(false) end)
end

NZR.editHooks = NZR.editHooks or {}

function NZR:SetUnlocked(on)
    if InCombatLockdown() then
        self:Print("impossible en combat.")
        return
    end
    self.editing = on and true or nil
    for _, hd in pairs(self.holders) do hd.nzrOpen = on; self:ShowHolder(hd, on) end
    self.unlocked = on
    for _, fn in ipairs(self.editHooks) do pcall(fn, on) end
    if NZR.CompassEdit then pcall(NZR.CompassEdit, on) end
    if on and not editBar then BuildBar() end
    if editBar then editBar:SetShown(on and true or false) end
    if editGrid and not on then editGrid:Hide() end
    self:Print(on and "mode édition : glisse les blocs dorés, puis « Terminer »."
                  or "mode édition terminé, positions enregistrées.")
end

---------------------------------------------------------------------------
-- Cadenas au survol : clic = déverrouiller / reverrouiller un élément NZR
-- opts.holder : ancre à montrer (cadres), sinon opts.get / opts.set (meter)
---------------------------------------------------------------------------
local LOCK_TEX = "Interface\\AddOns\\NZRForever\\Media\\"

function NZR:AddLock(frame, opts)
    -- enfant de l'élément : même étage d'affichage, donc caché par les fenêtres ouvertes devant
    local b = CreateFrame("Button", nil, frame)
    b:SetSize(18, 18)
    b:SetFrameLevel(frame:GetFrameLevel() + 20)
    b:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", 0, 3)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints(); b.bg:SetColorTexture(0.043, 0.039, 0.063, 0.92)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 2, -2); b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    b:SetAlpha(0)

    local function unlocked()
        if opts.holder then return opts.holder.nzrOpen end
        return not opts.get()
    end
    local function refresh()
        local open = unlocked()
        b.icon:SetTexture(LOCK_TEX .. (open and "unlock" or "lock"))
        local c = open and NZR.C.accent2 or NZR.C.dim
        b.icon:SetVertexColor(c[1], c[2], c[3])
    end
    local hideTimer
    local function show()
        if hideTimer then hideTimer:Cancel(); hideTimer = nil end
        refresh(); b:SetAlpha(1)
    end
    local function hideSoon()
        if hideTimer then hideTimer:Cancel() end
        hideTimer = C_Timer.NewTimer(0.6, function()
            hideTimer = nil
            if not b:IsMouseOver() and not frame:IsMouseOver() then b:SetAlpha(0) end
        end)
    end
    frame:HookScript("OnEnter", show)
    frame:HookScript("OnLeave", hideSoon)
    frame:HookScript("OnHide", function() b:SetAlpha(0) end)
    b:SetScript("OnEnter", function(s)
        show()
        GameTooltip:SetOwner(s, "ANCHOR_TOP")
        GameTooltip:AddLine(unlocked() and "Verrouiller" or "Déverrouiller")
        GameTooltip:AddLine(unlocked() and "Clique pour fixer cet élément." or "Clique, puis fais glisser l'élément où tu veux.", 0.75, 0.73, 0.8, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide(); hideSoon() end)
    b:SetScript("OnClick", function()
        if InCombatLockdown() and opts.holder then NZR:Print("impossible en combat.") return end
        if opts.holder then
            opts.holder.nzrOpen = not opts.holder.nzrOpen
            NZR:ShowHolder(opts.holder, opts.holder.nzrOpen)
        else
            opts.set(not opts.get())
        end
        refresh()
    end)
    b:SetShown(frame:IsShown() or true)
    refresh()
    b.Refresh = refresh
    return b
end

---------------------------------------------------------------------------
-- Modules
---------------------------------------------------------------------------
NZR.modules = {}
function NZR:Module(name)
    local m = { name = name }
    table.insert(self.modules, m)
    return m
end

-- couleurs d'accent proposées dans les réglages
NZR.ACCENTS = {
    { id = "violet", name = "Violet NZR", a = { 0.608, 0.420, 0.949 }, b = { 0.780, 0.640, 1.000 } },
    { id = "bleu",   name = "Bleu",       a = { 0.300, 0.560, 0.980 }, b = { 0.620, 0.780, 1.000 } },
    { id = "rouge",  name = "Rouge",      a = { 0.900, 0.280, 0.360 }, b = { 1.000, 0.620, 0.660 } },
    { id = "vert",   name = "Vert",       a = { 0.260, 0.800, 0.550 }, b = { 0.600, 0.950, 0.750 } },
    { id = "or",     name = "Or",         a = { 0.950, 0.720, 0.250 }, b = { 1.000, 0.860, 0.550 } },
}

local function LoadSettings()
    NZRF_DB = NZRF_DB or {}
    for k, v in pairs(defaults) do
        if NZRF_DB[k] == nil then
            NZRF_DB[k] = (type(v) == "table") and {} or v
        end
    end
    NZR.db = NZRF_DB
    -- 1.1.0 : le look des sorts et des buffs devient facultatif (désactivé de base)
    if not NZRF_DB.v102 then
        NZRF_DB.v102 = true
        NZRF_DB.theme, NZRF_DB.auras, NZRF_DB.tooltips = false, false, false
    end
    NZRF_DB.tooltips = false          -- ancien habillage NZR des infobulles : retiré (on garde celui du jeu)
    if (NZRF_DB.dbVersion or 0) < 5 then
        NZRF_DB.dbVersion = 5
        NZRF_DB.meterMode = 1
        NZRF_DB.meterW, NZRF_DB.meterH = 300, 180
    end
    -- couleur d'accent choisie
    for _, ac in ipairs(NZR.ACCENTS) do
        if ac.id == NZRF_DB.accent then
            NZR.C.accent  = { ac.a[1], ac.a[2], ac.a[3], 1 }
            NZR.C.accent2 = { ac.b[1], ac.b[2], ac.b[3], 1 }
        end
    end
    -- teinte « noir » : sorts, buffs, infobulles et réglages en noir et gris, sans violet
    -- 1.1.0 : teinte « Jeu » par défaut (se fond dans l'interface de WoW)
    if not NZRF_DB.v110 then
        NZRF_DB.v110 = true
        NZRF_DB.meterTheme = "jeu"
        NZRF_DB.moveWindows = true
    end
    local th = NZRF_DB.meterTheme or "jeu"
    if th == "jeu" then
        NZR.FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
        NZR.FONT_BOLD = NZR.FONT
    end
    if th == "noir" or th == "jeu" then
        NZR.C.bg      = { 0.0, 0.0, 0.0, 0.7 }
        NZR.C.bg2     = { 0.06, 0.06, 0.07, 0.95 }
        NZR.C.border  = { 0.0, 0.0, 0.0, 1 }
        NZR.C.accent  = { 0.34, 0.34, 0.38, 1 }
        NZR.C.accent2 = { 0.92, 0.92, 0.95, 1 }
        NZR.C.dim     = { 0.6, 0.6, 0.63 }
    end
    -- police : Inter (NZR) ou police d'origine du jeu
    if NZRF_DB.font == "classic" then
        NZR.FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
        NZR.FONT_BOLD = NZR.FONT
    end
    -- chiffres de dégâts flottants (lus par le jeu à l'entrée dans le monde)
    if NZRF_DB.damageFont then
        DAMAGE_TEXT_FONT = NZR.FONT_BOLD
    end
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_LOGIN")
loader:RegisterEvent("PLAYER_REGEN_ENABLED")

-- Après un /reload : rouvrir les fenêtres NZR qui étaient ouvertes (réglage « Rouvrir après rechargement »)
local reopen = CreateFrame("Frame")
reopen:RegisterEvent("PLAYER_LOGOUT")
reopen:RegisterEvent("PLAYER_ENTERING_WORLD")
reopen:SetScript("OnEvent", function(_, ev, isLogin, isReload)
    local db = NZRF_DB
    if not db then return end
    if ev == "PLAYER_LOGOUT" then
        if not db.reopenWindows then db.reopenState = nil; return end
        local function shown(n) local f = _G[n]; return f and f:IsShown() or nil end
        db.reopenState = {
            options = NZR.OptionsState and NZR.OptionsState() or nil,
            guide = shown("NZRF_Guide"), guidePage = db.guidePage,
            bless = shown("NZRF_BlessWindow"),
        }
        return
    end
    -- seulement après un rechargement, pas à la connexion
    local st = db.reopenState
    db.reopenState = nil
    if not (isReload and db.reopenWindows and st) then return end
    C_Timer.After(0.8, function()
        if InCombatLockdown() then return end
        if st.options and NZR.OptionsRestore then pcall(NZR.OptionsRestore, st.options) end
        if st.guide and NZR.GuideToggle and not (_G.NZRF_Guide and _G.NZRF_Guide:IsShown()) then pcall(NZR.GuideToggle) end
        if st.bless and NZR.BlessOpen then pcall(NZR.BlessOpen) end
    end)
end)
loader:SetScript("OnEvent", function(_, ev, arg1)
    if ev == "ADDON_LOADED" then
        if arg1 == ADDON then LoadSettings() end
        return
    end
    if ev == "PLAYER_REGEN_ENABLED" then
        if NZR.pendingScale then NZR:ApplyScale() end
        return
    end
    if not NZR.db then LoadSettings() end
    local uiOn = (C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("NZR_UI")) or (IsAddOnLoaded and IsAddOnLoaded("NZR_UI"))
    NZR.withUI = uiOn and true or false
    if ev == "PLAYER_LOGIN" then
        local old = (C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("NZRMeter")) or (IsAddOnLoaded and IsAddOnLoaded("NZRMeter"))
        if old then print("|cff9b6bf2NZR Forever|r : désactive l'ancien addon « NZR Meter », NZR Forever le remplace.") end
    end
    if NZR.db.damageFont and CombatTextFont then
        local _, size = CombatTextFont:GetFont()
        CombatTextFont:SetFont(NZR.FONT_BOLD, size or 25, "OUTLINE")
    end
    for _, m in ipairs(NZR.modules) do
        -- avec NZR UI : il habille déjà les barres et les buffs, on ne garde que le meter
        if m.Init and not (NZR.withUI and (m.name == "Theme" or m.name == "Auras")) then
            local ok, err = pcall(m.Init, m)
            if not ok then
                NZR:Print("|cffff5555erreur module " .. m.name .. "|r : " .. tostring(err))
                if NZR.LogError then pcall(NZR.LogError, NZR, err, m.name) end
            end
        end
    end
    NZR:ApplyScale()
    NZR:ApplyOpacity()
    NZR:Print("v" .. NZR.version .. " chargé. Réglages : |cffffffff/nzr|r, clic droit sur le meter ou Échap > NZR Forever.")
end)

---------------------------------------------------------------------------
-- Commandes
---------------------------------------------------------------------------
local toggles = {
    meter  = { "meter", "DPS meter" },
    sorts  = { "theme", "Look NZR des barres d'action" },
    buffs  = { "auras", "Look NZR des buffs et débuffs" },
}

local function onoff(v) return v and "|cff7dff8aON|r" or "|cffff6070OFF|r" end

SLASH_NZRF1 = "/nzr"
SLASH_NZRF2 = "/nzrf"
SLASH_NZRF3 = "/nzrforever"
SlashCmdList.NZRF = function(msg)
    local cmd, arg = strsplit(" ", strlower(strtrim(msg or "")), 2)
    if cmd == "unlock" then
        NZR:SetUnlocked(true)
    elseif cmd == "lock" then
        NZR:SetUnlocked(false)
    elseif cmd == "resetpos" then
        if InCombatLockdown() then return NZR:Print("impossible en combat.") end
        wipe(NZRF_DB.pos)
        for _, hd in pairs(NZR.holders) do NZR:PlaceHolder(hd) end
        if NZR.ResetMeterPos then NZR.ResetMeterPos() end
        NZR:Print("positions par défaut restaurées.")
    elseif cmd == "reset" then
        if NZR.ResetMeterData then NZR.ResetMeterData() end
    elseif cmd == "plaque" or cmd == "plate" then
        if NZR.InspectPlateText then NZR.InspectPlateText() else NZR:Print("active d'abord « Personnaliser ces barres » (Cadres), puis recharge.") end
    elseif cmd == "edit" or cmd == "edition" or cmd == "move" then
        NZR:SetUnlocked(not NZR.unlocked)
    elseif cmd == "guide" or cmd == "build" then
        if NZR.GuideToggle then NZR.GuideToggle() else NZR:Print("guide désactivé : /nzr > Pratique > Guide de progression.") end
    elseif cmd == "bene" or cmd == "benedictions" or cmd == "pally" then
        if NZR.BlessOpen then NZR.BlessOpen() else NZR:Print("active l'assistant de bénédictions dans les réglages (onglet Paladin).") end
    elseif cmd == "inspecte" or cmd == "inspect" then
        if NZR.StartInspector then NZR.StartInspector() end
    elseif cmd == "barre" then
        if NZR.InspectNameplate then NZR.InspectNameplate() end
    elseif cmd == "erreurs" or cmd == "errors" then
        if NZR.ShowErrors then NZR.ShowErrors() end
    elseif cmd == "art" then
        -- aide au débogage : liste les textures en bas de l'écran
        local n = 0
        for _, f in ipairs({ UIParent:GetChildren() }) do
            local ok, b = pcall(f.GetBottom, f)
            if ok and b and b < 140 then
                for _, r in ipairs({ f:GetRegions() }) do
                    if r.GetObjectType and r:GetObjectType() == "Texture" and r:IsShown() and r:GetAlpha() > 0 then
                        n = n + 1
                        if n <= 25 then
                            print(("  %s : %s / %s"):format(f:GetName() or "?", tostring(r:GetAtlas()), tostring(r:GetTexture())))
                        end
                    end
                end
            end
        end
        NZR:Print(n .. " texture(s) trouvée(s).")
    elseif (cmd == "" or cmd == "options" or cmd == "config") and NZR.ToggleOptions then
        NZR:ToggleOptions()
    elseif toggles[cmd] then
        local key = toggles[cmd][1]
        NZRF_DB[key] = not NZRF_DB[key]
        NZR:Print(toggles[cmd][2] .. " : " .. onoff(NZRF_DB[key]) .. " — tape |cffffffff/reload|r pour appliquer.")
    else
        NZR:Print("v" .. NZR.version .. " — commandes :")
        print("  |cffc8a8ff/nzr unlock|r / |cffc8a8fflock|r — déplacer les cadres")
        print("  |cffc8a8ff/nzr resetpos|r — positions par défaut")
        print("  |cffc8a8ff/nzr reset|r — remettre le DPS meter à zéro")
        print("  |cffc8a8ff/nzr inspecte|r — inspecteur (survole un élément, Maj = copier)")
        print("  |cffc8a8ff/nzr barre|r — détails de la barre au-dessus de ta cible")
        print("  |cffc8a8ff/nzr erreurs|r — journal des erreurs NZR")
        for k, t in pairs(toggles) do
            print(("  |cffc8a8ff/nzr %s|r — %s : %s"):format(k, t[2], onoff(NZRF_DB[t[1]])))
        end
    end
end

-- polices au choix pour les textes des barres (cadres et barres au-dessus des monstres)
NZR.FONTS = {
    { "game", "Du jeu" },
    { "friz", "Friz Quadrata", "Fonts\\FRIZQT__.TTF" },
    { "arial", "Arial Narrow", "Fonts\\ARIALN.TTF" },
    { "skurri", "Skurri", "Fonts\\SKURRI.TTF" },
    { "morpheus", "Morpheus", "Fonts\\MORPHEUS.TTF" },
}
function NZR.FontPath(key, gameFont)
    for _, f in ipairs(NZR.FONTS) do
        if f[1] == key and f[3] then return f[3] end
    end
    return gameFont or STANDARD_TEXT_FONT
end

-- contour du texte : ombre seule (propre), contour fin, épais, ou rien
NZR.OUTLINES = {
    { "shadow", "Ombre seule" },
    { "outline", "Contour fin" },
    { "thick", "Contour épais" },
    { "none", "Aucun" },
}
-- renvoie les « flags » de police et si on met l'ombre portée
function NZR.OutlineFlags(key, gameFlags)
    if key == "outline" then return "OUTLINE", false
    elseif key == "thick" then return "THICKOUTLINE", false
    elseif key == "none" then return "", false
    elseif key == "shadow" then return "", true end
    return gameFlags or "OUTLINE", false            -- « du jeu »
end
function NZR.ApplyShadow(fs, on)
    if on then fs:SetShadowColor(0, 0, 0, 1); fs:SetShadowOffset(1, -1)
    else fs:SetShadowOffset(0, 0) end
end

-- Nom complet (prénom + nom de WoW Forever). Pour les autres joueurs, le jeu ne le donne
-- souvent que dans l'infobulle : on le lit là, et on le garde en mémoire (même loin de toi).
local fullNameCache = {}
function NZR.FullName(unit)
    local okN, first = pcall(UnitName, unit)
    if not okN or not NZR.plain(first) or first == "" then return nil end
    -- déjà connu (plus long que le prénom) : pas besoin de relire l'infobulle
    local known = fullNameCache[first]
    if known and #known > #first then return known end
    local best = first
    local function take(v)
        if NZR.plain(v) and type(v) == "string" and #v > #best and v:sub(1, #first) == first then best = v end
    end
    local okP, pvp = pcall(UnitPVPName, unit); if okP then take(pvp) end
    if C_TooltipInfo and C_TooltipInfo.GetUnit then
        local okT, data = pcall(C_TooltipInfo.GetUnit, unit)
        local line = okT and data and data.lines and data.lines[1]
        if line then take(line.leftText) end
    end
    local key = first
    if fullNameCache[key] and #fullNameCache[key] > #best then best = fullNameCache[key] end
    fullNameCache[key] = best
    return best
end
