-- NZR Forever - Minimap carrée (facultatif) : garde les boutons et la barre de zone du jeu
local _, NZR = ...
local M = NZR:Module("Minimap")

local MASK = "Interface\\AddOns\\NZRForever\\Media\\minimap_mask"

local function Fade(obj)
    if obj and obj.SetAlpha then obj:SetAlpha(0) end
end

-- Boutons des addons autour de la minicarte : on retient leur place (glisser = mémorisé)
local function DBIcon()
    return LibStub and LibStub("LibDBIcon-1.0", true)
end

local function MinimapButtons()
    local list = {}
    local lib = DBIcon()
    if lib and lib.objects then
        for name, b in pairs(lib.objects) do list[name] = b end
    end
    for _, c in ipairs({ Minimap:GetChildren() }) do
        local n = c.GetName and c:GetName()
        if n and n:find("^LibDBIcon10_") and not list[n] then list[n] = c end
    end
    return list
end

local function SaveButton(name, b)
    local mx, my = Minimap:GetCenter()
    local bx, by = b:GetCenter()
    if not (mx and bx) then return end
    NZR.db.mmButtons = NZR.db.mmButtons or {}
    NZR.db.mmButtons[name] = { bx - mx, by - my }
end

local function ApplyButtons()
    local saved = NZR.db.mmButtons or {}
    for name, b in pairs(MinimapButtons()) do
        if not b.nzrSaveHook then
            b.nzrSaveHook = true
            b:HookScript("OnDragStop", function(s) SaveButton(name, s) end)
        end
        local p = saved[name]
        if p and not (b.isMoving or b.dragging) then
            b:ClearAllPoints()
            b:SetPoint("CENTER", Minimap, "CENTER", p[1], p[2])
        end
    end
end

local function SetupButtonMemory()
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:SetScript("OnEvent", function()
        -- les addons posent leurs boutons au chargement : on repasse derrière, deux fois
        C_Timer.After(1, ApplyButtons)
        C_Timer.After(4, ApplyButtons)
    end)
end

---------------------------------------------------------------------------
-- Boutons d'addons carrés et libres (option « mmFree ») : tous les boutons d'addons
-- de la minicarte (LibDBIcon, que presque tous utilisent, + les autres boutons d'addons
-- posés sur la minicarte) prennent l'anneau doré carré de NZR et se glissent n'importe
-- où sur l'écran. Leurs clics et infobulles restent ceux de leur addon.
---------------------------------------------------------------------------
local RING = "Interface\\AddOns\\NZRForever\\Media\\uf\\ring_square"
local NOT_ADDON = { "^Minimap", "^MiniMap", "^GameTime", "^TimeManager", "^QueueStatus", "^ExpansionLanding",
    "^AddonCompartment", "^Garrison", "^NZRF", "^GuildInstance", "^Tracking", "^HybridMinimap", "^Calendar" }

local function IsAddonButton(c)
    if not (c and c.IsObjectType and c:IsObjectType("Button")) then return false end
    local okN, n = pcall(c.GetName, c)
    if not okN or type(n) ~= "string" then return false end
    if n:find("^LibDBIcon10_") then return true end
    for _, pat in ipairs(NOT_ADDON) do if n:find(pat) then return false end end
    local w, h = c:GetSize()
    return w and h and w >= 14 and w <= 48 and math.abs(w - h) <= 8
end

local function AllAddonButtons()
    local list = MinimapButtons()
    for _, parent in ipairs({ Minimap, _G.MinimapBackdrop }) do
        if parent then
            for _, c in ipairs({ parent:GetChildren() }) do
                local n = c.GetName and c:GetName()
                if n and not list[n] and IsAddonButton(c) then list[n] = c end
            end
        end
    end
    return list
end

