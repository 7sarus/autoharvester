local _G = rawget(_G, "GLOBAL") or _G
local GetPlayer = _G.GetPlayer
local GetTime = _G.GetTime
local SpawnPrefab = _G.SpawnPrefab
local Vector3 = _G.Vector3 or Vector3
local TUNING = _G.TUNING or {}
local Logger = require("wx_logger")

local assets = {
    Asset("ANIM", "anim/tallbird_egg.zip"),
}

local HATCH_TIME = 5 * (TUNING.TOTAL_DAY_TIME or 480)

local slotpos_mirror_mc = require("slot_layout")


local EQUIP_SLOTS = { [16] = _G.EQUIPSLOTS.HANDS, [17] = _G.EQUIPSLOTS.BODY, [18] = _G.EQUIPSLOTS.HEAD }

local function Hatch(inst, doer)
    local player = doer or (GetPlayer and GetPlayer())
    local x, y, z

    local invitem = inst.components.inventoryitem
    local owner = invitem and invitem.owner
    if owner and owner:IsValid() and owner.Transform then
        x, y, z = owner.Transform:GetWorldPosition()
        if owner.components.inventory then
            owner.components.inventory:RemoveItem(inst)
        elseif owner.components.container then
            owner.components.container:RemoveItem(inst)
        end
    elseif inst.Transform then
        x, y, z = inst.Transform:GetWorldPosition()
    elseif player and player.Transform then
        x, y, z = player.Transform:GetWorldPosition()
    else
        x, y, z = 0, 0, 0
    end

    if inst.components.container and inst.components.container:IsOpen() then
        inst.components.container:Close()
    end

    local companion = SpawnPrefab and SpawnPrefab("wx_companion")
    if companion then
        companion.Transform:SetPosition(x, y, z)
        if player and player:IsValid() then
            if companion.components.follower then
                companion.components.follower:SetLeader(player)
            end
            player.wx_companion = companion
            player.wx_egg = nil
        end

        -- Transfer stored items back to companion container
        if inst.components.container and companion.components.container then
            for s = 1, inst.components.container.numslots do
                local item = inst.components.container:RemoveItemBySlot(s)
                if item then
                    companion.components.container:GiveItem(item, s, nil, false, true)
                end
            end
        end

        -- Restore saved companion settings
        if inst.companion_data then
            local d = inst.companion_data
            if d.harvest_radius ~= nil then companion.harvest_radius = d.harvest_radius end
            if d.untethered_radius ~= nil then companion.untethered_radius = d.untethered_radius end
            if d.target_items ~= nil then
                for k, v in pairs(d.target_items) do companion.target_items[k] = v end
            end
            if d.target_priority ~= nil then companion.target_priority = d.target_priority end
            if d.follow_player ~= nil then companion.follow_player = d.follow_player end
            if d.harvest_enabled ~= nil then companion.harvest_enabled = d.harvest_enabled end
            if d.untethered ~= nil then companion.untethered = d.untethered end
            if d.draw_aggro ~= nil then companion.draw_aggro = d.draw_aggro end
            if d.pickup_enabled ~= nil then companion.pickup_enabled = d.pickup_enabled end
            if d.prioritize_pickup ~= nil then companion.prioritize_pickup = d.prioritize_pickup end
            if d.join_player_work ~= nil then companion.join_player_work = d.join_player_work end
            if d.transfer_to_player ~= nil then companion.transfer_to_player = d.transfer_to_player end
        end

        if companion.Rewear then
            companion:Rewear({16, 17, 18})
        end

        Logger.Info("EGG", "Robot egg hatched at (%.1f, %.1f)", x, z)
    end

    if inst.SoundEmitter then
        inst.SoundEmitter:PlaySound("dontstarve/creatures/egg/egg_hatch_crack")
    end
    inst:Remove()
    return companion
end

local function CheckHatch(inst)
    if inst.auto_hatch ~= false and GetTime() >= (inst.hatch_time or 0) then
        Hatch(inst)
    end
end

local function OnSave(inst, data)
    data.hatch_time = inst.hatch_time
    data.auto_hatch = inst.auto_hatch
    data.companion_data = inst.companion_data
end

local function OnLoad(inst, data)
    if data then
        if data.hatch_time ~= nil then inst.hatch_time = data.hatch_time end
        if data.auto_hatch ~= nil then inst.auto_hatch = data.auto_hatch end
        if data.companion_data ~= nil then inst.companion_data = data.companion_data end
    end
end

local function fn()
    local inst = CreateEntity()

    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddSoundEmitter()

    MakeInventoryPhysics(inst)

    inst.AnimState:SetBank("egg")
    inst.AnimState:SetBuild("tallbird_egg")
    inst.AnimState:PlayAnimation("egg")
    if inst.AnimState.SetMultColour then
        inst.AnimState:SetMultColour(0.78, 0.62, 0.42, 1) -- metallic copper tint (distinct from tallbird egg)
    end

    inst:AddTag("robot_egg")
    inst:AddTag("wx_companion_egg")
    inst:AddTag("irreplaceable") -- companion must not pick up its own egg

    inst:AddComponent("inventoryitem")
    inst.components.inventoryitem.imagename = "tallbirdegg"
    inst.components.inventoryitem.atlasname = "images/inventoryimages.xml"
    inst:AddComponent("inspectable")

    -- Horizontal Storage matching WX companion (15 storage slots + 3 equipment columns)
    inst:AddComponent("container")
    inst.components.container:SetNumSlots(#slotpos_mirror_mc)
    inst.components.container.widgetslotpos = slotpos_mirror_mc
    inst.components.container.side_align_tip = 160
    inst.components.container.widgetbgatlas = "images/ui.xml"
    inst.components.container.widgetbgimage = "blank.tex"
    inst.components.container.type = "wx_companion"
    inst.components.container.acceptsstacks = true
    inst.components.container.itemtestfn = function(inst, item, slot)
        local want = EQUIP_SLOTS[slot]
        return not want or (item.components.equippable ~= nil and item.components.equippable.equipslot == want)
    end

    inst.ToggleStorage = function(inst, player)
        local cont = inst.components.container
        if cont:IsOpen() then
            cont:Close()
        else
            cont:Open(player or (GetPlayer and GetPlayer()))
        end
    end

    inst.components.container.onopenfn = function(inst)
        if inst.ui_storage_checkbox then inst.ui_storage_checkbox:SetChecked(true) end
    end
    inst.components.container.onclosefn = function(inst)
        if inst.ui_storage_checkbox then inst.ui_storage_checkbox:SetChecked(false) end
    end

    inst.hatch_time = GetTime() + HATCH_TIME
    inst.auto_hatch = true -- natural death eggs auto-hatch after timer; manual/boat sets to false
    inst.CheckHatch = CheckHatch
    inst.Hatch = Hatch
    inst.Deploy = Hatch
    inst.companion_data = {}
    inst.persists = true

    inst.OnSave = OnSave
    inst.OnLoad = OnLoad

    return inst
end

return Prefab("common/robot_egg", fn, assets)
