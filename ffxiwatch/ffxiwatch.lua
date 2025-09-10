

addon.name    = 'ffxiwatch'
addon.author  = 'Ilogical'
addon.version = '2.3'
addon.desc    = 'Forward Tell/Party/Linkshell chats to Discord with simple toggles.'
addon.link    = 'https://ashitaxi.com/'

require('common')
local chat     = require('chat')
local settings = require('settings')
local ffi      = require('ffi')


local ltn12 = {}
do
    local function src_string(s)
        local done = false
        return function()
            if not done then done = true; return s end
            return nil
        end
    end
    local function sink_table(t)
        return function(chunk, err)
            if chunk then table.insert(t, chunk) end
            return 1
        end
    end
    ltn12.source = { string = src_string }
    ltn12.sink   = { table  = sink_table  }
end

local http = require('socket.http')


local defaults = T{
    -- Forwarding toggles (true = forward)
    forward_party = true,
    forward_ls1   = true,
    forward_ls2   = true,  -- LS2 is chat mode 27 on your server
    -- Optional channels (off by default; add webhooks if you want them)
    forward_say   = false,
    forward_shout = false,
    forward_emote = false,
    forward_yell  = false,
    forward_unity = false,

    -- Debug prints to Ashita log
    debug         = false,

    -- Webhooks by chat mode id (string keys for safety)
    -- Fill these in your generated settings.lua after first load.
    webhooks = T{
        ['3']  = '', -- Tell
        ['4']  = '', -- Party
        ['5']  = '', -- Linkshell 1
        ['27'] = '', -- Linkshell 2 (your environment)
        -- Optional:
        ['1']  = '', -- Say
        ['2']  = '', -- Shout
        ['7']  = '', -- Emote
        ['9']  = '', -- Yell
        ['10'] = '', -- Unity
    },
}


local S = settings.load(defaults)

-- Normalize in case older files had weird shapes
local function ensure_bool(k, def) S[k] = (type(S[k]) == 'boolean') and S[k] or def end
ensure_bool('forward_party', true)
ensure_bool('forward_ls1',   true)
ensure_bool('forward_ls2',   true)
ensure_bool('forward_say',   false)
ensure_bool('forward_shout', false)
ensure_bool('forward_emote', false)
ensure_bool('forward_yell',  false)
ensure_bool('forward_unity', false)
ensure_bool('debug',         false)
if type(S.webhooks) ~= 'table' then S.webhooks = T{} end

-- React to character swap / external edits
settings.register('settings', 'ffxiwatch_settings_update', function(t)
    if t ~= nil then S = t end
end)

----------------------------------------------------------------
-- Chat names + Discord formatting
----------------------------------------------------------------
local chat_names = {
    [1]  = 'Say',
    [2]  = 'Shout',
    [3]  = 'Tell',
    [4]  = 'Party',
    [5]  = 'Linkshell 1',
    [6]  = 'Linkshell 2',   -- classic id; not used 
    [7]  = 'Emote',
    [9]  = 'Yell',
    [10] = 'Unity',
    [27] = 'Linkshell 2',   -- your actual LS2 id
}

local function format_message(mode, sender, message)
    -- Emojis you requested earlier:
    -- Tell=📩, Party=🔵, LS1=🟧, LS2=🟩, Shout=🔴, Yell=📢, Emote=🤔, Say=💬, Unity=🌐
    if     mode == 3  then return string.format('📩 **[Tell] %s:** %s',          sender, message)
    elseif mode == 4  then return string.format('🔵 **[Party] %s:** %s',         sender, message)
    elseif mode == 5  then return string.format('🟧 **[Linkshell 1] %s:** %s',   sender, message)
    elseif mode == 27 then return string.format('🟩 **[Linkshell 2] %s:** %s',   sender, message)
    elseif mode == 2  then return string.format('🔴 **[Shout] %s:** %s',         sender, message)
    elseif mode == 9  then return string.format('📢 **[Yell] %s:** %s',          sender, message)
    elseif mode == 7  then return string.format('🤔 *[Emote] %s %s*',            sender, message)
    elseif mode == 1  then return string.format('💬 **[Say] %s:** %s',           sender, message)
    elseif mode == 10 then return string.format('🌐 [Unity] %s: %s',             sender, message)
    else
        local name = chat_names[mode] or tostring(mode)
        return string.format('[%s] %s: %s', name, sender, message)
    end
end

----------------------------------------------------------------
-- Forwarding gates
----------------------------------------------------------------
local function is_forward_enabled(mode)
    if     mode == 3  then return true                   -- Tell always on
    elseif mode == 4  then return S.forward_party
    elseif mode == 5  then return S.forward_ls1
    elseif mode == 27 then return S.forward_ls2
    elseif mode == 1  then return S.forward_say
    elseif mode == 2  then return S.forward_shout
    elseif mode == 7  then return S.forward_emote
    elseif mode == 9  then return S.forward_yell
    elseif mode == 10 then return S.forward_unity
    end
    return false
end

local function webhook_for_mode(mode)
    local key = tostring(mode)
    local url = S.webhooks[key]
    if type(url) ~= 'string' then return nil end
    if url == '' then return nil end
    return url
end

