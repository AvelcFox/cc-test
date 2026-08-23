-- ============================================================
-- base_core/lib/ui.lua
-- Графический интерфейс для Advanced Monitor с поддержкой Touch
-- ============================================================

local Config = require("/base_core/config")

local UI = {}

local currentMonitor = nil
local monWidth, monHeight = 51, 19
local buttons = {}
local activeTab = 1
local tabs = {}

function UI.init(monitor)
    currentMonitor = monitor or peripheral.find("monitor")
    if not currentMonitor then
        return false, "No monitor found"
    end

    currentMonitor.setTextScale(Config.SERVER.MONITOR_SCALE or 0.5)
    monWidth, monHeight = currentMonitor.getSize()
    currentMonitor.setBackgroundColor(Config.PALETTE.BG)
    currentMonitor.setTextColor(Config.PALETTE.TEXT)
    currentMonitor.clear()
    return true
end

function UI.getMonitor()
    return currentMonitor
end

function UI.getSize()
    return monWidth, monHeight
end

function UI.clearButtons()
    buttons = {}
end

function UI.registerButton(id, x, y, w, h, label, bgCol, textCol, onClick)
    table.insert(buttons, {
        id      = id,
        x       = x,
        y       = y,
        w       = w,
        h       = h,
        label   = label,
        bgCol   = bgCol or Config.PALETTE.PANEL_BG,
        textCol = textCol or Config.PALETTE.TEXT,
        onClick = onClick,
    })
end

function UI.handleTouch(x, y)
    for _, btn in ipairs(buttons) do
        if x >= btn.x and x <= (btn.x + btn.w - 1) and
           y >= btn.y and y <= (btn.y + btn.h - 1) then
            if btn.onClick then
                btn.onClick(btn)
                return true, btn.id
            end
        end
    end
    return false
end

-- ── Примитивы отрисовки ──────────────────────────────────────

function UI.box(x, y, w, h, bgCol)
    if not currentMonitor then return end
    currentMonitor.setBackgroundColor(bgCol or Config.PALETTE.PANEL_BG)
    local line = string.rep(" ", w)
    for row = y, y + h - 1 do
        currentMonitor.setCursorPos(x, row)
        currentMonitor.write(line)
    end
end

function UI.text(x, y, str, textCol, bgCol)
    if not currentMonitor then return end
    if bgCol then currentMonitor.setBackgroundColor(bgCol) end
    if textCol then currentMonitor.setTextColor(textCol) end
    currentMonitor.setCursorPos(x, y)
    currentMonitor.write(tostring(str))
end

function UI.centerText(y, str, textCol, bgCol, startX, endX)
    local minX = startX or 1
    local maxX = endX or monWidth
    local len = string.len(str)
    local x = math.floor(minX + ((maxX - minX + 1) - len) / 2)
    UI.text(math.max(1, x), y, str, textCol, bgCol)
end

function UI.panel(x, y, w, h, title, borderCol, bgCol)
    borderCol = borderCol or Config.PALETTE.BORDER
    bgCol = bgCol or Config.PALETTE.BG

    UI.box(x, y, w, h, bgCol)

    -- Верхняя и нижняя граница
    currentMonitor.setTextColor(borderCol)
    currentMonitor.setBackgroundColor(bgCol)
    currentMonitor.setCursorPos(x, y)
    currentMonitor.write("+" .. string.rep("-", w - 2) .. "+")
    currentMonitor.setCursorPos(x, y + h - 1)
    currentMonitor.write("+" .. string.rep("-", w - 2) .. "+")

    -- Боковые границы
    for row = y + 1, y + h - 2 do
        currentMonitor.setCursorPos(x, row)
        currentMonitor.write("|")
        currentMonitor.setCursorPos(x + w - 1, row)
        currentMonitor.write("|")
    end

    -- Заголовок панели
    if title and title ~= "" then
        local tStr = " " .. title .. " "
        currentMonitor.setTextColor(Config.PALETTE.ACCENT)
        currentMonitor.setCursorPos(x + 2, y)
        currentMonitor.write(tStr)
    end
end

function UI.progressBar(x, y, w, pct, fillCol, emptyCol, showText)
    pct = math.max(0, math.min(100, pct or 0))
    local filled = math.floor((pct / 100) * w)
    local empty = w - filled

    currentMonitor.setCursorPos(x, y)
    if filled > 0 then
        currentMonitor.setBackgroundColor(fillCol or Config.PALETTE.SUCCESS)
        currentMonitor.write(string.rep(" ", filled))
    end
    if empty > 0 then
        currentMonitor.setBackgroundColor(emptyCol or Config.PALETTE.PANEL_BG)
        currentMonitor.write(string.rep(" ", empty))
    end

    if showText ~= false then
        local text = string.format("%d%%", pct)
        UI.centerText(y, text, Config.PALETTE.TEXT, nil, x, x + w - 1)
    end
end

function UI.drawButton(btn)
    UI.box(btn.x, btn.y, btn.w, btn.h, btn.bgCol)
    UI.centerText(btn.y + math.floor((btn.h - 1) / 2), btn.label, btn.textCol, btn.bgCol, btn.x, btn.x + btn.w - 1)
end

function UI.renderButtons()
    for _, btn in ipairs(buttons) do
        UI.drawButton(btn)
    end
end

-- ── Навигационная шапка и вкладки ─────────────────────────────

function UI.setTabs(tabList, activeIdx)
    tabs = tabList or {}
    activeTab = activeIdx or 1
end

function UI.getActiveTab()
    return activeTab
end

function UI.setActiveTab(idx)
    activeTab = idx
end

function UI.drawHeader(title, alertLevel)
    if not currentMonitor then return end

    -- Фон шапки
    UI.box(1, 1, monWidth, 2, Config.PALETTE.PANEL_BG)

    -- Логотип / Название
    UI.text(2, 1, "[ " .. (title or Config.SERVER.NAME) .. " ]", Config.PALETTE.HIGHLIGHT, Config.PALETTE.PANEL_BG)

    -- Индикатор тревоги
    local statusText = "[ OK ]"
    local statusCol = Config.PALETTE.SUCCESS
    if alertLevel == "CRITICAL" or alertLevel == "DANGER" then
        statusText = "[ THREAT ]"
        statusCol = Config.PALETTE.DANGER
    elseif alertLevel == "WARNING" then
        statusText = "[ WARN ]"
        statusCol = Config.PALETTE.WARNING
    end
    UI.text(monWidth - string.len(statusText) - 12, 1, statusText, statusCol, Config.PALETTE.PANEL_BG)

    -- Время
    local t = os.time()
    local hours = math.floor(t)
    local mins = math.floor((t - hours) * 60)
    local timeStr = string.format("%02d:%02d", hours, mins)
    UI.text(monWidth - 8, 1, timeStr, Config.PALETTE.TEXT, Config.PALETTE.PANEL_BG)

    -- Рендер вкладок на строке 2
    local curX = 2
    for i, tab in ipairs(tabs) do
        local label = " " .. tab.name .. " "
        local tabLen = string.len(label)
        local isCurrent = (i == activeTab)
        local bgCol = isCurrent and Config.PALETTE.PRIMARY or Config.PALETTE.PANEL_BG
        local textCol = isCurrent and Config.PALETTE.TEXT or Config.PALETTE.TEXT_DIM

        UI.registerButton("tab_" .. i, curX, 2, tabLen, 1, tab.name, bgCol, textCol, function()
            activeTab = i
            if tab.onSelect then tab.onSelect() end
        end)

        UI.text(curX, 2, label, textCol, bgCol)
        curX = curX + tabLen + 1
    end
end

return UI
