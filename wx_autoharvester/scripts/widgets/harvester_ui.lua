local _G = rawget(_G, "GLOBAL") or _G
local Widget = require("widgets/widget")
local Image = require("widgets/image")
local Text = require("widgets/text")
local ImageButton = require("widgets/imagebutton")
local Logger = require("wx_logger")
local DEFAULT_TARGET_PRIORITY = require("target_priority")
local TARGET_CATEGORIES = require("target_categories")

-- Always use Open Sans for ultra-legible, modern UI typography
local DEFAULTFONT = _G.DEFAULTFONT or "opensans"
local ANCHOR_RIGHT = _G.ANCHOR_RIGHT
local ANCHOR_MIDDLE = _G.ANCHOR_MIDDLE
local ANCHOR_LEFT = _G.ANCHOR_LEFT
local ANCHOR_TOP = _G.ANCHOR_TOP
local ANCHOR_BOTTOM = _G.ANCHOR_BOTTOM

local RADIUS_VALUES = { 10, 15, 20, 25, 30 }
local FREE_ROAM_VALUES = { 20, 30, 40, 50, 60, 80, 100, 120 }

local function SetGamePaused(paused)
    if _G.SetPause then _G.SetPause(paused, "harvester_ui") end
end
local function FindRobotEgg(player)
    if player and player:IsValid() and player.components.inventory then
        for _, item in pairs(player.components.inventory.itemslots or {}) do
            if item and item:IsValid() and item:HasTag("robot_egg") then return item end
        end
        local overflow = player.components.inventory.overflow
        if overflow and overflow.components.container then
            for _, item in pairs(overflow.components.container.slots or {}) do
                if item and item:IsValid() and item:HasTag("robot_egg") then return item end
            end
        end
        local active = player.components.inventory.activeitem
        if active and active:IsValid() and active:HasTag("robot_egg") then return active end
    end
    local x, y, z = 0, 0, 0
    if player and player.Transform then x, y, z = player.Transform:GetWorldPosition() end
    local TheSim = _G.TheSim
    local eggs = TheSim and TheSim:FindEntities(x, y, z, 9999, {"robot_egg"})
    return eggs and eggs[1] or nil
end

