-- NZR Forever - Outils : fenêtre de copie, journal d'erreurs, inspecteur d'éléments
-- But : quand un élément de Forever résiste, l'inspecteur donne en un clic
-- exactement ce qu'il faut pour le corriger (noms, textures, structure).
local ADDON, NZR = ...
local M = NZR:Module("Diag")
local C = NZR.C

---------------------------------------------------------------------------
-- Fenêtre de copie (texte sélectionné, Ctrl+C)
---------------------------------------------------------------------------
local copyWin
local function CopyWindow()
    if copyWin then return copyWin end
    local f = CreateFrame("Frame", "NZRF_Copy", UIParent, "BackdropTemplate")
    f:SetSize(620, 420)
    f:SetPoint("CENTER")
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetMovable(true); f:EnableMouse(true); f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    NZR:Skin(f, 0.98, nil, 8)
    NZR:AccentLine(f, "TOP", 2, 1)
    tinsert(UISpecialFrames, "NZRF_Copy")

    f.title = NZR:Text(f, 14, nil, "LEFT", true)
    f.title:SetPoint("TOPLEFT", 16, -14)
    f.hint = NZR:Text(f, 11, C.dim, "LEFT")
    f.hint:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -5)
    f.hint:SetText("Le texte est déjà sélectionné : Ctrl+C pour copier, puis colle-le à Claude.")

    local close = CreateFrame("Button", nil, f)
    close:SetSize(24, 24); close:SetPoint("TOPRIGHT", -8, -8)
    local cx = close:CreateFontString(nil, "OVERLAY")
    cx:SetFont(NZR.FONT, 20, ""); cx:SetPoint("CENTER", 0, 1); cx:SetText("×")
    cx:SetTextColor(C.dim[1], C.dim[2], C.dim[3])
    close:SetScript("OnClick", function() f:Hide() end)

    local area = CreateFrame("Frame", nil, f, "BackdropTemplate")
    area:SetPoint("TOPLEFT", 14, -56); area:SetPoint("BOTTOMRIGHT", -14, 14)
    NZR:FlatBackdrop(area, true, 1, 5)
    area:SetBackdropColor(0.03, 0.027, 0.045, 1)
    area:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)

    local sf = CreateFrame("ScrollFrame", "NZRF_CopyScroll", area, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 8, -8); sf:SetPoint("BOTTOMRIGHT", -28, 8)
    local eb = CreateFrame("EditBox", "NZRF_CopyEdit", sf)
    eb:SetMultiLine(true)
    eb:SetAutoFocus(false)
    eb:SetFont(NZR.FONT, 11, "")
    eb:SetWidth(540)
    eb:SetScript("OnEscapePressed", function() f:Hide() end)
    eb:SetScript("OnTextChanged", function(s, user) if user then s:SetText(f.text or ""); s:HighlightText() end end)
    sf:SetScrollChild(eb)
    f.eb = eb
    copyWin = f
    return f
end

local function ChatFallback(title, text)
    NZR:Print(title .. " (affiché ici car la fenêtre n'a pas pu s'ouvrir) :")
    local n = 0
    for line in tostring(text):gmatch("[^\n]+") do
        n = n + 1
        if n > 14 then print("  …") break end
        print("  " .. line)
    end
end

function NZR:ShowCopy(title, text)
    local ok = pcall(self.ShowCopyWindow, self, title, text)
    if not ok then ChatFallback(title, text) end
end

function NZR:ShowCopyWindow(title, text)
    local f = CopyWindow()
    f.title:SetText(title)
    f.text = text
    f.eb:SetText(text)
    f:Show()
    f.eb:SetFocus()
    f.eb:HighlightText()
end

---------------------------------------------------------------------------
-- Journal d'erreurs : seulement celles de NZR Forever, sans gêner les autres addons
---------------------------------------------------------------------------
NZR.errors = {}
local toast, lastToast = nil, 0

local function Toast(msg)
    if not toast then
        toast = CreateFrame("Button", nil, UIParent, "BackdropTemplate")
        toast:SetSize(380, 30)
        toast:SetPoint("TOP", 0, -120)
        toast:SetFrameStrata("FULLSCREEN_DIALOG")
        NZR:Skin(toast, 0.96, nil, 8)
        NZR:AccentLine(toast, "TOP", 2, 1)
        toast.text = NZR:Text(toast, 11.5, nil, "CENTER")
        toast.text:SetPoint("CENTER")
        toast:SetScript("OnClick", function(s) s:Hide(); SlashCmdList.NZRF("erreurs") end)
    end
    toast.text:SetText(msg)
    toast:Show()
    C_Timer.After(8, function() if toast then toast:Hide() end end)
