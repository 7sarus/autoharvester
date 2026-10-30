-- Automated offline test suite for WX-78 Auto-Harvester Mod
local function assert_ok(name, fn)
    io.write(string.format("Testing %-45s ", name .. "..."))
    local status, err = pcall(fn)
    if status then
        print("[PASS]")
    else
        print("[FAIL]")
        error(err)
    end
end

-- 1. Locate repository root and game environment paths dynamically
local function get_repo_root()
    local info = debug.getinfo(1, "S")
    if info and info.source and info.source:sub(1, 1) == "@" then
        local script_path = info.source:sub(2)
        local root = script_path:match("^(.*)[/\\]tests[/\\][^/\\]+$")
        if root and root ~= "" then return root end
    end
    return "."
end

local REPO_ROOT = get_repo_root()

local function resolve_game_scripts()
    local env_candidates = {
        os.getenv("DONT_STARVE_SCRIPTS_DIR"),
        os.getenv("DONT_STARVE_DATA_DIR") and (os.getenv("DONT_STARVE_DATA_DIR") .. "/scripts"),
        os.getenv("DONT_STARVE_DIR") and (os.getenv("DONT_STARVE_DIR") .. "/data/scripts"),
        os.getenv("DONT_STARVE_DIR") and (os.getenv("DONT_STARVE_DIR") .. "/game/data/scripts"),
    }
    for _, dir in ipairs(env_candidates) do
        if dir and dir ~= "" then
            local f = io.open(dir .. "/class.lua", "r")
            if f then f:close(); return dir end
        end
    end

    local home = os.getenv("HOME") or os.getenv("USERPROFILE") or ""
    if home ~= "" then
        local candidates = {
            home .. "/Games/gog/dont-starve/game/data/scripts",
            home .. "/.local/share/Steam/steamapps/common/dont_starve/data/scripts",
            home .. "/.steam/steam/steamapps/common/dont_starve/data/scripts",
            home .. "/.steam/root/steamapps/common/dont_starve/data/scripts",
            home .. "/Library/Application Support/Steam/steamapps/common/dont_starve/data/scripts",
        }
        for _, dir in ipairs(candidates) do
            local f = io.open(dir .. "/class.lua", "r")
            if f then f:close(); return dir end
        end
    end
    return nil
end

local game_scripts = resolve_game_scripts()

package.path = string.format("%s/wx_autoharvester/scripts/?.lua;%s/wx_autoharvester/scripts/?/init.lua;", REPO_ROOT, REPO_ROOT)
    .. (game_scripts and (game_scripts .. "/?.lua;") or "")
    .. package.path

_G.GLOBAL = _G

if game_scripts and io.open(game_scripts .. "/class.lua", "r") then
    dofile(game_scripts .. "/class.lua")
    require("brain")
    require("behaviourtree")
    require("vector3")
else
    -- Fallback self-contained definitions if game files are absent (e.g. CI environments)
    if not _G.Class then
        function _G.Class(base, _ctor)
            local c = {}
            if not _ctor and type(base) == "function" then
                _ctor = base
                base = nil
            end
            c._ctor = _ctor
            c.__index = c
            local mt = {
                __index = base,
                __call = function(cls, ...)
                    local inst = setmetatable({}, cls)
                    if cls._ctor then cls._ctor(inst, ...) end
                    return inst
                end
            }
            return setmetatable(c, mt)
        end
    end
    if not _G.Brain then
        _G.Brain = Class(function(self, inst) self.inst = inst end)
    end
    if not _G.BehaviourTree then
        _G.BehaviourTree = Class(function(self, inst, root) self.inst = inst; self.root = root end)
    end
    if not _G.Vector3 then
        _G.Vector3 = Class(function(self, x, y, z)
            self.x = x or 0
            self.y = y or 0
            self.z = z or 0
        end)
        function Vector3:DistSq(other)
            local dx = self.x - (other.x or 0)
            local dy = self.y - (other.y or 0)
            local dz = self.z - (other.z or 0)
            return dx*dx + dy*dy + dz*dz
        end
        function Vector3:Dist(other) return math.sqrt(self:DistSq(other)) end
    end
    _G.PriorityNode = _G.PriorityNode or Class(function(self, children, period) self.children = children end)
    _G.Follow = _G.Follow or Class(function(self, inst, leader, min, max, target) end)
    _G.FaceEntity = _G.FaceEntity or Class(function(self, inst, getfn, canfn) end)
    _G.DoAction = _G.DoAction or Class(function(self, inst, fn, name) self.actionfn = fn end)
    package.preload["behaviours/follow"] = package.preload["behaviours/follow"] or function() end
    package.preload["behaviours/faceentity"] = package.preload["behaviours/faceentity"] or function() end
    package.preload["behaviours/doaction"] = package.preload["behaviours/doaction"] or function() end
end

-- 2. Game Constants & Global APIs
_G.TUNING = {
    WILSON_HEALTH = 150,
    CALORIES_MED = 50,
    HUNGRY_THRESH = 0.33,
    SANITY_DAY_GAIN = 1,
}
_G.ACTIONS = {
    PICK = { id = "PICK" },
    PICKUP = { id = "PICKUP" },
    HARVEST = { id = "HARVEST" },
    CHOP = { id = "CHOP" },
    MINE = { id = "MINE" },
    ATTACK = { id = "ATTACK" },
    WALKTO = { id = "WALKTO" },
}
_G.EQUIPSLOTS = { HANDS = "hands", HEAD = "head", BODY = "body" }
local now = 0
_G.GetTime = function() return now end
_G.BufferedAction = function(doer, target, action, invobject)
    return {
        doer = doer, target = target, action = action, invobject = invobject,
        AddSuccessAction = function(self, fn) self.onsuccess = fn end,
        AddFailAction = function(self, fn) self.onfail = fn end,
    }
end
_G.ANCHOR_RIGHT = 1
_G.ANCHOR_MIDDLE = 2
_G.ANCHOR_LEFT = 3
_G.DEFAULTFONT = "opensans"
_G.BODYTEXTFONT = "opensans"
_G.BUTTONFONT = "opensans"
_G.TITLEFONT = "opensans"
_G.UIFONT = "opensans"
_G.ANIM_ORIENTATION = { OnGround = 1, Billboard = 0 }
_G.LAYER_BACKGROUND = 1
_G.KEY_H = 104

