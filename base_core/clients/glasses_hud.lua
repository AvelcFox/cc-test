-- ============================================================
-- base_core/clients/glasses_hud.lua
-- Клиент дополненной реальности (AR HUD) для Smart Glasses AP 0.8
-- Полная поддержка нативной архитектуры Smart Glasses и getEyePosition
-- ============================================================

local Config   = require("/base_core/config")
local Protocol = require("/base_core/lib/protocol")
local Net      = require("/base_core/lib/net")

term.clear()
term.setCursorPos(1, 1)

print("========================================")
print("     NEXINET: SMART GLASSES AR-HUD      ")
print("========================================")

if not Net.init() then
    print("ERROR: No modem attached!")
    return
end

local overlay = nil
local speaker = nil
local notifications = {}
local telemetryData = {
    stressPct   = 0,
    energyPct   = 0,
    storagePct  = 0,
    threatCount = 0,
    lastUpdate  = 0,
}

local playerPos = { x = 0, y = 0, z = 0 }
local hasGPS = false

local NOTIF_LIFETIME = Config.GLASSES.NOTIF_DURATION or 10
local MAX_NOTIFS     = Config.GLASSES.MAX_NOTIFICATIONS or 5

local COLORS = {
    bg          = 0x111122,
    panel       = 0x1A1A2E,
    border      = 0x334466,
    text        = 0xFFFFFF,
    textDim     = 0x8899AA,
    header      = 0x00FFBB,
    threat      = 0xFF2244,
    warning     = 0xFFAA00,
    success     = 0x22FF66,
    info        = 0x00AAFF,
    coords      = 0xFFDD44,
}

local SEV_MAP = {
    critical = { label = "CRITICAL", color = COLORS.threat },
    danger   = { label = "THREAT",   color = COLORS.threat },
    error    = { label = "ALERT",    color = COLORS.threat },
    warning  = { label = "WARN",     color = COLORS.warning },
    success  = { label = "SUCCESS",  color = COLORS.success },
    info     = { label = "INFO",     color = COLORS.info },
}

-- ── Поиск модуля Overlay в AP 0.8 ─────────────────────────────

-- 1. Проверяем нативный глобальный API Smart Glasses
if smartglasses and smartglasses.modules then
    pcall(function()
        overlay = smartglasses.modules.overlay
    end)
end

-- 2. Проверяем все подключенные периферии
if not overlay then
    for _, name in ipairs(peripheral.getNames()) do
        local p = peripheral.wrap(name)
        if p then
            if p.getModule then
                pcall(function() overlay = p.getModule("overlay") end)
            elseif p.createRectangle or p.createText or p.addBox then
                overlay = p
            end

            if p.playSound or peripheral.getType(name):find("speaker", 1, true) then
                speaker = p
                print("[OK] Speaker: " .. name)
            end
        end
        if overlay then
            print("[OK] Smart Glasses Module attached on: " .. name)
            break
        end
    end
end

if not overlay then
    print("[WARN] Overlay module not bound yet. Make sure Smart Glasses have Overlay Module equipped.")
else
    print("[OK] Overlay active: createRectangle & getEyePosition ready.")
end

-- ── Звуковые эффекты через Speaker ───────────────────────────

local function playSound(severity)
    if not speaker or not Config.GLASSES.PLAY_SOUNDS then return end
    local sounds = {
        critical = { "minecraft:block.note_block.bit", 0.5, 1.2 },
        danger   = { "minecraft:block.note_block.bit", 0.6, 1.0 },
        warning  = { "minecraft:block.note_block.bit", 0.8, 1.0 },
        success  = { "minecraft:block.note_block.pling", 2.0, 0.6 },
        info     = { "minecraft:block.note_block.harp", 1.5, 0.5 },
    }
    local snd = sounds[severity] or sounds.info
    pcall(function() speaker.playSound(snd[1], snd[3], snd[2]) end)
end

-- ── Добавление уведомления ───────────────────────────────────

local function addNotification(notif)
    table.insert(notifications, 1, {
        text     = notif.text or "Base Event",
        severity = notif.severity or "info",
        source   = notif.source or "BASE",
        time     = os.clock(),
    })

    while #notifications > MAX_NOTIFS do
        table.remove(notifications)
    end

    print(string.format("[NOTIF] [%s] %s", string.upper(notif.severity or "INFO"), notif.text or ""))
    playSound(notif.severity)
end

-- ── Опрос позиции игрока через встроенный getEyePosition / GPS ─

local function updateCoordinates()
    local updated = false

    -- 1. Нативный метод getEyePosition прямо из очков AP 0.8
    if overlay and overlay.getEyePosition then
        local ok, pos = pcall(overlay.getEyePosition)
        if ok and pos and pos.x then
            playerPos = { x = math.floor(pos.x), y = math.floor(pos.y), z = math.floor(pos.z) }
            hasGPS = true
            updated = true
        end
    end

    -- 2. GPS резерв
    if not updated and gps and gps.locate then
        local gx, gy, gz = gps.locate(1)
        if gx then
            playerPos = { x = math.floor(gx), y = math.floor(gy), z = math.floor(gz) }
            hasGPS = true
            updated = true
        end
    end

    -- Транслируем координаты в сеть на Радар
    if hasGPS then
        Net.broadcast(Protocol.TYPE.TELEMETRY, {
            role      = "glasses_hud",
            playerPos = playerPos,
        })
    end
end

-- ── Безопасные методы отрисовки ───────────────────────────────

