-- load common SDL input/video library
local SDL = require("ffi/SDL3")
local BB = require("ffi/blitbuffer")
local util = require("ffi/util")
local ffi = require("ffi")
local framebuffer = {
    -- this blitbuffer will be used when we use refresh emulation
    sdl_bb = nil,
}

local function getBackingSize(bb)
    return tonumber(bb.w), tonumber(bb.h)
end

function framebuffer:init()
    if not self.dummy then
        -- Input dimensions are *window* sizes
        SDL.open(self.w, self.h, self.x, self.y)
        -- Open might fudge them a bit on the emu, so, resync
        self.w, self.h = SDL.win_w, SDL.win_h
        self:_newBB()
    else
        self.bb = BB.new(600, 800)
    end
    if (os.getenv("EMULATE_BW_SCREEN") or "") ~= "" then
        self.device.hasColorScreen = function() return false end
        self.isColorEnabled = function() return false end
    end

    self.bb:fill(BB.COLOR_WHITE)
    self:refreshFull(0, 0, self:getWidth(), self:getHeight())

    framebuffer.parent.init(self)
end

function framebuffer:resize(w, h)
    local output_w = ffi.new("int[1]", 0)
    local output_h = ffi.new("int[1]", 0)
    local viewport = self.viewport
    local old_bb = self.full_bb or self.bb
    local old_w, old_h
    if old_bb then
        old_w, old_h = getBackingSize(old_bb)
    end

    SDL.SDL.SDL_GetWindowSize(SDL.screen, output_w, output_h)
    SDL.win_w = w or tonumber(output_w[0])
    SDL.win_h = h or tonumber(output_h[0])
    self.w = SDL.win_w
    self.h = SDL.win_h

    if SDL.SDL.SDL_GetCurrentRenderOutputSize(SDL.renderer, output_w, output_h) then
        -- This is a workaround to obtain a simulacrum of real pixels in scenarios that marketing likes to refer to as "HiDPI".
        -- The utterly deranged idea is to render things at 2x or 3x, so it can subsequently be scaled down in order to assure everything will always be at least a little bit blurry unless you happen to use exactly 2x or 3x, instead of the traditional methods of just rendering at the desired DPI that have worked perfectly fine in Windows and X11 for decades.
        -- Contrary to claims by the blind that macOS is sharp, it's not.
        -- Wayland is a bad derivative of macOS. Everything macOS does wrong it does worse.
        -- tl;dr Use Windows or X11 if you value your eyes and sanity. Or *gulp* Android. And Sailfish of course.
        w = tonumber(output_w[0])
        h = tonumber(output_h[0])
    else
        w = SDL.win_w
        h = SDL.win_h
    end

    if not self.dummy and old_w == w and old_h == h then
        SDL.w = w
        SDL.h = h
        self:_updateScreenSize()
        return
    end

    if not self.dummy then
        self:_newBB(w, h)
        SDL.w = w
        SDL.h = h
    else
        self.bb:free()
        self.bb = BB.new(600, 800)
    end

    if SDL.texture then SDL.destroyTexture(SDL.texture) end
    SDL.texture = SDL.createTexture(w, h)

    self:_updateScreenSize()
    if viewport and self:_viewportFits(viewport) then
        self:setViewport(viewport)
        return
    end

    self.bb:fill(BB.COLOR_WHITE)
    self:refreshFull(0, 0, self:getWidth(), self:getHeight())
end

local bb_emu = os.getenv("EMULATE_BB_TYPE")
function framebuffer:_newBB(w, h)
    w = w or SDL.w
    h = h or SDL.h

    local rotation
    local inverse

    if self.sdl_bb then self.sdl_bb:free() end
    if self.full_bb then
        self.bb = self.full_bb
        self.full_bb = nil
    end
    self.viewport = nil
    if self.bb then
        rotation = self.bb:getRotation()
        inverse = self.bb:getInverse() == 1
        self.bb:free()
    end

    -- we present this buffer to the outside
    local sdl_bb_type = BB["TYPE_" .. (bb_emu or "BBRGB32")]
    local bb = BB.new(w, h, sdl_bb_type)
    local flash = os.getenv("EMULATE_READER_FLASH")
    if flash then
        -- in refresh emulation mode, we use a shadow blitbuffer
        -- and blit refresh areas from it.
        self.sdl_bb = bb
        self.bb = BB.new(w, h, bb:getType())
    else
        self.bb = bb
    end

    if rotation then
        self.bb:setRotation(rotation)
    end

    -- reinit inverse mode on resize
    if inverse then
        self.bb:invert()
    end
end

function framebuffer:_updateScreenSize()
    local bb = self.full_bb or self.bb
    local w, h = getBackingSize(bb)
    self.screen_size = { w = w, h = h }
    if self.screen_size.w > self.screen_size.h and self.is_always_portrait then
        self.screen_size.w, self.screen_size.h = self.screen_size.h, self.screen_size.w
    end
end

