local _G = rawget(_G, "GLOBAL") or _G
local Widget = require("widgets/widget")
local Image = require("widgets/image")
local Text = require("widgets/text")
local ImageButton = require("widgets/imagebutton")
local Logger = require("wx_logger")

-- Always use Open Sans for ultra-legible, modern UI typography
local DEFAULTFONT = _G.DEFAULTFONT or "opensans"
local ANCHOR_RIGHT = _G.ANCHOR_RIGHT
local ANCHOR_MIDDLE = _G.ANCHOR_MIDDLE
local ANCHOR_LEFT = _G.ANCHOR_LEFT

local RADIUS_VALUES = { 10, 15, 20, 25, 30 }

local function GetCompanion(player)
    if player and player.wx_companion and player.wx_companion:IsValid() then
        return player.wx_companion
    end
    return nil
end

local function UpdateOverlay(player, enabled, radius)
    if not player or not player:IsValid() or not player.entity then return end
    if enabled then
        if not player.harvest_range_ring or not player.harvest_range_ring:IsValid() then
            local ring = SpawnPrefab and SpawnPrefab("harvest_range_ring")
            if ring then
                ring.entity:SetParent(player.entity)
                ring.Transform:SetPosition(0, 0, 0)
                player.harvest_range_ring = ring
            end
        end
        if player.harvest_range_ring and player.harvest_range_ring:IsValid() then
            player.harvest_range_ring:Show()
            if player.harvest_range_ring.SetRadius then player.harvest_range_ring:SetRadius(radius) end
        end
    elseif player.harvest_range_ring and player.harvest_range_ring:IsValid() then
        player.harvest_range_ring:Hide()
    end
end

-- Helper: Creates a card container with warm antique brass border and dark walnut backing
local function CreateBorderedCard(parent, x, y, w, h, bg_tint, border_tint)
    local card_group = parent:AddChild(Widget("card"))
    card_group:SetPosition(x, y, 0)

    -- Brass border
    local border = card_group:AddChild(Image("images/global.xml", "square.tex"))
    if border.ScaleToSize then border:ScaleToSize(w, h) end
    local bt = border_tint or {0.55, 0.43, 0.28, 0.95}
    border:SetTint(bt[1], bt[2], bt[3], bt[4])

    -- Dark walnut inner fill
    local inner = card_group:AddChild(Image("images/global.xml", "square.tex"))
    if inner.ScaleToSize then inner:ScaleToSize(w - 2, h - 2) end
    local bg = bg_tint or {0.11, 0.09, 0.07, 0.97}
    inner:SetTint(bg[1], bg[2], bg[3], bg[4])

    return card_group
end

-- Helper: Creates a modern card button with brass outline and hover glow
local function CreateCardButton(parent, x, y, w, h, text, font_size, onclick)
    local btn_group = parent:AddChild(Widget("card_btn_group"))
    btn_group:SetPosition(x, y, 0)

    local border = btn_group:AddChild(Image("images/global.xml", "square.tex"))
    if border.ScaleToSize then border:ScaleToSize(w, h) end
    border:SetTint(0.55, 0.43, 0.28, 0.92)

    local btn = btn_group:AddChild(ImageButton("images/global.xml", "square.tex", "square.tex", "square.tex"))
    if btn.image and btn.image.ScaleToSize then
        btn.image:ScaleToSize(w - 2, h - 2)
        btn.image:SetTint(0.20, 0.16, 0.12, 0.96)
    end

    local label = btn:AddChild(Text(DEFAULTFONT, font_size or 18, text))
    label:SetPosition(0, 1, 0)
    label:SetColour(1.0, 0.96, 0.92, 1)

    btn.OnGainFocus = function()
        TheFrontEnd:GetSound():PlaySound("dontstarve/HUD/click_mouseover")
        if btn.image then btn.image:SetTint(0.32, 0.25, 0.18, 1) end
        border:SetTint(0.95, 0.78, 0.38, 1)
        label:SetColour(1.0, 0.92, 0.48, 1)
    end

    btn.OnLoseFocus = function()
        if btn.image then btn.image:SetTint(0.20, 0.16, 0.12, 0.96) end
        border:SetTint(0.55, 0.43, 0.28, 0.92)
        label:SetColour(1.0, 0.96, 0.92, 1)
    end

    btn:SetOnClick(onclick)
    return btn
