local _G = rawget(_G, "GLOBAL") or _G
local GetPlayer = _G.GetPlayer
local Vector3 = _G.Vector3 or Vector3
local brain = require("brains/wx_companionbrain")
local Logger = require("wx_logger")

local assets = {
    Asset("ANIM", "anim/player_basic.zip"),
    Asset("ANIM", "anim/player_actions.zip"),
    Asset("ANIM", "anim/player_idles.zip"),
    Asset("ANIM", "anim/player_idles_shiver.zip"),
    Asset("ANIM", "anim/wx78.zip"),
    Asset("ANIM", "anim/ui_krampusbag_2x8.zip"),
    Asset("SOUND", "sound/wx78.fsb"),
}

-- Single horizontal strip mirroring MC storage: 15 storage slots + 3 equipment columns
local slotpos_mirror_mc = {}
local W = 68
local SEP = 12
local INTERSEP = 28
local num_slots = 15
local num_storage = num_slots
local num_equip = 3
local num_intersep = math.floor(num_slots / 5) + 1 -- 4
local total_w = (num_slots + num_equip) * W + (num_slots + num_equip - 2 - num_intersep) * SEP + INTERSEP * num_intersep

-- 15 Storage slots (slots 1..15)
for k = 1, num_slots do
    local interseps = math.floor((k - 1) / 5)
    local x = -total_w / 2 + W / 2 + interseps * (INTERSEP - SEP) + (k - 1) * W + (k - 1) * SEP
    table.insert(slotpos_mirror_mc, Vector3(x, 0, 0))
end

-- 3 Equipment columns: Hands, Body, Head (slots 16, 17, 18)
for k = 1, num_equip do
    local x = -total_w / 2 + num_slots * W + num_intersep * (INTERSEP - SEP) + (num_slots - 1) * SEP + INTERSEP + W * (k - 1) + SEP * (k - 1)
    table.insert(slotpos_mirror_mc, Vector3(x, 0, 0))
end

