-- ============================================================
-- base_core/clients/satellite_node.lua
-- Универсальный сателлит-клиент для удаленных узлов базы
-- ============================================================

local Config   = require("/base_core/config")
local Protocol = require("/base_core/lib/protocol")
local Net      = require("/base_core/lib/net")

term.clear()
term.setCursorPos(1, 1)

print("=== BASECORE SATELLITE NODE ===")

if not Net.init() then
    print("ERROR: No modem attached!")
    return
end

local nodeName = "Satellite-" .. os.getComputerID()
print("Node Name: " .. nodeName)

local function collectLocalPeripherals()
    local names = peripheral.getNames()
    local list = {}
    for _, name in ipairs(names) do
        table.insert(list, { name = name, type = peripheral.getType(name) })
    end
    return list
end

print("Sending telemetry to BaseCore server...")

while true do
    local periphs = collectLocalPeripherals()

    Net.broadcast(Protocol.TYPE.HEARTBEAT, {
        name  = nodeName,
        role  = "satellite",
        data  = {
            peripherals = periphs,
            time        = os.time(),
        }
    })

    sleep(Config.NETWORK.HEARTBEAT_SEC or 5)
end
