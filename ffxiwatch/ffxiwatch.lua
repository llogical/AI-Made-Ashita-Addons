-- ffxiwatch (Ashita v4)
-- Author: Klipsy
-- Version: 2.1.0
-- Desc: Forwards selected FFXI chat to Discord webhooks. Per-character JSON settings,
--       Ashita-style chat output, and in-game toggles for Party / Linkshell / Linkshell2.
--
-- Commands (aliases: /ffxiwatch, /ffw)
--   /ffw status            - Show current toggle status and which webhooks are set
--   /ffw help              - Show this help
--   /ffw reload            - Reload settings.json from disk
--   /ffw party on|off      - Toggle Party forwarding
--   /ffw ls1 on|off        - Toggle Linkshell 1 forwarding
--   /ffw ls2 on|off        - Toggle Linkshell 2 forwarding (mode 27)
--   /ffw debug on|off      - Toggle debug logging

addon.name    = 'ffxiwatch';
addon.author  = 'Klipsy';
addon.version = '2.1.0';
addon.desc    = 'FFXI chat to Discord with webhooks and per-character settings.';

require('common');
local chat  = require('chat');
local json  = require('json');
local ffi   = require('ffi');

-- Minimal ltn12 replacement (if not provided by luasocket build)
local ltn12 = {}
function ltn12.source_string(s)
    local done = false
    return function()
        if not done then done = true; return s end
        return nil
    end
end
function ltn12.sink_table(t)
    return function(chunk, err)
        if chunk then table.insert(t, chunk) end
        return 1
    end
end
ltn12.source = { string = ltn12.source_string }
ltn12.sink   = { table  = ltn12.sink_table }

local http_ok, http = pcall(require, 'socket.http')
if not http_ok then
    print(chat.header(addon.name):append(chat.error('luasocket not found (socket.http). Webhook sending disabled.')));
    http = nil
end

-- -------------------------------
-- Paths / settings
-- -------------------------------
local install = AshitaCore:GetInstallPath();

local function get_self_name()
    local p = AshitaCore:GetMemoryManager():GetParty();
    if not p or type(p.GetMemberName) ~= 'function' then return nil end
    local n = p:GetMemberName(0)
    if type(n) ~= 'string' then return nil end
    n = n:gsub('%z.*','')
    if n == '' then return nil end
    return n
end

local function ensure_dir(path)
    if not ashita.fs.exists(path) then
        ashita.fs.create_directory(path)
    end
end

local function settings_path_for(name)
    if not name or name == '' then
        return string.format('%s\\config\\addons\\ffxiwatch\\default\\settings.json', install)
    end
    return string.format('%s\\config\\addons\\ffxiwatch\\%s\\settings.json', install, name)
end

local defaults = {
    webhooks = {
        -- Optional channels (leave blank to disable):
        ["1"]  = "", -- Say
        ["2"]  = "", -- Shout
        ["7"]  = "", -- Emote
        ["9"]  = "", -- Yell
        ["10"] = "", -- Unity

        -- Primary channels:
        ["3"]  = "", -- Tell
        ["4"]  = "", -- Party
        ["5"]  = "", -- Linkshell 1
        ["27"] = "", -- Linkshell 2  (note: LS2 uses 27 on your install)
    },
    forward = {
        party = true,
        ls1   = true,
        ls2   = true,
    },
    debug = false
}

local SETTINGS = nil
local SETTINGS_PATH = nil

local function save_settings()
    if not SETTINGS_PATH or not SETTINGS then return end
    local f = io.open(SETTINGS_PATH, 'w')
    if not f then
        print(chat.header(addon.name):append(chat.error('Failed to write settings: ' .. tostring(SETTINGS_PATH))));
        return
    end
    f:write(json.encode(SETTINGS))
    f:close()
end

