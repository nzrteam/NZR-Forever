-- NZR Forever - Buffs et débuffs du joueur (cadre de Blizzard, simplement habillé)
local _, NZR = ...
local M = NZR:Module("Auras")
local C = NZR.C

local function StyleAura(b)
    if not b or b.nzr or (b.IsForbidden and b:IsForbidden()) then return end
    local icon = b.Icon or b.icon
    if not icon then return end
    b.nzr = true
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    if icon.GetMaskTextures then
        for _, mask in ipairs({ icon:GetMaskTextures() }) do pcall(icon.RemoveMaskTexture, icon, mask) end
    end
    -- bord fin (noir + liseré sombre) derrière l'icône
    local edge = b:CreateTexture(nil, "BACKGROUND", nil, -8)
    edge:SetPoint("TOPLEFT", icon, -2, 2); edge:SetPoint("BOTTOMRIGHT", icon, 2, -2)
    edge:SetColorTexture(C.border[1], C.border[2], C.border[3], 1)
    local inner = b:CreateTexture(nil, "BACKGROUND", nil, -7)
    inner:SetPoint("TOPLEFT", icon, -1, 1); inner:SetPoint("BOTTOMRIGHT", icon, 1, -1)
    inner:SetColorTexture(0, 0, 0, 1)
    b.nzrEdge = edge
    NZR:RoundTex(edge, 3, C.border[1], C.border[2], C.border[3], 1)
    NZR:RoundTex(inner, 3, 0, 0, 0, 1)
    NZR:Mask(NZR:RoundMask(b, icon, 0), icon)

    -- débuffs : bord rouge fin à la place du gros cadre de Blizzard
    if b.DebuffBorder then b.DebuffBorder:SetAlpha(0) end
    if b.Border then b.Border:SetAlpha(0) end
    if b.TempEnchantBorder then b.TempEnchantBorder:SetAlpha(0) end

    local dur = b.Duration or b.duration
    if dur then
        dur:SetFont(NZR.FONT_BOLD, 10, "")
        dur:SetShadowColor(0, 0, 0, 1)
        dur:SetShadowOffset(1, -1)
        dur:SetTextColor(C.accent2[1], C.accent2[2], C.accent2[3])
        hooksecurefunc(dur, "SetTextColor", function(s)
            if s.nzrLock then return end
            s.nzrLock = true
            s:SetTextColor(C.accent2[1], C.accent2[2], C.accent2[3])
            s.nzrLock = false
        end)
    end
    local cnt = b.Count or b.count
    if cnt then
        cnt:SetFont(NZR.FONT_BOLD, 11, "OUTLINE")
        cnt:ClearAllPoints()
        cnt:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 1, 1)
    end
end

local function Recolor(b)
    if not b or not b.nzrEdge then return end
    local debuff = (b.DebuffBorder and b.DebuffBorder:IsShown()) or b.isDebuff or (b.auraType == "Debuff")
    if debuff then
        local r, g, bl = 0.85, 0.22, 0.26
        if b.DebuffBorder and b.DebuffBorder.GetVertexColor then
            local dr, dg, db = b.DebuffBorder:GetVertexColor()
            if dr then r, g, bl = dr, dg, db end
        end
        b.nzrEdge:SetVertexColor(r, g, bl, 1)
    elseif b.TempEnchantBorder and b.TempEnchantBorder:IsShown() then
        b.nzrEdge:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 1)
    else
        b.nzrEdge:SetVertexColor(C.border[1], C.border[2], C.border[3], 1)
    end
end

local function StyleAll()
    for _, parent in ipairs({ BuffFrame, DebuffFrame }) do
        if parent then
            local list = parent.auraFrames
            if type(list) == "table" then
                for _, b in pairs(list) do pcall(StyleAura, b); pcall(Recolor, b) end
            end
            local cont = parent.AuraContainer
            if cont then
                for _, b in ipairs({ cont:GetChildren() }) do pcall(StyleAura, b); pcall(Recolor, b) end
            end
        end
    end
    -- anciens noms (BuffButton1, DebuffButton1…)
    for i = 1, 40 do
        for _, n in ipairs({ "BuffButton", "DebuffButton", "TempEnchant" }) do
            local b = _G[n .. i]
            if b then pcall(StyleAura, b); pcall(Recolor, b) end
        end
    end
end

function M:Init()
    if not NZR.db.auras then return end
    local pending = false
    local function Queue()
        if pending then return end
        pending = true
        C_Timer.After(0, function() pending = false; StyleAll() end)
    end
    for _, parent in ipairs({ BuffFrame, DebuffFrame }) do
        if parent then
            for _, fn in ipairs({ "UpdateAuraButtons", "Update", "UpdateGridLayout" }) do
                if type(parent[fn]) == "function" then hooksecurefunc(parent, fn, Queue) end
            end
        end
    end
    local ev = CreateFrame("Frame")
    ev:RegisterUnitEvent("UNIT_AURA", "player")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:SetScript("OnEvent", Queue)
    Queue()
end
