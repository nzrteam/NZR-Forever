-- NZR Forever - Infobulle, sacs et carte déplaçables (facultatif)
local _, NZR = ...
local M = NZR:Module("Movers")

---------------------------------------------------------------------------
-- Infobulle par défaut (survol d'un monstre, d'un joueur, du monde)
---------------------------------------------------------------------------
local function SetupTooltip()
    local hd = NZR:Holder("tooltip", "Infobulles", 200, 60, { "BOTTOMRIGHT", "BOTTOMRIGHT", -60, 200 })
    hd.scaled = false
    -- On ne touche jamais l'infobulle elle-même (sinon le jeu la vide aussitôt) :
    -- on déplace seulement son emplacement, le cadre « GameTooltipDefaultContainer »
    -- sur lequel le jeu l'accroche (coin bas-droit).
    local cont = _G.GameTooltipDefaultContainer
    if not cont then
        NZR:Print("infobulle : ce client ne permet pas de la déplacer sans la casser, option ignorée.")
        return
    end
    local function Place()
        if InCombatLockdown() and cont:IsProtected() then return end
        if NZR.db.tooltipCursor then return end
        cont:ClearAllPoints()
        cont:SetPoint("BOTTOMRIGHT", hd, "BOTTOMRIGHT", 0, 0)
    end
    Place()
    hd:HookScript("OnDragStop", Place)
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
    ev:SetScript("OnEvent", function() C_Timer.After(0.2, Place) end)
    -- à la souris : l'emplacement suit le curseur (l'infobulle reste celle du jeu)
    if NZR.db.tooltipCursor then
        local follow = CreateFrame("Frame")
        follow:SetScript("OnUpdate", function()
            if not GameTooltip:IsShown() then return end
            local x, y = GetCursorPosition()
            local s = UIParent:GetEffectiveScale()
            cont:ClearAllPoints()
            cont:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMLEFT", x / s - 14, y / s + 14)
        end)
    end
end

---------------------------------------------------------------------------
-- Sacs du jeu : Blizzard les empile depuis le coin bas-droit de l'écran.
-- On décale toute la pile selon la position de l'ancre "Sacs".
---------------------------------------------------------------------------
local BAG_DEFAULT = { "BOTTOMRIGHT", "BOTTOMRIGHT", -60, 110 }

local function SetupBags()
    local hd = NZR:Holder("bags", "Sacs", 340, 360, BAG_DEFAULT)
    hd.scaled = false

    local function Offset()
        local ux, uy = UIParent:GetRight(), UIParent:GetBottom()
        local hx, hy = hd:GetRight(), hd:GetBottom()
        if not (ux and hx) then return 0, 0 end
        -- décalage par rapport à la place d'origine (coin bas-droit - 60/110)
        return (hx - ux) - BAG_DEFAULT[3], (hy - uy) - BAG_DEFAULT[4]
    end

    local function Move(f, dx, dy)
        if not f or not f:IsShown() then return end
        if InCombatLockdown() and f.IsProtected and f:IsProtected() then return end
        local p, rel, rp, x, y = f:GetPoint(1)
        if rel == UIParent or rel == nil then
            f:ClearAllPoints()
            f:SetPoint(p, UIParent, rp, (x or 0) + dx, (y or 0) + dy)
        end
    end

    local function Reanchor()
        local dx, dy = Offset()
        if dx == 0 and dy == 0 then return end
        local cb = ContainerFrameCombinedBags
        if cb and cb:IsShown() then
            if not (InCombatLockdown() and cb:IsProtected()) then
                cb:ClearAllPoints()
                cb:SetPoint("BOTTOMRIGHT", hd, "BOTTOMRIGHT", 0, 0)
            end
        end
        for i = 1, (NUM_CONTAINER_FRAMES or 13) do
            pcall(Move, _G["ContainerFrame" .. i], dx, dy)
        end
    end

    if UpdateContainerFrameAnchors then
        hooksecurefunc("UpdateContainerFrameAnchors", function() pcall(Reanchor) end)
    end
    hd:HookScript("OnDragStop", function()
        if UpdateContainerFrameAnchors and not InCombatLockdown() then pcall(UpdateContainerFrameAnchors) end
    end)
end

