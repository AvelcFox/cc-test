-- ============================================================
-- base_core/lib/net.lua
-- Сетевой менеджер: поиск модема, отправка, приём, реестр узлов
-- ============================================================

local Protocol = require("/base_core/lib/protocol")
local Logger   = require("/base_core/lib/logger")
local Config   = require("/base_core/config")

local Net = {}

local activeModem = nil
local activeModemName = nil
local registeredNodes = {}
local messageHandlers = {}

function Net.init()
    -- Поиск первого подходящего модема
    for _, name in ipairs(peripheral.getNames()) do
        local pType = peripheral.getType(name)
        if pType and (pType:find("modem", 1, true) or pType == "wireless_modem") then
            activeModem = peripheral.wrap(name)
            activeModemName = name
            break
        end
    end

    if not activeModem then
        Logger.error("NET", "No modem found attached to this computer!")
        return false
    end

    if not rednet.isOpen(activeModemName) then
        rednet.open(activeModemName)
    end

    Logger.success("NET", "Rednet opened on modem: " .. activeModemName .. " (ID: " .. os.getComputerID() .. ")")
    return true
end

function Net.getModemName()
    return activeModemName
end

function Net.broadcast(msgType, payload)
    if not activeModemName then return false end
    local packet = Protocol.sign(msgType, payload, nil)
    rednet.broadcast(packet, Protocol.NAME)
    return true
end

function Net.send(targetID, msgType, payload)
    if not activeModemName then return false end
    local packet = Protocol.sign(msgType, payload, targetID)
    rednet.send(targetID, packet, Protocol.NAME)
    return true
end

function Net.on(msgType, callback)
    messageHandlers[msgType] = messageHandlers[msgType] or {}
    table.insert(messageHandlers[msgType], callback)
end

function Net.registerNode(senderID, payload)
    local now = os.clock()
    local node = registeredNodes[senderID] or {}
    node.id       = senderID
    node.name     = payload.name or ("Node-" .. senderID)
    node.role     = payload.role or "satellite"
    node.lastSeen = now
    node.status   = "online"
    node.data     = payload.data or {}
    registeredNodes[senderID] = node
end

function Net.cleanStaleNodes()
    local now = os.clock()
    local timeout = Config.NETWORK.TIMEOUT_SEC or 15
    for id, node in pairs(registeredNodes) do
        if now - node.lastSeen > timeout then
            node.status = "offline"
        end
    end
end

function Net.getNodes()
    return registeredNodes
end

function Net.processMessage(senderID, rawPacket, proto)
    if proto ~= Protocol.NAME then return end

    local valid, packet = Protocol.verify(rawPacket)
    if not valid then
        Logger.warn("NET", "Ignored packet from " .. senderID .. ": " .. tostring(packet))
        return
    end

    -- Если пакет адресован не нам и не широковещательный
    if packet.target and packet.target ~= os.getComputerID() then
        return
    end

    if packet.type == Protocol.TYPE.HEARTBEAT or packet.type == Protocol.TYPE.TELEMETRY then
        Net.registerNode(senderID, packet.payload)
    end

    local handlers = messageHandlers[packet.type]
    if handlers then
        for _, handler in ipairs(handlers) do
            local ok, err = pcall(handler, senderID, packet.payload, packet)
            if not ok then
                Logger.error("NET", "Handler error: " .. tostring(err))
            end
        end
    end
end

return Net
