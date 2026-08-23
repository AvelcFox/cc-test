-- ============================================================
-- base_core/server/main.lua
-- Главный сервер базы BaseCore OS & NexiNetSystem
-- Исключительно динамические реле от сателлитов
-- ============================================================

local Config         = require("/base_core/config")
local Logger         = require("/base_core/lib/logger")
local Protocol       = require("/base_core/lib/protocol")
local Net            = require("/base_core/lib/net")
local CreateService  = require("/base_core/services/create_service")
local StorageService = require("/base_core/services/storage_service")
local RadarService   = require("/base_core/services/radar_service")
local Dashboard         = require("/base_core/server/dashboard")
local OpenClaw          = require("/base_core/services/openclaw_bridge")
local AutomationService = require("/base_core/services/automation_service")

term.clear()
term.setCursorPos(1, 1)

Logger.info("SERVER", "=== INITIALIZING BASECORE OS ===")

-- 1. Инициализация Сети & Внешнего Моста
local netOk = Net.init()
if not netOk then
    Logger.warn("SERVER", "Operating in offline mode (no modem attached)")
end
OpenClaw.init()

-- 2. Инициализация Монитора
local monitor = peripheral.find("monitor")
local dashOk = false
if monitor then
    dashOk = Dashboard.init(monitor)
    if dashOk then
        Logger.success("SERVER", "Attached to monitor: " .. peripheral.getName(monitor))
    end
else
    Logger.warn("SERVER", "No monitor attached. Dashboard running in headless mode.")
end

-- Динамический реестр реле и контроллеров от удаленных ПК
local dynamicRelays = {}

local function getAllRelays()
    local list = {}
    for uid, r in pairs(dynamicRelays) do
        table.insert(list, r)
    end
    return list
end

local serverState
serverState = {
    create   = {},
    storage  = { vaultCount = 0, totalSlots = 0, usedSlots = 0, freeSlots = 0, pct = 0, items = {} },
    radar    = { hasRadar = false, threatCount = 0, entities = {}, threats = {} },
    relays   = getAllRelays(),
    nodes    = {},
    onToggleRelay = function(relayUid)
        local target = dynamicRelays[relayUid]
        if target then
            target.state = not target.state
            serverState.relays = getAllRelays()
            Net.broadcast(Protocol.TYPE.COMMAND, {
                action   = "SET_RELAY",
                relayUid = relayUid,
                name     = target.name,
                state    = target.state,
            })
            Net.broadcast(Protocol.TYPE.ALERT, {
                text     = string.format("Relay '%s' -> %s", target.name, target.state and "ON" or "OFF"),
                severity = Protocol.SEVERITY.INFO,
                source   = "SERVER",
            })
        end
    end
}

-- ── Обработчики сетевых сообщений ─────────────────────────────

Net.on(Protocol.TYPE.COMMAND, function(senderID, payload)
    if payload.action == "TOGGLE_RELAY" and (payload.channelId or payload.relayUid) then
        serverState.onToggleRelay(payload.channelId or payload.relayUid)
        Net.send(senderID, Protocol.TYPE.COMMAND_RESP, { success = true, relays = serverState.relays })
    elseif payload.action == "GET_STATUS" then
        Net.send(senderID, Protocol.TYPE.RESPONSE, {
            create  = serverState.create,
            storage = serverState.storage,
            radar   = serverState.radar,
            relays  = serverState.relays,
        })
    end
end)

-- Приём телеметрии от сателлитов (Радар 3, Склад 10, Реле-узлы, Очки 8)
Net.on(Protocol.TYPE.TELEMETRY, function(senderID, payload)
    -- Радар (Computer 3)
    if payload.role == "radar_outpost" or payload.entities ~= nil then
        serverState.radar = {
            hasRadar    = true,
            threatCount = payload.threatCount or 0,
            entities    = payload.entities or {},
            threats     = payload.threats or {},
        }

    -- Склад (Computer 10)
    elseif payload.role == "storage_node" or payload.vaultCount ~= nil or payload.totalSlots ~= nil then
        serverState.storage = {
            vaultCount = tonumber(payload.vaultCount) or 0,
            totalSlots = tonumber(payload.totalSlots) or 0,
            usedSlots  = tonumber(payload.usedSlots) or 0,
            freeSlots  = tonumber(payload.freeSlots) or math.max(0, (tonumber(payload.totalSlots) or 0) - (tonumber(payload.usedSlots) or 0)),
            pct        = tonumber(payload.pct) or 0,
            items      = payload.items or {},
        }

    -- Реле-узел (динамический контроллер с сателлит-ПК)
    elseif payload.role == "relay_node" and payload.relays then
        for _, r in ipairs(payload.relays) do
            dynamicRelays[r.uid] = {
                uid     = r.uid,
                nodeId  = payload.nodeId or senderID,
                name    = r.name or "Relay",
                state   = r.state or false,
                type    = r.type or "peripheral",
                isLocal = false,
            }
        end
        serverState.relays = getAllRelays()
    end
end)

