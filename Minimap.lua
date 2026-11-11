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
-- sans nom connu…) ; il garde son look et devient libre de se placer, retenu après /reload
local SKIP = { UIParent = true, Minimap = true, MinimapCluster = true, MinimapBackdrop = true, WorldFrame = true }
local FreeExtraResolve
local function FreeExtra(name)
    local f = FreeExtraResolve and FreeExtraResolve(name) or _G[name]
    if not f or f.nzrFree or InCombatLockdown() then return end
    f.nzrFree = true
    local cx, cy = f:GetCenter()
    local s = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
    pcall(f.SetParent, f, UIParent)
    f:SetFrameStrata("MEDIUM")
    if not (NZR.db.mmFreePos and NZR.db.mmFreePos[name]) and cx then
        NZR.db.mmFreePos = NZR.db.mmFreePos or {}
        NZR.db.mmFreePos[name] = { cx * s / f:GetScale(), cy * s / f:GetScale() }
    end
    DragFree(name, f)
end
-- nom « retrouvable » d'un cadre : son nom, sinon Parent.clé (cadres du jeu sans nom)
local function FrameId(f)
    local ok, n = pcall(f.GetName, f)
    if ok and type(n) == "string" then return n end
    local p = f.GetParent and f:GetParent()
    local okK, key = pcall(function() return f:GetParentKey() end)
    local pn = p and select(2, pcall(p.GetName, p))
    if okK and type(key) == "string" and type(pn) == "string" then return pn .. "." .. key end
end
local function Resolve(id)
    if _G[id] then return _G[id] end
    local pn, key = id:match("^(.-)%.([^%.]+)$")
    local p = pn and _G[pn]
    return p and p[key]
end
NZR.MinimapResolve = Resolve
FreeExtraResolve = Resolve

-- le plus petit cadre visible sous la souris autour de la minicarte (même s'il ignore la souris)
local function PickUnderMouse()
    local best, area
    local function walk(f, depth)
        if depth > 4 or not f or not f.GetChildren then return end
        for _, c in ipairs({ f:GetChildren() }) do
            local okV, vis = pcall(c.IsVisible, c)
            if okV and vis then
                local okM, over = pcall(c.IsMouseOver, c)
                local w, h = c:GetSize()
                local id = FrameId(c)
                if okM and over and w and w > 4 and id and not SKIP[id] and not id:find("^NZRF") then
                    local a = w * h
                    if not area or a < area then best, area = id, a end
                end
                walk(c, depth + 1)
            end
        end
    end
    for _, root in ipairs({ _G.MinimapCluster, Minimap, _G.MinimapBackdrop }) do walk(root, 1) end
    return best
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
        NZR:Print("« " .. name .. " » remis à sa place d'origine après /reload.")
        return
    end
    NZR.db.mmFreeExtra[name] = true
    FreeExtra(name)
    NZR:Print("« " .. name .. " » est libre : glisse-le où tu veux. Refais /nzr libre dessus pour l'annuler.")
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
