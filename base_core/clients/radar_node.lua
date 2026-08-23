-- ============================================================
-- base_core/clients/radar_node.lua
-- Выделенный пост безопасности и радарной станции (Computer 3)
-- С интеграцией координат GPS и Smart Glasses
-- ============================================================

local Config       = require("/base_core/config")
local Protocol     = require("/base_core/lib/protocol")
local Net          = require("/base_core/lib/net")
local UUIDResolver = require("/base_core/lib/uuid_resolver")

term.clear()
term.setCursorPos(1, 1)

print("========================================")
print("     NEXINET: RADAR OUTPOST NODE        ")
print("========================================")

if not Net.init() then
    print("ERROR: No modem attached!")
    return
end

local function isAlly(name)
    if not name or name == "" then return false end
    local clean = string.lower(tostring(name)):gsub("^%s+", ""):gsub("%s+$", "")
    for _, ally in ipairs(Config.ALLIES or {}) do
        local a = string.lower(tostring(ally)):gsub("^%s+", ""):gsub("%s+$", "")
        if clean == a then
            return true
        end
    end
    return false
end

local function findRadarPeripherals()
    local pd = nil
    local radarMon = nil

    for _, name in ipairs(peripheral.getNames()) do
        local pType = peripheral.getType(name) or ""
        if pType:find("player", 1, true) or pType:find("detector", 1, true) then
            pd = peripheral.wrap(name)
        elseif pType:find("create_radar", 1, true) or pType:find("radar", 1, true) then
            local dev = peripheral.wrap(name)
            if dev.getTracks or dev.getTargets or dev.getEntities then
                radarMon = dev
            end
        end
    end

    return pd, radarMon
end

local pd, radarMon = findRadarPeripherals()
if not pd and not radarMon then
    print("WARNING: No Radar Monitor or Player Detector found!")
else
    if pd then print("[OK] Player Detector: " .. peripheral.getName(pd)) end
    if radarMon then print("[OK] Create Radar:    " .. peripheral.getName(radarMon)) end
end

print("Protocol: " .. Config.NETWORK.PROTOCOL)

-- Позиция радара (по GPS) и позиция игрока (из Очков)
local radarPos = nil
local playerPos = nil

local function updateGPS()
    if gps and gps.locate then
        local gx, gy, gz = gps.locate(1)
        if gx then
            radarPos = { x = math.floor(gx), y = math.floor(gy), z = math.floor(gz) }
        end
    end
end

updateGPS()
if radarPos then
    print(string.format("[GPS] Station Pos: %d, %d, %d", radarPos.x, radarPos.y, radarPos.z))
end

-- Приём позиции игрока от Smart Glasses
Net.on(Protocol.TYPE.TELEMETRY, function(senderID, payload)
    if payload.role == "glasses_hud" and payload.playerPos then
        playerPos = payload.playerPos
    end
end)

