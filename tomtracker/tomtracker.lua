addon.name      = 'ToM Tracker';
addon.author    = 'Ilogical';
addon.version   = '1.0.0'
addon.desc      = 'Tracks Trial of the Magians progress with a compact HUD.';
addon.link      = 'https://ashitaxi.com/';
addon.commands  = { 'tom' }

require('common')
local imgui = require('imgui')
local chat  = require('chat')
local bit   = require('bit')

-- ============= UI state / config =============
local ui = { is_open = { true } }

local cfg = {
    announce_enabled = true,
    announce_round   = 10,       -- default milestone interval
    announce_chan    = 'ls',     -- 'p' | 'ls' | 'ls2'
    announce_mode    = 'final',  -- 'step' (every N) | 'final' (when N remain)
    autolabel        = true,     -- fill desc from map by trial id
    debug            = false,    -- no UI toggle; use /tom debug on|off
}

local trial = { id = 0, desc = '', remaining = -1, last_announced_for = -1 }

-- ============= Path helpers =============
local function get_addon_dir()
    local src = ''
    if debug and debug.getinfo then
        local info = debug.getinfo(1, 'S')
        if info and info.source then src = info.source end
    end
    if src ~= '' then
        src = src:gsub('^@', '')
        local dir = src:match('^(.+)[\\/].-$')
        if dir and dir ~= '' then return dir end
    end
    local ok, base = pcall(function() return AshitaCore:GetInstallPath() end)
    if ok and base and base ~= '' then return base .. '\\addons\\tomtracker' end
    return '.\\addons\\tomtracker'
end
local function path_join(a,b)
    if a:sub(-1) == '\\' or a:sub(-1) == '/' then return a .. b end
    return a .. '\\' .. b
end
local function file_exists(p)
    local f = io.open(p, 'r')
    if f then f:close(); return true end
    return false
end

-- ============= Built-in minimal map + tags (you can extend via external map) =============
local TRIAL_NAME_MAP = {
    [1019] = 'Burtgang (Mythic): Atonement KB vs Dragons x200',
    [1024] = 'Ragnarok (Relic): Scourge vs Birds x200',
    [150]  = 'Almace (Empy): Serpopard Ishtar x3',
    [216]  = 'Caladbolg (Empy): Bloodpool Vorax x3',
    [891]  = 'Marksmanship OA2 (early)',
    [1783] = 'Marksmanship Damage path (early)',
}
local TRIAL_TAGS = {}
local function _tag_many(list,label) for _,id in ipairs(list) do TRIAL_TAGS[id]=label end end
_tag_many({891,892,893,899,900,901,1761,1762,2236,2646,3079,3542}, 'Speed (OA2) [Gun]')
_tag_many({902,903,904,1763,1764,2237,2647,3080,3543}, 'Speed (OA2-4) [Gun]')
_tag_many({1765,2238,2648,3081,3544}, 'Speed (ODD) [Gun]')
_tag_many({1783,1784,1785,1786,1787,2247,2248,2657,2658,2659,3090,3091,3092,3553,3554,3555}, 'Damage (WSD/TP/STP) [Gun]')

-- ============= External trials_map.lua loader =============
local external_map_loaded, external_added = false, 0
local function load_trials_map()
    local dir = get_addon_dir()
    local path = path_join(dir, 'trials_map.lua')
    if not file_exists(path) then
        if cfg.debug then
            print(chat.header(addon.name):append(chat.message('trials_map.lua not found at: ' .. path)))
        end
        return false
    end
    local ok, tbl = pcall(dofile, path)
    if not ok then
        print(chat.header(addon.name):append(chat.error('Failed to load trials_map.lua: ' .. tostring(tbl))))
        return false
    end
    if type(tbl) ~= 'table' then
        print(chat.header(addon.name):append(chat.error('trials_map.lua did not return a table.')))
        return false
    end
    local added = 0
    for id, desc in pairs(tbl) do
        if type(id) == 'number' and type(desc) == 'string' then
            TRIAL_NAME_MAP[id] = desc
            added = added + 1
        end
    end
    external_map_loaded, external_added = true, added
    print(chat.header(addon.name):append(chat.message(string.format('Loaded trials_map.lua (%d entries).', added))))
    return true