local function addBox(x, y, w, h, color, alpha)
    if not overlay then return end
    if overlay.createRectangle then
        pcall(overlay.createRectangle, {
            pos   = { x, y },
            sizes = { w, h },
            color = color,
            alpha = alpha or 0.65,
        })
    elseif overlay.rectangle then
        pcall(overlay.rectangle, {
            pos   = { x, y },
            sizes = { w, h },
            color = color,
            alpha = alpha or 0.65,
        })
    elseif overlay.addBox then
        pcall(overlay.addBox, x, y, w, h, color)
    end
end

local function addText(x, y, text, color, scale)
    if not overlay then return end
    if overlay.createText then
        pcall(overlay.createText, {
            pos   = { x, y },
            text  = tostring(text),
            color = color,
            scale = scale or 1.0,
        })
    elseif overlay.text then
        pcall(overlay.text, {
            pos   = { x, y },
            text  = tostring(text),
            color = color,
            scale = scale or 1.0,
        })
    elseif overlay.addText then
        pcall(overlay.addText, x, y, tostring(text), color)
    end
end

local function drawWidgetBox(x, y, w, h, bgCol, borderCol, alpha)
    addBox(x, y, w, h, bgCol, alpha or 0.65)
end

local function drawProgressBar(x, y, w, h, pct, fillCol, bgCol)
    addBox(x, y, w, h, bgCol or 0x222233, 0.5)
    local fillW = math.max(0, math.floor((w * math.min(100, math.max(0, pct))) / 100))
    if fillW > 0 then
        addBox(x, y, fillW, h, fillCol, 0.9)
    end
end

-- ── Отрисовка HUD ─────────────────────────────────────────────

local function renderHUD()
    if not overlay then
        -- Попытка динамически перепривязать оверлей
        if smartglasses and smartglasses.modules and smartglasses.modules.overlay then
            overlay = smartglasses.modules.overlay
        end
        if not overlay then return end
    end

    pcall(function()
        if overlay.clear then overlay.clear() end
    end)

    local curTime = textutils.formatTime(os.time(), true)

    -- 1. Виджет базы (Справа вверху)
    if Config.GLASSES.SHOW_STATUS_BAR then
        local bx, by = 280, 8
        local bw, bh = 145, hasGPS and 82 or 68

        drawWidgetBox(bx, by, bw, bh, COLORS.panel, COLORS.border, 0.7)

        addText(bx + 6, by + 4, Config.SERVER.NAME .. " BASE STATUS", COLORS.header, 0.8)
        addText(bx + bw - 32, by + 4, curTime, COLORS.textDim, 0.7)

        -- Stress
        local stressCol = telemetryData.stressPct > 85 and COLORS.threat or (telemetryData.stressPct > 70 and COLORS.warning or COLORS.success)
        addText(bx + 6, by + 18, string.format("SU: %d%%", telemetryData.stressPct), COLORS.text, 0.7)
        drawProgressBar(bx + 52, by + 19, 85, 5, telemetryData.stressPct, stressCol)

        -- Storage
        addText(bx + 6, by + 28, string.format("VAULT: %d%%", telemetryData.storagePct), COLORS.text, 0.7)
        drawProgressBar(bx + 52, by + 29, 85, 5, telemetryData.storagePct, COLORS.info)

        -- Radar
        local radCol = telemetryData.threatCount > 0 and COLORS.threat or COLORS.success
        local radTxt = telemetryData.threatCount > 0 and string.format("THREATS: %d", telemetryData.threatCount) or "PERIMETER SECURE"
        addText(bx + 6, by + 39, radTxt, radCol, 0.7)

        -- Координаты GPS из очков
        if hasGPS then
            local posStr = string.format("GPS: %d, %d, %d", playerPos.x, playerPos.y, playerPos.z)
            addText(bx + 6, by + 52, posStr, COLORS.coords, 0.7)
        end
    end

    -- 2. Всплывающие алерты (Слева)
    local ny = 40
    local now = os.clock()

    for i, notif in ipairs(notifications) do
        local age = now - notif.time
        if age < NOTIF_LIFETIME then
            local sevInfo = SEV_MAP[notif.severity] or SEV_MAP.info
            local alpha = math.max(0.1, 1.0 - (age / NOTIF_LIFETIME))

            drawWidgetBox(8, ny, 200, 24, COLORS.panel, sevInfo.color, alpha * 0.75)
            addText(14, ny + 3, "[" .. sevInfo.label .. "] " .. (notif.source or "SYS"), sevInfo.color, 0.65)

            local msg = notif.text or ""
            if #msg > 34 then msg = msg:sub(1, 32) .. ".." end
            addText(14, ny + 12, msg, COLORS.text, 0.7)

            ny = ny + 28
        end
    end
end

-- ── Сетевые обработчики ───────────────────────────────────────

Net.on(Protocol.TYPE.ALERT, function(senderID, payload)
    addNotification(payload)
end)

Net.on(Protocol.TYPE.TELEMETRY, function(senderID, payload)
    if payload.stressPct ~= nil then
        telemetryData.stressPct   = payload.stressPct or 0
        telemetryData.energyPct   = payload.energyPct or 0
        telemetryData.storagePct  = payload.storagePct or 0
        telemetryData.threatCount = payload.threatCount or 0
        telemetryData.lastUpdate  = os.clock()
    end
end)

-- ── Потоки выполнения ─────────────────────────────────────────

local function gpsLoop()
    while true do
        updateCoordinates()
        sleep(2.0)
    end
end

local function renderLoop()
    while true do
        renderHUD()
        sleep(1.0)
    end
end

local function networkLoop()
    while true do
        local ev = { os.pullEvent() }
        if ev[1] == "rednet_message" then
            local senderID, rawPacket, proto = ev[2], ev[3], ev[4]
            Net.processMessage(senderID, rawPacket, proto)
        end
    end
end

parallel.waitForAny(gpsLoop, renderLoop, networkLoop)
