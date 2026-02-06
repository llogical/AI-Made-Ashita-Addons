
-- Font Awesome browser for Ashita: reads ICON_FA_* globals from addons/libs/imgui.lua

addon.name    = 'fa_browser'
addon.author  = 'ilogicall'
addon.version = '0.0.1'
addon.desc    = 'In-game Font Awesome icon browser (ICON_FA_* globals) + fallback scanner.';

require('common')
local imgui = require('imgui')

local ui = {
    open   = { true },
    search = { '' },

    mode_named = { true }, -- true = ICON_FA_* globals, false = PUA scan fallback

    -- fallback scanner:
    range_min = { 0xF000 },
    range_max = { 0xF8FF },
    cols      = { 16 },
    show_hex  = { true },

    -- named list options:
    show_glyph = { true },
    copy_style = { 0 }, -- 0=copy ICON_FA_NAME, 1=copy local fa.NAME = ICON_FA_NAME, 2=copy both
}

-- -----------------------------
-- Helpers
-- -----------------------------
local function contains(hay, needle)
    if (needle == nil or needle == '') then return true end
    hay = tostring(hay):lower()
    needle = tostring(needle):lower()
    return hay:find(needle, 1, true) ~= nil
end

local function cp_to_utf8(cp)
    if (cp <= 0x7F) then
        return string.char(cp)
    elseif (cp <= 0x7FF) then
        return string.char(
            0xC0 + bit.rshift(cp, 6),
            0x80 + bit.band(cp, 0x3F)
        )
    elseif (cp <= 0xFFFF) then
        return string.char(
            0xE0 + bit.rshift(cp, 12),
            0x80 + bit.band(bit.rshift(cp, 6), 0x3F),
            0x80 + bit.band(cp, 0x3F)
        )
    else
        return string.char(
            0xF0 + bit.rshift(cp, 18),
            0x80 + bit.band(bit.rshift(cp, 12), 0x3F),
            0x80 + bit.band(bit.rshift(cp, 6), 0x3F),
            0x80 + bit.band(cp, 0x3F)
        )
    end
end

