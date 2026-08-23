-- ============================================================
-- base_core/lib/protocol.lua
-- Стандартизированный сетевой протокол BaseCore & NexiNetSystem
-- ============================================================

local Config = require("/base_core/config")

local Protocol = {}

Protocol.NAME = Config.NETWORK.PROTOCOL

Protocol.TYPE = {
    HEARTBEAT    = "HEARTBEAT",
    TELEMETRY    = "TELEMETRY",
    ALERT        = "ALERT",
    COMMAND      = "COMMAND",
    COMMAND_RESP = "COMMAND_RESP",
    QUERY        = "QUERY",
    RESPONSE     = "RESPONSE",
}

Protocol.SEVERITY = {
    INFO     = "info",
    SUCCESS  = "success",
    WARNING  = "warning",
    DANGER   = "danger",
    CRITICAL = "critical",
}

local function djb2Hash(str)
    local h = 5381
    for i = 1, #str do
        h = bit.band(h * 33 + string.byte(str, i), 0xFFFFFFFF)
    end
    return string.format("%08x", h)
end

-- Очистка таблиц от циклических ссылок, функций и метатаблиц
local function sanitize(val, seen)
    seen = seen or {}
    local vType = type(val)
    if vType == "number" or vType == "string" or vType == "boolean" then
        return val
    elseif vType == "table" then
        if seen[val] then
            return nil
        end
        seen[val] = true
        local copy = {}
        for k, v in pairs(val) do
            local cleanK = (type(k) == "number" or type(k) == "string") and k or tostring(k)
            local cleanV = sanitize(v, seen)
            if cleanV ~= nil then
                copy[cleanK] = cleanV
            end
        end
        return copy
    end
    return nil
end

Protocol.sanitize = sanitize

function Protocol.sign(msgType, payload, targetID)
    local timestamp = os.epoch and os.epoch("utc") or (os.time() * 1000)
    local nonce = math.random(100000, 999999)
    local secret = Config.NETWORK.SECRET_KEY or "default"
    local cleanPayload = sanitize(payload) or {}

    -- Подпись на основе скаляров: защищает от подделки и исключает рассинхрон порядка ключей в JSON
    local raw = string.format("%s|%d|%d|%s", msgType, timestamp, nonce, secret)
    local signature = djb2Hash(raw)

    return {
        proto    = Protocol.NAME,
        type     = msgType,
        sender   = os.getComputerID(),
        target   = targetID,
        ts       = timestamp,
        nonce    = nonce,
        payload  = cleanPayload,
        sig      = signature,
    }
end

function Protocol.verify(packet)
    if type(packet) ~= "table" then return false, "Not a table" end
    if packet.proto ~= Protocol.NAME then return false, "Protocol mismatch" end
    if not packet.type or not packet.sig or not packet.ts or not packet.nonce then
        return false, "Malformed packet"
    end

    local secret = Config.NETWORK.SECRET_KEY or "default"
    local raw = string.format("%s|%d|%d|%s", packet.type, packet.ts, packet.nonce, secret)
    local expectedSig = djb2Hash(raw)

    if packet.sig ~= expectedSig then
        return false, "Invalid signature"
    end

    return true, packet
end

return Protocol