end

-- Helper: Stepper minus/plus card button with large symbol
local function CreateStepperBtn(parent, x, y, symbol, onclick)
    local btn_group = parent:AddChild(Widget("stepper_btn_group"))
    btn_group:SetPosition(x, y, 0)

    local border = btn_group:AddChild(Image("images/global.xml", "square.tex"))
    if border.ScaleToSize then border:ScaleToSize(38, 38) end
    border:SetTint(0.55, 0.43, 0.28, 0.92)

    local btn = btn_group:AddChild(ImageButton("images/global.xml", "square.tex", "square.tex", "square.tex"))
    if btn.image and btn.image.ScaleToSize then
        btn.image:ScaleToSize(36, 36)
        btn.image:SetTint(0.22, 0.17, 0.13, 0.96)
    end

    local label = btn:AddChild(Text(DEFAULTFONT, 28, symbol))
    label:SetPosition(0, 1, 0)
    label:SetColour(1.0, 0.90, 0.42, 1)

    btn.OnGainFocus = function()
        TheFrontEnd:GetSound():PlaySound("dontstarve/HUD/click_mouseover")
        if btn.image then btn.image:SetTint(0.32, 0.25, 0.18, 1) end
        border:SetTint(0.95, 0.78, 0.38, 1)
        label:SetColour(1.0, 0.98, 0.60, 1)
    end
    btn.OnLoseFocus = function()
        if btn.image then btn.image:SetTint(0.22, 0.17, 0.13, 0.96) end
        border:SetTint(0.55, 0.43, 0.28, 0.92)
        label:SetColour(1.0, 0.90, 0.42, 1)
    end

    btn:SetOnClick(onclick)
    return btn
end

