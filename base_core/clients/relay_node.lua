-- ============================================================
-- base_core/clients/relay_node.lua
-- Динамический узел управления Redstone Relays
-- С интерактивным редактором названий каналов (клавиша 'E')
-- ============================================================

local Config   = require("/base_core/config")
local Protocol = require("/base_core/lib/protocol")
local Net      = require("/base_core/lib/net")

local RELAY_CONFIG_FILE = "/base_core/data/local_relays.json"
local configuredRelays = {}

local function loadRelayConfig()
    if fs.exists(RELAY_CONFIG_FILE) then
        local f = fs.open(RELAY_CONFIG_FILE, "r")
        if f then
            local raw = f.readAll()
            f.close()
            local decoded = textutils.unserialiseJSON(raw)
            if decoded and type(decoded) == "table" then
                configuredRelays = decoded
            end
        end
    end
end

local function saveRelayConfig()
    local f = fs.open(RELAY_CONFIG_FILE, "w")
    if f then
        f.write(textutils.serialiseJSON(configuredRelays))
        f.close()
    end
end

-- Автоматический поиск всех физических реле и сторон
local function scanPhysicalRelays()
    loadRelayConfig()
    local found = {}

    -- 1. Поиск внешних периферийных Redstone Relays
    for _, name in ipairs(peripheral.getNames()) do
        local pType = peripheral.getType(name) or ""
        if pType:find("redstone_relay", 1, true) or pType:find("relay", 1, true) then
            local rel = peripheral.wrap(name)
            if rel and rel.setOutput then
                local saved = configuredRelays[name] or {}
                table.insert(found, {
                    uid    = name,
                    type   = "peripheral",
                    name   = saved.name or ("Relay " .. name:gsub("peripheral.", ""):gsub("redstone_relay_", "#")),
                    state  = saved.state or false,
                    target = name,
                    p      = rel,
                })
            end
        end
    end

    -- 2. Добавляем физические стороны компьютера
    if redstone.getSides then
        for _, side in ipairs(redstone.getSides()) do
            local uid = "side_" .. side
            local saved = configuredRelays[uid]
            if saved or #found == 0 then
                table.insert(found, {
                    uid    = uid,
                    type   = "side",
                    name   = (saved and saved.name) or ("Port " .. string.upper(side)),
                    state  = (saved and saved.state) or false,
                    target = side,
                })
            end
        end
    end

    return found
end

local relays = scanPhysicalRelays()

-- Применение текущих состояний на физические выходы
local function applyRelay(ch)
    if ch.type == "peripheral" and ch.p and ch.p.setOutput then
        pcall(ch.p.setOutput, "front", ch.state)
        pcall(ch.p.setOutput, "top", ch.state)
    elseif ch.type == "side" and redstone.setOutput then
        pcall(redstone.setOutput, ch.target, ch.state)
    end

    configuredRelays[ch.uid] = { name = ch.name, state = ch.state }
    saveRelayConfig()
end

local function applyAll()
    for _, ch in ipairs(relays) do
        applyRelay(ch)
    end
end

-- Формирование списка для трансляции на сервер
local function getRelayList()
    local list = {}
    for _, ch in ipairs(relays) do
        table.insert(list, {
            uid     = ch.uid,
            nodeId  = os.getComputerID(),
            name    = ch.name,
            state   = ch.state,
            type    = ch.type,
        })
    end
    return list
end

local function broadcastState()
    Net.broadcast(Protocol.TYPE.TELEMETRY, {
        role    = "relay_node",
        nodeId  = os.getComputerID(),
        relays  = getRelayList(),
    })
end

-- ── Интерактивный редактор названий реле ──────────────────────

