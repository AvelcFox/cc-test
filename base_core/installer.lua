-- ============================================================
-- base_core/installer.lua
-- Установщик и настройщик ролей BaseCore OS & NexiNetSystem
-- ============================================================

term.clear()
term.setCursorPos(1, 1)

print("========================================")
print("     NEXINET SYSTEM: COMPUTER SETUP     ")
print("========================================")
print("Choose role for Computer (ID: " .. os.getComputerID() .. "):")
print("")
print(" [1] Central Base Server  (Main PC 0 + 5x3 Monitor)")
print(" [2] Smart Glasses HUD    (AR Controller PC 8)")
print(" [3] Radar Security Node  (Radar PC 3)")
print(" [4] Storage Logistics    (Vaults / Auto-Farms PC 10)")
print(" [5] Dynamic Relay Node   (Machines / Redstone Relays)")
print(" [6] Pocket Remote        (Pocket Computer)")
print(" [7] Satellite Outpost    (Remote Sensors/Generators)")
print("")
io.write("Select option [1-7]: ")
local choice = read()

local startupTarget = nil

if choice == "1" then
    startupTarget = "/base_core/server/main.lua"
    print("\nSetting up as Central Base Server...")
elseif choice == "2" then
    startupTarget = "/base_core/clients/glasses_hud.lua"
    print("\nSetting up as Smart Glasses HUD...")
elseif choice == "3" then
    startupTarget = "/base_core/clients/radar_node.lua"
    print("\nSetting up as Radar Security Node...")
elseif choice == "4" then
    startupTarget = "/base_core/clients/storage_node.lua"
    print("\nSetting up as Storage Logistics Node...")
elseif choice == "5" then
    startupTarget = "/base_core/clients/relay_node.lua"
    print("\nSetting up as Dynamic Relay Node...")
elseif choice == "6" then
    startupTarget = "/base_core/clients/pocket_remote.lua"
    print("\nSetting up as Pocket Remote...")
elseif choice == "7" then
    startupTarget = "/base_core/clients/satellite_node.lua"
    print("\nSetting up as Satellite Outpost...")
else
    print("\nInvalid choice. Setup aborted.")
    return
end

-- Создаем /startup.lua для автозагрузки
local f = fs.open("/startup.lua", "w")
if f then
    f.writeLine("-- NexiNetSystem Auto-Launcher")
    f.writeLine('shell.run("' .. startupTarget .. '")')
    f.close()
    print("[OK] Created /startup.lua -> " .. startupTarget)
else
    print("[ERROR] Failed to write startup.lua")
end

print("\nSetup complete! Would you like to run it now? (y/n)")
local runNow = read()
if runNow == "y" or runNow == "Y" then
    shell.run(startupTarget)
end
