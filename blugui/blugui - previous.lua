addon.name    = 'blugui'
addon.author  = 'Ilogical'
addon.version = '1.0.0'
addon.desc    = 'GUI Companion for blusets (by atom0s, shipped with Ashita).'
addon.link    = ''

require('common')
local imgui = require('imgui')
local chat  = require('chat')

-- Prefer local blu.lua; fallback to the blusets copy.
local blu
do
    local ok, mod = pcall(require, 'blu')
    if ok and mod then
        blu = mod
    else
        local p = string.format('%s\\addons\\blusets\\blu.lua', AshitaCore:GetInstallPath())
        local f, ferr = loadfile(p)
        if not f then error(string.format('Could not load blu module. Tried require("blu") and %s.\nError: %s', p, ferr or 'unknown')) end
        local m = f(); if not m then error('blu.lua did not return a module table.') end
        blu = m
    end
end

--------------------------------------------------------------------------------
-- ImGui helpers
--------------------------------------------------------------------------------
local ImGuiCond_FirstUseEver         = _G.ImGuiCond_FirstUseEver or 0
local ImGuiCond_Always               = _G.ImGuiCond_Always or 0
local ImGuiWindowFlags_NoResize      = _G.ImGuiWindowFlags_NoResize or 0
local ImGuiTreeNodeFlags_DefaultOpen = _G.ImGuiTreeNodeFlags_DefaultOpen or 0
local function v2(x,y) return (imgui and imgui.ImVec2) and imgui.ImVec2(x,y) or {x=x,y=y} end
local function push_hide_sizegrip()
    local idxs = {
        imgui.Col_ResizeGrip or imgui.ImGuiCol_ResizeGrip,
        imgui.Col_ResizeGripHovered or imgui.ImGuiCol_ResizeGripHovered,
        imgui.Col_ResizeGripActive or imgui.ImGuiCol_ResizeGripActive,
    }
    local pushed = 0
    if imgui.PushStyleColor then
        for _,idx in ipairs(idxs) do
            if idx then
                local ok = pcall(function() imgui.PushStyleColor(idx, {0,0,0,0}) end)
                if not ok then pcall(function() imgui.PushStyleColor(idx, 0x00000000) end) end
                pushed = pushed + 1
            end
        end
    end
    return pushed
end
local function pop_hide_sizegrip(n) if imgui.PopStyleColor and n and n>0 then imgui.PopStyleColor(n) end end
local function width_chars(n) local w=7; if imgui.CalcTextSize then local sz=imgui.CalcTextSize('W'); if type(sz)=='table' then w=(sz.x or sz[1] or 7) end end; return (w*n)+24 end
local function width_one_third() local w=180; local ok,avail=pcall(function() return imgui.GetContentRegionAvail() end); if ok and type(avail)=='table' then w=math.max(120, math.floor((avail.x or avail[1] or 360)/3)) end; return w end
local function begin_child_compat(id,w,h,border)
    if pcall(function() return imgui.BeginChild(id, w, h, border) end) then return true end
    local size=(imgui.ImVec2 and imgui.ImVec2(w,h)) or {w,h}
    if pcall(function() return imgui.BeginChild(id, size, border) end) then return true end
    if pcall(function() return imgui.BeginChild(id, size, border, 0) end) then return true end
    return false
end

--------------------------------------------------------------------------------
-- Paths / sets
--------------------------------------------------------------------------------
local function sets_dir() return string.format('%s\\config\\addons\\%s\\', AshitaCore:GetInstallPath(), 'blusets') end
local function ensure_sets_dir() local p=sets_dir(); if not ashita.fs.exists(p) then ashita.fs.create_dir(p) end end
local function sets_dir_files() return ashita.fs.get_dir(sets_dir(), '.*.txt', true) or {} end
local function last_set_path() return sets_dir() .. '__last_set.txt' end
local function write_last_set(name) local f=io.open(last_set_path(),'w+'); if f then f:write(name or ''); f:close() end end
local function read_last_set() local f=io.open(last_set_path(),'r'); if not f then return nil end local s=f:read('*a') or ''; f:close(); s=s:gsub('^%s+',''):gsub('%s+$',''); if s=='' then return nil end return s end
local function addon_dir() return string.format('%s\\addons\\%s\\', AshitaCore:GetInstallPath(), addon.name) end
local function unbridled_lua_path() return addon_dir() .. 'unbridled.lua' end

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------
local MAX_SLOTS_UI, MAX_APPLY_SLOTS = 20, 20
local state = {
    is_open          = true,
    current_set_name = '(unsaved)',
    apply_status     = 'idle',     -- 'idle' | 'ok' | 'error' | 'applying'
    verify_after_s   = 1.25,

    sets_dropdown    = { items = {}, index = 1 },

    learned          = {},
    learned_refresh  = 0,
    learned_ttl_s    = 0.75,

    working          = {},
    working_sel      = 1,
    avail_sel        = 1,

    packet_delay_s   = 1.25,
    save_name_buf    = '',

    list_scroll_h    = 280,
    ui               = { pos_x = 60, pos_y = 120, width = 460 },

    unbridled_set    = {},

    points_cache     = { used = 0, max = 0 },
}

