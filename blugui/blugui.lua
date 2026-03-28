addon.name    = 'blugui'
addon.author  = 'ilogical'
addon.version = '1.2.3'
addon.desc    = 'GUI Companion for blusets (by atom0s, shipped with Ashita).'
addon.link    = ''

require('common')
local imgui = require('imgui')
local chat  = require('chat')

-- Texture loader (borrowed from Points addon / atom0s pattern).
local ffi       = require('ffi')
local d3d       = require('d3d8')
local C         = ffi.C
local d3d8dev   = d3d.get_device()

ffi.cdef[[
    // Exported from Addons.dll
    HRESULT __stdcall D3DXCreateTextureFromFileA(IDirect3DDevice8* pDevice, const char* pSrcFile, IDirect3DTexture8** ppTexture);
]]

local texture_cache = T{}   -- [filename] = IDirect3DTexture8*
local missing_cache = T{}   -- [filename] = true  (avoid spamming load attempts)

local function normalize_icon_fallback(file)
    if type(file) ~= 'string' then return file end
    if file:lower():sub(-4) == '.gif' then
        -- bgwiki-style: "Fire-BLU-Icon.gif" -> "Fire-Icon.png"
        local alt = file:gsub('%-BLU%-Icon%.gif$', '-Icon.png')
        if alt ~= file then return alt end
    end
    return file
end

local function load_texture_for_file(file)
    if not file or file == '' then return nil end
    if texture_cache[file] ~= nil then return texture_cache[file] end
    if missing_cache[file] then return nil end

    local texture_ptr = ffi.new('IDirect3DTexture8*[1]')
    local full = string.format('%s/assets/%s', addon.path, file)
    local res = C.D3DXCreateTextureFromFileA(d3d8dev, full, texture_ptr)

    if res ~= C.S_OK then
        -- Try fallback name (gif -> png mapping)
        local alt = normalize_icon_fallback(file)
        if alt ~= file then
            full = string.format('%s/assets/%s', addon.path, alt)
            res = C.D3DXCreateTextureFromFileA(d3d8dev, full, texture_ptr)
            if res == C.S_OK then
                local tex = ffi.new('IDirect3DTexture8*', texture_ptr[0])
                d3d.gc_safe_release(tex)
                texture_cache[file] = tex       -- cache under original requested name
                texture_cache[alt]  = tex       -- and the alt name
                return tex
            end
        end

        missing_cache[file] = true
        return nil
    end

    local tex = ffi.new('IDirect3DTexture8*', texture_ptr[0])
    d3d.gc_safe_release(tex)
    texture_cache[file] = tex
    return tex
end

local function draw_icon_inline(file, size)
    local tex = load_texture_for_file(file)
    if not tex then return false end
    imgui.Image(tonumber(ffi.cast('uint32_t', tex)), { size, size })
    return true
end

-- Optional Blue Magic point-cost lookup table.
-- If blu_points.lua is present beside this addon, it will be used to display '[X]' costs in the available list.
local blu_points = {}
do
    local ok, mod = pcall(require, 'blu_points')
    if ok and type(mod) == 'table' then
        blu_points = mod
    end
end

local function fmt_points(name)
    if type(name) ~= 'string' then
        return '?'
    end
    local p = blu_points[name]
    if p == nil then
        -- Try trimmed variant.
        local t = name:gsub('^%s+', ''):gsub('%s+$', '')
        p = blu_points[t]
    end
    if p == nil then
        return '?'
    end
    return tostring(p)
end


local function get_spell_points_by_name(name)
    if type(name) ~= 'string' then return nil end
    local p = blu_points[name]
    if p == nil then
        local t = name:gsub('^%s+', ''):gsub('%s+$', '')
        p = blu_points[t]
    end
    if type(p) == 'string' then p = tonumber(p) end
    if type(p) == 'number' then return p end
    return nil
end

-- Optional spell metadata (element/type/properties) derived from resources/spells.lua when present.
-- This lets us show hover details without scraping websites.
local spell_meta = {}
local function _load_spell_meta()
    if next(spell_meta) ~= nil then return end
    local ok, sp = pcall(require, 'spells')
    if not ok or type(sp) ~= 'table' then return end

    for _, v in pairs(sp) do
        if type(v) == 'table' and type(v.en) == 'string' then
            -- Only index BLU spells (type field tends to be "BlueMagic" in resources/spells.lua)
            if v.type == 'BlueMagic' then
                spell_meta[v.en] = {
                    element = v.element,
                    skill   = v.skill,
                }
            end
        end
    end
end

local function get_spell_element_by_name(name)
    if type(name) ~= 'string' then return nil end
    _load_spell_meta()
    local e = spell_meta[name]
    if e == nil then
        local t = name:gsub('^%s+', ''):gsub('%s+$', '')
        e = spell_meta[t]
    end
    if type(e) == 'table' then
        return e.element
    end
    return nil
