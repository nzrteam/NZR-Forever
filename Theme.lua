-- NZR Forever - Thème : barres d'action, infobulles, chat
local _, NZR = ...
local M = NZR:Module("Theme")
local C = NZR.C

---------------------------------------------------------------------------
-- Barres d'action : icônes carrées, bord fin, survol violet
---------------------------------------------------------------------------
local BAR_PREFIXES = {
    "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton",
    "MultiBarRightButton", "MultiBarLeftButton", "MultiBar5Button",
    "MultiBar6Button", "MultiBar7Button", "PetActionButton", "StanceButton",
}

local function StyleButton(b)
    if not b or b.nzr then return end
    b.nzr = true
    local icon = b.icon or b.Icon or (b:GetName() and _G[b:GetName() .. "Icon"])
    if icon then
        if b.IconMask then pcall(icon.RemoveMaskTexture, icon, b.IconMask) end
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        icon:ClearAllPoints()
        icon:SetPoint("TOPLEFT", 1, -1)
        icon:SetPoint("BOTTOMRIGHT", -1, 1)
    end
    local nt = b.NormalTexture or (b.GetNormalTexture and b:GetNormalTexture())
    if nt then nt:SetAlpha(0) end
    if b.SlotBackground then b.SlotBackground:SetAlpha(0) end
    if b.SlotArt then b.SlotArt:SetAlpha(0) end
    if b.RightDivider then b.RightDivider:SetAlpha(0) end
    if b.BottomDivider then b.BottomDivider:SetAlpha(0) end

    -- bord + fond (visible aussi sur les emplacements vides)
    local edge = b:CreateTexture(nil, "BACKGROUND", nil, -8)
    edge:SetAllPoints()
    edge:SetColorTexture(C.border[1], C.border[2], C.border[3], 1)
    local fill = b:CreateTexture(nil, "BACKGROUND", nil, -7)
    fill:SetPoint("TOPLEFT", 1, -1)
    fill:SetPoint("BOTTOMRIGHT", -1, 1)
    fill:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], 0.85)

    local a = C.accent
    local hl = b.GetHighlightTexture and b:GetHighlightTexture()
    if hl then
        hl:SetColorTexture(a[1], a[2], a[3], 0.22)
        hl:ClearAllPoints(); hl:SetPoint("TOPLEFT", 1, -1); hl:SetPoint("BOTTOMRIGHT", -1, 1)
    end
    local pt = b.GetPushedTexture and b:GetPushedTexture()
    if pt then
        pt:SetColorTexture(1, 1, 1, 0.15)
        pt:ClearAllPoints(); pt:SetPoint("TOPLEFT", 1, -1); pt:SetPoint("BOTTOMRIGHT", -1, 1)
    end
    local ct = b.GetCheckedTexture and b:GetCheckedTexture()
    if ct then
        ct:SetColorTexture(a[1], a[2], a[3], 0.35)
        ct:ClearAllPoints(); ct:SetPoint("TOPLEFT", 1, -1); ct:SetPoint("BOTTOMRIGHT", -1, 1)
    end

    -- textes (raccourci, charges, macro)
    local hk = b.HotKey or _G[(b:GetName() or "") .. "HotKey"]
    if hk then
        hk:SetFont(NZR.FONT_BOLD, 10, "OUTLINE")
        hk:ClearAllPoints(); hk:SetPoint("TOPRIGHT", -2, -3)
        hk:SetTextColor(C.accent2[1], C.accent2[2], C.accent2[3])
    end
    -- coins arrondis discrets sur tout le bouton
    NZR:RoundButton(b, { edge }, { fill, icon, hl, pt, ct, b.Flash, b.NewActionTexture, b.SpellHighlightTexture })
    local ct2 = b.Count or _G[(b:GetName() or "") .. "Count"]
    if ct2 then ct2:SetFont(NZR.FONT_BOLD, 11, "OUTLINE") end
    local nm = b.Name or _G[(b:GetName() or "") .. "Name"]
    if nm then nm:SetAlpha(0) end
end

local function StyleBarArt()
    for _, name in ipairs({ "MainMenuBar", "MainActionBar" }) do
        local bar = _G[name]
        if bar then
            if bar.EndCaps then bar.EndCaps:SetAlpha(0) end
            if bar.BorderArt then bar.BorderArt:SetAlpha(0) end
            if bar.Background then bar.Background:SetAlpha(0) end
            if bar.ActionBarPageNumber then bar.ActionBarPageNumber:SetAlpha(0.6) end
        end
    end
end

local function StyleAllButtons()
    for _, prefix in ipairs(BAR_PREFIXES) do
        for i = 1, 12 do StyleButton(_G[prefix .. i]) end
    end
    StyleBarArt()
end

---------------------------------------------------------------------------
-- Infobulles sombres, bord violet
---------------------------------------------------------------------------
local TOOLTIPS = {
    "GameTooltip", "ItemRefTooltip", "ShoppingTooltip1", "ShoppingTooltip2",
    "ItemRefShoppingTooltip1", "ItemRefShoppingTooltip2", "EmbeddedItemTooltip",
    "WorldMapTooltip", "QuestScrollFrameTooltip",
}