function _G.Asset(type, file) return { type = type, file = file } end
function _G.Prefab(name, fn, assets) return { name = name, fn = fn, assets = assets } end
function _G.GetModConfigData(k) return nil end
_G.AddSimPostInit = function(fn) end
local postconstructs = {}
_G.AddClassPostConstruct = function(pkg, fn)
    postconstructs[pkg] = postconstructs[pkg] or {}
    table.insert(postconstructs[pkg], fn)
end

local listeners = {}
function _G.CreateEntity()
    local e = {
        components = {},
        tags = {},
        entity = {
            AddTransform = function() end,
            AddAnimState = function() end,
            AddSoundEmitter = function() end,
            AddDynamicShadow = function() end,
            AddLightWatcher = function() end,
            SetParent = function() end,
            Hide = function() end,
            Show = function() end,
        },
        Transform = {
            SetFourFaced = function() end,
            SetScale = function() end,
            SetPosition = function() end,
            GetWorldPosition = function() return 0, 0, 0 end,
        },
        AnimState = {
            SetBank = function() end,
            SetBuild = function() end,
            PlayAnimation = function() end,
            SetOrientation = function() end,
            SetLayer = function() end,
            SetSortOrder = function() end,
        },
        DynamicShadow = { SetSize = function() end },
        SoundEmitter = { PlaySound = function() end },
        LightWatcher = { GetLightValue = function() return 1 end },
        Physics = { Teleport = function() end },
    }
    function e:IsValid() return true end
    function e:AddTag(t) self.tags[t] = true end
    function e:HasTag(t) return self.tags[t] == true end
    function e:RemoveTag(t) self.tags[t] = nil end
    function e:AddComponent(name)
        self.components[name] = { inst = self }
        if name == "health" then
            self.components.health.SetMaxHealth = function() end
            self.components.health.SetInvincible = function() end
            self.components.health.IsDead = function() return false end
        elseif name == "inventory" then
            self.components.inventory.itemslots = {}
            self.components.inventory.equipslots = {}
            self.components.inventory.GetEquippedItem = function(inv, eslot) return inv.equipslots[eslot] end
            self.components.inventory.GiveItem = function(self, item) return true end
            self.components.inventory.RemoveItem = function(self, item) end
        elseif name == "workable" then
            self.components.workable.action = _G.ACTIONS.CHOP
            self.components.workable.workleft = 5
            self.components.workable.CanBeWorked = function(w) return (w.workleft or 0) > 0 end
            self.components.workable.GetWorkAction = function(w) return w.action end
            self.components.workable.SetWorkAction = function(w, act) w.action = act end
        elseif name == "tool" then
            self.components.tool.actions = {}
            self.components.tool.CanDoAction = function(t, act) return t.actions[act] == true end
            self.components.tool.SetAction = function(t, act) t.actions[act] = true end
        elseif name == "locomotor" then
            self.components.locomotor.walkspeed = 6
            self.components.locomotor.runspeed = 9
            self.components.locomotor.WantsToMoveForward = function() return false end
            self.components.locomotor.WantsToRun = function() return false end
        elseif name == "follower" then
            self.components.follower.SetLeader = function() end
        elseif name == "rider" then
            self.components.rider.IsRiding = function() return false end
            self.components.rider.GetSaddle = function() return nil end
        elseif name == "combat" then
            self.components.combat.GetWeapon = function() return nil end
            self.components.combat.SetDefaultDamage = function() end
            self.components.combat.SetAttackPeriod = function() end
            self.components.combat.SetRange = function() end
        elseif name == "talker" then
            self.components.talker.Say = function() end
        elseif name == "freezable" then
            self.components.freezable.IsFrozen = function() return false end
            self.components.freezable.Unfreeze = function() end
        elseif name == "pinnable" then
            self.components.pinnable.IsStuck = function() return false end
            self.components.pinnable.Unstick = function() end
        elseif name == "container" then
            self.components.container.slots = {}
            self.components.container.numslots = 18
            self.components.container.acceptsstacks = true
            self.components.container.SetNumSlots = function(c, n) c.numslots = n end
            self.components.container.GiveItem = function(c, item, slot) if slot then c.slots[slot] = item else table.insert(c.slots, item) end return true end
            self.components.container.GetItemInSlot = function(c, slot) return c.slots[slot] end
            self.components.container.Open = function(c, doer) c.open = true end
            self.components.container.Close = function(c) c.open = false end
            self.components.container.IsOpen = function(c) return c.open == true end
            self.components.container.RemoveItemBySlot = function(c, slot)
                local item = c.slots[slot]
                c.slots[slot] = nil
                return item
            end
            self.components.container.DropEverything = function(c)
                c.dropped_everything = true
                for k in pairs(c.slots) do c.slots[k] = nil end
            end
        end
        return self.components[name]
    end
    function e:ListenForEvent(ev, fn)
        listeners[ev] = listeners[ev] or {}
        table.insert(listeners[ev], fn)
    end
    function e:PushEvent(ev, data)
        for _, fn in ipairs(listeners[ev] or {}) do fn(self, data) end
    end
    function e:DoTaskInTime(t, fn) fn(self) end
    function e:DoPeriodicTask() end
    function e:SetStateGraph() end
    function e:SetBrain() end
    function e:Show() end
    function e:Hide() end
    function e:Remove() self.removed = true end
    return e
end

function _G.MakeCharacterPhysics() end
function _G.MakeGhostPhysics() end
function _G.MakeInventoryPhysics() end
_G.TheSim = {
    FindEntities = function() return {} end,
}
_G.TheInput = {
    AddKeyUpHandler = function() end,
}

local player_inst = _G.CreateEntity()
player_inst:AddComponent("inventory")
function _G.GetPlayer() return player_inst end

_G.__spawned_prefabs = {}
function _G.SpawnPrefab(name)
    table.insert(_G.__spawned_prefabs, name)
    if name == "robot_egg" then
        local egg_def = dofile(REPO_ROOT .. "/wx_autoharvester/scripts/prefabs/robot_egg.lua")
        local egg = egg_def.fn()
        egg.prefab = name
        return egg
    elseif name == "wx_companion" then
        local comp_def = dofile(REPO_ROOT .. "/wx_autoharvester/scripts/prefabs/wx_companion.lua")
        local comp = comp_def.fn()
        comp.prefab = name
        return comp
    end
    local e = CreateEntity()
    e.prefab = name
    return e
end