local function interactiveConfig()
    term.clear()
    term.setCursorPos(1, 1)
    term.setTextColor(colors.yellow)
    print("=== RELAY CHANNEL CONFIGURATION ===")
    term.setTextColor(colors.white)
    print("Computer ID: " .. os.getComputerID() .. "\n")

    for i, ch in ipairs(relays) do
        term.setTextColor(colors.cyan)
        io.write(string.format(" [%d] ", i))
        term.setTextColor(colors.white)
        io.write(string.format("%-22s -> ", ch.uid))
        term.setTextColor(colors.green)
        print('"' .. ch.name .. '"')
    end

    term.setTextColor(colors.lightGray)
    print("\n[A] Add Computer Side port (top/bottom/left/right/back)")
    print("[Q] Finish and Start Node")
    term.setTextColor(colors.yellow)
    io.write("\nSelect channel number to rename [1-" .. #relays .. ", A, Q]: ")
    term.setTextColor(colors.white)
    local inp = read()

    if inp == "q" or inp == "Q" or inp == "" then
        return
    elseif inp == "a" or inp == "A" then
        print("\nEnter side name (top, bottom, left, right, front, back):")
        local s = read():lower()
        if s == "top" or s == "bottom" or s == "left" or s == "right" or s == "front" or s == "back" then
            print("Enter friendly name for Port " .. string.upper(s) .. " (e.g. 'Tree Farm'):")
            local customName = read()
            if customName ~= "" then
                local uid = "side_" .. s
                configuredRelays[uid] = { name = customName, state = false }
                saveRelayConfig()
                relays = scanPhysicalRelays()
            end
        end
        interactiveConfig()
    else
        local idx = tonumber(inp)
        if idx and relays[idx] then
            local target = relays[idx]
            print("\nEnter new friendly name for " .. target.uid .. " (Current: '" .. target.name .. "'):")
            print("Examples: 'Iron Farm', 'Andesite Line', 'Defense Guns', 'Base Lighting'")
            io.write("> ")
            local newName = read()
            if newName and newName ~= "" then
                target.name = newName
                configuredRelays[target.uid] = { name = newName, state = target.state }
                saveRelayConfig()
                print("[OK] Renamed to '" .. newName .. "'")
                sleep(0.8)
            end
            interactiveConfig()
        end
    end
end

-- ── Запуск ───────────────────────────────────────────────────

term.clear()
term.setCursorPos(1, 1)

if not Net.init() then
    print("ERROR: No modem attached!")
    return
end

applyAll()

-- Обработка сетевых команд переключения
Net.on(Protocol.TYPE.COMMAND, function(senderID, payload)
    local targetUid = payload.relayUid or payload.uid
    local targetName = payload.name
    local newState = payload.state

    local modified = false
    for _, ch in ipairs(relays) do
        if (targetUid and ch.uid == targetUid) or (targetName and string.lower(ch.name) == string.lower(targetName)) then
            if newState ~= nil then
                ch.state = not not newState
            else
                ch.state = not ch.state
            end
            applyRelay(ch)
            modified = true
            print(string.format("[CMD] Relay '%s' -> %s", ch.name, ch.state and "ON" or "OFF"))
        end
    end

    if modified then
        broadcastState()
    end
end)

local function drawScreen()
    term.clear()
    term.setCursorPos(1, 1)
    term.setTextColor(colors.yellow)
    print("========================================")
    print("     NEXINET: DYNAMIC RELAY NODE        ")
    print("========================================")
    term.setTextColor(colors.white)
    print(string.format("Node ID: %d | Active Channels: %d\n", os.getComputerID(), #relays))

    for i, ch in ipairs(relays) do
        term.setTextColor(colors.lightGray)
        io.write(string.format(" [%d] %-20s ", i, ch.name))
        if ch.state then
            term.setTextColor(colors.green)
            print("[ ACTIVE / ON ]")
        else
            term.setTextColor(colors.red)
            print("[ DISABLED / OFF ]")
        end
    end

    term.setTextColor(colors.gray)
    print("\n----------------------------------------")
    print("Press [E] to Rename channels / Add ports")
    print("Press [1-" .. math.min(9, #relays) .. "] to Toggle manually")
    print("Press [Q] to Exit")
end

drawScreen()
broadcastState()

-- ── Главный цикл: трансляция и клавиатурный ввод ──────────────

local function inputLoop()
    while true do
        local ev = { os.pullEvent() }
        if ev[1] == "char" then
            local ch = ev[2]:lower()
            if ch == "e" then
                interactiveConfig()
                applyAll()
                drawScreen()
                broadcastState()
            elseif ch == "q" then
                break
            else
                local num = tonumber(ch)
                if num and relays[num] then
                    relays[num].state = not relays[num].state
                    applyRelay(relays[num])
                    drawScreen()
                    broadcastState()
                end
            end
        elseif ev[1] == "rednet_message" then
            local senderID, rawPacket, proto = ev[2], ev[3], ev[4]
            Net.processMessage(senderID, rawPacket, proto)
            drawScreen()
        end
    end
end

local function broadcastLoop()
    while true do
        broadcastState()
        sleep(3.0)
    end
end

parallel.waitForAny(inputLoop, broadcastLoop)
