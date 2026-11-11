-- Nameplate Combos: options panel + minimap button

local ADDON_NAME, ns = ...
if ns.disabled then return end

local ICON = "Interface\\Icons\\Ability_Rogue_Eviscerate"
local panel
local controls = {} -- each has :Refresh()

---------------------------------------------------------------------------
-- Color picker (supports both the new and the old ColorPickerFrame API)
---------------------------------------------------------------------------

local function OpenColorPicker(color, onChange)
    local r, g, b = color[1], color[2], color[3]

    local function apply()
        color[1], color[2], color[3] = ColorPickerFrame:GetColorRGB()
        onChange()
    end
    local function cancel()
        color[1], color[2], color[3] = r, g, b
        onChange()
    end

    if ColorPickerFrame.SetupColorPickerAndShow then
        ColorPickerFrame:SetupColorPickerAndShow({
            r = r, g = g, b = b,
            hasOpacity = false,
            swatchFunc = apply,
            cancelFunc = cancel,
        })
    else
        ColorPickerFrame.hasOpacity = false
        ColorPickerFrame.previousValues = { r, g, b }
        ColorPickerFrame.func = apply
        ColorPickerFrame.cancelFunc = cancel
        ColorPickerFrame:SetColorRGB(r, g, b)
        ColorPickerFrame:Hide()
        ColorPickerFrame:Show()
    end
end

---------------------------------------------------------------------------
-- Widgets
---------------------------------------------------------------------------

local function Changed()
    ns.Update()
end

local function CreateLabel(parent, text, template)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontNormal")
    fs:SetText(text)
    return fs
end

local function CreateColorSwatch(parent, label, key)
    local row = CreateFrame("Button", nil, parent)
    row:SetSize(220, 20)

    local swatch = row:CreateTexture(nil, "ARTWORK")
    swatch:SetSize(14, 14)
    swatch:SetPoint("LEFT", 3, 0)

    local border = row:CreateTexture(nil, "BACKGROUND")
    border:SetSize(18, 18)
    border:SetPoint("CENTER", swatch, "CENTER")
    border:SetColorTexture(1, 1, 1, 0.8)

    local text = CreateLabel(row, label, "GameFontHighlight")
    text:SetPoint("LEFT", swatch, "RIGHT", 8, 0)

    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.08)

    function row:Refresh()
        local c = ns.db[key]
        swatch:SetColorTexture(c[1], c[2], c[3], 1)
    end

    row:SetScript("OnClick", function()
        OpenColorPicker(ns.db[key], function()
            row:Refresh()
            Changed()
        end)
    end)

    table.insert(controls, row)
    return row
end

local function CreateSlider(parent, label, minV, maxV, step, getter, setter, fmt)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(220, 34)

    local title = CreateLabel(holder, label, "GameFontHighlightSmall")
    title:SetPoint("TOPLEFT", 0, 0)

    local valueText = CreateLabel(holder, "", "GameFontNormalSmall")
    valueText:SetPoint("TOPRIGHT", 0, 0)

    local slider = CreateFrame("Slider", nil, holder)
    slider:SetOrientation("HORIZONTAL")
    slider:SetPoint("TOPLEFT", 0, -14)
    slider:SetPoint("TOPRIGHT", 0, -14)
    slider:SetHeight(16)
    slider:SetMinMaxValues(minV, maxV)
    slider:SetValueStep(step)
    if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
    slider:EnableMouseWheel(true)

    local track = slider:CreateTexture(nil, "BACKGROUND")
    track:SetPoint("LEFT", 0, 0)
    track:SetPoint("RIGHT", 0, 0)
    track:SetHeight(6)
    track:SetColorTexture(0, 0, 0, 0.6)

    local trackBorder = slider:CreateTexture(nil, "BORDER")
    trackBorder:SetPoint("TOPLEFT", track, "TOPLEFT", 0, 0)
    trackBorder:SetPoint("BOTTOMRIGHT", track, "BOTTOMRIGHT", 0, 0)
    trackBorder:SetColorTexture(1, 1, 1, 0.1)

    slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")

    local updating = false
    local function show(v)
        valueText:SetText(fmt and fmt(v) or tostring(v))
    end

    slider:SetScript("OnValueChanged", function(_, v)
        v = math.floor(v / step + 0.5) * step
        show(v)
        if not updating then
            setter(v)
            Changed()
        end
    end)
    slider:SetScript("OnMouseWheel", function(self, delta)
        self:SetValue(self:GetValue() + delta * step)
    end)

    function holder:Refresh()
        updating = true
        local v = getter()
        slider:SetValue(v)
        show(v)
        updating = false
    end

    table.insert(controls, holder)
    return holder