---------------------------------------------------------------------------
-- Fenêtres du jeu : on les glisse par leur barre de titre, la position est
-- gardée ; clic droit sur la barre = place d'origine. Toutes celles que le jeu
-- ouvre comme « panneau » (personnage, sorts, talents, collections, PNJ…).
---------------------------------------------------------------------------
local KNOWN = {
    "CharacterFrame", "WorldMapFrame", "FriendsFrame", "MerchantFrame", "GossipFrame",
    "QuestFrame", "MailFrame", "OpenMailFrame", "SpellBookFrame", "PVEFrame", "DressUpFrame",
    "TradeFrame", "BankFrame", "AccountBankPanel", "GuildRegistrarFrame", "TabardFrame",
    "PetStableFrame", "ItemTextFrame", "AddonList", "QuestLogFrame", "HelpFrame",
    "ChannelFrame", "RaidParentFrame", "TaxiFrame", "LootFrame", "ProfessionsBookFrame",
    "ClassTrainerFrame", "PlayerSpellsFrame", "PlayerTalentFrame", "CollectionsJournal",
    "WardrobeFrame", "ProfessionsFrame", "TradeSkillFrame", "AuctionHouseFrame", "AuctionFrame",
    "CommunitiesFrame", "GuildFrame", "InspectFrame", "EncounterJournal", "MacroFrame",
    "FlightMapFrame", "ItemSocketingFrame", "AchievementFrame", "CalendarFrame",
    "WeeklyRewardsFrame", "ExpansionLandingPage", "GarrisonLandingPage", "ItemUpgradeFrame",
    "ItemInteractionFrame", "ScrappingMachineFrame", "AzeriteRespecFrame", "CovenantSanctumFrame",
    "GenericTraitFrame", "HousingDashboardFrame", "HouseEditorFrame", "VoidStorageFrame",
    "BlackMarketFrame", "ObliterumForgeFrame", "TimeManagerFrame", "LFGListApplicationDialog",
    "PlayerChoiceFrame", "QuestLogPopupDetailFrame", "BarberShopFrame", "ChatConfigFrame",
}
local NO_DRAG = { GameMenuFrame = true, SettingsPanel = true, StaticPopup1 = true }
local moved = {}

local function SavePos(f)
    local p, _, rp, x, y = f:GetPoint()
    if p then NZR.db.panelPos[f:GetName()] = { p, rp, x, y } end
end

local function Restore(f)
    local pos = NZR.db.panelPos[f:GetName()]
    if not pos or (InCombatLockdown() and f:IsProtected()) then return end
    f:ClearAllPoints()
    f:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
end