local Widget = Class(function(self, name)
    self.name = name
    self.children = {}
    self.shown = true
end)
function Widget:AddChild(child) table.insert(self.children, child) return child end
function Widget:SetPosition() end
function Widget:SetScale() end
function Widget:SetHAnchor() end
function Widget:SetVAnchor() end
function Widget:MoveToBack() end
function Widget:MoveToFront() end
function Widget:Show() self.shown = true end
function Widget:Hide() self.shown = false end

package.preload["widgets/widget"] = function() return Widget end
package.preload["widgets/image"] = function()
    local Image = Class(Widget, function(self, atlas, tex) Widget._ctor(self, "Image") self.tex = tex end)
    function Image:ScaleToSize(w, h) end
    function Image:SetTint(r, g, b, a) self.tint = { r, g, b, a } end
    return Image
end
package.preload["widgets/text"] = function()
    local Text = Class(Widget, function(self, font, size, text)
        Widget._ctor(self, "Text")
        self.string = text
    end)
    function Text:SetHAlign() end
    function Text:SetColour() end
    function Text:SetString(value) self.string = value end
    function Text:SetRegionSize() end
    return Text
end
package.preload["widgets/imagebutton"] = function()
    local ImageButton = Class(Widget, function(self, atlas, img1, img2)
        Widget._ctor(self, "ImageButton")
        self.image = { ScaleToSize = function() end, SetTint = function() end, SetTexture = function() end }
    end)
    function ImageButton:SetTextures() end
    function ImageButton:SetScale() end
    function ImageButton:SetPosition() end
    function ImageButton:SetText() end
    function ImageButton:SetTextSize() end
    function ImageButton:SetOnClick(fn) self.onclick = fn end
    return ImageButton
end

print("=== WX-78 Auto-Harvester Mod Automated Harness ===")

assert_ok("Logger module loads cleanly", function()
    local logger = require("wx_logger")
    logger.Info("TEST", "Logger operational")
end)

assert_ok("Brain module loads cleanly", function()
    local brain_class = require("brains/wx_companionbrain")
    local inst = CreateEntity()
    inst:AddComponent("follower")
    local b = brain_class(inst)
    b.inst = inst
    _G.PriorityNode = Class(function(self, children, period) self.children = children end)
    _G.BT = Class(function(self, inst, root) self.inst = inst self.root = root end)
    _G.Follow = function() return {} end
    _G.DoAction = function() return {} end
    b:OnStart()
    assert(b.bt, "BT instance was not created")
end)

assert_ok("Range ring prefab creates without crash", function()
    local ring_def = dofile(REPO_ROOT .. "/wx_autoharvester/scripts/prefabs/harvest_range_ring.lua")
    local ring = ring_def.fn()
    assert(ring.SetRadius, "SetRadius missing")
    ring:SetRadius(20)
end)

assert_ok("WX Companion prefab spawns & initializes", function()
    local comp_def = dofile(REPO_ROOT .. "/wx_autoharvester/scripts/prefabs/wx_companion.lua")
    local comp = comp_def.fn()
    assert(comp.components.sanity:IsSane() == true, "sanity.IsSane failed")
    assert(comp.components.sanity:IsCrazy() == false, "sanity.IsCrazy failed")
    assert(comp.components.sanity.DoDelta, "sanity.DoDelta missing")
    comp.components.sanity:DoDelta(5)
    assert(comp.components.hunger:GetPercent() == 1, "hunger.GetPercent failed")
    assert(comp.components.hunger.DoDelta, "hunger.DoDelta missing")
    comp.components.hunger:DoDelta(-5)
    assert(comp.components.temperature:GetCurrent() == 30, "temperature.GetCurrent failed")
    assert(comp.components.temperature.DoDelta, "temperature.DoDelta missing")
    comp.components.temperature:DoDelta(1)
    assert(comp.components.playercontroller.Enable, "playercontroller stub failed")
    for _, name in ipairs({ "poisonable", "eater", "bundler", "hayfever", "grogginess", "beaverness" }) do
        assert(comp.components[name], "SGwilson stub missing: " .. name)
    end
    assert(comp.components.poisonable:IsPoisoned() == false, "poisonable should always return not poisoned")
    assert(comp.components.eater:CanEat() == false, "eater should always return false")
    assert(comp.components.container and comp.components.container.numslots == 18, "1x15+equip container failed")
end)

assert_ok("HarvesterUI widget instantiates cleanly", function()
    local HarvesterUI = require("widgets/harvester_ui")
    local comp_def = dofile(REPO_ROOT .. "/wx_autoharvester/scripts/prefabs/wx_companion.lua")
    local comp = comp_def.fn()
    player_inst.wx_companion = comp
    local ui = HarvesterUI(player_inst, 15)
    assert(ui.radius_index == 2, "Default radius mismatch")
    assert(comp.target_items.twigs == true, "Default twigs target should be true")
    assert(comp.target_items.log == true, "Default log target should be true")
    assert(comp.target_items.seeds == true, "Default seeds target should be true")
    assert(comp.target_items.flint == false, "Default flint target should be false")

    comp.target_items.seeds = false
    ui = HarvesterUI(player_inst, 15)
    local function FindSavedSeeds(node)
        if node.name == "checkbox_row" and node.label and node.label.string and node.label.string:find("Seeds") then return node end
        for _, child in ipairs(node.children or {}) do
            local found = FindSavedSeeds(child)
            if found then return found end
        end
    end
    local seeds = FindSavedSeeds(ui)
    assert(seeds and not seeds:IsChecked(), "saved unchecked item was shown as enabled")
end)

assert_ok("Brain skips failed target for 120s, then retries", function()
    local brain_class = require("brains/wx_companionbrain")
    local inst = CreateEntity()
    inst.Transform.GetWorldPosition = function() return 0, 0, 0 end
    inst.target_items = { log = true }
    inst.harvest_enabled = true
    local log = CreateEntity()
    log.prefab = "log"
    log.IsInLimbo = function() return false end
    log.Transform.GetWorldPosition = function() return 1, 0, 1 end
    log:AddComponent("inventoryitem")
    log.components.inventoryitem.canbepickedup = true
    log.components.inventoryitem.IsHeld = function() return false end
    local saved_find = TheSim.FindEntities
    TheSim.FindEntities = function() return { log } end
    local b = brain_class(inst)
    b.inst = inst

    now = 0
    local action = b:FindHarvestAction()
    assert(action, "log should be targeted first")
    action.onfail()
    now = 10
    assert(b:FindHarvestAction() == nil, "failed log should be skipped within 120s")
    now = 121
    assert(b:FindHarvestAction(), "failed log should be retried after 120s")
    TheSim.FindEntities = saved_find
end)

