-- ============================================================
-- base_core/server/dashboard.lua
-- Сенсорный интерфейс монитора 5x3 с вкладками и виджетами
-- ============================================================

local UI     = require("/base_core/lib/ui")
local Config = require("/base_core/config")
local Logger = require("/base_core/lib/logger")

local Dashboard = {}

local activeTabIdx = 1

local tabDefs = {
    { id = "overview", name = "OVERVIEW" },
    { id = "kinetic",  name = "POWER"    },
    { id = "storage",  name = "STORAGE"  },
    { id = "radar",    name = "RADAR"    },
    { id = "controls", name = "CONTROLS" },
    { id = "logs",     name = "LOGS"     },
}

function Dashboard.init(monitor)
    local ok, err = UI.init(monitor)
    if not ok then return false, err end

    UI.setTabs(tabDefs, activeTabIdx)
    return true
end

-- ── Вкладка 1: Overview ──────────────────────────────────────

local function renderOverview(w, h, state)
    local createData  = state.create or {}
    local storageData = state.storage or {}
    local radarData   = state.radar or {}
    local relayData   = state.relays or {}

    local colW = math.floor((w - 3) / 2)
    local leftX = 2
    local rightX = leftX + colW + 1
    local panelH = h - 4

    -- Левая панель: Статус систем
    UI.panel(leftX, 4, colW, panelH, "BASE TELEMETRY", Config.PALETTE.BORDER, Config.PALETTE.BG)

    -- Create Kinetic
    local stress = createData.stress or { current = 0, capacity = 0, pct = 0 }
    UI.text(leftX + 2, 6, "Create Stress (SU):", Config.PALETTE.TEXT_DIM)
    local stressStr = string.format("%d / %d", stress.current, stress.capacity)
    UI.text(leftX + colW - string.len(stressStr) - 2, 6, stressStr, Config.PALETTE.TEXT)
    local stressCol = stress.pct > 90 and Config.PALETTE.DANGER or (stress.pct > 75 and Config.PALETTE.WARNING or Config.PALETTE.SUCCESS)
    UI.progressBar(leftX + 2, 7, colW - 4, stress.pct, stressCol, Config.PALETTE.PANEL_BG)

    -- FE Energy
    local energy = createData.energy or { stored = 0, capacity = 0, pct = 0 }
    UI.text(leftX + 2, 9, "FE Power Grid:", Config.PALETTE.TEXT_DIM)
    local energyStr = string.format("%d%%", energy.pct)
    UI.text(leftX + colW - string.len(energyStr) - 2, 9, energyStr, Config.PALETTE.TEXT)
    local energyCol = energy.pct < 20 and Config.PALETTE.DANGER or Config.PALETTE.PRIMARY
    UI.progressBar(leftX + 2, 10, colW - 4, energy.pct, energyCol, Config.PALETTE.PANEL_BG)

    -- Storage Vaults
    local usedS = storageData.usedSlots or 0
    local totalS = storageData.totalSlots or 0
    local freeS = storageData.freeSlots or math.max(0, totalS - usedS)
    local pctS = storageData.pct or (totalS > 0 and math.floor((usedS / totalS) * 100) or 0)

    UI.text(leftX + 2, 12, "Storage Vaults:", Config.PALETTE.TEXT_DIM)
    local storeStr = string.format("%d / %d", usedS, totalS)
    UI.text(leftX + colW - string.len(storeStr) - 2, 12, storeStr, Config.PALETTE.TEXT)
    UI.progressBar(leftX + 2, 13, colW - 4, pctS, Config.PALETTE.ACCENT, Config.PALETTE.PANEL_BG)

    -- Правая панель: Безопасность и Быстрое управление
    UI.panel(rightX, 4, colW, panelH, "DEFENSE & CONTROLS", Config.PALETTE.BORDER, Config.PALETTE.BG)

    -- Радар статус
    local threatCount = radarData.threatCount or 0
    if threatCount > 0 then
        UI.box(rightX + 2, 6, colW - 4, 2, Config.PALETTE.DANGER)
        UI.centerText(6, "!! THREAT DETECTED (" .. threatCount .. ") !!", Config.PALETTE.TEXT, Config.PALETTE.DANGER, rightX + 2, rightX + colW - 3)
        UI.centerText(7, "Check Radar Tab for details", Config.PALETTE.TEXT, Config.PALETTE.DANGER, rightX + 2, rightX + colW - 3)
    else
        UI.box(rightX + 2, 6, colW - 4, 2, Config.PALETTE.PANEL_BG)
        UI.centerText(6, "PERIMETER SECURE", Config.PALETTE.SUCCESS, Config.PALETTE.PANEL_BG, rightX + 2, rightX + colW - 3)
        UI.centerText(7, "No hostile signatures", Config.PALETTE.TEXT_MUTED, Config.PALETTE.PANEL_BG, rightX + 2, rightX + colW - 3)
    end

    -- Быстрые переключатели
    UI.text(rightX + 2, 10, "Quick Relays:", Config.PALETTE.ACCENT)
    if #relayData == 0 then
        UI.text(rightX + 2, 12, "No relay nodes online", Config.PALETTE.TEXT_MUTED)
        UI.text(rightX + 2, 13, "Start relay_node on PC", Config.PALETTE.TEXT_DIM)
    else
        local curY = 12
        for i, ch in ipairs(relayData) do
            if i <= 3 then
                local btnLabel = string.format("%-14s [%s]", ch.name, ch.state and " ON " or "OFF ")
                local bgCol = ch.state and Config.PALETTE.SUCCESS or Config.PALETTE.PANEL_BG
                local textCol = ch.state and Config.PALETTE.BG or Config.PALETTE.TEXT
                local btnId = "relay_toggle_" .. tostring(ch.uid or ch.id or i)

                UI.registerButton(btnId, rightX + 2, curY, colW - 4, 1, btnLabel, bgCol, textCol, function()
                    state.onToggleRelay(ch.uid or ch.id)
                end)
                UI.box(rightX + 2, curY, colW - 4, 1, bgCol)
                UI.text(rightX + 4, curY, ch.name:sub(1, colW - 14), textCol, bgCol)
                UI.text(rightX + colW - 10, curY, ch.state and "[ ON ]" or "[ OFF ]", textCol, bgCol)
                curY = curY + 2
            end
        end
    end
