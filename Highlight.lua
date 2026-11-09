-- NZR Forever - Surbrillance des quêtes
-- Quand la souris passe sur un objet, un PNJ ou un monstre utile à une quête de
-- ton journal, un court effet (Ping, Éclat ou Halo) s'affiche à cet endroit.
-- Désactivé de base (Réglages > Pratique > Surbrillance des quêtes).
local _, NZR = ...
local M = NZR:Module("Highlight")
local MEDIA = "Interface\\AddOns\\NZRForever\\Media\\hl\\"

local COLORS = {
    gold  = { 1, 0.82, 0 },
    white = { 1, 1, 1 },
    green = { 0.3, 1, 0.35 },
    blue  = { 0.35, 0.7, 1 },
}

local function DB() return NZR.db end

local function plain(v)
    if issecretvalue and issecretvalue(v) then return false end
    return v ~= nil
end

---------------------------------------------------------------------------
-- Est-ce lié à une quête ? (lignes « quête » des infobulles du jeu)
---------------------------------------------------------------------------
local QUEST_LINES = {}
local function InitLineTypes()
    local T = Enum and Enum.TooltipDataLineType
    if not T then return end
    for _, k in ipairs({ "QuestObjective", "QuestTitle", "QuestPlayer" }) do
        if T[k] then QUEST_LINES[T[k]] = true end
    end
end

local function DataHasQuest(data)
    if not data or not data.lines then return false end
    for _, line in ipairs(data.lines) do
        if line.type and plain(line.type) and QUEST_LINES[line.type] then return true end
    end
    return false
end

local function UnitIsQuest(unit)
    if C_QuestLog and C_QuestLog.UnitIsRelatedToActiveQuest then
        local ok, r = pcall(C_QuestLog.UnitIsRelatedToActiveQuest, unit)
        if ok and plain(r) and r then return true end
    end
    if C_TooltipInfo and C_TooltipInfo.GetUnit then
        local ok, data = pcall(C_TooltipInfo.GetUnit, unit)
        if ok and DataHasQuest(data) then return true end
    end
    return false
end

---------------------------------------------------------------------------
-- Effets
---------------------------------------------------------------------------
local pool = {}

local function GetFx()
    for _, f in ipairs(pool) do if not f.busy then return f end end
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetFrameStrata("TOOLTIP")
    f:SetFrameLevel(1)
    f:SetSize(1, 1)
    f.tex = {}
    for i = 1, 3 do
        local t = f:CreateTexture(nil, "OVERLAY")
        t:SetBlendMode("ADD")
        t:SetPoint("CENTER")
        f.tex[i] = t
    end
    f:Hide()
    table.insert(pool, f)
    return f
end

local function Play(x, y)
    local d = DB()
    local f = GetFx()
    f.busy = true
    f.style = d.hlStyle or "ping"
    f.t = 0
    f.dur = (f.style == "halo") and 1.1 or 0.9
    f.size = 64 * (d.hlSize or 1)
    local c = COLORS[d.hlColor or "gold"] or COLORS.gold
    for i, t in ipairs(f.tex) do
        t:SetVertexColor(c[1], c[2], c[3], 1)
        t:SetTexture(MEDIA .. (f.style == "ping" and "ring" or f.style == "eclat" and (i == 1 and "star" or "glow") or "glow"))
        t:SetShown(f.style == "ping" or (f.style == "eclat" and i <= 2) or (f.style == "halo" and i <= 2))
        if f.style == "halo" and i == 2 then t:SetTexture(MEDIA .. "ring") end
    end
    local s = UIParent:GetEffectiveScale()
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / s, y / s)
    f:Show()
    if d.hlSound and PlaySound then pcall(PlaySound, 3175) end
end

