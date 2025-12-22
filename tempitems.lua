addon.name      = 'tempitems';
addon.author    = 'Ilogicall';
addon.version   = '1.0.1';
addon.desc      = 'Click-to-use Temporary Items with optional command prefix.';
addon.link      = 'https://ashitaxi.com/';

require('common');
local imgui     = require('imgui');
local settings  = require('settings');


local defaults = T{
    window = T{
        pos = T{ x = 200, y = 200 },
        open = true,
    },
    use = T{
        prefix = '',           -- e.g. '/mss ' for use with multisend.
        target = '<me>',       -- '<me>', '<t>', etc.
        confirm_click = false, -- confirm step
    },
    ui = T{
        filter = '',
        columns = 2,
        show_counts = true,
    }
};

local S = settings.load(defaults);


local function save()
    settings.save();
end

local function set_prefix(p)
    S.use.prefix = p or '';
    save();
end

local function set_target(t)
    local valid = { ['<me>']=1, ['<t>']=1, ['<stpc>']=1, ['<stpt>']=1, ['<stal>']=1, ['<last>']=1 };
    if valid[string.lower(t)] then
        S.use.target = string.lower(t);
        save();
        return true;
    end
    return false;
end


local ZONE_TEMENOS  = 37;
local ZONE_APOLLYON = 38;

local function get_zone_id()

    local mm = AshitaCore and AshitaCore:GetMemoryManager() or nil;
    if mm and mm.GetParty then
        local party = mm:GetParty();
        if party and party.GetMemberZone then
            local z = party:GetMemberZone(0); -- 0 = player
            if z ~= nil then return tonumber(z) end
        end
    end

    if mm and mm.GetPlayer then
        local pl = mm:GetPlayer();
        if pl and pl.GetZoneId then
            local z = pl:GetZoneId();
            if z ~= nil then return tonumber(z) end
        end
    end

    return nil;
end

local function limbus_zone_label(zone_id)
    if zone_id == ZONE_APOLLYON then return 'Apollyon' end
    if zone_id == ZONE_TEMENOS then return 'Temenos' end
    return nil
end


local function _ti_norm(s)
    if type(s) ~= 'string' then return '' end

    s = s:gsub(string.char(194,160), ' ')
    s = s:gsub('\u{00A0}', ' ')

    s = s:gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    return s
end


local function parse_limbus_floor_key(name)
    name = _ti_norm(name)
    local low = name:lower()


    do
        local wing, floor = low:match('apollyon%s+([ns][we])%s*#%s*(%d+)')
        if wing and floor then
            return wing:upper(), tonumber(floor), 'Apollyon'
        end
    end


    do
        
        local wing, floor = low:match('temenos%s+([neswc])%s*#%s*(%d+)')
        if not wing then
            wing, floor = low:match('tem%.?%s*([neswc])%s*%-%s*f%s*(%d+)')
        end
        if not wing then
            wing, floor = low:match('temenos%s+([neswc])%s*%-%s*f%s*(%d+)')
        end
        if not wing then
            
            wing, floor = low:match('tem%.?%s*([neswc])%s*f%s*(%d+)')
        end
        if wing and floor then
            return wing:upper(), tonumber(floor), 'Temenos'
        end
    end

    return nil, nil, nil
end

