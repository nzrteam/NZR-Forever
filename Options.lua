-- NZR Forever - Réglages : /nzr, bouton "NZR Forever" du menu Échap, clic droit sur la minimap,
-- Échap > Options > AddOns. Catégories à gauche, une ligne par réglage avec explication.
local _, NZR = ...
local M = NZR:Module("Options")
local C = NZR.C

local W, H = 820, 600
local LIST_W = 170          -- colonne de gauche (catégories), comme les Options du jeu
local win
local snapshot = {}
local reloadKeys = {}

---------------------------------------------------------------------------
-- Contenu des pages
-- t = type (switch, slider, choice, button), key = réglage, r = recharge nécessaire
---------------------------------------------------------------------------
local function accentChoices()
    local list = {}
    for _, a in ipairs(NZR.ACCENTS) do table.insert(list, { a.id, a.name, a.a }) end
    return list
end

local PAGES = {
    { id = "meter", name = "DPS meter", desc = "Le compteur de dégâts. L'essentiel en haut, le reste pour personnaliser. Clic droit sur le meter = cette page.",
      items = {
        { t = "switch", key = "meter", section = "Affichage", label = "Afficher le DPS meter", desc = "Pense à couper celui de Blizzard dans les options du jeu.", r = true },
        { t = "choice", key = "meterView", section = "Affichage", label = "Présentation", desc = "Détaillé : une carte par joueur. Tableau : colonnes. Barres : un classement simple.",
          choices = function() return { { "cards", "Détaillé" }, { "table", "Tableau" }, { "bars", "Barres" } } end, apply = function() if NZR.MeterApplySize then NZR.MeterApplySize() end end },
        { t = "choice", section = "Affichage", key = "meterTheme", label = "Teinte", r = true, desc = "La même que le meter. Jeu : se fond dans WoW. Noir : sobre. Violet : couleurs NZR.",
          choices = function() return { { "jeu", "Jeu" }, { "noir", "Noir" }, { "violet", "Violet" } } end },
        { t = "slider", key = "meterAlpha", section = "Affichage", label = "Opacité du fond", desc = "Plus bas = on voit le jeu à travers.", min = 0.3, max = 1, step = 0.05,
          apply = function() if NZR.MeterRefresh then NZR.MeterRefresh(false) end end },
        { t = "switch", key = "meterLock", section = "Affichage", label = "Verrouiller", desc = "Empêche de le déplacer ou de le redimensionner par erreur.", meter = true },
        { t = "switch", key = "meterAuto", section = "Quand l'afficher", label = "Caché en solo hors combat", desc = "Apparaît en combat ou en groupe, disparaît 20 s après. Le bouton « réduire » du meter le range en petite icône quand tu veux.", meter = true },
        { t = "switch", key = "meterShiftBars", section = "Meter réduit", label = "Réduit : les barres prennent sa place", desc = "Quand tu réduis le meter, tes barres de sorts collées à sa droite vont où tu veux (bouton Déplacer : bloc « Barres quand le meter est réduit »), l'icône DPS au-dessus. Elles reviennent quand tu le rouvres (hors combat).",
          apply = function() if NZR.MeterShiftRefresh then NZR.MeterShiftRefresh() end end },
        { t = "switch", key = "meterShiftBuffs", section = "Meter réduit", label = "… avec les buffs", desc = "Tes buffs et débuffs suivent aussi, s'ils sont collés au meter.",
          apply = function() if NZR.MeterShiftRefresh then NZR.MeterShiftRefresh(true) end end },
        { t = "switch", key = "meterShiftCD", section = "Meter réduit", label = "… avec les temps de recharge", desc = "« Temps de recharge essentiels » et « utilitaires » du jeu suivent aussi.",
          apply = function() if NZR.MeterShiftRefresh then NZR.MeterShiftRefresh(true) end end },
        { t = "button", section = "Meter réduit", label = "Où vont les barres", desc = "Fait apparaître le bloc « Barres quand le meter est réduit » à glisser. Reclique pour finir.",
          text = function() return NZR.unlocked and "Terminer" or "Déplacer" end,
          click = function() NZR:SetUnlocked(not NZR.unlocked) end },
        { t = "multi", key = "meterInfo", section = "Présentation Détaillé", label = "Infos sous le nom", desc = "Clique pour afficher ou masquer.", meter = true,
          choices = function() return { { "dmg", "Total" }, { "heal", "Soins" }, { "hps", "HPS" }, { "taken", "Subis" }, { "abs", "Absorptions" }, { "int", "Interruptions" }, { "disp", "Dissipations" }, { "death", "Morts" } } end },
        { t = "switch", key = "meterTargetBar", section = "Présentation Détaillé", label = "Vie de ta cible en haut", desc = "Nom et vie de ce que tu combats.", meter = true },
        { t = "switch", key = "meterCardFill", section = "Présentation Détaillé", label = "Fond à la couleur de la classe", desc = "Se remplit selon la part de chacun.", meter = true },
        { t = "multi", key = "meterCols", section = "Tableau et Barres", label = "Colonnes", desc = "Ce que montre le tableau. La largeur s'adapte.", meter = true,
          choices = function()
              local list = {}
              for _, c in ipairs(NZR.METER_COLUMNS or {}) do
                  if c.available ~= false then table.insert(list, { c.id, c.long }) end
              end
              return list
          end },
        { t = "choice", key = "meterSort", section = "Tableau et Barres", label = "Trier par", desc = "Aussi en cliquant sur un titre de colonne.", meter = true,
          choices = function() return { { "dps", "DPS" }, { "dmg", "Dégâts" }, { "heal", "Soins" }, { "taken", "Subis" } } end },
        { t = "choice", key = "meterRowSize", section = "Tableau et Barres", label = "Taille des lignes", desc = "Compacte : une ligne fine.", meter = true, resize = false,
          choices = function() return { { "compact", "Compacte" }, { "normal", "Normale" }, { "large", "Grande" } } end },
        { t = "choice", key = "meterBarColor", section = "Tableau et Barres", label = "Couleur des barres", desc = "Couleur de la classe ou couleur d'accent.", meter = true,
          choices = function() return { { "class", "Classe" }, { "accent", "Accent" } } end },
        { t = "multi", key = "meterExtras", flat = true, section = "Tableau et Barres", label = "Petits plus", desc = "Clique pour afficher ou masquer.", meter = true,
          choices = function() return { { "meterShare", "Part (%)" }, { "meterIcons", "Icônes de spé" }, { "meterRank", "Rang" }, { "meterCrown", "Couronne du 1er" }, { "meterFooter", "Totaux du groupe" } } end },
        { t = "button", section = "Outils", label = "Vider le compteur", desc = "Remet tous les combats à zéro.", text = function() return "Vider" end,
          click = function() if NZR.ResetMeterData then NZR.ResetMeterData() end end },
        { t = "button", section = "Outils", label = "Ajuster la largeur", desc = "Recalcule la largeur selon les colonnes.", text = function() return "Ajuster" end,
          click = function() if NZR.MeterRefresh then NZR.MeterRefresh(true) end end },
      } },
    { id = "frames", name = "Cadres", desc = "Tes cadres (joueur, cible, groupe, raid) et les barres au-dessus des monstres, au style du jeu mais plus lisibles. Désactivés de base.",
      items = {
        { t = "switch", key = "unitFrames", section = "Joueur et cible", label = "Cadres joueur et cible NZR", desc = "Remplace les cadres du jeu par des cadres dorés plus lisibles (portrait, niveau, nom, vie, mana).", r = true },
        { t = "choice", key = "ufPortrait", section = "Joueur et cible", label = "Portrait", desc = "Rond comme le jeu, ou carré.", r = true,
          choices = function() return { { "round", "Rond" }, { "square", "Carré" } } end },
        { t = "choice", key = "ufName", section = "Joueur et cible", label = "Nom affiché", desc = "Nom complet (avec le titre, comme dans le jeu) ou seulement le premier mot.",
          choices = function() return { { "full", "Nom complet" }, { "first", "Prénom seul" } } end,
          apply = function() if NZR.FramesRefresh then NZR.FramesRefresh() end end },
        { t = "switch", key = "ufAuras", section = "Joueur et cible", label = "Buffs et débuffs de la cible", desc = "Sous le cadre de ta cible, comme le jeu (débuffs en premier sur un ennemi). Survol = détail.",
          apply = function() if NZR.FramesRefresh then NZR.FramesRefresh() end end },
        { t = "slider", key = "ufScale", section = "Joueur et cible", label = "Taille", desc = "Taille des deux cadres.", min = 0.7, max = 1.5, step = 0.05,
          apply = function() if NZR.FramesScale then NZR.FramesScale() end end },
        { t = "button", section = "Joueur et cible", label = "Déplacer les cadres", desc = "Fait apparaître des blocs à glisser. Reclique pour finir.",
          text = function() return NZR.unlocked and "Terminer" or "Déplacer" end,
          click = function() NZR:SetUnlocked(not NZR.unlocked) end },
        { t = "choice", key = "ufText", section = "Texte des barres", label = "Texte affiché", desc = "Valeurs + % : « 836 / 836  100 % » centré. % : seulement le pourcentage, gros et centré.",
          choices = function() return { { "both", "Valeurs + %" }, { "values", "Valeurs" }, { "percent", "%" }, { "none", "Rien" } } end,
          apply = function() if NZR.FramesRefresh then NZR.FramesRefresh() end end },
        { t = "switch", key = "ufShort", section = "Texte des barres", label = "Grands nombres raccourcis", desc = "12,4k au lieu de 12 400.",
          apply = function() if NZR.FramesRefresh then NZR.FramesRefresh() end end },
        { t = "cycle", key = "ufFont", section = "Texte des barres", label = "Police", desc = "Police des chiffres de vie et de mana. Le nom garde la police dorée du jeu.",
          choices = function() return NZR.FONTS end, preview = function(k) return NZR.FontPath(k) end,
          apply = function() if NZR.FramesRefresh then NZR.FramesRefresh() end end },
        { t = "cycle", key = "ufOutline", section = "Texte des barres", label = "Contour du texte", desc = "Ombre seule : net et léger (conseillé). Contour : bord noir autour des lettres.",
          choices = function() return NZR.OUTLINES end,
          apply = function() if NZR.FramesRefresh then NZR.FramesRefresh() end end },
        { t = "slider", key = "ufFontSize", section = "Texte des barres", label = "Taille du texte", desc = "100 % = taille normale.", min = 0.7, max = 1.5, step = 0.05,
          apply = function() if NZR.FramesRefresh then NZR.FramesRefresh() end end },
        { t = "choice", key = "ufColor", section = "Couleurs", label = "Barre de vie", desc = "Verte comme le jeu, ou couleur de classe pour les joueurs (rouge pour les monstres à combattre, vert pour les PNJ amicaux).",
          choices = function() return { { "green", "Verte" }, { "class", "Couleur de classe" } } end,
          apply = function() if NZR.FramesRefresh then NZR.FramesRefresh() end end },
        { t = "slider", key = "ufHealthShade", section = "Couleurs", label = "Nuance de la vie", desc = "Moins de 100 % = plus foncé (le texte ressort mieux), plus = plus clair.", min = 0.4, max = 1.5, step = 0.05,
          apply = function() if NZR.FramesRefresh then NZR.FramesRefresh() end end },
        { t = "choice", key = "ufPowerColor", section = "Couleurs", label = "Barre de mana / énergie", desc = "Couleur du jeu (bleu, jaune, rouge selon la ressource) ou couleur de classe.",
          choices = function() return { { "game", "Du jeu" }, { "class", "Couleur de classe" } } end,
          apply = function() if NZR.FramesRefresh then NZR.FramesRefresh() end end },
        { t = "slider", key = "ufPowerShade", section = "Couleurs", label = "Nuance de la mana", desc = "Moins de 100 % = plus foncé, plus = plus clair.", min = 0.4, max = 1.5, step = 0.05,
          apply = function() if NZR.FramesRefresh then NZR.FramesRefresh() end end },
        { t = "switch", key = "groupFrames", section = "Groupe et raid", label = "Cadres de groupe et de raid NZR", desc = "Remplace les cases du jeu par les nôtres : cadre doré, couleur de classe, vie, mana, rôle, chef, marque, soins en approche, débuffs à dissiper, hors de portée = transparent.", r = true },
        { t = "choice", key = "grpPartyStyle", section = "Groupe et raid", label = "En groupe (5)", desc = "Larges comme nos cadres, ou les mêmes cases que le raid.", r = true,
          choices = function() return { { "big", "Larges" }, { "compact", "Cases de raid" } } end },
        { t = "choice", key = "grpName", section = "Groupe et raid", label = "Nom affiché", desc = "Nom complet (prénom + nom) ou prénom seul (pratique en raid).",
          choices = function() return { { "full", "Nom complet" }, { "first", "Prénom seul" } } end, apply = function() if NZR.GroupRefresh then NZR.GroupRefresh() end end },
        { t = "choice", key = "grpNameColor", section = "Groupe et raid", label = "Couleur du nom", desc = "Doré (groupe) / blanc (raid), ou couleur de classe.",
          choices = function() return { { "default", "Doré / blanc" }, { "class", "Classe" } } end, apply = function() if NZR.GroupRefresh then NZR.GroupRefresh() end end },
        { t = "choice", key = "grpColor", section = "Groupe et raid", label = "Barre de vie", desc = "Couleur de classe ou verte. La nuance suit le réglage « Nuance de la vie ».",
          choices = function() return { { "class", "Classe" }, { "green", "Verte" } } end, apply = function() if NZR.GroupRefresh then NZR.GroupRefresh() end end },
        { t = "choice", key = "grpText", section = "Groupe et raid", label = "Texte de vie", desc = "Auto : valeurs dans les cases larges, % dans les cases de raid.",
          choices = function() return { { "auto", "Auto" }, { "percent", "%" }, { "values", "Valeurs" }, { "none", "Rien" } } end, apply = function() if NZR.GroupRefresh then NZR.GroupRefresh() end end },
        { t = "switch", key = "grpPower", section = "Groupe et raid", label = "Barre de mana", desc = "Fine barre de mana / énergie sous la vie.", r = true },
        { t = "switch", key = "grpRole", section = "Groupe et raid", label = "Icône de rôle", desc = "Tank, soigneur, dégâts (si le rôle est choisi).", apply = function() if NZR.GroupRefresh then NZR.GroupRefresh() end end },
        { t = "choice", key = "grpBuffs", section = "Groupe : buffs", label = "Buffs", desc = "En bas à gauche de chaque case, avec le temps restant.",
          choices = function() return { { "mine", "Les miens" }, { "all", "Tous" }, { "none", "Aucun" } } end, apply = function() if NZR.GroupRefresh then NZR.GroupRefresh() end end },
        { t = "switch", key = "grpDebuffs", section = "Groupe : buffs", label = "Débuffs à dissiper", desc = "Jusqu'à 3 icônes en bas à droite, bord à la couleur du type (magie, malédiction…).", apply = function() if NZR.GroupRefresh then NZR.GroupRefresh() end end },
        { t = "switch", key = "grpDebuffAll", section = "Groupe : buffs", label = "Tous les débuffs", desc = "Montre aussi ceux que tu ne peux pas dissiper.", apply = function() if NZR.GroupRefresh then NZR.GroupRefresh() end end },
        { t = "slider", key = "grpCellScale", section = "Groupe : taille", label = "Taille des cases", desc = "Largeur et hauteur de chaque case.", min = 0.7, max = 1.5, step = 0.05, r = true },
        { t = "slider", key = "grpScale", section = "Groupe : taille", label = "Taille de l'ensemble", desc = "Agrandit tout le cadre (hors combat).", min = 0.6, max = 1.5, step = 0.05, apply = function() if NZR.GroupRefresh then NZR.GroupRefresh() end end },
        { t = "slider", key = "grpAlpha", section = "Groupe : taille", label = "Opacité du cadre", desc = "Fond pierre et bordure dorée autour des cases.", min = 0.2, max = 1, step = 0.05, apply = function() if NZR.GroupRefresh then NZR.GroupRefresh() end end },
        { t = "button", section = "Groupe : taille", label = "Déplacer", desc = "Bloc « Groupe et raid » à glisser. Reclique pour finir.",
          text = function() return NZR.unlocked and "Terminer" or "Déplacer" end,
          click = function() NZR:SetUnlocked(not NZR.unlocked) end },
        { t = "switch", key = "plates", section = "Barres des monstres", label = "Personnaliser ces barres", desc = "Coche pour appliquer les deux choix ci-dessous. Décoché : les barres restent exactement comme dans le jeu.", r = true },
        { t = "choice", key = "npText", section = "Barres des monstres", label = "Texte affiché", desc = "Comme pour tes cadres.",
          choices = function() return { { "both", "Vie + %" }, { "values", "Vie" }, { "percent", "%" }, { "none", "Rien" } } end,
          apply = function() if NZR.PlatesRefresh then NZR.PlatesRefresh() end end },
        { t = "choice", key = "npColor", section = "Barres des monstres", label = "Couleur", desc = "Celle du jeu, ou rouge pour tout ce que tu peux attaquer (gris si un autre joueur l'a déjà touché).",
          choices = function() return { { "game", "Du jeu" }, { "red", "Rouge si attaquable" } } end,
          apply = function() if NZR.PlatesRefresh then NZR.PlatesRefresh() end end },
        { t = "cycle", key = "npFont", section = "Barres des monstres", label = "Police", desc = "Du jeu = exactement celle d'origine.",
          choices = function() return NZR.FONTS end, preview = function(k) return NZR.FontPath(k) end,
          apply = function() if NZR.PlatesRefresh then NZR.PlatesRefresh() end end },
        { t = "cycle", key = "npOutline", section = "Barres des monstres", label = "Contour du texte", desc = "Du jeu = comme d'origine. Ombre seule : plus net.",
          choices = function() local l = { { "game", "Du jeu" } }; for _, v in ipairs(NZR.OUTLINES) do table.insert(l, v) end; return l end,
          apply = function() if NZR.PlatesRefresh then NZR.PlatesRefresh() end end },
        { t = "slider", key = "npFontSize", section = "Barres des monstres", label = "Taille du texte", desc = "100 % = taille d'origine.", min = 0.7, max = 1.6, step = 0.05,
          apply = function() if NZR.PlatesRefresh then NZR.PlatesRefresh() end end },
      } },
    { id = "look", name = "Interface", desc = "L'interface du jeu en mieux : sorts et buffs, infobulles, minicarte, fenêtres, butin. Rien n'est changé tant que tu n'actives pas.",
      items = {
        { t = "switch", section = "Sorts et buffs", key = "theme", label = "Barres d'action (sorts)", desc = "Coins arrondis discrets, bord fin, raccourcis lisibles, survol coloré.", r = true },
        { t = "switch", section = "Sorts et buffs", key = "auras", label = "Buffs et débuffs", desc = "Icônes arrondies, bord fin (rouge pour les débuffs), durée lisible.", r = true },
        { t = "choice", section = "Sorts et buffs", key = "meterTheme", label = "Teinte", r = true, desc = "La même que le meter. Jeu : se fond dans WoW. Noir : sobre. Violet : couleurs NZR.",
          choices = function() return { { "jeu", "Jeu" }, { "noir", "Noir" }, { "violet", "Violet" } } end },
        { t = "switch", key = "tooltipOpaque", section = "Infobulles", label = "Infobulles opaques", desc = "Fond plein (plus de décor qui transparaît) et toujours au-dessus du reste.", r = true },
        { t = "slider", key = "tooltipAlpha", section = "Infobulles", label = "Opacité des infobulles", desc = "100 % = complètement opaque.", min = 0.5, max = 1, step = 0.05 },
        { t = "switch", key = "moveTooltip", section = "Infobulles", label = "Infobulle déplaçable", desc = "Puis « Placer l'infobulle et les sacs » pour choisir l'endroit.", r = true },
        { t = "switch", key = "tooltipCursor", section = "Infobulles", label = "Infobulle à la souris", desc = "Elle s'affiche juste à côté du curseur, en haut à gauche.", r = true },
        { t = "switch", key = "squareMinimap", section = "Minicarte", label = "Minicarte carrée", desc = "Carte carrée avec le bord des infobulles du jeu ; boutons et nom de zone inchangés. Molette = zoom.", r = true },
        { t = "switch", key = "mmButtonsSave", section = "Minicarte", label = "Retenir la place des boutons d'addons", desc = "Les petits boutons ronds autour de la minicarte (Questie…) restent où tu les as glissés, même après un /reload.", r = true },
        { t = "switch", key = "moveWindows", section = "Fenêtres et sacs", label = "Toutes les fenêtres du jeu déplaçables", desc = "Personnage, carte, sorts, talents, collections, PNJ, quêtes… Glisse par la barre de titre ; clic droit dessus = place d'origine.", r = true },
        { t = "switch", key = "moveBags", section = "Fenêtres et sacs", label = "Sacs déplaçables", desc = "Toute la pile de sacs suit l'endroit choisi.", r = true },
        { t = "switch", key = "reopenWindows", section = "Fenêtres et sacs", label = "Rouvrir les fenêtres après /reload", desc = "Les fenêtres NZR ouvertes avant un rechargement (réglages sur le même onglet, guide, bénédictions) se rouvrent toutes seules." },
        { t = "button", section = "Fenêtres et sacs", label = "Placer l'infobulle et les sacs", desc = "Fait apparaître des blocs à glisser. Reclique ou tape /nzr lock pour finir.",
          text = function() return NZR.unlocked and "Terminer" or "Placer" end,
          click = function() NZR:SetUnlocked(not NZR.unlocked) end },
        { t = "switch", key = "lootAll", section = "Butin", label = "Bouton « Tout ramasser »", desc = "Bouton du jeu sous la fenêtre de butin.", r = true },
        { t = "switch", key = "lootAutoClose", section = "Butin", label = "Fermer le butin quand il est vide", desc = "La fenêtre se ferme toute seule dès qu'il n'y a plus rien à ramasser." },
        { t = "choice", key = "lootKey", section = "Butin", label = "Touche pour tout ramasser", desc = "Active seulement quand la fenêtre de butin est ouverte. Hors combat.",
          choices = function() return { { "E", "E" }, { "F", "F" }, { "R", "R" }, { "SPACE", "Espace" }, { "none", "Aucune" } } end },
        { t = "switch", key = "sct", section = "Texte de combat", label = "Texte de combat défilant", desc = "Tes coups montent à droite avec l'icône du sort, les dégâts reçus descendent à gauche, les soins en vert, « +Combat / -Combat » au centre.", r = true },
        { t = "button", section = "Texte de combat", label = "Essayer", desc = "Un petit combat pour voir le rendu (texte activé et rechargé).", text = function() return "Essayer" end,
          click = function() if NZR.ScrollTest then NZR.ScrollTest() end end },
        { t = "switch", key = "sctOut", section = "Texte de combat", label = "Mes dégâts", desc = "Les coups sur ta cible (critiques plus gros, en jaune)." },
        { t = "switch", key = "sctIn", section = "Texte de combat", label = "Dégâts reçus", desc = "Ce que tu prends, et les esquives / parades / ratés." },
        { t = "switch", key = "sctHeal", section = "Texte de combat", label = "Soins reçus", desc = "En vert, à gauche." },
        { t = "switch", key = "sctNotice", section = "Texte de combat", label = "Entrée et sortie de combat", desc = "« +Combat » / « -Combat » au centre." },
        { t = "switch", key = "sctPower", section = "Texte de combat", label = "Gains de ressource", desc = "+Rage, +Énergie, +Mana… pour toutes les classes. La régénération normale n'est pas affichée, seulement les vrais gains." },
        { t = "switch", key = "sctKill", section = "Texte de combat", label = "Coup fatal", desc = "« Coup fatal ! » quand ta cible meurt juste après ton coup (en solo)." },
        { t = "switch", key = "sctOthers", section = "Texte de combat", label = "En groupe : tous les coups sur ma cible", desc = "Le jeu ne dit pas qui frappe : en groupe, seuls tes coups seuls sont sûrs. Coche pour tout voir quand même." },
        { t = "switch", key = "sctHideBlizz", section = "Texte de combat", label = "Cacher les chiffres du jeu", desc = "Évite les doublons. Tes réglages du jeu reviennent quand tu coupes, à la déconnexion, ou si tu retires NZR.", r = true },
        { t = "cycle", key = "sctFont", section = "Texte de combat", label = "Police", desc = "Police des chiffres.",
          choices = function() return NZR.FONTS end, preview = function(k) return NZR.FontPath(k) end },
        { t = "slider", key = "sctSize", section = "Texte de combat", label = "Taille du texte", desc = "100 % = taille normale.", min = 0.6, max = 2, step = 0.05 },
        { t = "switch", key = "menuButton", section = "Menu Échap", label = "Bouton « NZR Forever » dans le menu Échap", desc = "Tout en haut du menu, pour ouvrir ces réglages. Sinon : /nzr." },
      } },
    { id = "quest", name = "Quêtes", desc = "Pour progresser : guide des talents et des zones, flèche vers ta quête, surbrillance de ce qu'il faut ramasser ou tuer.",
      items = {
        { t = "switch", key = "guide", section = "Guide de progression", label = "Guide de progression", desc = "Petite icône (livre doré) qui ouvre le build à suivre selon ton niveau : talents à prendre, déjà pris, prochain point. Paladin pour l'instant (aussi /nzr guide).", r = true },
        { t = "button", section = "Guide de progression", label = "Ouvrir le guide", desc = "Si le guide est activé et rechargé.", text = function() return "Ouvrir" end,
          click = function() if NZR.GuideToggle then NZR.GuideToggle() end end },
        { t = "switch", key = "compass", section = "Flèche de quête", label = "Flèche vers ta quête (Forever Compass)", desc = "Flèche ou boussole à placer où tu veux, vers la quête suivie ; rouge vers ton cadavre quand tu es mort. Inutile si tu as déjà l'addon Forever Compass.", r = true },
        { t = "button", section = "Flèche de quête", label = "Réglages de la flèche", desc = "Style, couleur, taille, infos affichées… (aussi /fc).",
          text = function() return "Ouvrir" end,
          click = function()
              if NZR.CompassOpen then NZR:ToggleOptions(false); NZR.CompassOpen()
              else NZR:Print("active d'abord la flèche, puis clique sur Recharger.") end
          end },
        { t = "switch", key = "questHL", section = "Surbrillance", label = "Surbrillance des quêtes", desc = "Un court effet quand ta souris passe sur un objet, un PNJ ou un monstre utile à une de tes quêtes.", r = true },
        { t = "choice", key = "hlStyle", section = "Surbrillance", label = "Style", desc = "Ping : anneaux au sol. Éclat : étoile qui scintille. Halo : lueur douce.",
          choices = function() return { { "ping", "Ping" }, { "eclat", "Éclat" }, { "halo", "Halo" } } end,
          apply = function() if NZR.HighlightTest then NZR.HighlightTest() end end },
        { t = "choice", key = "hlColor", section = "Surbrillance", label = "Couleur", desc = "Doré comme les quêtes du jeu, ou une autre couleur.",
          choices = function() return { { "gold", "Doré" }, { "white", "Blanc" }, { "green", "Vert" }, { "blue", "Bleu" } } end,
          apply = function() if NZR.HighlightTest then NZR.HighlightTest() end end },
        { t = "slider", key = "hlSize", section = "Surbrillance", label = "Taille de l'effet", desc = "100 % = taille normale.", min = 0.5, max = 2, step = 0.1 },
        { t = "switch", key = "hlSound", section = "Surbrillance", label = "Petit son", desc = "Le son du ping de la carte." },
        { t = "button", section = "Surbrillance", label = "Essayer", desc = "Joue l'effet au-dessus de ta souris (surbrillance activée et rechargée).",
          text = function() return "Essayer" end,
          click = function() if NZR.HighlightTest then NZR.HighlightTest() else NZR:Print("active la surbrillance, puis clique sur Recharger.") end end },
        { t = "switch", key = "hlObjects", section = "Surbrillance : sur quoi", label = "Objets (caisses, plantes…)", desc = "Ce que tu ramasses ou utilises pour une quête." },
        { t = "switch", key = "hlNPCs", section = "Surbrillance : sur quoi", label = "PNJ", desc = "Les personnages à qui parler pour une quête." },
        { t = "switch", key = "hlMobs", section = "Surbrillance : sur quoi", label = "Monstres", desc = "Les monstres à tuer ou à fouiller pour une quête." },
        { t = "switch", key = "hlCombat", section = "Surbrillance : sur quoi", label = "Rien en combat", desc = "Pas d'effet pendant les combats." },
      } },
    { id = "paladin", name = "Paladin", desc = "Assistant de bénédictions (comme PallyPower) : répartition entre paladins du groupe et barre pour les lancer. Désactivé de base.",
      items = {
        { t = "switch", section = "Assistant", key = "paladin", label = "Assistant de bénédictions", desc = "Seulement si tu joues un paladin. Les autres paladins avec NZR Forever partagent la même répartition.", r = true },
        { t = "button", section = "Assistant", label = "Répartition des bénédictions", desc = "Qui donne quoi à quelle classe (aussi /nzr bene, ou clic droit sur la barre).",
          text = function() return "Ouvrir" end,
          click = function() if NZR.BlessOpen then NZR:ToggleOptions(false); NZR.BlessOpen() else NZR:Print("active d'abord l'assistant, puis clique sur Recharger.") end end },
        { t = "switch", key = "blessGreater", section = "Barre", label = "Bénédictions supérieures au clic gauche", desc = "Toute la classe d'un coup (demande un Symbole des rois). Clic droit = version simple." },
        { t = "switch", key = "blessSolo", section = "Barre", label = "Afficher la barre même seul", desc = "Sinon, elle n'apparaît qu'en groupe ou en raid.", r = true },
        { t = "switch", key = "blessLock", section = "Barre", label = "Verrouiller la barre", desc = "Sinon, glisse-la par son titre pour la déplacer." },
        { t = "slider", key = "blessScale", section = "Barre", label = "Taille de la barre", desc = "Taille des boutons de bénédiction.", min = 0.6, max = 1.6, step = 0.05,
          apply = function() local b = _G.NZRF_BlessBar; if b and not InCombatLockdown() then b:SetScale(NZR.db.blessScale) end end },
      } },
}

