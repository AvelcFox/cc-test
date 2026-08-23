-- ============================================================
-- base_core/services/relay_service.lua
-- Управление Redstone Relay и переключателями базы
-- ============================================================

local Logger = require("/base_core/lib/logger")

local RelayService = {}

local channels = {
    { id = 1, name = "Factory Power",    state = true,  side = "top"    },
    { id = 2, name = "Defense System",   state = false, side = "bottom" },
    { id = 3, name = "Ore Processing",   state = true,  side = "left"   },
    { id = 4, name = "Emergency Sirens", state = false, side = "right"  },
    { id = 5, name = "Base Lighting",    state = true,  side = "back"   },
}

local function saveState()
    local f = fs.open("/base_core/data/relays.json", "w")
    if f then
        f.write(textutils.serialiseJSON(channels))
        f.close()
    end
end

local function loadState()
    if fs.exists("/base_core/data/relays.json") then
        local f = fs.open("/base_core/data/relays.json", "r")
        if f then
            local content = f.readAll()
            f.close()
            local decoded = textutils.unserialiseJSON(content)
            if decoded and type(decoded) == "table" then
                channels = decoded
            end
        end
    end
end

function RelayService.init()
    loadState()
    RelayService.applyAll()
    Logger.info("RELAY", "Relay Service initialized (" .. #channels .. " channels)")
end

function RelayService.applyAll()
    for _, ch in ipairs(channels) do
        -- 1. Обычный redstone на сторонах компьютера
        if ch.side and redstone.getSides then
            pcall(function()
                redstone.setOutput(ch.side, ch.state)
            end)
        end
    end

    -- 2. Поиск внешних Redstone Relays
    for _, name in ipairs(peripheral.getNames()) do
        local pType = peripheral.getType(name)
        if pType and pType:find("redstone_relay", 1, true) then
            local relay = peripheral.wrap(name)
            if relay and relay.setOutput then
                -- Применяем общий статус первого канала по умолчанию
                pcall(relay.setOutput, "front", channels[1].state)
            end
        end
    end
end

function RelayService.toggle(channelId)
    for _, ch in ipairs(channels) do
        if ch.id == channelId then
            ch.state = not ch.state
            RelayService.applyAll()
            saveState()
            Logger.info("RELAY", "Channel '" .. ch.name .. "' set to " .. (ch.state and "ON" or "OFF"))
            return ch.state
        end
    end
    return nil
end

function RelayService.set(channelId, state)
    for _, ch in ipairs(channels) do
        if ch.id == channelId then
            ch.state = state
            RelayService.applyAll()
            saveState()
            Logger.info("RELAY", "Channel '" .. ch.name .. "' set to " .. (state and "ON" or "OFF"))
            return true
        end
    end
    return false
end

function RelayService.getChannels()
    return channels
end

return RelayService