function framebuffer:_viewportFits(viewport)
    return viewport.x >= 0 and viewport.y >= 0
        and viewport.w >= 0 and viewport.h >= 0
        and viewport.x + viewport.w <= self.screen_size.w
        and viewport.y + viewport.h <= self.screen_size.h
end

function framebuffer:setViewport(viewport)
    if viewport.x < 0 or viewport.x > self.screen_size.w
    or viewport.y < 0 or viewport.y > self.screen_size.h
    or viewport.w < 0 or viewport.x + viewport.w > self.screen_size.w
    or viewport.h < 0 or viewport.y + viewport.h > self.screen_size.h then
        error("fb:setViewport() bad viewport")
    end

    local first_viewport = not self.full_bb
    if first_viewport then
        self.full_bb = self.bb
    end
    self.debug("fb:setViewport() setting viewport to",
               viewport.x, viewport.y,
               viewport.w, viewport.h)
    self.bb = self.full_bb:viewport(
        viewport.x,
        viewport.y,
        viewport.w,
        viewport.h)
    self.viewport = viewport

    local full_w = self.full_bb:getWidth()
    local full_h = self.full_bb:getHeight()
    local function clearRect(x, y, w, h)
        if w > 0 and h > 0 then
            self.full_bb:paintRect(x, y, w, h, BB.COLOR_WHITE)
        end
    end
    if first_viewport then
        self.full_bb:fill(BB.COLOR_WHITE)
    else
        clearRect(0, 0, full_w, viewport.y)
        clearRect(0, viewport.y + viewport.h, full_w, full_h - viewport.y - viewport.h)
        clearRect(0, viewport.y, viewport.x, viewport.h)
        clearRect(viewport.x + viewport.w, viewport.y,
            full_w - viewport.x - viewport.w, viewport.h)
    end

    if self.full_bb then
        self:_render(self.full_bb, 0, 0, self.full_bb:getWidth(), self.full_bb:getHeight())
    end
end

function framebuffer:_render(bb, x, y, w, h)
    -- x, y, w, h without rotation for SDL rectangle
    local px, py, pw, ph = bb:getPhysicalRect(x, y, w, h)

    -- A viewport is a Blitbuffer object that works on a rectangular
    -- subset of the underlying memory without allocating new memory.
    local full_update = x == 0 and y == 0 and w == bb:getWidth() and h == bb:getHeight()
    local bb_rect = full_update and bb or bb:viewport(x, y, w, h)
    local sdl_rect = SDL.rect(px, py, pw, ph)

    if not bb_emu then
        SDL.SDL.SDL_UpdateTexture(SDL.texture, sdl_rect, bb_rect.data, bb_rect.stride)
    else
        -- The manual conversion is here deliberately, so as to separate us from possible bugs in the blitter.
        local vbuf = ffi.new("ColorRGB32[?]", pw*ph)
        local pos = 0
        for vy=0, ph-1 do
            for vx=0, pw-1 do
                vbuf[pos] = bb_rect:getPixelP(vx, vy)[0]:getColorRGB32()
                pos = pos+1
            end
        end
        SDL.SDL.SDL_UpdateTexture(SDL.texture, sdl_rect, vbuf, pw * 4)
    end

    SDL.SDL.SDL_RenderClear(SDL.renderer)
    SDL.SDL.SDL_RenderTexture(SDL.renderer, SDL.texture, nil, nil)
    SDL.SDL.SDL_RenderPresent(SDL.renderer)
end

function framebuffer:refreshFullImp(x, y, w, h)
    if self.dummy then return end

    local bb = self.full_bb or self.bb
    x, y, w, h = bb:getBoundedRect(x, y, w, h)
    self.debug(string.format("refresh on logical rectangle %dx%d+%d+%d", w, h, x, y))

    local flash = os.getenv("EMULATE_READER_FLASH")
    if flash then
        -- Match the rotation of the screen buffer now
        self.sdl_bb:setRotation(bb:getRotation())
        self.sdl_bb:setInverse(bb:getInverse())
        -- This ensures invertRect will not paint to now potentially off-screen regions (e.g., because of a viewport)
        self.sdl_bb:invertRect(x, y, w, h)
        self:_render(self.sdl_bb, x, y, w, h)
        util.usleep(tonumber(flash)*1000)
        -- Resync the shadow buffer with the new content
        self.sdl_bb:blitFrom(bb, x, y, x, y, w, h)
    end
    self:_render(bb, x, y, w, h)
end

function framebuffer:setWindowTitle(new_title)
    framebuffer.parent.setWindowTitle(self, new_title)
    SDL.SDL.SDL_SetWindowTitle(SDL.screen, self.window_title)
end

function framebuffer:setWindowIcon(icon)
    SDL.setWindowIcon(icon)
end

function framebuffer:close()
    SDL.SDL.SDL_DestroyRenderer(SDL.renderer)
    SDL.SDL.SDL_Quit()
end

return require("ffi/framebuffer"):extend(framebuffer)