end

-- ============= ImGui helpers =============
local function char_width(n)
    if imgui.CalcTextSize ~= nil then
        local s = string.rep('X', n)
        local w = imgui.CalcTextSize(s)
        if type(w) == 'table' and w.x then return w.x + 10 end
        if type(w) == 'number' then return w + 10 end
    end
    return n * 8 + 10
end
local WIDTH_6, WIDTH_8, WIDTH_TID, WIDTH_DESC2X = char_width(6), char_width(8), char_width(12), char_width(44)

-- ============= Parsing =============
local function clean_text(raw)
    local s=(raw or ''):gsub('\x1E',''):gsub('\x1F.','')
    return s:gsub('[\r\n]',' ')
end
local function parse_progress_line(raw)
    local lower = clean_text(raw):lower()
    local tnum, rem = lower:match('trial%s+(%d+)%s*[:：%-–—]%s*([%d,]+)%s+objective[s]?%s+remain[ing]?%.?')
    if not tnum then
        tnum, rem = lower:match('trial%s+(%d+).-([%d,]+)%s+objective[s]?%s+remain[ing]?')
    end
    if tnum and rem then
        rem = rem:gsub(',', '')
        return tonumber(tnum), tonumber(rem)
    end
    return nil, nil
end
local function parse_completion_line(raw)
    local lower = clean_text(raw):lower()
    local t = lower:match('you%s+have%s+completed%s+trial%s+(%d+)%s*%.?')
    if t then return tonumber(t) end
    t = lower:match('trial%s+(%d+)%s+complete[sd]?%s*%.?')
    if t then return tonumber(t) end
    return nil
end

-- ============= Abyssea Zone IDs =============
local ABYSSEA_ZONES = {
    [15]="Abyssea - Konschtat",[45]="Abyssea - Tahrongi",[132]="Abyssea - La Theine",
    [215]="Abyssea - Attohwa",[216]="Abyssea - Misareaux",[217]="Abyssea - Vunkerl",
    [218]="Abyssea - Altepa",[253]="Abyssea - Uleguerand",[254]="Abyssea - Grauberg",
}
local abyssea_expire_at = 0 -- epoch seconds (fallback)

local function fmt_mmss(sec)
    sec = math.floor(tonumber(sec) or 0)
    local m = math.floor(sec / 60)
    local s = sec % 60
    return string.format('%d:%02d', m, s)
end
local function get_zone_id()
    local mm = AshitaCore:GetMemoryManager()
    if mm and mm.GetParty and mm:GetParty() and mm:GetParty().GetMemberZone then
        return mm:GetParty():GetMemberZone(0)
    end
    if mm and mm.GetZone then
        local z = mm:GetZone()
        if z and z.GetZoneId then return z:GetZoneId() end
    end
    return nil
end
local function in_abyssea()
    local zid = get_zone_id()
    if not zid then return false, nil end
    return ABYSSEA_ZONES[zid] ~= nil, zid
end
local function query_abyssea_seconds_left()
    local ok, p = pcall(function() return AshitaCore:GetMemoryManager():GetPlayer() end)
    if ok and p then
        if type(p.GetAbysseaTimeRemaining) == 'function' then
            local s = p:GetAbysseaTimeRemaining(); if s and s > 0 then return s end
        end
        if type(p.GetVisitantTimeRemaining) == 'function' then
            local s = p:GetVisitantTimeRemaining(); if s and s > 0 then return s end
        end
    end
    if abyssea_expire_at > os.time() then
        return abyssea_expire_at - os.time()
    end
    return nil
end