end

local function CreateCheckbox(parent, label, getter, setter)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    local text = CreateLabel(cb, label, "GameFontHighlight")
    text:SetPoint("LEFT", cb, "RIGHT", 2, 1)
    -- hide the template's own label if it has one
    if cb.Text then cb.Text:SetText("") end
    if cb.text then cb.text:SetText("") end

    cb:SetScript("OnClick", function(self)
        setter(self:GetChecked() and true or false)
        Changed()
    end)
    function cb:Refresh()
        self:SetChecked(getter())
    end

    table.insert(controls, cb)
    return cb
end

---------------------------------------------------------------------------
-- Panel
---------------------------------------------------------------------------

function ns.RefreshOptions()
    if not panel then return end
    for _, c in ipairs(controls) do c:Refresh() end
end

local function CreatePanel()
    panel = CreateFrame("Frame", "NameplateCombosOptions", UIParent,
        BackdropTemplateMixin and "BackdropTemplate" or nil)
    panel:SetSize(500, 420)
    panel:SetPoint("CENTER")
    panel:SetFrameStrata("DIALOG")
    panel:SetClampedToScreen(true)
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
    panel:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 24,
        insets = { left = 6, right = 6, top = 6, bottom = 6 },
    })
    panel:Hide()
    table.insert(UISpecialFrames, panel:GetName()) -- close with Escape

    local title = CreateLabel(panel, "Nameplate Combos", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -16)

    local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)

    -- Preview strip (used when you have no target). It counts up from 0 to
    -- max and holds there so you can see the max-combo glow.
    local preview = CreateFrame("Frame", nil, panel)
    preview:SetSize(460, 40)
    preview:SetPoint("TOP", 0, -44)
    local pbg = preview:CreateTexture(nil, "BACKGROUND")
    pbg:SetAllPoints()
    pbg:SetColorTexture(0, 0, 0, 0.35)
    ns.previewAnchor = preview

    local STEP_TIME, HOLD_TIME, PREVIEW_MAX = 0.45, 3, 5
    local previewClock = 0
    preview:SetScript("OnUpdate", function(_, elapsed)
        previewClock = (previewClock + elapsed) % (PREVIEW_MAX * STEP_TIME + HOLD_TIME)
        local points = math.min(PREVIEW_MAX, math.floor(previewClock / STEP_TIME) + 1)
        if points ~= ns.previewPoints then
            ns.previewPoints = points
            Changed()
        end
    end)

    local db = function() return ns.db end
    local x, y
    local function column(cx)
        x, y = cx, -100
    end
    local function place(w, h)
        w:SetPoint("TOPLEFT", x, y)
        y = y - h
    end

    -- Left column ------------------------------------------------------
    column(20)
    place(CreateLabel(panel, "Colors"), 20)
    place(CreateColorSwatch(panel, "Combo point", "colorFull"), 22)
    place(CreateColorSwatch(panel, "Max combo points", "colorMax"), 22)
    place(CreateColorSwatch(panel, "Empty", "colorEmpty"), 30)

    place(CreateLabel(panel, "Appearance"), 22)
    place(CreateSlider(panel, "Opacity", 0.1, 1, 0.05,
        function() return db().alpha end,
        function(v) db().alpha = v end,
        function(v) return math.floor(v * 100 + 0.5) .. "%" end), 38)
    place(CreateSlider(panel, "Height", 4, 30, 1,
        function() return db().size end,
        function(v) db().size = v end), 38)
    place(CreateSlider(panel, "Spacing", 0, 10, 1,
        function() return db().spacing end,
        function(v) db().spacing = v end), 38)
    place(CreateSlider(panel, "Vertical offset", -20, 20, 1,
        function() return db().yOffset end,
        function(v) db().yOffset = v end), 40)

    -- Right column -----------------------------------------------------
    column(260)
    place(CreateLabel(panel, "Max combo points"), 22)
    place(CreateCheckbox(panel, "Glow at max combo points",
        function() return db().glow end,
        function(v) db().glow = v end), 26)
    place(CreateCheckbox(panel, "Pulse (off = steady glow)",
        function() return db().glowPulse end,
        function(v) db().glowPulse = v end), 30)
    place(CreateSlider(panel, "Pulse duration", 0.4, 3, 0.1,
        function() return db().pulseSpeed end,
        function(v) db().pulseSpeed = v end,
        function(v) return string.format("%.1fs", v) end), 42)
    place(CreateColorSwatch(panel, "Glow color", "colorGlow"), 34)

    place(CreateLabel(panel, "General"), 22)
    place(CreateCheckbox(panel, "Show empty combo points",
        function() return db().showEmpty end,
        function(v) db().showEmpty = v end), 26)
    place(CreateCheckbox(panel, "Show minimap button",
        function() return not db().minimap.hide end,
        function(v)
            db().minimap.hide = not v
            ns.UpdateMinimapButton()
            if not v then ns.Print("minimap button hidden — type /ncp to open options") end
        end), 26)

    local reset = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    reset:SetSize(120, 22)
    reset:SetPoint("BOTTOM", 0, 16)
    reset:SetText("Reset to defaults")
    reset:SetScript("OnClick", function()
        ns.ResetSettings()
        ns.RefreshOptions()
        ns.UpdateMinimapButton()
        Changed()
    end)

    panel:SetScript("OnShow", function()
        ns.RefreshOptions()
        Changed()
    end)
    panel:SetScript("OnHide", Changed)
