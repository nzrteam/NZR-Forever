-- NZR Forever - Bénédictions (assistant paladin, façon PallyPower, en français)
-- • Répartition : chaque paladin du groupe reçoit une bénédiction par classe ;
--   tout est partagé entre les paladins qui ont NZR Forever.
-- • Barre : un bouton par classe du groupe avec ta bénédiction ; il montre qui
--   en manque et le temps restant. Clic gauche = version supérieure (toute la
--   classe), clic droit = version simple sur un joueur qui en manque.
-- Désactivé de base (Réglages > Paladin). Ne fait rien si tu n'es pas paladin.
local _, NZR = ...
local M = NZR:Module("Paladin")

local PREFIX = "NZRFBLESS"
local SYMBOL_OF_KINGS = 21177

-- bénédictions (rang 1 / version supérieure) : noms et icônes lus dans le jeu
local BLESS = {
    { key = "might",  id = 19740, gid = 25782, short = "Puissance" },
    { key = "wisdom", id = 19742, gid = 25894, short = "Sagesse" },
    { key = "kings",  id = 20217, gid = 25898, short = "Rois" },
    { key = "salv",   id = 1038,  gid = 25895, short = "Salut" },
    { key = "light",  id = 19977, gid = 25890, short = "Lumière" },
    { key = "sanc",   id = 20911, gid = 25899, short = "Sanctuaire" },
}
local BY_KEY = {}
for i, b in ipairs(BLESS) do b.index = i; BY_KEY[b.key] = b end

local CLASS_ORDER = { "WARRIOR", "ROGUE", "HUNTER", "DRUID", "SHAMAN", "PALADIN", "PRIEST", "MAGE", "WARLOCK",
                      "DEATHKNIGHT", "MONK", "DEMONHUNTER", "EVOKER" }
local CLASSIC_CLASSES = { WARRIOR = true, ROGUE = true, HUNTER = true, DRUID = true, SHAMAN = true,
                          PALADIN = true, PRIEST = true, MAGE = true, WARLOCK = true }

-- ordre conseillé pour la répartition automatique
local PRIO = {
    WARRIOR = { "might", "kings", "light", "sanc", "salv" },
    ROGUE   = { "might", "kings", "salv", "light" },
    HUNTER  = { "might", "kings", "wisdom", "salv", "light" },
    DRUID   = { "wisdom", "kings", "salv", "might", "light" },
    SHAMAN  = { "wisdom", "kings", "salv", "might", "light" },
    PALADIN = { "wisdom", "kings", "might", "salv", "light" },
    PRIEST  = { "wisdom", "kings", "salv", "light" },
    MAGE    = { "wisdom", "kings", "salv", "light" },
    WARLOCK = { "wisdom", "kings", "salv", "light" },
}
local PRIO_DEFAULT = { "might", "kings", "wisdom", "salv", "light" }

local function plain(v)
    if issecretvalue and issecretvalue(v) then return false end
    return v ~= nil
end

local function SpellName(id)
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(id)
        if info then return info.name, info.iconID end
    end
    if GetSpellInfo then
        local n, _, icon = GetSpellInfo(id)
        return n, icon
    end
end

local function LoadNames()
    for _, b in ipairs(BLESS) do
        b.name, b.icon = SpellName(b.id)
        b.gname, b.gicon = SpellName(b.gid)
        b.name = b.name or b.short
    end
end

local function KnowsSpell(id, name)
    if IsPlayerSpell and IsPlayerSpell(id) then return true end
    if IsSpellKnown and IsSpellKnown(id) then return true end
    if name and C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, name)
        if ok and info and info.spellID and IsPlayerSpell and IsPlayerSpell(info.spellID) then return true end
    end
    return false
end

local function MyName()
    local n = UnitName("player")
    return n
end

local function ShortName(full)
    return (full or ""):match("^([^%-]+)") or full
end

local function ClassName(cls)
    return (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[cls]) or cls
end

local function ClassColor(cls)
    local c = (C_ClassColor and C_ClassColor.GetClassColor and C_ClassColor.GetClassColor(cls)) or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[cls])
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

local function SetClassIcon(tex, cls)
    local atlas = "classicon-" .. cls:lower()
    if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then
        tex:SetAtlas(atlas)
        return
    end
    tex:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
    local c = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[cls]
    if c then tex:SetTexCoord(c[1], c[2], c[3], c[4]) end
end

local function DB() return NZR.db end

---------------------------------------------------------------------------
-- Groupe et paladins
---------------------------------------------------------------------------
local roster = {}        -- [classFile] = { unit, unit, ... }
local paladins = {}      -- [nom] = { known = { key = true }, me = bool, nzr = bool (a NZR Forever) }
-- ce que les paladins SANS NZR Forever lancent vraiment, vu sur le groupe : [nom][classe] = clé
local seen = {}

