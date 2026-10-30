require "behaviours/follow"
require "behaviours/faceentity"
require "behaviours/doaction"

local _G = rawget(_G, "GLOBAL") or _G
local TheSim = _G.TheSim
local GetPlayer = _G.GetPlayer
local ACTIONS = _G.ACTIONS
local BufferedAction = _G.BufferedAction
local Vector3 = _G.Vector3
local Logger = require("wx_logger")
local DEFAULT_TARGET_PRIORITY = require("target_priority")
local TARGET_CATEGORIES = require("target_categories")

local MIN_FOLLOW_DIST = 1.5
local TARGET_FOLLOW_DIST = 3
local MAX_FOLLOW_DIST = 6
local CANT_TAGS = { "INLIMBO", "fire", "burnt" }
local DEFAULT_FREE_ROAM_RADIUS = 60

-- Detect player's current work target (chop/mine)
local function GetPlayerWorkTarget(player)
    if not player or not player:IsValid() then return nil, nil end
    
    -- Check if player has the right tool equipped
    local function HasPlayerTool(action)
        local hand = player.components.inventory and player.components.inventory:GetEquippedItem(_G.EQUIPSLOTS.HANDS)
        if hand and hand.components.tool and hand.components.tool:CanDoAction(action) then
            return true
        end
        return false
    end

    local buffered = player.components.locomotor and player.components.locomotor.bufferedaction
    if buffered and buffered.action then
        if buffered.action == ACTIONS.CHOP and buffered.target and buffered.target:IsValid() and HasPlayerTool(ACTIONS.CHOP) then
            return buffered.target, "chop"
        end
        if buffered.action == ACTIONS.MINE and buffered.target and buffered.target:IsValid() and HasPlayerTool(ACTIONS.MINE) then
            return buffered.target, "mine"
        end
    end
    -- Also check SG state tags
    local sg = player.sg
    if sg then
        if sg:HasStateTag("chopping") or sg:HasStateTag("working") then
            -- Try to find what they're working on nearby
            local px, _, pz = player.Transform:GetWorldPosition()
            local ents = TheSim:FindEntities(px, 0, pz, 3, {"workable"}, CANT_TAGS)
            for _, ent in ipairs(ents) do
                if ent.components.workable and ent.components.workable:CanBeWorked() then
                    local act = ent.components.workable:GetWorkAction()
                    if act == ACTIONS.CHOP and HasPlayerTool(ACTIONS.CHOP) then return ent, "chop" end
                    if act == ACTIONS.MINE and HasPlayerTool(ACTIONS.MINE) then return ent, "mine" end
                end
            end
        end
    end
    return nil, nil
end

-- Any entity the player currently has queued as an action target.
-- The companion must not race the player for the same target.
local function GetPlayerTarget(player)
    if not player or not player:IsValid() then return nil end
    local buffered = player.components.locomotor and player.components.locomotor.bufferedaction
    local target = buffered and buffered.target
    if target and target:IsValid() then return target end
    return nil
end

local PLANT_CATEGORIES, ITEM_CATEGORIES = {}, {}
for _, category in ipairs(TARGET_CATEGORIES) do
    for _, item in ipairs(category.items) do
        for _, prefab in ipairs(item.plants or {}) do PLANT_CATEGORIES[prefab] = item.key end
        for _, prefab in ipairs(item.prefabs or {}) do ITEM_CATEGORIES[prefab] = item.key end
    end
end
local WXCompanionBrain = Class(Brain, function(self, inst)
    Brain._ctor(self, inst)
end)

local function GetLeader(inst)
    if not inst.follow_player then return nil end
    local leader = inst.components.follower and inst.components.follower.leader
    if leader and leader:IsValid() then return leader end
    local player = GetPlayer and GetPlayer()
    return (player and player:IsValid()) and player or nil
end

local function FreeRoamRadius(inst)
    return inst.untethered_radius or DEFAULT_FREE_ROAM_RADIUS
end

local function MaxLeashDist(inst)
    if inst.untethered then return FreeRoamRadius(inst) end
    return math.max(10, (inst.harvest_radius or 15) + 2)
