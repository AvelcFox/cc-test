-- ============================================================
-- base_core/lib/uuid_resolver.lua
-- Преобразование UUID в реальные ники игроков (с кэшированием и HTTP API)
-- ============================================================

local UUIDResolver = {}

local cache = {
    ["df33e35a-b11e-481f-b9e1-2eb071375870"] = "Avellc",
    ["df33e35ab11e481fb9e12eb071375870"]     = "Avellc",
}

local CACHE_FILE = "/base_core/data/uuid_cache.json"

local function loadCache()
    if fs.exists(CACHE_FILE) then
        local f = fs.open(CACHE_FILE, "r")
        if f then
            local raw = f.readAll()
            f.close()
            local decoded = textutils.unserialiseJSON(raw)
            if decoded and type(decoded) == "table" then
                for k, v in pairs(decoded) do
                    cache[k] = v
                end
            end
        end
    end
end

local function saveCache()
    local f = fs.open(CACHE_FILE, "w")
    if f then
        f.write(textutils.serialiseJSON(cache))
        f.close()
    end
end

loadCache()

local pendingQueries = {}

-- Попытка асинхронно запросить ник по UUID через Mojang / PlayerDB API
local function queryMojangAPI(uuid)
    if not http then return end
    if pendingQueries[uuid] then return end
    pendingQueries[uuid] = true

    local cleanUUID = uuid:gsub("-", "")
    local url = "https://sessionserver.mojang.com/session/minecraft/profile/" .. cleanUUID

    pcall(function()
        http.request(url)
    end)
end

function UUIDResolver.getName(idStr, entityType)
    if not idStr then return "Unknown" end
    local id = tostring(idStr)

    -- Если это уже обычный ник (не длинный UUID)
    if not id:find("-", 1, true) and #id < 20 and not id:find("^[0-9a-fA-F]+$") then
        return id
    end

    -- Проверяем локальный кэш
    if cache[id] then
        return cache[id]
    end
    local noDash = id:gsub("-", "")
    if cache[noDash] then
        return cache[noDash]
    end

    -- Если это игрок, пытаемся разрешить через HTTP API
    if (entityType and (entityType == "player" or entityType == "Player")) or #id >= 32 then
        queryMojangAPI(id)
    end

    -- Если это contraption или mob
    if entityType and entityType ~= "player" and entityType ~= "Player" and entityType ~= "Entity" then
        return entityType .. " (" .. id:sub(1, 4) .. ")"
    end

    -- Временно возвращаем сокращенный ID пока идет запрос
    return "Player-" .. id:sub(1, 6)
end

function UUIDResolver.register(uuid, name)
    if uuid and name then
        cache[tostring(uuid)] = tostring(name)
        local noDash = tostring(uuid):gsub("-", "")
        cache[noDash] = tostring(name)
        saveCache()
    end
end

-- Обработка ответа от HTTP запроса
function UUIDResolver.handleHttpResponse(url, response)
    if not url or not response then return end
    if url:find("mojang.com", 1, true) or url:find("playerdb.co", 1, true) then
        local body = response.readAll()
        response.close()
        local data = textutils.unserialiseJSON(body)
        if data and data.name and data.id then
            UUIDResolver.register(data.id, data.name)
            return true, data.name
        end
    end
    return false
end

return UUIDResolver
