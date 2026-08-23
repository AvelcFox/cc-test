-- ============================================================
-- base_core/clients/glasses_hud.lua
-- Клиент дополненной реальности (AR HUD) для Smart Glasses AP 0.8
-- Персистентные объекты: БЕЗ CLEAR(), БЕЗ МЕРЦАНИЯ, 60 FPS
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
local MAX_NOTIFS     = 4

local COLORS = {
    bg          = 0x111122,
    panel       = 0x151525,
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

if smartglasses and smartglasses.modules then
    pcall(function() overlay = smartglasses.modules.overlay end)
end

if not overlay then
    for _, name in ipairs(peripheral.getNames()) do
        local p = peripheral.wrap(name)
        if p then
            if p.getModule then
                pcall(function() overlay = p.getModule("overlay") end)
            elseif p.createRectangle or p.createText then
                overlay = p
            end

            if p.playSound or p.playNote or peripheral.getType(name):find("speaker", 1, true) then
                speaker = p
                print("[OK] Speaker: " .. name)
            end
        end
        if overlay then
            print("[OK] Smart Glasses Module on: " .. name)
            break
        end
    end
end

if not overlay then
    print("[WARN] Overlay module not bound yet. Make sure Smart Glasses have Overlay Module equipped.")
else
    if overlay.setAutoUpdate then pcall(overlay.setAutoUpdate, true) end
    pcall(overlay.clear) -- Очищаем один раз при старте
    print("[OK] Overlay active: Persistent Zero-Flicker Renderer ready.")
end

-- ── Звуковые эффекты через Speaker ───────────────────────────

local function playSound(severity)
    if not speaker or not Config.GLASSES.PLAY_SOUNDS then return end
    local sounds = {
        critical = { "minecraft:block.note_block.bit", 1.0, 1.2 },
        danger   = { "minecraft:block.note_block.bit", 1.0, 1.0 },
        warning  = { "minecraft:block.note_block.bit", 1.0, 1.0 },
        success  = { "minecraft:block.note_block.pling", 2.0, 0.8 },
        info     = { "minecraft:block.note_block.harp", 1.5, 0.6 },
    }
    local snd = sounds[severity] or sounds.info
    pcall(function()
        if speaker.playSound then
            speaker.playSound(snd[1], snd[3], snd[2])
        elseif speaker.playNote then
            speaker.playNote("pling", snd[3], 12)
        end
    end)
end

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

-- ── Персистентные объекты интерфейса ──────────────────────────

local hudUI = {
    initialized = false,
    -- Базовый виджет
    bgPanel     = nil,
    txtHeader   = nil,
    txtTime     = nil,
    txtStress   = nil,
    bgStress    = nil,
    barStress   = nil,
    txtVault    = nil,
    bgVault     = nil,
    barVault    = nil,
    txtRadar    = nil,
    txtGPS      = nil,
    -- Уведомления (4 слота)
    notifs      = {},
}

local function initHUDObjects()
    if not overlay or hudUI.initialized then return end

    local bx, by = 280, 8
    local bw, bh = 145, 68

    -- 1. Фоновые панели виджета базы (Z = 0)
    hudUI.bgPanel = overlay.createRectangle({
        x = bx, y = by, z = 0.0,
        sizeX = bw, sizeY = bh,
        color = COLORS.panel, opacity = 0.65,
    })

    -- Шкалы прогресса (Z = 1 фоновые дорожки, Z = 2 заполнение)
    hudUI.bgStress = overlay.createRectangle({
        x = bx + 52, y = by + 19, z = 1.0,
        sizeX = 85, sizeY = 5,
        color = 0x222233, opacity = 0.5,
    })
    hudUI.barStress = overlay.createRectangle({
        x = bx + 52, y = by + 19, z = 2.0,
        sizeX = 0, sizeY = 5,
        color = COLORS.success, opacity = 0.9,
    })

    hudUI.bgVault = overlay.createRectangle({
        x = bx + 52, y = by + 29, z = 1.0,
        sizeX = 85, sizeY = 5,
        color = 0x222233, opacity = 0.5,
    })
    hudUI.barVault = overlay.createRectangle({
        x = bx + 52, y = by + 29, z = 2.0,
        sizeX = 0, sizeY = 5,
        color = COLORS.info, opacity = 0.9,
    })

    -- 2. Текстовые метки поверх фона (Z = 5)
    hudUI.txtHeader = overlay.createText({
        x = bx + 6, y = by + 4, z = 5.0,
        content = Config.SERVER.NAME .. " BASE STATUS",
        color = COLORS.header, fontSize = 0.8, shadow = true,
    })
    hudUI.txtTime = overlay.createText({
        x = bx + bw - 32, y = by + 4, z = 5.0,
        content = "12:00",
        color = COLORS.textDim, fontSize = 0.7, shadow = true,
    })
    hudUI.txtStress = overlay.createText({
        x = bx + 6, y = by + 18, z = 5.0,
        content = "SU: 0%",
        color = COLORS.text, fontSize = 0.7, shadow = true,
    })
    hudUI.txtVault = overlay.createText({
        x = bx + 6, y = by + 28, z = 5.0,
        content = "VAULT: 0%",
        color = COLORS.text, fontSize = 0.7, shadow = true,
    })
    hudUI.txtRadar = overlay.createText({
        x = bx + 6, y = by + 39, z = 5.0,
        content = "PERIMETER SECURE",
        color = COLORS.success, fontSize = 0.7, shadow = true,
    })
    hudUI.txtGPS = overlay.createText({
        x = bx + 6, y = by + 52, z = 5.0,
        content = "GPS: OFFLINE",
        color = COLORS.textDim, fontSize = 0.7, shadow = true,
    })

    -- 3. Слоты всплывающих уведомлений (Слева, 4 слота)
    local ny = 40
    for i = 1, MAX_NOTIFS do
        local slot = {}
        slot.bg = overlay.createRectangle({
            x = 8, y = ny, z = 0.0,
            sizeX = 200, sizeY = 24,
            color = COLORS.panel, opacity = 0.0, enabled = false,
        })
        slot.title = overlay.createText({
            x = 14, y = ny + 3, z = 5.0,
            content = "",
            color = COLORS.info, fontSize = 0.65, shadow = true, enabled = false,
        })
        slot.body = overlay.createText({
            x = 14, y = ny + 12, z = 5.0,
            content = "",
            color = COLORS.text, fontSize = 0.7, shadow = true, enabled = false,
        })
        hudUI.notifs[i] = slot
        ny = ny + 28
    end

    hudUI.initialized = true
    print("[OK] HUD visual elements instantiated in VRAM.")
end

-- ── Мгновенное обновление свойств без удаления (60 FPS) ───────

local function updateHUD()
    if not hudUI.initialized then
        initHUDObjects()
        if not hudUI.initialized then return end
    end

    local curTime = textutils.formatTime(os.time(), true)

    -- Обновляем время
    if hudUI.txtTime and hudUI.txtTime.setContent then
        hudUI.txtTime.setContent(curTime)
    end

    -- Обновляем Create Stress
    local stressPct = telemetryData.stressPct or 0
    local stressCol = stressPct > 85 and COLORS.threat or (stressPct > 70 and COLORS.warning or COLORS.success)
    if hudUI.txtStress and hudUI.txtStress.setContent then
        hudUI.txtStress.setContent(string.format("SU: %d%%", stressPct))
    end
    if hudUI.barStress then
        local fillW = math.max(0, math.floor((85 * math.min(100, math.max(0, stressPct))) / 100))
        if hudUI.barStress.setSizeX then hudUI.barStress.setSizeX(fillW) end
        if hudUI.barStress.setSizes then hudUI.barStress.setSizes(fillW, 5) end
        if hudUI.barStress.setColor then hudUI.barStress.setColor(stressCol) end
    end

    -- Обновляем Storage
    local storagePct = telemetryData.storagePct or 0
    if hudUI.txtVault and hudUI.txtVault.setContent then
        hudUI.txtVault.setContent(string.format("VAULT: %d%%", storagePct))
    end
    if hudUI.barVault then
        local fillW = math.max(0, math.floor((85 * math.min(100, math.max(0, storagePct))) / 100))
        if hudUI.barVault.setSizeX then hudUI.barVault.setSizeX(fillW) end
        if hudUI.barVault.setSizes then hudUI.barVault.setSizes(fillW, 5) end
    end

    -- Обновляем Радар
    if hudUI.txtRadar and hudUI.txtRadar.setContent then
        local radCol = telemetryData.threatCount > 0 and COLORS.threat or COLORS.success
        local radTxt = telemetryData.threatCount > 0 and string.format("THREATS: %d", telemetryData.threatCount) or "PERIMETER SECURE"
        hudUI.txtRadar.setContent(radTxt)
        if hudUI.txtRadar.setColor then hudUI.txtRadar.setColor(radCol) end
    end

    -- Обновляем GPS
    if hudUI.txtGPS and hudUI.txtGPS.setContent then
        local posStr = hasGPS and string.format("GPS: %d, %d, %d", playerPos.x, playerPos.y, playerPos.z) or "GPS: OFFLINE"
        hudUI.txtGPS.setContent(posStr)
        if hudUI.txtGPS.setColor then hudUI.txtGPS.setColor(hasGPS and COLORS.coords or COLORS.textDim) end
    end

    -- Обновляем всплывающие уведомления (плавное затухание)
    local now = os.clock()
    for i = 1, MAX_NOTIFS do
        local slot = hudUI.notifs[i]
        local notif = notifications[i]
        if slot and notif then
            local age = now - notif.time
            if age < NOTIF_LIFETIME then
                local sevInfo = SEV_MAP[notif.severity] or SEV_MAP.info
                local alpha = math.max(0.05, 1.0 - (age / NOTIF_LIFETIME))

                if slot.bg and slot.bg.setEnabled then slot.bg.setEnabled(true) end
                if slot.bg and slot.bg.setOpacity then slot.bg.setOpacity(alpha * 0.7) end

                if slot.title and slot.title.setEnabled then slot.title.setEnabled(true) end
                if slot.title and slot.title.setContent then slot.title.setContent("[" .. sevInfo.label .. "] " .. (notif.source or "SYS")) end
                if slot.title and slot.title.setColor then slot.title.setColor(sevInfo.color) end

                local msg = notif.text or ""
                if #msg > 34 then msg = msg:sub(1, 32) .. ".." end
                if slot.body and slot.body.setEnabled then slot.body.setEnabled(true) end
                if slot.body and slot.body.setContent then slot.body.setContent(msg) end
            else
                if slot.bg and slot.bg.setEnabled then slot.bg.setEnabled(false) end
                if slot.title and slot.title.setEnabled then slot.title.setEnabled(false) end
                if slot.body and slot.body.setEnabled then slot.body.setEnabled(false) end
            end
        elseif slot then
            if slot.bg and slot.bg.setEnabled then slot.bg.setEnabled(false) end
            if slot.title and slot.title.setEnabled then slot.title.setEnabled(false) end
            if slot.body and slot.body.setEnabled then slot.body.setEnabled(false) end
        end
    end

    -- Синхронизация изменений с клиентом
    if overlay and overlay.update then
        pcall(overlay.update)
    end
end

-- ── Опрос позиции игрока ──────────────────────────────────────

local function updateCoordinates()
    local updated = false

    if overlay and overlay.getEyePosition then
        local res = { pcall(overlay.getEyePosition) }
        if res[1] then
            if type(res[2]) == "number" and type(res[3]) == "number" and type(res[4]) == "number" then
                playerPos = { x = math.floor(res[2]), y = math.floor(res[3]), z = math.floor(res[4]) }
                hasGPS = true
                updated = true
            elseif type(res[2]) == "table" then
                local t = res[2]
                local px = tonumber(t.x or t[1])
                local py = tonumber(t.y or t[2]) or 0
                local pz = tonumber(t.z or t[3])
                if px and pz then
                    playerPos = { x = math.floor(px), y = math.floor(py), z = math.floor(pz) }
                    hasGPS = true
                    updated = true
                end
            end
        end
    end

    if not updated and gps and gps.locate then
        local gx, gy, gz = gps.locate(1)
        if gx then
            playerPos = { x = math.floor(gx), y = math.floor(gy), z = math.floor(gz) }
            hasGPS = true
            updated = true
        end
    end

    if hasGPS then
        Net.broadcast(Protocol.TYPE.TELEMETRY, {
            role      = "glasses_hud",
            playerPos = playerPos,
        })
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
        sleep(1.0)
    end
end

local function renderLoop()
    while true do
        pcall(updateHUD)
        sleep(0.05) -- 20 FPS идеально плавное обновление без малейшего мерцания
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
