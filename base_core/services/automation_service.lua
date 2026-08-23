-- ============================================================
-- base_core/services/automation_service.lua
-- Централизованный движок автоматизации для Главного Сервера (ПК 0)
-- Гибкие правила: item_count, stress, energy, threat -> переключение реле
-- ============================================================

local Logger   = require("/base_core/lib/logger")
local Protocol = require("/base_core/lib/protocol")
local Net      = require("/base_core/lib/net")

local AutomationService = {}

local RULES_FILE = "/base_core/data/automation_rules.json"

local rules = {}
local ruleStates = {} -- { [ruleId] = { isTriggered = false, lastTriggerTime = 0 } }

-- Загрузка правил из JSON
function AutomationService.loadRules()
    if fs.exists(RULES_FILE) then
        local f = fs.open(RULES_FILE, "r")
        if f then
            local data = f.readAll()
            f.close()
            local ok, parsed = pcall(textutils.unserializeJSON, data)
            if ok and type(parsed) == "table" then
                rules = parsed
                return rules
            end
        end
    end

    -- Правила по умолчанию
    rules = {
        {
            id          = "iron_farm",
            name        = "Iron Ingot Auto-Refill",
            enabled     = true,
            trigger     = {
                type           = "item_count",
                item           = "minecraft:iron_ingot",
                condition      = "<=",
                threshold      = 128,
                reset_cond     = ">=",
                reset_thresh   = 512,
            },
            action      = {
                type         = "set_relay",
                target_relay = "Iron Farm", -- Имя реле или UID
                state        = true,        -- Включить ферму
            },
            reset_action= {
                type         = "set_relay",
                target_relay = "Iron Farm",
                state        = false,       -- Выключить ферму
            },
            cooldown    = 15,
            notify      = true,
        },
        {
            id          = "andesite_farm",
            name        = "Andesite Alloy Production",
            enabled     = true,
            trigger     = {
                type           = "item_count",
                item           = "create:andesite_alloy",
                condition      = "<=",
                threshold      = 128,
                reset_cond     = ">=",
                reset_thresh   = 256,
            },
            action      = {
                type         = "set_relay",
                target_relay = "Andesite Farm",
                state        = true,
            },
            reset_action= {
                type         = "set_relay",
                target_relay = "Andesite Farm",
                state        = false,
            },
            cooldown    = 15,
            notify      = true,
        },
        {
            id          = "stress_protection",
            name        = "Kinetic Overload Auto-Shutdown",
            enabled     = true,
            trigger     = {
                type           = "stress_pct",
                condition      = ">=",
                threshold      = 95,
                reset_cond     = "<=",
                reset_thresh   = 75,
            },
            action      = {
                type         = "set_relay",
                target_relay = "Heavy Machinery",
                state        = false,
            },
            reset_action= {
                type         = "set_relay",
                target_relay = "Heavy Machinery",
                state        = true,
            },
            cooldown    = 30,
            notify      = true,
        }
    }

    AutomationService.saveRules()
    return rules
end

-- Сохранение правил в JSON
function AutomationService.saveRules()
    local dir = fs.getDir(RULES_FILE)
    if not fs.exists(dir) then fs.makeDir(dir) end
    local f = fs.open(RULES_FILE, "w")
    if f then
        f.write(textutils.serializeJSON(rules))
        f.close()
        return true
    end
    return false
end

function AutomationService.getRules()
    return rules
end

function AutomationService.addRule(rule)
    table.insert(rules, rule)
    AutomationService.saveRules()
end

function AutomationService.deleteRule(index)
    table.remove(rules, index)
    AutomationService.saveRules()
end

-- Поиск количества предметов на складе
local function getItemCount(storageItems, targetItem)
    local targetLower = targetItem:lower()
    local total = 0
    for _, item in ipairs(storageItems or {}) do
        local name = (item.name or ""):lower()
        if name == targetLower or name:find(targetLower, 1, true) then
            total = total + (item.count or 0)
        end
    end
    return total
end

-- Проверка математического условия
local function evalCondition(val, op, threshold)
    if op == "<=" then return val <= threshold
    elseif op == "<" then return val < threshold
    elseif op == ">=" then return val >= threshold
    elseif op == ">" then return val > threshold
    elseif op == "==" then return val == threshold
    end
    return false
end

-- Поиск целевого реле по имени, UID или номеру
local function findRelayTarget(relays, targetQuery)
    local queryStr = tostring(targetQuery):lower()
    for _, r in ipairs(relays or {}) do
        local rUid = tostring(r.uid or r.id or ""):lower()
        local rName = tostring(r.name or ""):lower()
        if rUid == queryStr or rName == queryStr or rName:find(queryStr, 1, true) then
            return r
        end
    end
    return nil