----------------------------------------------------------------
-- Discord POST
----------------------------------------------------------------
local function send_to_discord(mode, content)
    local url = webhook_for_mode(mode)
    if not url then
        if S.debug then
            print(chat.header(addon.name):append(chat.message(
                string.format('No webhook set for chat mode %s.', tostring(mode))
            )))
        end
        return
    end

    local body = '{"content":"' .. content:gsub('\\', '\\\\'):gsub('"', '\\"') .. '"}'
    local response_body = {}
    local res, code = http.request{
        url = url,
        method = 'POST',
        headers = {
            ['Content-Type']   = 'application/json',
            ['Content-Length'] = tostring(#body),
        },
        source = ltn12.source.string(body),
        sink   = ltn12.sink.table(response_body),
    }

    if S.debug then
        print(chat.header(addon.name):append(chat.message(
            string.format('POST (%s) code=%s', tostring(mode), tostring(code))
        )))
    end
end

----------------------------------------------------------------
-- Packet hook
----------------------------------------------------------------
ashita.events.register('packet_in', 'ffxiwatch_packet_in', function(e)
    -- Incoming chat: 0x17
    if e.id ~= 0x17 then return end

    local data = ffi.cast('uint8_t*', e.data_raw)
    local mode = data[4]

    -- LS2 on your environment uses 27; keep classic 6 unused
    if not is_forward_enabled(mode) then
        if S.debug then
            print(chat.header(addon.name):append(chat.message(
                string.format('Mode %d blocked by toggle.', mode)
            )))
        end
        return
    end

    local sender  = ffi.string(ffi.cast('char*', data + 8))
    local message = ffi.string(ffi.cast('char*', data + 23))

    if not message or message == '' then return end

    local line = string.format('[%s] %s', os.date('%H:%M'), format_message(mode, sender, message))

    if S.debug then
        print(chat.header(addon.name):append(chat.message(
            string.format('Forwarding %s from %s: %s', chat_names[mode] or tostring(mode), sender, message)
        )))
    end

    send_to_discord(mode, line)
end)

----------------------------------------------------------------
-- Commands
----------------------------------------------------------------
local function print_status()
    local lines = {
        string.format('Forward: Party=%s, LS1=%s, LS2=%s | Optional: Say=%s, Shout=%s, Emote=%s, Yell=%s, Unity=%s',
            tostring(S.forward_party), tostring(S.forward_ls1), tostring(S.forward_ls2),
            tostring(S.forward_say), tostring(S.forward_shout), tostring(S.forward_emote),
            tostring(S.forward_yell), tostring(S.forward_unity)),
        string.format('Webhooks set: Tell=%s, Party=%s, LS1=%s, LS2=%s',
            (S.webhooks['3']  ~= ''), (S.webhooks['4']  ~= ''), (S.webhooks['5']  ~= ''), (S.webhooks['27'] ~= '')),
        'Edit your webhooks in: Ashita 4/config/addons/ffxiwatch/<Character>/settings.lua',
    }
    for _, l in ipairs(lines) do
        print(chat.header(addon.name):append(chat.message(l)))
    end
end

local function print_help()
    local lines = {
        'Usage: /ffw [subcommand]',
        '  /ffw status            - Show current settings',
        '  /ffw reload            - Reload settings from disk',
        '  /ffw debug on|off      - Toggle debug logs',
        '  /ffw party on|off      - Forward Party',
        '  /ffw ls1 on|off        - Forward Linkshell 1',
        '  /ffw ls2 on|off        - Forward Linkshell 2 (mode 27)',
        '  /ffw say on|off        - (optional) Forward Say',
        '  /ffw shout on|off      - (optional) Forward Shout',
        '  /ffw emote on|off      - (optional) Forward Emote',
        '  /ffw yell on|off       - (optional) Forward Yell',
        '  /ffw unity on|off      - (optional) Forward Unity',
        '',
        'Set webhooks by editing your settings.lua (first run generates it).',
    }
    for _, l in ipairs(lines) do
        print(chat.header(addon.name):append(chat.message(l)))
    end
end

local function set_toggle(key, val)
    local on = (val == 'on')
    S[key] = on
    settings.save()
    print(chat.header(addon.name):append(chat.message(
        string.format('%s: %s', key, on and 'ON' or 'OFF')
    )))
end

ashita.events.register('command', 'ffxiwatch_command', function(e)
    local args = e.command:args()
    if #args == 0 then return end
    local cmd = args[1]:lower()

    if not (cmd == '/ffxiwatch' or cmd == '/ffw') then return end
    e.blocked = true

    local sub = args[2] and args[2]:lower() or ''

    if sub == '' or sub == 'help' then
        print_help()
        return
    end

    if sub == 'status' then
        print_status()
        return
    end

    if sub == 'reload' then
        settings.reload()
        print(chat.header(addon.name):append(chat.message('Settings reloaded.')))
        return
    end

    if sub == 'debug' and args[3] then
        S.debug = (args[3]:lower() == 'on')
        settings.save()
        print(chat.header(addon.name):append(chat.message('Debug: ' .. (S.debug and 'ON' or 'OFF'))))
        return
    end

    -- Toggles
    local map = {
        party = 'forward_party',
        ls1   = 'forward_ls1',
        ls2   = 'forward_ls2',
        say   = 'forward_say',
        shout = 'forward_shout',
        emote = 'forward_emote',
        yell  = 'forward_yell',
        unity = 'forward_unity',
    }
    if map[sub] and args[3] then
        local v = args[3]:lower()
        if v == 'on' or v == 'off' then
            set_toggle(map[sub], v)
            return
        end
    end

    print_help()
end)

----------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------
ashita.events.register('load', 'ffxiwatch_load', function()
    -- Quiet load to keep logs clean (per your preference).
    -- Ensure we persist defaults for this character on first run:
    settings.save()
end)

ashita.events.register('unload', 'ffxiwatch_unload', function()
    settings.save()
end)