end

local function IsInventoryFull(inst)
    local inv = inst.components.inventory
    local cont = inst.components.container
    if not inv and not cont then return false end
    local count = 0
    if inv then
        for _, item in pairs(inv.itemslots) do
            if item then count = count + 1 end
        end
    end
    if cont then
        for s = 1, 15 do -- only storage slots (1-15), not equipment (16-18)
            if cont:GetItemInSlot(s) then count = count + 1 end
        end
    end
    return count >= 15 -- full when all 15 storage slots filled
end

-- Tree-chopping state: stick with one tree until it's down, then collect loot
local function IsTreeChopTarget(inst, target)
    if not target or not target:IsValid() then return false end
    local workable = target.components.workable
    if not workable or not workable:CanBeWorked() then return false end
    local act = workable:GetWorkAction() or workable.action
    return act == ACTIONS.CHOP
end

-- Mining state: stick with one rock/boulder until it's mined out, then collect loot
local function IsMineTarget(inst, target)
    if not target or not target:IsValid() then return false end
    local workable = target.components.workable
    if not workable or not workable:CanBeWorked() then return false end
    local act = workable:GetWorkAction() or workable.action
    return act == ACTIONS.MINE
end

local function FindLootNearby(inst, x, z, radius, avoid)
    local ents = TheSim:FindEntities(x, 0, z, radius or 4, {"inventoryitem"}, CANT_TAGS)
    local best, min_dsq = nil, math.huge
    for _, item in ipairs(ents or {}) do
        if item ~= avoid and item.components.inventoryitem and item.components.inventoryitem.canbepickedup and not item:IsInLimbo() and not item.components.inventoryitem:IsHeld() then
            local ex, _, ez = item.Transform:GetWorldPosition()
            local dsq = (x - ex) * (x - ex) + (z - ez) * (z - ez)
            if dsq < min_dsq then
                min_dsq = dsq
                best = item
            end
        end
    end
    return best
end

local function GetFaceTargetFn(inst)
    local leader = GetLeader(inst)
    return (leader and leader:IsValid()) and leader or nil
end

local function KeepFaceTargetFn(inst, target)
    return target and target:IsValid() and GetLeader(inst) == target
end

local function GetEquippedWeapon(inst)
    local combat = inst.components.combat
    if combat and combat.GetWeapon then
        local weapon = combat:GetWeapon()
        if weapon and weapon:IsValid() then return weapon end
    end
    local inv = inst.components.inventory
    if inv and inv.GetEquippedItem then
        local hands = inv:GetEquippedItem(_G.EQUIPSLOTS.HANDS)
        if hands and hands.components and hands.components.weapon then return hands end
    end
    return nil
end

local function FindAggroTarget(inst)
    if not inst.draw_aggro then return nil end
    local combat = inst.components.combat
    if not combat then return nil end

    local ix, iy, iz = inst.Transform:GetWorldPosition()
    local ents = TheSim:FindEntities(ix, iy, iz, 25, {"hostile"}, CANT_TAGS)
    local best, min_dsq = nil, math.huge
    for _, ent in ipairs(ents or {}) do
        if ent ~= inst and ent:IsValid() and not ent:IsInLimbo() then
            local dead = ent.components.health and ent.components.health.IsDead and ent.components.health:IsDead()
            if not dead and not (inst.failed_until and (inst.failed_until[ent] or 0) > GetTime()) then
                local ex, _, ez = ent.Transform:GetWorldPosition()
                local dsq = (ix - ex) * (ix - ex) + (iz - ez) * (iz - ez)
                if dsq < min_dsq then
                    min_dsq = dsq
                    best = ent
                end
            end
        end
    end
    return best
end

local function GetEquippedTool(inst, action)
    local hand_item = (inst.components.container and inst.components.container:GetItemInSlot(16))
        or (inst.worn and inst.worn[16])
        or (inst.components.inventory and inst.components.inventory:GetEquippedItem(_G.EQUIPSLOTS.HANDS))
    if hand_item and hand_item:IsValid() and hand_item.components.tool and hand_item.components.tool:CanDoAction(action) then
        return hand_item
    end
    return nil