local function load_or_init_settings()
    local me = get_self_name() or 'default'
    local dir = string.format('%s\\config\\addons\\ffxiwatch\\%s', install, me)
    ensure_dir(string.format('%s\\config\\addons', install))
    ensure_dir(string.format('%s\\config\\addons\\ffxiwatch', install))
    ensure_dir(dir)
    local path = settings_path_for(me)
    SETTINGS_PATH = path

    if not ashita.fs.exists(path) then
        SETTINGS = defaults
        save_settings()
        print(chat.header(addon.name):append(chat.message('Created settings: ' .. path)))
    else
        local f = io.open(path, 'r')
        if f then
            local txt = f:read('*a'); f:close()
            local ok, t = pcall(json.decode, txt)
            if ok and type(t) == 'table' then
                -- fill any missing keys from defaults
                for k,v in pairs(defaults) do
                    if t[k] == nil then t[k] = v end
                end
                -- fill nested
                for k,v in pairs(defaults.webhooks) do
                    if not t.webhooks[k] then t.webhooks[k] = v end
                end
                for k,v in pairs(defaults.forward) do
                    if t.forward[k] == nil then t.forward[k] = v end
                end
                SETTINGS = t
            else
                SETTINGS = defaults
            end
        else
            SETTINGS = defaults
        end
    end
end

-- -------------------------------
-- Helpers
-- -------------------------------
local chat_names = {
    [1]  = 'Say',
    [2]  = 'Shout',
    [3]  = 'Tell',
    [4]  = 'Party',
    [5]  = 'Linkshell 1',
    [6]  = 'Linkshell 2 (legacy)',
    [7]  = 'Emote',
    [9]  = 'Yell',
    [10] = 'Unity',
    [27] = 'Linkshell 2',
}

local function markup(chat_mode, sender, message)
    if chat_mode == 3 then
        return string.format('📩 **[Tell] %s:** %s', sender, message)
    elseif chat_mode == 4 then
        return string.format('🔵 **[Party] %s:** %s', sender, message)          -- blue circle feel
    elseif chat_mode == 5 then
        return string.format('🟧 **[LS1] %s:** %s', sender, message)             -- orange square
    elseif chat_mode == 27 then
        return string.format('🟩 **[LS2] %s:** %s', sender, message)             -- green square
    elseif chat_mode == 2 then
        return string.format('🔴 **[Shout] %s:** %s', sender, message)
    elseif chat_mode == 9 then
        return string.format('📢 **[Yell] %s:** %s', sender, message)
    elseif chat_mode == 7 then
        return string.format('🤔 *[Emote] %s %s*', sender, message)
    elseif chat_mode == 1 then
        return string.format('💬 **[Say] %s:** %s', sender, message)
    elseif chat_mode == 10 then
        return string.format('🌐 **[Unity] %s:** %s', sender, message)
    else
        return string.format('[%s] %s: %s', chat_names[chat_mode] or tostring(chat_mode), sender, message)
    end
end

local function has_webhook(mode)
    if not SETTINGS or not SETTINGS.webhooks then return false end
    local key = tostring(mode)
    local v = SETTINGS.webhooks[key]
    return (type(v) == 'string' and v ~= '')
end

local function wh_url(mode)
    return SETTINGS.webhooks[tostring(mode)]
end

local function debugf(fmt, ...)
    if SETTINGS and SETTINGS.debug then
        print(chat.header(addon.name):append(chat.message(string.format('[dbg] ' .. fmt, ...))))
    end
end

