-- ============================================================
-- base_core/services/openclaw_bridge.lua
-- Мост интеграции с внешним сервером OpenClaw (HTTP / Webhooks)
-- ============================================================

local Config = require("/base_core/config")
local Logger = require("/base_core/lib/logger")

local OpenClawBridge = {}

local lastSyncTime = 0

function OpenClawBridge.isEnabled()
    return Config.OPENCLAW and Config.OPENCLAW.ENABLED and (http ~= nil)
end

function OpenClawBridge.init()
    if not http then
        Logger.warn("OPENCLAW", "HTTP API is disabled on this server. OpenClaw bridge cannot run.")
        return false
    end

    if not Config.OPENCLAW or not Config.OPENCLAW.ENABLED then
        Logger.info("OPENCLAW", "OpenClaw bridge is disabled in config.lua")
        return false
    end

    Logger.success("OPENCLAW", "OpenClaw Bridge initialized -> " .. (Config.OPENCLAW.SERVER_URL or "none"))
    return true
end

-- Отправка алерта на внешний сервер OpenClaw
function OpenClawBridge.sendAlert(alert)
    if not OpenClawBridge.isEnabled() or not Config.OPENCLAW.SEND_ALERTS then return end

    local url = (Config.OPENCLAW.SERVER_URL or "") .. "/api/alert"
    local payload = textutils.serialiseJSON({
        source    = alert.source or "BASE",
        severity  = alert.severity or "info",
        text      = alert.text or "",
        timestamp = os.epoch("utc"),
    })

    local headers = {
        ["Content-Type"] = "application/json",
        ["Authorization"] = "Bearer " .. (Config.OPENCLAW.API_KEY or ""),
    }

    -- Асинхронный HTTP POST (не блокирует сервер)
    pcall(function()
        http.request(url, payload, headers)
    end)
end

-- Синхронизация полной телеметрии базы (SU, FE, Склад, Радар, Реле)
function OpenClawBridge.syncTelemetry(state)
    if not OpenClawBridge.isEnabled() then return end

    local now = os.clock()
    local interval = Config.OPENCLAW.SYNC_RATE_SEC or 5
    if now - lastSyncTime < interval then return end
    lastSyncTime = now

    local url = (Config.OPENCLAW.SERVER_URL or "") .. "/api/telemetry"
    local payload = textutils.serialiseJSON({
        serverName = Config.SERVER.NAME or "NEXI",
        time       = os.time(),
        stress     = state.create and state.create.stress or {},
        speed      = state.create and state.create.speed or 0,
        energy     = state.create and state.create.energy or {},
        tanks      = state.create and state.create.tanks or {},
        storage    = state.storage or {},
        radar      = {
            threatCount = state.radar and state.radar.threatCount or 0,
            entities    = state.radar and state.radar.entities or {},
        },
        relays     = state.relays or {},
    })

    local headers = {
        ["Content-Type"] = "application/json",
        ["Authorization"] = "Bearer " .. (Config.OPENCLAW.API_KEY or ""),
    }

    pcall(function()
        http.request(url, payload, headers)
    end)
end

-- Опрос внешних команд (например, если вы нажали кнопку на сайте / в Telegram)
function OpenClawBridge.pollCommands(onCommand)
    if not OpenClawBridge.isEnabled() then return end

    local url = (Config.OPENCLAW.SERVER_URL or "") .. "/api/commands/pop"
    local headers = {
        ["Authorization"] = "Bearer " .. (Config.OPENCLAW.API_KEY or ""),
    }

    pcall(function()
        local res = http.get(url, headers)
        if res then
            local body = res.readAll()
            res.close()
            local data = textutils.unserialiseJSON(body)
            if data and data.command and onCommand then
                onCommand(data.command)
            end
        end
    end)
end

return OpenClawBridge
