PrefabFiles = {
    "wx_companion",
    "harvest_range_ring",
}

local GLOBAL = GLOBAL
local TheInput = GLOBAL.TheInput
local TheSim = GLOBAL.TheSim
local GetPlayer = GLOBAL.GetPlayer
local Vector3 = GLOBAL.Vector3

local Logger = GLOBAL.require("wx_logger")
local HarvesterUI = GLOBAL.require("widgets/harvester_ui")
local ImageButton = GLOBAL.require("widgets/imagebutton")
local Image = GLOBAL.require("widgets/image")
local Text = GLOBAL.require("widgets/text")
local Widget = GLOBAL.require("widgets/widget")
local DEFAULTFONT = GLOBAL.DEFAULTFONT or "opensans"

local default_radius = GetModConfigData("DEFAULT_RADIUS") or 15
local toggle_key = GetModConfigData("KEY_TOGGLE_UI") or GLOBAL.KEY_H
local toggle_storage_key = GetModConfigData("KEY_TOGGLE_STORAGE") or GLOBAL.KEY_C
Logger.SetLevel(GetModConfigData("DEBUG_LOGGING") or 2)

-- DS SP has FindEntities but not FindFirstEntityWithTag
local function FindCompanionEntity()
    local x, y, z = 0, 0, 0
    local player = GetPlayer and GetPlayer()
    if player and player.Transform then x, y, z = player.Transform:GetWorldPosition() end
    local ents = TheSim and TheSim:FindEntities(x, y, z, 9999, {"wx_companion"})
    return ents and ents[1] or nil
end

local function EnsureCompanion(player)
    if not player or not player:IsValid() then return end

    if not player.wx_companion or not player.wx_companion:IsValid() then
        local existing = FindCompanionEntity()
        if existing and existing:IsValid() then
            player.wx_companion = existing
        else
            local px, py, pz = player.Transform:GetWorldPosition()
            local companion = nil
            Logger.SafeCall("SPAWN", function()
                companion = GLOBAL.SpawnPrefab("wx_companion")
            end)
            if companion then
                companion.Transform:SetPosition(px + 1.5, py, pz + 1.5)
                companion.harvest_radius = default_radius
                player.wx_companion = companion
                Logger.Info("SPAWN", "Companion spawned at (%.1f, %.1f)", px + 1.5, pz + 1.5)
            end
        end
    end

    if player.wx_companion and player.wx_companion:IsValid() and player.wx_companion.components.follower then
        player.wx_companion.components.follower:SetLeader(player)
    end
end

AddSimPostInit(function(player)
    local target = player or (GetPlayer and GetPlayer())
    if target and target:IsValid() then
        EnsureCompanion(target)
    else
        local world = GLOBAL.GetWorld()
        if world then world:DoTaskInTime(0, function() EnsureCompanion(GetPlayer and GetPlayer()) end) end
    end
end)

local active_hud = nil
AddClassPostConstruct("screens/playerhud", function(self)
    active_hud = self

    local function InitHarvesterUI(player)
        if not self.harvester_ui then
            local root = self.root or self
            self.harvester_ui = root:AddChild(HarvesterUI(player, default_radius))
            self.harvester_ui:Hide()

            -- Button 1: Control UI
            local btn_ui = root:AddChild(ImageButton("images/ui.xml", "button_small.tex", "button_small_over.tex"))
            btn_ui:SetHAnchor(GLOBAL.ANCHOR_RIGHT)
            btn_ui:SetVAnchor(GLOBAL.ANCHOR_TOP)
            btn_ui:SetPosition(-48, -45, 0)
            btn_ui:SetScale(0.55, 0.55, 1)
            btn_ui:SetText("WX")
            if btn_ui.SetTextSize then btn_ui:SetTextSize(24) end
            btn_ui:SetOnClick(function()
                if self.harvester_ui.shown then
                    self.harvester_ui:Hide()
                else
                    self.harvester_ui:Show()
                end
            end)
            self.harvester_toggle_btn = btn_ui

            -- Button 2: Storage Container Toggle (1x15 + Equip)
            local btn_storage = root:AddChild(ImageButton("images/ui.xml", "button_small.tex", "button_small_over.tex"))
            btn_storage:SetHAnchor(GLOBAL.ANCHOR_RIGHT)
            btn_storage:SetVAnchor(GLOBAL.ANCHOR_TOP)
            btn_storage:SetPosition(-122, -45, 0)
            btn_storage:SetScale(0.55, 0.55, 1)
            btn_storage:SetText("Chest")
            if btn_storage.SetTextSize then btn_storage:SetTextSize(22) end
            btn_storage:SetOnClick(function()
                local p = self.owner or (GetPlayer and GetPlayer())
                local comp = p and p.wx_companion
                if comp and comp.ToggleStorage then comp:ToggleStorage(p) end
            end)
            self.harvester_storage_btn = btn_storage
        end
    end

    if self.owner then
        InitHarvesterUI(self.owner)
    else
        local orig_SetMainCharacter = self.SetMainCharacter
        self.SetMainCharacter = function(hud, maincharacter)
            if orig_SetMainCharacter then
                orig_SetMainCharacter(hud, maincharacter)
            end
            InitHarvesterUI(maincharacter or (GetPlayer and GetPlayer()))
        end
    end
end)

