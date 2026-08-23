-- ============================================================
-- base_core/install.lua
-- Bootstrap installer — one command to install BaseCore OS
-- ============================================================
-- Usage on any CC computer:
--   wget run https://raw.githubusercontent.com/USER/REPO/main/base_core/install.lua
-- ============================================================

local GITHUB_USER = "AvelcFox"
local GITHUB_REPO = "cc-test"
local BRANCH      = "main"
local BASE_URL    = "https://raw.githubusercontent.com/"..GITHUB_USER.."/"..GITHUB_REPO.."/"..BRANCH

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
    "base_core/services/create_service.lua",
    "base_core/services/openclaw_bridge.lua",
    "base_core/services/radar_service.lua",
    "base_core/services/relay_service.lua",
    "base_core/services/storage_service.lua",
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
print("   BaseCore OS - GitHub Installer       ")
print("   Server: " .. GITHUB_USER .. "/" .. GITHUB_REPO)
print("========================================")
print()

local ok, fail = 0, 0
for _, path in ipairs(FILES) do
    io.write("  " .. path .. " ... ")
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
                print("[WRITE ERROR]")
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
print("  Installed: " .. ok .. " | Failed: " .. fail)
print("========================================")

if fail == 0 then
    print()
    print("Run setup now? (y/n)")
    io.write("> ")
    local ans = read()
    if ans == "y" or ans == "Y" then
        shell.run("/base_core/installer.lua")
    else
        print("To setup later, run: /base_core/installer.lua")
    end
else
    print("Some files failed. Check your GitHub repo settings.")
    print("Make sure GITHUB_USER and GITHUB_REPO are correct.")
end