-- Универсальное извлечение дистанции
local function extractDistance(t)
    if not t or type(t) ~= "table" then return 0 end

    if t.distance and tonumber(t.distance) then return math.floor(tonumber(t.distance)) end
    if t.range and tonumber(t.range) then return math.floor(tonumber(t.range)) end
    if t.radius and tonumber(t.radius) then return math.floor(tonumber(t.radius)) end
    if t.dist and tonumber(t.dist) then return math.floor(tonumber(t.dist)) end
    if t.r and tonumber(t.r) then return math.floor(tonumber(t.r)) end

    -- Поиск вложенных таблиц координат
    local posTables = { t.position, t.pos, t.location, t.coords, t.coordinates, t.vector, t.targetPos, t.origin }
    for _, pt in ipairs(posTables) do
        if pt and type(pt) == "table" then
            local px = tonumber(pt.x or pt.X or pt[1])
            local py = tonumber(pt.y or pt.Y or pt[2]) or 0
            local pz = tonumber(pt.z or pt.Z or pt[3])
            if px and pz then
                -- Если координаты абсолютные и известна позиция радара/игрока
                local refPos = playerPos or radarPos
                if refPos and (math.abs(px) > 500 or math.abs(pz) > 500) then
                    return math.floor(math.sqrt((px - refPos.x)^2 + (pz - refPos.z)^2))
                else
                    local d = math.floor(math.sqrt(px^2 + py^2 + pz^2))
                    if d > 0 then return d end
                end
            end
        end
    end

    local relX = tonumber(t.relativeX or t.relX or t.deltaX or t.dx or t.motionX)
    local relZ = tonumber(t.relativeZ or t.relZ or t.deltaZ or t.dz or t.motionZ)
    if relX and relZ and (relX ~= 0 or relZ ~= 0) then
        local d = math.floor(math.sqrt(relX^2 + relZ^2))
        if d > 0 then return d end
    end

    local rawX = tonumber(t.x or t.posX or t.X)
    local rawY = tonumber(t.y or t.posY or t.Y) or 0
    local rawZ = tonumber(t.z or t.posZ or t.Z)
    if rawX and rawZ and (rawX ~= 0 or rawZ ~= 0) then
        local refPos = playerPos or radarPos
        if refPos and (math.abs(rawX) > 500 or math.abs(rawZ) > 500) then
            return math.floor(math.sqrt((rawX - refPos.x)^2 + (rawZ - refPos.z)^2))
        elseif math.abs(rawX) < 500 and math.abs(rawZ) < 500 then
            return math.floor(math.sqrt(rawX^2 + rawY^2 + rawZ^2))
        end
    end

    return 0
end

local alertTracker = {}

local function shouldTriggerAlert(targetKey, currentDist)
    local now = os.clock()
    local last = alertTracker[targetKey]

    if not last then
        alertTracker[targetKey] = { time = now, dist = currentDist }
        return true
    end

    if (now - last.time > 45) or (last.dist - currentDist >= 20 and now - last.time > 10) then
        last.time = now
        last.dist = currentDist
        return true
    end

    return false
end

-- ── Поток 1: Сканирование радара ─────────────────────────────