---------------------------------------------------------------------------
-- Widgets au style du jeu (modèles Blizzard : cases, boutons rouges, onglets)
---------------------------------------------------------------------------
local function Make(kind, name, parent, template)
    local ok, f = pcall(CreateFrame, kind, name, parent, template)
    if ok and f then return f, true end
    return CreateFrame(kind, name, parent), false
end

local function GameText(parent, font, r, g, b)
    local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
    if r then fs:SetTextColor(r, g, b) end
    fs:SetJustifyH("LEFT")
    return fs
end

local function Switch(parent, get, set)
    local b = Make("CheckButton", nil, parent, "UICheckButtonTemplate")
    b:SetSize(26, 26)
    function b:Refresh() self:SetChecked(get() and true or false) end
    b:SetScript("OnClick", function(s)
        set(s:GetChecked() and true or false)
        PlaySound(s:GetChecked() and 856 or 857)
    end)
    b:Refresh()
    return b
end

-- choix : boutons radio du jeu
local function Choice(parent, list, get, set)
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(22)
    f.btns = {}
    local x = 0
    for i, ch in ipairs(list) do
        local b = Make("CheckButton", nil, f, "UIRadioButtonTemplate")
        b:SetSize(18, 18)
        b:SetPoint("LEFT", x, 0)
        b.value = ch[1]
        local t = GameText(f, "GameFontHighlightSmall")
        t:SetPoint("LEFT", b, "RIGHT", 2, 0)
        t:SetText(ch[2])
        b.label = t
        x = x + 18 + 2 + math.ceil(t:GetStringWidth()) + 14
        b:SetScript("OnClick", function() set(b.value); f:Refresh(); PlaySound(856) end)
        f.btns[i] = b
    end
    f:SetWidth(math.max(1, x - 14))
    function f:Refresh()
        local v = get()
        for _, b in ipairs(self.btns) do
            b:SetChecked(b.value == v)
            if b.value == v then b.label:SetTextColor(1, 0.82, 0) else b.label:SetTextColor(0.9, 0.9, 0.9) end
        end
    end
    f:Refresh()
    return f
