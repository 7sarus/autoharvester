local _G = rawget(_G, "GLOBAL") or _G
local ANIM_ORIENTATION = _G.ANIM_ORIENTATION
local LAYER_BACKGROUND = _G.LAYER_BACKGROUND

local assets = {
    Asset("ANIM", "anim/reticule.zip"),
}

local function SetRadius(inst, radius)
    radius = radius or 15
    inst.current_radius = radius
    -- reticule native radius is ~1.25m
    local s = radius / 1.25
    inst.Transform:SetScale(s, s, s)
end

local function fn()
    local inst = CreateEntity()
    inst.entity:AddTransform()
    inst.entity:AddAnimState()

    inst:AddTag("NOCLICK")
    inst:AddTag("FX")

    inst.AnimState:SetBank("reticule")
    inst.AnimState:SetBuild("reticule")
    inst.AnimState:PlayAnimation("idle")
    inst.AnimState:SetOrientation(ANIM_ORIENTATION.OnGround)
    inst.AnimState:SetLayer(LAYER_BACKGROUND)
    inst.AnimState:SetSortOrder(3)

    inst.persists = false
    inst.SetRadius = SetRadius
    SetRadius(inst, 15)

    return inst
end

return Prefab("common/harvest_range_ring", fn, assets)