local function radarLoop()
    while true do
        local entities = {}
        local threats = {}
        local threatMaxDist = Config.RADAR and Config.RADAR.THREAT_DIST or 120
        local detectedKeys = {}

        -- 1. Player Detector
        if pd then
            local ok, players = pcall(pd.getPlayersInRange, 64)
            if not ok or not players then
                ok, players = pcall(pd.getPlayersInCoords, { x1 = -64, y1 = -64, z1 = -64, x2 = 64, y2 = 64, z2 = 64 })
            end

            if ok and players and type(players) == "table" then
                for _, p in pairs(players) do
                    local pName = type(p) == "string" and p or (p.name or "Unknown")
                    local friend = isAlly(pName)
                    local dist = 0
                    if type(p) == "table" and p.distance then
                        dist = math.floor(tonumber(p.distance) or 0)
                    end

                    detectedKeys[string.lower(pName)] = true

                    local status = friend and "ALLY" or "HOSTILE"
                    local entry = {
                        name   = tostring(pName),
                        type   = "Player",
                        status = status,
                        isAlly = friend,
                        dist   = tonumber(dist) or 0,
                        yaw    = 0,
                        pitch  = 0,
                    }
                    table.insert(entities, entry)

                    if not friend and dist <= threatMaxDist then
                        table.insert(threats, {
                            name   = entry.name,
                            type   = "Player",
                            status = "HOSTILE",
                            isAlly = false,
                            dist   = entry.dist,
                            yaw    = 0,
                            pitch  = 0,
                        })
                    end
                end
            end
        end

        -- 2. Create Radar Monitor
        if radarMon then
            local ok, tracks = pcall(function()
                if radarMon.getTracks then return radarMon.getTracks()
                elseif radarMon.getTargets then return radarMon.getTargets()
                elseif radarMon.getEntities then return radarMon.getEntities() end
                return nil
            end)

            if ok and tracks and type(tracks) == "table" then
                for k, t in pairs(tracks) do
                    if type(t) == "table" then
                        local rawId = t.playerName or t.entityName or t.name or t.id or tostring(k)
                        local rawType = tostring(t.entityType or t.type or "Entity"):gsub("minecraft:", ""):gsub("create:", ""):lower()
                        local rawNameLow = tostring(rawId):lower()

                        local isContraption = (rawType:find("contraption", 1, true) or 
                                               rawType:find("carriage", 1, true) or 
                                               rawType:find("train", 1, true) or 
                                               rawType:find("sable", 1, true) or 
                                               rawType:find("ship", 1, true) or
                                               rawNameLow:find("contraption", 1, true) or
                                               rawNameLow:find("sable", 1, true) or
                                               rawNameLow:find("carriage", 1, true))

                        local resolvedName
                        local displayType
                        local status

                        if isContraption then
                            displayType = "Contraption"
                            if rawNameLow:find("sable", 1, true) or rawType:find("sable", 1, true) then
                                resolvedName = "Sable (" .. tostring(rawId):sub(1, 4) .. ")"
                            else
                                resolvedName = "Contraption (" .. tostring(rawId):sub(1, 4) .. ")"
                            end
                            status = "OBJECT"
                        else
                            resolvedName = UUIDResolver.getName(rawId, rawType)
                            local isPlayer = (rawType == "player" or t.playerName ~= nil)
                            displayType = isPlayer and "Player" or (rawType:gsub("^%l", string.upper))

                            if isAlly(resolvedName) or isAlly(rawId) then
                                status = "ALLY"
                            elseif isPlayer then
                                status = "HOSTILE"
                            else
                                status = "NEUTRAL"
                            end
                        end

                        if not detectedKeys[string.lower(resolvedName)] then
                            local dist = extractDistance(t)

                            local entry = {
                                name   = resolvedName,
                                type   = displayType,
                                status = status,
                                isAlly = (status == "ALLY"),
                                dist   = tonumber(dist) or 0,
                                yaw    = tonumber(t.yaw or 0) or 0,
                                pitch  = tonumber(t.pitch or 0) or 0,
                            }
                            table.insert(entities, entry)

                            if status == "HOSTILE" and dist <= threatMaxDist then
                                table.insert(threats, {
                                    name   = entry.name,
                                    type   = entry.type,
                                    status = "HOSTILE",
                                    isAlly = false,
                                    dist   = entry.dist,
                                    yaw    = entry.yaw,
                                    pitch  = entry.pitch,
                                })
                            end
                        end
                    end
                end
            end
        end

        -- Отправка периодической телеметрии радара на сервер
        Net.broadcast(Protocol.TYPE.TELEMETRY, {
            role        = "radar_outpost",
            threatCount = #threats,
            entities    = entities,
            threats     = threats,
        })

        -- Вывод статуса на локальный экран радара
        term.setCursorPos(1, 10)
        term.clearLine()
        io.write(string.format("Contacts: %d | Hostiles: %d | Time: %s", #entities, #threats, textutils.formatTime(os.time(), true)))

        -- Отправка алертов только по реальным врагам
        if #threats > 0 then
            for _, t in ipairs(threats) do
                if shouldTriggerAlert(t.name, t.dist) then
                    local alertMsg = string.format("WARNING: Hostile %s at %dm!", t.name, t.dist)
                    print("\n[ALERT] " .. alertMsg)
                    Net.broadcast(Protocol.TYPE.ALERT, {
                        text     = alertMsg,
                        severity = Protocol.SEVERITY.DANGER,
                        source   = "RADAR",
                    })
                end
            end
        end

        sleep(1.0)
    end
end

local function httpLoop()
    while true do
        local ev = { os.pullEvent() }
        if ev[1] == "http_success" then
            local url, response = ev[2], ev[3]
            UUIDResolver.handleHttpResponse(url, response)
        elseif ev[1] == "rednet_message" then
            local senderID, rawPacket, proto = ev[2], ev[3], ev[4]
            Net.processMessage(senderID, rawPacket, proto)
        end
    end
end

parallel.waitForAny(radarLoop, httpLoop)