end

-- plusieurs choix : cases à cocher du jeu
local function Multi(parent, list, getTable, onChange, maxW)
    local f = CreateFrame("Frame", nil, parent)
    f.boxes = {}
    local x, y = 0, 0
    maxW = maxW or 480
    for _, ch in ipairs(list) do
        local b = Make("CheckButton", nil, f, "UICheckButtonTemplate")
        b:SetSize(22, 22)
        local t = GameText(f, "GameFontHighlightSmall")
        t:SetText(ch[2])
        local w = 22 + 2 + math.ceil(t:GetStringWidth()) + 14
        if x + w > maxW then x = 0; y = y - 24 end
        b:SetPoint("TOPLEFT", x, y)
        t:SetPoint("LEFT", b, "RIGHT", 1, 0)
        x = x + w
        b.value = ch[1]
        b:SetScript("OnClick", function(s)
            local tb = getTable()
            tb[s.value] = s:GetChecked() and true or false
            onChange()
        end)
        table.insert(f.boxes, b)
    end
    f:SetSize(maxW, -y + 22)
    function f:Refresh()
        local tb = getTable()
        for _, b in ipairs(self.boxes) do b:SetChecked(tb[b.value] and true or false) end
    end
    f:Refresh()
    return f
end

-- curseur : rail et bouton du jeu, valeur en %
local function Slider(parent, item)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(230, 24)
    local v = GameText(f, "GameFontHighlightSmall")
    v:SetPoint("RIGHT", 0, 0); v:SetWidth(40); v:SetJustifyH("RIGHT")
    local s = CreateFrame("Slider", nil, f)
    s:SetOrientation("HORIZONTAL")
    s:SetPoint("LEFT", 0, 0); s:SetPoint("RIGHT", v, "LEFT", -8, 0)
    s:SetHeight(17)
    local track = s:CreateTexture(nil, "BACKGROUND")
    track:SetPoint("LEFT", 0, 0); track:SetPoint("RIGHT", 0, 0); track:SetHeight(8)
    if not pcall(track.SetAtlas, track, "Minimal_SliderBar_Middle", false) or not track:GetAtlas() then
        track:SetColorTexture(0.12, 0.12, 0.13, 1)
    end
    s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    local th = s:GetThumbTexture(); th:SetSize(32, 32)
    s:SetMinMaxValues(item.min, item.max)
    s:SetValueStep(item.step)
    s:SetObeyStepOnDrag(true)
    local function show(val) v:SetText(("%d %%"):format(math.floor(val * 100 + 0.5))) end
    s:SetValue(NZR.db[item.key] or 1); show(NZR.db[item.key] or 1)
    s:SetScript("OnValueChanged", function(_, val)
        val = math.floor(val / item.step + 0.5) * item.step
        NZR.db[item.key] = val
        show(val)
        if item.apply then item.apply() end
    end)
    f.Refresh = function() s:SetValue(NZR.db[item.key] or 1) end
    return f
