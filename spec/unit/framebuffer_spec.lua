describe("Framebuffer unit tests", function()
    local fb

    setup(function()
        fb = require("ffi/framebuffer_dummy"):new{
            dummy = true,
            device = {
                device_dpi = 167,
            }
        }
    end)

    it("should set & update DPI", function()
        assert.are.equals(160, fb:getDPI())

        fb:setDPI(120)
        assert.are.equals(120, fb:getDPI())

        fb:setDPI(60)
        assert.are.equals(60, fb:getDPI())
    end)

    it("should scale by DPI", function()
        fb:setDPI(167)
        assert.are.equals(31, fb:scaleBySize(30))

        fb:setDPI(167 * 3)
        assert.are.equals(62, fb:scaleBySize(30))
    end)

    local function withFakeSDLFramebuffer(fn)
        local old_sdl = package.loaded["ffi/SDL3"]
        local old_framebuffer_sdl3 = package.loaded["ffi/framebuffer_SDL3"]
        package.loaded["ffi/framebuffer_SDL3"] = nil

        local fake_sdl
        fake_sdl = {
            w = 600,
            h = 800,
            win_w = 600,
            win_h = 800,
            screen = {},
            renderer = {},
            texture = {},
            update_rects = {},
            SDL = {
                SDL_GetWindowSize = function(_, w, h)
                    w[0] = fake_sdl.win_w
                    h[0] = fake_sdl.win_h
                    return true
                end,
                SDL_GetCurrentRenderOutputSize = function(_, w, h)
                    w[0] = fake_sdl.w
                    h[0] = fake_sdl.h
                    return true
                end,
                SDL_UpdateTexture = function(_, rect)
                    table.insert(fake_sdl.update_rects, { x = rect.x, y = rect.y, w = rect.w, h = rect.h })
                    return true
                end,
                SDL_RenderClear = function() return true end,
                SDL_RenderTexture = function() return true end,
                SDL_RenderPresent = function() return true end,
            },
            open = function(_, _)
                return true
            end,
            createTexture = function(w, h)
                return { w = w, h = h }
            end,
            destroyTexture = function() end,
            rect = function(x, y, w, h)
                return { x = x, y = y, w = w, h = h }
            end,
        }
        package.loaded["ffi/SDL3"] = fake_sdl

        local ok, err = pcall(function()
            fn(require("ffi/framebuffer_SDL3"), fake_sdl)
        end)
        package.loaded["ffi/framebuffer_SDL3"] = old_framebuffer_sdl3
        package.loaded["ffi/SDL3"] = old_sdl
        assert.is_true(ok, err)
    end

    it("should refresh the full SDL texture when setting a viewport", function()
        withFakeSDLFramebuffer(function(SDLFramebuffer, fake_sdl)
            local sdl_fb = SDLFramebuffer:new{
                device = { device_dpi = 167 },
                debug = function() end,
                w = 600,
                h = 800,
            }

            sdl_fb:setViewport{x = 10, y = 20, w = 500, h = 500}

            local last_rect = fake_sdl.update_rects[#fake_sdl.update_rects]
            assert.are.equals(0, last_rect.x)
            assert.are.equals(0, last_rect.y)
            assert.are.equals(600, last_rect.w)
            assert.are.equals(800, last_rect.h)
        end)
    end)

    it("should preserve SDL viewport contents while clearing margins", function()
        withFakeSDLFramebuffer(function(SDLFramebuffer)
            local Blitbuffer = require("ffi/blitbuffer")
            local sdl_fb = SDLFramebuffer:new{
                device = { device_dpi = 167 },
                debug = function() end,
                w = 600,
                h = 800,
            }
            sdl_fb:setViewport{x = 0, y = 0, w = 600, h = 800}
            sdl_fb.bb:paintRect(5, 5, 10, 10, Blitbuffer.COLOR_BLACK)
            sdl_fb.bb:paintRect(30, 40, 10, 10, Blitbuffer.COLOR_BLACK)

            sdl_fb:setViewport{x = 10, y = 20, w = 500, h = 500}

            assert.True(sdl_fb.full_bb:getPixel(5, 5):getColor8() == Blitbuffer.Color8(0xFF))
            assert.True(sdl_fb.full_bb:getPixel(30, 40):getColor8() == Blitbuffer.Color8(0x00))
        end)
    end)

    it("should preserve an SDL viewport on resize when render output is unchanged", function()
        withFakeSDLFramebuffer(function(SDLFramebuffer, fake_sdl)
            local Blitbuffer = require("ffi/blitbuffer")
            local sdl_fb = SDLFramebuffer:new{
                device = { device_dpi = 167 },
                debug = function() end,
                w = 600,
                h = 800,
            }
            sdl_fb:setViewport{x = 10, y = 20, w = 500, h = 500}
            sdl_fb.bb:paintRect(5, 5, 10, 10, Blitbuffer.COLOR_BLACK)
            local old_full_bb = sdl_fb.full_bb
            local update_count = #fake_sdl.update_rects

            sdl_fb:resize(600, 800)

            assert.are.equals(old_full_bb, sdl_fb.full_bb)
            assert.are.equals(600, sdl_fb:getScreenWidth())
            assert.are.equals(800, sdl_fb:getScreenHeight())
            assert.are.equals(500, sdl_fb:getWidth())
            assert.are.equals(500, sdl_fb:getHeight())
            assert.True(sdl_fb.full_bb:getPixel(15, 25):getColor8() == Blitbuffer.Color8(0x00))
            assert.are.equals(update_count, #fake_sdl.update_rects)
        end)
    end)

    it("should not treat a rotated SDL backing buffer as unchanged on resize", function()
        withFakeSDLFramebuffer(function(SDLFramebuffer, fake_sdl)
            local sdl_fb = SDLFramebuffer:new{
                device = { device_dpi = 167 },
                debug = function() end,
                w = 600,
                h = 800,
            }
            sdl_fb:setViewport{x = 10, y = 20, w = 500, h = 500}
            sdl_fb:setRotationMode(sdl_fb.DEVICE_ROTATED_CLOCKWISE)
            local old_full_bb = sdl_fb.full_bb
            local old_rotation = sdl_fb.full_bb:getRotation()

            fake_sdl.win_w = 800
            fake_sdl.win_h = 600
            fake_sdl.w = 800
            fake_sdl.h = 600
            sdl_fb:resize(800, 600)

            assert.are_not.equals(old_full_bb, sdl_fb.full_bb)
            assert.are.equals(800, tonumber(sdl_fb.full_bb.w))
            assert.are.equals(600, tonumber(sdl_fb.full_bb.h))
            assert.are.equals(old_rotation, sdl_fb.full_bb:getRotation())
            assert.are.equals(800, sdl_fb:getScreenWidth())
            assert.are.equals(600, sdl_fb:getScreenHeight())
        end)
    end)

    it("should recreate the full SDL backing buffer on resize with a viewport", function()
        withFakeSDLFramebuffer(function(SDLFramebuffer, fake_sdl)
            local sdl_fb = SDLFramebuffer:new{
                device = { device_dpi = 167 },
                debug = function() end,
                w = 600,
                h = 800,
            }
            sdl_fb:setViewport{x = 10, y = 20, w = 500, h = 500}
            local old_full_bb = sdl_fb.full_bb

            fake_sdl.win_w = 800
            fake_sdl.win_h = 600
            fake_sdl.w = 800
            fake_sdl.h = 600
            sdl_fb:resize(800, 600)

            assert.are.equals(800, sdl_fb:getScreenWidth())
            assert.are.equals(600, sdl_fb:getScreenHeight())
            assert.are.equals(500, sdl_fb:getWidth())
            assert.are.equals(500, sdl_fb:getHeight())
            assert.are.equals(10, sdl_fb.viewport.x)
            assert.are.equals(20, sdl_fb.viewport.y)
            assert.are_not.equals(old_full_bb, sdl_fb.full_bb)
        end)
    end)

    it("should drop an SDL viewport that no longer fits after resize", function()
        withFakeSDLFramebuffer(function(SDLFramebuffer, fake_sdl)
            local sdl_fb = SDLFramebuffer:new{
                device = { device_dpi = 167 },
                debug = function() end,
                w = 600,
                h = 800,
            }
            sdl_fb:setViewport{x = 10, y = 20, w = 500, h = 700}

            fake_sdl.win_w = 800
            fake_sdl.win_h = 600
            fake_sdl.w = 800
            fake_sdl.h = 600
            sdl_fb:resize(800, 600)

            assert.is_nil(sdl_fb.viewport)
            assert.is_nil(sdl_fb.full_bb)
            assert.are.equals(800, sdl_fb:getWidth())
            assert.are.equals(600, sdl_fb:getHeight())
            assert.are.equals(800, sdl_fb:getScreenWidth())
            assert.are.equals(600, sdl_fb:getScreenHeight())
        end)
    end)
end)