-- unified message builder (always returns a string)
local function build_progress_message(rem)
    local tnum   = (trial.id and trial.id > 0) and tostring(trial.id) or '—'
    local label  = (trial.desc and trial.desc ~= '') and trial.desc or 'Progress'

    local remaining_val = rem
    if remaining_val == nil then
        if trial.remaining ~= nil and trial.remaining >= 0 then
            remaining_val = trial.remaining
        else
            remaining_val = 'unknown'
        end
    end

    local msg = string.format('[ToM] Trial %s: %s remaining (%s).', tnum, tostring(remaining_val), label)

    local is_aby = in_abyssea()
    if is_aby then
        local secs = query_abyssea_seconds_left()
        if type(secs) == 'number' and secs > 0 then
            msg = msg .. ' | Abyssea: ' .. fmt_mmss(secs) .. ' left'
        end
    end
    return msg
end

-- ============= Announce helpers =============
local function send_chat(cmd) AshitaCore:GetChatManager():QueueCommand(-1, cmd) end
local function announce_in_channel(msg)
    msg = tostring(msg or '')
    if msg == '' then msg = '[ToM] (no message)' end
    if cfg.debug then print(chat.header(addon.name):append(chat.message('(announce) ' .. msg))) end
    local ch = (cfg.announce_chan or 'p'):lower()
    if ch == 'p' then
        send_chat('/p ' .. msg)
    elseif ch == 'ls' or ch == 'l' then
        send_chat('/l ' .. msg)
    elseif ch == 'ls2' or ch == 'l2' then
        send_chat('/l2 ' .. msg)
    else
        send_chat('/p ' .. msg)
    end
end
local function maybe_announce(remaining_now)
    if not cfg.announce_enabled then return end
    if not remaining_now or remaining_now < 0 then return end
    if remaining_now == 0 then return end
    local r = cfg.announce_round or 0
    if r <= 0 then return end

    local should = false
    if cfg.announce_mode == 'final' then
        should = (remaining_now == r)
    else
        should = ((remaining_now % r) == 0)
    end
    if not should then return end
    if trial.last_announced_for == remaining_now then return end

    local msg = build_progress_message(remaining_now)
    announce_in_channel(msg)
    trial.last_announced_for = remaining_now
end

-- ============= Name fallback + auto-label =============
local function maybe_autolabel()
    if not cfg.autolabel then return end
    if trial.id <= 0 then return end
    if trial.desc and trial.desc ~= '' then return end
    local nm = TRIAL_NAME_MAP[trial.id]
    if nm then
        trial.desc = nm
    end
end

-- ============= UI =============
local ROUND_CHOICES, ROUND_VALUES = {'100','50','25','10','1'}, {100,50,25,10,1}
local CHANNEL_LABELS, CHANNEL_CODES = {'Party','LS','LS2'},{'p','ls','ls2'}
local function idx_of_round(v) for i,n in ipairs(ROUND_VALUES) do if n==v then return i end end return 3 end
local function idx_of_channel(code) code=(code or 'p'):lower(); for i,c in ipairs(CHANNEL_CODES) do if c==code then return i end end return 1 end

