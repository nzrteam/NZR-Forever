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

function M:Init()
    if NZR.withUI then return end
    if NZR.db.mmButtonsSave and Minimap then SetupButtonMemory() end
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