AddClassPostConstruct("widgets/containerwidget", function(self)
    local orig_Open = self.Open
    self.Open = function(widget, container, doer)
        orig_Open(widget, container, doer)
        if container and (container:HasTag("wx_companion") or (container.components.container and container.components.container.type == "wx_companion")) then
            local hud = (doer and doer.HUD) or (widget.owner and widget.owner.HUD)
            if hud and hud.controls and hud.controls.top_root then
                hud.controls.top_root:AddChild(widget)
                widget:SetPosition(0, -58, 0)
            end

            if not widget.wx_bg then
                local bg_group = widget:AddChild(Widget("wx_bg_group"))
                local border = bg_group:AddChild(Image("images/ui.xml", "black.tex"))
                if border.ScaleToSize then border:ScaleToSize(1516, 102) end
                border:SetTint(0.55, 0.43, 0.28, 0.95)

                local fill = bg_group:AddChild(Image("images/ui.xml", "black.tex"))
                if fill.ScaleToSize then fill:ScaleToSize(1512, 98) end
                fill:SetTint(0.12, 0.10, 0.08, 0.96)

                local lbl_storage = bg_group:AddChild(Text(DEFAULTFONT, 18, "WX COMPANION STORAGE (15 SLOTS)"))
                lbl_storage:SetPosition(-130, 36, 0)
                lbl_storage:SetColour(1.0, 0.88, 0.40, 1)

                local lbl_equip = bg_group:AddChild(Text(DEFAULTFONT, 18, "EQUIPMENT"))
                lbl_equip:SetPosition(620, 36, 0)
                lbl_equip:SetColour(0.95, 0.92, 0.88, 1)

                widget.wx_bg = bg_group
            end
            if widget.wx_bg and widget.wx_bg.MoveToBack then
                widget.wx_bg:MoveToBack()
            end
            if widget.wx_bg then
                widget.wx_bg:Show()
            end
            if widget.inv then
                for idx, slot in ipairs(widget.inv) do
                    if slot.MoveToFront then slot:MoveToFront() end
                    if idx == 16 and slot.bgimage then
                        slot.bgimage:SetTexture("images/hud.xml", "equip_slot.tex")
                    elseif idx == 17 and slot.bgimage then
                        slot.bgimage:SetTexture("images/hud.xml", "equip_slot_body.tex")
                    elseif idx == 18 and slot.bgimage then
                        slot.bgimage:SetTexture("images/hud.xml", "equip_slot_head.tex")
                    end
                end
            end
        else
            if widget.wx_bg then widget.wx_bg:Hide() end
        end
    end

    local orig_Close = self.Close
    self.Close = function(widget)
        if widget.wx_bg then widget.wx_bg:Hide() end
        orig_Close(widget)
    end

    local orig_OnUpdate = self.OnUpdate
    self.OnUpdate = function(widget, dt)
        if widget.isopen and widget.container and (widget.container:HasTag("wx_companion") or (widget.container.components.container and widget.container.components.container.type == "wx_companion")) then
            if not widget.container:IsValid() or (widget.owner and not widget.owner:IsValid()) then
                widget:Close()
            end
            return
        end
        orig_OnUpdate(widget, dt)
    end
end)

TheInput:AddKeyUpHandler(toggle_key, function()
    if active_hud and active_hud.inst and active_hud.inst:IsValid() and active_hud.harvester_ui then
        if active_hud.harvester_ui.shown then
            active_hud.harvester_ui:Hide()
        else
            active_hud.harvester_ui:Show()
        end
    end
end)

TheInput:AddKeyUpHandler(toggle_storage_key, function()
    local player = GetPlayer and GetPlayer()
    local comp = player and player.wx_companion
    if comp and comp.ToggleStorage then comp:ToggleStorage(player) end
end)
