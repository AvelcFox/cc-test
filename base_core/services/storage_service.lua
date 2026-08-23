-- ============================================================
-- base_core/services/storage_service.lua
-- Сканирование и мониторинг хранилищ (Item Vaults, Barrels, Chests)
-- ============================================================

local Logger = require("/base_core/lib/logger")
local Config = require("/base_core/config")

local StorageService = {}

local data = {
    totalSlots = 0,
    usedSlots  = 0,
    pct        = 0,
    items      = {},
    vaultCount = 0,
}

local function findInventories()
    local invs = {}
    for _, name in ipairs(peripheral.getNames()) do
        local pType = peripheral.getType(name)
        if pType then
            if pType:find("item_vault", 1, true) or
               pType:find("barrel", 1, true) or
               pType:find("chest", 1, true) or
               pType:find("inventory", 1, true) then
                local wrapped = peripheral.wrap(name)
                if wrapped and wrapped.list then
                    table.insert(invs, { name = name, p = wrapped, type = pType })
                end
            end
        end
    end
    return invs
end

function StorageService.poll()
    local inventories = findInventories()
    local totalSlots = 0
    local usedSlots = 0
    local counts = {}

    -- Инициализируем отслеживаемые предметы нулями
    for _, itemCfg in ipairs(Config.TRACKED_ITEMS) do
        counts[itemCfg.id] = 0
    end

    data.vaultCount = #inventories

    for _, inv in ipairs(inventories) do
        local ok, items = pcall(inv.p.list)
        local okSize, size = pcall(inv.p.size)

        if okSize and size then
            totalSlots = totalSlots + size
        end

        if ok and items then
            for slot, item in pairs(items) do
                usedSlots = usedSlots + 1
                if counts[item.name] ~= nil then
                    counts[item.name] = counts[item.name] + (item.count or 0)
                else
                    -- Можно также сохранять другие часто встречающиеся предметы
                    counts[item.name] = (counts[item.name] or 0) + (item.count or 0)
                end
            end
        end
    end

    data.totalSlots = totalSlots
    data.usedSlots = usedSlots
    data.pct = totalSlots > 0 and math.floor((usedSlots / totalSlots) * 100) or 0

    -- Формируем структурированный список для UI
    data.items = {}
    for _, itemCfg in ipairs(Config.TRACKED_ITEMS) do
        table.insert(data.items, {
            id    = itemCfg.id,
            label = itemCfg.label,
            icon  = itemCfg.icon,
            count = counts[itemCfg.id] or 0,
        })
    end

    return data
end

function StorageService.getData()
    return data
end

return StorageService