-- trouver l'icône d'un bouton, quel que soit l'addon : LibDBIcon (.icon), texture
-- « normale » du bouton (SetNormalTexture), ou la plus grande texture qui n'est pas
-- un bord / fond / surbrillance, dans n'importe quelle couche (même dans un sous-cadre)
local DECOR_ID = { [136430] = true, [136467] = true, [136477] = true, [136466] = true }
local function IsDecor(r)
    local okT, tex = pcall(r.GetTexture, r)
    local okA, atlas = pcall(r.GetAtlas, r)
    if not (okT and tex) and not (okA and atlas) then return true end      -- vide
    if type(tex) == "number" and DECOR_ID[tex] then return true end
    local n = ((type(tex) == "string" and tex or "") .. " " .. (okA and atlas or "")):lower()
    return n:find("border") or n:find("background") or n:find("highlight") or n:find("trackingborder") or n:find("minimap%-") and not n:find("icon")
end
local function Textures(f, out)
    for _, r in ipairs({ f:GetRegions() }) do
        if r:GetObjectType() == "Texture" then table.insert(out, r) end
    end
    return out
end
local function FindIcon(b)
    local ic = b.icon or b.Icon or b.iconTexture or b.texture
    if ic and ic.GetObjectType and ic:GetObjectType() == "Texture" and not IsDecor(ic) then return ic end
    local list = Textures(b, {})
    local nt = b.GetNormalTexture and b:GetNormalTexture()
    if nt then table.insert(list, nt) end
    for _, c in ipairs({ b:GetChildren() }) do Textures(c, list) end
    local best, score = nil, 0
    for _, r in ipairs(list) do
        if r ~= b.nzrRing and r:GetDrawLayer() ~= "HIGHLIGHT" and not IsDecor(r) then
            local w, h = r:GetSize()
            w, h = w or 0, h or 0
            if w == 0 or h == 0 then w, h = b:GetSize() end      -- texture étirée sur tout le bouton
            local sc = w * h + (r:GetDrawLayer() == "ARTWORK" and 1 or 0)
            if sc > score then best, score = r, sc end
        end
    end
    return best
end

local DragFree
local function SavePos(name, b)
    local x, y = b:GetCenter()
    if not x then return end
    NZR.db.mmFreePos = NZR.db.mmFreePos or {}
    NZR.db.mmFreePos[name] = { x, y }
end

local function Place(name, b)
    local p = NZR.db.mmFreePos and NZR.db.mmFreePos[name]
    if not p then return end
    b.nzrLock = true
    b:ClearAllPoints()
    b:SetPoint("CENTER", UIParent, "BOTTOMLEFT", p[1], p[2])
    b.nzrLock = nil
end


-- glisser un bouton libre : l'infobulle se cache pendant le glissé (on voit les voisins),
-- et le bouton s'aligne tout seul sur les autres s'il passe à moins de 8 px de leur ligne
local freed = {}
local dragging
if GameTooltip then
    hooksecurefunc(GameTooltip, "Show", function(t) if dragging then t:Hide() end end)
end
local function Snap(name, b)
    local x, y = b:GetCenter()
    if not x then return end
    local bx, by, dx, dy = x, y, 8, 8
    for n, o in pairs(freed) do
        if n ~= name and o:IsShown() then
            local ox, oy = o:GetCenter()
            if ox then
                if math.abs(ox - x) < dx then dx, bx = math.abs(ox - x), ox end
                if math.abs(oy - y) < dy then dy, by = math.abs(oy - y), oy end
            end
        end
    end
    b:ClearAllPoints()
    b:SetPoint("CENTER", UIParent, "BOTTOMLEFT", bx, by)
end
DragFree = function(name, b)
    freed[name] = b
    b:SetMovable(true); b:SetClampedToScreen(true)
    if b.EnableMouse then b:EnableMouse(true) end
    b:RegisterForDrag("LeftButton")
    b:SetScript("OnDragStart", function(self)
        self.nzrDrag = true; dragging = true
        GameTooltip:Hide()
        self:StartMoving()
    end)
    b:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        self.nzrLock = true; Snap(name, self); self.nzrLock = nil
        self.nzrDrag = nil; dragging = nil
        SavePos(name, self); Place(name, self)
    end)
    -- l'addon (ou le jeu) qui le replace : on le remet à sa place
    if not b.nzrHooked then
        b.nzrHooked = true
        hooksecurefunc(b, "SetPoint", function(self)
            if self.nzrLock or self.nzrDrag then return end
            Place(name, self)
        end)
    end
    Place(name, b)