local function ProcessHarvestedItems(inst)
    local inv = inst.components.inventory
    local cont = inst.components.container
    if not inv then return end

    local player = GetPlayer and GetPlayer()

    -- Snapshot inventory slots
    local items = {}
    for slot, item in pairs(inv.itemslots) do
        if item and item:IsValid() then items[#items + 1] = item end
    end

    for _, item in ipairs(items) do
        inv:RemoveItem(item, true)
        local stored = false

        -- 1. Store in companion's 1x15 storage strip (slots 1..15, leaving 16..18 for equipment)
        if not inst.transfer_to_player and cont then
            local item_name = item.prefab or "item"
            for s = 1, num_storage do
                local slot_item = cont:GetItemInSlot(s)
                if slot_item and slot_item.prefab == item.prefab and slot_item.components.stackable and not slot_item.components.stackable:IsFull() then
                    item = slot_item.components.stackable:Put(item)
                    if not item then
                        stored = true
                        Logger.Debug("STORAGE", "Stacked %s in storage slot %d", item_name, s)
                        break
                    end
                end
            end
            if not stored and item then
                for s = 1, num_storage do
                    if not cont:GetItemInSlot(s) then
                        if cont:GiveItem(item, s, nil, false) then
                            stored = true
                            Logger.Debug("STORAGE", "Stored %s in storage slot %d", item.prefab or item_name, s)
                            break
                        end
                    end
                end
            end
        end

        -- 2. If storage full or direct transfer enabled, pass to player
        if not stored and player and player:IsValid() and player.components.inventory then
            if player.components.inventory:GiveItem(item) then
                stored = true
                Logger.Info("TRANSFER", "Transferred %s to player inventory", item.prefab or "item")
            end
        end

        -- 3. If both companion and player are full, drop safely at feet
        if not stored then
            local px, py, pz = inst.Transform:GetWorldPosition()
            if item.Physics then item.Physics:Teleport(px, py, pz) else item.Transform:SetPosition(px, py, pz) end
            if item.components.inventoryitem then item.components.inventoryitem:OnDropped(true) end
            Logger.Warn("STORAGE", "Storage full; dropped %s", item.prefab or "item")
        end
    end

    if #items > 0 and inst.SoundEmitter then
        inst.SoundEmitter:PlaySound("dontstarve/characters/wx78/levelup")
    end
end

local EQUIP_SLOTS = { [16] = _G.EQUIPSLOTS.HANDS, [17] = _G.EQUIPSLOTS.BODY, [18] = _G.EQUIPSLOTS.HEAD }

local function IsInInventory(inst, item)
    for _, in_inv in pairs(inst.components.inventory.itemslots) do
        if in_inv == item then return true end
    end
    return false
end

local function WearItem(inst, slot, item)
    inst.worn = inst.worn or {}
    inst.worn[slot] = item
    item.components.equippable:Equip(inst, EQUIP_SLOTS[slot])
end

local function OnItemGet(inst, data)
    local slot = data and data.slot
    local item = data and data.item
    local want = slot and EQUIP_SLOTS[slot]
    if want and item and item.components.equippable and inst.components.container:GetItemInSlot(slot) == item then
        WearItem(inst, slot, item)
    elseif item and IsInInventory(inst, item) then
        inst:DoTaskInTime(0, ProcessHarvestedItems)
    end
end

local function OnItemLose(inst, data)
    local slot = data and data.slot
    local item = slot and inst.worn and inst.worn[slot]
    if item and inst.components.container:GetItemInSlot(slot) ~= item then
        inst.worn[slot] = nil
        item.components.equippable:Unequip(inst, EQUIP_SLOTS[slot])
    end
end

local function OnSave(inst, data)
    data.follow_player = inst.follow_player
    data.harvest_enabled = inst.harvest_enabled
    data.transfer_to_player = inst.transfer_to_player
    data.harvest_radius = inst.harvest_radius
    data.target_items = inst.target_items
    data.worn = {}
    for slot in pairs(inst.worn or {}) do
        table.insert(data.worn, slot)
    end
end

local function Rewear(inst, slots)
    local cont = inst.components.container
    for _, slot in ipairs(slots or {}) do
        local item = cont:GetItemInSlot(slot)
        local want = EQUIP_SLOTS[slot]
        if item and want and item.components.equippable and item.components.equippable.equipslot == want then
            WearItem(inst, slot, item)
        end
    end
end

local function OnLoad(inst, data)
    if not data then return end
    if data.follow_player ~= nil then inst.follow_player = data.follow_player end
    if data.harvest_enabled ~= nil then inst.harvest_enabled = data.harvest_enabled end
    if data.transfer_to_player ~= nil then inst.transfer_to_player = data.transfer_to_player end
    if data.harvest_radius ~= nil then inst.harvest_radius = data.harvest_radius end
    for key, value in pairs(data.target_items or {}) do
        inst.target_items[key] = value
    end

    local player = GetPlayer and GetPlayer()
    if player and inst.components.follower then
        inst.components.follower:SetLeader(player)
        player.wx_companion = inst
    end

    inst:DoTaskInTime(0, function() Rewear(inst, data.worn) end)
end

local function Cleanup(inst)
    local player = GetPlayer and GetPlayer()
    if player and player.wx_companion == inst then
        player.wx_companion = nil
    end
    for slot, item in pairs(inst.worn or {}) do
        if item:IsValid() and item.components.equippable then
            item.components.equippable:Unequip(inst, EQUIP_SLOTS[slot])
        end
    end
    inst.worn = nil
end

local function fn()
    local inst = CreateEntity()

    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddSoundEmitter()
    inst.entity:AddDynamicShadow()

    inst.DynamicShadow:SetSize(1.5, 0.75)
    inst.Transform:SetFourFaced()
    inst.Transform:SetScale(0.75, 0.75, 0.75)

    -- Ghost physics: still blocked by terrain and water, but walks through trees, rocks and walls
    MakeGhostPhysics(inst, 50, 0.5)

    inst.AnimState:SetBank("wilson")
    inst.AnimState:SetBuild("wx78")
    inst.AnimState:PlayAnimation("idle_loop", true)

    inst:AddTag("companion")
    inst:AddTag("notarget")
    inst:AddTag("scarytoprey")
    inst:AddTag("wx_companion")

    inst:AddComponent("locomotor")
    inst.components.locomotor.walkspeed = 6
    inst.components.locomotor.runspeed = 9

    inst:AddComponent("follower")
    inst:AddComponent("inventory")

    -- Horizontal Storage (15 slots + 3 equipment columns mirroring MC storage)
    inst:AddComponent("container")
    inst.components.container:SetNumSlots(#slotpos_mirror_mc)
    inst.components.container.widgetslotpos = slotpos_mirror_mc
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

    inst:AddComponent("health")
    inst.components.health:SetMaxHealth(100)
    inst.components.health:SetInvincible(true)

    -- Real components needed by SGwilson
    inst:AddComponent("rider")
    inst:AddComponent("combat")
    inst:AddComponent("freezable")
    inst:AddComponent("pinnable")
    inst:AddComponent("talker")
    inst.components.talker.Say = function() end

    -- Zero-drain stubs satisfying SGwilson state queries and interaction callbacks (e.g. flower picking)
    inst.components.sanity = {
        inst = inst,
        current = 100,
        max = 100,
        IsSane = function() return true end,
        IsCrazy = function() return false end,
        GetPercent = function() return 1 end,
        SetPercent = function() end,
        DoDelta = function() end,
    }
    inst.components.hunger = {
        inst = inst,
        current = 100,
        max = 100,
        GetPercent = function() return 1 end,
        IsStarving = function() return false end,
        Pause = function() end,
        Resume = function() end,
        SetPercent = function() end,
        DoDelta = function() end,
    }
    inst.components.temperature = {
        inst = inst,
        GetCurrent = function() return 30 end,
        IsFreezing = function() return false end,
        IsOverheating = function() return false end,
        SetTemperature = function() end,
        DoDelta = function() end,
    }
    -- SGwilson (Hamlet) indexes these unguarded; stubs keep every state from crashing
    inst.components.poisonable = {
        inst = inst,
        IsPoisoned = function() return false end,
        Poison = function() end,
        CurePoison = function() end,
    }
    inst.components.eater = {
        inst = inst,
        CanEat = function() return false end,
        Eat = function() return false end,
    }
    inst.components.bundler = {
        inst = inst,
        StopBundling = function() end,
        OnFinishBundling = function() end,
    }
    inst.components.hayfever = {
        inst = inst,
        IsSneezing = function() return false end,
        DoSneezeEffects = function() end,
    }
    inst.components.grogginess = {
        inst = inst,
        IsGroggy = function() return false end,
        IsKnockedOut = function() return false end,
        GetGrogginess = function() return 0 end,
        AddGrogginess = function() end,
        KnockOut = function() end,
    }
    inst.components.beaverness = {
        inst = inst,
        IsBeaver = function() return false end,
        makebeaver = function() end,
        doing_transform = false,
    }
    inst.components.playercontroller = {
        Enable = function() end,
        EnableMapControls = function() end,
    }

    inst:SetStateGraph("SGwilson")
    inst:SetBrain(brain)

    inst.follow_player = true
    inst.harvest_enabled = true
    inst.transfer_to_player = false
    inst.harvest_radius = 15
    inst.target_items = {
        twigs = true,
        cutgrass = true,
        log = true,
        seeds = true,
        berries = true,
        carrot = false,
        flint = false,
        rocks = false,
        goldnugget = false,
        nitre = false,
        pinecone = false,
        misc = true,
    }

    inst:ListenForEvent("itemget", OnItemGet)
    inst:ListenForEvent("itemlose", OnItemLose)
    inst:ListenForEvent("onremove", Cleanup)
    inst.OnSave = OnSave
    inst.OnLoad = OnLoad

    return inst
end

return Prefab("common/wx_companion", fn, assets)