-- ── Поток 1: Опрос периферии и алерты ────────────────────────

local function telemetryLoop()
    while true do
        serverState.create = CreateService.poll()
        
        -- Локальный склад опрашивается только если нет удаленного узла склада
        if (serverState.storage.totalSlots or 0) == 0 then
            local localStore = StorageService.poll()
            if (localStore.totalSlots or 0) > 0 then
                serverState.storage = localStore
            end
        end
        
        -- Локальный радар
        local localRadar = RadarService.poll()
        if localRadar.hasRadar and not serverState.radar.hasRadar then
            serverState.radar = localRadar
        end

        serverState.relays = getAllRelays()
        serverState.nodes  = Net.getNodes()

        Net.cleanStaleNodes()

        -- Проверка алертов Create Stress
        if serverState.create.stress and serverState.create.stress.pct >= Config.ALERTS.STRESS_WARN_PCT then
            local isCrit = serverState.create.stress.pct >= Config.ALERTS.STRESS_CRIT_PCT
            local sev = isCrit and Protocol.SEVERITY.CRITICAL or Protocol.SEVERITY.WARNING
            local txt = isCrit and "CRITICAL: Kinetic Network Overloaded!" or ("Kinetic Stress high: " .. serverState.create.stress.pct .. "%")
            Logger.warn("ALERT", txt)
            Net.broadcast(Protocol.TYPE.ALERT, { text = txt, severity = sev, source = "KINETIC" })
            OpenClaw.sendAlert({ text = txt, severity = sev, source = "KINETIC" })
        end

        -- Оценка и выполнение правил автоматизации (пороги предметов, защита Create и т.д.)
        AutomationService.evaluate(serverState)

        -- Синхронизация с OpenClaw сервером
        OpenClaw.syncTelemetry(serverState)
        OpenClaw.pollCommands(function(cmd)
            if cmd.action == "TOGGLE_RELAY" and (cmd.channelId or cmd.relayUid) then
                serverState.onToggleRelay(cmd.channelId or cmd.relayUid)
            end
        end)

        -- Периодическая трансляция сводки для Smart Glasses HUD
        Net.broadcast(Protocol.TYPE.TELEMETRY, {
            stressPct   = serverState.create.stress and serverState.create.stress.pct or 0,
            energyPct   = serverState.create.energy and serverState.create.energy.pct or 0,
            storagePct  = serverState.storage.pct or 0,
            threatCount = serverState.radar.threatCount or 0,
        })

        sleep(Config.SERVER.POLL_RATE_SEC or 1.0)
    end
end

-- ── Поток 2: Отрисовка Дашборда ──────────────────────────────

local function renderLoop()
    while true do
        if dashOk then
            Dashboard.render(serverState)
        end
        sleep(0.5)
    end
end

-- ── Поток 3: Обработка событий (Touch, Network, Keys) ────────

local function eventLoop()
    while true do
        local ev = { os.pullEvent() }
        local event = ev[1]

        if event == "monitor_touch" then
            local side, x, y = ev[2], ev[3], ev[4]
            if dashOk then
                Dashboard.handleTouch(x, y)
                Dashboard.render(serverState)
            end

        elseif event == "rednet_message" then
            local senderID, rawPacket, proto = ev[2], ev[3], ev[4]
            Net.processMessage(senderID, rawPacket, proto)

        elseif event == "char" or event == "key" then
            if ev[2] == keys.q then
                Logger.info("SERVER", "Stopping BaseCore OS...")
                break
            end
        end
    end
end

Logger.success("SERVER", "BaseCore OS running! Press 'Q' in terminal to stop.")

parallel.waitForAny(telemetryLoop, renderLoop, eventLoop)