local function draw_limbus_grouped(list, limbus_label)
    list = (type(list) == 'table') and list or {}


    local groups = {}
    for _, it in ipairs(list) do
        local wing, floor, zlabel = parse_limbus_floor_key(it.name)
        if wing and floor and zlabel == limbus_label then
            groups[wing] = groups[wing] or {}
            table.insert(groups[wing], { name = _ti_norm(it.name), floor = floor })
        end
    end


    local any = false
    for _ in pairs(groups) do any = true break end
    if not any then
        for _, it in ipairs(list) do
            imgui.Text(_ti_norm(it.name))
        end
        return
    end


    for _, g in pairs(groups) do
        table.sort(g, function(a, b)
            if a.floor ~= b.floor then return a.floor < b.floor end
            return a.name:lower() < b.name:lower()
        end)
    end


    local left, right
    if limbus_label == 'Apollyon' then
        left  = { 'NW', 'SW' }
        right = { 'NE', 'SE' }
    else

        left  = { 'N', 'S', 'C' }
        right = { 'E', 'W' }
    end

    local function draw_wing_block(wing)
        local g = groups[wing]
        if not g or #g == 0 then return end

 
        imgui.TextColored({ 0.45, 0.75, 1.0, 1.0 }, wing)
        imgui.Separator()

        for i = 1, #g do
            local row = g[i]
            imgui.Text(row.name)


            local next_floor = (i < #g) and g[i + 1].floor or nil
            if next_floor ~= row.floor then
                imgui.Separator()
            end
        end

        
        imgui.Dummy({ 0, 6 })
    end


    local avail = { imgui.GetContentRegionAvail() }
    local gutter = 12
    local colw = math.max(140, (avail[1] - gutter) / 2)

    imgui.BeginChild('ti_limbus_left', { colw, 0 }, false)
    for _, wing in ipairs(left) do
        draw_wing_block(wing)
    end
    imgui.EndChild()

    imgui.SameLine(0, gutter)

    imgui.BeginChild('ti_limbus_right', { colw, 0 }, false)
    for _, wing in ipairs(right) do
        draw_wing_block(wing)
    end
    imgui.EndChild()
end


local function read_temp_items()
    local out = T{};
    local inv = AshitaCore:GetMemoryManager():GetInventory();
    if inv == nil then return out; end

    
    local container = 3;
    local count = inv:GetContainerCount(container);
    if count == nil or count <= 0 then return out; end

    local resm = AshitaCore:GetResourceManager();

    for slot = 1, count do
        local it = inv:GetContainerItem(container, slot);
        if it ~= nil and it.Id ~= 0 then
            local rid = it.Id;
            local ri = resm:GetItemById(rid);
            local name = ri and ri.Name[1] or ('Item:' .. tostring(rid));
            table.insert(out, { id = rid, name = name, count = it.Count or 1, slot = slot });
        end
    end

    table.sort(out, function(a, b)
        return string.lower(a.name) < string.lower(b.name);
    end);

    return out;
end

local function issue_use(name)
    if not name or name == '' then return end
    local cm = AshitaCore:GetChatManager();
    if cm == nil then return end

    local cmd = string.format('%s/item "%s" %s', S.use.prefix or '', name, S.use.target or '<me>');
    cm:QueueCommand(1, cmd);
end


ashita.events.register('command', 'tempitems_command', function (e)
    local args = e.command:args();
    if #args == 0 then return; end

    local root = string.lower(args[1]);
    if root ~= '/tempitems' and root ~= '/ti' then return; end
    e.blocked = true;

    if #args == 1 then
        S.window.open = not S.window.open;
        save();
        return;
    end

    local sub = string.lower(args[2] or '');
    if sub == 'prefix' then
 
        local p = e.command:sub(#args[1] + #args[2] + 3) or '';
        set_prefix(p);
        return;
    elseif sub == 'target' then
        local t = args[3] or '<me>';
        if not set_target(t) then
            print(string.format('[tempitems] Invalid target: %s  (use one of: <me>, <t>, <stpc>, <stpt>, <stal>, <last>)', t));
        end
        return;
    else
        print('[tempitems] Unknown command. Usage: /ti [prefix <text> | target <me|t|stpc|stpt|stal|last>]');
    end
end);


local last_window_pos = { x = S.window.pos.x, y = S.window.pos.y };

local function draw_ui()
    if not S.window.open then return end

    local zid = get_zone_id();
    local limbus_label = limbus_zone_label(zid);
    local is_limbus = (limbus_label ~= nil);


    imgui.SetNextWindowPos({ S.window.pos.x, S.window.pos.y }, ImGuiCond_FirstUseEver);
    imgui.SetNextWindowSize({ 420, 360 }, ImGuiCond_FirstUseEver);

    local title = 'Temp Items';
    if is_limbus then
        title = string.format('Temp Items [%s]', limbus_label);
    end

    if imgui.Begin(title, true) then

        local pos = { imgui.GetWindowPos() };
        if pos[1] ~= last_window_pos.x or pos[2] ~= last_window_pos.y then
            last_window_pos.x, last_window_pos.y = pos[1], pos[2];
            S.window.pos.x, S.window.pos.y = pos[1], pos[2];
            save();
        end

        if not is_limbus then
            imgui.Text('Columns:');
            do
                local col_label = tostring(S.ui.columns or 2);
                imgui.SameLine()
                imgui.SetNextItemWidth(60);
                if imgui.BeginCombo('##ti_columns_dd', col_label) then
                    for i = 1, 5 do
                        local selected = (i == (S.ui.columns or 2));
                        if imgui.Selectable(tostring(i), selected) then
                            S.ui.columns = i; save();
                        end
                    end
                    imgui.EndCombo();
                end
            end

            imgui.Text('Target :');
            imgui.SameLine();
            do
                local avail = { imgui.GetContentRegionAvail() };
                local third = math.max(40, (avail[1] or 120) / 3);
                imgui.SetNextItemWidth(math.min(third, 170));
                local targets = { '<me>', '<t>', '<stpc>', '<stpt>', '<stal>', '<last>' };
                local current = 1;
                for i, t in ipairs(targets) do if t == S.use.target then current = i break end end
                if imgui.BeginCombo('##ti_target', targets[current]) then
                    for i, t in ipairs(targets) do
                        local selected = (i == current);
                        if imgui.Selectable(t, selected) then
                            S.use.target = t; save();
                        end
                    end
                    imgui.EndCombo();
                end
            end


            local prefix_buf = { S.use.prefix };
            imgui.Text('Prefix :');
            imgui.SameLine();
            imgui.SetNextItemWidth(240);
            if imgui.InputText('##ti_prefix', prefix_buf, 64) then
                S.use.prefix = prefix_buf[1];
                save();
            end

            local filter_buf = { S.ui.filter };
            imgui.Text('Filter :');
            imgui.SameLine();
            imgui.SetNextItemWidth(240);
            if imgui.InputText('##ti_filter', filter_buf, 96) then
                S.ui.filter = filter_buf[1];
                save();
            end

            imgui.Separator();
        end


        local list = read_temp_items() or T{};
        local filter = (S.ui.filter or ''):lower();

        if is_limbus then
            draw_limbus_grouped(list, limbus_label);
        else
            local colcount = math.max(1, S.ui.columns or 2);
            imgui.Columns(colcount, 'ti_grid', false);

            for _, it in ipairs(list) do
                if (filter == '' or string.find(it.name:lower(), filter, 1, true)) then
                    local label = it.name;
                    if S.ui.show_counts and (it.count or 1) > 1 then
                        label = string.format('%s x%d', label, it.count);
                    end

                    if imgui.Button(label, { -1, 0 }) then
                        issue_use(it.name);
                    end
                end
                imgui.NextColumn();
            end

            imgui.Columns(1);
        end
    end
    imgui.End();
end


ashita.events.register('d3d_present', 'tempitems_present', function ()
    draw_ui();
end);


ashita.events.register('load', 'tempitems_load', function()

end);