--------------------------------------------------------------------------------
-- BLU helpers (strict classification)
--------------------------------------------------------------------------------
local function is_blu_active()
    local pm = AshitaCore:GetMemoryManager():GetPlayer()
    return pm and ((pm:GetMainJob() == 16) or (pm:GetSubJob() == 16)) or false
end
local function safe_idx(t,k) local ok,v=pcall(function() return t[k] end); if ok then return v end end
local function get_spell_name(sp)
    if not sp then return '' end
    local N = sp.Name; if N == nil then return '' end
    local function pick(x) return (type(x)=='string' and x~='') and x or nil end
    local v = pick(safe_idx(N,1)) or pick(safe_idx(N,0)) or pick(safe_idx(N,'en')) or pick(safe_idx(N,'English')) or pick(safe_idx(N,'english'))
    if v then return v end
    if type(N)=='string' and N~='' then return N end
    return ''
end
local function has_spell_truthy(pm, id)
    local ok, v = pcall(function() return pm:HasSpell(id) end)
    if ok and v ~= nil then
        if type(v) == 'boolean' then return v end
        if type(v) == 'number'  then return v ~= 0 end
    end
    return false
end
local function player_has_spell_any(id)
    local pm = AshitaCore:GetMemoryManager():GetPlayer(); if not pm then return false end
    if has_spell_truthy(pm, id) then return true end
    if id >= 512 and has_spell_truthy(pm, id - 512) then return true end
    return false
end
local function get_field(sp, key) local ok, v = pcall(function() return sp[key] end); if not ok then return nil end; return v end
local function get_number_field(sp, key)
    local v = get_field(sp, key)
    if type(v) == 'number' then return v end
    if type(v) == 'string' then local n = tonumber(v); if n then return n end end
    return nil
end
local function get_string_field(sp, key)
    local v = get_field(sp, key)
    if type(v) == 'string' then return v end
    return nil
end
local function get_setpoints(sp)
    local v = get_number_field(sp,'SetPoints') or get_number_field(sp,'SetPoint') or get_number_field(sp,'Points') or get_number_field(sp,'BluePoints')
    return v or 0
end
local function is_trust_spell(sp)
    local s = get_string_field(sp,'Skill'); if s and s:lower():find('trust') then return true end
    local t = get_string_field(sp,'Type');  if t and t:lower():find('trust') then return true end
    return false
end
local function is_blu_spell_strict(sp)
    if not sp then return false end
    if is_trust_spell(sp) then return false end
    local pts = get_setpoints(sp)
    if pts and pts > 0 then return true end
    local skill_num = get_number_field(sp,'Skill')
    if skill_num and skill_num == 43 then return true end
    local skill_str = get_string_field(sp,'Skill'); if skill_str and skill_str:lower():find('blue') then return true end
    local type_str  = get_string_field(sp,'Type');  if type_str and type_str:lower():find('blue') then return true end
    return false
end

