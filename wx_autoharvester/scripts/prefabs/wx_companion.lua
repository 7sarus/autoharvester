local _G = rawget(_G, "GLOBAL") or _G
local GetPlayer = _G.GetPlayer
local Vector3 = _G.Vector3 or Vector3
local SpawnPrefab = _G.SpawnPrefab
local brain = require("brains/wx_companionbrain")
local Logger = require("wx_logger")
local TARGET_PRIORITY = require("target_priority")
local TARGET_CATEGORIES = require("target_categories")

local assets = {
    Asset("ANIM", "anim/player_basic.zip"),
    Asset("ANIM", "anim/player_actions.zip"),
    Asset("ANIM", "anim/player_idles.zip"),
    Asset("ANIM", "anim/player_idles_shiver.zip"),
    Asset("ANIM", "anim/wx78.zip"),
    Asset("ANIM", "anim/ui_krampusbag_2x8.zip"),
    Asset("SOUND", "sound/wx78.fsb"),
}

local slotpos_mirror_mc = require("slot_layout")


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
            for s = 1, 15 do
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
                for s = 1, 15 do
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
            -- Prevent an infinite pick-up/drop loop when both storages are full.
            inst.failed_until = inst.failed_until or {}
            inst.failed_until[item] = (GetTime and GetTime() or 0) + 120
            Logger.Warn("STORAGE", "Storage full; dropped %s", item.prefab or "item")
        end
    end

    if #items > 0 and inst.SoundEmitter then
        inst.SoundEmitter:PlaySound("dontstarve/characters/wx78/levelup")
    end
end

-- Transfer all items from companion's container (storage slots 1-15) to player inventory
local function TransferStorageToPlayer(inst)
    local cont = inst.components.container
    local player = GetPlayer and GetPlayer()
    if not cont or not player or not player:IsValid() or not player.components.inventory then return 0 end

    local transferred = 0
    for s = 1, 15 do -- only storage slots 1-15
        local item = cont:GetItemInSlot(s)
        if item and item:IsValid() then
            item = cont:RemoveItemBySlot(s)
            if item then
                if player.components.inventory:GiveItem(item) then
                    transferred = transferred + 1
                    Logger.Info("TRANSFER", "Docked %s to player inventory", item.prefab or "item")
                else
                    -- Player full, put back
                    cont:GiveItem(item, s, nil, false)
                    Logger.Warn("TRANSFER", "Player inventory full, kept %s in storage", item.prefab or "item")
                end
            end
        end
    end

    if transferred > 0 and inst.SoundEmitter then
        inst.SoundEmitter:PlaySound("dontstarve/characters/wx78/levelup")
    end
    return transferred
end

local EQUIP_SLOTS = { [16] = _G.EQUIPSLOTS.HANDS, [17] = _G.EQUIPSLOTS.BODY, [18] = _G.EQUIPSLOTS.HEAD }

local function TransformToEgg(inst, player)
    if inst.is_transforming then return end
    inst.is_transforming = true

    local p = player or (GetPlayer and GetPlayer())

    if inst.components.container and inst.components.container:IsOpen() then
        inst.components.container:Close()
    end

    local egg = SpawnPrefab and SpawnPrefab("robot_egg")
    if not egg then
        inst.is_transforming = false
        return nil
    end

    -- Transfer all items from companion's container to egg's container
    if inst.components.container and egg.components.container then
        for s = 1, inst.components.container.numslots do
            local item = inst.components.container:RemoveItemBySlot(s)
            if item then
                egg.components.container:GiveItem(item, s, nil, false, true)
            end
        end
    end

    -- Save companion settings & state into egg
    egg.companion_data = {
        harvest_radius = inst.harvest_radius,
        untethered_radius = inst.untethered_radius,
        target_items = inst.target_items,
        target_priority = inst.target_priority,
        follow_player = inst.follow_player,
        harvest_enabled = inst.harvest_enabled,
        untethered = inst.untethered,
        draw_aggro = inst.draw_aggro,
        pickup_enabled = inst.pickup_enabled,
        prioritize_pickup = inst.prioritize_pickup,
        join_player_work = inst.join_player_work,
        transfer_to_player = inst.transfer_to_player,
    }
    egg.auto_hatch = false -- manual / boat transform stays in egg form until deployed

    -- Place egg into player inventory
    local given = false
    if p and p:IsValid() and p.components.inventory then
        given = p.components.inventory:GiveItem(egg)
    end
    if not given then
        local px, py, pz = inst.Transform:GetWorldPosition()
        if p and p:IsValid() and p.Transform then px, py, pz = p.Transform:GetWorldPosition() end
        egg.Transform:SetPosition(px, py, pz)
    end

    if p and p:IsValid() then
        p.wx_companion = egg
        p.wx_egg = egg
        if p.SoundEmitter then
            p.SoundEmitter:PlaySound("dontstarve/characters/wx78/levelup")
        end
    end

    Logger.Info("TRANSFORM", "Companion transformed into robot egg/seed in player inventory")
    inst:Remove()
    return egg
