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

    local home = os.getenv("HOME") or ""
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
}
_G.EQUIPSLOTS = { HANDS = "hands", HEAD = "head", BODY = "body" }
local now = 0
_G.GetTime = function() return now end
_G.BufferedAction = function(doer, target, action)
    return {
        doer = doer, target = target, action = action,
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
            self.components.inventory.GiveItem = function(self, item) return true end
            self.components.inventory.RemoveItem = function(self, item) end
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
    return e
end

function _G.MakeCharacterPhysics() end
function _G.MakeGhostPhysics() end
_G.TheSim = {
    FindEntities = function() return {} end,
}
_G.TheInput = {
    AddKeyUpHandler = function() end,
}

local player_inst = _G.CreateEntity()
player_inst:AddComponent("inventory")
function _G.GetPlayer() return player_inst end

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
    end)
    function Text:SetHAlign() end
    function Text:SetColour() end
    function Text:SetString() end
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

assert_ok("Other Loot picks pinecones but not gear", function()
    local brain_class = require("brains/wx_companionbrain")
    local inst = CreateEntity()
    inst.Transform.GetWorldPosition = function() return 0, 0, 0 end
    inst.target_items = { misc = true }
    inst.harvest_enabled = true
    local cone = CreateEntity()
    cone.prefab = "pinecone"
    cone.IsInLimbo = function() return false end
    cone.Transform.GetWorldPosition = function() return 1, 0, 1 end
    cone:AddComponent("inventoryitem")
    cone.components.inventoryitem.canbepickedup = true
    cone.components.inventoryitem.IsHeld = function() return false end

    local axe = CreateEntity()
    axe.prefab = "axe"
    axe.IsInLimbo = function() return false end
    axe.Transform.GetWorldPosition = function() return 1, 0, 1 end
    axe:AddComponent("inventoryitem")
    axe.components.inventoryitem.canbepickedup = true
    axe.components.inventoryitem.IsHeld = function() return false end
    axe.components.tool = {}
    axe.components.equippable = {}

    local saved_find = TheSim.FindEntities
    TheSim.FindEntities = function() return { axe, cone } end
    local b = brain_class(inst)
    b.inst = inst
    local action = b:FindHarvestAction()
    assert(action, "pinecone was not targeted")
    assert(action.target == cone, "companion targeted gear instead of the pinecone")
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
    now = 24
    b:CheckStall()
    assert(not failed, "pickup failed before 25s")
    now = 26
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
    comp.components.container.slots[18] = nil
    comp:PushEvent("itemlose", { slot = 18 })
    assert(worn_as == nil, "hat was not unworn after removal")
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

    comp.OnLoad(comp, { target_items = { twigs = false }, worn = { 18 } })
    assert(comp.target_items.twigs == false, "saved twigs setting was ignored")
    assert(comp.target_items.misc == true, "new Other Loot default was lost on load")
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

print("=== All Automated Tests Passed (0 errors) ===")
