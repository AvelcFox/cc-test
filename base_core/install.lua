-- ============================================================
-- base_core/install.lua
-- Универсальный загрузчик и инсталлятор BaseCore OS & NexiNet
-- Установка всей системы одной командой:
--   wget run https://raw.githubusercontent.com/AvelcFox/cc-test/main/base_core/install.lua [role]
-- ============================================================

local GITHUB_USER = "AvelcFox"
local GITHUB_REPO = "cc-test"
local BRANCH      = "main"
local BASE_URL    = "https://raw.githubusercontent.com/" .. GITHUB_USER .. "/" .. GITHUB_REPO .. "/" .. BRANCH

local args = { ... }
local targetRole = args[1] -- Опциональный аргумент роли для тихой установки (server|radar|glasses|storage|relay|pocket)

local FILES = {
    "base_core/config.lua",
    "base_core/installer.lua",
    "base_core/diagnostics.lua",
    "base_core/lib/logger.lua",
    "base_core/lib/net.lua",
    "base_core/lib/protocol.lua",
    "base_core/lib/ui.lua",
    "base_core/lib/uuid_resolver.lua",
    "base_core/server/main.lua",
    "base_core/server/dashboard.lua",
    "base_core/clients/glasses_hud.lua",
    "base_core/clients/pocket_remote.lua",
    "base_core/clients/radar_node.lua",
    "base_core/clients/relay_node.lua",
    "base_core/clients/satellite_node.lua",
    "base_core/clients/storage_node.lua",
    "base_core/services/automation_service.lua",
    "base_core/services/create_service.lua",
    "base_core/services/openclaw_bridge.lua",
    "base_core/services/radar_service.lua",
    "base_core/services/relay_service.lua",
    "base_core/services/storage_service.lua",
    "base_core/tools/rules_cli.lua",
}

local function ensureDir(path)
    local parts = {}
    for part in path:gmatch("[^/]+") do
        parts[#parts + 1] = part
    end
    local dir = ""
    for i = 1, #parts - 1 do
        dir = dir == "" and parts[i] or (dir .. "/" .. parts[i])
        if not fs.exists(dir) then fs.makeDir(dir) end
    end
end

term.clear()
term.setCursorPos(1, 1)
print("========================================")
print("     BASECORE OS: UNIVERSAL INSTALL     ")
print("     Repo: " .. GITHUB_USER .. "/" .. GITHUB_REPO .. " (" .. BRANCH .. ")")
print("========================================")
print()

local ok, fail = 0, 0
local total = #FILES

for i, path in ipairs(FILES) do
    local pct = math.floor((i / total) * 100)
    io.write(string.format("[%2d%%] %-34s ", pct, path))
    ensureDir(path)
    local url = BASE_URL .. "/" .. path
    local response = http.get(url)
    if response then
        local content = response.readAll()
        response.close()
        if content then
            local f = fs.open(path, "w")
            if f then
                f.write(content)
                f.close()
                print("[OK]")
                ok = ok + 1
            else
                print("[ERR]")
                fail = fail + 1
            end
        else
            print("[EMPTY]")
            fail = fail + 1
        end
    else
        print("[FAIL]")
        fail = fail + 1
    end
end

print()
print("========================================")
print(string.format("  Downloaded: %d / %d | Errors: %d", ok, total, fail))
print("========================================")

local roleMap = {
    server  = "/base_core/server/main.lua",
    main    = "/base_core/server/main.lua",
    radar   = "/base_core/clients/radar_node.lua",
    glasses = "/base_core/clients/glasses_hud.lua",
    hud     = "/base_core/clients/glasses_hud.lua",
    storage = "/base_core/clients/storage_node.lua",
    vault   = "/base_core/clients/storage_node.lua",
    relay   = "/base_core/clients/relay_node.lua",
    farm    = "/base_core/clients/relay_node.lua",
    pocket  = "/base_core/clients/pocket_remote.lua",
}

if fail == 0 then
    if targetRole and roleMap[targetRole:lower()] then
        local entryPoint = roleMap[targetRole:lower()]
        local f = fs.open("startup.lua", "w")
        if f then
            f.writeLine("-- Auto-generated startup by BaseCore Installer")
            f.writeLine("shell.run(\"" .. entryPoint .. "\")")
            f.close()
            print(string.format("[SUCCESS] Configured startup.lua for role: %s", targetRole:upper()))
            print("Rebooting computer in 2 seconds...")
            sleep(2)
            os.reboot()
        end
    else
        print()
        print("Launch Interactive Role Wizard now? (Y/n)")
        io.write("> ")
        local ans = read()
        if ans == "" or ans == "y" or ans == "Y" then
            shell.run("/base_core/installer.lua")
        else
            print("To setup role anytime, run: base_core/installer")
        end
    end
else
    print("WARNING: Some files failed to download.")
    print("Check your internet/HTTP whitelist settings or GitHub repo branch.")
end