end

-- Death turns the companion into a collectable robot egg (hatches into a new companion)
local function OnDeath(inst)
    if inst.is_transforming then return end
    local x, y, z = inst.Transform:GetWorldPosition()

    -- Never lose the player's stored loot: spill it where the companion fell
    if inst.components.container and inst.components.container.DropEverything then
        inst.components.container:DropEverything()
    end

    local egg = SpawnPrefab and SpawnPrefab("robot_egg")
    if egg then
        egg.Transform:SetPosition(x, y, z)
        Logger.Info("DEATH", "Companion destroyed; robot egg laid at (%.1f, %.1f)", x, z)
    end

    inst:Remove()
end

local function IsInInventory(inst, item)
    for _, in_inv in pairs(inst.components.inventory.itemslots) do
        if in_inv == item then return true end
    end
    return false
end

local function WearItem(inst, slot, item)
    inst.worn = inst.worn or {}
    inst.worn[slot] = item
    local want = EQUIP_SLOTS[slot]
    if inst.components.inventory and want then
        inst.components.inventory.equipslots[want] = item
    end
    if item.components and item.components.equippable and item.components.equippable.Equip then
        item.components.equippable:Equip(inst, want)
    end
    inst:ListenForEvent("onremove", function()
        if inst.worn and inst.worn[slot] == item then inst.worn[slot] = nil end
        if inst.components.inventory and inst.components.inventory.equipslots[want] == item then
            inst.components.inventory.equipslots[want] = nil
        end
        if inst.components.container and inst.components.container.slots[slot] == item then
            inst.components.container.slots[slot] = nil
        end
    end, item)
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
        local want = EQUIP_SLOTS[slot]
        if inst.components.inventory and want then
            inst.components.inventory.equipslots[want] = nil
        end
        if item.components and item.components.equippable then
            item.components.equippable:Unequip(inst, want)
        end
    end
end