-- Helper: Checkbox matching FigCraft mockup (square brass frame with gold check indicator)
local function CreateCheckbox(parent, x, y, label_text, initial_state, on_toggle, btn_x, label_w, font_size, label_colour)
    local row = parent:AddChild(Widget("checkbox_row"))
    row:SetPosition(x, y, 0)

    local bx = btn_x or -155
    local lw = label_w or 290
    local fsize = font_size or 22
    local fcol = label_colour or {1.0, 0.98, 0.94, 1}
    local box_size = (fsize >= 21) and 28 or 24
    local border_thickness = 4

    -- Checkbox Button
    local box_group = row:AddChild(Widget("box_group"))
    box_group:SetPosition(bx, 0, 0)

    -- Outer brass border frame (always clearly visible against dark card)
    local box_border = box_group:AddChild(Image("images/global.xml", "square.tex"))
    if box_border.ScaleToSize then box_border:ScaleToSize(box_size + border_thickness, box_size + border_thickness) end
    box_border:SetTint(0.85, 0.70, 0.48, 1)

    -- Inset well (distinctly lighter than card background)
    local btn = box_group:AddChild(ImageButton("images/global.xml", "square.tex", "square.tex", "square.tex"))
    if btn.image and btn.image.ScaleToSize then
        btn.image:ScaleToSize(box_size, box_size)
        btn.image:SetTint(0.32, 0.26, 0.20, 1)
    end

    -- Bright gold inner square indicator
    local indicator = btn:AddChild(Image("images/global.xml", "square.tex"))
    local ind_size = box_size - 8
    if indicator.ScaleToSize then indicator:ScaleToSize(ind_size, ind_size) end
    indicator:SetTint(1.0, 0.86, 0.35, 1)

    -- Centered dark 'x' mark on top of the gold square
    local mark = btn:AddChild(Text(DEFAULTFONT, box_size - 6, "x"))
    mark:SetPosition(0, 1, 0)
    mark:SetColour(0.12, 0.09, 0.06, 1)

    local state = initial_state
    local function UpdateVisual()
        if state then
            indicator:Show()
            mark:Show()
            if btn.image then btn.image:SetTint(0.30, 0.24, 0.17, 1) end
            box_border:SetTint(1.0, 0.88, 0.42, 1)
        else
            indicator:Hide()
            mark:Hide()
            if btn.image then btn.image:SetTint(0.32, 0.26, 0.20, 1) end
            box_border:SetTint(0.85, 0.70, 0.48, 1)
        end
    end
    UpdateVisual()

    local function Toggle()
        state = not state
        UpdateVisual()
        if on_toggle then on_toggle(state) end
    end

    btn:SetOnClick(Toggle)

    local function OnHover()
        TheFrontEnd:GetSound():PlaySound("dontstarve/HUD/click_mouseover")
        if not state then
            box_border:SetTint(0.95, 0.82, 0.52, 1)
            if btn.image then btn.image:SetTint(0.40, 0.33, 0.25, 1) end
        end
    end

    local function OnLoseHover()
        if not state then
            box_border:SetTint(0.85, 0.70, 0.48, 1)
            if btn.image then btn.image:SetTint(0.32, 0.26, 0.20, 1) end
        end
    end

    btn.OnGainFocus = OnHover
    btn.OnLoseFocus = OnLoseHover

    -- Clickable Label in large, highly legible Open Sans
    local label_btn = row:AddChild(ImageButton("images/ui.xml", "blank.tex", "blank.tex", "blank.tex"))
    local label_center_x = bx + (box_size / 2) + 10 + (lw / 2)
    label_btn:SetPosition(label_center_x, 0, 0)

    local label = label_btn:AddChild(Text(DEFAULTFONT, fsize, label_text))
    if label.SetRegionSize then label:SetRegionSize(lw, 34) end
    label:SetHAlign(ANCHOR_LEFT)
    label:SetColour(fcol[1], fcol[2], fcol[3], fcol[4])

    label_btn:SetOnClick(Toggle)
    label_btn.OnGainFocus = OnHover
    label_btn.OnLoseFocus = OnLoseHover

    row.SetChecked = function(_, val) state = val UpdateVisual() end
    row.IsChecked = function(_) return state end
    row.label = label
    row.btn = btn
    return row
end

