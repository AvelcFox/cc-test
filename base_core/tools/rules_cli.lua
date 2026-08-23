-- ============================================================
-- base_core/tools/rules_cli.lua
-- Интерактивный CLI редактор правил автоматизации
-- Использование: rules [list|add|remove|toggle]
-- ============================================================

local AutomationService = require("/base_core/services/automation_service")

local args = { ... }
local cmd = args[1] or "list"

term.clear()
term.setCursorPos(1, 1)

print("========================================")
print("     NEXINET: AUTOMATION RULES CLI      ")
print("========================================")

if cmd == "list" then
    local rules = AutomationService.getRules()
    print(string.format("Loaded %d automation rules:\n", #rules))
    for i, r in ipairs(rules) do
        local status = r.enabled and "[ACTIVE]" or "[DISABLED]"
        local trig = r.trigger or {}
        local act = r.action or {}
        print(string.format("%d. %s %s", i, status, r.name or r.id))
        print(string.format("   Trigger: IF %s %s %s", trig.item or trig.type, trig.condition or "<=", trig.threshold or 0))
        if trig.reset_cond and trig.reset_thresh then
            print(string.format("   Reset:   IF %s %s %s", trig.item or trig.type, trig.reset_cond, trig.reset_thresh))
        end
        print(string.format("   Action:  SET Relay '%s' -> %s\n", act.target_relay or "?", act.state and "ON" or "OFF"))
    end
    print("Commands:")
    print("  rules add <item> <cond> <thresh> <relay> [reset_cond] [reset_thresh]")
    print("  rules toggle <index>")
    print("  rules delete <index>")

elseif cmd == "add" then
    local item = args[2]
    local cond = args[3] or "<="
    local thresh = tonumber(args[4]) or 100
    local relay = args[5] or "Relay 1"
    local reset_cond = args[6] or ">="
    local reset_thresh = tonumber(args[7]) or (thresh * 2)

    if not item then
        print("Usage: rules add <item_id> <cond> <thresh> <relay_name>")
        print("Example: rules add minecraft:iron_ingot <= 120 \"Iron Farm\" >= 500")
        return
    end

    local newRule = {
        id          = "rule_" .. tostring(os.time()),
        name        = "Auto " .. item,
        enabled     = true,
        trigger     = {
            type         = "item_count",
            item         = item,
            condition    = cond,
            threshold    = thresh,
            reset_cond   = reset_cond,
            reset_thresh = reset_thresh,
        },
        action      = {
            type         = "set_relay",
            target_relay = relay,
            state        = true,
        },
        reset_action= {
            type         = "set_relay",
            target_relay = relay,
            state        = false,
        },
        cooldown    = 10,
        notify      = true,
    }

    AutomationService.addRule(newRule)
    print(string.format("[SUCCESS] Added rule: IF %s %s %d -> Relay '%s' ON (Reset %s %d)", item, cond, thresh, relay, reset_cond, reset_thresh))

elseif cmd == "toggle" then
    local idx = tonumber(args[2])
    local rules = AutomationService.getRules()
    if idx and rules[idx] then
        rules[idx].enabled = not rules[idx].enabled
        AutomationService.saveRules()
        print(string.format("[OK] Rule %d '%s' is now %s", idx, rules[idx].name, rules[idx].enabled and "ENABLED" or "DISABLED"))
    else
        print("Invalid rule index!")
    end

elseif cmd == "delete" or cmd == "remove" then
    local idx = tonumber(args[2])
    local rules = AutomationService.getRules()
    if idx and rules[idx] then
        local name = rules[idx].name
        AutomationService.deleteRule(idx)
        print(string.format("[OK] Deleted rule %d '%s'", idx, name))
    else
        print("Invalid rule index!")
    end
end