--------------------------------------------------------------------------------
-- Unbridled list
--------------------------------------------------------------------------------
local DEFAULT_UNBRIDLED = {
    'Thunderbolt','Harden Shell','Absolute Terror','Gates of Hades','Tourbillion',
    'Pyric Bulwark','Bilgestorm','Bloodrake','Droning Whirlwind','Carcharian Verve',
    'Blistering Roar','Uproot','Crashing Thunder','Polar Roar','Mighty Guard',
    'Cruel Joke','Cesspool','Tearing Gust',
}
local function load_unbridled()
    local set = {}
    local function add(name)
        if name and name ~= '' then set[tostring(name):lower()] = true end
    end
    for _,n in ipairs(DEFAULT_UNBRIDLED) do add(n) end
    local lp = unbridled_lua_path()
    if ashita.fs.exists(lp) then
        local f, ferr = loadfile(lp)
        if f then
            local ok, list = pcall(f)
            if ok and type(list) == 'table' then
                for _,n in ipairs(list) do add(n) end
            else
                print(chat.header(addon.name):append(chat.warning('unbridled.lua did not return a table; using defaults.')))
            end
        else
            print(chat.header(addon.name):append(chat.warning('Failed to load unbridled.lua: ')):append(chat.message(tostring(ferr or 'unknown'))))
        end
    end
    state.unbridled_set = set
end