end

local function PushButton(parent, textFn, onClick)
    local b = Make("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetHeight(22)
    function b:Refresh()
        self:SetText(textFn())
        local fs = self:GetFontString()
        self:SetWidth(math.max(110, (fs and fs:GetStringWidth() or 80) + 30))
    end
    b:SetScript("OnClick", function(s) onClick(); s:Refresh() end)
    b:Refresh()
    return b
end

-- liste déroulante façon Options du jeu : ◀ valeur ▶ (la valeur s'écrit dans sa propre police)
local function Cycle(parent, list, get, set, preview)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(230, 26)
    local function arrow(dir)
        local b = CreateFrame("Button", nil, f)
        b:SetSize(24, 24)
        local base = dir < 0 and "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-" or "Interface\\Buttons\\UI-SpellbookIcon-NextPage-"
        b:SetNormalTexture(base .. "Up"); b:SetPushedTexture(base .. "Down"); b:SetDisabledTexture(base .. "Disabled")
        b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
        return b
    end
    local prev, nextB = arrow(-1), arrow(1)
    prev:SetPoint("LEFT", 0, 0); nextB:SetPoint("RIGHT", 0, 0)
    local box = CreateFrame("Button", nil, f)
    box:SetPoint("LEFT", prev, "RIGHT", 2, 0); box:SetPoint("RIGHT", nextB, "LEFT", -2, 0); box:SetHeight(22)
    local edge = box:CreateTexture(nil, "BACKGROUND", nil, -1)
    edge:SetAllPoints(); edge:SetColorTexture(0.45, 0.36, 0.18, 0.9)
    local bg = box:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", 1, -1); bg:SetPoint("BOTTOMRIGHT", -1, 1); bg:SetColorTexture(0.06, 0.05, 0.04, 0.95)
    local hl = box:CreateTexture(nil, "HIGHLIGHT"); hl:SetPoint("TOPLEFT", 1, -1); hl:SetPoint("BOTTOMRIGHT", -1, 1)
    hl:SetColorTexture(1, 0.82, 0, 0.08)
    local t = box:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    t:SetPoint("LEFT", 6, 0); t:SetPoint("RIGHT", -6, 0); t:SetJustifyH("CENTER")
    local function index()
        local v = get()
        for i, ch in ipairs(list) do if ch[1] == v then return i end end
        return 1
    end
    local function go(d)
        local i = (index() - 1 + d) % #list + 1
        set(list[i][1]); f:Refresh(); PlaySound(856)
    end
    prev:SetScript("OnClick", function() go(-1) end)
    nextB:SetScript("OnClick", function() go(1) end)
    box:SetScript("OnClick", function(_, btn) go(btn == "RightButton" and -1 or 1) end)
    box:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    function f:Refresh()
        local ch = list[index()]
        t:SetFontObject("GameFontHighlight")
        if preview then
            local path = preview(ch[1])
            local _, size = t:GetFont()
            if path then pcall(t.SetFont, t, path, size or 12, "") end
        end
        t:SetText(ch[2])
    end
    f:Refresh()
    return f
end

---------------------------------------------------------------------------
-- Fenêtre (cadre du jeu, onglets en bas comme Personnage ou Collections)
---------------------------------------------------------------------------
local function NeedsReload()
    for key in pairs(reloadKeys) do
        if NZR.db[key] ~= snapshot[key] then return true end
    end
    return false
end

local function MeterApply(item)
    if item.meter and NZR.MeterRefresh then
        NZR.MeterRefresh(item.resize ~= false and (item.key == "meterCols" or item.key == "meterIcons" or item.key == "meterShare"))
    end
end

-- une catégorie = une page défilante à droite
local function BuildSection(content, title, items, name)
    local scroll = Make("ScrollFrame", name, content, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", LIST_W + 10, -6)
    scroll:SetPoint("BOTTOMRIGHT", -28, 6)
    scroll:Hide()
    local PW = (W - 16) - (LIST_W + 10) - 34
    local p = CreateFrame("Frame", nil, scroll)
    p:SetSize(PW, 100)
    scroll:SetScrollChild(p)
    scroll:SetScript("OnShow", function(s) s:SetVerticalScroll(0) end)

    scroll.controls = {}
    local st = GameText(p, "GameFontNormalLarge")
    st:SetPoint("TOPLEFT", 8, -10)
    st:SetText(title)
    local ln = p:CreateTexture(nil, "ARTWORK")
    ln:SetAtlas("Options_HorizontalDivider", true)
    if not ln:GetAtlas() then ln:SetColorTexture(1, 1, 1, 0.12); ln:SetHeight(1) end
    ln:SetPoint("TOPLEFT", st, "BOTTOMLEFT", -4, -4)
    ln:SetPoint("RIGHT", p, "RIGHT", -8, 0)
    local y = -44
    for _, item in ipairs(items) do
        local row = CreateFrame("Frame", nil, p)
        row:SetPoint("TOPLEFT", 0, y); row:SetPoint("TOPRIGHT", 0, y)
        local hl = row:CreateTexture(nil, "BACKGROUND")
        hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.04); hl:Hide()
        row:EnableMouse(true)
        row:SetScript("OnEnter", function() hl:Show() end)
        row:SetScript("OnLeave", function() hl:Hide() end)

        local label = GameText(row, "GameFontHighlight")
        label:SetPoint("TOPLEFT", 14, -8)
        label:SetText(item.label .. (item.r and "  |cff808080(recharge)|r" or ""))
        if item.r then reloadKeys[item.key] = true end
        local desc = GameText(row, "GameFontDisableSmall")
        desc:SetTextColor(0.62, 0.62, 0.62)
        desc:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -4)
        desc:SetWordWrap(true)
        desc:SetText(item.desc)

        local function changed()
            if item.apply then item.apply() end
            MeterApply(item)
            win.Update()
        end
        local ctl, rowH = nil, 46
        if item.t == "switch" then
            ctl = Switch(row, function() return NZR.db[item.key] end, function(v) NZR.db[item.key] = v; changed() end)
        elseif item.t == "choice" then
            ctl = Choice(row, item.choices(), function() return NZR.db[item.key] end, function(v) NZR.db[item.key] = v; changed() end)
        elseif item.t == "cycle" then
            ctl = Cycle(row, item.choices(), function() return NZR.db[item.key] end, function(v) NZR.db[item.key] = v; changed() end, item.preview)
        elseif item.t == "slider" then
            ctl = Slider(row, item)
        elseif item.t == "button" then
            ctl = PushButton(row, item.text, item.click)
        elseif item.t == "multi" then
            ctl = Multi(row, item.choices(), function()
                if item.flat then return NZR.db end         -- cases = réglages oui/non séparés
                if type(NZR.db[item.key]) ~= "table" then NZR.db[item.key] = {} end
                return NZR.db[item.key]
            end, changed, PW - 50)
        end
        if item.t == "multi" then
            ctl:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", -4, -6)
            desc:SetPoint("RIGHT", row, "RIGHT", -14, 0)
            rowH = 46 + ctl:GetHeight() + 6
        else
            ctl:SetPoint("RIGHT", row, "RIGHT", -14, 0)
            desc:SetPoint("RIGHT", ctl, "LEFT", -16, 0)
            label:SetPoint("RIGHT", ctl, "LEFT", -16, 0)
        end
        row:SetHeight(rowH)
        table.insert(scroll.controls, ctl)
        y = y - rowH - 2
    end
    p:SetHeight(-y + 10)
    return scroll
end

-- un onglet = colonne de catégories à gauche + la catégorie choisie à droite
local function BuildPage(content, page, idx)
    local holder = CreateFrame("Frame", nil, content)
    holder:SetAllPoints()
    holder:Hide()
    holder.controls = {}

    -- regroupe les réglages par catégorie, dans l'ordre
    local groups, byName = {}, {}
    for _, item in ipairs(page.items) do
        local s = item.section or "Général"
        if not byName[s] then byName[s] = { name = s, items = {} }; table.insert(groups, byName[s]) end
        table.insert(byName[s].items, item)
    end

    -- colonne de gauche : fond un peu plus sombre + filet, comme les Options du jeu
    local list = CreateFrame("Frame", nil, holder)
    list:SetPoint("TOPLEFT", 4, -4); list:SetPoint("BOTTOMLEFT", 4, 4); list:SetWidth(LIST_W)
    local lbg = list:CreateTexture(nil, "BACKGROUND")
    lbg:SetAllPoints(); lbg:SetColorTexture(0, 0, 0, 0.25)
    local sep = holder:CreateTexture(nil, "ARTWORK")
    sep:SetPoint("TOPLEFT", list, "TOPRIGHT", 2, 0); sep:SetPoint("BOTTOMLEFT", list, "BOTTOMRIGHT", 2, 0); sep:SetWidth(1)
    sep:SetColorTexture(0.55, 0.45, 0.25, 0.5)

    holder.sections, holder.entries = {}, {}
    local function Select(s)
        holder.current = s
        for j, sc in ipairs(holder.sections) do sc:SetShown(j == s) end
        for j, e in ipairs(holder.entries) do
            e.sel:SetShown(j == s)
            if j == s then e.text:SetTextColor(1, 1, 1) else e.text:SetTextColor(1, 0.82, 0) end
        end
    end
    holder.Select = Select
    for s, g in ipairs(groups) do
        local sc = BuildSection(holder, g.name, g.items, "NZRF_OptionsScroll" .. idx .. "_" .. s)
        holder.sections[s] = sc
        for _, c in ipairs(sc.controls) do table.insert(holder.controls, c) end

        local e = CreateFrame("Button", nil, list)
        e:SetHeight(24)
        e:SetPoint("TOPLEFT", 4, -8 - (s - 1) * 26); e:SetPoint("RIGHT", list, "RIGHT", -4, 0)
        e.sel = e:CreateTexture(nil, "BACKGROUND")
        e.sel:SetAllPoints()
        if not (pcall(e.sel.SetAtlas, e.sel, "Options_List_Active", false) and e.sel:GetAtlas()) then
            e.sel:SetColorTexture(1, 0.82, 0, 0.16)
        end
        e.sel:Hide()
        local hov = e:CreateTexture(nil, "HIGHLIGHT")
        hov:SetAllPoints()
        if not (pcall(hov.SetAtlas, hov, "Options_List_Hover", false) and hov:GetAtlas()) then
            hov:SetColorTexture(1, 1, 1, 0.07)
        end
        e.text = e:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        e.text:SetPoint("LEFT", 10, 0); e.text:SetPoint("RIGHT", -6, 0); e.text:SetJustifyH("LEFT")
        e.text:SetWordWrap(false)
        e.text:SetText(g.name)
        e:SetScript("OnClick", function() Select(s); PlaySound(856) end)
        holder.entries[s] = e
    end
    Select(1)
    return holder
end

local function Create()
    win = Make("Frame", "NZRF_Options", UIParent, "ButtonFrameTemplate")
    win:SetSize(W, H)
    win:SetPoint("CENTER")
    win:SetFrameStrata("HIGH")
    win:SetToplevel(true)
    win:SetMovable(true)
    win:EnableMouse(true)
    win:SetClampedToScreen(true)
    tinsert(UISpecialFrames, "NZRF_Options")
    if ButtonFrameTemplate_HidePortrait then pcall(ButtonFrameTemplate_HidePortrait, win) end
    if ButtonFrameTemplate_HideButtonBar then pcall(ButtonFrameTemplate_HideButtonBar, win) end
    local title = "NZR Forever"
    if not (win.SetTitle and pcall(win.SetTitle, win, title)) then
        local tt = win.TitleText or (win.TitleContainer and win.TitleContainer.TitleText)
        if tt then tt:SetText(title) end
    end
    -- déplacer par la barre de titre
    local drag = CreateFrame("Frame", nil, win)
    drag:SetPoint("TOPLEFT", 0, 0); drag:SetPoint("TOPRIGHT", -28, 0); drag:SetHeight(22)
    drag:EnableMouse(true); drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function() win:StartMoving() end)
    drag:SetScript("OnDragStop", function() win:StopMovingOrSizing() end)

    local inset = win.Inset or win
    win.desc = GameText(win, "GameFontNormal")
    win.desc:SetPoint("TOPLEFT", 16, -64)
    win.desc:SetPoint("RIGHT", win, "RIGHT", -16, 0)
    win.desc:SetWordWrap(true)
    if win.Inset then
        win.Inset:ClearAllPoints()
        win.Inset:SetPoint("TOPLEFT", 8, -92)
        win.Inset:SetPoint("BOTTOMRIGHT", -8, 40)
    end

    win.pages, win.tabs = {}, {}
    local Show
    Show = function(i)
        for j, p in ipairs(win.pages) do p:SetShown(j == i) end
        if PanelTemplates_SetTab then pcall(PanelTemplates_SetTab, win, i) end
        win.current = i
        win.desc:SetText(PAGES[i].desc)
    end
    for i, page in ipairs(PAGES) do
        win.pages[i] = BuildPage(inset, page, i)
        -- onglets en haut (modèle du jeu « onglet du dessus », sinon onglet classique)
        local tab, top = Make("Button", "NZRF_OptionsTab" .. i, win, "PanelTopTabButtonTemplate")
        if not top then tab = Make("Button", "NZRF_OptionsTab" .. i .. "b", win, "PanelTabButtonTemplate") end
        tab:SetID(i)
        tab:SetText(page.name)
        if PanelTemplates_TabResize then pcall(PanelTemplates_TabResize, tab, 0) end
        if i == 1 then tab:SetPoint("TOPLEFT", win, "TOPLEFT", 14, -26)
        else tab:SetPoint("LEFT", win.tabs[i - 1], "RIGHT", top and 2 or -16, 0) end
        tab:SetScript("OnClick", function() Show(i); PlaySound(841) end)
        win.tabs[i] = tab
    end
    win.Tabs = win.tabs
    if PanelTemplates_SetNumTabs then pcall(PanelTemplates_SetNumTabs, win, #PAGES) end

    -- bas : tout réinitialiser, recharger, fermer (boutons du jeu)
    local resetAll = PushButton(win, function() return "Tout réinitialiser" end, function()
        StaticPopupDialogs["NZRF_RESET"] = {
            text = "Remettre tous les réglages de NZR Forever à zéro ?\nL'interface sera rechargée.",
            button1 = "Réinitialiser", button2 = "Annuler",
            OnAccept = function() NZRF_DB = nil; ReloadUI() end,
            timeout = 0, whileDead = true, hideOnEscape = true,
        }
        StaticPopup_Show("NZRF_RESET")
    end)
    resetAll:SetPoint("BOTTOMLEFT", 10, 12)
    local reload = PushButton(win, function() return "Recharger" end, function() ReloadUI() end)
    reload:SetPoint("LEFT", resetAll, "RIGHT", 6, 0)
    local done = PushButton(win, function() return "Fermer" end, function() win:Hide() end)
    done:SetPoint("BOTTOMRIGHT", -10, 12)
    local hint = GameText(win, "GameFontDisableSmall")
    hint:SetPoint("RIGHT", done, "LEFT", -12, 0)
    hint:SetJustifyH("RIGHT")

    function win.Update()
        local need = NeedsReload()
        if need then reload:LockHighlight() else reload:UnlockHighlight() end
        hint:SetText(need and "|cffffd100Clique sur Recharger pour appliquer.|r" or "Réglages enregistrés automatiquement.")
    end

    win:SetScript("OnShow", function()
        PlaySound(SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_OPEN or 839)
        for _, p in ipairs(win.pages) do
            for _, c in ipairs(p.controls) do if c.Refresh then c:Refresh() end end
        end
        if win.wantPage then win.Show(win.wantPage); win.wantPage = nil end
        win.Update()
    end)
    win:SetScript("OnHide", function() PlaySound(SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_CLOSE or 840) end)
    win.Show = Show
    Show(1)
    win:Hide()
end

function NZR:ToggleOptions(show, pageId)
    if not win then Create() end
    if show == nil then show = not win:IsShown() end
    if pageId then
        for i, page in ipairs(PAGES) do
            if page.id == pageId then win.wantPage = i end
        end
        if win:IsShown() and win.wantPage then win.Show(win.wantPage); win.wantPage = nil end
    end
    win:SetShown(show)
end

-- état de la fenêtre (onglet + catégorie), pour la rouvrir après un /reload
function NZR.OptionsState()
    if not win or not win:IsShown() then return nil end
    local pg = win.pages[win.current or 1]
    return { page = win.current or 1, section = pg and pg.current or 1 }
end
function NZR.OptionsRestore(st)
    if not st then return end
    NZR:ToggleOptions(true)
    if win and win.Show then
        win.Show(st.page or 1)
        local pg = win.pages[st.page or 1]
        if pg and pg.Select and st.section then pcall(pg.Select, st.section) end
    end
end

local function OpenFromMenu()
    if GameMenuFrame and GameMenuFrame:IsShown() then HideUIPanel(GameMenuFrame) end
    if SettingsPanel and SettingsPanel:IsShown() then pcall(HideUIPanel, SettingsPanel) end
    NZR:ToggleOptions(true)
end

function M:Init()
    -- valeurs de départ pour savoir si un rechargement est nécessaire
    for _, page in ipairs(PAGES) do
        for _, item in ipairs(page.items) do
            if item.key then snapshot[item.key] = NZR.db[item.key] end
        end
    end

    -- bouton "NZR Forever" dans le menu Échap (le menu garde le look du jeu)
    if GameMenuFrame and GameMenuFrame.InitButtons and GameMenuFrame.AddButton then
        hooksecurefunc(GameMenuFrame, "InitButtons", function(self)
            if NZR.db.menuButton == false then return end
            pcall(self.AddButton, self, "NZR Forever", OpenFromMenu)
            -- tout en haut du menu, avec un petit espace en dessous
            local pool = self.buttonPool
            if pool and pool.EnumerateActive then
                for b in pool:EnumerateActive() do
                    if b.GetText and b:GetText() == "NZR Forever" then
                        b.layoutIndex = 0
                        b.bottomPadding = 10
                    end
                end
                if self.MarkDirty then pcall(self.MarkDirty, self) end
                if self.Layout then pcall(self.Layout, self) end
            end
        end)
        -- (NZR Forever ne touche pas au reste du menu Échap)
    elseif GameMenuFrame then
        local b = CreateFrame("Button", nil, GameMenuFrame, "UIPanelButtonTemplate")
        b:SetSize(144, 21)
        b:SetText("NZR Forever")
        b:SetPoint("TOP", GameMenuFrame, "BOTTOM", 0, -4)
        b:SetScript("OnClick", OpenFromMenu)
    end

    -- Échap > Options > AddOns > NZR Forever
    if Settings and Settings.RegisterCanvasLayoutCategory then
        local panel = CreateFrame("Frame")
        local t = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        t:SetPoint("TOPLEFT", 16, -16)
        t:SetText("NZR Forever " .. NZR.version)
        local b = PushButton(panel, function() return "Ouvrir les réglages" end, OpenFromMenu)
        b:SetPoint("TOPLEFT", 16, -46)
        local ok, cat = pcall(Settings.RegisterCanvasLayoutCategory, panel, "NZR Forever")
        if ok and cat then pcall(Settings.RegisterAddOnCategory, cat) end
    end
end