end

-- la lune / le soleil (heure et calendrier du jeu) : déplaçable, mais garde son look rond
local function FreeGameTime()
    local g = _G.GameTimeFrame
    if not g or g.nzrFree or InCombatLockdown() then return end
    g.nzrFree = true
    local cx, cy = g:GetCenter()
    local s = g:GetEffectiveScale() / UIParent:GetEffectiveScale()
    pcall(g.SetParent, g, UIParent)
    g:SetFrameStrata("MEDIUM")
    if not (NZR.db.mmFreePos and NZR.db.mmFreePos.GameTimeFrame) and cx then
        NZR.db.mmFreePos = NZR.db.mmFreePos or {}
        NZR.db.mmFreePos.GameTimeFrame = { cx * s / g:GetScale(), cy * s / g:GetScale() }
    end
    DragFree("GameTimeFrame", g)
end


-- n'importe quel élément de la minicarte : souris dessus + /nzr libre (la lune, un bouton
-- sans nom…) ; il garde son look et devient libre de se placer, retenu après /reload.
-- Un cadre se déplace tel quel ; une simple image (texture) suit une poignée invisible NZR.
local SKIP = { UIParent = true, Minimap = true, MinimapCluster = true, MinimapBackdrop = true, WorldFrame = true }
local MAX_SIZE = 80            -- plus grand = un conteneur (la carte elle-même), jamais libéré

local function NameOf(o)
    local ok, n = pcall(o.GetName, o)
    return ok and type(n) == "string" and n or nil