end

local function IsValidTarget(inst, item, targets, axe_tool, pickaxe_tool)
    if not item or not item:IsValid() or item:IsInLimbo() then return false end
    if item:HasTag("fire") or item:HasTag("burnt") or item:HasTag("INLIMBO") or item:HasTag("irreplaceable") then return false end

    -- Global toggles: harvest vs pickup.
    local is_pickup = (item.components.inventoryitem and item.components.inventoryitem.canbepickedup and not item.components.inventoryitem:IsHeld()
        and not item.components.trap and not item.components.pickable and not item.components.workable) or false
    local is_harvest = not is_pickup
    if is_pickup then
        if inst.pickup_enabled == false then return false end
    else
        if inst.harvest_enabled == false then return false end
    end

    local targets = inst.target_items or {}
    if inst.failed_until and (inst.failed_until[item] or 0) > GetTime() then return false end

    local trap = item.components.trap
    if trap then
        if ACTIONS.HARVEST and trap.IsSprung and trap:IsSprung() then
            local key = "harvest_resources"
            if targets[key] == false then return false end
            return true, ACTIONS.HARVEST, nil, key
        end
        return false
    end

    if item.components.pickable and item.components.pickable:CanBePicked() then
        if item:HasTag("flower") or (item.prefab and string.find(item.prefab, "mushroom")) then return false end
        local item_key = PLANT_CATEGORIES[item.prefab]
        local key = (item_key == "berries" or item_key == "carrot" or item_key == "seeds") and "harvest_food" or "harvest_resources"
        if targets[key] == false then return false end
        return true, ACTIONS.PICK, nil, key
    end

    -- Pickup: any item on the floor (except flowers) is eligible.
    if item.components.inventoryitem and item.components.inventoryitem.canbepickedup and not item.components.inventoryitem:IsHeld() then
        if item:HasTag("flower") then return false end
        local key = "pickup"
        if targets[key] == false then return false end
        return true, ACTIONS.PICKUP, nil, key
    end

    -- 3. Chores: woodlogging (axe) and mining (pickaxe)
    if item.components.workable and item.components.workable:CanBeWorked() and not item:HasTag("structure") then
        local act = item.components.workable:GetWorkAction() or item.components.workable.action
        if act == ACTIONS.CHOP and axe_tool then
            local key = "harvest_resources"
            if targets[key] == false then return false end
            return true, ACTIONS.CHOP, axe_tool, key
        end
        if act == ACTIONS.MINE and pickaxe_tool then
            if not item:HasTag("spiderden") and not item:HasTag("cavedr") and not item:HasTag("antlion_sinkhole_blocker") then
                local key = "harvest_resources"
                if targets[key] == false then return false end
                return true, ACTIONS.MINE, pickaxe_tool, key
            end
        end
    end

    return false
end