local function render_ui()
    if not ui.is_open[1] then return end
    local flags = bit.bor(ImGuiWindowFlags_AlwaysAutoResize or 0, ImGuiWindowFlags_NoSavedSettings or 0)
    local opened = imgui.Begin('ToM Tracker##tomtracker', ui.is_open, flags)
    if opened then
        imgui.Text('Trial : ' .. (trial.id>0 and tostring(trial.id) or '—'))
        local show_desc = (trial.id==0 and (trial.desc=='' or trial.desc==nil)) and 'No trial set' or (trial.desc or '')
        imgui.Text('Desc  : ' .. show_desc)
        local tag = TRIAL_TAGS[trial.id]
        if tag then imgui.Text('Path  : ' .. tag) end
        imgui.Text('Remain: ' .. (trial.remaining>=0 and tostring(trial.remaining) or '—'))

        imgui.Separator()

        -- Manual inputs
        imgui.PushItemWidth(WIDTH_TID)
        local tnum_str = { trial.id>0 and tostring(trial.id) or '' }
        if imgui.InputText('Trial Number', tnum_str, 16) then
            local n = tonumber(tnum_str[1])
            if n and n>0 then
                trial.id = n
                if cfg.autolabel and (trial.desc=='' or trial.desc==nil) then
                    trial.desc = TRIAL_NAME_MAP[n] or trial.desc
                end
            end
        end
        imgui.PopItemWidth()

        imgui.PushItemWidth(WIDTH_DESC2X)
        local tdesc = { trial.desc }
        if imgui.InputText('Desc', tdesc, 512) then
            trial.desc = tdesc[1] or ''
        end
        imgui.PopItemWidth()

        -- Announce controls
        local abox = { cfg.announce_enabled }
        if imgui.Checkbox('Announce Milestones', abox) then cfg.announce_enabled = abox[1] end

        imgui.SameLine()
        imgui.PushItemWidth(WIDTH_6)
        local ridx = { idx_of_round(cfg.announce_round) - 1 }
        if imgui.Combo('##Round', ridx, table.concat(ROUND_CHOICES,'\0')..'\0') then
            cfg.announce_round = ROUND_VALUES[ridx[1]+1]
        end
        imgui.PopItemWidth()

        imgui.SameLine()
        imgui.PushItemWidth(WIDTH_8)
        local cidx = { idx_of_channel(cfg.announce_chan) - 1 }
        if imgui.Combo('Channel', cidx, table.concat(CHANNEL_LABELS,'\0')..'\0') then
            cfg.announce_chan = CHANNEL_CODES[cidx[1]+1]
        end
        imgui.PopItemWidth()

        imgui.SameLine()
        local MODE_LABELS = {'Every N','When N remain'}
        imgui.PushItemWidth(char_width(12))
        local midx = { (cfg.announce_mode=='final') and 1 or 0 }
        if imgui.Combo('Mode', midx, table.concat(MODE_LABELS,'\0')..'\0') then
            cfg.announce_mode = (midx[1]==1) and 'final' or 'step'
        end
        imgui.PopItemWidth()

        -- Autolabel toggle only
        local albox = { cfg.autolabel }
        if imgui.Checkbox('Autolabel from known trials', albox) then
            cfg.autolabel = albox[1]; if cfg.autolabel then maybe_autolabel() end
        end

        if external_map_loaded then
            imgui.TextDisabled(string.format('trials_map.lua: %d entries loaded.', external_added))
        else
            imgui.TextDisabled('trials_map.lua: (not loaded)')
        end
    end
    imgui.End()
end

