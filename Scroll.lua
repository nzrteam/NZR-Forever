-- NZR Forever - Texte de combat défilant (facultatif, désactivé par défaut)
-- Tes coups qui montent à droite (avec l'icône du sort), les dégâts reçus qui descendent
-- à gauche, les soins en vert, « +Combat / -Combat » au centre. Les combats de Forever
-- sont fermés aux addons : on lit ce que le jeu annonce (UNIT_COMBAT) et on rattache tes
-- coups à ton dernier sort lancé.
local _, NZR = ...
local M = NZR:Module("Scroll")
local plain = NZR.plain

local function DB() return NZR.db end

local SWING_ICON = "Interface\\Icons\\INV_Sword_04"
local pool, active = {}, {}
local driver
local lastCast = { t = 0 }

---------------------------------------------------------------------------
-- Une ligne de texte
---------------------------------------------------------------------------
local function Font(fs, size)
    local path = NZR.FontPath(DB().sctFont or "game", STANDARD_TEXT_FONT)
    if not pcall(fs.SetFont, fs, path, size, "THICKOUTLINE") then pcall(fs.SetFont, fs, STANDARD_TEXT_FONT, size, "THICKOUTLINE") end
    fs:SetShadowColor(0, 0, 0, 1); fs:SetShadowOffset(2, -2)
end

local function Get()
    local f = table.remove(pool)
    if not f then
        f = CreateFrame("Frame", nil, UIParent)
        f:SetFrameStrata("HIGH")
        f:SetSize(1, 1)
        f.icon = f:CreateTexture(nil, "OVERLAY")
        f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        f.edge = f:CreateTexture(nil, "ARTWORK")
        f.edge:SetPoint("TOPLEFT", f.icon, -1, 1); f.edge:SetPoint("BOTTOMRIGHT", f.icon, 1, -1)
        f.edge:SetColorTexture(0, 0, 0, 0.9)
        f.text = f:CreateFontString(nil, "OVERLAY")
        f.text:SetPoint("LEFT", f.icon, "RIGHT", 4, 0)
    end
    return f
end

-- zones : x, y de départ (par rapport au centre de l'écran), sens et longueur du trajet
local AREAS = {
    out = { x = 70, y = 70, dy = 130, dx = 40, dur = 1.5 },     -- au-dessus à droite du perso, monte en s'écartant
    inc = { x = -150, y = 40, dy = -110, dx = -20, dur = 1.5 },  -- à gauche, descend
    note = { x = -60, y = 220, dy = 90, dx = 0, dur = 2.2 },     -- au centre, en haut : un message à la fois, ils montent l'un après l'autre
}
local lastSpawn = { out = 0, inc = 0, note = 0 }
local stagger = { out = 0, inc = 0, note = 0 }

local anchors = {}
local Spawn
local noteNext = 0
local function SpawnNow(area, value, r, g, b, icon, crit)
    local a = AREAS[area]
    -- point de départ = bloc placé en mode édition (sinon la place par défaut)
    local hd = anchors[area]
    if hd and hd:GetCenter() then
        local hx, hy = hd:GetCenter(); local cx, cy = UIParent:GetCenter()
        a.x, a.y = hx - cx - (area == "note" and 0 or 0), hy - cy
    end
    local f = Get()
    local scale = DB().sctSize or 1
    local size = math.floor(((area == "note") and 26 or (crit and 30 or 22)) * scale + 0.5)
    Font(f.text, size)
    if not pcall(f.text.SetText, f.text, value) then f.text:SetText("") end
    f.text:SetTextColor(r, g, b)
    if icon then
        f.icon:SetTexture(icon); f.icon:SetSize(size, size); f.icon:Show(); f.edge:Show()
    else
        f.icon:SetSize(1, size); f.icon:Hide(); f.edge:Hide()
    end
    f.icon:ClearAllPoints(); f.icon:SetPoint("LEFT", f, "LEFT", 0, 0)
    -- plusieurs coups d'affilée : on décale un peu pour ne pas les empiler
    local now = GetTime()
    if now - lastSpawn[area] < 0.25 then stagger[area] = (stagger[area] + 1) % 4 else stagger[area] = 0 end
    lastSpawn[area] = now
    f.area, f.t, f.crit = a, 0, crit
    f.x0 = a.x + (area == "note" and 0 or stagger[area] * (area == "out" and 26 or -26))
    if area == "note" then stagger.note = 0 end
    f.y0 = a.y - stagger[area] * 18 * (a.dy > 0 and 1 or -1)
    f:ClearAllPoints(); f:SetPoint("LEFT", UIParent, "CENTER", f.x0, f.y0)
    f:SetAlpha(0); f:SetScale(crit and 1.6 or 1); f:Show()
    table.insert(active, f)
    driver:Show()
end

-- messages du centre : espacés d'une demi-seconde pour ne jamais se chevaucher
Spawn = function(area, value, r, g, b, icon, crit)
    if area ~= "note" then return SpawnNow(area, value, r, g, b, icon, crit) end
    local now = GetTime()
    local at = math.max(now, noteNext)
    if at - now > 3 then return end                 -- trop en retard : on laisse tomber
    noteNext = at + 0.5
    if at <= now then return SpawnNow(area, value, r, g, b, icon, crit) end
    C_Timer.After(at - now, function() SpawnNow(area, value, r, g, b, icon, crit) end)
end

local function Animate(_, e)
    for i = #active, 1, -1 do
        local f = active[i]
        f.t = f.t + e
        local a = f.area
        local p = f.t / a.dur
        if p >= 1 then
            f:Hide(); table.remove(active, i); table.insert(pool, f)
        else
            -- coup critique : petit « pop » qui se résorbe
            if f.crit then f:SetScale(1 + math.max(0, 0.6 - f.t * 3)) end
            -- départ rapide puis ralenti (plus agréable à lire)
            local ease = 1 - (1 - p) * (1 - p)
            f:ClearAllPoints()
            f:SetPoint("LEFT", UIParent, "CENTER", f.x0 + (a.dx or 0) * ease, f.y0 + a.dy * ease)
            f:SetAlpha(f.t < 0.08 and f.t / 0.08 or (p < 0.75 and 1 or (1 - (p - 0.75) / 0.25)))
        end
    end
    if #active == 0 then driver:Hide() end
end

---------------------------------------------------------------------------
-- Ce que le jeu annonce
---------------------------------------------------------------------------
local MISS = { DODGE = "Esquive", PARRY = "Parade", MISS = "Raté", BLOCK = "Bloqué", RESIST = "Résisté",
               ABSORB = "Absorbé", IMMUNE = "Insensible", EVADE = "Évite", DEFLECT = "Dévié", REFLECT = "Renvoyé" }

local function Amount(v)
    if v == nil then return "" end
    if plain(v) then return NZR.Abbrev(v) end
    local ok, s = pcall(string.format, "%d", v)
    return ok and s or ""
end

local lastHit = { t = 0 }

---------------------------------------------------------------------------
-- Gains de ressource (toutes les classes) : rage, énergie, mana, puissance runique…
-- La régénération normale n'est pas affichée : seulement les vrais gains.
---------------------------------------------------------------------------
local lastPower = {}
local function OnPower(token)
    if DB().sctPower == false then return end
    local ptype, tok = UnitPowerType("player")
    local cur, max = UnitPower("player", ptype), UnitPowerMax("player", ptype)
    if not (plain(cur) and plain(max) and plain(tok)) or max <= 0 then lastPower = {}; return end
    local prev = lastPower[tok]
    lastPower[tok] = cur
    if not prev or cur <= prev then return end
    local gain = cur - prev
    -- mana et énergie se régénèrent toutes seules : on ne montre que les gros gains
    if tok == "MANA" and gain < max * 0.04 then return end
    if tok == "ENERGY" and gain < 25 then return end
    if tok == "FOCUS" and gain < 15 then return end
    local c = PowerBarColor and PowerBarColor[tok]
    local name = _G[tok] or tok
    Spawn("inc", ("+%d %s"):format(gain, name), c and c.r or 0.4, c and c.g or 0.6, c and c.b or 1)
end

-- icône d'un coup : le jeu ne dit pas quel sort a frappé.
-- Sort lancé à l'instant -> son icône ; dégâts physiques -> ton arme ;
-- dégâts magiques (sceau, consécration, aura…) -> ton dernier sort, sinon une icône de l'école.
local SCHOOL_ICON = {
    [2] = "Interface\\Icons\\Spell_Holy_HolyBolt", [4] = "Interface\\Icons\\Spell_Fire_FlameBolt",
    [8] = "Interface\\Icons\\Spell_Nature_Lightning", [16] = "Interface\\Icons\\Spell_Frost_FrostBolt02",
    [32] = "Interface\\Icons\\Spell_Shadow_ShadowBolt", [64] = "Interface\\Icons\\Spell_Arcane_Blast",
}
local function WeaponIcon()
    local ok, tex = pcall(GetInventoryItemTexture, "player", 16)
    if ok and plain(tex) and tex then return tex end
    return SWING_ICON
end
local function HitIcon(school)
    local since = GetTime() - lastCast.t
    if lastCast.icon and since < 0.8 then return lastCast.icon end
    local sc = plain(school) and type(school) == "number" and school or 1
    if sc == 1 then return WeaponIcon() end
    if lastCast.icon and since < 9 then return lastCast.icon end
    return SCHOOL_ICON[sc] or SCHOOL_ICON[2]
end

local function OnUnitCombat(unit, action, flag, amount, school)
    if not plain(action) then return end
    local crit = plain(flag) and (flag == "CRITICAL" or flag == "CRUSHING")
    if unit == "player" then
        if action == "HEAL" then
            if DB().sctHeal ~= false then Spawn("inc", "+" .. Amount(amount), 0.3, 1, 0.3, nil, crit) end
        elseif action == "WOUND" then
            if DB().sctIn ~= false then
                local ok, s = pcall(string.format, "-%s", Amount(amount))
                Spawn("inc", ok and s or "", 1, 0.2, 0.2, nil, crit)
            end
        elseif MISS[action] and DB().sctIn ~= false then
            Spawn("inc", MISS[action], 0.6, 0.8, 1)
        end
        return
    end
    -- tes coups sur ta cible (en groupe, le jeu ne dit pas qui frappe : réglage « dégâts des autres »)
    if DB().sctOut == false then return end
    if not IsInGroup() or DB().sctOthers then
        if action == "WOUND" then
            lastHit.t = GetTime()
            local icon = HitIcon(school)
            local txt = Amount(amount)
            if plain(flag) and flag == "GLANCING" then txt = txt .. " (érafle)" end
            Spawn("out", txt, 1, crit and 0.85 or 1, crit and 0.1 or 1, icon, crit)
        elseif MISS[action] then
            Spawn("out", MISS[action], 0.8, 0.8, 0.8, WeaponIcon())
        end
    end
end

---------------------------------------------------------------------------
-- Cacher les chiffres du jeu (remis comme avant quand on coupe, et à la déconnexion)
---------------------------------------------------------------------------
local CVARS = { "floatingCombatTextCombatDamage", "floatingCombatTextCombatDamage_v2",
                "floatingCombatTextCombatHealing", "floatingCombatTextCombatHealing_v2", "enableFloatingCombatText" }
local function HideBlizzard(hide)
    if not (GetCVar and SetCVar) then return end
    DB().sctSaved = DB().sctSaved or {}
    for _, c in ipairs(CVARS) do
        if hide then
            local okG, cur = pcall(GetCVar, c)
            if not okG or cur == nil then cur = false end
            if cur and DB().sctSaved[c] == nil then DB().sctSaved[c] = cur end
            pcall(SetCVar, c, "0")
        elseif DB().sctSaved[c] ~= nil then
            pcall(SetCVar, c, DB().sctSaved[c]); DB().sctSaved[c] = nil
        end
    end
end

-- texte d'expérience du jeu (« PX : 49 » violet) : pas de réglage à lui ; seule astuce,
-- agrandir le texte flottant du jeu au point qu'il ne s'affiche plus (remis à la déconnexion)
local XPCVARS = { "WorldTextScale_v2", "WorldTextScale" }
local function HideBlizzardXP(hide)
    if not (GetCVar and SetCVar) then return end
    DB().sctSaved = DB().sctSaved or {}
    for _, c in ipairs(XPCVARS) do
        local okG, cur = pcall(GetCVar, c)
        if okG and cur ~= nil then
            if hide then
                if DB().sctSaved[c] == nil and cur ~= "1000" then DB().sctSaved[c] = cur end
                pcall(SetCVar, c, "1000")
            elseif DB().sctSaved[c] ~= nil then
                pcall(SetCVar, c, DB().sctSaved[c]); DB().sctSaved[c] = nil
            elseif cur == "1000" then
                pcall(SetCVar, c, "1")
            end
        end
    end
end

-- gains d'expérience : la barre du jeu, et sinon le message du chat de combat
local xpLast, xpMax, xpLevel, xpShown, killShown = nil, nil, nil, 0, 0
local function ShowXP(gain)
    if gain and gain > 0 and DB().sctXP ~= false and GetTime() - xpShown > 0.8 then
        xpShown = GetTime()
        Spawn("note", "+" .. gain .. " XP", 0.78, 0.5, 1)
    end
end
local function OnXPMessage(msg)
    if type(msg) ~= "string" or not plain(msg) then return end
    local name = msg:match("^(.-) meurt") or msg:match("^(.-) dies")
    local num = name and msg:sub(#name + 1):match("(%d+)") or msg:match("(%d+)")
    if name and DB().sctKill ~= false and GetTime() - killShown > 1.5 then
        killShown = GetTime()
        Spawn("note", name .. " tué", 1, 0.82, 0, "Interface\\TargetingFrame\\UI-TargetingFrame-Skull")
    end
    ShowXP(tonumber(num))
end

-- effets que TU poses sur ta cible (étourdissement, ralentissement…) : « [Marteau de la justice] »
local function OnTargetAura(info)
    if DB().sctAuras == false or not info or info.isFullUpdate or not info.addedAuras then return end
    local shown
    for _, a in ipairs(info.addedAuras) do
        local ok, name, src, harm, dur = pcall(function() return a.name, a.sourceUnit, a.isHarmful, a.duration end)
        if ok and plain(name) and plain(src) and plain(harm) and type(name) == "string" and harm
           and (src == "player" or src == "pet") then
            local d = plain(dur) and type(dur) == "number" and dur or 0
            if d > 0 and d <= 30 then
                Spawn("out", "[" .. name .. "]", 1, 0.6, 0.2, (plain(a.icon) and a.icon) or nil)
                shown = true; lastCast.shown = true
            end
        end
    end
    -- en combat le jeu peut cacher le nom de l'effet : on affiche alors le sort que tu viens
    -- de lancer, si ta cible reçoit un effet dans la demi-seconde qui suit
    if not shown and not lastCast.shown and lastCast.name and GetTime() - lastCast.t < 0.5 and #info.addedAuras > 0 then
        lastCast.shown = true
        Spawn("out", "[" .. lastCast.name .. "]", 1, 0.6, 0.2, lastCast.icon)
    end
end

-- buffs / procs / debuffs gagnés : [Maîtrise du blocage]
local function OnAura(info)
    if DB().sctAuras == false or not info or info.isFullUpdate or not info.addedAuras then return end
    for _, a in ipairs(info.addedAuras) do
        local okN, name = pcall(function() return a.name end)
        if okN and plain(name) and type(name) == "string" and name ~= "" then
            local help = plain(a.isHelpful) and a.isHelpful
            local harm = plain(a.isHarmful) and a.isHarmful
            local dur = plain(a.duration) and a.duration or 0
            if harm then
                Spawn("note", "[" .. name .. "]", 1, 0.3, 0.3)
            elseif help and dur > 0 and dur <= 120 then        -- procs et buffs courts (pas les bénédictions d'1 h)
                Spawn("note", "[" .. name .. "]", 1, 0.82, 0.3)
            end
        end
    end
end
local function OnXP()
    local okX, xp = pcall(UnitXP, "player"); local okM, mx = pcall(UnitXPMax, "player"); local okL, lvl = pcall(UnitLevel, "player")
    if not (okX and okM and okL and plain(xp) and plain(mx) and plain(lvl)) then return end
    if xpLast then
        local gain = (lvl > xpLevel) and ((xpMax - xpLast) + xp) or (xp - xpLast)
        ShowXP(gain)
    end
    xpLast, xpMax, xpLevel = xp, mx, lvl
end

function NZR.ScrollTest()
    if not driver then return end
    local icons = { "Interface\\Icons\\Spell_Holy_SealOfMight", SWING_ICON, "Interface\\Icons\\Spell_Holy_HolyBolt" }
    Spawn("note", "+Combat", 1, 0.3, 0.3)
    for i = 1, 6 do
        C_Timer.After(0.25 * i, function()
            local crit = i == 4
            Spawn("out", tostring(80 + i * 13 + (crit and 200 or 0)), crit and 1 or 1, crit and 0.82 or 1, crit and 0 or 1, icons[(i % 3) + 1], crit)
            if i % 2 == 0 then Spawn("inc", "-" .. (20 + i * 3), 1, 0.25, 0.2) end
        end)
    end
    C_Timer.After(1.8, function() Spawn("inc", "+150", 0.3, 1, 0.3); Spawn("note", "-Combat", 0.3, 1, 0.3) end)
end

local targetDead

function M:Init()
    if NZR.withUI then return end
    driver = CreateFrame("Frame")
    driver:SetScript("OnUpdate", Animate)
    driver:Hide()
    if not DB().sct then
        HideBlizzard(false)             -- au cas où : on rend les réglages du jeu
        HideBlizzardXP(false)
        return
    end
    if DB().sctHideBlizz ~= false then HideBlizzard(true) end
    HideBlizzardXP(DB().sctHideXP ~= false)
    -- messages rouges du jeu (« Le sort n'est pas encore utilisable. ») : même police
    if DB().sctErrors ~= false and UIErrorsFrame and UIErrorsFrame.SetFont then
        local path = NZR.FontPath(DB().sctFont or "game", STANDARD_TEXT_FONT)
        local size = math.floor(17 * (DB().sctSize or 1) + 0.5)
        if not pcall(UIErrorsFrame.SetFont, UIErrorsFrame, path, size, "OUTLINE") then
            pcall(UIErrorsFrame.SetFont, UIErrorsFrame, STANDARD_TEXT_FONT, size, "OUTLINE")
        end
        pcall(UIErrorsFrame.SetShadowColor, UIErrorsFrame, 0, 0, 0, 1)
        pcall(UIErrorsFrame.SetShadowOffset, UIErrorsFrame, 1, -1)
    end
    anchors.out = NZR:Holder("sctOut", "Texte : tes coups", 150, 34, { "CENTER", "CENTER", 140, 90 })
    anchors.inc = NZR:Holder("sctIn", "Texte : reçu", 150, 34, { "CENTER", "CENTER", -110, 60 })
    anchors.note = NZR:Holder("sctNote", "Texte : combat", 150, 34, { "CENTER", "CENTER", 0, 230 })

    local ev = CreateFrame("Frame")
    ev:RegisterEvent("UNIT_COMBAT")
    pcall(ev.RegisterUnitEvent, ev, "UNIT_POWER_UPDATE", "player")
    pcall(ev.RegisterUnitEvent, ev, "UNIT_HEALTH", "target")
    ev:RegisterEvent("PLAYER_TARGET_CHANGED")
    ev:RegisterEvent("PLAYER_REGEN_DISABLED")
    ev:RegisterEvent("PLAYER_REGEN_ENABLED")
    ev:RegisterEvent("PLAYER_LOGOUT")
    ev:RegisterEvent("PLAYER_XP_UPDATE")
    ev:RegisterEvent("CHAT_MSG_COMBAT_XP_GAIN")
    pcall(ev.RegisterUnitEvent, ev, "UNIT_AURA", "player", "target")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    pcall(ev.RegisterUnitEvent, ev, "UNIT_SPELLCAST_SUCCEEDED", "player")
    ev:SetScript("OnEvent", function(_, e, unit, a, b, c, d)
        if e == "UNIT_COMBAT" then
            if unit == "player" then pcall(OnUnitCombat, "player", a, b, c, d)
            elseif unit == "target" then pcall(OnUnitCombat, "target", a, b, c, d) end
        elseif e == "UNIT_POWER_UPDATE" then
            pcall(OnPower, a)
        elseif e == "PLAYER_TARGET_CHANGED" then
            local ok, dead = pcall(UnitIsDead, "target")
            targetDead = ok and plain(dead) and dead or nil      -- déjà mort : pas de « coup fatal »
        elseif e == "UNIT_HEALTH" then
            -- coup fatal : ta cible meurt juste après ton coup (sûr seulement en solo)
            local ok, dead = pcall(UnitIsDead, "target")
            if ok and plain(dead) and dead and not targetDead then
                targetDead = true
                if DB().sctKill ~= false and GetTime() - lastHit.t < 1.5 and (not IsInGroup() or DB().sctOthers) then
                    local okN, n = pcall(UnitName, "target")
                    killShown = GetTime()
                    Spawn("note", "Coup fatal ! " .. ((okN and plain(n) and n) or ""), 1, 0.82, 0, "Interface\\TargetingFrame\\UI-TargetingFrame-Skull")
                end
            end
        elseif e == "UNIT_SPELLCAST_SUCCEEDED" then
            local spellID = c
            local tex = spellID and C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spellID)
            if tex then
                lastCast.t, lastCast.icon, lastCast.shown = GetTime(), tex, nil
                local okN, nm = pcall(C_Spell.GetSpellName, spellID)
                lastCast.name = okN and plain(nm) and nm or nil
            end
        elseif e == "PLAYER_REGEN_DISABLED" then
            if DB().sctNotice ~= false then Spawn("note", "+Combat", 1, 0.3, 0.3) end
        elseif e == "PLAYER_REGEN_ENABLED" then
            if DB().sctNotice ~= false then Spawn("note", "-Combat", 0.3, 1, 0.3) end
        elseif e == "CHAT_MSG_COMBAT_XP_GAIN" then
            pcall(OnXPMessage, unit)
        elseif e == "UNIT_AURA" then
            if unit == "player" then pcall(OnAura, a)
            elseif unit == "target" then pcall(OnTargetAura, a) end
        elseif e == "PLAYER_XP_UPDATE" then
            pcall(OnXP)
        elseif e == "PLAYER_ENTERING_WORLD" then
            xpLast = nil; pcall(OnXP)
        elseif e == "PLAYER_LOGOUT" then
            HideBlizzardXP(false)
            HideBlizzard(false)         -- tes réglages du jeu reviennent même si tu retires NZR
        end
    end)
end
