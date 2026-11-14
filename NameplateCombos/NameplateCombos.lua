-- Nameplate Combos
-- Shows combo points under the current target's nameplate for Rogues and
-- Druids in Cat Form.

local ADDON_NAME, ns = ...

local _, playerClass = UnitClass("player")
if playerClass ~= "ROGUE" and playerClass ~= "DRUID" then
    ns.disabled = true
    return -- nothing to do for other classes
end

local DB_VERSION = 7

ns.DEFAULTS = {
    size = 10,        -- pip height in pixels (width is 2x)
    spacing = 1,      -- gap between pips
    yOffset = -1,     -- vertical offset from the bottom of the health bar
    showEmpty = true, -- show empty pips when you have 0 points
    alpha = 1,        -- overall opacity of the tracker (0.1 - 1)
    colorFull  = { 1.0, 0.85, 0.1 },  -- filled pip
    colorMax   = { 1.0, 0.25, 0.1 },  -- all pips filled
    colorEmpty = { 0.15, 0.15, 0.15 }, -- empty pip
    glow = true,          -- glow behind the pips at max combo points
    glowPulse = true,     -- pulse the glow (false = steady glow)
    pulseSpeed = 1.2,     -- seconds per pulse
    colorGlow  = { 1.0, 0.35, 0.1 },
    minimap = { angle = 220, hide = false },
    -- Finisher damage: an overlay on the health bar, a number right of the
    -- combo points, or both ("OVERLAY", "NUMBER", "BOTH")
    damageDisplay = "OVERLAY",
    overlayColor     = { 1.0, 0.85, 0.1 },  -- overlay and number color
    overlayAlpha = 0.6, -- overlay opacity
    overlayKillColor = { 1.0, 0.15, 0.15 }, -- the finisher would kill
    overlayScale = 1,  -- damage adjustment (armor, talents), 0.5 - 1.5
    overlaySpell = { ROGUE = "EVISCERATE", DRUID = "FEROCIOUS_BITE" },
}

local EMPTY_ALPHA = 0.8

-- Trapezoid pips: A (wide top) and B (wide bottom) alternate and interlock.
-- Must match tools/make_textures.py: 64x32 texture with a 12px slant.
local MEDIA = "Interface\\AddOns\\" .. ADDON_NAME .. "\\media\\"
local TEX_A = MEDIA .. "trapezoid_a"
local TEX_B = MEDIA .. "trapezoid_b"
local GLOW_A = MEDIA .. "glow_a"  -- 2x the pip size, shape centered
local GLOW_B = MEDIA .. "glow_b"
local GLOW_SCALE = 2
local GLOW_STEADY_ALPHA = 0.85
local GLOW_MIN_ALPHA = 0.15       -- lowest point of the pulse
local PIP_ASPECT = 2          -- width / height
local SLANT_RATIO = 12 / 64   -- slant as a fraction of pip width
local CAT_FORM_ID = 1 -- GetShapeshiftFormID() for Cat Form
local PREVIEW_POINTS = 3
ns.PREVIEW_HEALTH = 0.6 -- fake target health in the options preview

local container = CreateFrame("Frame", ADDON_NAME .. "Frame", UIParent)
container:Hide()
local pips = {}

-- Glow layer: sits between the container and the pips.
local glowFrame = CreateFrame("Frame", nil, container)
glowFrame:SetAllPoints()
glowFrame:Hide()
local glows = {}
local pulseTime = 0

glowFrame:SetScript("OnUpdate", function(self, elapsed)
    local db = ns.db
    if not db.glowPulse then return end
    pulseTime = pulseTime + elapsed
    local period = math.max(0.2, db.pulseSpeed)
    local wave = 0.5 - 0.5 * math.cos(2 * math.pi * pulseTime / period)
    self:SetAlpha(GLOW_MIN_ALPHA + (1 - GLOW_MIN_ALPHA) * wave)
end)

-- Damage number, right of the pips. Own frame so it can sit above the pips
-- and glow (levels set in Attach).
local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local damageFrame = CreateFrame("Frame", nil, container)
damageFrame:SetAllPoints()
local damageText = damageFrame:CreateFontString(nil, "OVERLAY")
damageText:SetFont(FONT, 12, "OUTLINE")
damageText:SetPoint("LEFT", container, "RIGHT", 4, 0)

---------------------------------------------------------------------------
-- Saved variables
---------------------------------------------------------------------------

