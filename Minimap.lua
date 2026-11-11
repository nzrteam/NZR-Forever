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

-- trouver l'icône d'un bouton (LibDBIcon : .icon ; sinon la plus grande texture « dessin »)
local function FindIcon(b)
    local ic = b.icon or b.Icon or b.iconTexture
    if ic and ic.GetObjectType and ic:GetObjectType() == "Texture" then return ic end
    local best, area = nil, 0
    for _, r in ipairs({ b:GetRegions() }) do
        if r:GetObjectType() == "Texture" and r ~= b.nzrRing then
            local layer = r:GetDrawLayer()
            local w, h = r:GetSize()
            if (layer == "ARTWORK" or layer == "BORDER") and w and h and w * h > area then best, area = r, w * h end
        end
    end
    return best
end

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
    for _, r in ipairs({ b:GetRegions() }) do
        if r:GetObjectType() == "Texture" and r ~= icon and r:GetDrawLayer() ~= "HIGHLIGHT" then r:SetAlpha(0) end
    end
    if b.border then b.border:SetAlpha(0) end
    if b.background then b.background:SetAlpha(0) end
    if icon then
        icon:ClearAllPoints(); icon:SetPoint("TOPLEFT", 4, -4); icon:SetPoint("BOTTOMRIGHT", -4, 4)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        icon:SetAlpha(1)
        -- LibDBIcon décale l'icône quand on clique : on la remet carrée
        b:HookScript("OnMouseUp", function() icon:ClearAllPoints(); icon:SetPoint("TOPLEFT", 4, -4); icon:SetPoint("BOTTOMRIGHT", -4, 4); icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end)
    end
    local ring = b:CreateTexture(nil, "OVERLAY", nil, 7)
    ring:SetAllPoints(); ring:SetTexture(RING)
    b.nzrRing = ring
    local hl = b:GetHighlightTexture()
    if hl then hl:ClearAllPoints(); hl:SetPoint("TOPLEFT", 4, -4); hl:SetPoint("BOTTOMRIGHT", -4, 4); hl:SetColorTexture(1, 0.82, 0, 0.25) end
    -- glisser : librement, n'importe où ; la place est retenue
    b:SetMovable(true); b:SetClampedToScreen(true)
    b:RegisterForDrag("LeftButton")
    b:SetScript("OnDragStart", function(self) self.nzrDrag = true; self:StartMoving() end)
    b:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing(); self.nzrDrag = nil
        SavePos(name, self); Place(name, self)
    end)
    -- l'addon (ou LibDBIcon) qui le replace sur le bord de la carte : on le remet à sa place
    hooksecurefunc(b, "SetPoint", function(self)
        if self.nzrLock or self.nzrDrag then return end
        Place(name, self)
    end)
    Place(name, b)
end

local function FreeAll()
    if InCombatLockdown() then return end
    for name, b in pairs(AllAddonButtons()) do pcall(FreeButton, name, b) end
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

    -- molette = zoom
    mm:EnableMouseWheel(true)
    mm:HookScript("OnMouseWheel", function(self, d)
        local z = self:GetZoom() + (d > 0 and 1 or -1)
        if z >= 0 and z <= self:GetZoomLevels() - 1 then self:SetZoom(z) end
    end)
end
