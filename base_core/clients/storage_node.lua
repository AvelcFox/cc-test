-- ============================================================
-- base_core/clients/storage_node.lua
-- Выделенный контроллер склада (Computer 10)
-- Сканирование хранилищ и авто-управление фермами по порогам предметов
-- ============================================================

local Config   = require("/base_core/config")
local Protocol = require("/base_core/lib/protocol")
local Net      = require("/base_core/lib/net")

term.clear()
term.setCursorPos(1, 1)

print("========================================")
print("     NEXINET: STORAGE LOGISTICS NODE    ")
print("========================================")

if not Net.init() then
    print("ERROR: No modem attached!")
    return
end

local RULES_FILE = "/base_core/data/automation_rules.json"

local defaultRules = {
    {
        name        = "Iron Auto-Farm",
        itemId      = "minecraft:iron_ingot",
        label       = "Iron Ingot",
        min         = 500,
        max         = 1000,
        targetRelay = "Iron Farm",
        active      = false,
    },
    {
        name        = "Andesite Alloy Line",
        itemId      = "create:andesite_alloy",
        label       = "Andesite Alloy",
        min         = 256,
        max         = 512,
        targetRelay = "Andesite Line",
        active      = false,
    },
    {
        name        = "Brass Production",
        itemId      = "create:brass_ingot",
        label       = "Brass Ingot",
        min         = 128,
        max         = 256,
        targetRelay = "Brass Mixer",
        active      = false,
    },
}

local autoRules = {}

local function loadRules()
    if fs.exists(RULES_FILE) then
        local f = fs.open(RULES_FILE, "r")
        if f then
            local raw = f.readAll()
            f.close()
            local decoded = textutils.unserialiseJSON(raw)
            if decoded and type(decoded) == "table" then
                autoRules = decoded
                return
            end
        end
    end
    autoRules = defaultRules
    local f = fs.open(RULES_FILE, "w")
    if f then
        f.write(textutils.serialiseJSON(autoRules))
        f.close()
    end
end

local function saveRules()
    local f = fs.open(RULES_FILE, "w")
    if f then
        f.write(textutils.serialiseJSON(autoRules))
        f.close()
    end
end

loadRules()

-- Поиск всех подключенных хранилищ (Item Vaults, Barrels, Chests)
local function findInventories()
    local invs = {}
    for _, name in ipairs(peripheral.getNames()) do
        local p = peripheral.wrap(name)
        local pType = peripheral.getType(name) or ""
        -- Проверяем наличие методов инвентаря
        if p and (p.size or p.list or p.getItemDetail or pType:find("vault", 1, true) or pType:find("barrel", 1, true) or pType:find("chest", 1, true)) then
            if p.size and p.list then
                table.insert(invs, { name = name, p = p, type = pType })
            end
        end
    end
    return invs
end

local inventories = findInventories()
print(string.format("[OK] Discovered %d connected Storage units", #inventories))
print("Automation Rules loaded: " .. #autoRules)

local function scanAllStorage()
    inventories = findInventories()
    local totalSlots = 0
    local usedSlots = 0
    local counts = {}

    -- Инициализируем отслеживаемые предметы
    for _, itemCfg in ipairs(Config.TRACKED_ITEMS or {}) do
        counts[itemCfg.id] = 0
    end
    for _, rule in ipairs(autoRules) do
        counts[rule.itemId] = 0
    end

    for _, inv in ipairs(inventories) do
        local okSize, size = pcall(inv.p.size)
        if okSize and size and size > 0 then
            totalSlots = totalSlots + size
        end

        local okList, items = pcall(inv.p.list)
        if okList and items and type(items) == "table" then
            for slot, it in pairs(items) do
                if it and it.count and it.count > 0 then
                    usedSlots = usedSlots + 1
                    counts[it.name] = (counts[it.name] or 0) + it.count
                end
            end
        end
    end

    local freeSlots = math.max(0, totalSlots - usedSlots)
    local pct = totalSlots > 0 and math.floor((usedSlots / totalSlots) * 100) or 0

    local itemsList = {}
    for _, itemCfg in ipairs(Config.TRACKED_ITEMS or {}) do
        table.insert(itemsList, {
            id    = itemCfg.id,
            label = itemCfg.label,
            icon  = itemCfg.icon,
            count = counts[itemCfg.id] or 0,
        })
    end

    return {
        vaultCount = #inventories,
        totalSlots = totalSlots,
        usedSlots  = usedSlots,
        freeSlots  = freeSlots,
        pct        = pct,
        counts     = counts,
        items      = itemsList,
    }
end

-- Проверка порогов и авто-переключение реле ферм
local function processAutomation(counts)
    for _, rule in ipairs(autoRules) do
        local currentCount = counts[rule.itemId] or 0
        local targetRelay = rule.targetRelay

        if currentCount < rule.min and not rule.active then
            rule.active = true
            saveRules()
            print(string.format("[AUTO] Low stock '%s' (%d < %d) -> Enabling '%s'", rule.label, currentCount, rule.min, targetRelay))
            
            -- Отправляем команду включения реле на реле-ноды
            Net.broadcast(Protocol.TYPE.COMMAND, {
                action = "SET_RELAY",
                name   = targetRelay,
                state  = true,
            })

            -- Оповещаем Smart Glasses и Монитор
            Net.broadcast(Protocol.TYPE.ALERT, {
                text     = string.format("AUTO: Started %s (Stock: %d < %d)", rule.label, currentCount, rule.min),
                severity = Protocol.SEVERITY.INFO,
                source   = "LOGISTICS",
            })

        elseif currentCount >= rule.max and rule.active then
            rule.active = false
            saveRules()
            print(string.format("[AUTO] Full stock '%s' (%d >= %d) -> Disabling '%s'", rule.label, currentCount, rule.max, targetRelay))
            
            -- Отправляем команду выключения реле
            Net.broadcast(Protocol.TYPE.COMMAND, {
                action = "SET_RELAY",
                name   = targetRelay,
                state  = false,
            })

            Net.broadcast(Protocol.TYPE.ALERT, {
                text     = string.format("AUTO: Stopped %s (Stock full: %d)", rule.label, currentCount),
                severity = Protocol.SEVERITY.SUCCESS,
                source   = "LOGISTICS",
            })
        end
    end
end

-- ── Главный цикл контроллера склада ──────────────────────────

while true do
    local storageData = scanAllStorage()

    -- Проверяем правила авто-ферм
    processAutomation(storageData.counts)

    -- Транслируем данные склада в сеть BaseCore
    Net.broadcast(Protocol.TYPE.TELEMETRY, {
        role       = "storage_node",
        vaultCount = storageData.vaultCount,
        totalSlots = storageData.totalSlots,
        usedSlots  = storageData.usedSlots,
        freeSlots  = storageData.freeSlots,
        pct        = storageData.pct,
        items      = storageData.items,
    })

    -- Вывод на экран
    term.setCursorPos(1, 9)
    term.clearLine()
    io.write(string.format("Units: %d | Used: %d / %d (%d%%) | Free: %d slots", storageData.vaultCount, storageData.usedSlots, storageData.totalSlots, storageData.pct, storageData.freeSlots))

    sleep(1.5)
end