--------------------------------------------------------------------------------
-- Learned list refresh - not properly used yet
--------------------------------------------------------------------------------
local function refresh_learned(force)
    local now = os.clock()
    if (not force) and (now - state.learned_refresh < state.learned_ttl_s) then return end

    state.learned = {}
    state.learned_refresh = now

    local rm = AshitaCore:GetResourceManager()
    local pm = AshitaCore:GetMemoryManager():GetPlayer()
    if not rm or not pm then return end
    if not is_blu_active() then return end

    local seen = {}
    for id = 512, 1024 do
        local sp = rm:GetSpellById(id)
        if sp and is_blu_spell_strict(sp) then
            local nm = get_spell_name(sp)
            if nm ~= '' then
                local lower = nm:lower()
                if not state.unbridled_set[lower] then
                    if player_has_spell_any(id) then
                        if not seen[lower] then
                            state.learned[#state.learned+1] = { name = nm, id = id, points = get_setpoints(sp) or 0 }
                            seen[lower] = true
                        end
                    end
                end
            end
        end
    end
    table.sort(state.learned, function(a,b) return (a.name:lower() < b.name:lower()) end)
end

--------------------------------------------------------------------------------
-- Current equipped helpers (reads via blu.lua)
--------------------------------------------------------------------------------
local blu_name_to_id = {}
local function build_blu_name_map()
    blu_name_to_id = {}
    local rm = AshitaCore:GetResourceManager(); if not rm then return end
    for id=512,1024 do
        local sp = rm:GetSpellById(id)
        if sp and is_blu_spell_strict(sp) then
            local nm = get_spell_name(sp)
            if nm ~= '' and not state.unbridled_set[nm:lower()] then
                blu_name_to_id[nm:lower()] = id
            end
        end
    end
end
local function resolve_name_to_id(name)
    if not name or name=='' then return nil end
    local k = name:lower()
    if blu_name_to_id[k] then return blu_name_to_id[k] end
    local sp = AshitaCore:GetResourceManager():GetSpellByName(name, 0)
    return sp and sp.Index or nil
end
local function get_current_spell_names()
    if blu.get_spells_names then
        local ok,n = pcall(blu.get_spells_names)
        if ok and type(n)=='table' then return n end
    end
    local rm = AshitaCore:GetResourceManager()
    local out, slots = {}, (blu.get_spells and blu.get_spells() or {})
    for i=1,MAX_APPLY_SLOTS do
        local v = (slots and slots[i]) or 0
        if v and v > 0 then
            local sp = rm:GetSpellById(v + 512)
            out[i] = get_spell_name(sp)
        else
            out[i] = ''
        end
    end
    return out
end
local function get_current_spells()
    local names, arr = get_current_spell_names(), {}
    for i=1,MAX_APPLY_SLOTS do
        local n = names[i] or ''
        arr[i] = { name = n, id = resolve_name_to_id(n) }
    end
    return arr
end
local function seed_from_current_equipped()
    local cur = get_current_spells()
    state.working = {}
    for i=1,MAX_SLOTS_UI do
        local e = cur[i]; state.working[i] = { name = (e and e.name) or '', id = (e and e.id) or nil }
    end
end

-- Fallback: compute USED points directly from currently equipped spells.
local function compute_used_points_from_equipped()
    local rm = AshitaCore:GetResourceManager(); if not rm then return 0 end
    local used = 0
    local names = get_current_spell_names()
    for i=1,MAX_APPLY_SLOTS do
        local n = names[i]
        if n and n ~= '' then
            local id = resolve_name_to_id(n)
            if id then
                local sp = rm:GetSpellById(id)
                if sp then used = used + (get_setpoints(sp) or 0) end
            end
        end
    end
    return used
end

--------------------------------------------------------------------------------
-- Sets I/O
--------------------------------------------------------------------------------
local function rescan_sets()
    ensure_sets_dir()
    local files = sets_dir_files()
    table.sort(files, function(a,b) return a:lower() < b:lower() end)
    local items = {}
    for _,f in ipairs(files) do
        local name = (f:gsub('%.txt$',''))
        if name:sub(1,2) ~= '__' then items[#items+1] = name end
    end
    state.sets_dropdown.items = items
end
local function read_set(setname)
    local p = sets_dir() .. setname .. '.txt'
    if not ashita.fs.exists(p) then return nil end
    local f = io.open(p,'r'); if not f then return nil end
    local lines = {}; for line in f:lines() do lines[#lines+1] = line end; f:close()
    local work = {}
    for i=1,MAX_SLOTS_UI do local n = lines[i] or ''; work[i] = { name = n, id = resolve_name_to_id(n) } end
    return work
end
local function write_set(setname)
    local p = sets_dir() .. setname .. '.txt'
    local f = io.open(p,'w+'); if not f then return false end
    for i=1,MAX_SLOTS_UI do local e=state.working[i]; local n=(e and e.name) or ''; f:write(n .. (i<MAX_SLOTS_UI and '\n' or '')) end
    f:close(); rescan_sets(); local _=pcall(write_last_set, setname); return true
end
local function sync_sets_dropdown_to_current()
    local cur = state.current_set_name or ''
    local items = state.sets_dropdown.items or {}
    local idx = 1
    if cur ~= '' then
        for i,name in ipairs(items) do
            if name == cur then idx = i; break end
        end
    end
    state.sets_dropdown.index = (#items > 0 and math.min(idx, #items)) or 1
end

--------------------------------------------------------------------------------
-- Saved-set matching / last-used
--------------------------------------------------------------------------------
local function arrays_equal_20(a, b)
    local function nm(x) if type(x)=='table' then return tostring(x.name or '') elseif type(x)=='string' then return x else return '' end end
    for i=1,MAX_APPLY_SLOTS do if nm(a[i]) ~= nm(b[i]) then return false end end
    return true
end
local function try_select_current_saved()
    local current = get_current_spells()
    local files = sets_dir_files()
    for _,f in ipairs(files) do
        local name = (f:gsub('%.txt$',''))
        if name:sub(1,2) ~= '__' then
            local saved = read_set(name)
            if saved and arrays_equal_20(current, saved) then
                state.current_set_name = name; state.working = saved; return true
            end
        end
    end
    return false
end

--------------------------------------------------------------------------------
-- Points + apply
--------------------------------------------------------------------------------
local function try_blu_numbers(list)
    for _,fn in ipairs(list) do
        local f = blu[fn]
        if type(f) == 'function' then
            local ok, v = pcall(f)
            if ok and type(v) == 'number' and v >= 0 then return v end
        end
    end
    return nil
end
local function get_equipped_points()
    local used = try_blu_numbers({'get_spent_points','get_points_used','get_used_points','get_spent'}) or 0
    local maxp = try_blu_numbers({'get_max_points','get_points_max','get_max_set_points','get_cap_points'}) or 0
    if used <= 0 then used = compute_used_points_from_equipped() end
    if maxp <= 0 or used > maxp then
        local pm = AshitaCore:GetMemoryManager():GetPlayer()
        local lvl = pm and pm:GetMainJobLevel() or 0
        if pm and pm:GetMainJob() == 16 and lvl >= 99 then
            maxp = 80 -- typical BLU cap
        elseif state.points_cache.max > 0 then
            maxp = state.points_cache.max
        else
            maxp = math.max(used, 0)
        end
    end
    state.points_cache.used = used
    if maxp > 0 then state.points_cache.max = maxp end
    return used, maxp
end
local function verify_current_matches_working()
    local cur = get_current_spell_names()
    for i=1,MAX_APPLY_SLOTS do
        local want = state.working[i] and state.working[i].name or ''
        local got  = cur[i] or ''
        if want ~= got then return false end
    end
    return true
end
local function apply_working_set()
    if blu then
        if rawget(blu,'mode') ~= nil then blu.mode = 'safe' end
        if rawget(blu,'delay')~= nil then blu.delay = state.packet_delay_s end
    end
    ashita.tasks.once(0.1, function()
        state.apply_status = 'applying'
        if blu.reset_all_spells then blu.reset_all_spells() end
        local d = math.max(1.0, math.min(5.0, tonumber(state.packet_delay_s) or 1.25))
        coroutine.sleep(d)
        for i=1,MAX_APPLY_SLOTS do
            local e=state.working[i]; local name=(e and e.name) or ''
            if blu.set_spell_by_name then blu.set_spell_by_name(i, name) end
            coroutine.sleep(d)
        end
        coroutine.sleep(state.verify_after_s)
        local ok = verify_current_matches_working()
        state.apply_status = (ok and 'ok' or 'error')
        if ok then
            print(chat.header(addon.name):append(chat.success('Applied set successfully.')))
        else
            print(chat.header(addon.name):append(chat.error('Error, not all spells set, try increasing the packet delay and that you in fact, know the spell.')))
        end
        refresh_learned(true)
        try_select_current_saved()
        sync_sets_dropdown_to_current()
    end)
end
local function is_already_in_working(name)
    for i=1,MAX_SLOTS_UI do local e=state.working[i]; if e and e.name==name then return true end end
    return false
end

--------------------------------------------------------------------------------
-- UI
--------------------------------------------------------------------------------
local CLR_OK, CLR_ERR, CLR_APPLY, CLR_IDLE, CLR_LABEL =
    {0.20,0.80,0.20,1}, {0.85,0.25,0.25,1}, {0.95,0.85,0.35,1}, {0.60,0.60,0.60,1}, {0.90,0.90,0.90,1}
local function TextColored(c, s)
    if pcall(function() imgui.TextColored(c, s) end) then return end
    local function col32(r,g,b,a) local R=math.floor((r or 0)*255); local G=math.floor((g or 0)*255); local B=math.floor((b or 0)*255); local A=math.floor((a or 1)*255); return A*256^3 + R*256^2 + G*256 + B end
    if pcall(function() imgui.TextColored(col32(c[1],c[2],c[3],c[4] or 1), s) end) then return end
    imgui.Text(s or '')
end
local function draw_header_with_status()
    TextColored(CLR_LABEL, string.format('Current Set - %s  ', state.current_set_name)); imgui.SameLine()
    if state.apply_status == 'ok' then TextColored(CLR_OK,'OK')
    elseif state.apply_status == 'error' then TextColored(CLR_ERR,'ERROR'); imgui.SameLine(); TextColored(CLR_LABEL,'(try again)'); imgui.SameLine()
        if imgui.Button('Retry##blugui_retry', v2(90, 0)) then apply_working_set() end
    elseif state.apply_status == 'applying' then TextColored(CLR_APPLY,'Applying...')
    else TextColored(CLR_IDLE,'Not Set') end
    imgui.SameLine()
    local used,maxp = get_equipped_points(); imgui.Spacing(); imgui.SameLine()
    local okpoints = (maxp or 0) > 0 and (used <= maxp)
    TextColored(okpoints and CLR_OK or CLR_ERR, string.format('%d/%d', used, maxp))
end
local function truncate(s,n) s=tostring(s or ''); if #s<=n then return s end return s:sub(1, math.max(0,n-1))..'…' end
local function draw_sets_dropdown()
    imgui.PushItemWidth(width_chars(30))
    local preview = '(none)'
    if #state.sets_dropdown.items > 0 then
        local full = state.sets_dropdown.items[state.sets_dropdown.index] or ''
        preview = truncate(full, 30)
    end
    if imgui.BeginCombo('Saved Sets##blugui_sets', preview) then
        for i,name in ipairs(state.sets_dropdown.items) do
            local selected = (i == state.sets_dropdown.index)
            if imgui.Selectable(name, selected) then state.sets_dropdown.index = i end
            if selected and imgui.SetItemDefaultFocus then imgui.SetItemDefaultFocus() end
        end
        imgui.EndCombo()
    end
    imgui.PopItemWidth()
    imgui.SameLine()
    if imgui.Button('Load##blugui_load_set', v2(90, 0)) then
        local name = state.sets_dropdown.items[state.sets_dropdown.index]
        local work = read_set(name)
        if work and #work>0 then
            state.working = work; state.current_set_name = name; state.apply_status='idle'; pcall(write_last_set, name)
            sync_sets_dropdown_to_current()
        else
            print(chat.header(addon.name):append(chat.error('Failed to read set: ')):append(chat.warning(name or '(nil)')))
        end
    end
end
local function draw_available_blu_section()
    if imgui.CollapsingHeader('Available BLU Magic##blugui_av', ImGuiTreeNodeFlags_DefaultOpen) then
        if begin_child_compat('##blugui_av_child', 0, state.list_scroll_h, true) then
            for idx,entry in ipairs(state.learned) do
                local nm = entry.name or ''
                local sel = (state.avail_sel == idx)
                if imgui.Selectable(string.format('%s##blugui_av%03d', nm, idx), sel) then state.avail_sel = idx end
            end
            imgui.EndChild()
        end
        if imgui.Button('Add Spell##blugui_add', v2(110, 0)) then
            local rm = AshitaCore:GetResourceManager()
            local idx = state.avail_sel; local entry = state.learned[idx]
            if entry then
                local id = entry.id or 0
                local sp = rm and rm:GetSpellById(id) or nil
                if sp and is_blu_spell_strict(sp) then
                    if not is_already_in_working(entry.name) then
                        local placed=false
                        for i=1,MAX_SLOTS_UI do
                            local e=state.working[i]
                            if (not e) or (e.name=='' or e.name==nil) then
                                state.working[i] = { name=entry.name, id=entry.id }; state.working_sel=i; placed=true; break
                            end
                        end
                        if not placed then print(chat.header(addon.name):append(chat.warning('All slots are filled; remove one first.'))) end
                    else
                        print(chat.header(addon.name):append(chat.warning('That spell is already in your working set.')))
                    end
                end
            end
        end
        imgui.SameLine()
        if imgui.Button('Use Equipped##blugui_seed', v2(110, 0)) then
            seed_from_current_equipped(); state.apply_status='idle'; state.current_set_name='(unsaved)'
            sync_sets_dropdown_to_current()
        end
        imgui.SameLine()
        if imgui.Button('Rescan##blugui_rescan', v2(90, 0)) then refresh_learned(true) end
    end
end
local function draw_working_section()
    if imgui.CollapsingHeader('Working Set##blugui_work', ImGuiTreeNodeFlags_DefaultOpen) then
        if begin_child_compat('##blugui_work_child', 0, state.list_scroll_h, true) then
            for i=1,MAX_SLOTS_UI do
                local e = state.working[i]; local nm = (e and e.name) or ''
                local label = (nm ~= '' and string.format('%02d: %s##blugui_work%02d', i, nm, i)
                                       or string.format('%02d: (empty)##blugui_work%02d', i, i))
                local sel = (state.working_sel == i)
                if imgui.Selectable(label, sel) then state.working_sel = i end
            end
            imgui.EndChild()
        end

        local wBtn = 110

        -- Row 1: Remove
        if imgui.Button('Remove Spell##blugui_remove', v2(wBtn, 0)) then
            local i = state.working_sel or 1
            if i>=1 and i<=MAX_SLOTS_UI then state.working[i] = { name='', id=nil } end
        end

        -- Row 2: Apply + slider
        imgui.NewLine()
        if imgui.Button('Apply Set##blugui_apply', v2(wBtn, 0)) then apply_working_set() end
        imgui.SameLine()
        imgui.PushItemWidth(width_one_third())
        local r = { tonumber(state.packet_delay_s) or 1.25 }
        if imgui.SliderFloat('##blugui_delay', r, 1.00, 5.00, '%.2f') then
            state.packet_delay_s = math.max(1.00, math.min(5.00, math.floor(r[1]*100 + 0.5)/100))
        end
        imgui.PopItemWidth()
        imgui.SameLine()
        imgui.Text('Packet Delay (s)')

        -- Row 3: Save + input
        imgui.Spacing()
        if imgui.Button('Save Set##blugui_save', v2(wBtn, 0)) then
            local name = (state.save_name_buf or ''):gsub('%.txt$','')
            name = name:gsub('^%s+',''):gsub('%s+$','')
            if name=='' then
                print(chat.header(addon.name):append(chat.error('Please enter a set name to save.')))
            else
                if write_set(name) then
                    state.current_set_name = name
                    print(chat.header(addon.name):append(chat.success('Saved set: ')):append(chat.message(name)))
                    sync_sets_dropdown_to_current()
                else
                    print(chat.header(addon.name):append(chat.error('Failed to save set: ')):append(chat.warning(name)))
                end
            end
        end
        imgui.SameLine()
        do
            local ch = 7
            local ok, sz = pcall(function() return imgui.CalcTextSize and imgui.CalcTextSize(' ') end)
            if ok and type(sz)=='table' and (sz.x or sz[1]) then ch = math.floor((sz.x or sz[1]) + 0.5) end
            if imgui.Dummy then imgui.Dummy(v2(ch, 0)) end
        end
        imgui.SameLine()
        imgui.PushItemWidth(width_one_third())
        local s = { state.save_name_buf or '' }
        if imgui.InputText('##blugui_savename', s, 64) then state.save_name_buf = tostring(s[1] or '') end
        imgui.PopItemWidth()
    end
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------
ashita.events.register('load', 'blugui_load', function()
    ensure_sets_dir()
    load_unbridled()
    rescan_sets()
    build_blu_name_map()
    refresh_learned(true)

    seed_from_current_equipped()
    if not try_select_current_saved() then
        local last = read_last_set()
        if last and ashita.fs.exists(sets_dir() .. last .. '.txt') then
            local w = read_set(last); if w and #w>0 then state.working = w; state.current_set_name = last end
        else
            state.current_set_name = '(unsaved)'
        end
    end
    sync_sets_dropdown_to_current()
end)

ashita.events.register('packet_in', 'blugui_in', function(e)
    refresh_learned(false)
end)

ashita.events.register('d3d_present', 'blugui_present', function()
    if not state.is_open then return end
    imgui.SetNextWindowSize(v2(state.ui.width, 0), ImGuiCond_Always)
    imgui.SetNextWindowPos(v2(state.ui.pos_x, state.ui.pos_y), ImGuiCond_FirstUseEver)
    local pushed = push_hide_sizegrip()

    local open = { true }
    if imgui.Begin('BLU Spells##blugui_root', open, ImGuiWindowFlags_NoResize) then
        local pos = imgui.GetWindowPos()
        if type(pos)=='table' then state.ui.pos_x = pos.x or state.ui.pos_x; state.ui.pos_y = pos.y or state.ui.pos_y end

        TextColored({0.90,0.90,0.90,1}, string.format('Current Set - %s  ', state.current_set_name)); imgui.SameLine()
        if state.apply_status == 'ok' then TextColored({0.20,0.80,0.20,1},'OK')
        elseif state.apply_status == 'error' then TextColored({0.85,0.25,0.25,1},'ERROR'); imgui.SameLine(); TextColored({0.90,0.90,0.90,1},'(try again)'); imgui.SameLine()
            if imgui.Button('Retry##blugui_retry', v2(90, 0)) then apply_working_set() end
        elseif state.apply_status == 'applying' then TextColored({0.95,0.85,0.35,1},'Applying...')
        else TextColored({0.60,0.60,0.60,1},'Not Set') end
        imgui.SameLine()
        local used,maxp = get_equipped_points(); imgui.Spacing(); imgui.SameLine()
        local okpoints = (maxp or 0) > 0 and (used <= maxp)
        TextColored(okpoints and {0.20,0.80,0.20,1} or {0.85,0.25,0.25,1}, string.format('%d/%d', used, maxp))
        imgui.Separator()

        draw_sets_dropdown();      imgui.Separator()
        draw_available_blu_section(); imgui.Separator()
        draw_working_section()
    end
    imgui.End()
    pop_hide_sizegrip(pushed)

    if (os.clock() - state.learned_refresh) > state.learned_ttl_s then
        refresh_learned(false)
    end
end)

ashita.events.register('command', 'blugui_cmd', function(e)
    local args = e.command:args()
    if #args > 0 and (args[1] == '/blugui') then
        e.blocked = true
        local sub = args[2] or 'toggle'
        if sub == 'show' or sub == 'open' then state.is_open = true
        elseif sub == 'hide' or sub == 'close' then state.is_open = false
        else state.is_open = not state.is_open end
    end
end)
