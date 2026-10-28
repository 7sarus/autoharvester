require "behaviours/follow"
require "behaviours/faceentity"
require "behaviours/doaction"

local _G = rawget(_G, "GLOBAL") or _G
local TheSim = _G.TheSim
local GetPlayer = _G.GetPlayer
local ACTIONS = _G.ACTIONS
local BufferedAction = _G.BufferedAction
local Logger = require("wx_logger")

local MIN_FOLLOW_DIST = 1.5
local TARGET_FOLLOW_DIST = 3
local MAX_FOLLOW_DIST = 6

local WXCompanionBrain = Class(Brain, function(self, inst)
    Brain._ctor(self, inst)
end)

local function GetLeader(inst)
    if not inst.follow_player then return nil end
    local player = GetPlayer and GetPlayer()
    return (player and player:IsValid()) and player or nil
end

local function MaxLeashDist(inst)
    return math.max(10, (inst.harvest_radius or 15) + 2)
end

local function GetFaceTargetFn(inst)
    local leader = GetLeader(inst)
    return (leader and leader:IsValid()) and leader or nil
end

local function KeepFaceTargetFn(inst, target)
    return target and target:IsValid() and GetLeader(inst) == target
end

local function IsValidTarget(inst, item, px, pz, max_rad_sq)
    if not item or not item:IsValid() or item:IsInLimbo() then return false end
    if item:HasTag("fire") or item:HasTag("burnt") or item:HasTag("INLIMBO") then return false end
    if inst.failed_until and (inst.failed_until[item] or 0) > GetTime() then return false end

    local ix, _, iz = item.Transform:GetWorldPosition()
    if (px - ix) * (px - ix) + (pz - iz) * (pz - iz) > max_rad_sq then return false end

    local targets = inst.target_items or {}

    if item.components.pickable and item.components.pickable:CanBePicked() then
        if targets.twigs and item.prefab == "sapling" then return true, ACTIONS.PICK end
        if targets.cutgrass and item.prefab == "grass" then return true, ACTIONS.PICK end
        if targets.berries and (item.prefab == "berrybush" or item.prefab == "berrybush2") then return true, ACTIONS.PICK end
        if targets.carrot and item.prefab == "carrot_planted" then return true, ACTIONS.PICK end
        if targets.misc and not item:HasTag("irreplaceable") then return true, ACTIONS.PICK end
    end

    if item.components.inventoryitem and item.components.inventoryitem.canbepickedup and not item.components.inventoryitem:IsHeld() then
        if targets.twigs and item.prefab == "twigs" then return true, ACTIONS.PICKUP end
        if targets.cutgrass and item.prefab == "cutgrass" then return true, ACTIONS.PICKUP end
        if targets.log and item.prefab == "log" then return true, ACTIONS.PICKUP end
        if targets.seeds and (item.prefab == "seeds" or string.find(item.prefab, "_seeds")) then return true, ACTIONS.PICKUP end
        if targets.berries and item.prefab == "berries" then return true, ACTIONS.PICKUP end
        if targets.carrot and item.prefab == "carrot" then return true, ACTIONS.PICKUP end
        if targets.flint and item.prefab == "flint" then return true, ACTIONS.PICKUP end
        if targets.rocks and item.prefab == "rocks" then return true, ACTIONS.PICKUP end
        if targets.goldnugget and item.prefab == "goldnugget" then return true, ACTIONS.PICKUP end
        if targets.nitre and item.prefab == "nitre" then return true, ACTIONS.PICKUP end

        -- Other loot: pinecones, coconuts, manure and similar loose items, never gear
        if targets.misc then
            local c = item.components
            local isgear = c.equippable ~= nil or c.weapon ~= nil or c.tool ~= nil
                or c.armor ~= nil or c.finiteuses ~= nil or c.fueled ~= nil
            if not isgear and not item:HasTag("irreplaceable") then return true, ACTIONS.PICKUP end
        end
    end

    return false
end

function WXCompanionBrain:FindHarvestAction()
    if self.inst.harvest_enabled == false then return nil end

    local leader = GetLeader(self.inst)
    if leader and self.inst:GetDistanceSqToInst(leader) > MaxLeashDist(self.inst) ^ 2 then return nil end

    local radius = self.inst.harvest_radius or 15
    local ix, iy, iz = self.inst.Transform:GetWorldPosition()
    local ents = TheSim:FindEntities(ix, iy, iz, radius, nil, { "INLIMBO", "fire", "burnt" })

    local best_target, best_action, min_dist_sq = nil, nil, math.huge
    local max_rad_sq = radius * radius

    for _, ent in ipairs(ents) do
        local valid, action = IsValidTarget(self.inst, ent, ix, iz, max_rad_sq)
        if valid then
            local ex, _, ez = ent.Transform:GetWorldPosition()
            local dsq = (ix - ex) * (ix - ex) + (iz - ez) * (iz - ez)
            if dsq < min_dist_sq then
                min_dist_sq = dsq
                best_target = ent
                best_action = action
            end
        end
    end

    if best_target and best_action then
        Logger.Debug("AI", "Target: %s (%s)", best_target.prefab or "item", best_action.id)
        self.action_started = GetTime()
        local buffered = BufferedAction(self.inst, best_target, best_action)
        buffered:AddFailAction(function()
            Logger.Debug("AI", "Failed %s, skipping it for 120s", best_target.prefab or "item")
            self.inst.failed_until = self.inst.failed_until or {}
            self.inst.failed_until[best_target] = GetTime() + 120
        end)
        return buffered
    end

    return nil
end

function WXCompanionBrain:CheckStall()
    local da = self.harvest_node
    local loco = self.inst.components.locomotor
    if da.status == RUNNING and loco.bufferedaction then
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
        if GetTime() - (self.action_started or 0) > 25 then
            loco.bufferedaction:Fail()
            loco:Clear()
        end
    end
end

function WXCompanionBrain:OnStart()
    local harvest_node = DoAction(self.inst, function() return self:FindHarvestAction() end, "AutoHarvest", true)

    local root = PriorityNode({
        -- 1. Leash boundary: return if separated beyond harvest perimeter
        Follow(self.inst, function()
            local leader = GetLeader(self.inst)
            if not leader then return nil end
            local max_dist = MaxLeashDist(self.inst)
            local act = harvest_node.action
            if harvest_node.status == RUNNING and act and act.target and act.target:IsValid() and leader:GetDistanceSqToInst(act.target) <= max_dist * max_dist then return nil end
            return (self.inst:GetDistanceSqToInst(leader) > max_dist * max_dist) and leader or nil
        end, 2, 4, 10),

        -- 2. Auto-harvest nearby resources
        harvest_node,

        -- 3. Follow player when moving away
        Follow(self.inst, function() return GetLeader(self.inst) end, MIN_FOLLOW_DIST, TARGET_FOLLOW_DIST, MAX_FOLLOW_DIST),

        -- 4. Fixed standing position: stationary in player's vicinity facing player
        FaceEntity(self.inst, GetFaceTargetFn, KeepFaceTargetFn),
    }, 0.25)

    local BT = _G.BT or BT
    self.bt = BT(self.inst, root)
    self.harvest_node = harvest_node

    self.inst:DoPeriodicTask(2, function() self:CheckStall() end)
end

return WXCompanionBrain