local function send_to_discord(mode, text)
    if not http then return end
    if not has_webhook(mode) then
        debugf('No webhook for mode %s', tostring(mode))
        return
    end
    local url = wh_url(mode)
    local body = '{"content":"' .. text:gsub('\\', '\\\\'):gsub('"','\\"') .. '"}'
    local resp = {}
    local ok, code, headers, status = http.request{
        url = url,
        method = 'POST',
        headers = {
            ["Content-Type"] = "application/json",
            ["Content-Length"] = tostring(#body),
        },
        source = ltn12.source.string(body),
        sink   = ltn12.sink.table(resp),
    }
    debugf('POST %s -> %s', tostring(mode), tostring(code))
end

-- -------------------------------
-- Event: load
-- -------------------------------
ashita.events.register('load', 'ffxiwatch_load', function()
    load_or_init_settings()
    print(chat.header(addon.name):append(chat.message('Loaded. Use /ffw help for commands.')))
end)

-- -------------------------------
-- Command handler
-- -------------------------------
local function print_status()
    local w = SETTINGS.webhooks or {}
    local function setmark(mode) return (w[tostring(mode)] and w[tostring(mode)] ~= '' and 'set') or 'unset' end
    local lines = {
        string.format('Party: %s  | LS1: %s  | LS2: %s', SETTINGS.forward.party and 'ON' or 'OFF', SETTINGS.forward.ls1 and 'ON' or 'OFF', SETTINGS.forward.ls2 and 'ON' or 'OFF'),
        string.format('Webhooks - Tell:%s Party:%s LS1:%s LS2:%s  (Say:%s Shout:%s Emote:%s Yell:%s Unity:%s)',
            setmark(3), setmark(4), setmark(5), setmark(27), setmark(1), setmark(2), setmark(7), setmark(9), setmark(10))
    }
    for _,l in ipairs(lines) do
        print(chat.header(addon.name):append(chat.message(l)))
    end
end

local function print_help()
    local lines = {
        'Commands:',
        '  /ffw status           - Show status and webhook presence',
        '  /ffw reload           - Reload settings',
        '  /ffw party on|off     - Toggle Party forwarding',
        '  /ffw ls1 on|off       - Toggle Linkshell 1 forwarding',
        '  /ffw ls2 on|off       - Toggle Linkshell 2 forwarding (mode 27)',
        '  /ffw debug on|off     - Toggle debug logs',
    }
    for _,l in ipairs(lines) do
        print(chat.header(addon.name):append(chat.message(l)))
    end
end

ashita.events.register('command', 'ffxiwatch_cmd', function(e)
    local args = e.command:args()
    if #args == 0 then return end

    local cmd = args[1]
    if not (cmd:any('/ffxiwatch') or cmd:any('/ffw')) then return end
    e.blocked = true

    local sub = args[2] and args[2]:lower() or 'help'
    if sub == 'help' then
        print_help(); return
    elseif sub == 'status' then
        print_status(); return
    elseif sub == 'reload' then
        load_or_init_settings(); print(chat.header(addon.name):append(chat.message('Settings reloaded.'))); return
    elseif sub == 'debug' then
        local v = args[3] and args[3]:lower() or ''
        if v == 'on' or v == 'off' then
            SETTINGS.debug = (v == 'on'); save_settings()
            print(chat.header(addon.name):append(chat.message('Debug: ' .. (SETTINGS.debug and 'ON' or 'OFF'))))
        else
            print(chat.header(addon.name):append(chat.message('Usage: /ffw debug on|off')))
        end
        return
    elseif sub == 'party' or sub == 'ls1' or sub == 'ls2' then
        local v = args[3] and args[3]:lower() or ''
        if v ~= 'on' and v ~= 'off' then
            print(chat.header(addon.name):append(chat.message('Usage: /ffw ' .. sub .. ' on|off')))
            return
        end
        local flag = (v == 'on')
        if sub == 'party' then SETTINGS.forward.party = flag
        elseif sub == 'ls1' then SETTINGS.forward.ls1 = flag
        elseif sub == 'ls2' then SETTINGS.forward.ls2 = flag end
        save_settings()
        print(chat.header(addon.name):append(chat.message(string.format('%s forwarding %s', sub:upper(), flag and 'ON' or 'OFF'))))
        return
    else
        print_help(); return
    end
end)

-- -------------------------------
-- Packet hook (0x17 = chat)
-- -------------------------------
ashita.events.register('packet_in', 'ffxiwatch_packet', function(e)
    if e.id ~= 0x17 then return end

    local data = ffi.cast('uint8_t*', e.data_raw)
    local mode = data[4]

    -- Apply toggles for the core channels
    if mode == 4 and not SETTINGS.forward.party then return end
    if mode == 5 and not SETTINGS.forward.ls1   then return end
    if mode == 27 and not SETTINGS.forward.ls2  then return end

    if not has_webhook(mode) then
        -- ignore quietly if no webhook is defined for this mode
        return
    end

    local sender  = ffi.string(ffi.cast('char*', data + 8))
    local message = ffi.string(ffi.cast('char*', data + 23))
    if not message or message == '' then return end

    local out = string.format('[%s] %s', os.date('%H:%M'), markup(mode, sender, message))
    debugf('Forwarding %s from %s: %s', chat_names[mode] or tostring(mode), sender, message)
    send_to_discord(mode, out)
end)