assert_ok("Gear category picks up loose weapons and tools", function()
    local brain_class = require("brains/wx_companionbrain")
    local inst = CreateEntity()
    inst.Transform.GetWorldPosition = function() return 0, 0, 0 end
    inst.target_items = { gear = true }
    inst.harvest_enabled = true

    local spear = CreateEntity()
    spear.prefab = "spear"
    spear.IsInLimbo = function() return false end
    spear.Transform.GetWorldPosition = function() return 1, 0, 1 end
    spear:AddComponent("inventoryitem")
    spear.components.inventoryitem.canbepickedup = true
    spear.components.inventoryitem.IsHeld = function() return false end
    spear.components.weapon = {}
    spear.components.equippable = {}

    local saved_find = TheSim.FindEntities
    TheSim.FindEntities = function() return { spear } end
    local b = brain_class(inst)
    b.inst = inst
    local action = b:FindHarvestAction()
    assert(action, "spear was not targeted")
    assert(action.target == spear, "companion did not target the dropped weapon")
    TheSim.FindEntities = saved_find
end)

assert_ok("Harvest target priority beats distance", function()
    local brain_class = require("brains/wx_companionbrain")
    local inst = CreateEntity()
    inst.Transform.GetWorldPosition = function() return 0, 0, 0 end
    inst.harvest_enabled = true
    inst.pickup_enabled = true

    local function make_item(name, distance)
        local item = CreateEntity()
        item.prefab = name
        item.IsInLimbo = function() return false end
        item.Transform.GetWorldPosition = function() return distance, 0, 0 end
        item:AddComponent("inventoryitem")
        item.components.inventoryitem.canbepickedup = true
        item.components.inventoryitem.IsHeld = function() return false end
        return item
    end
    local near_log, far_misc = make_item("log", 1), make_item("spear", 8)
    local saved_find = TheSim.FindEntities
    TheSim.FindEntities = function() return { near_log, far_misc } end

    local b = brain_class(inst)
    b.inst = inst
    assert(b:FindHarvestAction().target == near_log, "nearer loot should be picked first when priorities are removed")
    TheSim.FindEntities = saved_find
end)

assert_ok("Companion ignores targets the player is already acting on", function()
    local brain_class = require("brains/wx_companionbrain")
    local inst = CreateEntity()
    inst.Transform.GetWorldPosition = function() return 0, 0, 0 end
    inst.GetDistanceSqToInst = function() return 0 end
    inst.target_items = { log = true }
    inst.harvest_enabled = true
    inst.follow_player = true
    inst:AddComponent("follower")

    local player = CreateEntity()
    player:AddComponent("locomotor")

    local function make_log(distance)
        local item = CreateEntity()
        item.prefab = "log"
        item.IsInLimbo = function() return false end
        item.Transform.GetWorldPosition = function() return distance, 0, 0 end
        item:AddComponent("inventoryitem")
        item.components.inventoryitem.canbepickedup = true
        item.components.inventoryitem.IsHeld = function() return false end
        return item
    end
    local near_log, far_log = make_log(1), make_log(5)
    inst.components.follower.leader = player
    player.components.locomotor.bufferedaction = { action = ACTIONS.PICKUP, target = near_log }

    local saved_find = TheSim.FindEntities
    TheSim.FindEntities = function() return { near_log, far_log } end
    local b = brain_class(inst)
    b.inst = inst
    local action = b:FindHarvestAction()
    assert(action and action.target == far_log, "companion should skip the log the player is picking up")
    TheSim.FindEntities = saved_find
end)

assert_ok("Companion ignores a tree the player is chopping", function()
    local brain_class = require("brains/wx_companionbrain")
    local inst = CreateEntity()
    inst.Transform.GetWorldPosition = function() return 0, 0, 0 end
    inst.GetDistanceSqToInst = function() return 0 end
    inst.target_items = { log = true }
    inst.harvest_enabled = true
    inst.follow_player = true
    inst:AddComponent("follower")
    inst:AddComponent("container")

    local axe = CreateEntity()
    axe.prefab = "axe"
    axe:AddComponent("tool")
    axe.components.tool:SetAction(_G.ACTIONS.CHOP)
    inst.components.container.slots[16] = axe

    local player = CreateEntity()
    player:AddComponent("locomotor")

    local function make_tree(distance)
        local t = CreateEntity()
        t.prefab = "evergreen"
        t.IsInLimbo = function() return false end
        t.Transform.GetWorldPosition = function() return distance, 0, 0 end
        t:AddComponent("workable")
        t.components.workable:SetWorkAction(_G.ACTIONS.CHOP)
        return t
    end
    local near_tree, far_tree = make_tree(1), make_tree(4)
    inst.components.follower.leader = player
    player.components.locomotor.bufferedaction = { action = ACTIONS.CHOP, target = near_tree }

    local saved_find = TheSim.FindEntities
    TheSim.FindEntities = function() return { near_tree, far_tree } end
    local b = brain_class(inst)
    b.inst = inst
    local action = b:FindHarvestAction()
    assert(action and action.target == far_tree, "companion should leave the player's tree alone and chop another")
    TheSim.FindEntities = saved_find
end)

assert_ok("Only caught traps are harvested; disabled item filters stay disabled", function()
    local brain_class = require("brains/wx_companionbrain")
    local inst = CreateEntity()
    inst.Transform.GetWorldPosition = function() return 0, 0, 0 end
    inst.target_items = { traps = true, flint = false, misc = true, harvest_resources = true }
    inst.harvest_enabled = true
    inst.pickup_enabled = false

    local trap = CreateEntity()
    trap.prefab = "trap"
    trap.IsInLimbo = function() return false end
    trap.Transform.GetWorldPosition = function() return 1, 0, 0 end
    trap.components.trap = { IsSprung = function() return false end }
    trap:AddComponent("inventoryitem")
    trap.components.inventoryitem.canbepickedup = true
    trap.components.inventoryitem.IsHeld = function() return false end

    local flint = CreateEntity()
    flint.prefab = "flint"
    flint.IsInLimbo = function() return false end
    flint.Transform.GetWorldPosition = function() return 2, 0, 0 end
    flint:AddComponent("inventoryitem")
    flint.components.inventoryitem.canbepickedup = true
    flint.components.inventoryitem.IsHeld = function() return false end

    local saved_find = TheSim.FindEntities
    TheSim.FindEntities = function() return { trap, flint } end
    local brain = brain_class(inst)
    brain.inst = inst
    assert(brain:FindHarvestAction() == nil, "empty trap or disabled flint was targeted")

    trap.components.trap.IsSprung = function() return true end
    local action = brain:FindHarvestAction()
    assert(action and action.target == trap and action.action == ACTIONS.HARVEST, "caught trap was not harvested")
    TheSim.FindEntities = saved_find
end)