end

function ns.ToggleOptions()
    if not panel then CreatePanel() end
    panel:SetShown(not panel:IsShown())
end

---------------------------------------------------------------------------
-- Minimap button
---------------------------------------------------------------------------

local button

local function PositionButton()
    local angle = math.rad(ns.db.minimap.angle or 220)
    local radius = (Minimap:GetWidth() / 2) + 10
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function OnDragUpdate()
    local mx, my = Minimap:GetCenter()
    local cx, cy = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    cx, cy = cx / scale, cy / scale
    ns.db.minimap.angle = math.deg(math.atan2(cy - my, cx - mx))
    PositionButton()
end

local function CreateMinimapButton()
    button = CreateFrame("Button", "NameplateCombosMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local bg = button:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetSize(20, 20)
    bg:SetPoint("TOPLEFT", 7, -5)

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(ICON)
    icon:SetSize(17, 17)
    icon:SetPoint("TOPLEFT", 7, -6)
    icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")

    button:SetScript("OnClick", function() ns.ToggleOptions() end)
    button:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", OnDragUpdate) end)
    button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Nameplate Combos")
        GameTooltip:AddLine("Click to open options", 1, 1, 1)
        GameTooltip:AddLine("Drag to move", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

function ns.UpdateMinimapButton()
    if not ns.db then return end
    if not button then CreateMinimapButton() end
    PositionButton()
    button:SetShown(not ns.db.minimap.hide)
end

-- Called by NameplateCombos.lua once saved variables are ready.
function ns.OnLoaded()
    ns.UpdateMinimapButton()
end
