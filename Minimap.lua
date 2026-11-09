-- NZR Forever - Minimap carrée (facultatif) : garde les boutons et la barre de zone du jeu
local _, NZR = ...
local M = NZR:Module("Minimap")

local MASK = "Interface\\AddOns\\NZRForever\\Media\\minimap_mask"

local function Fade(obj)
    if obj and obj.SetAlpha then obj:SetAlpha(0) end
end

function M:Init()
    if NZR.withUI or not NZR.db.squareMinimap then return end
    local mm = Minimap
    if not mm then return end

    -- forme carrée (aussi pour les boutons des autres addons)
    GetMinimapShape = function() return "SQUARE" end
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