local function OnSave(inst, data)
    data.follow_player = inst.follow_player
    data.harvest_enabled = inst.harvest_enabled
    data.transfer_to_player = inst.transfer_to_player
    data.untethered = inst.untethered
    data.draw_aggro = inst.draw_aggro
    data.pickup_enabled = inst.pickup_enabled
    data.prioritize_pickup = inst.prioritize_pickup
    data.harvest_radius = inst.harvest_radius
    data.untethered_radius = inst.untethered_radius
    data.target_items = inst.target_items
    data.target_priority = inst.target_priority
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
    if data.untethered ~= nil then inst.untethered = data.untethered end
    if data.draw_aggro ~= nil then inst.draw_aggro = data.draw_aggro end
    if data.pickup_enabled ~= nil then inst.pickup_enabled = data.pickup_enabled end
    if data.prioritize_pickup ~= nil then inst.prioritize_pickup = data.prioritize_pickup end
    if data.harvest_radius ~= nil then inst.harvest_radius = data.harvest_radius end
    if data.untethered_radius ~= nil then inst.untethered_radius = data.untethered_radius end
    for key, value in pairs(data.target_items or {}) do
        inst.target_items[key] = value
    end
    if data.target_priority then
        local allowed, seen, priority = {}, {}, {}
        for _, key in ipairs(TARGET_PRIORITY) do allowed[key] = true end
        for _, key in ipairs(data.target_priority) do
            if allowed[key] and not seen[key] then
                priority[#priority + 1] = key
                seen[key] = true
            end
        end
        for _, key in ipairs(TARGET_PRIORITY) do
            if not seen[key] then priority[#priority + 1] = key end
        end
        inst.target_priority = priority
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
    if inst.debug_log_widget and inst.debug_log_widget.inst and inst.debug_log_widget.inst:IsValid() then
        inst.debug_log_widget:Kill()
    end
    inst.debug_log_widget = nil
    inst.debug_log_lines = nil
    for slot, item in pairs(inst.worn or {}) do
        local want = EQUIP_SLOTS[slot]
        if item and item.IsValid and item:IsValid() and item.components and item.components.equippable then
            item.components.equippable:Unequip(inst, want)
        end
        if inst.components.inventory and want then
            inst.components.inventory.equipslots[want] = nil
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

    inst.TransferStorageToPlayer = TransferStorageToPlayer
    inst.TransformToEgg = TransformToEgg
    inst.Rewear = Rewear

    inst.components.container.onopenfn = function(inst)
        if inst.ui_storage_checkbox then inst.ui_storage_checkbox:SetChecked(true) end
    end
    inst.components.container.onclosefn = function(inst)
        if inst.ui_storage_checkbox then inst.ui_storage_checkbox:SetChecked(false) end
    end

    inst:AddComponent("health")
    inst.components.health:SetMaxHealth(100)

    -- Real components needed by SGwilson
    inst:AddComponent("rider")
    inst:AddComponent("combat")
    if inst.components.combat.SetDefaultDamage then
        inst.components.combat:SetDefaultDamage(20)
    end
    if inst.components.combat.SetAttackPeriod then
        inst.components.combat:SetAttackPeriod(1)
    end
    if inst.components.combat.SetRange then
        inst.components.combat:SetRange(2)
    end
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

    -- Stationary debug log at the top of the HUD showing the active brain chain,
    -- current action, and a short history of recent actions.
    local text_ok, Text = pcall(require, "widgets/text")
    if text_ok and Text then
        local function RunningChain(node)
            if not node or node.status ~= _G.RUNNING then return "" end
            local s = node.name or "?"
            if node.DBString then
                local db = node:DBString()
                if db and db ~= "" then s = s .. " [" .. db .. "]" end
            end
            if node.children then
                for _, child in ipairs(node.children) do
                    if child.status == _G.RUNNING then
                        local child_s = RunningChain(child)
                        if child_s ~= "" then return s .. " > " .. child_s end
                    end
                end
            end
            return s
        end

        -- Only write a debug log when a real home directory is available; never
        -- hardcode a user path (DS sandbox may strip os.getenv).
        -- Cross-platform home resolution (Unix HOME, Windows USERPROFILE).
        local home = (os and os.getenv and (os.getenv("HOME") or os.getenv("USERPROFILE")))
        -- DS paths use forward slashes on all platforms.
        local DEBUG_LOG_FILE = (home and home ~= "") and (home .. "/.klei/DoNotStarve/wx_companion_log.txt") or nil
        local function WriteDebugLog(chain, action)
            if not DEBUG_LOG_FILE then return end
            local ok, f = pcall(io.open, DEBUG_LOG_FILE, "a")
            if ok and f then
                local ts = (os and os.date and os.date("%Y-%m-%d %H:%M:%S")) or ""
                f:write(string.format("%s | BT: %s | ACT: %s\n", ts, chain ~= "" and chain or "-", action))
                f:close()
            end
        end
        if DEBUG_LOG_FILE then
            local ok, f = pcall(io.open, DEBUG_LOG_FILE, "w")
            if ok and f then f:close() end
        end

        local function AttachDebugLog(inst)
            local player = GetPlayer and GetPlayer()
            if not (player and player.HUD and _G.TheFrontEnd and inst:IsValid()) then return false end
            if inst.debug_log_widget then return true end
            local root = (player.HUD.controls and player.HUD.controls.top_root) or player.HUD
            local label = root:AddChild(Text(_G.DEFAULTFONT or "opensans", 20, "WX DEBUG"))
            -- Top-align the text so multi-line output grows downward from the
            -- anchor instead of being centered and clipped at the top edge.
            label:SetHAlign(_G.ANCHOR_LEFT)
            label:SetVAlign(_G.ANCHOR_TOP)
            label:SetPosition(0, -55, 0)
            label:SetHAnchor(_G.ANCHOR_LEFT)
            label:SetVAnchor(_G.ANCHOR_TOP)
            label:SetClickable(false)
            inst.debug_log_widget = label
            inst.debug_log_lines = {}
            inst.debug_log_last = ""

            inst:DoPeriodicTask(0.25, function()
                if not (inst.debug_log_widget and inst.debug_log_widget.inst and inst.debug_log_widget.inst:IsValid()) then
                    inst.debug_log_widget = nil
                    return
                end
                local chain = ""
                if inst.brain and inst.brain.bt and inst.brain.bt.root then
                    chain = RunningChain(inst.brain.bt.root)
                end
                local action_str = "none"
                local loco = inst.components.locomotor
                local ba = loco and loco.bufferedaction
                if ba and ba:IsValid() then
                    local act = ba.action and ba.action.id or "?"
                    local target = ba.target and ba.target.prefab or (ba.pos and "pos" or "?")
                    action_str = string.format("%s %s", act, target)
                end

                local line = string.format("ACT: %s", action_str)
                if line ~= inst.debug_log_last then
                    WriteDebugLog(chain, action_str)
                    table.insert(inst.debug_log_lines, 1, line)
                    if #inst.debug_log_lines > 4 then table.remove(inst.debug_log_lines) end
                    inst.debug_log_last = line
                end

                local lines = {
                    string.format("BT: %s", chain ~= "" and chain or "-"),
                    line,
                }
                for i = math.min(4, #inst.debug_log_lines), 1, -1 do
                    if inst.debug_log_lines[i] ~= line then
                        table.insert(lines, inst.debug_log_lines[i])
                    end
                end
                inst.debug_log_widget:SetString(table.concat(lines, "\n"))
            end)
            return true
        end

        -- Retry attach until HUD is ready (it may not be at t=0).
        local attach_task
        attach_task = inst:DoPeriodicTask(0.5, function()
            if AttachDebugLog(inst) then
                if attach_task and attach_task.Cancel then attach_task:Cancel() end
            end
        end)
    end

    inst.follow_player = true
    inst.harvest_enabled = true
    inst.transfer_to_player = false
    inst.untethered = false
    inst.draw_aggro = false
    inst.pickup_enabled = true
    inst.prioritize_pickup = false
    inst.harvest_radius = 15
    inst.untethered_radius = 60
    inst.target_items = {
        harvest_resources = true,
        harvest_food = true,
        pickup = true,
    }
    for _, category in ipairs(TARGET_CATEGORIES) do
        for _, item in ipairs(category.items) do
            inst.target_items[item.key] = item.default
        end
    end
    inst.target_priority = {}
    for _, key in ipairs(TARGET_PRIORITY) do
        inst.target_priority[#inst.target_priority + 1] = key
    end

    inst:ListenForEvent("itemget", OnItemGet)
    inst:ListenForEvent("itemlose", OnItemLose)
    inst:ListenForEvent("death", OnDeath)
    inst:ListenForEvent("onremove", Cleanup)
    inst.OnSave = OnSave
    inst.OnLoad = OnLoad

    return inst
end

return Prefab("common/wx_companion", fn, assets)