end

-- ── Главный цикл вычисления правил ────────────────────────────

function AutomationService.evaluate(serverState)
    if #rules == 0 then return end

    local now = os.clock()
    local storageItems = serverState.storage and serverState.storage.items or {}
    local stressPct    = serverState.create and serverState.create.stress and serverState.create.stress.pct or 0
    local energyPct    = serverState.create and serverState.create.energy and serverState.create.energy.pct or 0
    local threatCount  = serverState.radar and serverState.radar.threatCount or 0
    local relays       = serverState.relays or {}

    for _, rule in ipairs(rules) do
        if rule.enabled then
            local rId = rule.id or rule.name
            local rState = ruleStates[rId] or { isTriggered = false, lastTriggerTime = 0 }
            ruleStates[rId] = rState

            -- 1. Получаем текущее значение для триггера
            local currentVal = 0
            local trig = rule.trigger or {}

            if trig.type == "item_count" then
                currentVal = getItemCount(storageItems, trig.item or "")
            elseif trig.type == "stress_pct" then
                currentVal = stressPct
            elseif trig.type == "energy_pct" then
                currentVal = energyPct
            elseif trig.type == "threat_count" then
                currentVal = threatCount
            end

            -- 2. Проверяем условие срабатывания (Trigger)
            local shouldTrigger = evalCondition(currentVal, trig.condition or "<=", trig.threshold or 0)

            -- 3. Проверяем условие сброса (Reset / Hysteresis)
            local shouldReset = false
            if trig.reset_cond and trig.reset_thresh then
                shouldReset = evalCondition(currentVal, trig.reset_cond, trig.reset_thresh)
            else
                shouldReset = not shouldTrigger
            end

            -- Выполнение действия срабатывания
            if shouldTrigger and not rState.isTriggered then
                if (now - rState.lastTriggerTime) >= (rule.cooldown or 10) then
                    rState.isTriggered = true
                    rState.lastTriggerTime = now

                    local act = rule.action or {}
                    if act.type == "set_relay" and act.target_relay then
                        local targetRelay = findRelayTarget(relays, act.target_relay)
                        if targetRelay then
                            if targetRelay.state ~= act.state then
                                serverState.onToggleRelay(targetRelay.uid or targetRelay.id)
                            end
                            local logMsg = string.format("[AUTO] Rule '%s': %s (Val: %s %s %s) -> Relay '%s' = %s",
                                rule.name, trig.item or trig.type, currentVal, trig.condition, trig.threshold,
                                targetRelay.name, act.state and "ON" or "OFF")
                            Logger.info("AUTO", logMsg)

                            if rule.notify then
                                Net.broadcast(Protocol.TYPE.ALERT, {
                                    text     = string.format("Auto: %s -> %s %s", rule.name, targetRelay.name, act.state and "ON" or "OFF"),
                                    severity = Protocol.SEVERITY.INFO,
                                    source   = "AUTO",
                                })
                            end
                        end
                    end
                end

            -- Выполнение действия сброса
            elseif shouldReset and rState.isTriggered then
                if (now - rState.lastTriggerTime) >= (rule.cooldown or 10) then
                    rState.isTriggered = false
                    rState.lastTriggerTime = now

                    local resetAct = rule.reset_action or {}
                    if resetAct.type == "set_relay" and resetAct.target_relay then
                        local targetRelay = findRelayTarget(relays, resetAct.target_relay)
                        if targetRelay then
                            if targetRelay.state ~= resetAct.state then
                                serverState.onToggleRelay(targetRelay.uid or targetRelay.id)
                            end
                            local logMsg = string.format("[AUTO-RESET] Rule '%s': Target restored (Val: %s %s %s) -> Relay '%s' = %s",
                                rule.name, currentVal, trig.reset_cond, trig.reset_thresh,
                                targetRelay.name, resetAct.state and "ON" or "OFF")
                            Logger.info("AUTO", logMsg)

                            if rule.notify then
                                Net.broadcast(Protocol.TYPE.ALERT, {
                                    text     = string.format("Auto-Reset: %s -> %s %s", rule.name, targetRelay.name, resetAct.state and "ON" or "OFF"),
                                    severity = Protocol.SEVERITY.SUCCESS,
                                    source   = "AUTO",
                                })
                            end
                        end
                    end
                end
            end
        end
    end
end

-- Инициализация при старте
AutomationService.loadRules()

return AutomationService
