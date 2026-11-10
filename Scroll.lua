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
    if not pcall(fs.SetFont, fs, path, size, "OUTLINE") then pcall(fs.SetFont, fs, STANDARD_TEXT_FONT, size, "OUTLINE") end
    fs:SetShadowColor(0, 0, 0, 0.8); fs:SetShadowOffset(1, -1)
end

local function Get()
    local f = table.remove(pool)
    if not f then
        f = CreateFrame("Frame", nil, UIParent)
        f:SetFrameStrata("HIGH")
        f:SetSize(1, 1)
        f.icon = f:CreateTexture(nil, "OVERLAY")
        f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        f.text = f:CreateFontString(nil, "OVERLAY")
        f.text:SetPoint("LEFT", f.icon, "RIGHT", 4, 0)
    end
    return f
end

-- zones : x, y de départ (par rapport au centre de l'écran), sens et longueur du trajet
local AREAS = {
    out = { x = 120, y = 30, dy = 150, dur = 1.6 },
    inc = { x = -200, y = 20, dy = -150, dur = 1.6 },
    note = { x = 0, y = 200, dy = 40, dur = 1.6 },
}
local lastSpawn = { out = 0, inc = 0, note = 0 }
local stagger = { out = 0, inc = 0, note = 0 }

local function Spawn(area, value, r, g, b, icon, crit)
    local a = AREAS[area]
    local f = Get()
    local scale = DB().sctSize or 1
    local size = math.floor((crit and 26 or 18) * scale + 0.5)
    Font(f.text, size)
    if not pcall(f.text.SetText, f.text, value) then f.text:SetText("") end
    f.text:SetTextColor(r, g, b)
    if icon then
        f.icon:SetTexture(icon); f.icon:SetSize(size, size); f.icon:Show()
    else
        f.icon:SetSize(1, size); f.icon:Hide()
    end
    f.icon:ClearAllPoints(); f.icon:SetPoint("LEFT", f, "LEFT", 0, 0)
    -- plusieurs coups d'affilée : on décale un peu pour ne pas les empiler
    local now = GetTime()
    if now - lastSpawn[area] < 0.25 then stagger[area] = (stagger[area] + 1) % 4 else stagger[area] = 0 end
    lastSpawn[area] = now
    f.area, f.t, f.crit = a, 0, crit
    f.x0 = a.x + (area == "note" and 0 or stagger[area] * (area == "out" and 18 or -18))
    f.y0 = a.y - stagger[area] * 14 * (a.dy > 0 and 1 or -1)
    f:ClearAllPoints(); f:SetPoint("LEFT", UIParent, "CENTER", f.x0, f.y0)
    f:SetAlpha(1); f:SetScale(crit and 1.5 or 1); f:Show()
    table.insert(active, f)
    driver:Show()
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
            if f.crit then f:SetScale(1 + math.max(0, 0.5 - f.t * 2.5)) end
            f:ClearAllPoints()
            f:SetPoint("LEFT", UIParent, "CENTER", f.x0, f.y0 + a.dy * p)
            f:SetAlpha(p < 0.7 and 1 or (1 - (p - 0.7) / 0.3))
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

local function OnUnitCombat(unit, action, flag, amount, school)
    if not plain(action) then return end
    local crit = plain(flag) and (flag == "CRITICAL" or flag == "CRUSHING")
    if unit == "player" then
        if action == "HEAL" then
            if DB().sctHeal ~= false then Spawn("inc", "+" .. Amount(amount), 0.3, 1, 0.3, nil, crit) end
        elseif action == "WOUND" then
            if DB().sctIn ~= false then
                local ok, s = pcall(string.format, "-%s", Amount(amount))
                Spawn("inc", ok and s or "", 1, 0.25, 0.2, nil, crit)
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
            local icon = (GetTime() - lastCast.t < 0.8 and lastCast.icon) or SWING_ICON
            local txt = Amount(amount)
            if plain(flag) and flag == "GLANCING" then txt = txt .. " (érafle)" end
            Spawn("out", txt, crit and 1 or 1, crit and 0.82 or 1, crit and 0 or 1, icon, crit)
        elseif MISS[action] then
            Spawn("out", MISS[action], 0.8, 0.8, 0.8, SWING_ICON)
        end
    end
end

---------------------------------------------------------------------------
-- Cacher les chiffres du jeu (remis comme avant quand on coupe, et à la déconnexion)
---------------------------------------------------------------------------
local CVARS = { "floatingCombatTextCombatDamage", "enableFloatingCombatText" }
local function HideBlizzard(hide)
    if not (GetCVar and SetCVar) then return end
    DB().sctSaved = DB().sctSaved or {}
    for _, c in ipairs(CVARS) do
        if hide then
            if DB().sctSaved[c] == nil then DB().sctSaved[c] = GetCVar(c) end
            pcall(SetCVar, c, "0")
        elseif DB().sctSaved[c] ~= nil then
            pcall(SetCVar, c, DB().sctSaved[c]); DB().sctSaved[c] = nil
        end
    end
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
        return
    end
    if DB().sctHideBlizz ~= false then HideBlizzard(true) end

    local ev = CreateFrame("Frame")
    ev:RegisterEvent("UNIT_COMBAT")
    pcall(ev.RegisterUnitEvent, ev, "UNIT_POWER_UPDATE", "player")
    pcall(ev.RegisterUnitEvent, ev, "UNIT_HEALTH", "target")
    ev:RegisterEvent("PLAYER_TARGET_CHANGED")
    ev:RegisterEvent("PLAYER_REGEN_DISABLED")
    ev:RegisterEvent("PLAYER_REGEN_ENABLED")
    ev:RegisterEvent("PLAYER_LOGOUT")
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
                    Spawn("note", "Coup fatal ! " .. ((okN and plain(n) and n) or ""), 1, 0.82, 0, "Interface\\TargetingFrame\\UI-TargetingFrame-Skull")
                end
            end
        elseif e == "UNIT_SPELLCAST_SUCCEEDED" then
            local spellID = c
            local tex = spellID and C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spellID)
            if tex then lastCast.t, lastCast.icon = GetTime(), tex end
        elseif e == "PLAYER_REGEN_DISABLED" then
            if DB().sctNotice ~= false then Spawn("note", "+Combat", 1, 0.3, 0.3) end
        elseif e == "PLAYER_REGEN_ENABLED" then
            if DB().sctNotice ~= false then Spawn("note", "-Combat", 0.3, 1, 0.3) end
        elseif e == "PLAYER_LOGOUT" then
            HideBlizzard(false)         -- tes réglages du jeu reviennent même si tu retires NZR
        end
    end)
end