local function Animate(f, e)
    f.t = f.t + e
    local p = f.t / f.dur
    if p >= 1 then f:Hide(); f.busy = false; return end
    local S = f.size
    if f.style == "ping" then
        -- trois anneaux aplatis (posés au sol) qui s'élargissent l'un après l'autre
        for i, t in ipairs(f.tex) do
            local q = p * 1.35 - (i - 1) * 0.17
            if q <= 0 or q >= 1 then t:SetAlpha(0)
            else
                local r = S * (0.35 + q * 0.9)
                t:SetSize(r * 2, r * 1.1)
                t:SetAlpha((1 - q) * 0.95)
            end
        end
    elseif f.style == "eclat" then
        -- étoile qui grossit, tourne un peu et s'éteint, avec une lueur
        local a = (p < 0.25) and (p / 0.25) or (1 - (p - 0.25) / 0.75)
        local star, glow = f.tex[1], f.tex[2]
        local r = S * (0.6 + 0.6 * math.sin(math.min(p, 0.5) * math.pi))
        star:SetSize(r * 1.6, r * 1.6)
        star:SetRotation(p * 0.8)
        star:SetAlpha(a)
        glow:SetSize(S * 1.8, S * 1.8)
        glow:SetAlpha(a * 0.55)
    else
        -- halo : lueur au sol qui monte puis s'efface, avec un fin contour
        local a = (p < 0.3) and (p / 0.3) or (1 - (p - 0.3) / 0.7)
        local glow, ring = f.tex[1], f.tex[2]
        glow:SetSize(S * 2.2, S * 1.2)
        glow:SetAlpha(a * 0.8)
        ring:SetSize(S * 1.9, S * 1.0)
        ring:SetAlpha(a * 0.6)
    end
end

---------------------------------------------------------------------------
-- Déclenchement
---------------------------------------------------------------------------
local lastKey, lastAt = nil, 0

local function Trigger(key)
    local now = GetTime()
    if key and key == lastKey and now - lastAt < 2.5 then return end
    lastKey, lastAt = key, now
    local x, y = GetCursorPosition()
    Play(x, y)
end

local function Allowed()
    if DB().hlCombat ~= false and InCombatLockdown() then return false end
    return true
end

local function OnMouseoverUnit()
    if not Allowed() or not UnitExists("mouseover") then return end
    if UnitIsPlayer("mouseover") then return end
    local hostile = UnitCanAttack("player", "mouseover")
    if hostile and not DB().hlMobs then return end
    if not hostile and not DB().hlNPCs then return end
    if not UnitIsQuest("mouseover") then return end
    local guid = UnitGUID("mouseover")
    Trigger(plain(guid) and guid or UnitName("mouseover"))
end

local function OnWorldCursor()
    if not Allowed() or not DB().hlObjects then return end
    if UnitExists("mouseover") then return end            -- c'est une créature : géré ci-dessus
    if not (C_TooltipInfo and C_TooltipInfo.GetWorldCursor) then return end
    local ok, data = pcall(C_TooltipInfo.GetWorldCursor)
    if not ok or not DataHasQuest(data) then return end
    local key = data.lines and data.lines[1] and data.lines[1].leftText
    Trigger(plain(key) and key or nil)
end

function M:Init()
    if NZR.withUI or not DB().questHL then return end
    InitLineTypes()
    local driver = CreateFrame("Frame")
    driver:SetScript("OnUpdate", function(_, e)
        for _, f in ipairs(pool) do if f.busy then Animate(f, e) end end
    end)
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
    pcall(ev.RegisterEvent, ev, "WORLD_CURSOR_TOOLTIP_UPDATE")
    ev:SetScript("OnEvent", function(_, e)
        if e == "UPDATE_MOUSEOVER_UNIT" then pcall(OnMouseoverUnit)
        else pcall(OnWorldCursor) end
    end)
    -- aperçu depuis les réglages
    NZR.HighlightTest = function()
        local x, y = GetCursorPosition()
        Play(x, y + 60 * UIParent:GetEffectiveScale())
    end
end
