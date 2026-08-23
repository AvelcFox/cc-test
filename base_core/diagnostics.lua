-- ============================================================
-- base_core/diagnostics.lua
-- Интерактивная диагностика оборудования базы и очков HUD
-- ============================================================

local Config   = require("/base_core/config")
local Protocol = require("/base_core/lib/protocol")
local Net      = require("/base_core/lib/net")

term.clear()
term.setCursorPos(1, 1)

local function printHeader(text)
    term.setTextColor(colors.yellow)
    print("\n=== " .. text .. " ===")
    term.setTextColor(colors.white)
end

local function printStatus(name, ok, details)
    io.write(string.format("%-26s [", name))
    if ok then
        term.setTextColor(colors.green)
        io.write("  OK  ")
    else
        term.setTextColor(colors.red)
        io.write(" FAIL ")
    end
    term.setTextColor(colors.white)
    io.write("]")
    if details then
        term.setTextColor(colors.lightGray)
        io.write(" " .. tostring(details))
        term.setTextColor(colors.white)
    end
    print("")
end

print("========================================")
print("     NEXINET SYSTEM: DIAGNOSTICS        ")
print("========================================")

-- ── 1. Проверка сети ──────────────────────────────────────────
printHeader("1. NETWORK & PROTOCOL")
local modem = nil
for _, name in ipairs(peripheral.getNames()) do
    local pType = peripheral.getType(name)
    if pType and pType:find("modem", 1, true) then
        modem = name
        break
    end