-- ============= Event: parse chat (progress / completion + visitant timer) =============
local function handle_incoming_text(src, raw)
    if not raw or raw=='' then return end

    -- Abyssea Visitant time sniff (fallback from chat)
    do
        local l = clean_text(raw):lower()
        if l:find('visitant') and (l:find('wear off in') or l:find('remaining')) then
            local mins = tonumber(l:match('(%d+)%s*minute')) or 0
            local secs = tonumber(l:match('(%d+)%s*second')) or 0
            local total = mins * 60 + secs
            if total <= 0 then
                mins = tonumber(l:match('(%d+)%s*min')) or mins
                total = mins * 60
            end
            if total > 0 then
                abyssea_expire_at = os.time() + total
                if cfg.debug then
                    print(chat.header(addon.name):append(chat.message(string.format('[aby] timer set to %s (from chat)', fmt_mmss(total)))))
                end
            end
        end
    end

    -- Progress line
    local tnum, rem = parse_progress_line(raw)
    if tnum or rem then
        if cfg.debug then
            print(chat.header(addon.name):append(chat.message(string.format('[%s/progress] trial=%s rem=%s', src, tostring(tnum), tostring(rem)))))
        end
        if tnum and tnum>0 and tnum~=trial.id then
            trial.id = tnum
            if cfg.autolabel and (trial.desc=='' or trial.desc==nil) then
                maybe_autolabel()
            end
        end
        if rem ~= nil and rem ~= trial.remaining then
            trial.remaining = rem
            maybe_announce(rem)
        end
        return
    end

    -- Completion line
    local completed_id = parse_completion_line(raw)
    if completed_id then
        if cfg.debug then
            print(chat.header(addon.name):append(chat.message(string.format('[%s/complete] trial=%d', src, completed_id))))
        end
        trial.id = completed_id
        if cfg.autolabel and (trial.desc=='' or trial.desc==nil) then
            maybe_autolabel()
        end
        trial.remaining = 0
        announce_in_channel(string.format('[ToM] Trial %d: Completed! (%s).',
            completed_id, (trial.desc ~= '' and trial.desc or 'Trial')))
        return
    end

    -- Sniff logging if looks relevant
    if cfg.debug then
        local l = clean_text(raw):lower()
        if l:find('trial',1,true) or l:find('remain',1,true) or l:find('complete',1,true) then
            print(chat.header(addon.name):append(chat.message(string.format('[sniff:%s] %s', src, clean_text(raw)))))
        end
    end
end

-- ============= Events registration =============
ashita.events.register('d3d_present','present_cb_tom', function()
    render_ui()
end)
ashita.events.register('chat_in','chat_in_cb_tom', function(e) handle_incoming_text('chat_in', e.message) end)
ashita.events.register('text_in','text_in_cb_tom', function(e) handle_incoming_text('text_in', e.message) end)

-- ============= Commands =============
local function print_help()
    local lines={
        'Usage: /tom <subcommand>',
        '  /tom                          - Toggle HUD',
        '  /tom help                     - Show this help',
        '  /tom announce on|off          - Toggle milestone announcements',
        '  /tom round <100|50|25|10|1>   - Set milestone interval',
        '  /tom chan <party|ls|ls2>      - Set announcement channel',
        '  /tom mode <step|final>        - step=every N; final=when N remain',
        '  /tom trial <number>           - Set trial number',
        '  /tom desc <text>              - Set desc (alias: /tom type <text>)',
        '  /tom autolabel on|off         - Auto fill desc from trials_map.lua if known',
        '  /tom loadmap                  - Reload trials_map.lua next to addon',
        '  /tom mapinfo                  - Show where tomtracker is looking',
        '  /tom reset                    - Clear remaining/milestone',
        '  /tom debug on|off             - Toggle debug logging (no HUD checkbox)',
        '  /tom sim <trial> <remain>     - Simulate a progress line',
        '  /tom progress                 - Announce current progress now',
        '  /tom aby                      - Print Abyssea time left',
    }
    for _,l in ipairs(lines) do print(chat.header(addon.name):append(chat.message(l))) end
end