local function MakeMovable(f)
    if type(f) == "string" then f = _G[f] end
    if not f or type(f) ~= "table" or not f.GetName or f.nzrDrag then return end
    local name = f:GetName()
    if not name or NO_DRAG[name] or not f.CreateTexture then return end
    if f.IsForbidden and f:IsForbidden() then return end
    local d = CreateFrame("Frame", nil, f)
    d:SetPoint("TOPLEFT", 0, 0)
    d:SetPoint("TOPRIGHT", -60, 0)          -- on laisse libres les boutons de droite
    d:SetHeight(22)
    d:SetFrameLevel(f:GetFrameLevel() + 20)
    d:EnableMouse(true)
    d:RegisterForDrag("LeftButton")
    f.nzrDrag = d
    moved[f] = true
    d:SetScript("OnDragStart", function()
        if InCombatLockdown() and f:IsProtected() then return end
        f:SetMovable(true)
        f:SetClampedToScreen(true)
        f:StartMoving()
    end)
    d:SetScript("OnDragStop", function() f:StopMovingOrSizing(); SavePos(f) end)
    d:SetScript("OnMouseUp", function(_, btn)
        if btn == "RightButton" then
            NZR.db.panelPos[name] = nil
            if not (InCombatLockdown() and f:IsProtected()) then pcall(HideUIPanel, f); pcall(ShowUIPanel, f) end
        end
    end)
    d:SetScript("OnEnter", function(s)
        GameTooltip:SetOwner(s, "ANCHOR_TOP")
        GameTooltip:AddLine("Déplacer la fenêtre")
        GameTooltip:AddLine("Glisser : déplacer. Clic droit : remettre à sa place.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    d:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- le jeu replace la fenêtre à chaque ouverture : on remet la nôtre juste après
    f:HookScript("OnShow", function() C_Timer.After(0, function() Restore(f) end) end)
    if f:IsShown() then Restore(f) end
end

local function ScanAll()
    for _, n in ipairs(KNOWN) do pcall(MakeMovable, n) end
    if UIPanelWindows then
        for n in pairs(UIPanelWindows) do pcall(MakeMovable, n) end
    end
end

local function SetupWindows()
    ScanAll()
    -- fenêtres chargées plus tard (talents, collections, hôtel des ventes…)
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("ADDON_LOADED")
    ev:SetScript("OnEvent", function() C_Timer.After(0, ScanAll) end)
    -- toute fenêtre ouverte comme panneau par le jeu
    if ShowUIPanel then hooksecurefunc("ShowUIPanel", function(f) if f then pcall(MakeMovable, f) end end) end
    if UpdateUIPanelPositions then
        hooksecurefunc("UpdateUIPanelPositions", function()
            for f in pairs(moved) do if f:IsShown() then pcall(Restore, f) end end
        end)
    end
end

---------------------------------------------------------------------------
-- Butin : bouton « Tout ramasser » au style du jeu, sous la fenêtre de butin,
-- avec une touche active seulement tant que la fenêtre est ouverte.
---------------------------------------------------------------------------
local function SetupLoot()
    if not LootFrame then return end
    local b = CreateFrame("Button", "NZRF_LootAll", LootFrame, "UIPanelButtonTemplate")
    b:SetHeight(22)            -- taille normale des boutons du jeu (sinon le bord se déforme)
    b:SetPoint("TOP", LootFrame, "BOTTOM", 0, -1)
    local function Label()
        local key = NZR.db.lootKey
        b:SetText((key and key ~= "none") and ("Tout ramasser (" .. (key == "SPACE" and "Espace" or key) .. ")") or "Tout ramasser")
    end
    local oldLabel = Label
    Label = function()
        oldLabel()
        local fs = b:GetFontString()
        b:SetWidth(math.max(100, (fs and fs:GetStringWidth() or 90) + 40))
    end
    Label()
    b:SetScript("OnClick", function()
        local n = (GetNumLootItems and GetNumLootItems()) or 0
        for i = n, 1, -1 do pcall(LootSlot, i) end
    end)

    local owner = CreateFrame("Frame")
    local bound, pendingClear = false, false
    if not NZR.db.lootAll then b:Hide(); b.SetShown = function() end; b.Show = function() end end
    local function Bind()
        if not NZR.db.lootAll then return end
        local key = NZR.db.lootKey
        if InCombatLockdown() then return end
        if bound then ClearOverrideBindings(owner); bound = false end
        if not key or key == "none" then return end
        SetOverrideBindingClick(owner, true, key, "NZRF_LootAll")
        bound = true
    end
    local function Unbind()
        if not bound then return end
        if InCombatLockdown() then pendingClear = true; return end
        ClearOverrideBindings(owner)
        bound, pendingClear = false, false
    end
    LootFrame:HookScript("OnShow", function() Label(); Bind() end)
    LootFrame:HookScript("OnHide", Unbind)
    -- butin vide : on ferme la fenêtre tout seul
    local function HasLoot()
        local n = (GetNumLootItems and GetNumLootItems()) or 0
        for i = 1, n do
            if not LootSlotHasItem or LootSlotHasItem(i) then return true end
        end
        return false
    end
    local function CloseIfEmpty()
        if NZR.db.lootAutoClose == false then return end
        if LootFrame:IsShown() and not HasLoot() and CloseLoot then pcall(CloseLoot) end
    end
    owner:RegisterEvent("PLAYER_REGEN_ENABLED")
    owner:RegisterEvent("LOOT_CLOSED")
    owner:RegisterEvent("LOOT_OPENED")
    owner:RegisterEvent("LOOT_SLOT_CLEARED")
    owner:SetScript("OnEvent", function(_, ev)
        if ev == "LOOT_OPENED" or ev == "LOOT_SLOT_CLEARED" then
            C_Timer.After(0.15, CloseIfEmpty)
            return
        end
        if ev == "LOOT_CLOSED" or pendingClear or not LootFrame:IsShown() then Unbind() end
    end)
end

---------------------------------------------------------------------------
-- Infobulles opaques et toujours au premier plan (lisibles sur tout décor)
---------------------------------------------------------------------------
local function SetupOpaqueTooltips()
    local function Fix(tt)
        if not tt or (tt.IsForbidden and tt:IsForbidden()) then return end
        local a = NZR.db.tooltipAlpha or 1
        if tt.NineSlice and tt.NineSlice.SetCenterColor then
            pcall(tt.NineSlice.SetCenterColor, tt.NineSlice, 0.03, 0.03, 0.05, a)
        end
        if tt.SetFrameStrata and tt:GetFrameStrata() ~= "TOOLTIP" then tt:SetFrameStrata("TOOLTIP") end
    end
    for _, name in ipairs({ "GameTooltip", "ItemRefTooltip", "ShoppingTooltip1", "ShoppingTooltip2",
                            "EmbeddedItemTooltip", "WorldMapTooltip" }) do
        local tt = _G[name]
        if tt and tt.HookScript then tt:HookScript("OnShow", Fix) end
    end
    -- le jeu remet sa couleur à chaque contenu : on repasse derrière
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum.TooltipDataType then
        pcall(TooltipDataProcessor.AddTooltipPostCall, TooltipDataProcessor.AllTypes or Enum.TooltipDataType.Item, function(tt) Fix(tt) end)
    end
    if SharedTooltip_SetBackdropStyle then
        hooksecurefunc("SharedTooltip_SetBackdropStyle", function(tt) Fix(tt) end)
    end
end

function M:Init()
    if NZR.withUI then return end           -- NZR UI s'en charge déjà
    if NZR.db.tooltipOpaque ~= false and not NZR.db.tooltips then pcall(SetupOpaqueTooltips) end
    if NZR.db.lootAll or NZR.db.lootAutoClose ~= false then pcall(SetupLoot) end
    if NZR.db.moveTooltip or NZR.db.tooltipCursor then pcall(SetupTooltip) end
    if NZR.db.moveBags then pcall(SetupBags) end
    if NZR.db.moveWindows or NZR.db.moveMap then pcall(SetupWindows) end
end
