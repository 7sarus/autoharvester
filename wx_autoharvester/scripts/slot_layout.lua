-- Shared 15-storage + 3-equipment slot positions for the WX companion/egg containers.
local _G = rawget(_G, "GLOBAL") or _G
local Vector3 = _G.Vector3 or Vector3

local slotpos = {}
local W = 68
local SEP = 12
local INTERSEP = 28
local num_slots = 15
local num_storage = num_slots
local num_equip = 3
local num_intersep = math.floor(num_slots / 5) + 1
local total_w = (num_slots + num_equip) * W + (num_slots + num_equip - 2 - num_intersep) * SEP + INTERSEP * num_intersep

for k = 1, num_slots do
    local interseps = math.floor((k - 1) / 5)
    local x = -total_w / 2 + W / 2 + interseps * (INTERSEP - SEP) + (k - 1) * W + (k - 1) * SEP
    table.insert(slotpos, Vector3(x, 0, 0))
end

for k = 1, num_equip do
    local x = -total_w / 2 + num_slots * W + num_intersep * (INTERSEP - SEP) + (num_slots - 1) * SEP + INTERSEP + W * (k - 1) + SEP * (k - 1)
    table.insert(slotpos, Vector3(x, 0, 0))
end

return slotpos
