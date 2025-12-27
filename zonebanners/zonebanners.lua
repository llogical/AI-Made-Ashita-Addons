addon.name    = 'zonebanners'
addon.author  = 'Ilogical'
addon.version = '1.0.0'
addon.desc    = 'Displays zone entry banner (PNG).'

require('common')
local imgui    = require('imgui')
local settings = require('settings')
local bit      = bit or require('bit')
local ffi      = require('ffi')
local d3d      = require('d3d8')
local C        = ffi.C
local d3d8dev  = d3d.get_device()

ffi.cdef[[
    HRESULT __stdcall D3DXCreateTextureFromFileA(IDirect3DDevice8* pDevice, const char* pSrcFile, IDirect3DTexture8** ppTexture);
]]

local cfg = settings.load(T{
    banner_delay    = 1.0,
    banner_fade_in  = 0.35,
    banner_hold     = 10.0,
    banner_fade_out = 0.90,
    banner_y_frac   = 0.12,
    banner_scale    = 1.0,
})
settings.register('settings','zonebanners_settings_update', function(t) cfg = t end)

local function get_zone_id()
    local party = AshitaCore:GetMemoryManager():GetParty()
    if party ~= nil then
        local zid = party:GetMemberZone(0)
        if zid ~= nil then return zid end
    end
    local ply = GetPlayerEntity()
    if ply and ply.Zone then return ply.Zone end
    return nil
end

local function file_exists(path)
    local f = io.open(path, 'rb')
    if f ~= nil then f:close(); return true end
    return false
end

local function png_get_size(path)
    local f = io.open(path, 'rb')
    if not f then return nil end
    local header = f:read(24) 
    f:close()
    if not header or #header < 24 then return nil end

    if header:sub(1, 8) ~= string.char(137,80,78,71,13,10,26,10) then return nil end
    if header:sub(13, 16) ~= 'IHDR' then return nil end

    local function be_u32(s)
        local b1, b2, b3, b4 = s:byte(1,4)
        return (((b1 * 256 + b2) * 256 + b3) * 256 + b4)
    end

    local w = be_u32(header:sub(17,20))
    local h = be_u32(header:sub(21,24))
    if not w or not h or w <= 0 or h <= 0 then return nil end
    return w, h
end

local function load_texture_d3d8(path)
    local texture_ptr = ffi.new('IDirect3DTexture8*[1]')
    local res = C.D3DXCreateTextureFromFileA(d3d8dev, path, texture_ptr)
    if res ~= C.S_OK then
        return nil
    end

    local texture = ffi.new('IDirect3DTexture8*', texture_ptr[0])
    d3d.gc_safe_release(texture)
    return texture
end

local banner = {
    active  = false,
    start   = 0,
    texture = nil,
    w       = 0,
    h       = 0,
}

local last_zone_id = nil
local addon_path = addon.path

local function start_banner(zid)
    local path = string.format('%s\\assets\\zones\\%d.png', addon_path, zid)
    if not file_exists(path) then
        return
    end

    local w, h = png_get_size(path)
    if not w or not h then
        return
    end

    local tex = load_texture_d3d8(path)
    if not tex then
        return
    end

    banner.texture = tex
    banner.w, banner.h = w, h
    banner.start = os.clock()
    banner.active = true
end

------------------------------------------------------------
-- Draw
------------------------------------------------------------
ashita.events.register('d3d_present','zonebanners_present', function()

    local zid = get_zone_id()
    if zid and zid ~= last_zone_id then
        last_zone_id = zid
        start_banner(zid)
    end

    if banner.active and banner.texture then
        local delay    = cfg.banner_delay    or 1.5
        local fade_in  = cfg.banner_fade_in  or 0.75
        local hold     = cfg.banner_hold     or 6.0
        local fade_out = cfg.banner_fade_out or 0.95

        local t = os.clock() - banner.start
        local total = delay + fade_in + hold + fade_out

        if t >= total then
            banner.active = false
        elseif t >= delay then
            local u = t - delay

            local alpha = 1.0
            if u < fade_in then
                alpha = u / fade_in
            elseif u > fade_in + hold then
                alpha = 1.0 - ((u - fade_in - hold) / fade_out)
            end
            if alpha < 0 then alpha = 0 end
            if alpha > 1 then alpha = 1 end

            local io = imgui.GetIO()
            local scale = cfg.banner_scale or 1.0
            local w = banner.w * scale
            local h = banner.h * scale

            local x = (io.DisplaySize.x - w) * 0.5
            local y = io.DisplaySize.y * (cfg.banner_y_frac or 0.12)

            imgui.SetNextWindowPos({ x, y }, ImGuiCond_Always)
            imgui.SetNextWindowSize({ w, h }, ImGuiCond_Always)
            imgui.SetNextWindowBgAlpha(0)

            local winFlags = bit.bor(
                ImGuiWindowFlags_NoDecoration,
                ImGuiWindowFlags_NoBackground,
                ImGuiWindowFlags_NoInputs,
                ImGuiWindowFlags_NoMove
            )

            imgui.Begin('##zonebanner', true, winFlags)

            local sx, sy = imgui.GetCursorScreenPos()
            local textureID = tonumber(ffi.cast('uint32_t', banner.texture))

            imgui.GetWindowDrawList():AddImage(
                textureID,
                { sx, sy },
                { sx + w, sy + h },
                { 0, 0 },
                { 1, 1 },
                imgui.GetColorU32({ 1.0, 1.0, 1.0, alpha })
            )

            imgui.End()
        end
    end
end)

ashita.events.register('unload','zonebanners_unload', function()
    settings.save()
end)