end

function NZR:LogError(msg, where)
    local line = date("%H:%M:%S") .. "  " .. (where and ("[" .. where .. "] ") or "") .. tostring(msg)
    table.insert(self.errors, line)
    if #self.errors > 50 then table.remove(self.errors, 1) end
    if self.db then
        self.db.lastErrors = self.db.lastErrors or {}
        table.insert(self.db.lastErrors, line)
        while #self.db.lastErrors > 15 do table.remove(self.db.lastErrors, 1) end
    end
    if GetTime() - lastToast > 30 then
        lastToast = GetTime()
        Toast("|cffc7a4ffNZR|r : une erreur est survenue. Clique pour la voir.")
    end
end

local function HookErrors()
    local prev = geterrorhandler()
    seterrorhandler(function(msg, ...)
        if type(msg) == "string" and msg:find(ADDON, 1, true) then
            pcall(NZR.LogError, NZR, msg)
        end
        if prev then return prev(msg, ...) end
    end)
end

local function ErrorReport()
    local lines = { "NZR Forever " .. NZR.version .. "  ·  " .. (GetBuildInfo and table.concat({ GetBuildInfo() }, " / ") or "") , "" }
    local list = (#NZR.errors > 0) and NZR.errors or (NZR.db.lastErrors or {})
    if #list == 0 then table.insert(lines, "Aucune erreur enregistrée.") end
    for _, l in ipairs(list) do table.insert(lines, l) end
    return table.concat(lines, "\n")
end

---------------------------------------------------------------------------
-- Inspecteur : survole un élément, appuie sur Maj pour figer et copier
---------------------------------------------------------------------------
local function Describe(frame)
    if not frame then return "?" end
    local name = frame.GetName and frame:GetName()
    local key = frame.GetParentKey and frame:GetParentKey()
    local ot = frame.GetObjectType and frame:GetObjectType() or "?"
    local w, h = 0, 0
    if frame.GetSize then w, h = frame:GetSize() end
    local s = ot .. "  " .. (name or (key and ("." .. key)) or "(sans nom)")
    s = s .. ("  %dx%d"):format(w or 0, h or 0)
    if frame.GetFrameStrata then s = s .. "  " .. frame:GetFrameStrata() .. "/" .. (frame:GetFrameLevel() or 0) end
    if frame.IsForbidden and frame:IsForbidden() then s = s .. "  INTERDIT" end
    return s
end

local function Regions(frame, indent, out, max)
    local n = 0
    for _, r in ipairs({ frame:GetRegions() }) do
        if n >= max then table.insert(out, indent .. "…"); break end
        local t = r:GetObjectType()
        local key = r.GetParentKey and r:GetParentKey()
        local label = (r.GetName and r:GetName()) or (key and ("." .. key)) or ""
        if t == "Texture" then
            local a = r:GetAtlas()
            local tx = r:GetTexture()
            table.insert(out, ("%sTexture %s  atlas=%s  tex=%s  alpha=%.2f  %s"):format(indent, label, tostring(a), tostring(tx),
                r:GetAlpha() or 0, r:IsShown() and "visible" or "cachée"))
        elseif t == "FontString" then
            local ok, txt = pcall(r.GetText, r)
            if not ok or NZR.issecret(txt) then txt = "(secret)" end
            table.insert(out, ("%sTexte %s  \"%s\""):format(indent, label, tostring(txt or "")))
        end
        n = n + 1
    end
end

local function Tree(frame, depth, maxDepth, out, indent)
    if not frame or depth > maxDepth then return end
    table.insert(out, indent .. Describe(frame))
    pcall(Regions, frame, indent .. "    ", out, 14)
    for _, c in ipairs({ frame:GetChildren() }) do
        Tree(c, depth + 1, maxDepth, out, indent .. "  ")
    end
end

local function FocusFrame()
    if GetMouseFoci then
        local list = GetMouseFoci()
        return list and list[1]
    end
    return GetMouseFocus and GetMouseFocus()
end

local function InspectReport(frame)
    local out = { "NZR Forever " .. NZR.version .. "  ·  inspection", "" }
    if not frame or frame == WorldFrame then
        table.insert(out, "Aucun élément sous la souris (monde du jeu).")
        return table.concat(out, "\n")
    end
    table.insert(out, "Élément et ses parents :")
    local f, i = frame, 0
    while f and i < 6 do
        table.insert(out, ("  %d. %s"):format(i, Describe(f)))
        f = f.GetParent and f:GetParent()
        i = i + 1
    end
    table.insert(out, "")
    table.insert(out, "Contenu :")
    Tree(frame, 0, 2, out, "  ")
    local parent = frame.GetParent and frame:GetParent()
    if parent and parent ~= UIParent then
        table.insert(out, "")
        table.insert(out, "Contenu du parent :")
        Tree(parent, 0, 1, out, "  ")
    end
    return table.concat(out, "\n")
end

local inspector
local function StartInspector()
    if not inspector then
        inspector = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        inspector:SetSize(340, 64)
        inspector:SetFrameStrata("TOOLTIP")
        NZR:Skin(inspector, 0.95, nil, 5)
        NZR:AccentLine(inspector, "TOP", 2, 1)
        inspector.title = NZR:Text(inspector, 11, C.accent2, "LEFT", true)
        inspector.title:SetPoint("TOPLEFT", 10, -8)
        inspector.title:SetText("Inspecteur NZR  ·  Maj = copier  ·  Échap = quitter")
        inspector.line = NZR:Text(inspector, 11, nil, "LEFT")
        inspector.line:SetPoint("TOPLEFT", inspector.title, "BOTTOMLEFT", 0, -6)
        inspector.line:SetWidth(320)
        inspector.line:SetWordWrap(true)
        inspector.hl = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        inspector.hl:SetFrameStrata("TOOLTIP")
        NZR:FlatBackdrop(inspector.hl, false, 2)
        inspector.hl:SetBackdropBorderColor(C.accent2[1], C.accent2[2], C.accent2[3], 1)
        local acc = 0
        inspector:SetScript("OnUpdate", function(self, e)
            acc = acc + e
            local x, y = GetCursorPosition()
            local s = UIParent:GetEffectiveScale()
            self:ClearAllPoints()
            self:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x / s + 18, y / s + 18)
            if acc < 0.1 then return end
            acc = 0
            local f = FocusFrame()
            self.target = f
            self.line:SetText(f and Describe(f) or "monde du jeu")
            if f and f ~= WorldFrame and f.GetLeft and f:GetLeft() then
                self.hl:ClearAllPoints()
                self.hl:SetPoint("TOPLEFT", f, "TOPLEFT", -2, 2)
                self.hl:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 2, -2)
                self.hl:Show()
            else
                self.hl:Hide()
            end
            if IsShiftKeyDown() then
                self:Hide(); self.hl:Hide()
                NZR:ShowCopy("Inspection d'un élément", InspectReport(self.target))
            end
        end)
        inspector:SetScript("OnHide", function(self) self.hl:Hide() end)
        inspector:EnableKeyboard(true)
        inspector:SetPropagateKeyboardInput(true)
        inspector:SetScript("OnKeyDown", function(self, key)
            if key == "ESCAPE" then self:SetPropagateKeyboardInput(false); self:Hide()
                C_Timer.After(0, function() self:SetPropagateKeyboardInput(true) end) end
        end)
    end
    inspector:Show()
    NZR:Print("inspecteur actif : survole l'élément puis appuie sur |cffffffffMaj|r.")
end

-- barre au-dessus de ta cible (là où Forever cache ses images)
local function NameplateReport()
    local out = { "NZR Forever " .. NZR.version .. "  ·  barre de nom de la cible", "" }
    local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit("target")
    if not plate then
        table.insert(out, "Aucune barre trouvée : cible un monstre dont la barre est visible, puis recommence.")
        return table.concat(out, "\n")
    end
    table.insert(out, "UnitFrame présent : " .. tostring(plate.UnitFrame ~= nil))
    Tree(plate, 0, 5, out, "")
    return table.concat(out, "\n")
end

NZR.StartInspector = StartInspector
NZR.InspectNameplate = function() NZR:ShowCopy("Barre de nom de la cible", NameplateReport()) end
NZR.ShowErrors = function() NZR:ShowCopy("Erreurs NZR Forever", ErrorReport()) end

function M:Init()
    pcall(HookErrors)
end
