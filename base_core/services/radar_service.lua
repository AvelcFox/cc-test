-- ============================================================
-- base_core/services/radar_service.lua
-- Интеграция с Create Radar и Player Detector
-- ============================================================

local Logger = require("/base_core/lib/logger")
local Config = require("/base_core/config")

local RadarService = {}

local data = {
    entities    = {},
    threats     = {},
    threatCount = 0,
    hasRadar    = false,
}

local function isAlly(name)
    for _, ally in ipairs(Config.ALLIES or {}) do
        if string.lower(ally) == string.lower(name) then
            return true
        end
    end
    return false
end

local function findRadarDevices()
    local playerDetector = peripheral.find("player_detector") or peripheral.find("playerDetector")
    local createRadar = peripheral.find("create_radar:radar_bearing") or peripheral.find("radar_bearing")
    return playerDetector, createRadar
end

function RadarService.poll()
    local pd, cr = findRadarDevices()
    local entities = {}
    local threats = {}

    data.hasRadar = (pd ~= nil or cr ~= nil)

    -- 1. Опрос Player Detector (Advanced Peripherals)
    if pd then
        local ok, players = pcall(pd.getPlayersInRange or pd.getPlayersInArea, 64)
        if ok and players then
            for _, p in ipairs(players) do
                local pName = type(p) == "string" and p or (p.name or "Unknown")
                local isFriend = isAlly(pName)
                local entry = {
                    name     = pName,
                    type     = "Player",
                    isAlly   = isFriend,
                    dist     = p.distance or 0,
                    pos      = p.pos or { x = 0, y = 0, z = 0 }
                }
                table.insert(entities, entry)
                if not isFriend then
                    table.insert(threats, entry)
                end
            end
        end
    end

    -- 2. Опрос Create Radar
    if cr then
        local ok, targets = pcall(cr.getTargets or cr.getEntities)
        if ok and targets then
            for _, t in ipairs(targets) do
                local tName = t.name or t.type or "Contraption"
                local isFriend = isAlly(tName)
                local dist = t.distance or math.floor(math.sqrt((t.x or 0)^2 + (t.z or 0)^2))
                local entry = {
                    name     = tName,
                    type     = t.entityType or "RadarEntity",
                    isAlly   = isFriend,
                    dist     = dist,
                    yaw      = t.yaw or 0,
                    pitch    = t.pitch or 0,
                }
                table.insert(entities, entry)
                if not isFriend and dist <= Config.ALERTS.RADAR_THREAT_DIST then
                    table.insert(threats, entry)
                end
            end
        end
    end

    data.entities = entities
    data.threats = threats
    data.threatCount = #threats

    return data
end

function RadarService.getData()
    return data
end

return RadarService