assert_ok("Woodlogging chore chops trees when equipped with an axe", function()
    local brain_class = require("brains/wx_companionbrain")
    local inst = CreateEntity()
    inst.Transform.GetWorldPosition = function() return 0, 0, 0 end
    inst.target_items = { log = true, misc = true }
    inst.harvest_enabled = true
    inst:AddComponent("container")

    local axe = CreateEntity()
    axe.prefab = "axe"
    axe:AddComponent("tool")
    axe.components.tool:SetAction(_G.ACTIONS.CHOP)
    inst.components.container.slots[16] = axe

    local tree = CreateEntity()
    tree.prefab = "evergreen"
    tree.IsInLimbo = function() return false end
    tree.Transform.GetWorldPosition = function() return 2, 0, 2 end
    tree:AddComponent("workable")
    tree.components.workable:SetWorkAction(_G.ACTIONS.CHOP)
    tree.components.workable.workleft = 5

    local saved_find = TheSim.FindEntities
    TheSim.FindEntities = function() return { tree } end
    local b = brain_class(inst)
    b.inst = inst
    local action = b:FindHarvestAction()
    assert(action, "tree was not targeted for chopping")
    assert(action.action == _G.ACTIONS.CHOP, "action was not CHOP")
    assert(action.invobject == axe, "axe was not passed as tool invobject")
    assert(action.target == tree, "wrong target for chopping")
    TheSim.FindEntities = saved_find
end)

assert_ok("Mining chore mines rocks when equipped with a pickaxe", function()
    local brain_class = require("brains/wx_companionbrain")
    local inst = CreateEntity()
    inst.Transform.GetWorldPosition = function() return 0, 0, 0 end
    inst.target_items = { rocks = true, misc = true }
    inst.harvest_enabled = true
    inst:AddComponent("container")

    local pick = CreateEntity()
    pick.prefab = "pickaxe"
    pick:AddComponent("tool")
    pick.components.tool:SetAction(_G.ACTIONS.MINE)
    inst.components.container.slots[16] = pick

    local boulder = CreateEntity()
    boulder.prefab = "rock1"
    boulder.IsInLimbo = function() return false end
    boulder.Transform.GetWorldPosition = function() return 2, 0, 2 end
    boulder:AddComponent("workable")
    boulder.components.workable:SetWorkAction(_G.ACTIONS.MINE)
    boulder.components.workable.workleft = 6

    local saved_find = TheSim.FindEntities
    TheSim.FindEntities = function() return { boulder } end
    local b = brain_class(inst)
    b.inst = inst
    local action = b:FindHarvestAction()
    assert(action, "boulder was not targeted for mining")
    assert(action.action == _G.ACTIONS.MINE, "action was not MINE")
    assert(action.invobject == pick, "pickaxe was not passed as tool invobject")
    assert(action.target == boulder, "wrong target for mining")
    TheSim.FindEntities = saved_find
end)

assert_ok("Chopping sticks to the current tree over a nearer one", function()
    local brain_class = require("brains/wx_companionbrain")
    local inst = CreateEntity()
    inst.Transform.GetWorldPosition = function() return 0, 0, 0 end
    inst.target_items = { log = true }
    inst.harvest_enabled = true
    inst:AddComponent("container")

    local axe = CreateEntity()
    axe.prefab = "axe"
    axe:AddComponent("tool")
    axe.components.tool:SetAction(_G.ACTIONS.CHOP)
    inst.components.container.slots[16] = axe

    local near = CreateEntity()
    near.prefab = "evergreen"
    near.IsInLimbo = function() return false end
    near.Transform.GetWorldPosition = function() return 2, 0, 2 end
    near:AddComponent("workable")
    near.components.workable:SetWorkAction(_G.ACTIONS.CHOP)

    local far = CreateEntity()
    far.prefab = "evergreen"
    far.IsInLimbo = function() return false end
    far.Transform.GetWorldPosition = function() return 5, 0, 5 end
    far:AddComponent("workable")
    far.components.workable:SetWorkAction(_G.ACTIONS.CHOP)

    local saved_find = TheSim.FindEntities
    TheSim.FindEntities = function() return { near, far } end
    local b = brain_class(inst)
    b.inst = inst
    b.chop_target = far
    local action = b:FindHarvestAction()
    assert(action and action.target == far, "companion should keep chopping the current tree")
    TheSim.FindEntities = saved_find
end)

assert_ok("Does not chop or mine without tool equipped", function()
    local brain_class = require("brains/wx_companionbrain")
    local inst = CreateEntity()
    inst.Transform.GetWorldPosition = function() return 0, 0, 0 end
    inst.target_items = { log = true, rocks = true, misc = true }
    inst.harvest_enabled = true
    inst:AddComponent("container")

    local tree = CreateEntity()
    tree.prefab = "evergreen"
    tree.IsInLimbo = function() return false end
    tree.Transform.GetWorldPosition = function() return 2, 0, 2 end
    tree:AddComponent("workable")
    tree.components.workable:SetWorkAction(_G.ACTIONS.CHOP)

    local boulder = CreateEntity()
    boulder.prefab = "rock1"
    boulder.IsInLimbo = function() return false end
    boulder.Transform.GetWorldPosition = function() return 3, 0, 3 end
    boulder:AddComponent("workable")
    boulder.components.workable:SetWorkAction(_G.ACTIONS.MINE)

    local saved_find = TheSim.FindEntities
    TheSim.FindEntities = function() return { tree, boulder } end
    local b = brain_class(inst)
    b.inst = inst
    local action = b:FindHarvestAction()
    assert(action == nil, "companion should not chop or mine without a tool equipped")
    TheSim.FindEntities = saved_find
end)