ashita.events.register('command','command_cb_tom', function(e)
    local args = e.command:args()
    if #args==0 or not args[1]:any('/tom') then return end
    e.blocked = true

    if #args==1 then
        ui.is_open[1] = not ui.is_open[1]
        return
    end

    if args[2]:any('help') then
        print_help(); return
    elseif args[2]:any('announce') and #args>=3 then
        cfg.announce_enabled = args[3]:any('on')
        print(chat.header(addon.name):append(chat.message('Announce: ' .. (cfg.announce_enabled and 'ON' or 'OFF'))))
    elseif args[2]:any('round') and #args>=3 then
        local n = tonumber(args[3])
        if n and (n==100 or n==50 or n==25 or n==10 or n==1) then cfg.announce_round = n end
    elseif args[2]:any('chan') and #args>=3 then
        local v = string.lower(args[3])
        if v=='party' or v=='p' then
            cfg.announce_chan='p'
        elseif v=='ls' or v=='l' or v=='linkshell' then
            cfg.announce_chan='ls'
        elseif v=='ls2' or v=='l2' then
            cfg.announce_chan='ls2'
        end
        local label = (cfg.announce_chan=='p') and 'Party' or ((cfg.announce_chan=='ls') and 'LS' or 'LS2')
        print(chat.header(addon.name):append(chat.message('Channel: ' .. label)))
    elseif args[2]:any('mode') and #args>=3 then
        local m = string.lower(args[3])
        cfg.announce_mode = (m=='final') and 'final' or 'step'
        print(chat.header(addon.name):append(chat.message('Announce Mode: ' .. cfg.announce_mode)))
    elseif args[2]:any('trial') and #args>=3 then
        local n = tonumber(args[3])
        if n then
            trial.id = n
            if cfg.autolabel and (trial.desc=='' or trial.desc==nil) then
                trial.desc = TRIAL_NAME_MAP[n] or trial.desc
            end
        end
    elseif args[2]:any('desc') and #args>=3 then
        trial.desc = table.concat(args,' ',3)
    elseif args[2]:any('type') and #args>=3 then
        trial.desc = table.concat(args,' ',3)
    elseif args[2]:any('autolabel') and #args>=3 then
        cfg.autolabel = args[3]:any('on')
        if cfg.autolabel then maybe_autolabel() end
    elseif args[2]:any('loadmap') then
        load_trials_map()
    elseif args[2]:any('mapinfo') then
        local p = path_join(get_addon_dir(),'trials_map.lua')
        local exists = file_exists(p) and 'YES' or 'NO'
        print(chat.header(addon.name):append(chat.message(string.format('Looking for trials_map.lua at: %s (exists: %s)', p, exists))))
    elseif args[2]:any('reset') then
        trial.remaining = -1; trial.last_announced_for = -1
        print(chat.header(addon.name):append(chat.message('Runtime reset.')))
    elseif args[2]:any('debug') and #args>=3 then
        cfg.debug = args[3]:any('on')
        print(chat.header(addon.name):append(chat.message('Debug: ' .. (cfg.debug and 'ON' or 'OFF'))))
    elseif args[2]:any('sim') and #args>=4 then
        local tid = tonumber(args[3]); local rem = tonumber(args[4])
        if tid and rem then
            local fake = string.format('Trial %d: %d objectives remain.', tid, rem)
            handle_incoming_text('simulate', fake)
            print(chat.header(addon.name):append(chat.message('Simulated: ' .. fake)))
        end
    elseif args[2]:any('progress') or args[2]:any('prog') then
        local m = build_progress_message(trial.remaining)
        announce_in_channel(m)
        print(chat.header(addon.name):append(chat.message('Announced current progress to channel.')))
    elseif args[2]:any('aby') then
        local is_aby, zid = in_abyssea()
        if not is_aby then
            print(chat.header(addon.name):append(chat.message('Not in Abyssea.')))
        else
            local secs = query_abyssea_seconds_left()
            if type(secs) == 'number' and secs > 0 then
                print(chat.header(addon.name):append(chat.message(string.format('Abyssea time left: %s (zone: %s).', fmt_mmss(secs), ABYSSEA_ZONES[zid] or tostring(zid)))))
            else
                print(chat.header(addon.name):append(chat.message(string.format('Abyssea time left: unknown (zone: %s).', ABYSSEA_ZONES[zid] or tostring(zid)))))
            end
        end
    else
        print_help()
    end
end)

-- ============= Lifecycle =============
ashita.events.register('load','load_cb_tom', function()
    if cfg.announce_chan~='p' and cfg.announce_chan~='ls' and cfg.announce_chan~='ls2' then
        cfg.announce_chan='p'
    end
    load_trials_map()
    print(chat.header(addon.name):append(chat.message('ToM Tracker loaded! /tom to toggle HUD; /tom help for commands.')))
end)
ashita.events.register('unload','unload_cb_tom', function() end)