local function StyleTooltip(tt)
    if not tt or (tt.IsForbidden and tt:IsForbidden()) then return end
    if tt.NineSlice then tt.NineSlice:SetAlpha(0) end
    if not tt.nzrBG then
        -- notre propre fond, que Blizzard ne réinitialise pas
        local bg = CreateFrame("Frame", nil, tt, "BackdropTemplate")
        bg:SetAllPoints()
        bg:SetFrameLevel(math.max(0, tt:GetFrameLevel() - 1))
        NZR:Skin(bg, 0.94, nil, 5)
        bg.line = NZR:AccentLine(bg, "TOP", 2, 0.95)
        tt.nzrBG = bg
        if tt.SetBackdrop and not tt.NineSlice then pcall(tt.SetBackdrop, tt, nil) end
    end
    tt.nzrBG:SetFrameLevel(math.max(0, tt:GetFrameLevel() - 1))
end

local function StyleTooltips()
    for _, n in ipairs(TOOLTIPS) do
        local tt = _G[n]
        if tt then
            StyleTooltip(tt)
            tt:HookScript("OnShow", StyleTooltip)
        end
    end
    if SharedTooltip_SetBackdropStyle then
        hooksecurefunc("SharedTooltip_SetBackdropStyle", function(tt) StyleTooltip(tt) end)
    end
    if GameTooltip_SetBackdropStyle then
        hooksecurefunc("GameTooltip_SetBackdropStyle", function(tt) StyleTooltip(tt) end)
    end
    -- bord et liseré à la couleur de la qualité de l'objet, sinon accent NZR
    local function SetTipColor(tt, r, g, b)
        local bg = tt and tt.nzrBG
        if not bg then return end
        bg:SetBackdropBorderColor(r, g, b, 1)
        if bg.line then bg.line:SetGradient("HORIZONTAL", CreateColor(r, g, b, 0.95), CreateColor(r, g, b, 0.95)) end
    end
    local function ResetTip(tt)
        SetTipColor(tt, C.border[1], C.border[2], C.border[3])
        local bg = tt and tt.nzrBG
        if bg and bg.line then bg.line:SetGradient("HORIZONTAL", CreateColor(C.accent[1], C.accent[2], C.accent[3], 0.95), CreateColor(C.accent2[1], C.accent2[2], C.accent2[3], 0.95)) end
    end
    for _, n in ipairs(TOOLTIPS) do
        local tt = _G[n]
        if tt and tt.HookScript then pcall(tt.HookScript, tt, "OnTooltipCleared", ResetTip) end
    end
    if TooltipDataProcessor and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tt, data)
            if not tt or (tt.IsForbidden and tt:IsForbidden()) then return end
            local q
            if data and data.id and C_Item and C_Item.GetItemQualityByID then q = C_Item.GetItemQualityByID(data.id) end
            if not q and tt.GetItem then
                local _, link = tt:GetItem()
                if link and C_Item and C_Item.GetItemQualityByID then q = C_Item.GetItemQualityByID(link) end
            end
            local qc = q and q >= 2 and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
            if qc then SetTipColor(tt, qc.r, qc.g, qc.b) end
        end)
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tt)
            if tt ~= GameTooltip or tt:IsForbidden() then return end
            local ok, _, unit = pcall(tt.GetUnit, tt)
            if not ok or not unit or NZR.issecret(unit) then return end
            local ok2, isPlayer = pcall(UnitIsPlayer, unit)
            if ok2 and isPlayer == true then
                local _, cls = UnitClass(unit)
                local cc = cls and not NZR.issecret(cls) and RAID_CLASS_COLORS[cls]
                local line = GameTooltipTextLeft1
                if cc and line then line:SetTextColor(cc.r, cc.g, cc.b) end
            end
            local okt, tn = pcall(UnitName, unit .. "target")
            if okt and NZR.plain(tn) and tn ~= "" then
                local _, tc = UnitClass(unit .. "target")
                local cc2 = (not NZR.issecret(tc)) and tc and RAID_CLASS_COLORS[tc]
                local hex = cc2 and cc2:GenerateHexColor() or "ffece9f3"
                GameTooltip:AddLine("Cible : |c" .. hex .. tn .. "|r", 0.6, 0.58, 0.66)
            end
        end)
    end
    local sb = GameTooltipStatusBar
    if sb then
        sb:SetStatusBarTexture(NZR.TEX)
        sb:SetHeight(4)
        sb:ClearAllPoints()
        sb:SetPoint("BOTTOMLEFT", GameTooltip, "BOTTOMLEFT", 2, 2)
        sb:SetPoint("BOTTOMRIGHT", GameTooltip, "BOTTOMRIGHT", -2, 2)
        hooksecurefunc(sb, "SetStatusBarColor", function(s)
            if s.nzrLock then return end
            s.nzrLock = true
            s:SetStatusBarColor(C.accent[1], C.accent[2], C.accent[3])
            s.nzrLock = false
        end)
    end
end

function M:Init()
    if not NZR.db.theme then return end
    StyleAllButtons()
    -- les infobulles gardent l'apparence du jeu (réglages dans Pratique > Infobulles)
    -- les barres peuvent être (re)créées par le mode Édition
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:RegisterEvent("UPDATE_BONUS_ACTIONBAR")
    f:SetScript("OnEvent", function() StyleAllButtons() end)
    if EditModeManagerFrame then
        EditModeManagerFrame:HookScript("OnHide", StyleAllButtons)
    end
end