-- Decode first UTF-8 codepoint from a string (used only for optional “hex search”)
local function utf8_first_codepoint(s)
    if (type(s) ~= 'string' or #s == 0) then return nil end
    local b1 = s:byte(1); if not b1 then return nil end
    if (b1 < 0x80) then return b1 end
    local b2 = s:byte(2); if not b2 then return nil end
    if (b1 >= 0xC0 and b1 < 0xE0) then
        return bit.lshift(bit.band(b1, 0x1F), 6) + bit.band(b2, 0x3F)
    end
    local b3 = s:byte(3); if not b3 then return nil end
    if (b1 >= 0xE0 and b1 < 0xF0) then
        return bit.lshift(bit.band(b1, 0x0F), 12)
             + bit.lshift(bit.band(b2, 0x3F), 6)
             + bit.band(b3, 0x3F)
    end
    local b4 = s:byte(4); if not b4 then return nil end
    if (b1 >= 0xF0 and b1 < 0xF8) then
        return bit.lshift(bit.band(b1, 0x07), 18)
             + bit.lshift(bit.band(b2, 0x3F), 12)
             + bit.lshift(bit.band(b3, 0x3F), 6)
             + bit.band(b4, 0x3F)
    end
    return nil
end

-- -----------------------------
-- Named icon index (ICON_FA_* globals)
-- -----------------------------
local named = {
    built = false,
    list = {},
    count = 0,
}

local function build_named_index()
    named.list = {}
    named.count = 0

    for k, v in pairs(_G) do
        if (type(k) == 'string'
            and k:sub(1, 8) == 'ICON_FA_'
            and type(v) == 'string'
            and #v > 0) then
            local short = k:sub(9) -- remove ICON_FA_
            local cp = utf8_first_codepoint(v)
            table.insert(named.list, {
                key = k,
                name = short,
                glyph = v,
                cp = cp,
            })
            named.count = named.count + 1
        end
    end

    table.sort(named.list, function(a, b)
        return a.name < b.name
    end)

    named.built = true
end

local function copy_named(item)
    local k = item.key
    local n = item.name

    if (ui.copy_style[1] == 0) then
        imgui.SetClipboardText(k)
        return
    end

    if (ui.copy_style[1] == 1) then
        imgui.SetClipboardText(string.format("local fa_%s = %s\n", n:lower(), k))
        return
    end

    -- both
    local s = string.format(
        "%s\nlocal fa_%s = %s\n",
        k, n:lower(), k
    )
    imgui.SetClipboardText(s)
end


build_named_index()

-- -----------------------------
-- Draw
-- -----------------------------
ashita.events.register('d3d_present', 'fa_browser_present', function()
    if (not ui.open[1]) then return end

    imgui.SetNextWindowSize({ 740, 580 }, ImGuiCond_FirstUseEver)

    if (not imgui.Begin('Font Awesome Browser##fa_browser', ui.open, ImGuiWindowFlags_AlwaysAutoResize)) then
        imgui.End()
        return
    end

    imgui.Text('Uses ICON_FA_* globals from addons/libs/imgui.lua. Click an icon to copy.')
    imgui.Separator()

    -- Mode
    imgui.Text('Mode:')
    imgui.SameLine()
    if (imgui.RadioButton('Named (ICON_FA_*)', ui.mode_named[1])) then ui.mode_named[1] = true end
    imgui.SameLine()
    if (imgui.RadioButton('PUA Scan (fallback)', not ui.mode_named[1])) then ui.mode_named[1] = false end

    imgui.Separator()

    -- Search
    imgui.Text('Search (name or hex like F013):')
    imgui.SameLine()
    imgui.SetNextItemWidth(260)
    imgui.InputText('##fa_search', ui.search, 96)

    imgui.SameLine()
    if (imgui.Button('Rebuild##fa_rebuild')) then
        build_named_index()
    end
    imgui.SameLine()
    imgui.TextDisabled(string.format('Found: %d', named.count))

    local search = ui.search[1] or ''
    imgui.Separator()

    if (ui.mode_named[1]) then
        -- Named view options
        imgui.Checkbox('Show glyph beside name', ui.show_glyph)
        imgui.SameLine()
        imgui.Text('Copy:')
        imgui.SameLine()
        if (imgui.RadioButton('ICON_FA_NAME', ui.copy_style[1] == 0)) then ui.copy_style[1] = 0 end
        imgui.SameLine()
        if (imgui.RadioButton('local fa_x = ICON_FA_NAME', ui.copy_style[1] == 1)) then ui.copy_style[1] = 1 end
        imgui.SameLine()
        if (imgui.RadioButton('Both', ui.copy_style[1] == 2)) then ui.copy_style[1] = 2 end

        imgui.Separator()

        local child_flags = ImGuiChildFlags_Borders
        imgui.BeginChild('##fa_named', { 720, 440 }, child_flags)

        for _, item in ipairs(named.list) do
            local hex = (item.cp and string.format('%04X', item.cp)) or ''
            if (contains(item.name, search) or contains(item.key, search) or contains(hex, search)) then
                -- glyph button
                if (imgui.Button(item.glyph .. '##fa_' .. item.key, { 28, 28 })) then
                    copy_named(item)
                end

                imgui.SameLine()

                if (ui.show_glyph[1]) then
                    imgui.Text(string.format('%s  (%s)', item.key, item.name))
                else
                    imgui.Text(item.key)
                end

                if (item.cp ~= nil) then
                    imgui.SameLine()
                    imgui.TextDisabled('0x' .. hex)
                end
            end
        end

        imgui.EndChild()

        imgui.Separator()
        imgui.Text('Example:')
        imgui.TextDisabled("if imgui.CollapsingHeader(ICON_FA_GEAR .. '  Run Settings##run', IMGUI_TNF_DEFAULT_OPEN) then ... end")

    else
        -- PUA scan fallback
        imgui.Text('PUA Range:')
        imgui.SameLine()
        imgui.SetNextItemWidth(90)
        imgui.InputInt('##fa_min', ui.range_min)
        imgui.SameLine()
        imgui.SetNextItemWidth(90)
        imgui.InputInt('##fa_max', ui.range_max)

        if (ui.range_min[1] < 0) then ui.range_min[1] = 0 end
        if (ui.range_max[1] < ui.range_min[1]) then ui.range_max[1] = ui.range_min[1] end

        imgui.SameLine()
        imgui.Text('Cols:')
        imgui.SameLine()
        imgui.SetNextItemWidth(150)
        imgui.SliderInt('##fa_cols', ui.cols, 8, 32)

        imgui.Checkbox('Show Hex Under Icons', ui.show_hex)
        imgui.Separator()

        local child_flags = ImGuiChildFlags_Borders
        imgui.BeginChild('##fa_grid', { 720, 440 }, child_flags)

        local col = 0
        for cp = ui.range_min[1], ui.range_max[1] do
            local hex = string.format('%04X', cp)
            local glyph = cp_to_utf8(cp)

            if (contains(hex, search) or contains(glyph, search)) then
                if (col > 0) then imgui.SameLine() end
                if (imgui.Button(glyph .. '##fa_' .. hex, { 28, 28 })) then
                    imgui.SetClipboardText(string.format("local icon = utf8.char(0x%s)\n", hex))
                end
                if (ui.show_hex[1]) then
                    imgui.SameLine()
                    imgui.TextDisabled(hex)
                end
                col = col + 1
                if (col >= ui.cols[1]) then col = 0 end
            end
        end

        imgui.EndChild()
    end

    imgui.End()
end)