local function CopyDefault(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, val in pairs(v) do t[k] = CopyDefault(val) end
    return t
end

local function ApplyDefaults(target, defaults)
    for k, v in pairs(defaults) do
        if target[k] == nil then
            target[k] = CopyDefault(v)
        elseif type(v) == "table" and type(target[k]) == "table" and #v == 0 then
            ApplyDefaults(target[k], v) -- nested settings tables (not colors)
        end
    end
end

function ns.ResetSettings()
    local minimap = ns.db.minimap -- keep the button where the user put it
    wipe(ns.db)
    ApplyDefaults(ns.db, ns.DEFAULTS)
    ns.db.minimap = minimap
    ns.db.version = DB_VERSION
end

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local function GetPoints()
    if GetComboPoints then
        return GetComboPoints("player", "target") or 0
    end
    return UnitPower("player", Enum.PowerType.ComboPoints) or 0
end

local function GetMaxPoints()
    if UnitPowerMax and Enum and Enum.PowerType and Enum.PowerType.ComboPoints then
        local max = UnitPowerMax("player", Enum.PowerType.ComboPoints)
        if max and max > 0 then return math.min(max, 10) end
    end
    return 5
end

local function UsesComboPoints()
    if playerClass == "ROGUE" then return true end
    return GetShapeshiftFormID() == CAT_FORM_ID
end

local function TargetIsValid()
    return UnitExists("target")
        and UnitCanAttack("player", "target")
        and not UnitIsDead("target")
end

-- The health bar is the visible part of the plate; anchoring to it (instead
-- of the whole plate frame) keeps the pips tight under the bar.
local function GetHealthBar(plate)
    local uf = plate.UnitFrame
    return uf and (uf.healthBar or uf.HealthBar)
end

local function GetPlateAnchor(plate)
    return GetHealthBar(plate) or plate.UnitFrame or plate
end

-- Enemy players may only report health as a percentage, which can't be
-- compared with damage numbers.
-- Returns nil when health is unknown: hidden during combat on newer clients,
-- or only a percentage (enemy players).
local function TargetHealth()
    local health, maxHealth = UnitHealth("target"), UnitHealthMax("target")
    if not (ns.Usable(health) and ns.Usable(maxHealth)) then return nil end
    if UnitIsPlayer("target") and maxHealth == 100 then return nil end
    return health, maxHealth
end

---------------------------------------------------------------------------
-- Pips
---------------------------------------------------------------------------

local function CreatePip(i)
    local pip = CreateFrame("Frame", nil, container)
    pip.fill = pip:CreateTexture(nil, "ARTWORK")
    pip.fill:SetAllPoints()
    pip.fill:SetTexture(i % 2 == 1 and TEX_A or TEX_B)
    pips[i] = pip

    local glow = glowFrame:CreateTexture(nil, "ARTWORK")
    glow:SetTexture(i % 2 == 1 and GLOW_A or GLOW_B)
    glow:SetPoint("CENTER", pip, "CENTER")
    glows[i] = glow
    return pip
end

local function Layout(maxPoints)
    local db = ns.db
    local height = db.size
    local width = height * PIP_ASPECT
    -- Each pip overlaps the previous one by the slant so the edges interlock.
    local step = width * (1 - SLANT_RATIO) + db.spacing
    container:SetSize((maxPoints - 1) * step + width, height)

    for i = 1, math.max(maxPoints, #pips) do
        local pip = pips[i] or CreatePip(i)
        if i <= maxPoints then
            pip:SetSize(width, height)
            pip:ClearAllPoints()
            pip:SetPoint("LEFT", container, "LEFT", (i - 1) * step, 0)
            pip:Show()
            glows[i]:SetSize(width * GLOW_SCALE, height * GLOW_SCALE)
            glows[i]:Show()
        else
            pip:Hide()
            glows[i]:Hide()
        end
    end
end

local function Paint(points, maxPoints)
    local db = ns.db
    local full = (points >= maxPoints) and db.colorMax or db.colorFull
    local empty = db.colorEmpty
    for i = 1, maxPoints do
        if i <= points then
            pips[i].fill:SetVertexColor(full[1], full[2], full[3], 1)
        else
            pips[i].fill:SetVertexColor(empty[1], empty[2], empty[3], EMPTY_ALPHA)
        end
    end
    container:SetAlpha(db.alpha)

    if db.glow and points >= maxPoints then
        local c = db.colorGlow
        for i = 1, maxPoints do
            glows[i]:SetVertexColor(c[1], c[2], c[3], 1)
        end
        if not glowFrame:IsShown() then
            pulseTime = 0 -- start each pulse cycle from dim
            glowFrame:SetAlpha(db.glowPulse and GLOW_MIN_ALPHA or GLOW_STEADY_ALPHA)
            glowFrame:Show()
        elseif not db.glowPulse then
            glowFrame:SetAlpha(GLOW_STEADY_ALPHA)
        end
    else
        glowFrame:Hide()
    end
end

local function Attach(parent, anchor, yOffset)
    container:SetParent(parent)
    container:SetFrameStrata(parent:GetFrameStrata())
    local level = parent:GetFrameLevel() + 10
    container:SetFrameLevel(level)
    glowFrame:SetFrameLevel(level + 1)
    for _, pip in ipairs(pips) do pip:SetFrameLevel(level + 2) end
    damageFrame:SetFrameLevel(level + 3)
    container:ClearAllPoints()
    container:SetPoint("TOP", anchor, "BOTTOM", 0, yOffset)
end

---------------------------------------------------------------------------
-- Damage number: the tracked finisher's estimated damage at the current
-- combo points, shown just right of the pips. "?" means the damage couldn't
-- be worked out (see /ncp debug).
---------------------------------------------------------------------------

local UNKNOWN_COLOR = { 0.6, 0.6, 0.6 }

local function SetDamageText(text, color)
    damageText:SetFont(FONT, math.max(8, math.floor(ns.db.size * 1.2 + 0.5)), "OUTLINE")
    damageText:SetText(text)
    damageText:SetTextColor(color[1], color[2], color[3])
end

-- health may be nil (unknown), in which case it's never shown as lethal.
local function PaintDamage(points, damage, health)
    local db = ns.db
    if points <= 0 then
        damageText:SetText("") -- nothing to finish with
    elseif not damage then
        SetDamageText("?", UNKNOWN_COLOR)
    else
        local lethal = health and health > 0 and damage >= health
        SetDamageText(tostring(math.floor(damage + 0.5)),
            lethal and db.overlayKillColor or db.overlayColor)
    end
end

---------------------------------------------------------------------------
-- Damage overlay on the health bar: the part of the bar the finisher would
-- take off, ending at the current health.
--
-- Target health can be hidden from addons during combat, so nothing here
-- does math with it. The overlay is its own status bar, filled from the
-- right and anchored to the right edge of the health bar's fill. It takes
-- the health bar's own range and is given only the damage; the game works
-- out the size. A clipping frame keeps it inside the health bar.
---------------------------------------------------------------------------

local overlayClip = CreateFrame("Frame", nil, UIParent)
overlayClip:Hide()
if overlayClip.SetClipsChildren then overlayClip:SetClipsChildren(true) end
local overlayBar = CreateFrame("StatusBar", nil, overlayClip)
overlayBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
if overlayBar.SetReverseFill then overlayBar:SetReverseFill(true) end

local function HideOverlay()
    overlayClip:Hide()
end

-- Returns true if the overlay is drawn.
local function DrawOverlay(parent, bar, damage, lethal)
    local db = ns.db
    local fill = bar and bar.GetStatusBarTexture and bar:GetStatusBarTexture()
    local width = bar and bar:GetWidth()
    if not (damage and damage > 0 and fill and width and width > 0) then
        HideOverlay()
        return false
    end
    -- Same parenting and layering as the combo points (see Attach).
    overlayClip:SetParent(parent)
    overlayClip:SetFrameStrata(parent:GetFrameStrata())
    overlayClip:SetFrameLevel(parent:GetFrameLevel() + 10)
    overlayClip:ClearAllPoints()
    overlayClip:SetAllPoints(bar)
    overlayBar:SetFrameLevel(overlayClip:GetFrameLevel() + 1)

    overlayBar:ClearAllPoints()
    overlayBar:SetPoint("TOPRIGHT", fill, "TOPRIGHT")
    overlayBar:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT")
    overlayBar:SetWidth(width)
    overlayBar:SetMinMaxValues(bar:GetMinMaxValues()) -- the health bar's scale
    overlayBar:SetValue(damage)
    local c = lethal and db.overlayKillColor or db.overlayColor
    overlayBar:SetStatusBarColor(c[1], c[2], c[3], db.overlayAlpha)
    overlayClip:Show()
    return true
end

-- Draws the overlay and/or the number, as set in the options. A "?" number
-- is shown even in overlay mode when the damage is unknown, and the number
-- stands in when the overlay can't be drawn, so a problem is never silent.
local function ShowDamage(parent, bar, points, damage, health)
    local mode = ns.db.damageDisplay
    local lethal = damage and health and health > 0 and damage >= health
    local overlayDrawn = false
    if mode ~= "NUMBER" and points > 0 then
        local ok, drawn = pcall(DrawOverlay, parent, bar, damage, lethal)
        overlayDrawn = ok and drawn
        if not ok then HideOverlay() end
    else
        HideOverlay()
    end
    if mode == "OVERLAY" and overlayDrawn then
        damageText:SetText("")
    else
        PaintDamage(points, damage, health)
    end
end

-- The damage display must never break the combo points: run it protected,
-- and report the first error so it can be fixed.
local damageErrorShown = false

local function SafeDamage(fn)
    local ok, err = pcall(fn)
    if not ok then
        SetDamageText("?", UNKNOWN_COLOR)
        HideOverlay()
        if not damageErrorShown then
            damageErrorShown = true
            ns.Print("damage display error (combo points still work): " .. tostring(err))
        end
    end
end

---------------------------------------------------------------------------
-- Update
---------------------------------------------------------------------------

function ns.Update()
    local db = ns.db
    if not db then return end

    local plate = UsesComboPoints() and TargetIsValid()
        and C_NamePlate.GetNamePlateForUnit("target")

    if plate then
        local points = GetPoints()
        if points == 0 and not db.showEmpty then
            container:Hide()
            return
        end
        local maxPoints = GetMaxPoints()
        Layout(maxPoints)
        Attach(plate, GetPlateAnchor(plate), db.yOffset)
        Paint(points, maxPoints)
        SafeDamage(function()
            local damage = ns.EstimateDamage(points)
            -- Health only decides the lethal color; never let it hide the damage.
            local ok, health = pcall(TargetHealth)
            ShowDamage(plate, GetHealthBar(plate), points, damage, ok and health or nil)
        end)
        container:Show()
    elseif ns.previewAnchor and ns.previewAnchor:IsVisible() then
        -- Options panel is open and there's no target: show a sample under a
        -- fake health bar.
        local points = ns.previewPoints or PREVIEW_POINTS
        Layout(5)
        Attach(ns.previewAnchor, ns.previewHealthBar, db.yOffset)
        Paint(points, 5)
        SafeDamage(function()
            -- Fake target: 5 points is lethal, fewer points aren't.
            local damage, full = ns.EstimateDamage(points), ns.EstimateDamage(5)
            local maxHealth = (full or 100) * 1.6
            local health = maxHealth * ns.PREVIEW_HEALTH
            local bar = ns.previewHealthBar
            bar:SetMinMaxValues(0, maxHealth)
            bar:SetValue(health)
            ShowDamage(ns.previewAnchor, bar, points, damage, full and health)
        end)
        container:Show()
    else
        container:Hide()
        HideOverlay()
    end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local events = CreateFrame("Frame")

local function SafeRegister(event, ...)
    -- Some events differ between client versions; ignore unknown ones.
    if select("#", ...) > 0 then
        pcall(events.RegisterUnitEvent, events, event, ...)
    else
        pcall(events.RegisterEvent, events, event)
    end
end

events:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON_NAME then return end
        NameplateCombosDB = NameplateCombosDB or {}
        local db = NameplateCombosDB
        local version = db.version or 1
        if version < 2 then
            -- v2 anchors to the health bar; old offset no longer applies.
            db.yOffset = nil
        end
        -- (v4 adds glow settings, v5 the damage overlay; defaults fill them in)
        if version < 6 then
            -- v6 draws a separate yellow bar instead of tinting the health
            -- bar; the old white, half-transparent defaults don't suit it.
            db.overlayColor, db.overlayAlpha = nil, nil
        end
        if version < 7 then
            -- v7 shows a number instead of a bar: drop the bar's settings.
            db.overlay, db.overlayAlpha, db.overlayHeight = nil, nil, nil
            db.overlayX, db.overlayY = nil, nil
        end
        if version < 3 then
            -- v3 trapezoids interlock; the old square spacing is too wide.
            db.spacing = nil
        end
        ApplyDefaults(db, ns.DEFAULTS)
        db.version = DB_VERSION
        ns.db = db
        events:UnregisterEvent("ADDON_LOADED")
        if ns.OnLoaded then ns.OnLoaded() end
        return
    end

    if event == "NAME_PLATE_UNIT_REMOVED" and arg1 and UnitIsUnit(arg1, "target") then
        -- Our plate is going away; detach so we aren't hidden with it.
        container:SetParent(UIParent)
        container:Hide()
        overlayClip:SetParent(UIParent)
        HideOverlay()
        return
    end

    if event == "SPELLS_CHANGED" or event == "LEARNED_SPELL_IN_TAB" then
        ns.InvalidateDamageCache() -- may have learned a new rank
    end
    -- Read the finisher damage while out of combat, where spell text is
    -- always available; the numbers are kept for use during combat.
    if (event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_REGEN_ENABLED"
            or event == "SPELLS_CHANGED" or event == "LEARNED_SPELL_IN_TAB")
            and not (InCombatLockdown and InCombatLockdown()) then
        pcall(ns.WarmDamageCache)
    end

    ns.Update()
end)

events:RegisterEvent("ADDON_LOADED")
SafeRegister("PLAYER_ENTERING_WORLD")
SafeRegister("PLAYER_TARGET_CHANGED")
SafeRegister("NAME_PLATE_UNIT_ADDED")
SafeRegister("NAME_PLATE_UNIT_REMOVED")
SafeRegister("UNIT_POWER_FREQUENT", "player")
SafeRegister("UNIT_POWER_UPDATE", "player")
SafeRegister("UNIT_MAXPOWER", "player")
SafeRegister("PLAYER_COMBO_POINTS")
SafeRegister("UNIT_FLAGS", "target")
SafeRegister("UNIT_HEALTH", "target")
SafeRegister("UNIT_HEALTH_FREQUENT", "target")
SafeRegister("UNIT_MAXHEALTH", "target")
SafeRegister("SPELLS_CHANGED")
SafeRegister("PLAYER_REGEN_ENABLED")
SafeRegister("LEARNED_SPELL_IN_TAB")
SafeRegister("UPDATE_SHAPESHIFT_FORM")

---------------------------------------------------------------------------
-- /ncp debug: everything the damage number depends on, step by step
---------------------------------------------------------------------------

-- WoW chat can't be copied, so the debug output also goes into a small
-- window with the text selected, ready for Ctrl+C.
local copyFrame

local function ShowCopyWindow(text)
    if not copyFrame then
        copyFrame = CreateFrame("Frame", "NameplateCombosCopyFrame", UIParent,
            BackdropTemplateMixin and "BackdropTemplate" or nil)
        copyFrame:SetSize(560, 320)
        copyFrame:SetPoint("CENTER")
        copyFrame:SetFrameStrata("FULLSCREEN_DIALOG")
        copyFrame:EnableMouse(true)
        copyFrame:SetMovable(true)
        copyFrame:RegisterForDrag("LeftButton")
        copyFrame:SetScript("OnDragStart", copyFrame.StartMoving)
        copyFrame:SetScript("OnDragStop", copyFrame.StopMovingOrSizing)
        if copyFrame.SetBackdrop then
            copyFrame:SetBackdrop({
                bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
                edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
                tile = true, tileSize = 32, edgeSize = 24,
                insets = { left = 6, right = 6, top = 6, bottom = 6 },
            })
        end
        table.insert(UISpecialFrames, copyFrame:GetName()) -- close with Escape

        local title = copyFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOP", 0, -14)
        title:SetText("Nameplate Combos debug - press Ctrl+C to copy, Escape to close")

        local close = CreateFrame("Button", nil, copyFrame, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -4, -4)

        local scroll = CreateFrame("ScrollFrame", nil, copyFrame, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 16, -36)
        scroll:SetPoint("BOTTOMRIGHT", -34, 16)

        local edit = CreateFrame("EditBox", nil, scroll)
        edit:SetMultiLine(true)
        edit:SetAutoFocus(false)
        edit:SetFontObject("ChatFontNormal")
        edit:SetWidth(500)
        edit:SetScript("OnEscapePressed", function() copyFrame:Hide() end)
        scroll:SetScrollChild(edit)
        copyFrame.edit = edit
    end
    copyFrame.edit:SetText(text)
    copyFrame:Show()
    copyFrame.edit:SetFocus()
    copyFrame.edit:HighlightText()
end

-- tostring that copes with values hidden during combat.
local function Show(v)
    if v ~= nil and not ns.Usable(v) then return "(hidden)" end
    return tostring(v)
end

local function CollectDebug(add)
    local db = ns.db

    local GetMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    add("version: " .. tostring(GetMeta and GetMeta(ADDON_NAME, "Version"))
        .. ", client: " .. table.concat({ GetBuildInfo() }, " | "))
    add("class: " .. playerClass .. ", damage adjust: " .. tostring(db.overlayScale))
    add("uses combo points: " .. tostring(UsesComboPoints())
        .. ", combo points: " .. tostring(GetPoints()))
    for _, line in ipairs(ns.DamageDebugLines()) do add(line) end
    add("estimate now: " .. Show(ns.EstimateDamage(GetPoints())))

    if not UnitExists("target") then
        add("target: none")
    else
        add(string.format("target: valid=%s, player=%s, health=%s/%s",
            tostring(TargetIsValid() and true or false), tostring(UnitIsPlayer("target")),
            Show(UnitHealth("target")), Show(UnitHealthMax("target"))))
        add("energy: " .. Show(UnitPower("player", 3)))
        local plate = C_NamePlate.GetNamePlateForUnit("target")
        if plate then
            local bar = GetHealthBar(plate)
            local fill = bar and bar.GetStatusBarTexture and bar:GetStatusBarTexture()
            add(string.format("combo points shown: %s, damage number: \"%s\"",
                tostring(container:IsShown()), tostring(damageText:GetText())))
            add(string.format("show damage as: %s, health bar: %s (width %s), bar fill: %s",
                tostring(db.damageDisplay), tostring(bar ~= nil),
                Show(bar and math.floor(bar:GetWidth() + 0.5)), tostring(fill ~= nil)))
            local fillTex = overlayBar:GetStatusBarTexture()
            add(string.format("overlay shown: %s, overlay part width: %s",
                tostring(overlayClip:IsShown()),
                Show(fillTex and fillTex:GetWidth())))
        else
            add("nameplate: not found (are enemy nameplates on?)")
        end
    end
end

function ns.PrintDebug()
    local out = {}
    local function add(s) out[#out + 1] = s end
    -- Each step guarded, so a failure still reports everything before it.
    local ok, err = pcall(CollectDebug, add)
    if not ok then add("|cffff5555debug stopped with an error:|r " .. tostring(err)) end

    ns.Print("debug")
    for _, line in ipairs(out) do print(line) end
    -- Strip color codes for the copy window.
    local plain = table.concat(out, "\n"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    ShowCopyWindow(plain)
end

---------------------------------------------------------------------------
-- Slash commands: /ncp
---------------------------------------------------------------------------

function ns.Print(msg)
    print("|cffffd200Nameplate Combos:|r " .. msg)
end

SLASH_NAMEPLATECOMBOS1 = "/ncp"
SlashCmdList.NAMEPLATECOMBOS = function(input)
    local db = ns.db
    local cmd, value = strsplit(" ", (input or ""):lower(), 2)
    local num = tonumber(value)

    if cmd == "" then
        ns.ToggleOptions()
        return
    elseif cmd == "size" and num then
        db.size = math.max(4, math.min(30, num))
    elseif cmd == "spacing" and num then
        db.spacing = math.max(0, math.min(10, num))
    elseif cmd == "y" and num then
        db.yOffset = num
    elseif cmd == "empty" then
        db.showEmpty = not db.showEmpty
    elseif cmd == "debug" then
        ns.PrintDebug()
        return
    elseif cmd == "minimap" then
        db.minimap.hide = not db.minimap.hide
        ns.UpdateMinimapButton()
    elseif cmd == "reset" then
        ns.ResetSettings()
        ns.UpdateMinimapButton()
    else
        ns.Print("commands:")
        print("  /ncp                - open options")
        print("  /ncp size <4-30>    - pip size")
        print("  /ncp spacing <0-10> - gap between pips")
        print("  /ncp y <number>     - vertical offset (negative = lower)")
        print("  /ncp empty          - toggle showing empty pips")
        print("  /ncp debug          - show how the damage number is worked out")
        print("  /ncp minimap        - toggle the minimap button")
        print("  /ncp reset          - restore defaults")
        return
    end
    ns.Print("settings updated")
    if ns.RefreshOptions then ns.RefreshOptions() end
    ns.Update()
end