end

local function element_name(e)
    local names = {
        [0] = 'Fire',
        [1] = 'Ice',
        [2] = 'Wind',
        [3] = 'Earth',
        [4] = 'Lightning',
        [5] = 'Water',
        [6] = 'Light',
        [7] = 'Dark',
    }
    if e == 15 then return 'None' end
    return names[e] or tostring(e or '?')

end

-- ============================================================
-- BG Wiki icon metadata (generated lua table)
-- ============================================================
local spell_icons = {}
do
    local ok, t = pcall(require, 'blu_spell_icons')
    if ok and type(t) == 'table' then
        spell_icons = t
    end
end


-- local element_icon_by_name = {
--     Fire      = 'Fire-Icon.png',
--     Ice       = 'Ice-Icon.png',
--     Wind      = 'Wind-Icon.png',
--     Earth     = 'Earth-Icon.png',
--     Lightning = 'Lightning-Icon.png',
--     Water     = 'Water-Icon.png',
--     Light     = 'Light-Icon.png',
--     Dark      = 'Dark-Icon.png',
-- }

local function pretty_icon_label(file)
    if file == nil then return nil end
    -- Strip any leading path (handles both Windows '\\' and Unix '/').
    -- Note: backslashes must be escaped in Lua strings.
    local name = file:gsub('^.*[\\/]', ''):gsub('%.%w+$', '')
    name = name:gsub('_SC_Icon$', ''):gsub('_SC_Icon', '')
    name = name:gsub('_', ' ')
    return name
end

