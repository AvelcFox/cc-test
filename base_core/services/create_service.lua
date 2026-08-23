-- ============================================================
-- base_core/services/create_service.lua
-- Сбор телеметрии Create (Stressometer, Speedometer, Tanks, FE)
-- ============================================================

local Logger = require("/base_core/lib/logger")
local Config = require("/base_core/config")

local CreateService = {}

local data = {
    stress = {
        current   = 0,
        capacity  = 0,
        pct       = 0,
        overload  = false,
    },
    speed = 0,
    energy = {
        stored    = 0,
        capacity  = 0,
        pct       = 0,
    },
    tanks = {},
}

local function findPeripherals()
    local stressometer = peripheral.find("Create_Stressometer") or peripheral.find("create:stressometer")
    local speedometer  = peripheral.find("Create_Speedometer") or peripheral.find("create:speedometer")
    
    local tanks = {}
    local feDevices = {}

    for _, name in ipairs(peripheral.getNames()) do
        local pType = peripheral.getType(name)
        if pType then
            if pType:find("fluid_tank", 1, true) or pType == "create:fluid_tank" then
                table.insert(tanks, peripheral.wrap(name))
            elseif pType:find("ElectricGauge", 1, true) or pType:find("tesla_coil", 1, true) or pType:find("accumulator", 1, true) then
                table.insert(feDevices, peripheral.wrap(name))
            end
        end
    end

    return stressometer, speedometer, tanks, feDevices
end

function CreateService.poll()
    local stressometer, speedometer, tanks, feDevices = findPeripherals()

    -- 1. Стресс и емкость SU (getStressCapacity)
    if stressometer then
        local ok1, stress = pcall(stressometer.getStress)
        local ok2, capacity = pcall(function()
            if stressometer.getStressCapacity then
                return stressometer.getStressCapacity()
            elseif stressometer.getCapacity then
                return stressometer.getCapacity()
            end
            return 0
        end)

        if ok1 and ok2 and capacity and capacity > 0 then
            data.stress.current = math.floor(stress or 0)
            data.stress.capacity = math.floor(capacity or 0)
            data.stress.pct = math.floor((data.stress.current / data.stress.capacity) * 100)
            data.stress.overload = data.stress.current > data.stress.capacity
        else
            data.stress.current = math.floor(stress or 0)
            data.stress.capacity = 0
            data.stress.pct = 0
            data.stress.overload = false
        end
    end

    -- 2. Скорость RPM
    if speedometer then
        local ok, spd = pcall(speedometer.getSpeed)
        if ok and spd then
            data.speed = math.floor(spd)
        end
    end

    -- 3. Баки с жидкостями
    data.tanks = {}
    for i, tank in ipairs(tanks) do
        local ok, tankInfo = pcall(tank.tanks)
        if ok and tankInfo and #tankInfo > 0 then
            for _, t in ipairs(tankInfo) do
                table.insert(data.tanks, {
                    name     = t.name or "Empty",
                    amount   = t.amount or 0,
                    capacity = t.capacity or 1000,
                    pct      = math.floor(((t.amount or 0) / (t.capacity or 1)) * 100)
                })
            end
        end
    end

    -- 4. FE Энергия (Create Crafts & Additions / Electroenergetics)
    local totalStored = 0
    local totalCap = 0
    for _, dev in ipairs(feDevices) do
        local ok1, stored = pcall(dev.getEnergy or dev.getEnergyStored)
        local ok2, cap = pcall(dev.getMaxEnergy or dev.getMaxEnergyStored)
        if ok1 and ok2 and cap and cap > 0 then
            totalStored = totalStored + (stored or 0)
            totalCap = totalCap + (cap or 0)
        end
    end

    if totalCap > 0 then
        data.energy.stored = totalStored
        data.energy.capacity = totalCap
        data.energy.pct = math.floor((totalStored / totalCap) * 100)
    end

    return data
end

function CreateService.getData()
    return data
end

return CreateService