end
printStatus("Modem Attached", modem ~= nil, modem or "No modem found")
printStatus("Protocol Name", true, Config.NETWORK.PROTOCOL)
printStatus("Secret Key Set", Config.NETWORK.SECRET_KEY ~= nil and #Config.NETWORK.SECRET_KEY > 0, "Length: " .. #(Config.NETWORK.SECRET_KEY or ""))
printStatus("HTTP API Available", http ~= nil, http and "Enabled" or "Disabled on server")

-- ── 2. Проверка оборудования Сервера ─────────────────────────
printHeader("2. BASE SERVER PERIPHERALS")

local mon = peripheral.find("monitor")
if mon then
    mon.setTextScale(0.5)
    local w, h = mon.getSize()
    printStatus("Advanced Monitor", true, string.format("%s (%dx%d chars)", peripheral.getName(mon), w, h))
else
    printStatus("Advanced Monitor", false, "Not connected")
end

local stress = peripheral.find("Create_Stressometer") or peripheral.find("create:stressometer")
if stress then
    local ok1, cur = pcall(stress.getStress)
    local ok2, cap = pcall(stress.getCapacity)
    printStatus("Create Stressometer", ok1 and ok2, string.format("%d / %d SU", cur or 0, cap or 0))
else
    printStatus("Create Stressometer", false, "Not connected")
end

local speed = peripheral.find("Create_Speedometer") or peripheral.find("create:speedometer")
if speed then
    local ok, spd = pcall(speed.getSpeed)
    printStatus("Create Speedometer", ok, string.format("%d RPM", spd or 0))
else
    printStatus("Create Speedometer", false, "Not connected")
end

local vaults = 0
local barrels = 0
for _, name in ipairs(peripheral.getNames()) do
    local pType = peripheral.getType(name) or ""
    if pType:find("item_vault", 1, true) then vaults = vaults + 1
    elseif pType:find("barrel", 1, true) then barrels = barrels + 1 end
end
printStatus("Storage Units", (vaults + barrels) > 0, string.format("%d Vaults, %d Barrels", vaults, barrels))

local radar = peripheral.find("create_radar:radar_bearing") or peripheral.find("radar_bearing") or peripheral.find("player_detector")
printStatus("Radar / Player Detector", radar ~= nil, radar and peripheral.getName(radar) or "None detected")

-- ── 3. Проверка Smart Glasses (AP 0.8+) ───────────────────────
printHeader("3. SMART GLASSES (AP 0.8)")

local glasses = peripheral.find("smartglasses") or peripheral.find("arController")
if not glasses then
    for _, name in ipairs(peripheral.getNames()) do
        local pType = peripheral.getType(name) or ""
        if pType:find("glasses", 1, true) or pType:find("ar", 1, true) then
            glasses = peripheral.wrap(name)
            break
        end
    end
end

local overlay = nil
if glasses then
    local ok, ov = pcall(glasses.getModule, "advancedperipherals:overlay")
    if ok and ov then overlay = ov else overlay = glasses end
end

local glassesOk = (overlay ~= nil and overlay.createRectangle ~= nil)
printStatus("AR Controller / Glasses", glasses ~= nil, glasses and peripheral.getName(glasses) or "Not found")
printStatus("Overlay / Canvas Module", glassesOk, glassesOk and "Ready" or "Overlay not accessible")

-- ── 4. Интерактивный тест ─────────────────────────────────────
printHeader("4. INTERACTIVE TESTS")
print("Options:")
print(" [1] Test Monitor Dashboard Render")
print(" [2] Send Visual Test Pattern to Smart Glasses HUD")
print(" [3] Test Network Ping Broadcast")
print(" [Q] Exit")
print("")
io.write("Select test [1-3, Q]: ")
local choice = read()

if choice == "1" then
    if mon then
        local Dashboard = require("/base_core/server/dashboard")
        Dashboard.init(mon)
        Dashboard.render({
            create = { stress = { current = 1200, capacity = 4096, pct = 29 }, speed = 64, energy = { stored = 50000, capacity = 100000, pct = 50 } },
            storage = { usedSlots = 140, totalSlots = 500, pct = 28, items = Config.TRACKED_ITEMS },
            radar = { hasRadar = true, threatCount = 0, entities = {} },
            relays = { { id = 1, name = "Factory Power", state = true }, { id = 2, name = "Defense System", state = false } },
            onToggleRelay = function() end
        })
        print("\n[OK] Test pattern sent to monitor! Check your 5x3 screen.")
    else
        print("\n[FAIL] No monitor attached to render test pattern.")
    end

elseif choice == "2" then
    if glassesOk then
        overlay.clear()
        local sw, sh = overlay.getGuiSize()
        sw = (sw and sw > 0) and sw or 256
        sh = (sh and sh > 0) and sh or 140

        overlay.createRectangle({ x = 8, y = 16, sizeX = 160, sizeY = 22, color = 0x1A1A2E, opacity = 0.85 })
        overlay.createRectangle({ x = 8, y = 16, sizeX = 3, sizeY = 22, color = 0x00FFBB, opacity = 1.0 })
        overlay.createText({ x = 16, y = 18, content = "[TEST] NEXI HUD LINK ACTIVE", fontSize = 0.7, color = 0x00FFBB })
        overlay.createText({ x = 16, y = 26, content = "Smart Glasses 0.8 Working!", fontSize = 0.85, color = 0xFFFFFF, shadow = true })
        overlay.update()

        local spk = peripheral.find("speaker")
        if spk then
            pcall(function() spk.playSound("minecraft:block.note_block.pling", 1.0, 2.0) end)
        end

        print("\n[OK] Test HUD overlay displayed in Smart Glasses! It will stay for 5s...")
        sleep(5)
        overlay.clear()
        overlay.update()
        print("[OK] HUD Test cleared.")
    else
        print("\n[FAIL] Smart Glasses or Overlay module not available on this computer.")
    end

elseif choice == "3" then
    if Net.init() then
        Net.broadcast(Protocol.TYPE.ALERT, {
            text = "Diagnostic Ping Test",
            severity = Protocol.SEVERITY.INFO,
            source = "DIAG",
        })
        print("\n[OK] Broadcasted test ALERT packet on protocol: " .. Config.NETWORK.PROTOCOL)
    else
        print("\n[FAIL] Could not open modem for network test.")
    end
end

print("\nDiagnostics complete.")