-- Type labels are only shown for physical types (so we don't print "Fire/Light/Dark" etc.)
local function pretty_type_label(file)
    if file == nil then return nil end
    local base = pretty_icon_label(file)
    if base == nil or base == '' then return nil end

    -- Normalize a few known filenames.
    if base:lower() == 'h2h' then
        base = 'Hand to Hand'
    elseif base:lower() == 'piercingv2' then
        base = 'Piercing'
    else
        -- Title-case common physical types; leave others alone.
        local map = {
            slashing = 'Slashing',
            blunt    = 'Blunt',
            piercing = 'Piercing',
            ranged   = 'Ranged',
        }
        local k = base:lower()
        if map[k] then base = map[k] end
    end

    local physical = {
        ['Slashing'] = true,
        ['Blunt'] = true,
        ['Piercing'] = true,
        ['Ranged'] = true,
        ['Hand to Hand'] = true,
    }
    if not physical[base] then
        return nil
    end
    return base
end

local function get_spell_type_by_name(name)
    if name == nil then return nil, nil end
    local e = spell_icons[name]
    local file = e and e.typeFile or nil
    return pretty_type_label(file), file
end

local function get_spell_props_and_desc_by_name(name)
    if name == nil then return nil, nil, nil end
    local e = spell_icons[name]
    if type(e) ~= 'table' then return nil, nil, nil end

    -- Preferred: explicit description field.
    local desc = (type(e.desc) == 'string') and e.desc or nil

    local files = e.propFiles
    if type(files) ~= 'table' or #files == 0 then
        return nil, nil, desc
    end

    -- We treat items that resolve to real textures as icons/properties.
    -- Anything that does NOT resolve to a texture is treated as a text description fragment.
    local prop_labels = {}
    local prop_icon_files = {}
    local desc_bits = {}

    for i = 1, #files do
        local f = files[i]
        if type(f) == 'string' and f ~= '' then
            local label = pretty_icon_label(f) or f
            local tex_ok = (load_texture_for_file(f) ~= nil)

            if tex_ok then
                prop_labels[#prop_labels + 1] = label
                prop_icon_files[#prop_icon_files + 1] = f
            else
                desc_bits[#desc_bits + 1] = label
            end
        end
    end

    -- If no explicit desc was provided, fall back to any non-icon text bits found in propFiles.
    if (desc == nil or desc == '') and #desc_bits > 0 then
        desc = table.concat(desc_bits, ', ')
    end

    local props = nil
    if #prop_labels > 0 then
        props = table.concat(prop_labels, ', ')
    end

    return props, prop_icon_files, desc
end


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
local function enum(name, fallback)
    -- Try imgui namespace first, then globals; fall back to a known numeric if provided.
    local v = nil
    if imgui then
        v = rawget(imgui, name) or rawget(imgui, 'ImGui' .. name)
    end
    if v == nil then v = rawget(_G, name) end
    if v == nil then v = rawget(_G, 'ImGui' .. name) end
    if v == nil then v = fallback end
    return v
end

-- NOTE: Do NOT default ImGuiCond_* to 0.
-- In Dear ImGui, 0 means "always", which will force window sizes every frame and break user resizing.
local ImGuiCond_Once                 = enum('Cond_Once', 2) or enum('ImGuiCond_Once', 2) or 2
local ImGuiCond_FirstUseEver         = enum('Cond_FirstUseEver', 16) or enum('ImGuiCond_FirstUseEver', 16) or 16
-- local ImGuiCond_Appearing            = enum('Cond_Appearing', 8) or enum('ImGuiCond_Appearing', 8) or 8

local ImGuiWindowFlags_AlwaysAutoResize = enum('WindowFlags_AlwaysAutoResize', 64) or enum('ImGuiWindowFlags_AlwaysAutoResize', 64) or 64
local ImGuiTreeNodeFlags_DefaultOpen = enum('TreeNodeFlags_DefaultOpen', 32) or enum('ImGuiTreeNodeFlags_DefaultOpen', 32) or 32

local function v2(x,y) return (imgui and imgui.ImVec2) and imgui.ImVec2(x,y) or {x=x,y=y} end
local function width_chars(n) local w=7; if imgui.CalcTextSize then local sz=imgui.CalcTextSize('W'); if type(sz)=='table' then w=(sz.x or sz[1] or 7) end end; return (w*n)+24 end
-- local function width_one_third() local w=180; local ok,avail=pcall(function() return imgui.GetContentRegionAvail() end); if ok and type(avail)=='table' then w=math.max(120, math.floor((avail.x or avail[1] or 360)/3)) end; return w end
local function width_one_fifth()
    local w = 120
    local ok, avail = pcall(function() return imgui.GetContentRegionAvail() end)
    if ok and type(avail) == 'table' then
        w = math.max(90, math.floor((avail.x or avail[1] or 360) / 5))
    end
    return w
end
local function begin_child_compat(id, w, h, border)
    
    local size = (imgui.ImVec2 and imgui.ImVec2(w, h)) or { w, h }

    local child_flags = (border and ImGuiChildFlags_Borders) or 0
    if child_flags == 0 and border then
        child_flags = (imgui.ImGuiChildFlags_Borders or imgui.ChildFlags_Borders or 0)
    end

    local function try_call(fn)
        local ok, ret = pcall(fn)
        if not ok then
            return false, false
        end
        -- Called successfully; ImGui expects EndChild regardless of ret.
        local visible = (ret ~= false)
        return true, visible
    end

    -- Prefer the new signatures first (child_flags + optional window_flags).
    local called, visible = try_call(function() return imgui.BeginChild(id, size, child_flags, 0) end)
    if called then return called, visible end
    called, visible = try_call(function() return imgui.BeginChild(id, size, child_flags) end)
    if called then return called, visible end
    called, visible = try_call(function() return imgui.BeginChild(id, w, h, child_flags, 0) end)
    if called then return called, visible end
    called, visible = try_call(function() return imgui.BeginChild(id, w, h, child_flags) end)
    if called then return called, visible end

    -- Fall back to older overloads (pre-4.30).
    called, visible = try_call(function() return imgui.BeginChild(id, w, h, border) end)
    if called then return called, visible end
    called, visible = try_call(function() return imgui.BeginChild(id, size, border) end)
    if called then return called, visible end
    called, visible = try_call(function() return imgui.BeginChild(id, size, border, 0) end)
    if called then return called, visible end

    return false, false
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

    list_scroll_h    = 600,
    ui               = { pos_x = 60, pos_y = 120, width = 460, height = 780 },

    unbridled_set    = {},

    points_cache     = { used = 0, max = 0 },

    -- Live points override sourced from outgoing BLU set-spell packets (0x0102).
    -- This updates instantly when you set/unset spells via the in-game menu.
    points_live      = { used = nil, max = nil, updated_at = 0, ttl_s = 2.0 },

    -- Points override seeded after Apply Set succeeds (works even when BLU buffer is stale).
    points_override = { active = false, used = 0, max = 0 },

    hover_spell      = nil, -- { name=string, id=number|nil, from='available'|'working' }
}

-- Returns: totalKnownPoints (number), unknownCount (number)
local function calc_working_set_points()
    local total = 0
    local unknown = 0

    -- state.working is a fixed-size list of MAX_SLOTS_UI entries.
    for i = 1, MAX_SLOTS_UI do
        local e = state.working[i]
        local nm = (e and e.name) or ''
        if nm ~= '' then
            local p = get_spell_points_by_name(nm)
            if type(p) == 'number' then
                total = total + p
            else
                unknown = unknown + 1
            end
        end
    end

    return total, unknown
end

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
    -- For BLU spells (512-1024 range), only check the exact ID
    return has_spell_truthy(pm, id)
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
    -- 1) Try blu.get_spells_names(), but only trust it if it has at least one real name.
    if blu.get_spells_names then
        local ok, names = pcall(blu.get_spells_names)
        if ok and type(names) == 'table' then
            local has_real = false
            for i = 1, MAX_APPLY_SLOTS do
                local v = names[i]
                if type(v) == 'string' and v ~= '' then
                    has_real = true
                    break
                end
            end
            if has_real then
                return names
            end
            -- otherwise fall through to numeric slots
        end
    end

    -- 2) Fallback: use the numeric slots from blu.get_spells().
    local rm = AshitaCore:GetResourceManager()
    local out  = {}
    local slots = (blu.get_spells and blu.get_spells() or {})

    -- Detect 0-based vs 1-based layout for safety.
    local zero_based = (slots[0] ~= nil) and (slots[1] == nil)

    for i = 1, MAX_APPLY_SLOTS do
        local key = zero_based and (i - 1) or i
        local v   = slots[key] or 0
        if v and v > 0 and rm then
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

-- Compute USED points from a given working set list (names).
local function compute_used_points_from_working(list)
    local rm = AshitaCore:GetResourceManager(); if not rm then return 0 end
    local used = 0
    list = list or state.working
    for i=1,MAX_APPLY_SLOTS do
        local e = list[i]
        local n = (e and e.name) or ''
        if n ~= '' then
            local id = resolve_name_to_id(n)
            if id then
                local sp = rm:GetSpellById(id)
                if sp then used = used + (get_setpoints(sp) or 0) end
            end
        end
    end
    return used
end
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
-- Prefer an override seeded after Apply Set succeeds.
    if state.points_override and state.points_override.active then
        local used_o = tonumber(state.points_override.used) or 0
        local max_o  = tonumber(state.points_override.max) or 0
        if max_o <= 0 then
            max_o = try_blu_numbers({'get_max_points','get_points_max','get_max_set_points','get_cap_points'}) or 0
            if max_o <= 0 then
                local pm = AshitaCore:GetMemoryManager():GetPlayer()
                local lvl = pm and pm:GetMainJobLevel() or 0
                if pm and pm:GetMainJob() == 16 and lvl >= 99 then max_o = 80 end
            end
            if max_o > 0 then state.points_override.max = max_o end
        end
        return used_o, (max_o > 0 and max_o or math.max(used_o, 0))
    end

-- Prefer the live override if it was updated very recently (eg. while using the in-game BLU Set Spells menu).
do
    local now = os.clock()
    local ttl = (state.points_live and state.points_live.ttl_s) or 0
    if ttl > 0 and state.points_live and state.points_live.used ~= nil then
        if (now - (state.points_live.updated_at or 0)) <= ttl then
            local used_live = tonumber(state.points_live.used) or 0
            local max_live  = tonumber(state.points_live.max or state.points_cache.max or 0) or 0
            if max_live > 0 then
                state.points_cache.used = used_live
                state.points_cache.max  = max_live
                return used_live, max_live
            end
            -- If max is unknown, still return used and fall back to cached max handling below.
            state.points_cache.used = used_live
        end
    end
end

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


-- Live points reader (from outgoing 0x0102 packets)
local function parse_blu_equipex_packet_points(data)
    -- Expecting the 0x0102 packet layout:
    -- 0x00: IdSize(2) Sync(2) SpellId(1) u8(1) u16(2) => 8 bytes
    -- 0x08: JobId(1) IsSubJob(1) u16(2) => 4 bytes (total 12)
    -- 0x0C: Spells[20] => 20 bytes (values are spellId-512; 0 means empty)
    if type(data) ~= 'string' then return nil end
    if #data < 32 then return nil end -- 12 + 20 minimum
    local rm = AshitaCore:GetResourceManager()
    if not rm then return nil end

    local used = 0
    -- Lua strings are 1-based; spells start at byte 13 (offset 12).
    for i = 1, 20 do
        local v = string.byte(data, 12 + i) or 0
        if v > 0 then
            local sp = rm:GetSpellById(v + 512)
            if sp then used = used + (get_setpoints(sp) or 0) end
        end
    end
    return used
end

local function update_live_points_from_packet(data)
    local used = parse_blu_equipex_packet_points(data)
    if used == nil then return end
    state.points_live.used = used
    state.points_live.updated_at = os.clock()

    -- Max points generally doesn't change often; try to refresh it here too.
    local maxp = try_blu_numbers({'get_max_points','get_points_max','get_max_set_points','get_cap_points'})
    if type(maxp) == 'number' and maxp > 0 then
        state.points_live.max = maxp
        state.points_cache.max = maxp
    end
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
        local target_total = (select(1, calc_working_set_points())) or 0
        local applied_total = 0
        state.points_override.active = true
        state.points_override.used = 0
        state.points_override.max  = math.max(target_total, 0)
        if blu.reset_all_spells then blu.reset_all_spells() end
        local d = math.max(1.0, math.min(5.0, tonumber(state.packet_delay_s) or 1.25))
        coroutine.sleep(d)
        for i=1,MAX_APPLY_SLOTS do
            local e=state.working[i]; local name=(e and e.name) or ''
            if blu.set_spell_by_name then blu.set_spell_by_name(i, name) end
            local pts = get_spell_points_by_name(name) or 0
            if pts > 0 then
                applied_total = applied_total + pts
                state.points_override.used = applied_total
            end
            coroutine.sleep(d)
        end
        coroutine.sleep(state.verify_after_s)
        local ok = verify_current_matches_working()
        state.apply_status = (ok and 'ok' or 'error')
        if ok then
            -- Keep the header pinned to the chosen set total immediately after apply.
            local used_now = applied_total
            state.points_override.active = true
            state.points_override.used = used_now
            state.points_override.max  = math.max(target_total, used_now, 0)
            print(chat.header(addon.name):append(chat.success('Applied set successfully.')))
        else
            state.points_override.active = true
            state.points_override.used = applied_total
            state.points_override.max  = math.max(target_total, applied_total, 0)
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
-- local CLR_OK, CLR_ERR, CLR_APPLY, CLR_IDLE, CLR_LABEL =
--     {0.20,0.80,0.20,1}, {0.85,0.25,0.25,1}, {0.95,0.85,0.35,1}, {0.60,0.60,0.60,1}, {0.90,0.90,0.90,1}
local function TextColored(c, s)
    if pcall(function() imgui.TextColored(c, s) end) then return end
    local function col32(r,g,b,a) local R=math.floor((r or 0)*255); local G=math.floor((g or 0)*255); local B=math.floor((b or 0)*255); local A=math.floor((a or 1)*255); return A*256^3 + R*256^2 + G*256 + B end
    if pcall(function() imgui.TextColored(col32(c[1],c[2],c[3],c[4] or 1), s) end) then return end
    imgui.Text(s or '')
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

local function draw_available_list_only(list_h)
    local called, visible = begin_child_compat('##blugui_av_child', 0, list_h or 0, true)
    if called then
        if visible then
            for idx, entry in ipairs(state.learned) do
                local nm = entry.name or ''
                if not is_already_in_working(nm) then
                    local sel = (state.avail_sel == idx)
                    if imgui.Selectable(string.format('[%s] %s##blugui_av%03d', fmt_points(nm), nm, idx), sel) then
                        state.avail_sel = idx
                    end
                    if imgui.IsItemHovered and imgui.IsItemHovered() then
                        state.hover_spell = { name = nm, id = entry.id, from = 'available' }
                    end
                end
            end
        end
        imgui.EndChild()
    end
end

local function draw_working_list_only(list_h)
    local called, visible = begin_child_compat('##blugui_work_child', 0, list_h or 0, true)
    if called then
        if visible then
            for i = 1, MAX_SLOTS_UI do
                local e = state.working[i]
                local nm = (e and e.name) or ''
                -- if (nm ~= '' and e and e.id) then
                -- else
                -- end
                local label = (nm ~= '' and string.format('%02d: [%s] %s##blugui_work%02d', i, fmt_points(nm), nm, i)
                    or string.format('%02d: (empty)##blugui_work%02d', i, i))
                local sel = (state.working_sel == i)
                if imgui.Selectable(label, sel) then
                    state.working_sel = i
                end
            if imgui.IsItemHovered and imgui.IsItemHovered() then
                state.hover_spell = { name = nm, id = (e and e.id) or 0, from = 'working', slot = i }
            end
            end
        end
        imgui.EndChild()
    end
end

local function draw_available_blu_section(list_h)
    if not imgui.CollapsingHeader('Available BLU Magic##blugui_av', ImGuiTreeNodeFlags_DefaultOpen) then
        return
    end

    local called, visible = begin_child_compat('##blugui_av_child', 0, list_h or 0, true)
    if called then
        if visible then
            for idx, entry in ipairs(state.learned) do
                local nm = entry.name or ''
                -- Skip spells that are already in the working set
                if not is_already_in_working(nm) then
                    local sel = (state.avail_sel == idx)
                    if imgui.Selectable(string.format('[%s] %s##blugui_av%03d', fmt_points(nm), nm, idx), sel) then
                        state.avail_sel = idx
                    end
                end
            end
        end
        imgui.EndChild()
    end

    if imgui.Button('Add Spell##blugui_add', v2(110, 0)) then
        local rm = AshitaCore:GetResourceManager()
        local idx = state.avail_sel
        local entry = state.learned[idx]
        if entry then
            local id = entry.id or 0
            local sp = rm and rm:GetSpellById(id) or nil
            if sp and is_blu_spell_strict(sp) then
                if not is_already_in_working(entry.name) then
                    local placed = false
                    for i = 1, MAX_SLOTS_UI do
                        local e = state.working[i]
                        if (not e) or (e.name == '' or e.name == nil) then
                            state.working[i] = { name = entry.name, id = entry.id }
                            state.working_sel = i
                            placed = true
                            break
                        end
                    end
                    if not placed then
                        print(chat.header(addon.name):append(chat.warning('All slots are filled; remove one first.')))
                    end
                else
                    print(chat.header(addon.name):append(chat.warning('That spell is already in your working set.')))
                end
            end
        end
    end
    imgui.SameLine()
    if imgui.Button('Use Equipped##blugui_seed', v2(110, 0)) then
        seed_from_current_equipped()
        state.apply_status = 'idle'
        state.current_set_name = '(unsaved)'
        sync_sets_dropdown_to_current()
    end
    imgui.SameLine()
    if imgui.Button('Rescan##blugui_rescan', v2(90, 0)) then
        refresh_learned(true)
    end
end

local function draw_working_section(list_h)
    if not imgui.CollapsingHeader('Working Set##blugui_work', ImGuiTreeNodeFlags_DefaultOpen) then
        return
    end

    local called, visible = begin_child_compat('##blugui_work_child', 0, list_h or 0, true)
    if called then
        if visible then
            for i = 1, MAX_SLOTS_UI do
                local e = state.working[i]
                local nm = (e and e.name) or ''
                local label = (nm ~= '' and string.format('%02d: %s##blugui_work%02d', i, nm, i)
                    or string.format('%02d: (empty)##blugui_work%02d', i, i))
                local sel = (state.working_sel == i)
                if imgui.Selectable(label, sel) then
                    state.working_sel = i
                end
            end
        end
        imgui.EndChild()
    end

    local wBtn = 110

    -- Row 1: Remove
    if imgui.Button('Remove Spell##blugui_remove', v2(wBtn, 0)) then
        local i = state.working_sel or 1
        if i >= 1 and i <= MAX_SLOTS_UI then
            state.working[i] = { name = '', id = nil }
        end
    end

    -- Live point total (updates as spells are added/removed)
    imgui.SameLine()
    local total, unknown = calc_working_set_points()
    if (unknown or 0) > 0 then
        imgui.Text(string.format('Total Points: %d + ?', total or 0))
    else
        imgui.Text(string.format('Total Points: %d', total or 0))
    end

    -- Row 2: Apply + slider + Save
    imgui.NewLine()
    if imgui.Button('Apply Set##blugui_apply', v2(wBtn, 0)) then
        apply_working_set()
    end
    imgui.SameLine()
    imgui.PushItemWidth(width_one_fifth())
    local r = { tonumber(state.packet_delay_s) or 1.25 }
    if imgui.SliderFloat('##blugui_delay', r, 1.00, 5.00, '%.2f') then
        state.packet_delay_s = math.max(1.00, math.min(5.00, math.floor(r[1] * 100 + 0.5) / 100))
    end
    imgui.PopItemWidth()
    imgui.SameLine()
    imgui.Text('Packet Delay (s)')

    -- Same line: Save + input
    imgui.SameLine()
    if imgui.Button('Save Set##blugui_save', v2(wBtn, 0)) then
        local name = (state.save_name_buf or ''):gsub('%.txt$', '')
        name = name:gsub('^%s+', ''):gsub('%s+$', '')
        if name == '' then
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
    imgui.PushItemWidth(width_chars(22))
    local s = { state.save_name_buf or '' }
    if imgui.InputText('##blugui_savename', s, 64) then
        state.save_name_buf = tostring(s[1] or '')
    end
    imgui.PopItemWidth()
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


ashita.events.register('packet_out', 'blugui_out', function(e)
    -- 0x0102 is the client packet used to set/unset BLU spells. We can compute points from the outgoing slot array
    -- so the UI updates instantly while you're clicking spells in the menu.
    local id = e.id
    if id == 0x0102 or id == 0x102 then
        update_live_points_from_packet(e.data)
    end
end)



ashita.events.register('d3d_present', 'blugui_present', function()
    if not state.is_open then return end

    -- Match newer addons (eg. SellBuddy):
    --   * Auto-fit height to content to avoid the huge blank area when sections collapse.
    --   * Set a reasonable default width once; allow ImGui to persist size/pos in imgui.ini.
    if imgui.SetNextWindowSize then
        imgui.SetNextWindowSize(v2(560, 0), ImGuiCond_Once)
    end
    if imgui.SetNextWindowPos then
        imgui.SetNextWindowPos(v2(state.ui.pos_x, state.ui.pos_y), ImGuiCond_FirstUseEver)
    end

    local window_flags = ImGuiWindowFlags_AlwaysAutoResize

    local open = { state.is_open }
    local begin_ok = imgui.Begin('BLU Spells##blugui_root', open, window_flags)
    state.is_open = (open[1] ~= false)

    if begin_ok then
        state.hover_spell = nil
        -- Track last position (helpful if you later want command-based movement again).
        local pos = imgui.GetWindowPos and imgui.GetWindowPos() or nil
        if type(pos)=='table' then
            state.ui.pos_x = pos.x or state.ui.pos_x
            state.ui.pos_y = pos.y or state.ui.pos_y
        end

        TextColored({0.90,0.90,0.90,1}, string.format('Current Set - %s  ', state.current_set_name)); imgui.SameLine()
        if state.apply_status == 'ok' then
            TextColored({0.20,0.80,0.20,1},'OK')
        elseif state.apply_status == 'error' then
            TextColored({0.85,0.25,0.25,1},'ERROR'); imgui.SameLine(); TextColored({0.90,0.90,0.90,1},'(try again)'); imgui.SameLine()
            if imgui.Button('Retry##blugui_retry', v2(90, 0)) then apply_working_set() end
        elseif state.apply_status == 'applying' then
            TextColored({0.95,0.85,0.35,1},'Applying...')
        else
            TextColored({0.92,0.42,0.18,1},'Not Set')
        end
        imgui.SameLine()
        local used, maxp = get_equipped_points()
        if state.apply_status == 'idle' then
            local working_total = select(1, calc_working_set_points()) or 0
            used = 0
            maxp = math.max(working_total, 0)
        end
        imgui.Spacing(); imgui.SameLine()
        local okpoints = (maxp or 0) > 0 and (used <= maxp)
        TextColored(okpoints and {0.20,0.80,0.20,1} or {0.85,0.25,0.25,1}, string.format('%d/%d', used, maxp))
        imgui.Separator()

        draw_sets_dropdown()
        imgui.Separator()

        -- Side-by-side layout (SellBuddy-style):
        -- Both lists share the same vertical height, so the window isn't "double tall".
        local line_h  = (imgui.GetTextLineHeightWithSpacing and imgui.GetTextLineHeightWithSpacing() or 18)
        local list_h  = (line_h * MAX_SLOTS_UI) + 6

        -- Table flags are optional; keep it robust across bindings.
        local table_flags = 0
        if imgui.ImGuiTableFlags_SizingStretchProp then
            table_flags = bit.bor(table_flags, imgui.ImGuiTableFlags_SizingStretchProp)
        elseif _G.ImGuiTableFlags_SizingStretchProp then
            table_flags = bit.bor(table_flags, _G.ImGuiTableFlags_SizingStretchProp)
        end
        if imgui.ImGuiTableFlags_BordersInnerV then
            table_flags = bit.bor(table_flags, imgui.ImGuiTableFlags_BordersInnerV)
        elseif _G.ImGuiTableFlags_BordersInnerV then
            table_flags = bit.bor(table_flags, _G.ImGuiTableFlags_BordersInnerV)
        end

        local began_table = (imgui.BeginTable and imgui.BeginTable('##blugui_table', 2, table_flags)) or false
        if began_table then
            if imgui.TableSetupColumn then
                -- Give the Working Set a touch more width so longer names fit better.
                -- (Weights are proportional; they do not force a fixed pixel width.)
                imgui.TableSetupColumn('Available', (imgui.ImGuiTableColumnFlags_WidthStretch or 0), 0.48)
                imgui.TableSetupColumn('Working',   (imgui.ImGuiTableColumnFlags_WidthStretch or 0), 0.52)
            end

            -- Left: Available
            imgui.TableNextColumn()
            imgui.Text('Available BLU Magic')
            draw_available_list_only(list_h)
            if imgui.Button('Add Spell##blugui_add', v2(110, 0)) then
                local rm = AshitaCore:GetResourceManager()
                local idx = state.avail_sel
                local entry = state.learned[idx]
                if entry then
                    local id = entry.id or 0
                    local sp = rm and rm:GetSpellById(id) or nil
                    if sp and is_blu_spell_strict(sp) then
                        if not is_already_in_working(entry.name) then
                            local placed = false
                            for i = 1, MAX_SLOTS_UI do
                                local e = state.working[i]
                                if (not e) or (e.name == '' or e.name == nil) then
                                    state.working[i] = { name = entry.name, id = entry.id }
                                    state.working_sel = i
                                    placed = true
                                    break
                                end
                            end
                            if not placed then
                                print(chat.header(addon.name):append(chat.warning('All slots are filled; remove one first.')))
                            end
                        else
                            print(chat.header(addon.name):append(chat.warning('That spell is already in your working set.')))
                        end
                    end
                end
            end
            imgui.SameLine()
            if imgui.Button('Use Equipped##blugui_seed', v2(110, 0)) then
                seed_from_current_equipped()
                state.apply_status = 'idle'
                state.current_set_name = '(unsaved)'
                sync_sets_dropdown_to_current()
            end
            imgui.SameLine()
            if imgui.Button('Rescan##blugui_rescan', v2(90, 0)) then
                refresh_learned(true)
            end

            -- Right: Working
            imgui.TableNextColumn()
            imgui.Text('Working Set')
            draw_working_list_only(list_h)
            if imgui.Button('Remove Spell##blugui_remove', v2(110, 0)) then
                local i = state.working_sel or 1
                if i >= 1 and i <= MAX_SLOTS_UI then
                    state.working[i] = { name = '', id = nil }
                end
            end

            imgui.SameLine()
            local total, unknown = calc_working_set_points()
            if (unknown or 0) > 0 then
                imgui.Text(string.format('Total Points: %d + ?', total or 0))
            else
                imgui.Text(string.format('Total Points: %d', total or 0))
            end

            imgui.EndTable()
        else
            -- Fallback: stacked layout (shouldn't happen, but keep it safe).
            draw_available_blu_section(list_h); imgui.Separator()
            draw_working_section(list_h)
        end

        -- Bottom controls (span full width)
        imgui.Separator()

        local wBtn = 110
        if imgui.Button('Apply Set##blugui_apply', v2(wBtn, 0)) then
            apply_working_set()
        end
        imgui.SameLine()
        imgui.PushItemWidth(width_one_fifth())
        local r = { tonumber(state.packet_delay_s) or 1.25 }
        if imgui.SliderFloat('##blugui_delay', r, 1.00, 5.00, '%.2f') then
            state.packet_delay_s = math.max(1.00, math.min(5.00, math.floor(r[1] * 100 + 0.5) / 100))
        end
        imgui.PopItemWidth()
        imgui.SameLine()
        imgui.Text('Packet Delay (s)')

        -- Same line: Save + input
        imgui.SameLine()
        if imgui.Button('Save Set##blugui_save', v2(wBtn, 0)) then
            local name = (state.save_name_buf or ''):gsub('%.txt$', '')
            name = name:gsub('^%s+', ''):gsub('%s+$', '')
            if name == '' then
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
        imgui.PushItemWidth(width_chars(22))
        local buf = { state.save_name_buf or '' }
        if imgui.InputText('##blugui_savename', buf, 64) then
            state.save_name_buf = buf[1]
        end
        imgui.PopItemWidth()

        -- Hover info panel
        if state.hover_spell and state.hover_spell.name and state.hover_spell.name ~= '' then
            imgui.Spacing()

            -- Wider hover box; keep it full-width and a bit taller so it doesn't feel cramped.
            local panel_w = 0
            local panel_h = 124

	            local called, visible = begin_child_compat('##blugui_hover_panel', panel_w, panel_h, true)
	            if called then
	                if visible then
	                    local hn = state.hover_spell.name

                        -- Spell name + icons on the same line.
                        imgui.Text(hn)
                        
                        imgui.Dummy({ 0, 1 })

                        local tlabel, tfile = get_spell_type_by_name(hn)
                        local props, pfiles, desc = get_spell_props_and_desc_by_name(hn)

                        local iconSize = 18
                        local any = false
                        if tfile or (type(pfiles) == 'table' and #pfiles > 0) then
                            imgui.SameLine()
                        end

                        if tfile then
                            if tlabel then
                                imgui.SameLine()
                                imgui.Text(tlabel)
                                imgui.SameLine()
                            end
                            any = draw_icon_inline(tfile, iconSize) or any
                        end
                        if type(pfiles) == 'table' then
                            for i = 1, #pfiles do
                                if pfiles[i] then
                                    if tfile or any then imgui.SameLine() end
                                    any = draw_icon_inline(pfiles[i], iconSize) or any
                                end
                            end
                        end

                        local pts = get_spell_points_by_name(hn) or 0
	                    imgui.Text(string.format('Points: %d', pts))
	                    imgui.SameLine()
	                    local el = get_spell_element_by_name(hn)
	                    if el ~= nil then
	                        imgui.Text('Element: ' .. element_name(el))
	                    end

	                    if desc and desc ~= '' then
	                        imgui.Text('Description: ' .. desc)
	                    end
	                    if props and props ~= '' then
	                        imgui.Text('Properties: ' .. props)
	                    end
	                end
	                imgui.EndChild()
	            end
        end

    end

    imgui.End()

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
