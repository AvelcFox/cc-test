-- ============================================================
-- base_core/clients/pocket_remote.lua
-- Карманный терминал управления BaseCore OS (Pocket Computer)
-- ============================================================

local Config   = require("/base_core/config")
local Protocol = require("/base_core/lib/protocol")
local Net      = require("/base_core/lib/net")

term.clear()
term.setCursorPos(1, 1)

if not Net.init() then
    print("Error: Modem required for Pocket Remote!")
    return
end

local baseState = {
    create  = {},
    storage = {},
    radar   = {},
    relays  = {},
}

local function requestStatus()
    Net.broadcast(Protocol.TYPE.COMMAND, { action = "GET_STATUS" })
end

Net.on(Protocol.TYPE.RESPONSE, function(senderID, payload)
    baseState.create  = payload.create or {}
    baseState.storage = payload.storage or {}
    baseState.radar   = payload.radar or {}
    baseState.relays  = payload.relays or {}
end)

Net.on(Protocol.TYPE.COMMAND_RESP, function(senderID, payload)
    if payload.relays then
        baseState.relays = payload.relays
    end
end)

local function drawGUI()
    term.setBackgroundColor(colors.black)
    term.clear()

    local w, h = term.getSize()

    -- Шапка
    term.setBackgroundColor(colors.gray)
    term.setTextColor(colors.yellow)
    term.setCursorPos(1, 1)
    term.write(string.format("%-" .. w .. "s", " NEXUS REMOTE"))

    -- Статус
    local stress = baseState.create.stress or { pct = 0 }
    local threats = (baseState.radar.threatCount or 0)
    term.setBackgroundColor(colors.black)
    term.setCursorPos(2, 3)
    term.setTextColor(colors.cyan)
    term.write("Kinetic: ")
    term.setTextColor(stress.pct > 80 and colors.red or colors.green)
    term.write(stress.pct .. "%  ")

    term.setTextColor(colors.cyan)
    term.write("Threats: ")
    term.setTextColor(threats > 0 and colors.red or colors.green)
    term.write(tostring(threats))

    -- Реле
    term.setTextColor(colors.yellow)
    term.setCursorPos(2, 5)
    term.write("--- Base Relays ---")

    local y = 7
    for i, ch in ipairs(baseState.relays or {}) do
        if y < h - 2 then
            term.setCursorPos(2, y)
            term.setTextColor(colors.white)
            term.write(string.format("[%d] %-12s", ch.id, ch.name:sub(1, 12)))

            term.setCursorPos(w - 7, y)
            if ch.state then
                term.setBackgroundColor(colors.green)
                term.setTextColor(colors.black)
                term.write("[ ON ]")
            else
                term.setBackgroundColor(colors.red)
                term.setTextColor(colors.white)
                term.write("[ OFF]")
            end
            term.setBackgroundColor(colors.black)
            y = y + 2
        end
    end

    -- Подвал
    term.setBackgroundColor(colors.gray)
    term.setTextColor(colors.white)
    term.setCursorPos(1, h)
    term.write(string.format("%-" .. w .. "s", " [1-5] Toggle | [Q] Exit"))
end

requestStatus()

local function renderLoop()
    while true do
        drawGUI()
        sleep(1.0)
    end
end

local function inputLoop()
    while true do
        local ev = { os.pullEvent() }
        local event = ev[1]

        if event == "char" then
            local ch = ev[2]
            if ch == "q" or ch == "Q" then
                break
            end
            local num = tonumber(ch)
            if num and num >= 1 and num <= 5 then
                Net.broadcast(Protocol.TYPE.COMMAND, { action = "TOGGLE_RELAY", channelId = num })
                drawGUI()
            end
        elseif event == "mouse_click" then
            local mx, my = ev[3], ev[4]
            local relIdx = math.floor((my - 7) / 2) + 1
            if relIdx >= 1 and relIdx <= #(baseState.relays or {}) then
                local targetCh = baseState.relays[relIdx]
                if targetCh then
                    Net.broadcast(Protocol.TYPE.COMMAND, { action = "TOGGLE_RELAY", channelId = targetCh.id })
                    drawGUI()
                end
            end
        elseif event == "rednet_message" then
            local senderID, rawPacket, proto = ev[2], ev[3], ev[4]
            Net.processMessage(senderID, rawPacket, proto)
            drawGUI()
        end
    end
end

parallel.waitForAny(renderLoop, inputLoop)
term.setBackgroundColor(colors.black)
term.clear()
term.setCursorPos(1, 1)
print("Pocket Remote closed.")