local HarvesterUI = Class(Widget, function(self, owner, default_radius)
    Widget._ctor(self, "HarvesterUI")
    self.owner = owner
    local comp = GetCompanion(owner)

    local radius = (comp and comp.harvest_radius) or default_radius or 15
    self.radius_index = 2
    for i, v in ipairs(RADIUS_VALUES) do
        if v == radius then self.radius_index = i break end
    end

    self.show_overlay = true

    -- Positioned on the right side of the screen with comfortable margin
    self:SetHAnchor(ANCHOR_RIGHT)
    self:SetVAnchor(ANCHOR_MIDDLE)
    self:SetPosition(-230, 0, 0)

    -- 1. Outer Frame: 410px wide x 670px tall with brass border and warm dark walnut backing
    CreateBorderedCard(self, 0, 0, 410, 670, {0.12, 0.10, 0.08, 0.98}, {0.55, 0.43, 0.28, 0.96})

    -- 2. Header Banner (y = 295, height = 54)
    CreateBorderedCard(self, 0, 295, 406, 54, {0.20, 0.15, 0.11, 1}, {0.50, 0.39, 0.25, 0.92})

    self.title = self:AddChild(Text(DEFAULTFONT, 28, "WX-78 HARVESTER"))
    self.title:SetPosition(-25, 295, 0)
    self.title:SetColour(1.0, 0.88, 0.38, 1)

    -- Close Button [X] (34x34 card button, 20px font)
    local close_btn = CreateCardButton(self, 168, 295, 34, 34, "X", 20, function() self:Hide() end)

    -- 3. Section 1: Radius Stepper Card (y = 235, height = 50)
    CreateBorderedCard(self, 0, 235, 380, 50, {0.10, 0.08, 0.06, 0.95}, {0.42, 0.32, 0.20, 0.88})

    self.radius_label = self:AddChild(Text(DEFAULTFONT, 26, string.format("Radius: %dm", RADIUS_VALUES[self.radius_index])))
    self.radius_label:SetPosition(0, 235, 0)
    self.radius_label:SetColour(1.0, 0.92, 0.48, 1)

    local function ApplyRadius()
        local current_r = RADIUS_VALUES[self.radius_index]
        self.radius_label:SetString(string.format("Radius: %dm", current_r))
        local comp = GetCompanion(self.owner)
        if comp then comp.harvest_radius = current_r end
        if self.show_overlay then UpdateOverlay(self.owner, true, current_r) end
        Logger.Info("UI", "Radius set to %dm", current_r)
    end

    CreateStepperBtn(self, -148, 235, "-", function()
        if self.radius_index > 1 then self.radius_index = self.radius_index - 1 ApplyRadius() end
    end)

    CreateStepperBtn(self, 148, 235, "+", function()
        if self.radius_index < #RADIUS_VALUES then self.radius_index = self.radius_index + 1 ApplyRadius() end
    end)

    -- 4. Section 2: Behavior Master Toggles Card (y = 105, height = 170)
    CreateBorderedCard(self, 0, 105, 380, 170, {0.10, 0.08, 0.06, 0.95}, {0.42, 0.32, 0.20, 0.88})

    CreateCheckbox(self, 0, 162, "Auto-Harvesting Protocol", not comp or comp.harvest_enabled ~= false, function(checked)
        local comp = GetCompanion(self.owner)
        if comp then comp.harvest_enabled = checked end
    end, -158, 290, 22, {1.0, 0.98, 0.94, 1})

    CreateCheckbox(self, 0, 124, "Follow Player (3m Tether)", not comp or comp.follow_player ~= false, function(checked)
        local comp = GetCompanion(self.owner)
        if comp then comp.follow_player = checked end
    end, -158, 290, 22, {1.0, 0.98, 0.94, 1})

    CreateCheckbox(self, 0, 86, "Visual Boundary Ring", true, function(checked)
        self.show_overlay = checked
        UpdateOverlay(self.owner, checked, RADIUS_VALUES[self.radius_index])
    end, -158, 290, 22, {1.0, 0.98, 0.94, 1})

    local storage_row = CreateCheckbox(self, 0, 48, "Show Storage (1x15 + Equip)", false, function(checked)
        local c = GetCompanion(self.owner)
        if c and c.ToggleStorage then c:ToggleStorage(self.owner) end
    end, -158, 290, 22, {1.0, 0.88, 0.42, 1})

    if comp then
        comp.ui_storage_checkbox = storage_row
        if comp.components.container and comp.components.container:IsOpen() then
            storage_row:SetChecked(true)
        end
    end

    -- 5. Section 3: Target Directives Card (y = -125, height = 260)
    CreateBorderedCard(self, 0, -125, 380, 260, {0.10, 0.08, 0.06, 0.95}, {0.42, 0.32, 0.20, 0.88})

    local filter_heading = self:AddChild(Text(DEFAULTFONT, 20, "TARGET RESOURCE DIRECTIVES"))
    filter_heading:SetPosition(0, -18, 0)
    filter_heading:SetColour(1.0, 0.88, 0.40, 1)

    local function CreateCategoryGroup(header_bx, y_start, category_name, items, parent_colour)
        local child_rows = {}

        local function AreAnyChildrenChecked()
            for _, c in ipairs(child_rows) do
                if c.row:IsChecked() then return true end
            end
            return false
        end

        local function SyncToCompanion(key, val)
            local current_comp = GetCompanion(self.owner)
            if current_comp then
                if not current_comp.target_items then current_comp.target_items = {} end
                current_comp.target_items[key] = val
            end
        end

        -- Parent Category Checkbox (font size 21)
        local pcol = parent_colour or {1.0, 0.90, 0.45, 1}
        local parent_row = CreateCheckbox(self, 0, y_start, category_name, false, function(checked)
            for _, c in ipairs(child_rows) do
                c.row:SetChecked(checked)
                SyncToCompanion(c.key, checked)
            end
        end, header_bx, 130, 21, pcol)

        -- Child items (step 29px, font size 20)
        local child_step_y = 29
        for i, item in ipairs(items) do
            local cy = y_start - (i * child_step_y)
            local saved = comp and comp.target_items and comp.target_items[item.key]
            local row = CreateCheckbox(self, 0, cy, item.label, saved ~= nil and saved or item.default, function(checked)
                SyncToCompanion(item.key, checked)
                parent_row:SetChecked(AreAnyChildrenChecked())
            end, header_bx + 14, 120, 22, {1.0, 1.0, 1.0, 1})

            table.insert(child_rows, { row = row, key = item.key })
        end

        parent_row:SetChecked(AreAnyChildrenChecked())

        return {
            parent_row = parent_row,
            children = child_rows,
            SetAll = function(val)
                parent_row:SetChecked(val)
                for _, c in ipairs(child_rows) do
                    c.row:SetChecked(val)
                    SyncToCompanion(c.key, val)
                end
            end
        }
    end

    -- Left Column: Fuel then Food, grouped by use as in the game's crafting recipes
    local group_fuel = CreateCategoryGroup(-158, -48, "Fuel (All)", {
        { key = "twigs", label = "Twigs", default = true },
        { key = "cutgrass", label = "Cut Grass", default = true },
        { key = "log", label = "Wood Logs", default = true },
    }, {1.0, 0.90, 0.45, 1})

    local group_food = CreateCategoryGroup(-158, -150, "Food (All)", {
        { key = "seeds", label = "Seeds", default = true },
        { key = "berries", label = "Berries", default = true },
        { key = "carrot", label = "Carrots", default = false },
    }, {1.0, 0.90, 0.45, 1})

    -- Right Column: Minerals (y_start = -48)
    local group_minerals = CreateCategoryGroup(18, -48, "Minerals (All)", {
        { key = "flint", label = "Flint", default = false },
        { key = "rocks", label = "Rocks", default = false },
        { key = "goldnugget", label = "Gold", default = false },
        { key = "nitre", label = "Nitre", default = false },
        { key = "misc", label = "Other Loot", default = true },
    }, {0.95, 0.95, 0.95, 1})

    -- 6. Section 4: Quick Presets Toolbar (y = -295, height = 50)
    CreateBorderedCard(self, 0, -295, 380, 50, {0.10, 0.08, 0.06, 0.95}, {0.42, 0.32, 0.20, 0.88})

    CreateCardButton(self, -132, -295, 82, 36, "Flora", 19, function()
        group_fuel.SetAll(true)
        group_food.SetAll(true)
        group_minerals.SetAll(false)
    end)

    CreateCardButton(self, -44, -295, 82, 36, "Mining", 19, function()
        group_fuel.SetAll(false)
        group_food.SetAll(false)
        group_minerals.SetAll(true)
    end)

    CreateCardButton(self, 44, -295, 82, 36, "All", 19, function()
        group_fuel.SetAll(true)
        group_food.SetAll(true)
        group_minerals.SetAll(true)
    end)

    CreateCardButton(self, 132, -295, 82, 36, "Clear", 19, function()
        group_fuel.SetAll(false)
        group_food.SetAll(false)
        group_minerals.SetAll(false)
    end)

    -- Defer initial overlay to ensure player is ready
    if self.owner then
        self.owner:DoTaskInTime(0, function()
            UpdateOverlay(self.owner, true, RADIUS_VALUES[self.radius_index])
        end)
    end
end)

return HarvesterUI
