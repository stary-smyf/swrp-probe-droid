-- Verify the actual procedural texture path without external material files.
local file = assert(io.open("lua/autorun/probe_droid.lua", "rb"))
local source = file:read("*a")
file:close()
local first = assert(source:find("    local vignette\n", 1, true))
local last = assert(source:find("    local refreshRate =", first, true))
local pixels, alpha, builds, draws, blend, alphaWrite = {}, nil, 0, 0, false, false
local noop = function() end
local env = setmetatable({
    math = setmetatable({Clamp = function(x, a, b) return math.max(a, math.min(b, x)) end}, {__index = math}),
    FrameTime = function() return 1 / 60 end,
    Lerp = function(t, a, b) return a + (b - a) * t end,
    GetRenderTargetEx = function(_, w, h)
        assert(w == 128 and h == 128)
        builds = builds + 1
        return {GetName = function() return "radial-test" end}
    end,
    CreateMaterial = function(_, shader, params)
        assert(shader == "UnlitGeneric" and params["$basetexture"] == "radial-test")
        assert(params["$translucent"] == "1" and params["$vertexalpha"] == "1")
        return "material"
    end,
    render = {PushRenderTarget = noop, PopRenderTarget = noop, Clear = noop,
        OverrideAlphaWriteEnable = function(enabled) alphaWrite = enabled end,
        OverrideBlend = function(enabled) blend = enabled end},
    cam = {Start2D = noop, End2D = noop}, draw = {NoTexture = noop},
    surface = {
        SetDrawColor = function(_, _, _, a) alpha = a end,
        DrawRect = function(x, y) assert(blend and alphaWrite) pixels[y * 128 + x] = alpha end,
        SetMaterial = function(material) assert(material == "material") end,
        DrawTexturedRect = function(_, _, w, h)
            assert(not blend and not alphaWrite and w == 1920 and h == 1080)
            draws = draws + 1
        end
    }
}, {__index = _G})
local chunk = assert(loadstring(source:sub(first, last - 1) .. "\nreturn drawVignette"))
setfenv(chunk, env)
local drawVignette = chunk()
local probe = {stealth = false, GetStealth = function(self) return self.stealth end}
drawVignette(probe, 1920, 1080)
assert(alpha == 170 and pixels[64 * 128 + 64] == 0, "normal vignette obscures center")
assert(pixels[0] == 255 and pixels[64] > 0 and pixels[64] < 255, "radial edge falloff missing")
assert(pixels[64] == pixels[64 * 128], "gradient is not radially symmetric")
probe.stealth = true
for _ = 1, 90 do drawVignette(probe, 1920, 1080) end
assert(alpha > 254 and alpha <= 255, "stealth did not strengthen vignette")
assert(builds == 1 and draws == 91, "texture was rebuilt each frame")
print("Vignette checks passed: local texture generation, radial alpha, transparent center, caching and stealth fade")