function WXCompanionBrain:FindHarvestAction()
    if self.inst.harvest_enabled == false then return nil end

    local leader = GetLeader(self.inst)
    local max_dist = MaxLeashDist(self.inst)
    if leader and self.inst:GetDistanceSqToInst(leader) > max_dist * max_dist then return nil end

    -- Never contest whatever the player is already acting on
    local player_target = GetPlayerTarget(leader)

    local radius = self.inst.untethered and FreeRoamRadius(self.inst) or (self.inst.harvest_radius or 15)
    local ix, iy, iz = self.inst.Transform:GetWorldPosition()

    local targets = self.inst.target_items or {}
    local priority = {}
    for rank, key in ipairs(self.inst.target_priority or DEFAULT_TARGET_PRIORITY) do
        if priority[key] == nil then priority[key] = rank end
    end
    local axe_tool = ACTIONS.CHOP and GetEquippedTool(self.inst, ACTIONS.CHOP)
    local pickaxe_tool = ACTIONS.MINE and GetEquippedTool(self.inst, ACTIONS.MINE)

    -- 0. Join player's work target if enabled and we have the tool
    if self.inst.join_player_work and self.inst.harvest_enabled ~= false and leader then
        local work_target, work_type = GetPlayerWorkTarget(leader)
        if work_target then
            local ex, _, ez = work_target.Transform:GetWorldPosition()
            local dsq = (ix - ex) * (ix - ex) + (iz - ez) * (iz - ez)
            if dsq <= radius * radius then
                if work_type == "chop" and axe_tool then
                    Logger.Debug("AI", "Joining player chopping: %s", work_target.prefab or "tree")
                    self.chop_target = work_target
                    self.last_chop_pos = { x = ex, z = ez }
                    self.action_started = GetTime()
                    local buffered = BufferedAction(self.inst, work_target, ACTIONS.CHOP, axe_tool)
                    buffered:AddFailAction(function()
                        Logger.Debug("AI", "Failed join-chop %s, skipping 120s", work_target.prefab or "tree")
                        self.inst.failed_until = self.inst.failed_until or {}
                        self.inst.failed_until[work_target] = GetTime() + 120
                        self.chop_target = nil
                    end)
                    return buffered
                elseif work_type == "mine" and pickaxe_tool then
                    Logger.Debug("AI", "Joining player mining: %s", work_target.prefab or "rock")
                    self.mine_target = work_target
                    self.last_mine_pos = { x = ex, z = ez }
                    self.action_started = GetTime()
                    local buffered = BufferedAction(self.inst, work_target, ACTIONS.MINE, pickaxe_tool)
                    buffered:AddFailAction(function()
                        Logger.Debug("AI", "Failed join-mine %s, skipping 120s", work_target.prefab or "rock")
                        self.inst.failed_until = self.inst.failed_until or {}
                        self.inst.failed_until[work_target] = GetTime() + 120
                        self.mine_target = nil
                    end)
                    return buffered
                end
            end
        end
    end

    -- 1. If we have a chop target, stick with it until it's down
    if self.chop_target and self.chop_target ~= player_target and IsTreeChopTarget(self.inst, self.chop_target) then
        local ex, _, ez = self.chop_target.Transform:GetWorldPosition()
        local dsq = (ix - ex) * (ix - ex) + (iz - ez) * (iz - ez)
        local max_rad_sq = radius * radius
        if dsq <= max_rad_sq then
            local valid, action, tool, key = IsValidTarget(self.inst, self.chop_target, targets, axe_tool, pickaxe_tool)
            if valid and action == ACTIONS.CHOP then
                Logger.Debug("AI", "Continue chopping: %s", self.chop_target.prefab or "tree")
                self.action_started = GetTime()
                local buffered = BufferedAction(self.inst, self.chop_target, ACTIONS.CHOP, axe_tool)
                buffered:AddFailAction(function()
                    Logger.Debug("AI", "Failed chop %s, skipping it for 120s", self.chop_target.prefab or "tree")
                    self.inst.failed_until = self.inst.failed_until or {}
                    self.inst.failed_until[self.chop_target] = GetTime() + 120
                    self.chop_target = nil
                end)
                return buffered
            end
        end
        -- Tree is done or out of range
        self.chop_target = nil
    end

    -- 2. If we have a mine target, stick with it until it's down
    if self.mine_target and self.mine_target ~= player_target and IsMineTarget(self.inst, self.mine_target) then
        local ex, _, ez = self.mine_target.Transform:GetWorldPosition()
        local dsq = (ix - ex) * (ix - ex) + (iz - ez) * (iz - ez)
        local max_rad_sq = radius * radius
        if dsq <= max_rad_sq then
            local valid, action, tool, key = IsValidTarget(self.inst, self.mine_target, targets, axe_tool, pickaxe_tool)
            if valid and action == ACTIONS.MINE then
                Logger.Debug("AI", "Continue mining: %s", self.mine_target.prefab or "rock")
                self.action_started = GetTime()
                local buffered = BufferedAction(self.inst, self.mine_target, ACTIONS.MINE, pickaxe_tool)
                buffered:AddFailAction(function()
                    Logger.Debug("AI", "Failed mine %s, skipping it for 120s", self.mine_target.prefab or "rock")
                    self.inst.failed_until = self.inst.failed_until or {}
                    self.inst.failed_until[self.mine_target] = GetTime() + 120
                    self.mine_target = nil
                end)
                return buffered
            end
        end
        -- Rock is done or out of range
        self.mine_target = nil
    end

    -- 3 & 4. If we just finished chopping or mining, collect nearby loot first
    local last_pos = self.last_chop_pos or self.last_mine_pos
    if last_pos then
        local loot = FindLootNearby(self.inst, last_pos.x, last_pos.z, 4, player_target)
        if loot then
            local ex, _, ez = loot.Transform:GetWorldPosition()
            local dsq = (ix - ex) * (ix - ex) + (iz - ez) * (iz - ez)
            if dsq <= radius * radius then
                Logger.Debug("AI", "Collecting work loot: %s", loot.prefab or "item")
                self.action_started = GetTime()
                local buffered = BufferedAction(self.inst, loot, ACTIONS.PICKUP)
                buffered:AddFailAction(function()
                    self.inst.failed_until = self.inst.failed_until or {}
                    self.inst.failed_until[loot] = GetTime() + 30
                end)
                return buffered
            end
        end
        self.last_chop_pos = nil
        self.last_mine_pos = nil
    end

    -- Consume a pre-queued target before rescanning, to chain actions with no idle gap.
    if self.action_queue and #self.action_queue > 0 then
        while #self.action_queue > 0 do
            local queued = table.remove(self.action_queue, 1)
            if queued and queued.target and queued.target:IsValid() and not (self.inst.failed_until and (self.inst.failed_until[queued.target] or 0) > GetTime()) then
                self.action_started = GetTime()
                return queued
            end
        end
    end

    -- 5. Find next target within harvest radius, then (if idle) a wider seek
    -- radius so the companion goes and does something instead of standing by.
    local seek_radius = math.max(radius, math.min(MaxLeashDist(self.inst), radius * 2))
    local ents = TheSim:FindEntities(ix, iy, iz, seek_radius, nil, CANT_TAGS)

    local function SelectBest(limit_sq, pickup_only)
        local candidates = {}
        for _, ent in ipairs(ents) do
            local ex, _, ez = ent.Transform:GetWorldPosition()
            local dsq = (ix - ex) * (ix - ex) + (iz - ez) * (iz - ez)
            if ent ~= player_target and dsq <= limit_sq then
                local valid, action, tool, key = IsValidTarget(self.inst, ent, targets, axe_tool, pickaxe_tool)
                if valid and pickup_only and action ~= ACTIONS.PICKUP then valid = false end
                local rank = priority[key] or math.huge
                if valid and action == ACTIONS.CHOP then rank = rank - 0.5 end
                if valid and action == ACTIONS.MINE then rank = rank - 0.5 end
                if valid then
                    candidates[#candidates + 1] = { ent = ent, action = action, tool = tool, key = key, rank = rank, dsq = dsq }
                end
            end
        end
        table.sort(candidates, function(a, b)
            -- Queue closest-to-robot targets first for efficient chaining.
            if a.dsq ~= b.dsq then return a.dsq < b.dsq end
            if a.rank ~= b.rank then return a.rank < b.rank end
            return false
        end)
        return candidates
    end

    local candidates
    if self.inst.prioritize_pickup then
        candidates = SelectBest(radius * radius, true)
        if (not candidates or #candidates == 0) and seek_radius > radius then
            candidates = SelectBest(seek_radius * seek_radius, true)
        end
    end
    if not candidates or #candidates == 0 then
        candidates = SelectBest(radius * radius, false)
        if (not candidates or #candidates == 0) and seek_radius > radius then
            candidates = SelectBest(seek_radius * seek_radius, false)
        end
    end

    if candidates and #candidates > 0 then
        -- Queue up to 5 eligible targets to avoid idle gaps between actions.
        self.action_queue = {}
        local limit = math.min(5, #candidates)
        for i = 1, limit do
            local c = candidates[i]
            if c.action == ACTIONS.CHOP and i == 1 then
                self.chop_target = c.ent
                local ex, _, ez = c.ent.Transform:GetWorldPosition()
                self.last_chop_pos = { x = ex, z = ez }
            end
            if c.action == ACTIONS.MINE and i == 1 then
                self.mine_target = c.ent
                local ex, _, ez = c.ent.Transform:GetWorldPosition()
                self.last_mine_pos = { x = ex, z = ez }
            end
            local buffered = BufferedAction(self.inst, c.ent, c.action, c.tool)
            buffered:AddFailAction(function()
                Logger.Debug("AI", "Failed %s, skipping it for 120s", c.ent.prefab or "item")
                self.inst.failed_until = self.inst.failed_until or {}
                self.inst.failed_until[c.ent] = GetTime() + 120
                if c.action == ACTIONS.CHOP then self.chop_target = nil end
                if c.action == ACTIONS.MINE then self.mine_target = nil end
            end)
            self.action_queue[#self.action_queue + 1] = buffered
        end
        Logger.Debug("AI", "Target: %s (%s)", candidates[1].ent.prefab or "item", candidates[1].action.id)
        self.action_started = GetTime()
        return table.remove(self.action_queue, 1)
    end

    self.action_queue = nil
    return nil
end

function WXCompanionBrain:CheckStall()
    if not self.inst or not self.inst:IsValid() then return end
    local da = self.harvest_node
    local loco = self.inst.components.locomotor
    if da and da.status == RUNNING and loco and loco.bufferedaction then
        -- A target that vanished (chopped, picked, despawned) can leave the action
        -- stuck RUNNING. Fail it immediately so the next chore starts now.
        local target = loco.bufferedaction.target
        if target and not target:IsValid() then
            loco.bufferedaction:Fail()
            loco:Clear()
            return
        end

        -- SGwilson's idle state stops the locomotor updater; nothing wakes it while an
        -- action stays buffered, so re-push it to restart the walk.
        local sg = self.inst.sg
        local busy = sg and (sg:HasStateTag("moving") or sg:HasStateTag("busy") or sg:HasStateTag("working"))
        if not busy then
            local x, _, z = self.inst.Transform:GetWorldPosition()
            if self.still_at and math.abs(self.still_at.x - x) < 0.1 and math.abs(self.still_at.z - z) < 0.1 then
                self.still_since = self.still_since or GetTime()
                if GetTime() - self.still_since > 2 then
                    self.still_since = nil
                    self.still_at = { x = x, z = z }
                    loco:PushAction(loco.bufferedaction, true)
                    return
                end
            else
                self.still_at = { x = x, z = z }
                self.still_since = nil
            end
        else
            self.still_since = nil
        end
        if GetTime() - (self.action_started or 0) > 6 then
            loco.bufferedaction:Fail()
            loco:Clear()
        end
    end
end

function WXCompanionBrain:OnStart()
    local harvest_node = DoAction(self.inst, function() return self:FindHarvestAction() end, "AutoHarvest", true)

    -- Return to player when untethered and inventory full
    local return_home_node = DoAction(self.inst, function()
        if not self.inst.untethered then return nil end
        if not IsInventoryFull(self.inst) then return nil end
        local leader = GetLeader(self.inst)
        if not leader or not leader:IsValid() then return nil end
        if self.inst:GetDistanceSqToInst(leader) < 4 then
            -- Docked: transfer storage to player
            if self.inst.TransferStorageToPlayer then
                self.inst:TransferStorageToPlayer()
            end
            return nil
        end
        return BufferedAction(self.inst, leader, ACTIONS.WALKTO)
    end, "ReturnHome", true)

    local root = PriorityNode({
        -- 1. Draw aggro: attack nearby hostiles before anything else
        DoAction(self.inst, function()
            local target = FindAggroTarget(self.inst)
            if not target then return nil end
            return BufferedAction(self.inst, target, ACTIONS.ATTACK, GetEquippedWeapon(self.inst))
        end, "Aggro", true),

        -- 2. Return home when untethered and inventory full
        return_home_node,

        -- 3. Leash boundary: return if separated beyond harvest perimeter
        Follow(self.inst, function()
            if self.action_queue and #self.action_queue > 0 then return nil end
            local leader = GetLeader(self.inst)
            if not leader then return nil end
            local max_dist = MaxLeashDist(self.inst)
            local act = harvest_node.action
            if harvest_node.status == RUNNING and act and act.target and act.target:IsValid() and leader:GetDistanceSqToInst(act.target) <= max_dist * max_dist then return nil end
            return (self.inst:GetDistanceSqToInst(leader) > max_dist * max_dist) and leader or nil
        end, 2, 4, 10),

        -- 4. Auto-harvest nearby resources
        harvest_node,

        -- 5. Idle retrigger: shuffle a few metres so a stalled companion keeps
        -- moving and re-scans, instead of standing by indefinitely.
        DoAction(self.inst, function()
            if self.inst.harvest_enabled == false and self.inst.pickup_enabled == false then return nil end
            local leader = GetLeader(self.inst)
            if leader and self.inst:GetDistanceSqToInst(leader) > MAX_FOLLOW_DIST * MAX_FOLLOW_DIST then
                return nil -- let the follow node handle it
            end
            -- Don't wander while the player is sailing; stay on the boat.
            local driver = leader and leader.components.driver
            if driver and driver.GetIsDriving and driver:GetIsDriving() then return nil end
            local now = GetTime()
            if self.next_wander and now < self.next_wander then return nil end
            self.next_wander = now + 3

            local ix, iy, iz = self.inst.Transform:GetWorldPosition()
            local angle = math.random() * math.pi * 2
            local dist = 2 + math.random() * 3
            local tx, tz = ix + math.cos(angle) * dist, iz + math.sin(angle) * dist
            return BufferedAction(self.inst, nil, ACTIONS.WALKTO, nil, Vector3(tx, iy, tz), nil, 0.2)
        end, "IdleWander", true),

        -- 6. Follow player when moving away (only if not untethered, or if untethered but not full)
        Follow(self.inst, function()
            if self.action_queue and #self.action_queue > 0 then return nil end
            if self.inst.untethered and IsInventoryFull(self.inst) then return nil end
            local leader = GetLeader(self.inst)
            -- Don't tether/follow when the player is already within harvest
            -- radius; harvesting is more efficient than chasing.
            if leader and leader:IsValid() and self.inst:GetDistanceSqToInst(leader) <= (self.inst.harvest_radius or 15) ^ 2 then
                return nil
            end
            return leader
        end, MIN_FOLLOW_DIST, TARGET_FOLLOW_DIST, MAX_FOLLOW_DIST),

        -- 7. Fixed standing position: stationary in player's vicinity facing player
        FaceEntity(self.inst, GetFaceTargetFn, KeepFaceTargetFn),
    }, 0.25)

    local BT = _G.BT or BT
    self.bt = BT(self.inst, root)
    self.harvest_node = harvest_node

    self.inst:DoPeriodicTask(1, function() self:CheckStall() end)

    -- Shipwrecked: hop onto the player's boat so it keeps following while sailing.
    self.inst:DoPeriodicTask(1, function()
        if not self.inst:IsValid() then return end
        local leader = GetLeader(self.inst)
        if not leader or not leader:IsValid() then return end
        local driver = leader.components.driver
        if not (driver and driver.GetIsDriving and driver:GetIsDriving()) then return end
        local lx, ly, lz = leader.Transform:GetWorldPosition()
        local ix, _, iz = self.inst.Transform:GetWorldPosition()
        if (ix - lx) * (ix - lx) + (iz - lz) * (iz - lz) > 1 then
            local x, z = lx + 0.8, lz
            if self.inst.Physics and self.inst.Physics.Teleport then
                self.inst.Physics:Teleport(x, ly, z)
            else
                self.inst.Transform:SetPosition(x, ly, z)
            end
        end
    end)
end

return WXCompanionBrain
