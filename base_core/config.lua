-- ============================================================
-- base_core/config.lua
-- Глобальная конфигурация BaseCore OS & AR-Link
-- ============================================================

local Config = {
    -- ── Сетевые настройки ──────────────────────────────────────
    NETWORK = {
        PROTOCOL       = "NexiNetSystem",
        SECRET_KEY     = "FurryTop621OwO",
        BROADCAST_CHAN = 65530,
        HEARTBEAT_SEC  = 5,
        TIMEOUT_SEC    = 15,
    },

    -- ── Настройки сервера и сервисов ───────────────────────────
    SERVER = {
        NAME           = "NEXI",
        POLL_RATE_SEC  = 1.0,      -- Частота опроса локальной периферии
        LOG_MAX_LINES  = 50,       -- Максимум строк в истории лога
        MONITOR_SCALE  = 0.5,      -- Масштаб шрифта монитора (0.5 для четкости на 5x3)
    },

    -- ── Пороги алертов ─────────────────────────────────────────
    ALERTS = {
        STRESS_WARN_PCT   = 85,    -- Предупреждение при нагрузке Create > 85%
        STRESS_CRIT_PCT   = 98,    -- Критический алерт при перегрузке
        FE_LOW_PCT        = 15,    -- Предупреждение при низком заряде FE
        STORAGE_FULL_PCT  = 90,    -- Предупреждение при заполнении хранилища
        RADAR_THREAT_DIST = 120,   -- Дистанция тревоги радара (в блоках)
    },

    -- ── Фильтрация и режимы Радара ─────────────────────────────
    RADAR = {
        MODE        = "PLAYERS_ONLY", -- "PLAYERS_ONLY" (только игроки), "PLAYERS_AND_CONTRAPTIONS", "ALL"
        IGNORE_MOBS = true,           -- Игнорировать обычных мобов и животных
        THREAT_DIST = 120,            -- Дистанция тревоги (в блоках)
    },

    -- ── Отслеживаемые ресурсы на складе ────────────────────────
    TRACKED_ITEMS = {
        { id = "minecraft:iron_ingot",             label = "Iron",       icon = "Fe" },
        { id = "minecraft:copper_ingot",           label = "Copper",     icon = "Cu" },
        { id = "minecraft:gold_ingot",             label = "Gold",       icon = "Au" },
        { id = "create:andesite_alloy",            label = "Andesite",   icon = "An" },
        { id = "create:brass_ingot",               label = "Brass",      icon = "Br" },
        { id = "create:zinc_ingot",                label = "Zinc",       icon = "Zn" },
        { id = "minecraft:coal",                   label = "Coal",       icon = "C"  },
        { id = "minecraft:redstone",               label = "Redstone",   icon = "Rs" },
        { id = "minecraft:diamond",                label = "Diamond",    icon = "Dm" },
        { id = "minecraft:netherite_ingot",        label = "Netherite",  icon = "Ne" },
    },

    -- ── Белый список союзников по никам (Whitelist) ────────────
    ALLIES = {
        "Avellc",
        -- Добавьте сюда ники друзей:
        -- "FriendNick1",
        -- "FriendNick2",
    },

    -- ── Настройки Smart Glasses HUD (AP 0.8) ───────────────────
    GLASSES = {
        MAX_NOTIFICATIONS = 5,
        NOTIF_DURATION    = 10,    -- Секунд отображения всплывающего алерта
        SHOW_STATUS_BAR   = true,  -- Показывать ли мини-виджет базы в углу
        PLAY_SOUNDS       = true,  -- Воспроизводить звуки через speaker
    },

    -- ── Настройки интеграции с сервером OpenClaw (HTTP) ─────────
    OPENCLAW = {
        ENABLED        = false,                         -- Поставьте true для активации моста
        SERVER_URL     = "http://127.0.0.1:8080",       -- Адрес вашего сервера OpenClaw
        API_KEY        = "OpenClaw_Secure_Token_2026",  -- Токен авторизации (Bearer API Key)
        SYNC_RATE_SEC  = 5,                             -- Частота синхронизации телеметрии (сек)
        SEND_ALERTS    = true,                          -- Отправлять ли пуш-алерты в веб/Telegram
    },

    -- ── Цветовая палитра UI монитора (colors.*) ───────────────
    PALETTE = {
        BG         = colors.black,
        PANEL_BG   = colors.gray,
        PANEL_ALT  = colors.lightGray,
        BORDER     = colors.lightGray,
        TEXT       = colors.white,
        TEXT_DIM   = colors.lightGray,
        TEXT_MUTED = colors.gray,
        ACCENT     = colors.cyan,
        PRIMARY    = colors.blue,
        SUCCESS    = colors.green,
        WARNING    = colors.orange,
        DANGER     = colors.red,
        HIGHLIGHT  = colors.yellow,
    },
}

return Config