local function Units()
    local list = {}
    if IsInRaid and IsInRaid() then
        for i = 1, (GetNumGroupMembers() or 0) do list[#list + 1] = "raid" .. i end
    else
        list[1] = "player"
        if IsInGroup and IsInGroup() then
            for i = 1, 4 do if UnitExists("party" .. i) then list[#list + 1] = "party" .. i end end
        end
    end
    return list
end

local function ScanRoster()
    wipe(roster)
    local seenPal = {}
    for _, u in ipairs(Units()) do
        if UnitExists(u) then
            local _, cls = UnitClass(u)
            if cls then
                roster[cls] = roster[cls] or {}
                table.insert(roster[cls], u)
                if cls == "PALADIN" and not UnitIsUnit(u, "player") then
                    local n = UnitName(u)
                    if n then
                        seenPal[n] = true
                        paladins[n] = paladins[n] or { known = {} }
                    end
                end
            end
        end
    end
    -- on oublie les paladins partis
    for n in pairs(paladins) do if not seenPal[n] and n ~= MyName() then paladins[n] = nil end end
    local me = MyName()
    paladins[me] = paladins[me] or { known = {} }
    paladins[me].me = true
    paladins[me].nzr = true
    for n in pairs(seen) do if not paladins[n] then seen[n] = nil end end
    for _, b in ipairs(BLESS) do paladins[me].known[b.key] = KnowsSpell(b.id, b.name) or nil end
end

local function GroupClasses()
    local list = {}
    for _, cls in ipairs(CLASS_ORDER) do
        if roster[cls] then list[#list + 1] = cls end
    end
    -- « Toutes les classes » (case de la fenêtre) : pour préparer la répartition à l'avance
    if DB().blessAllClasses then
        list = {}
        for _, cls in ipairs(CLASS_ORDER) do if CLASSIC_CLASSES[cls] then list[#list + 1] = cls end end
    end
    return list
end

local function SortedPaladins()
    local list = {}
    for n in pairs(paladins) do list[#list + 1] = n end
    table.sort(list, function(a, b)
        if paladins[a].me ~= paladins[b].me then return paladins[a].me and true or false end
        return a < b
    end)
    return list
end

local function HasNZR(pal) return paladins[pal] and paladins[pal].nzr end
-- répartition d'un paladin : la sienne s'il a NZR Forever, sinon ce qu'on le voit lancer
local function Assign(pal, cls)
    if paladins[pal] and not paladins[pal].nzr then return seen[pal] and seen[pal][cls] end
    return DB().blessAssign[pal] and DB().blessAssign[pal][cls]
end
local function SetAssign(pal, cls, key)
    DB().blessAssign[pal] = DB().blessAssign[pal] or {}
    DB().blessAssign[pal][cls] = key
end

---------------------------------------------------------------------------
-- Partage entre paladins (messages d'addon, groupe ou raid)
---------------------------------------------------------------------------
local function Channel()
    if IsInRaid and IsInRaid() then return "RAID" end
    if IsInGroup and IsInGroup() then return "PARTY" end
end

local function Send(msg)
    local ch = Channel()
    if not ch or not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return end
    pcall(C_ChatInfo.SendAddonMessage, PREFIX, msg, ch)
end

local function SendHello()
    local me = MyName()
    local known, assign = {}, {}
    for _, b in ipairs(BLESS) do if paladins[me] and paladins[me].known[b.key] then known[#known + 1] = b.key end end
    for cls, key in pairs(DB().blessAssign[me] or {}) do assign[#assign + 1] = cls .. ":" .. key end
    Send("H|" .. table.concat(known, ",") .. "|" .. table.concat(assign, ";"))
end

---------------------------------------------------------------------------
-- Compatibilité PallyPower (même canal d'addon « PLPWR ») : un paladin avec PallyPower
-- compte comme s'il avait NZR Forever. On ne reprend aucun code de PallyPower, seulement
-- le format de ses messages : SELF (sorts connus @ répartition par classe), ASSIGN, PASSIGN, REQ.
---------------------------------------------------------------------------
local PP_PREFIX = "PLPWR"
local PP_SKILL = { "wisdom", "might", "kings", "salv", "light", "sanc" }        -- 1 à 6
local PP_SKILL_ID = {}; for i, k in ipairs(PP_SKILL) do PP_SKILL_ID[k] = i end
local PP_CLASS = { "WARRIOR", "ROGUE", "PRIEST", "DRUID", "PALADIN", "HUNTER", "MAGE", "WARLOCK", "SHAMAN" }
local PP_CLASS_ID = {}; for i, c in ipairs(PP_CLASS) do PP_CLASS_ID[c] = i end

local function SendPP(msg)
    local ch = Channel()
    if not ch or not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return end
    pcall(C_ChatInfo.SendAddonMessage, PP_PREFIX, msg, ch)
end

-- mon « SELF » façon PallyPower : 6 × (rang, talent) puis @ et 9 cases de répartition
local function SendPPSelf()
    local me = MyName()
    local known = paladins[me] and paladins[me].known or {}
    local s = ""
    for _, k in ipairs(PP_SKILL) do s = s .. (known[k] and "10" or "nn") end
    s = s .. "@"
    local mine = DB().blessAssign[me] or {}
    for _, cls in ipairs(PP_CLASS) do
        local k = mine[cls]
        s = s .. (k and PP_SKILL_ID[k] and tostring(PP_SKILL_ID[k]) or "n")
    end
    SendPP("SELF " .. s)
end

local function SendAssign(pal, cls, key)
    Send("A|" .. pal .. "|" .. cls .. "|" .. (key or "-"))
    -- les paladins avec PallyPower suivent aussi le changement
    local cid = PP_CLASS_ID[cls]
    if cid then SendPP(("ASSIGN %s %d %d"):format(pal, cid, key and PP_SKILL_ID[key] or 0)) end
end

local refreshAll   -- défini plus bas

-- l'expéditeur d'un message n'a pas toujours le même format que le nom du groupe
-- (royaume, prénom + nom…) : on le ramène au nom du groupe, et on se reconnaît soi-même
local function first(s) return s and s:match("^(%S+)") end
local function ResolveSender(sender)
    local s = sender or ""
    if Ambiguate then local ok, v = pcall(Ambiguate, s, "none"); if ok and v then s = v end end
    local short = ShortName(s)
    -- 1) correspondance exacte, 2) même premier mot
    for pass = 1, 2 do
        for _, u in ipairs(Units()) do
            if UnitExists(u) then
                local n = UnitName(u)
                local full = GetUnitName and GetUnitName(u, true)
                local hit
                if pass == 1 then hit = (n == s or n == short or full == s)
                else hit = n and first(n) == first(short) end
                if hit then return n, UnitIsUnit(u, "player") end
            end
        end
    end
    return short, short == MyName()
end

local function OnPPMessage(msg, sender)
    local from, isMe = ResolveSender(sender)
    if isMe or from == MyName() then return end
    if msg == "REQ" then SendPPSelf(); return end
    local function apply(pal, list)
        DB().blessAssign[pal] = {}
        for i, cls in ipairs(PP_CLASS) do
            local c = list:sub(i, i)
            local key = PP_SKILL[tonumber(c) or 0]
            if key then DB().blessAssign[pal][cls] = key end
        end
    end
    local ranks, list = msg:match("^SELF ([0-9a-fn]*)@([0-9n]*)")
    if ranks then
        paladins[from] = paladins[from] or { known = {} }
        paladins[from].nzr, paladins[from].pp = true, true
        wipe(paladins[from].known)
        for i, k in ipairs(PP_SKILL) do
            local r = ranks:sub((i - 1) * 2 + 1, (i - 1) * 2 + 1)
            if r ~= "" and r ~= "n" then paladins[from].known[k] = true end
        end
        apply(from, list or "")
        refreshAll()
        return
    end
    local name, cid, sid = msg:match("^ASSIGN (.+) (%d+) (%d+)$")
    if name then
        local pal = ResolveSender(name)
        local cls = PP_CLASS[tonumber(cid)]
        if pal and cls then
            SetAssign(pal, cls, PP_SKILL[tonumber(sid)])
            if paladins[pal] then paladins[pal].nzr = true end
            refreshAll()
        end
        return
    end
    local pname, plist = msg:match("^PASSIGN (.+)@([0-9n]*)$")
    if pname then
        local pal = ResolveSender(pname)
        if pal then apply(pal, plist); refreshAll() end
    end
end

local function OnMessage(msg, sender)
    local from, isMe = ResolveSender(sender)
    if isMe or from == MyName() then return end
    local kind, a, b, c = strsplit("|", msg)
    if paladins[from] then paladins[from].nzr = true end
    if kind == "H" then
        paladins[from] = paladins[from] or { known = {} }
        paladins[from].nzr = true
        wipe(paladins[from].known)
        for k in (a or ""):gmatch("[^,]+") do paladins[from].known[k] = true end
        DB().blessAssign[from] = {}
        for pair in (b or ""):gmatch("[^;]+") do
            local cls, key = pair:match("^(%u+):(%w+)$")
            if cls and BY_KEY[key] then DB().blessAssign[from][cls] = key end
        end
        refreshAll()
    elseif kind == "A" then
        local pal, cls, key = a, b, c
        if pal and cls then
            SetAssign(pal, cls, (key and BY_KEY[key]) and key or nil)
            refreshAll()
        end
    elseif kind == "Q" then
        SendHello()
    end
end

---------------------------------------------------------------------------
-- Qui a ma bénédiction ? (hors combat : en combat le jeu cache ces infos)
---------------------------------------------------------------------------
local function AuraOn(unit, b)
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName) then return end
    for _, n in ipairs({ b.name, b.gname }) do
        if n then
            local ok, aura = pcall(C_UnitAuras.GetAuraDataBySpellName, unit, n, "HELPFUL")
            if ok and aura then
                local exp = aura.expirationTime
                if plain(exp) and exp > 0 then return exp - GetTime() end
                return 0
            end
        end
    end
end

local function InRange(unit, name)
    if C_Spell and C_Spell.IsSpellInRange then
        local ok, r = pcall(C_Spell.IsSpellInRange, name, unit)
        if ok and plain(r) then return r == true or r == 1 end
    end
    if UnitInRange then
        local ok, r = pcall(UnitInRange, unit)
        if ok and plain(r) then return r and true or false end
    end
    return true
end

local function ClassStatus(cls, b)
    local missing, minLeft, target, targetFar = {}, nil, nil, nil
    for _, u in ipairs(roster[cls] or {}) do
        if UnitExists(u) and not UnitIsDeadOrGhost(u) and UnitIsConnected(u) then
            local left = AuraOn(u, b)
            if left then
                if left > 0 and (not minLeft or left < minLeft) then minLeft = left end
            else
                missing[#missing + 1] = u
                if InRange(u, b.name) then target = target or u else targetFar = targetFar or u end
            end
        end
    end
    -- tout le monde l'a : on vise le plus pressé à rafraîchir (premier de la classe)
    local any = (roster[cls] or {})[1]
    return missing, minLeft, target or targetFar or any
end

---------------------------------------------------------------------------
-- Paladins sans NZR Forever : on regarde qui a posé quelle bénédiction sur qui
-- (hors combat : en combat le jeu cache le lanceur), et je m'adapte pour ne pas l'écraser
---------------------------------------------------------------------------
local function CasterPaladin(aura)
    local src = aura and aura.sourceUnit
    if not plain(src) or type(src) ~= "string" then return end
    local ok, mine = pcall(UnitIsUnit, src, "player")
    if not ok or mine then return end
    local okC, _, cls = pcall(UnitClass, src)
    if not okC or cls ~= "PALADIN" then return end
    local okN, n = pcall(UnitName, src)
    if okN and plain(n) then return n end
end

local function Observe()
    if InCombatLockdown() or not (C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName) then return false end
    local fresh = {}
    for cls, units in pairs(roster) do
        for _, u in ipairs(units) do
            if UnitExists(u) and UnitIsConnected(u) then
                for _, b in ipairs(BLESS) do
                    for _, n in ipairs({ b.name, b.gname }) do
                        if n then
                            local ok, aura = pcall(C_UnitAuras.GetAuraDataBySpellName, u, n, "HELPFUL")
                            local pal = ok and CasterPaladin(aura)
                            if pal and paladins[pal] and not paladins[pal].nzr then
                                fresh[pal] = fresh[pal] or {}
                                fresh[pal][cls] = b.key
                            end
                        end
                    end
                end
            end
        end
    end
    -- on garde le dernier vu tant qu'il est là (une bénédiction expirée ne l'efface pas tout de suite)
    local changed = false
    for pal, list in pairs(fresh) do
        seen[pal] = seen[pal] or {}
        for cls, key in pairs(list) do
            if seen[pal][cls] ~= key then seen[pal][cls] = key; changed = true end
        end
    end
    return changed
end

-- ma bénédiction pour une classe est déjà posée par un paladin sans NZR : je passe à la suivante libre
local function Adapt()
    local me = MyName()
    if not paladins[me] then return end
    local known = paladins[me].known or {}
    for _, cls in ipairs(GroupClasses()) do
        local mine = DB().blessAssign[me] and DB().blessAssign[me][cls]
        if mine then
            local used, by = {}, nil
            for n in pairs(paladins) do
                if n ~= me then
                    local k = Assign(n, cls)
                    if k then used[k] = true; if k == mine and not HasNZR(n) then by = n end end
                end
            end
            if by then
                local new
                for _, key in ipairs(PRIO[cls] or PRIO_DEFAULT) do
                    if (next(known) == nil or known[key]) and not used[key] then new = key; break end
                end
                SetAssign(me, cls, new); SendAssign(me, cls, new)
                NZR:Print(("Bénédictions : %s pose déjà %s sur la classe %s, tu passes %s."):format(
                    by, BY_KEY[mine].short, ClassName(cls),
                    new and ("à " .. BY_KEY[new].short) or "à rien (plus de bénédiction libre)"))
            end
        end
    end
end

---------------------------------------------------------------------------
-- Barre de lancement (boutons sécurisés)
---------------------------------------------------------------------------
local bar, buttons = nil, {}
local pending = false

local function GameFrame(f, alpha)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", 3, -3); bg:SetPoint("BOTTOMRIGHT", -3, 3)
    bg:SetColorTexture(0.03, 0.03, 0.05, alpha or 0.85)
    local ns = CreateFrame("Frame", nil, f, "NineSlicePanelTemplate")
    ns:SetAllPoints()
    if NineSliceUtil and pcall(NineSliceUtil.ApplyLayoutByName, ns, "TooltipDefaultLayout") then
        if ns.Center then ns.Center:Hide() end
    else
        ns:Hide()
    end
    f.nzrBg = bg
end

local function FormatTime(s)
    if not s then return "" end
    if s >= 60 then return ("%d min"):format(math.floor(s / 60)) end
    return ("%d s"):format(math.floor(s))
end

local function MakeButton(i)
    local b = CreateFrame("Button", "NZRF_BlessButton" .. i, bar, "SecureActionButtonTemplate")
    b:SetSize(150, 34)
    b:SetFrameLevel(bar:GetFrameLevel() + 8)
    b:RegisterForClicks("AnyUp", "AnyDown")
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(30, 30); b.icon:SetPoint("LEFT", 2, 0)
    b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    b.cls = b:CreateTexture(nil, "OVERLAY")
    b.cls:SetSize(15, 15); b.cls:SetPoint("BOTTOMRIGHT", b.icon, "BOTTOMRIGHT", 3, -3)
    b.name = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.name:SetPoint("TOPLEFT", b.icon, "TOPRIGHT", 7, -2); b.name:SetJustifyH("LEFT")
    b.state = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.state:SetPoint("BOTTOMLEFT", b.icon, "BOTTOMRIGHT", 7, 2); b.state:SetJustifyH("LEFT")
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(); hl:SetColorTexture(1, 0.82, 0, 0.12)
    b:SetScript("OnEnter", function(s)
        if not s.blessing then return end
        GameTooltip:SetOwner(s, "ANCHOR_LEFT")
        GameTooltip:AddLine(s.blessing.name ..  "  -  " .. ClassName(s.class), 1, 0.82, 0)
        if #s.missing > 0 then
            GameTooltip:AddLine("Il manque à :", 1, 1, 1)
            for _, u in ipairs(s.missing) do
                local r, g, bl = ClassColor(s.class)
                GameTooltip:AddLine("  " .. (UnitName(u) or "?"), r, g, bl)
            end
        else
            GameTooltip:AddLine("Tout le monde l'a.", 0.4, 1, 0.4)
        end
        GameTooltip:AddLine(" ")
        if DB().blessGreater and s.blessing.gname and KnowsSpell(s.blessing.gid, s.blessing.gname) then
            GameTooltip:AddLine("Clic gauche : " .. s.blessing.gname .. " (toute la classe)", 0.8, 0.8, 0.8)
        else
            GameTooltip:AddLine("Clic gauche : " .. s.blessing.name, 0.8, 0.8, 0.8)
        end
        GameTooltip:AddLine("Clic droit : " .. s.blessing.name .. " sur un joueur qui en manque", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    buttons[i] = b
    return b
end

-- largeur : icône + texte centrés dans le cadre, la barre suit le contenu
local function FitBar()
    if not bar or InCombatLockdown() then return end
    local shown = bar.count or 0
    local content = 100
    for i = 1, shown do
        local b = buttons[i]
        local w = 39 + math.max(b.name:GetStringWidth() or 0, b.state:GetStringWidth() or 0)
        if w > content then content = w end
    end
    content = math.min(content, 220)
    for i = 1, shown do buttons[i]:SetWidth(content) end
    bar:SetWidth(math.max(140, content + 28, (bar.info:GetStringWidth() or 0) + 24))
    bar.empty:SetWidth(bar:GetWidth() - 20)
end

local function LayoutBar()
    if not bar then return end
    if InCombatLockdown() then pending = true; return end
    local me = MyName()
    local shown = 0
    for _, cls in ipairs(GroupClasses()) do
        local key = Assign(me, cls)
        local bl = key and BY_KEY[key]
        if bl and roster[cls] then
            shown = shown + 1
            local b = buttons[shown] or MakeButton(shown)
            b.class, b.blessing = cls, bl
            b.icon:SetTexture(bl.icon)
            SetClassIcon(b.cls, cls)
            b:ClearAllPoints()
            b:SetPoint("TOP", bar, "TOP", 0, -22 - (shown - 1) * 36)
            b:Show()
        end
    end
    for i = shown + 1, #buttons do buttons[i]:Hide(); buttons[i].class = nil end
    bar.count = shown
    -- la taille suit le nombre de classes : seul = un bouton, en raid = un par classe
    bar:SetHeight(42 + math.max(1, shown) * 36)
    FitBar()
    bar.empty:SetShown(shown == 0)
end

local function UpdateButtons()
    if not bar or not bar:IsShown() then return end
    local inCombat = InCombatLockdown()
    for i = 1, (bar.count or 0) do
        local b = buttons[i]
        local r, g, bl = ClassColor(b.class)
        b.name:SetText(ClassName(b.class)); b.name:SetTextColor(r, g, bl)
        -- en combat, le jeu cache les buffs des autres : on garde le dernier état connu
        -- (sinon tout passe à « sans » alors que la bénédiction est bien là)
        local missing, minLeft, target
        if inCombat and b.lastState then
            missing, minLeft, target = b.lastState.missing, b.lastState.minLeft, b.lastState.target
            if minLeft then minLeft = minLeft - (GetTime() - b.lastState.at) end
        else
            missing, minLeft, target = ClassStatus(b.class, b.blessing)
            b.lastState = { missing = missing, minLeft = minLeft, target = target, at = GetTime(), cls = b.class }
        end
        if b.lastState and b.lastState.cls ~= b.class then b.lastState = nil end
        b.missing = missing
        local total = #(roster[b.class] or {})
        if #missing > 0 then
            b.state:SetText(("|cffff5050Sans : %d / %d|r"):format(#missing, total))
            b.icon:SetDesaturated(true)
        else
            b.state:SetText(minLeft and minLeft > 0 and ("|cff80ff80%s|r"):format(FormatTime(minLeft)) or "|cff80ff80OK|r")
            b.icon:SetDesaturated(false)
        end
        if not inCombat and target then
            local useGreater = DB().blessGreater and b.blessing.gname and KnowsSpell(b.blessing.gid, b.blessing.gname)
            b:SetAttribute("type1", "spell")
            b:SetAttribute("spell1", useGreater and b.blessing.gname or b.blessing.name)
            b:SetAttribute("unit1", target)
            b:SetAttribute("type2", "spell")
            b:SetAttribute("spell2", b.blessing.name)
            b:SetAttribute("unit2", (missing[1]) or target)
        end
    end
    -- aura et symboles des rois
    local form = GetShapeshiftForm and GetShapeshiftForm() or 0
    local syms = (C_Item and C_Item.GetItemCount and C_Item.GetItemCount(SYMBOL_OF_KINGS)) or (GetItemCount and GetItemCount(SYMBOL_OF_KINGS)) or 0
    bar.info:SetText(((form == 0) and "|cffff5050Aucune aura|r   " or "") .. ("Symboles : %d"):format(syms))
    FitBar()
end

local function CreateBar()
    bar = CreateFrame("Frame", "NZRF_BlessBar", UIParent)
    bar:SetSize(166, 80)
    bar:SetFrameStrata("MEDIUM")
    bar:SetClampedToScreen(true)
    bar:SetMovable(true)
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    NZR:WowFrame(bar, "Bénédictions", 0.9, 0.8)
    bar.info = bar.nzrOver:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    bar.info:SetPoint("BOTTOM", 0, 6); bar.info:SetJustifyH("CENTER")
    bar.empty = bar.nzrOver:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.empty:SetPoint("TOPLEFT", 10, -24); bar.empty:SetWidth(146); bar.empty:SetJustifyH("LEFT")
    bar.empty:SetText("Rien d'attribué. Clic droit ici ou /nzr bene pour répartir.")
    local p = DB().blessPos
    if p then bar:SetPoint(p[1], UIParent, p[2], p[3], p[4]) else bar:SetPoint("LEFT", UIParent, "LEFT", 30, 120) end
    bar:SetScale(DB().blessScale or 1)
    bar:SetScript("OnDragStart", function(s)
        if (DB().blessLock and not NZR.editing) or InCombatLockdown() then return end
        s:StartMoving()
    end)
    bar:SetScript("OnDragStop", function(s)
        s:StopMovingOrSizing()
        local a, _, r, x, y = s:GetPoint()
        DB().blessPos = { a, r, x, y }
    end)
    bar:SetScript("OnMouseUp", function(_, btn) if btn == "RightButton" and NZR.BlessOpen then NZR.BlessOpen() end end)
    local acc = 0
    bar:SetScript("OnUpdate", function(_, e)
        acc = acc + e
        if acc < 1 then return end
        acc = 0
        pcall(UpdateButtons)
    end)
end

local function ShouldShowBar()
    if not DB().paladin then return false end
    if DB().blessSolo == false and not (IsInGroup and IsInGroup()) then return false end
    return true
end

---------------------------------------------------------------------------
-- Fenêtre de répartition (cadre du jeu)
---------------------------------------------------------------------------
local win
local CELL = 34

local function CycleKnown(pal, cls, dir)
    local known = paladins[pal] and paladins[pal].known or {}
    local anyKnown = next(known) ~= nil
    local cur = Assign(pal, cls)
    local idx = cur and BY_KEY[cur].index or 0
    for _ = 1, #BLESS + 1 do
        idx = idx + dir
        if idx > #BLESS then idx = 0 elseif idx < 0 then idx = #BLESS end
        if idx == 0 then return nil end
        local b = BLESS[idx]
        if not anyKnown or known[b.key] then return b.key end
    end
end

local function AutoAssign()
    local pals = {}
    for _, n in ipairs(SortedPaladins()) do if HasNZR(n) then pals[#pals + 1] = n end end
    for _, n in ipairs(pals) do DB().blessAssign[n] = {} end
    for _, cls in ipairs(GroupClasses()) do
        local used = {}
        -- ce que les paladins sans NZR posent déjà : pris
        for n in pairs(paladins) do
            if not HasNZR(n) and seen[n] and seen[n][cls] then used[seen[n][cls]] = true end
        end
        local free = {}
        for _, n in ipairs(pals) do free[#free + 1] = n end
        for _, key in ipairs(PRIO[cls] or PRIO_DEFAULT) do
            if #free == 0 then break end
            for i, n in ipairs(free) do
                local k = paladins[n].known
                if (next(k) == nil or k[key]) and not used[key] then
                    SetAssign(n, cls, key)
                    used[key] = true
                    table.remove(free, i)
                    break
                end
            end
        end
    end
    for _, n in ipairs(pals) do
        for cls, key in pairs(DB().blessAssign[n] or {}) do SendAssign(n, cls, key) end
    end
end

-- une nouvelle classe arrive dans le groupe : si aucun paladin ne la couvre, je prends
-- la meilleure bénédiction encore libre pour elle (sans toucher aux choix déjà faits)
local function FillMissing()
    local me = MyName()
    if not paladins[me] then return end
    for _, cls in ipairs(GroupClasses()) do
        local covered, used = false, {}
        for n in pairs(paladins) do
            local k = Assign(n, cls)
            if k then used[k] = true; if n == me then covered = true end end
        end
        local anyone = next(used) ~= nil
        if not covered and not anyone then
            local known = paladins[me].known or {}
            for _, key in ipairs(PRIO[cls] or PRIO_DEFAULT) do
                if (next(known) == nil or known[key]) and not used[key] then
                    SetAssign(me, cls, key); SendAssign(me, cls, key)
                    break
                end
            end
        end
    end
end

local function BuildGrid()
    if not win then return end
    for _, w in ipairs(win.cells or {}) do w:Hide() end
    for _, w in ipairs(win.labels or {}) do w:Hide() end
    win.cells, win.labels = win.cells or {}, win.labels or {}
    local ci, li = 0, 0
    local function Label(font)
        li = li + 1
        local fs = win.labels[li] or win.grid:CreateFontString(nil, "OVERLAY", font)
        fs:SetFontObject(font); fs:Show()
        win.labels[li] = fs
        return fs
    end
    local function Cell()
        ci = ci + 1
        local c = win.cells[ci]
        if not c then
            c = CreateFrame("Button", nil, win.grid)
            c:SetSize(CELL, CELL)
            c:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            c.bg = c:CreateTexture(nil, "BACKGROUND"); c.bg:SetAllPoints(); c.bg:SetColorTexture(0, 0, 0, 0.55)
            c.icon = c:CreateTexture(nil, "ARTWORK"); c.icon:SetPoint("TOPLEFT", 2, -2); c.icon:SetPoint("BOTTOMRIGHT", -2, 2)
            c.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            local hl = c:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 0.82, 0, 0.25)
            c.plus = c:CreateFontString(nil, "OVERLAY", "GameFontDisableLarge")
            c.plus:SetPoint("CENTER", 0, 1); c.plus:SetText("+")
            local edge = c:CreateTexture(nil, "BORDER")
            edge:SetPoint("TOPLEFT", -1, 1); edge:SetPoint("BOTTOMRIGHT", 1, -1); edge:SetColorTexture(0.55, 0.45, 0.25, 0.6)
            c.edge = edge
            win.cells[ci] = c
        end
        c:Show()
        return c
    end
    local classes = GroupClasses()
    local pals = SortedPaladins()
    local x0, y0 = 150, -6
    -- en-têtes de classe
    for i, cls in ipairs(classes) do
        local h = Cell()
        h:ClearAllPoints(); h:SetPoint("TOPLEFT", x0 + (i - 1) * (CELL + 6), y0)
        h:SetScript("OnClick", nil)
        h.icon:SetTexCoord(0, 1, 0, 1)
        SetClassIcon(h.icon, cls)
        h.icon:SetAlpha(1); h.icon:Show()
        h.plus:Hide(); h.edge:Hide()
        h.bg:SetColorTexture(0, 0, 0, 0)
        h:SetScript("OnEnter", function(s)
            GameTooltip:SetOwner(s, "ANCHOR_TOP")
            GameTooltip:AddLine(ClassName(cls), ClassColor(cls))
            GameTooltip:AddLine(("%d dans le groupe"):format(#(roster[cls] or {})), 1, 1, 1)
            GameTooltip:Show()
        end)
        h:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    -- une ligne par paladin
    for r, pal in ipairs(pals) do
        local y = y0 - (CELL + 10) - (r - 1) * (CELL + 8)
        local nm = Label("GameFontNormal")
        nm:ClearAllPoints(); nm:SetPoint("TOPLEFT", win.grid, "TOPLEFT", 6, y - 2)
        local pr, pg, pb = ClassColor("PALADIN")
        nm:SetText(pal .. (paladins[pal].me and " |cffaaaaaa(toi)|r" or ""))
        nm:SetTextColor(pr, pg, pb)
        local kn = Label("GameFontDisableSmall")
        kn:ClearAllPoints(); kn:SetPoint("TOPLEFT", nm, "BOTTOMLEFT", 0, -3)
        local list = {}
        for _, b in ipairs(BLESS) do if paladins[pal].known[b.key] then list[#list + 1] = b.short end end
        if not HasNZR(pal) then
            kn:SetText("|cffff9933Sans NZR Forever|r · vu en jeu")
        elseif paladins[pal].pp then
            kn:SetText("|cff66ccffPallyPower|r · " .. (#list > 0 and table.concat(list, ", ") or ""))
        else
            kn:SetText(#list > 0 and table.concat(list, ", ") or (paladins[pal].me and "Aucune connue" or "Aucune connue"))
        end
        kn:SetWidth(140); kn:SetJustifyH("LEFT")
        for i, cls in ipairs(classes) do
            local c = Cell()
            c:ClearAllPoints(); c:SetPoint("TOPLEFT", x0 + (i - 1) * (CELL + 6), y)
            c.bg:SetColorTexture(0, 0, 0, 0.55)
            local key = Assign(pal, cls)
            c.edge:Show()
            c.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            if key then c.icon:SetTexture(BY_KEY[key].icon); c.icon:Show(); c.plus:Hide()
            else c.icon:Hide(); c.plus:Show() end
            c.icon:SetDesaturated(false)
            if not HasNZR(pal) then
                -- pas de NZR chez lui : on montre ce qu'il lance, sans pouvoir le changer ;
                -- rien vu sur cette classe = case vide (pas de « + », on ne peut rien y choisir)
                if key then c.icon:SetAlpha(1) else c.plus:Hide(); c.bg:SetColorTexture(0, 0, 0, 0.25); c.edge:Hide() end
                c:SetScript("OnClick", nil)
                c:SetScript("OnEnter", function(s)
                    GameTooltip:SetOwner(s, "ANCHOR_TOP")
                    GameTooltip:AddLine(pal .. "  -  " .. ClassName(cls), 1, 0.82, 0)
                    GameTooltip:AddLine(key and BY_KEY[key].name or "Rien vu pour l'instant", 1, 1, 1)
                    GameTooltip:AddLine("Il n'a pas NZR Forever : on montre ce qu'il lance vraiment (vu hors combat). Ta répartition s'adapte pour ne pas l'écraser.", 0.7, 0.7, 0.7, true)
                    GameTooltip:Show()
                end)
                c:SetScript("OnLeave", function() GameTooltip:Hide() end)
            else
            c.icon:SetAlpha(1)
            c:SetScript("OnClick", function(_, btn)
                local newKey
                if IsShiftKeyDown() then newKey = nil
                else newKey = CycleKnown(pal, cls, btn == "RightButton" and -1 or 1) end
                SetAssign(pal, cls, newKey)
                SendAssign(pal, cls, newKey)
                refreshAll()
            end)
            c:SetScript("OnEnter", function(s)
                GameTooltip:SetOwner(s, "ANCHOR_TOP")
                local k = Assign(pal, cls)
                GameTooltip:AddLine(pal ..  "  -  " .. ClassName(cls), 1, 0.82, 0)
                GameTooltip:AddLine(k and BY_KEY[k].name or "Aucune bénédiction", 1, 1, 1)
                GameTooltip:AddLine("Clic : suivante   Clic droit : précédente   Maj+clic : effacer", 0.7, 0.7, 0.7, true)
                GameTooltip:Show()
            end)
            c:SetScript("OnLeave", function() GameTooltip:Hide() end)
            end
        end
    end
    local w = math.max(520, x0 + #classes * (CELL + 6) + 24)
    local h = 182 + (CELL + 10) + #pals * (CELL + 8)
    win:SetSize(w, h)
end

local function CreateWindow()
    local ok
    ok, win = pcall(CreateFrame, "Frame", "NZRF_BlessWindow", UIParent, "ButtonFrameTemplate")
    if not ok or not win then win = CreateFrame("Frame", "NZRF_BlessWindow", UIParent); GameFrame(win, 0.95) end
    win:SetPoint("CENTER")
    win:SetFrameStrata("HIGH")
    win:SetToplevel(true)
    win:SetMovable(true)
    win:EnableMouse(true)
    win:SetClampedToScreen(true)
    tinsert(UISpecialFrames, "NZRF_BlessWindow")
    if ButtonFrameTemplate_HidePortrait then pcall(ButtonFrameTemplate_HidePortrait, win) end
    if ButtonFrameTemplate_HideButtonBar then pcall(ButtonFrameTemplate_HideButtonBar, win) end
    if not (win.SetTitle and pcall(win.SetTitle, win, "Bénédictions du groupe")) then
        local tt = win.TitleText or (win.TitleContainer and win.TitleContainer.TitleText)
        if tt then tt:SetText("Bénédictions du groupe") end
    end
    local drag = CreateFrame("Frame", nil, win)
    drag:SetPoint("TOPLEFT"); drag:SetPoint("TOPRIGHT", -28, 0); drag:SetHeight(22)
    drag:EnableMouse(true); drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function() win:StartMoving() end)
    drag:SetScript("OnDragStop", function() win:StopMovingOrSizing() end)

    local hint = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", 24, -34); hint:SetPoint("RIGHT", -24, 0); hint:SetJustifyH("CENTER")
    hint:SetSpacing(2)
    hint:SetText("Une ligne par paladin, une colonne par classe. Clique une case pour choisir la bénédiction.\n"
        .. "|cffaaaaaaNZR Forever et PallyPower partagent la répartition. Sans addon : on montre ce qu'il lance.|r")
    win.hint = hint
    -- la grille commence sous le texte, quelle que soit sa hauteur
    win.grid:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", -14, -14); win.grid:SetPoint("BOTTOMRIGHT", -10, 70)

    local function Btn(text, onClick, anchor, x)
        local b = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
        b:SetSize(140, 22); b:SetText(text)
        b:SetScript("OnClick", onClick)
        return b
    end
    local auto = Btn("Répartition auto", function() AutoAssign(); refreshAll() end)
    auto:SetPoint("BOTTOMLEFT", 12, 12)
    local clear = Btn("Tout effacer", function()
        for n in pairs(paladins) do
            for cls in pairs(DB().blessAssign[n] or {}) do SendAssign(n, cls, nil) end
            DB().blessAssign[n] = {}
        end
        refreshAll()
    end)
    clear:SetPoint("LEFT", auto, "RIGHT", 6, 0)
    local all = CreateFrame("CheckButton", nil, win, "UICheckButtonTemplate")
    all:SetSize(24, 24)
    all:SetPoint("BOTTOMLEFT", auto, "TOPLEFT", -2, 6)
    local allT = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    allT:SetPoint("LEFT", all, "RIGHT", 2, 0); allT:SetText("Toutes les classes")
    all:SetScript("OnShow", function(s) s:SetChecked(DB().blessAllClasses and true or false) end)
    all:SetScript("OnClick", function(s) DB().blessAllClasses = s:GetChecked() and true or false; BuildGrid() end)
    all:SetScript("OnEnter", function(s)
        GameTooltip:SetOwner(s, "ANCHOR_TOP")
        GameTooltip:AddLine("Toutes les classes")
        GameTooltip:AddLine("Coché : prépare la répartition pour toutes les classes. Décoché : seulement celles de ton groupe (seul : la tienne).", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    all:SetScript("OnLeave", function() GameTooltip:Hide() end)
    local close = Btn("Fermer", function() win:Hide() end)
    close:SetPoint("BOTTOMRIGHT", -12, 12)
    win:SetScript("OnShow", function() ScanRoster(); Send("Q"); SendPP("REQ"); BuildGrid() end)
    win:Hide()
end

function NZR.BlessOpen()
    if not DB().paladin then
        NZR:Print("active d'abord l'assistant de bénédictions (Réglages > Paladin).")
        return
    end
    if not win then CreateWindow() end
    win:SetShown(not win:IsShown())
end

---------------------------------------------------------------------------
-- Démarrage
---------------------------------------------------------------------------
refreshAll = function()
    if win and win:IsShown() then BuildGrid() end
    if bar then
        if InCombatLockdown() then pending = true; return end
        bar:SetShown(ShouldShowBar())
        LayoutBar()
        pcall(UpdateButtons)
    end
end

function M:Init()
    local d = DB()
    d.blessAssign = d.blessAssign or {}
    if d.blessGreater == nil then d.blessGreater = true end
    if d.blessSolo == nil then d.blessSolo = true end
    if not d.paladin then return end
    local _, cls = UnitClass("player")
    if cls ~= "PALADIN" then return end

    LoadNames()
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
        pcall(C_ChatInfo.RegisterAddonMessagePrefix, PP_PREFIX)
    end
    CreateBar()
    ScanRoster()

    local ev = CreateFrame("Frame")
    ev:RegisterEvent("GROUP_ROSTER_UPDATE")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:RegisterEvent("CHAT_MSG_ADDON")
    ev:RegisterEvent("PLAYER_REGEN_ENABLED")
    ev:RegisterEvent("SPELLS_CHANGED")
    ev:RegisterEvent("UNIT_AURA")
    local helloAt = 0
    ev:SetScript("OnEvent", function(_, e, a1, a2, a3, a4)
        if e == "CHAT_MSG_ADDON" then
            if a1 == PREFIX and a2 then pcall(OnMessage, a2, a4)
            elseif a1 == PP_PREFIX and a2 then pcall(OnPPMessage, a2, a4) end
            return
        end
        if e == "UNIT_AURA" then
            -- regarder ce que lancent les paladins sans NZR (au plus toutes les 2 s, hors combat)
            if GetTime() - (M.obsAt or 0) > 2 and not InCombatLockdown() then
                M.obsAt = GetTime()
                local ok, changed = pcall(Observe)
                if ok and changed then pcall(Adapt); refreshAll() end
            end
            return
        end
        if e == "PLAYER_REGEN_ENABLED" then
            if pending then pending = false; refreshAll() end
            return
        end
        if e == "SPELLS_CHANGED" then LoadNames() end
        ScanRoster()
        if e == "GROUP_ROSTER_UPDATE" or e == "PLAYER_ENTERING_WORLD" then pcall(FillMissing) end
        refreshAll()
        if GetTime() - helloAt > 3 then
            helloAt = GetTime()
            C_Timer.After(1, SendHello)
            -- qui a NZR Forever ? les autres répondent par leur « bonjour »
            if e == "GROUP_ROSTER_UPDATE" or e == "PLAYER_ENTERING_WORLD" then
                C_Timer.After(1.5, function() Send("Q"); SendPP("REQ"); SendPPSelf() end)
            end
        end
        if e == "PLAYER_REGEN_ENABLED" or e == "GROUP_ROSTER_UPDATE" then
            local ok, changed = pcall(Observe)
            if ok and changed then pcall(Adapt) end
        end
    end)
    refreshAll()
end