local function GetCompanion(player)
    if player and player.wx_companion and player.wx_companion:IsValid() then
        return player.wx_companion
    end
    if player and player.wx_egg and player.wx_egg:IsValid() then
        return player.wx_egg
    end
    local egg = FindRobotEgg(player)
    if egg and egg:IsValid() then
        return egg
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

    -- Centered on screen, slightly smaller
    self:SetHAnchor(ANCHOR_MIDDLE)
    self:SetVAnchor(ANCHOR_MIDDLE)
    self:SetScale(1.05, 1.05, 1.05)
    self:SetPosition(0, 0, 0)

    -- 1. Outer Frame: 1200px wide x 800px tall (much wider for 3-column priority grid)
    CreateBorderedCard(self, 0, 0, 1200, 800, {0.12, 0.10, 0.08, 0.98}, {0.55, 0.43, 0.28, 0.96})

    -- 2. Header Banner
    CreateBorderedCard(self, 0, 360, 1180, 54, {0.20, 0.15, 0.11, 1}, {0.50, 0.39, 0.25, 0.92})

    self.title = self:AddChild(Text(DEFAULTFONT, 28, "WX-78 HARVESTER CONTROL"))
    self.title:SetPosition(0, 360, 0)
    self.title:SetColour(1.0, 0.88, 0.38, 1)

    -- Close Button [X]
    local close_btn = CreateCardButton(self, 565, 360, 36, 36, "X", 20, function() self:Hide() end)

    -- 3. Section 1: Radius Stepper Card
    CreateBorderedCard(self, 0, 305, 1140, 64, {0.10, 0.08, 0.06, 0.95}, {0.42, 0.32, 0.20, 0.88})

    self.radius_label = self:AddChild(Text(DEFAULTFONT, 24, string.format("Radius: %dm", RADIUS_VALUES[self.radius_index])))
    self.radius_label:SetPosition(-350, 305, 0)
    self.radius_label:SetColour(1.0, 0.92, 0.48, 1)

    local function ApplyRadius()
        local current_r = RADIUS_VALUES[self.radius_index]
        self.radius_label:SetString(string.format("Radius: %dm", current_r))
        local comp = GetCompanion(self.owner)
        if comp then
            comp.harvest_radius = current_r
            if comp.companion_data then comp.companion_data.harvest_radius = current_r end
        end
        if self.show_overlay then UpdateOverlay(self.owner, true, current_r) end
        Logger.Info("UI", "Radius set to %dm", current_r)
    end

    CreateStepperBtn(self, -540, 305, "-", function()
        if self.radius_index > 1 then self.radius_index = self.radius_index - 1 ApplyRadius() end
    end)

    CreateStepperBtn(self, -170, 305, "+", function()
        if self.radius_index < #RADIUS_VALUES then self.radius_index = self.radius_index + 1 ApplyRadius() end
    end)

    -- Free-roam (untethered) radius stepper
    local roam = (comp and (comp.untethered_radius or (comp.companion_data and comp.companion_data.untethered_radius))) or 60
    self.roam_index = 5
    for i, v in ipairs(FREE_ROAM_VALUES) do
        if v == roam then self.roam_index = i break end
    end

    self.roam_label = self:AddChild(Text(DEFAULTFONT, 24, string.format("Free Roam: %dm", FREE_ROAM_VALUES[self.roam_index])))
    self.roam_label:SetPosition(350, 305, 0)
    self.roam_label:SetColour(0.95, 0.75, 0.40, 1)

    local function ApplyRoam()
        local current_r = FREE_ROAM_VALUES[self.roam_index]
        self.roam_label:SetString(string.format("Free Roam: %dm", current_r))
        local c = GetCompanion(self.owner)
        if c then
            c.untethered_radius = current_r
            if c.companion_data then c.companion_data.untethered_radius = current_r end
        end
        Logger.Info("UI", "Free roam radius set to %dm", current_r)
    end

    CreateStepperBtn(self, 170, 305, "-", function()
        if self.roam_index > 1 then self.roam_index = self.roam_index - 1 ApplyRoam() end
    end)

    CreateStepperBtn(self, 540, 305, "+", function()
        if self.roam_index < #FREE_ROAM_VALUES then self.roam_index = self.roam_index + 1 ApplyRoam() end
    end)

    -- 4. Section 2: Behavior Master Toggles Card - MORE SPACED OUT
    CreateBorderedCard(self, 0, 135, 1140, 340, {0.10, 0.08, 0.06, 0.95}, {0.42, 0.32, 0.20, 0.88})

    local behavior_rows = {}
    local d_init = comp and comp.companion_data

    behavior_rows.harvest = CreateCheckbox(self, 0, 254, "Auto-Harvesting Protocol", not comp or (comp.harvest_enabled ~= false and (not d_init or d_init.harvest_enabled ~= false)), function(checked)
        local comp = GetCompanion(self.owner)
        if comp then
            comp.harvest_enabled = checked
            if comp.companion_data then comp.companion_data.harvest_enabled = checked end
        end
    end, -490, 920, 22, {1.0, 0.98, 0.94, 1})

    local storage_row = CreateCheckbox(self, 0, 99, "Show Storage (1x15 + Equip)", false, function(checked)
        local c = GetCompanion(self.owner)
        if c and c.ToggleStorage then c:ToggleStorage(self.owner) end
    end, -490, 920, 22, {1.0, 0.88, 0.42, 1})

    -- Harvest sub-items
    behavior_rows.harvest_resources = CreateCheckbox(self, 0, 161, "  Harvest: Resources", not comp or (comp.target_items and comp.target_items.harvest_resources ~= false), function(checked)
        local c = GetCompanion(self.owner)
        if c then
            c.target_items = c.target_items or {}
            c.target_items.harvest_resources = checked
            if c.companion_data then
                c.companion_data.target_items = c.companion_data.target_items or {}
                c.companion_data.target_items.harvest_resources = checked
            end
        end
    end, -490, 920, 20, {0.95, 0.92, 0.88, 1})

    behavior_rows.harvest_food = CreateCheckbox(self, 0, 130 + 0, "  Harvest: Food", not comp or (comp.target_items and comp.target_items.harvest_food ~= false), function(checked)
        local c = GetCompanion(self.owner)
        if c then
            c.target_items = c.target_items or {}
            c.target_items.harvest_food = checked
            if c.companion_data then
                c.companion_data.target_items = c.companion_data.target_items or {}
                c.companion_data.target_items.harvest_food = checked
            end
        end
    end, -490, 920, 20, {0.95, 0.92, 0.88, 1})

    -- Auto-Pickup toggle
    behavior_rows.pickup = CreateCheckbox(self, 0, 6, "Auto-Pickup Items (ground loot)", not comp or (comp.pickup_enabled ~= false and (not d_init or d_init.pickup_enabled ~= false)), function(checked)
        local c = GetCompanion(self.owner)
        if c then
            c.pickup_enabled = checked
            if c.companion_data then c.companion_data.pickup_enabled = checked end
        end
    end, -490, 920, 22, {1.0, 0.98, 0.94, 1})

    -- Prioritize pickup over harvest
    behavior_rows.prioritize = CreateCheckbox(self, 0, -25, "Prioritize Pickup Over Harvest", comp and (comp.prioritize_pickup == true or (d_init and d_init.prioritize_pickup == true)), function(checked)
        local c = GetCompanion(self.owner)
        if c then
            c.prioritize_pickup = checked
            if c.companion_data then c.companion_data.prioritize_pickup = checked end
        end
    end, -490, 920, 22, {0.95, 0.88, 0.42, 1})

    local is_egg_init = comp and (comp:HasTag("robot_egg") or comp:HasTag("wx_companion_egg"))
    behavior_rows.egg = CreateCheckbox(self, 0, 37, "Egg Form (Pack into Robot Seed in Inventory)", is_egg_init == true, function(checked)
        local c = GetCompanion(self.owner)
        if checked then
            if c and c:IsValid() and c.TransformToEgg then
                local egg = c:TransformToEgg(self.owner)
                if egg and egg.components.container and behavior_rows.storage and behavior_rows.storage:IsChecked() then
                    egg.components.container:Open(self.owner)
                end
            end
        else
            if c and c:IsValid() and (c.Hatch or c.Deploy) then
                local hatchfn = c.Deploy or c.Hatch
                local hatched = hatchfn(c, self.owner)
                if hatched and hatched.components.container and behavior_rows.storage and behavior_rows.storage:IsChecked() then
                    hatched.components.container:Open(self.owner)
                end
            end
        end
        if self.RefreshUI then self:RefreshUI() end
    end, -490, 920, 22, {0.62, 0.78, 0.92, 1})

    behavior_rows.storage = storage_row

    if comp then
        comp.ui_storage_checkbox = storage_row
        if comp.components.container and comp.components.container:IsOpen() then
            storage_row:SetChecked(true)
        end
    end

    -- 5. Section 3: Unified filter + priority list (checkbox + rank + label + arrows per row)
    CreateBorderedCard(self, 0, -165, 1160, 320, {0.10, 0.08, 0.06, 0.95}, {0.42, 0.32, 0.20, 0.88})

    local filter_heading = self:AddChild(Text(DEFAULTFONT, 18, "PICKUP FILTERS  ·  tick to enable  ·  ▲ / ▼ to reorder priority"))
    filter_heading:SetPosition(0, -16, 0)
    filter_heading:SetColour(1.0, 0.88, 0.40, 1)

    local priority_order = comp and comp.target_priority
    if not priority_order then
        priority_order = {}
        for _, key in ipairs(DEFAULT_TARGET_PRIORITY) do priority_order[#priority_order + 1] = key end
        if comp then comp.target_priority = priority_order end
    end

    -- Flat lookup: key -> label, key -> default
    local priority_text, priority_default = {}, {}
    for _, category in ipairs(TARGET_CATEGORIES) do
        for _, item in ipairs(category.items) do
            priority_text[item.key] = item.label
            priority_default[item.key] = item.default
        end
    end

    -- Four semantic columns: pickups | harvest & food | mining | chopping
    local COLUMN_OF = {}
    local function AssignColumn(keys, col)
        for _, k in ipairs(keys) do COLUMN_OF[k] = col end
    end
    AssignColumn({ "silk", "spidergland", "houndstooth", "pigskin", "feathers",
        "beefalowool", "monsterparts", "manure", "gear", "traps", "misc" }, 1)
    AssignColumn({ "flint", "rocks", "goldnugget", "nitre", "marble", "gems", "moonrock" }, 3)
    AssignColumn({ "log", "livinglog", "charcoal", "woodcraft", "pinecone" }, 4)

    local COLUMN_X = { -435, -145, 145, 435 }
    local COLUMN_NAMES = { "PICKUPS", "HARVEST & FOOD", "MINING", "CHOPPING" }
    local ROW_HEIGHT = 26
    local grid_root = self:AddChild(Widget("priority_grid"))
    grid_root:SetPosition(0, -50, 0)

    local function SyncItem(key, val)
        local c = GetCompanion(self.owner)
        if c then
            c.target_items = c.target_items or {}
            c.target_items[key] = val
            if c.companion_data then
                c.companion_data.target_items = c.companion_data.target_items or {}
                c.companion_data.target_items[key] = val
            end
        end
    end

    local priority_row_widgets = {}

    local function LayoutPriorityList()
        local col_rows = { 0, 0, 0, 0 }
        for rank, key in ipairs(priority_order) do
            local w = priority_row_widgets[key]
            if w then
                local col = COLUMN_OF[key] or 2
                local n = col_rows[col]
                col_rows[col] = n + 1
                w.row:SetPosition(COLUMN_X[col], -12 - n * ROW_HEIGHT, 0)
                w.checkbox.label:SetString(string.format("%02d %s", rank, priority_text[key] or key))
            end
        end
    end

    local function MovePriority(key, delta)
        local index
        for i, current in ipairs(priority_order) do
            if current == key then index = i break end
        end
        if index and priority_order[index + delta] then
            priority_order[index], priority_order[index + delta] = priority_order[index + delta], priority_order[index]
            LayoutPriorityList()
        end
    end

    -- Build every row once; reordering only repositions them
    for rank, key in ipairs(priority_order) do
        local row = grid_root:AddChild(Widget("priority_row_" .. key))
        row:SetPosition(0, 0, 0)

        local bg = row:AddChild(Image("images/global.xml", "square.tex"))
        bg:ScaleToSize(280, ROW_HEIGHT - 2)
        bg:SetTint(0.18, 0.14, 0.10, 0.6)
        bg:MoveToBack()

        local saved = comp and comp.target_items and comp.target_items[key]
        local initial
        if saved ~= nil then
            initial = saved
        else
            initial = (priority_default[key] == true)
        end
        local checkbox = CreateCheckbox(row, 0, 0, string.format("%02d %s", rank, priority_text[key] or key),
            initial, function(checked)
                SyncItem(key, checked)
                local w = priority_row_widgets[key]
                if w and w.on_change then w.on_change() end
            end, -128, 150, 14, {1,1,1,1})

        CreateCardButton(row, 78, 0, 20, 20, "▲", 11, function() MovePriority(key, -1) end)
        CreateCardButton(row, 100, 0, 20, 20, "▼", 11, function() MovePriority(key, 1) end)

        priority_row_widgets[key] = { row = row, checkbox = checkbox }
    end

    -- Column headers: each is a master checkbox for its column
    local column_all_boxes = {}

    local function ColumnAllChecked(col)
        for _, key in ipairs(priority_order) do
            if (COLUMN_OF[key] or 2) == col then
                local w = priority_row_widgets[key]
                if w and w.checkbox and not w.checkbox:IsChecked() then return false end
            end
        end
        return true
    end

    for i, name in ipairs(COLUMN_NAMES) do
        local all_row = grid_root:AddChild(Widget("col_all_" .. i))
        all_row:SetPosition(COLUMN_X[i], 12, 0)
        column_all_boxes[i] = CreateCheckbox(all_row, 0, 0, name, ColumnAllChecked(i), function(checked)
            for _, key in ipairs(priority_order) do
                if (COLUMN_OF[key] or 2) == i then
                    local w = priority_row_widgets[key]
                    if w and w.checkbox then w.checkbox:SetChecked(checked) end
                    SyncItem(key, checked)
                end
            end
        end, -120, 150, 14, {1.0, 0.9, 0.45, 1})
    end

    for _, key in ipairs(priority_order) do
        local w = priority_row_widgets[key]
        if w then
            local col = COLUMN_OF[key] or 2
            w.on_change = function()
                if column_all_boxes[col] then column_all_boxes[col]:SetChecked(ColumnAllChecked(col)) end
            end
        end
    end
    self.column_all_boxes = column_all_boxes

    LayoutPriorityList()

    -- 6. Section 4: Quick Presets Toolbar
    CreateBorderedCard(self, 0, -360, 1140, 58, {0.10, 0.08, 0.06, 0.95}, {0.42, 0.32, 0.20, 0.88})

    local function SetCategories(predicate, value)
        local c = GetCompanion(self.owner)
        if c then
            for _, category in ipairs(TARGET_CATEGORIES) do
                if predicate(category.name) then
                    c.target_items = c.target_items or {}
                    if c.companion_data then
                        c.companion_data.target_items = c.companion_data.target_items or {}
                    end
                    for _, item in ipairs(category.items) do
                        c.target_items[item.key] = value
                        if c.companion_data then
                            c.companion_data.target_items[item.key] = value
                        end
                        local w = priority_row_widgets[item.key]
                        if w and w.checkbox then w.checkbox:SetChecked(value) end
                    end
                end
            end
        end
    end

    CreateCardButton(self, -400, -360, 140, 38, "Flora", 20, function()
        SetCategories(function(name) return name == "Resources" or name == "Food" end, true)
        SetCategories(function(name) return name ~= "Resources" and name ~= "Food" end, false)
    end)

    CreateCardButton(self, -240, -360, 140, 38, "Mining", 20, function()
        SetCategories(function(name) return name == "Minerals" end, true)
        SetCategories(function(name) return name ~= "Minerals" end, false)
    end)

    CreateCardButton(self, -80, -360, 140, 38, "All", 20, function()
        SetCategories(function() return true end, true)
    end)

    CreateCardButton(self, 80, -360, 140, 38, "Clear", 20, function()
        SetCategories(function() return true end, false)
    end)

    CreateCardButton(self, 240, -360, 140, 38, "Save", 20, function()
        local c = GetCompanion(self.owner)
        if c then
            c.target_items = c.target_items or {}
            c.target_priority = priority_order
            if c.companion_data then
                c.companion_data.target_items = c.target_items
                c.companion_data.target_priority = priority_order
            end
            Logger.Info("UI", "Settings saved")
        end
        if self.RefreshUI then self:RefreshUI() end
    end)

    local function RefreshUI()
        local c = GetCompanion(self.owner)
        local is_egg = c and (c:HasTag("robot_egg") or c:HasTag("wx_companion_egg"))
        local d = c and c.companion_data

        local r = (c and (c.harvest_radius or (d and d.harvest_radius)))
        if r then
            for i, v in ipairs(RADIUS_VALUES) do
                if v == r then self.radius_index = i break end
            end
            self.radius_label:SetString(string.format("Radius: %dm", RADIUS_VALUES[self.radius_index]))
        end

        local roam = (c and (c.untethered_radius or (d and d.untethered_radius)))
        if roam then
            for i, v in ipairs(FREE_ROAM_VALUES) do
                if v == roam then self.roam_index = i break end
            end
            self.roam_label:SetString(string.format("Free Roam: %dm", FREE_ROAM_VALUES[self.roam_index]))
        end

        if c then
            local harvest_val = (c.harvest_enabled ~= false and (not d or d.harvest_enabled ~= false))
            behavior_rows.harvest:SetChecked(harvest_val)
            local pickup_val = (c.pickup_enabled ~= false and (not d or d.pickup_enabled ~= false))
            local prioritize_val = (c.prioritize_pickup == true or (d and d.prioritize_pickup == true))
            behavior_rows.pickup:SetChecked(pickup_val)
            behavior_rows.prioritize:SetChecked(prioritize_val)
            if behavior_rows.harvest_resources then
                local v = (c.target_items and c.target_items.harvest_resources ~= false)
                behavior_rows.harvest_resources:SetChecked(v)
            end
            if behavior_rows.harvest_food then
                local v = (c.target_items and c.target_items.harvest_food ~= false)
                behavior_rows.harvest_food:SetChecked(v)
            end
            behavior_rows.egg:SetChecked(is_egg == true)
            local open = c.components.container and c.components.container:IsOpen()
            behavior_rows.storage:SetChecked(open == true)
            c.ui_storage_checkbox = behavior_rows.storage
        end

        for key, w in pairs(priority_row_widgets) do
            if w.checkbox then
                local val
                if c and c.target_items and c.target_items[key] ~= nil then
                    val = c.target_items[key]
                elseif d and d.target_items and d.target_items[key] ~= nil then
                    val = d.target_items[key]
                else
                    val = (priority_default[key] == true)
                end
                w.checkbox:SetChecked(val)
            end
        end

        if self.column_all_boxes then
            for i, box in pairs(self.column_all_boxes) do
                box:SetChecked(ColumnAllChecked(i))
            end
        end
    end
    self.RefreshUI = RefreshUI

    -- Pause when shown, resume when hidden. Refresh every control from the
    -- companion so the panel always mirrors live data, not construction-time defaults.
    local orig_Show = self.Show
    self.Show = function(_self)
        orig_Show(_self)
        RefreshUI()
        SetGamePaused(true)
    end
    local orig_Hide = self.Hide
    self.Hide = function(_self)
        orig_Hide(_self)
        SetGamePaused(false)
    end

    -- Defer initial overlay to ensure player is ready
    if self.owner then
        self.owner:DoTaskInTime(0, function()
            UpdateOverlay(self.owner, true, RADIUS_VALUES[self.radius_index])
        end)
    end
end)

return HarvesterUI