end

-- ── Вкладка 2: Kinetic & Power ───────────────────────────────

local function renderKinetic(w, h, state)
    local createData = state.create or {}
    local stress = createData.stress or { current = 0, capacity = 0, pct = 0 }
    local speed  = createData.speed or 0
    local tanks  = createData.tanks or {}
    local energy = createData.energy or { stored = 0, capacity = 0, pct = 0 }

    local colW = math.floor((w - 3) / 2)
    local leftX = 2
    local rightX = leftX + colW + 1

    -- Левая колонка: Create Kinetic
    UI.panel(leftX, 4, colW, h - 4, "KINETIC NETWORK", Config.PALETTE.BORDER, Config.PALETTE.BG)
    UI.text(leftX + 2, 6, "Network Speed: " .. speed .. " RPM", Config.PALETTE.HIGHLIGHT)
    UI.text(leftX + 2, 8, "Current Stress:", Config.PALETTE.TEXT_DIM)
    UI.text(leftX + 18, 8, tostring(stress.current) .. " SU", Config.PALETTE.TEXT)
    UI.text(leftX + 2, 9, "Max Capacity:  ", Config.PALETTE.TEXT_DIM)
    UI.text(leftX + 18, 9, tostring(stress.capacity) .. " SU", Config.PALETTE.TEXT)
    UI.text(leftX + 2, 10, "Remaining SU:  ", Config.PALETTE.TEXT_DIM)
    UI.text(leftX + 18, 10, tostring(math.max(0, stress.capacity - stress.current)) .. " SU", Config.PALETTE.SUCCESS)

    UI.text(leftX + 2, 12, "Stress Load:", Config.PALETTE.TEXT_DIM)
    local stressCol = stress.pct > 90 and Config.PALETTE.DANGER or (stress.pct > 75 and Config.PALETTE.WARNING or Config.PALETTE.SUCCESS)
    UI.progressBar(leftX + 2, 13, colW - 4, stress.pct, stressCol, Config.PALETTE.PANEL_BG)

    -- Правая колонка: Жидкости & FE
    UI.panel(rightX, 4, colW, h - 4, "FLUIDS & ELECTRICITY", Config.PALETTE.BORDER, Config.PALETTE.BG)
    UI.text(rightX + 2, 6, "FE Grid: " .. energy.stored .. " / " .. energy.capacity .. " FE", Config.PALETTE.TEXT)
    UI.progressBar(rightX + 2, 7, colW - 4, energy.pct, Config.PALETTE.PRIMARY, Config.PALETTE.PANEL_BG)

    UI.text(rightX + 2, 9, "Fluid Tanks (" .. #tanks .. "):", Config.PALETTE.ACCENT)
    local ty = 11
    if #tanks == 0 then
        UI.text(rightX + 2, ty, "No connected fluid tanks found", Config.PALETTE.TEXT_MUTED)
    else
        for i, tank in ipairs(tanks) do
            if ty < h - 2 then
                local fName = tank.name:gsub("minecraft:", ""):gsub("create:", "")
                UI.text(rightX + 2, ty, string.format("%s: %d mB", fName, tank.amount), Config.PALETTE.TEXT)
                UI.progressBar(rightX + 2, ty + 1, colW - 4, tank.pct, Config.PALETTE.ACCENT, Config.PALETTE.PANEL_BG)
                ty = ty + 3
            end
        end
    end
end

-- ── Вкладка 3: Logistics & Storage ───────────────────────────

local function renderStorage(w, h, state)
    local storageData = state.storage or {}
    local items = storageData.items or {}
    local usedS = storageData.usedSlots or 0
    local totalS = storageData.totalSlots or 0
    local freeS = storageData.freeSlots or math.max(0, totalS - usedS)
    local pctS = storageData.pct or (totalS > 0 and math.floor((usedS / totalS) * 100) or 0)

    UI.panel(2, 4, w - 2, h - 4, "CENTRAL LOGISTICS & VAULTS", Config.PALETTE.BORDER, Config.PALETTE.BG)

    -- Общая сводка
    local summaryStr = string.format("Units: %d | Total: %d slots | Used: %d (%d%%) | Free: %d slots",
        storageData.vaultCount or 0, totalS, usedS, pctS, freeS)
    UI.text(4, 6, summaryStr, Config.PALETTE.HIGHLIGHT)
    UI.progressBar(4, 7, w - 8, pctS, Config.PALETTE.ACCENT, Config.PALETTE.PANEL_BG)

    -- Таблица ресурсов в 2 колонки
    local colW = math.floor((w - 12) / 2)
    local leftX = 4
    local rightX = leftX + colW + 4

    UI.text(leftX, 9, "RESOURCE", Config.PALETTE.TEXT_DIM)
    UI.text(leftX + colW - 8, 9, "AMOUNT", Config.PALETTE.TEXT_DIM)
    UI.text(rightX, 9, "RESOURCE", Config.PALETTE.TEXT_DIM)
    UI.text(rightX + colW - 8, 9, "AMOUNT", Config.PALETTE.TEXT_DIM)

    local row = 11
    for i, item in ipairs(items) do
        local colX = (i % 2 == 1) and leftX or rightX
        local targetY = (i % 2 == 1) and row or (row - 1)

        if targetY < h - 2 then
            local countCol = (item.count and item.count > 0) and Config.PALETTE.TEXT or Config.PALETTE.TEXT_MUTED
            local iconStr = "[" .. (item.icon or "It") .. "] "
            UI.text(colX, targetY, iconStr .. (item.label or "Item"), Config.PALETTE.ACCENT)
            UI.text(colX + colW - 8, targetY, string.format("%6d", item.count or 0), countCol)
        end

        if i % 2 == 0 then row = row + 1 end
    end
end

-- ── Вкладка 4: Radar & Defense ───────────────────────────────

local function renderRadar(w, h, state)
    local radarData = state.radar or {}
    local entities  = radarData.entities or {}

    UI.panel(2, 4, w - 2, h - 4, "RADAR & THREAT SURVEILLANCE", Config.PALETTE.BORDER, Config.PALETTE.BG)

    if not radarData.hasRadar then
        UI.centerText(math.floor(h / 2), "No Radar or Player Detector connected", Config.PALETTE.TEXT_MUTED)
        return
    end

    UI.text(4, 6, string.format("Detected Contacts: %d | Hostiles / Threats: %d", #entities, radarData.threatCount or 0), Config.PALETTE.HIGHLIGHT)

    local curY = 8
    UI.text(4, curY, string.format("%-20s %-12s %-10s %s", "NAME / CONTACT", "TYPE", "DISTANCE", "STATUS"), Config.PALETTE.TEXT_DIM)
    curY = curY + 2

    if #entities == 0 then
        UI.text(4, curY, "Perimeter is clear. No contacts in range.", Config.PALETTE.SUCCESS)
    else
        for i, ent in ipairs(entities) do
            if curY < h - 2 then
                local st = ent.status or (ent.isAlly and "ALLY" or "HOSTILE")
                local statusStr = "[" .. st .. "]"
                local col = Config.PALETTE.TEXT
                if st == "ALLY" then
                    statusStr = "[ ALLY ]"
                    col = Config.PALETTE.SUCCESS
                elseif st == "HOSTILE" then
                    statusStr = "[ HOSTILE ]"
                    col = Config.PALETTE.DANGER
                elseif st == "OBJECT" then
                    statusStr = "[ OBJECT ]"
                    col = Config.PALETTE.ACCENT
                else
                    statusStr = "[ NEUTRAL ]"
                    col = Config.PALETTE.TEXT_DIM
                end

                UI.text(4, curY, string.format("%-20s %-12s %-10d", ent.name:sub(1, 19), ent.type:sub(1, 11), ent.dist or 0), Config.PALETTE.TEXT)
                UI.text(50, curY, statusStr, col)
                curY = curY + 1
            end
        end
    end
end

-- ── Вкладка 5: Controls ──────────────────────────────────────

local function renderControls(w, h, state)
    local relayData = state.relays or {}

    UI.panel(2, 4, w - 2, h - 4, "DISTRIBUTED RELAYS & MACHINE CONTROL", Config.PALETTE.BORDER, Config.PALETTE.BG)

    if #relayData == 0 then
        UI.centerText(math.floor(h / 2), "No local or remote relays registered", Config.PALETTE.TEXT_MUTED)
        return
    end

    local curY = 6
    for i, ch in ipairs(relayData) do
        if curY < h - 3 then
            local stateStr = ch.state and "  [ ACTIVE / ON ]  " or " [ DISABLED / OFF ] "
            local bgCol = ch.state and Config.PALETTE.SUCCESS or Config.PALETTE.PANEL_BG
            local textCol = ch.state and Config.PALETTE.BG or Config.PALETTE.TEXT
            local nodeTag = ch.nodeId and ("PC #" .. ch.nodeId) or "Local"

            UI.text(6, curY + 1, string.format("[%s] %-22s", nodeTag, ch.name), Config.PALETTE.TEXT)

            local btnId = "ctl_btn_" .. tostring(ch.uid or ch.id or i)
            UI.registerButton(btnId, w - 26, curY, 22, 3, stateStr, bgCol, textCol, function()
                state.onToggleRelay(ch.uid or ch.id)
            end)

            UI.box(w - 26, curY, 22, 3, bgCol)
            UI.centerText(curY + 1, stateStr, textCol, bgCol, w - 26, w - 5)

            curY = curY + 4
        end
    end
end

-- ── Вкладка 6: Logs & Nodes ──────────────────────────────────

local function renderLogs(w, h, state)
    local logEntries = Logger.getHistory()
    local nodes = state.nodes or {}

    local colW = math.floor((w - 3) / 2)
    local leftX = 2
    local rightX = leftX + colW + 1

    -- Левая колонка: Журнал событий
    UI.panel(leftX, 4, colW, h - 4, "EVENT LOG", Config.PALETTE.BORDER, Config.PALETTE.BG)
    local ly = h - 6
    for i = #logEntries, 1, -1 do
        local entry = logEntries[i]
        if ly >= 6 then
            local lvlCol = Config.PALETTE.TEXT
            if entry.level == "ERROR" or entry.level == "CRITICAL" then lvlCol = Config.PALETTE.DANGER
            elseif entry.level == "WARN" then lvlCol = Config.PALETTE.WARNING
            elseif entry.level == "SUCCESS" then lvlCol = Config.PALETTE.SUCCESS
            elseif entry.level == "ALERT" then lvlCol = Config.PALETTE.HIGHLIGHT end

            local lineStr = string.format("%s [%s] %s", entry.time, entry.tag, entry.message)
            UI.text(leftX + 2, ly, lineStr:sub(1, colW - 4), lvlCol)
            ly = ly - 1
        end
    end

    -- Правая колонка: Сателлит-узлы
    UI.panel(rightX, 4, colW, h - 4, "CONNECTED SATELLITE NODES", Config.PALETTE.BORDER, Config.PALETTE.BG)
    local ny = 6
    local nodeCount = 0
    for id, node in pairs(nodes) do
        nodeCount = nodeCount + 1
        if ny < h - 2 then
            local statusCol = node.status == "online" and Config.PALETTE.SUCCESS or Config.PALETTE.DANGER
            UI.text(rightX + 2, ny, string.format("ID %d: %-14s [%s]", node.id, node.name, node.role), Config.PALETTE.TEXT)
            UI.text(rightX + colW - 10, ny, node.status:upper(), statusCol)
            ny = ny + 2
        end
    end

    if nodeCount == 0 then
        UI.text(rightX + 2, ny, "No remote satellite nodes registered", Config.PALETTE.TEXT_MUTED)
    end
end

-- ── Главный метод отрисовки ──────────────────────────────────

function Dashboard.render(state)
    local mon = UI.getMonitor()
    if not mon then return end

    UI.clearButtons()
    local w, h = UI.getSize()

    -- Очистка фона
    UI.box(1, 1, w, h, Config.PALETTE.BG)

    -- Шапка с вкладками
    local alertLvl = "OK"
    if state.radar and state.radar.threatCount > 0 then
        alertLvl = "CRITICAL"
    elseif state.create and state.create.stress and state.create.stress.pct > Config.ALERTS.STRESS_WARN_PCT then
        alertLvl = "WARNING"
    end
    UI.drawHeader(Config.SERVER.NAME, alertLvl)

    -- Отрисовка активной вкладки
    local currentTab = UI.getActiveTab()
    if currentTab == 1 then
        renderOverview(w, h, state)
    elseif currentTab == 2 then
        renderKinetic(w, h, state)
    elseif currentTab == 3 then
        renderStorage(w, h, state)
    elseif currentTab == 4 then
        renderRadar(w, h, state)
    elseif currentTab == 5 then
        renderControls(w, h, state)
    elseif currentTab == 6 then
        renderLogs(w, h, state)
    end
end

function Dashboard.handleTouch(x, y)
    return UI.handleTouch(x, y)
end

return Dashboard