assert_ok("Stalled pickup is re-pushed, then failed after 25s", function()
    local brain_class = require("brains/wx_companionbrain")
    local inst = CreateEntity()
    inst:AddComponent("locomotor")
    local failed, cleared, repushed = false, false, 0
    local action = { Fail = function() failed = true end }
    inst.components.locomotor.bufferedaction = action
    inst.components.locomotor.Clear = function() cleared = true end
    inst.components.locomotor.PushAction = function(_, act) repushed = repushed + 1 assert(act == action) end
    local b = brain_class(inst)
    b.inst = inst
    b.harvest_node = { status = RUNNING }

    now = 0
    b.action_started = 0
    now = 1
    b:CheckStall()
    assert(repushed == 0, "re-pushed before he was standing still")
    now = 4
    b:CheckStall()
    now = 7
    b:CheckStall()
    assert(repushed == 1, "standing-still pickup was not re-pushed")
    now = 5
    b:CheckStall()
    assert(not failed, "pickup failed before 6s")
    now = 7
    b:CheckStall()
    assert(failed and cleared, "stalled pickup was not failed and cleared")
end)

assert_ok("HarvesterUI tints visibly (no black.tex)", function()
    local HarvesterUI = require("widgets/harvester_ui")
    local ui = HarvesterUI(player_inst, 15)
    local imgs, lit = {}, 0
    local function walk(w)
        for _, c in ipairs(w.children) do
            if c.tex then table.insert(imgs, c) end
            walk(c)
        end
    end
    walk(ui)
    assert(#imgs > 0, "no images found in HarvesterUI")
    for _, img in ipairs(imgs) do
        assert(img.tex ~= "black.tex", "black.tex tint stays black: tint multiplies, so the color never shows")
        if img.shown and img.tint and img.tint[1] > 0.9 and img.tint[2] > 0.8 then lit = lit + 1 end
    end
    assert(lit > 0, "no visible bright (checked) indicator")
end)

assert_ok("Gear in slot 16-18 is worn and unworn", function()
    local comp_def = dofile(REPO_ROOT .. "/wx_autoharvester/scripts/prefabs/wx_companion.lua")
    local comp = comp_def.fn()
    local hat = CreateEntity()
    hat:AddComponent("equippable")
    hat.components.equippable.equipslot = EQUIPSLOTS.HEAD
    local worn_as
    hat.components.equippable.Equip = function(self, owner, slot) worn_as = slot end
    hat.components.equippable.Unequip = function(self) worn_as = nil end
    comp.components.container.slots[18] = hat
    comp:PushEvent("itemget", { slot = 18, item = hat })
    assert(worn_as == EQUIPSLOTS.HEAD, "hat was not worn in head slot")
    assert(comp.components.inventory:GetEquippedItem(EQUIPSLOTS.HEAD) == hat, "inventory equipslot was not updated")
    comp.components.container.slots[18] = nil
    comp:PushEvent("itemlose", { slot = 18 })
    assert(worn_as == nil, "hat was not unworn after removal")
    assert(comp.components.inventory:GetEquippedItem(EQUIPSLOTS.HEAD) == nil, "inventory equipslot was not cleared")
end)

assert_ok("Inventory transfer hook executes cleanly", function()
    local comp_def = dofile(REPO_ROOT .. "/wx_autoharvester/scripts/prefabs/wx_companion.lua")
    local comp = comp_def.fn()
    local item = CreateEntity()
    item.prefab = "twigs"
    item:AddComponent("inventoryitem")
    comp.components.inventory.itemslots[1] = item
    comp:PushEvent("itemget", { item = item })
end)

assert_ok("Old saves keep new defaults and rewear equipment", function()
    local comp_def = dofile(REPO_ROOT .. "/wx_autoharvester/scripts/prefabs/wx_companion.lua")
    local saved_companion = player_inst.wx_companion
    local comp = comp_def.fn()
    local hat = CreateEntity()
    hat:AddComponent("equippable")
    hat.components.equippable.equipslot = EQUIPSLOTS.HEAD
    local worn_as
    hat.components.equippable.Equip = function(_, _, slot) worn_as = slot end
    comp.components.container.slots[18] = hat

    comp.OnLoad(comp, { target_items = { twigs = false }, target_priority = { "misc", "misc", "unknown" }, worn = { 18 } })
    assert(comp.target_items.twigs == false, "saved twigs setting was ignored")
    assert(comp.target_items.misc == true, "new Other Loot default was lost on load")
    assert(comp.target_priority[1] == "misc" and #comp.target_priority == #require("target_priority"), "saved priority order was not safely merged with defaults")
    assert(worn_as == EQUIPSLOTS.HEAD, "equipped hat was not worn after load")
    player_inst.wx_companion = saved_companion
end)

assert_ok("Harvested items go to storage, then player, then the ground", function()
    local comp_def = dofile(REPO_ROOT .. "/wx_autoharvester/scripts/prefabs/wx_companion.lua")

    local function make_item(name)
        local item = CreateEntity()
        item.prefab = name
        item:AddComponent("inventoryitem")
        item.components.inventoryitem.OnDropped = function() item.dropped = true end
        return item
    end

    local function harvest(comp, item)
        comp.components.inventory.itemslots[1] = item
        comp:PushEvent("itemget", { item = item })
    end

    local saved_companion = player_inst.wx_companion
    local saved_give = player_inst.components.inventory.GiveItem

    -- storage has room
    local comp = comp_def.fn()
    player_inst.wx_companion = comp
    local item = make_item("twigs")
    harvest(comp, item)
    assert(comp.components.container.slots[1] == item, "item was not stored in the companion")

    -- storage full, player accepts
    comp = comp_def.fn()
    player_inst.wx_companion = comp
    for s = 1, 15 do comp.components.container.slots[s] = make_item("filler") end
    player_inst.components.inventory.GiveItem = function() return true end
    item = make_item("log")
    harvest(comp, item)
    assert(not item.dropped, "item was dropped although the player had room")

    -- both full, item drops at his feet
    player_inst.components.inventory.GiveItem = function() return false end
    item = make_item("rocks")
    harvest(comp, item)
    assert(item.dropped, "item was lost when storage and player were full")

    player_inst.components.inventory.GiveItem = saved_give
    player_inst.wx_companion = saved_companion
end)

assert_ok("modmain.lua loads and container hook functions", function()
    dofile(REPO_ROOT .. "/wx_autoharvester/modmain.lua")
    assert(postconstructs["widgets/containerwidget"], "containerwidget postconstruct missing")
    local dummy_widget = Widget("dummy")
    dummy_widget.Open = function() end
    dummy_widget.Close = function() end
    dummy_widget.OnUpdate = function() end
    for _, fn in ipairs(postconstructs["widgets/containerwidget"]) do
        fn(dummy_widget)
    end
    local comp_def = dofile(REPO_ROOT .. "/wx_autoharvester/scripts/prefabs/wx_companion.lua")
    local comp = comp_def.fn()
    player_inst.HUD = {
        controls = {
            top_root = Widget("top_root")
        }
    }
    dummy_widget.owner = player_inst
    dummy_widget:Open(comp, player_inst)
    assert(dummy_widget.wx_bg, "wx_bg was not created")
end)

assert_ok("Companion draws aggro on hostile creatures only when enabled", function()
    local brain_class = require("brains/wx_companionbrain")
    local inst = CreateEntity()
    inst:AddComponent("combat")
    inst.draw_aggro = false

    local hostile = CreateEntity()
    hostile:AddTag("hostile")
    hostile.IsInLimbo = function() return false end
    hostile.Transform.GetWorldPosition = function() return 4, 0, 4 end

    local saved_find = TheSim.FindEntities
    TheSim.FindEntities = function() return { hostile } end

    _G.PriorityNode = Class(function(self, children) self.children = children end)
    local captured
    _G.BT = Class(function(self, i, root) self.inst = i self.root = root captured = root end)
    _G.Follow = function() return {} end
    _G.FaceEntity = function() return {} end
    _G.DoAction = function(i, fn) return { actionfn = fn } end

    local b = brain_class(inst)
    b.inst = inst
    b:OnStart()
    local action = captured.children[1].actionfn()
    assert(action == nil, "companion attacked hostile when draw_aggro was false")

    -- Enable draw_aggro
    inst.draw_aggro = true
    action = captured.children[1].actionfn()
    assert(action and action.target == hostile and action.action == ACTIONS.ATTACK, "hostile was not targeted when draw_aggro was enabled")
    assert(action.invobject == nil, "attacked with a weapon that was not equipped")

    -- Equip a weapon in the hands slot: the attack must carry it
    inst:AddComponent("inventory")
    local weapon = CreateEntity()
    weapon:AddComponent("weapon")
    inst.components.inventory.equipslots[EQUIPSLOTS.HANDS] = weapon
    action = captured.children[1].actionfn()
    assert(action and action.invobject == weapon, "equipped weapon was not used for the attack")

    TheSim.FindEntities = saved_find
end)

assert_ok("Companion death spills storage and leaves a robot egg", function()
    local comp_def = dofile(REPO_ROOT .. "/wx_autoharvester/scripts/prefabs/wx_companion.lua")
    listeners["death"] = {}
    local comp = comp_def.fn()
    comp.components.container.slots[1] = CreateEntity()

    _G.__spawned_prefabs = {}
    comp:PushEvent("death")

    assert(comp.components.container.dropped_everything, "storage was not spilled on death")
    assert(comp.removed, "dead companion was not removed")
    assert(table.concat(_G.__spawned_prefabs, ","):find("robot_egg"), "no robot egg was laid")
end)

assert_ok("Robot egg is collectable and hatches into a companion", function()
    local egg_def = dofile(REPO_ROOT .. "/wx_autoharvester/scripts/prefabs/robot_egg.lua")
    local egg = egg_def.fn()
    assert(egg:HasTag("robot_egg"), "robot_egg tag missing")
    assert(egg.components.inventoryitem, "robot egg is not collectable")
    assert(egg.components.inventoryitem.imagename, "robot egg inventory image not set")
    assert(egg.hatch_time > GetTime(), "hatch timer was not set")

    _G.__spawned_prefabs = {}
    egg.hatch_time = GetTime() - 1
    egg:CheckHatch()
    assert(egg.removed, "hatched egg did not disappear")
    assert(table.concat(_G.__spawned_prefabs, ","):find("wx_companion"), "no companion hatched")
end)

assert_ok("Broken equipped tool cleans up container and equip slots", function()
    local comp_def = dofile(REPO_ROOT .. "/wx_autoharvester/scripts/prefabs/wx_companion.lua")
    local comp = comp_def.fn()
    local axe = CreateEntity()
    axe:AddComponent("equippable")
    axe.components.equippable.equipslot = EQUIPSLOTS.HANDS
    axe.components.equippable.Equip = function() end
    axe.components.equippable.Unequip = function() end
    comp.components.container.slots[16] = axe
    comp:PushEvent("itemget", { slot = 16, item = axe })
    assert(comp.worn and comp.worn[16] == axe, "axe was not worn")
    assert(comp.components.inventory.equipslots[EQUIPSLOTS.HANDS] == axe, "axe was not in equipslots")

    -- Simulate tool breaking (item:Remove triggers onremove)
    axe:PushEvent("onremove")
    assert(comp.worn[16] == nil, "broken tool was not un-worn")
    assert(comp.components.inventory.equipslots[EQUIPSLOTS.HANDS] == nil, "broken tool was not removed from equipslots")
    assert(comp.components.container.slots[16] == nil, "broken tool stayed in container slot 16")
end)

assert_ok("Robot egg hatches from container", function()
    local egg_def = dofile(REPO_ROOT .. "/wx_autoharvester/scripts/prefabs/robot_egg.lua")
    local egg = egg_def.fn()
    local backpack = CreateEntity()
    backpack:AddComponent("container")
    local removed_item = nil
    backpack.components.container.RemoveItem = function(c, item) removed_item = item return item end
    egg.components.inventoryitem.owner = backpack

    egg.hatch_time = GetTime() - 1
    egg:CheckHatch()
    assert(removed_item == egg, "egg was not removed from container when hatching")
    assert(egg.removed, "hatched egg did not disappear")
end)

assert_ok("Companion transforms to egg in player inventory without losing items", function()
    local comp_def = dofile(REPO_ROOT .. "/wx_autoharvester/scripts/prefabs/wx_companion.lua")
    local comp = comp_def.fn()
    local player = CreateEntity()
    player:AddComponent("inventory")
    local given_item = nil
    player.components.inventory.GiveItem = function(inv, item) given_item = item return true end

    local twigs = CreateEntity()
    twigs.prefab = "twigs"
    twigs:AddComponent("inventoryitem")
    comp.components.container.slots[1] = twigs

    local axe = CreateEntity()
    axe.prefab = "axe"
    axe:AddComponent("inventoryitem")
    axe:AddComponent("equippable")
    axe.components.equippable.equipslot = EQUIPSLOTS.HANDS
    comp.components.container.slots[16] = axe

    comp.harvest_radius = 25
    comp.draw_aggro = true

    local egg = comp:TransformToEgg(player)
    assert(egg ~= nil, "egg was not returned from TransformToEgg")
    assert(egg:HasTag("robot_egg"), "returned object is not a robot_egg")
    assert(egg:HasTag("wx_companion_egg"), "wx_companion_egg tag missing on egg")
    assert(comp.removed, "companion entity was not removed after transforming")
    assert(not comp.components.container.dropped_everything, "items should not be dropped on transform")
    assert(given_item == egg, "egg was not given to player inventory")

    -- Check container on egg is accessible and has all items
    assert(egg.components.container, "egg does not have a container")
    assert(egg.components.container.slots[1] == twigs, "twigs slot 1 was not transferred to egg")
    assert(egg.components.container.slots[16] == axe, "axe slot 16 was not transferred to egg")
    assert(egg.companion_data.harvest_radius == 25, "harvest_radius was not saved in egg")
    assert(egg.companion_data.draw_aggro == true, "draw_aggro was not saved in egg")

    -- Test egg storage toggle
    assert(not egg.components.container:IsOpen(), "egg container started open")
    egg:ToggleStorage(player)
    assert(egg.components.container:IsOpen(), "egg container did not open via ToggleStorage")
    egg:ToggleStorage(player)
    assert(not egg.components.container:IsOpen(), "egg container did not close via ToggleStorage")
end)

assert_ok("Robot egg deploys back to companion restoring items and settings", function()
    local egg_def = dofile(REPO_ROOT .. "/wx_autoharvester/scripts/prefabs/robot_egg.lua")
    local egg = egg_def.fn()
    local player = CreateEntity()
    player:AddComponent("inventory")

    local twigs = CreateEntity()
    twigs.prefab = "twigs"
    twigs:AddComponent("inventoryitem")
    egg.components.container.slots[1] = twigs

    egg.companion_data = {
        harvest_radius = 25,
        draw_aggro = true,
        untethered = true,
    }

    local comp = egg:Hatch(player)
    assert(comp ~= nil, "companion was not spawned from Hatch")
    assert(egg.removed, "egg was not removed after hatching")
    assert(comp.components.container.slots[1] == twigs, "twigs were not restored to companion container")
    assert(comp.harvest_radius == 25, "harvest_radius was not restored to companion")
    assert(comp.draw_aggro == true, "draw_aggro was not restored to companion")
    assert(comp.untethered == true, "untethered was not restored to companion")
    assert(player.wx_companion == comp, "player.wx_companion was not set to hatched companion")
end)

assert_ok("Clicking on boat transforms companion to robot seed in inventory", function()
    -- Load modmain to ensure playercontroller postconstruct is registered
    dofile(REPO_ROOT .. "/wx_autoharvester/modmain.lua")

    local player = CreateEntity()
    player:AddComponent("inventory")
    local given_item = nil
    player.components.inventory.GiveItem = function(inv, item) given_item = item return true end

    local comp_def = dofile(REPO_ROOT .. "/wx_autoharvester/scripts/prefabs/wx_companion.lua")
    local comp = comp_def.fn()
    player.wx_companion = comp

    local pc = {
        inst = player,
        DoAction = function(self, act) return true end,
    }

    -- Apply playercontroller postconstructs
    for _, fn in ipairs(postconstructs["components/playercontroller"] or {}) do
        fn(pc)
    end

    local boat = CreateEntity()
    boat:AddTag("boat")
    boat:AddComponent("drivable")

    local act = {
        action = ACTIONS.MOUNT,
        target = boat,
    }

    pc:DoAction(act)

    assert(comp.removed, "companion was not removed when player clicked on boat")
    assert(given_item ~= nil and given_item:HasTag("robot_egg"), "robot egg was not placed in player inventory on boat click")
    assert(player.wx_companion == given_item, "player.wx_companion does not point to egg")
    assert(given_item.components.container, "harvester inventory is not accessible on egg")
end)

assert_ok("HarvesterUI manual toggle packs to egg and deploys back", function()
    local HarvesterUI = require("widgets/harvester_ui")
    local player = CreateEntity()
    player:AddComponent("inventory")
    player.components.inventory.GiveItem = function(inv, item) player.held_egg = item return true end

    local comp_def = dofile(REPO_ROOT .. "/wx_autoharvester/scripts/prefabs/wx_companion.lua")
    local comp = comp_def.fn()
    player.wx_companion = comp

    local ui = HarvesterUI(player, 15)
    ui:Show()

    local egg_box = nil
    for _, child in ipairs(ui.children) do
        if child.label and child.label.string and child.label.string:find("Egg Form") then
            egg_box = child
            break
        end
    end
    assert(egg_box ~= nil, "Egg Form checkbox not found in HarvesterUI")
    assert(not egg_box:IsChecked(), "Egg Form started checked")

    -- Toggle to egg
    egg_box.btn:onclick()
    assert(egg_box:IsChecked(), "Egg Form did not check after click")
    assert(comp.removed, "companion entity not removed on UI toggle to egg")
    assert(player.held_egg and player.held_egg:HasTag("robot_egg"), "egg was not given to player")

    -- Toggle back to companion
    player.wx_egg = player.held_egg
    egg_box.btn:onclick()
    assert(not egg_box:IsChecked(), "Egg Form stayed checked after second click")
    assert(player.wx_companion and player.wx_companion:HasTag("wx_companion"), "companion was not redeployed")
end)

assert_ok("Companion spawns cleanly when os.getenv is nil (DS Lua sandbox)", function()
    local saved_getenv = os.getenv
    os.getenv = nil
    local ok, err = pcall(function()
        local comp_def = dofile(REPO_ROOT .. "/wx_autoharvester/scripts/prefabs/wx_companion.lua")
        local comp = comp_def.fn()
        assert(comp ~= nil, "companion failed to spawn under sandboxed os.getenv")
    end)
    os.getenv = saved_getenv
    assert(ok, err)
end)

print("=== All Automated Tests Passed (0 errors) ===")