end
-- « empreinte » d'un cadre sans nom : sa taille et les clés de ses images (Background,
-- Icon…), qui ne changent pas d'un chargement à l'autre (l'ordre des cadres, lui, peut changer)
local function Sig(f)
    local keys = {}
    for _, r in ipairs({ f:GetRegions() }) do
        local ok, k = pcall(function() return r:GetParentKey() end)
        if ok and type(k) == "string" then keys[#keys + 1] = k end
    end
    if #keys == 0 then return end
    table.sort(keys)
    local w, h = f:GetSize()
    return table.concat(keys, "+") .. ":" .. math.floor((w or 0) + 0.5) .. "x" .. math.floor((h or 0) + 0.5)
end
-- identifiant retrouvable après /reload : nom, sinon Parent.clé, sinon Parent@empreinte,
-- sinon Parent#n (n-ième cadre) ou Parent#rn (n-ième image)
local FrameId
FrameId = function(o)
    local n = NameOf(o)
    if n then return n end
    local p = o.GetParent and o:GetParent()
    if not p then return end
    local pid = FrameId(p)
    if not pid then return end
    local okK, key = pcall(function() return o:GetParentKey() end)
    if okK and type(key) == "string" then return pid .. "." .. key end
    local isTex = o.IsObjectType and o:IsObjectType("Texture")
    if not isTex then
        local sg = Sig(o)
        if sg then return pid .. "@" .. sg end
    end
    local list = isTex and { p:GetRegions() } or { p:GetChildren() }
    for i, c in ipairs(list) do if c == o then return pid .. (isTex and "#r" or "#") .. i end end
end
local Resolve
Resolve = function(id)
    if _G[id] then return _G[id] end
    -- Parent@empreinte (l'empreinte peut contenir des points : on coupe au dernier @)
    local apid, asig = id:match("^(.+)@([^@]+)$")
    if apid then
        local p = Resolve(apid)
        if not p then return end
        for _, c in ipairs({ p:GetChildren() }) do if Sig(c) == asig then return c end end
        return
    end
    local pid, sep, rest = id:match("^(.+)([%.#])([^%.#@]+)$")
    if not pid then return end
    local p = Resolve(pid)
    if not p then return end
    if sep == "." then return p[rest] end
    local ri = rest:match("^r(%d+)$")
    if ri then return (select(tonumber(ri), p:GetRegions())) end
    return (select(tonumber(rest), p:GetChildren()))
end
NZR.MinimapResolve = Resolve

local function TooBig(o)
    local w, h = o:GetSize()
    return not w or w > MAX_SIZE or h > MAX_SIZE or w < 4
end

local function FreeExtra(name)
    if SKIP[name] then return end
    local f = Resolve(name)
    if not f or f.nzrFree or InCombatLockdown() or TooBig(f) then return end
    f.nzrFree = true
    local cx, cy = f:GetCenter()
    local s = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local target = f
    if f:IsObjectType("Texture") then
        -- une image : une poignée invisible à sa place ; l'image et les petites images posées
        -- au même endroit (contour, fond…) la suivent ensemble, en gardant leur écart
        local parent = f:GetParent()
        local fl, ft = f:GetLeft(), f:GetTop()
        local w, h = f:GetSize()
        local fr, fb = fl + w, ft - h
        local group = { { tex = f, dx = 0, dy = 0, w = w, h = h } }
        for _, r in ipairs({ parent:GetRegions() }) do
            if r ~= f and r:IsObjectType("Texture") and r:GetDrawLayer() ~= "HIGHLIGHT" and not r.nzrFree and not TooBig(r) then
                local okV, vis = pcall(r.IsShown, r)
                local l, t = r:GetLeft(), r:GetTop()
                if okV and vis and l then
                    local rw, rh = r:GetSize()
                    -- se chevauchent nettement
                    local ix = math.min(fr, l + rw) - math.max(fl, l)
                    local iy = math.min(ft, t) - math.max(fb, t - rh)
                    if ix > 0 and iy > 0 and ix * iy >= 0.25 * math.min(w * h, rw * rh) then
                        r.nzrFree = true
                        table.insert(group, { tex = r, dx = l - fl, dy = t - ft, w = rw, h = rh })
                        local rid = FrameId(r)
                        if rid and NZR.db.mmFreeExtra and rid ~= name then
                            NZR.db.mmFreeExtra[rid] = nil
                            if NZR.db.mmFreePos then NZR.db.mmFreePos[rid] = nil end
                        end
                    end
                end
            end
        end
        -- la poignée couvre tout le groupe
        local gl, gt, gr, gb = 0, 0, w, -h
        for _, m in ipairs(group) do
            gl = math.min(gl, m.dx); gt = math.max(gt, m.dy)
            gr = math.max(gr, m.dx + m.w); gb = math.min(gb, m.dy - m.h)
        end
        local hd = CreateFrame("Frame", nil, UIParent)
        hd:SetSize((gr - gl) * s, (gt - gb) * s)
        hd:SetFrameStrata("MEDIUM")
        local function Stick()
            for _, m in ipairs(group) do
                local t = m.tex
                t.nzrLock = true
                t:ClearAllPoints()
                t:SetPoint("TOPLEFT", hd, "TOPLEFT", m.dx - gl, m.dy - gt)
                t:SetSize(m.w, m.h)
                t.nzrLock = nil
            end
        end
        for _, m in ipairs(group) do
            local t = m.tex
            hooksecurefunc(t, "SetPoint", function() if not t.nzrLock then Stick() end end)
            if t.SetAllPoints then hooksecurefunc(t, "SetAllPoints", function() if not t.nzrLock then Stick() end end) end
        end
        if not (NZR.db.mmFreePos and NZR.db.mmFreePos[name]) and cx then
            NZR.db.mmFreePos = NZR.db.mmFreePos or {}
            local gcx = (fl + gl + (gr - gl) / 2) * s
            local gcy = (ft + gt - (gt - gb) / 2) * s
            NZR.db.mmFreePos[name] = { gcx, gcy }
        end
        hd:ClearAllPoints()
        hd:SetPoint("CENTER", UIParent, "BOTTOMLEFT", (cx or 0) * s, (cy or 0) * s)
        DragFree(name, hd)
        Stick()
        return
    end
    pcall(f.SetParent, f, UIParent)
    f:SetFrameStrata("MEDIUM")
    if not (NZR.db.mmFreePos and NZR.db.mmFreePos[name]) and cx then
        NZR.db.mmFreePos = NZR.db.mmFreePos or {}
        NZR.db.mmFreePos[name] = { cx * s / f:GetScale(), cy * s / f:GetScale() }
    end
    DragFree(name, target)
end

-- la souris est-elle sur cet élément ? (calcul à la main : marche même s'il ignore la souris)
local function Over(o)
    local l, r, b, t = o:GetLeft(), o:GetRight(), o:GetBottom(), o:GetTop()
    if not l then return false end
    local x, y = GetCursorPosition()
    local sc = o:GetEffectiveScale()
    x, y = x / sc, y / sc
    return x >= l and x <= r and y >= b and y <= t
end

-- le plus petit élément visible (cadre ou image) sous la souris, autour de la minicarte
local function PickUnderMouse()
    local best, area
    local function consider(o)
        local okV, vis = pcall(o.IsVisible, o)
        if not (okV and vis) or o.nzrSkip then return end
        local okA, alpha = pcall(o.GetEffectiveAlpha or o.GetAlpha, o)
        if okA and alpha and alpha < 0.05 then return end
        if TooBig(o) or not Over(o) then return end
        -- une image dans un petit cadre : on prend le cadre entier (icône + contour + fond)
        if o:IsObjectType("Texture") then
            local p = o:GetParent()
            local pid = p and FrameId(p)
            if p and pid and not SKIP[pid] and not TooBig(p) and not p.nzrSkip then o = p end
        end
        local id = FrameId(o)
        if not id or SKIP[id] or id:find("NZRF") then return end
        local w, h = o:GetSize()
        if not area or w * h < area then best, area = id, w * h end
    end
    local function walk(f, depth)
        if depth > 5 or not f or f.nzrSkip then return end
        for _, r in ipairs({ f:GetRegions() }) do
            if r:IsObjectType("Texture") and r:GetDrawLayer() ~= "HIGHLIGHT" then pcall(consider, r) end
        end
        for _, c in ipairs({ f:GetChildren() }) do
            local okV, vis = pcall(c.IsVisible, c)
            if okV and vis then pcall(consider, c); walk(c, depth + 1) end
        end
    end
    for _, root in ipairs({ _G.MinimapCluster, Minimap, _G.MinimapBackdrop }) do walk(root, 1) end
    return best
end

-- anciens essais : jamais de gros conteneur (la carte elle-même) dans la liste
local function CleanExtra()
    for id in pairs(NZR.db.mmFreeExtra or {}) do
        local o = Resolve(id)
        if SKIP[id] or id:find("Container$") or id:find("#") or (o and TooBig(o)) then
            NZR.db.mmFreeExtra[id] = nil
            if NZR.db.mmFreePos then NZR.db.mmFreePos[id] = nil end
        end
    end
end

function NZR.MinimapFreeUnderMouse()
    if InCombatLockdown() then NZR:Print("Hors combat seulement.") return end
    local name = PickUnderMouse()
    if not name then
        NZR:Print("Rien à libérer sous la souris. Mets la souris sur l'icône (sans cliquer) puis tape /nzr libre.")
        return
    end
    NZR.db.mmFreeExtra = NZR.db.mmFreeExtra or {}
    if NZR.db.mmFreeExtra[name] then
        NZR.db.mmFreeExtra[name] = nil
        if NZR.db.mmFreePos then NZR.db.mmFreePos[name] = nil end
        NZR:Print("Remis à sa place d'origine après /reload.")
        return
    end
    NZR.db.mmFreeExtra[name] = true
    FreeExtra(name)
    NZR:Print("Libéré : glisse-le où tu veux. Refais /nzr libre dessus pour l'annuler. |cff808080(" .. name .. ")|r")
end

local function FreeButton(name, b)
    if b.nzrFree or InCombatLockdown() then return end
    b.nzrFree = true
    -- garder sa place actuelle à l'écran
    local cx, cy = b:GetCenter()
    local s = b:GetEffectiveScale() / UIParent:GetEffectiveScale()
    pcall(b.SetParent, b, UIParent)
    b:SetScale(1)
    b:SetFrameStrata("MEDIUM"); b:SetFrameLevel(20)
    b:SetSize(30, 30)
    if not (NZR.db.mmFreePos and NZR.db.mmFreePos[name]) and cx then
        NZR.db.mmFreePos = NZR.db.mmFreePos or {}
        NZR.db.mmFreePos[name] = { cx * s, cy * s }
    end
    -- look : on efface le rond (bord, fond), icône recadrée en carré, anneau doré NZR
    local icon = FindIcon(b)
    local pushed = b.GetPushedTexture and b:GetPushedTexture()
    local iconIsNormal = icon and b.GetNormalTexture and icon == b:GetNormalTexture()
    for _, r in ipairs({ b:GetRegions() }) do
        if r:GetObjectType() == "Texture" and r ~= icon and r:GetDrawLayer() ~= "HIGHLIGHT"
            and not (iconIsNormal and r == pushed) then r:SetAlpha(0) end
    end
    -- bouton dont l'icône est la texture « normale » : la version enfoncée prend la même forme
    if iconIsNormal and pushed then
        pushed:ClearAllPoints(); pushed:SetPoint("TOPLEFT", 5, -5); pushed:SetPoint("BOTTOMRIGHT", -3, 3)
        pushed:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
    if b.border then b.border:SetAlpha(0) end
    if b.background then b.background:SetAlpha(0) end
    if icon then
        icon:ClearAllPoints(); icon:SetPoint("TOPLEFT", b, "TOPLEFT", 4, -4); icon:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -4, 4)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        icon:SetAlpha(1); icon:Show()
        -- LibDBIcon décale l'icône quand on clique : on la remet carrée
        b:HookScript("OnMouseUp", function() icon:ClearAllPoints(); icon:SetPoint("TOPLEFT", b, "TOPLEFT", 4, -4); icon:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -4, 4); icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end)
    end
    local ring = b:CreateTexture(nil, "OVERLAY", nil, 7)
    ring:SetAllPoints(); ring:SetTexture(RING)
    b.nzrRing = ring
    local hl = b:GetHighlightTexture()
    if hl then hl:ClearAllPoints(); hl:SetPoint("TOPLEFT", 4, -4); hl:SetPoint("BOTTOMRIGHT", -4, 4); hl:SetColorTexture(1, 0.82, 0, 0.25) end
    -- glisser : librement, n'importe où ; la place est retenue
    DragFree(name, b)
end

local function FreeAll()
    if InCombatLockdown() then return end
    for name, b in pairs(AllAddonButtons()) do pcall(FreeButton, name, b) end
    pcall(FreeGameTime)
    pcall(CleanExtra)
    for n in pairs(NZR.db.mmFreeExtra or {}) do pcall(FreeExtra, n) end
end

local function SetupFreeButtons()
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:RegisterEvent("PLAYER_REGEN_ENABLED")
    ev:SetScript("OnEvent", function()
        C_Timer.After(1, FreeAll)
        C_Timer.After(4, FreeAll)
    end)
    -- les boutons créés plus tard (addon chargé à la demande)
    local lib = DBIcon()
    if lib and lib.RegisterCallback then
        pcall(lib.RegisterCallback, NZR, "LibDBIcon_IconCreated", function(_, b, name)
            C_Timer.After(0.2, function() if not InCombatLockdown() then pcall(FreeButton, name, b) end end)
        end)
    end
end
NZR.MinimapFreeAll = FreeAll
NZR.MinimapFreeButton = FreeButton

function M:Init()
    if NZR.withUI then return end
    if NZR.db.mmFree and Minimap then SetupFreeButtons()
    elseif NZR.db.mmButtonsSave and Minimap then SetupButtonMemory() end
    if not NZR.db.squareMinimap then return end
    local mm = Minimap
    if not mm then return end

    -- forme carrée (aussi pour les boutons des autres addons)
    GetMinimapShape = function() return "SQUARE" end
    -- les boutons déjà posés en mode « rond » sont replacés en mode carré
    C_Timer.After(0.5, function()
        local lib = DBIcon()
        if lib and lib.objects and lib.Refresh then
            for name in pairs(lib.objects) do pcall(lib.Refresh, lib, name) end
        end
    end)
    mm:SetMaskTexture(MASK)
    pcall(mm.SetArchBlobRingScalar, mm, 0)
    pcall(mm.SetArchBlobRingAlpha, mm, 0)
    pcall(mm.SetQuestBlobRingScalar, mm, 0)
    pcall(mm.SetQuestBlobRingAlpha, mm, 0)
    pcall(mm.SetTaskBlobRingScalar, mm, 0)

    -- seul l'anneau rond disparaît ; barre de zone, horloge, boutons restent ceux du jeu
    Fade(_G.MinimapCompassTexture)
    Fade(_G.MinimapBorder)
    Fade(_G.MinimapBackdrop and MinimapBackdrop.StaticOverlayTexture)

    -- bord des infobulles du jeu autour de la carte
    local ns = CreateFrame("Frame", nil, mm, "NineSlicePanelTemplate")
    ns.nzrSkip = true
    ns:SetPoint("TOPLEFT", -4, 4)
    ns:SetPoint("BOTTOMRIGHT", 4, -4)
    ns:SetFrameLevel(mm:GetFrameLevel() + 1)
    local ok = NineSliceUtil and pcall(NineSliceUtil.ApplyLayoutByName, ns, "TooltipDefaultLayout")
    if ok then
        if ns.Center then ns.Center:Hide() end
        if ns.SetBorderColor then pcall(ns.SetBorderColor, ns, 0.62, 0.62, 0.66, 1) end
    else
        ns:Hide()
        local e = mm:CreateTexture(nil, "BACKGROUND", nil, -8)
        e:SetColorTexture(0, 0, 0, 1)
        e:SetPoint("TOPLEFT", -2, 2); e:SetPoint("BOTTOMRIGHT", 2, -2)
    end

    -- mode Édition du jeu : le bloc de la minicarte est plus large que la carte carrée ;
    -- on laisse dépasser ce vide hors de l'écran pour coller la carte au bord
    local cl = _G.MinimapCluster
    if cl and cl.SetClampRectInsets then
        local function Insets()
            local cl_l, cl_r = cl:GetLeft(), cl:GetRight()
            local ml, mr = mm:GetLeft(), mm:GetRight()
            if not (cl_l and ml) then return end
            local s = mm:GetEffectiveScale() / cl:GetEffectiveScale()
            local gl = math.max(0, ml * s - cl_l - 6)
            local gr = math.max(0, cl_r - mr * s - 6)
            pcall(cl.SetClampRectInsets, cl, gl, -gr, 0, 0)
        end
        C_Timer.After(1, Insets)
        if EditModeManagerFrame then EditModeManagerFrame:HookScript("OnShow", function() C_Timer.After(0.1, Insets) end) end
    end

    -- molette = zoom
    mm:EnableMouseWheel(true)
    mm:HookScript("OnMouseWheel", function(self, d)
        local z = self:GetZoom() + (d > 0 and 1 or -1)
        if z >= 0 and z <= self:GetZoomLevels() - 1 then self:SetZoom(z) end
    end)
end
