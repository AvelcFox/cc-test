-- ============================================================
-- base_core/lib/logger.lua
-- Централизованная система логирования с кольцевым буфером
-- ============================================================

local Config = require("/base_core/config")

local Logger = {}

local logHistory = {}
local listeners = {}
local MAX_LOGS = Config.SERVER.LOG_MAX_LINES or 50

local function getFormattedTime()
    local t = os.time()
    local hours = math.floor(t)
    local mins = math.floor((t - hours) * 60)
    local secs = math.floor(((t - hours) * 60 - mins) * 60)
    return string.format("%02d:%02d:%02d", hours, mins, secs)
end

function Logger.addListener(fn)
    table.insert(listeners, fn)
end

function Logger.log(level, tag, message)
    local entry = {
        time    = getFormattedTime(),
        level   = string.upper(level or "INFO"),
        tag     = tag or "SYSTEM",
        message = tostring(message or ""),
        epoch   = os.clock(),
    }

    table.insert(logHistory, entry)
    while #logHistory > MAX_LOGS do
        table.remove(logHistory, 1)
    end

    for _, fn in ipairs(listeners) do
        pcall(fn, entry)
    end

    -- Печать в локальную консоль терминала
    local color = colors.white
    if entry.level == "ERROR" or entry.level == "CRITICAL" then
        color = colors.red
    elseif entry.level == "WARN" or entry.level == "WARNING" then
        color = colors.orange
    elseif entry.level == "SUCCESS" then
        color = colors.green
    elseif entry.level == "ALERT" then
        color = colors.magenta
    end

    if term.isColor and term.isColor() then
        local prev = term.getTextColor()
        term.setTextColor(colors.gray)
        io.write("[" .. entry.time .. "] ")
        term.setTextColor(color)
        io.write(string.format("[%-5s] ", entry.level))
        term.setTextColor(colors.lightGray)
        io.write(string.format("[%s] ", entry.tag))
        term.setTextColor(colors.white)
        print(entry.message)
        term.setTextColor(prev)
    else
        print(string.format("[%s] [%s] [%s] %s", entry.time, entry.level, entry.tag, entry.message))
    end

    return entry
end

function Logger.info(tag, msg)    return Logger.log("INFO", tag, msg) end
function Logger.success(tag, msg) return Logger.log("SUCCESS", tag, msg) end
function Logger.warn(tag, msg)    return Logger.log("WARN", tag, msg) end
function Logger.error(tag, msg)   return Logger.log("ERROR", tag, msg) end
function Logger.alert(tag, msg)   return Logger.log("ALERT", tag, msg) end

function Logger.getHistory()
    return logHistory
end

return Logger
