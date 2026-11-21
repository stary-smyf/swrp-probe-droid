-- Adapted from the Splinter Cell NVG "Thermal" preset and NVGBase.
-- See THIRD_PARTY_NOTICES.md for the source of the preset and textures.
return function(controlledProbe, thermalVision)
    if isfunction(_G.ProbeDroidNPCHeatCleanup) then _G.ProbeDroidNPCHeatCleanup() end
    -- Remove hooks left by the previous renderer during Lua auto-refresh.
    for _, event in ipairs({"PreDrawOpaqueRenderables", "PostDrawOpaqueRenderables", "ShutDown"}) do
        hook.Remove(event, "ProbeDroid.NPCHeatMask")
    end
    hook.Remove("Think", "ProbeDroid.NPCHeatMaskCleanup")
    hook.Remove("PostDrawTranslucentRenderables", "ProbeDroid.VehicleHeat")

    local legacyHeatPath = "probe_droid/thermal/heat"
    local heatName = "probe_droid_thermal_unlit_v1"
    local heatPath = "!" .. heatName
    -- A model-compatible unlit material keeps the heat animation independent
    -- of ambient light and the projected illuminator's distance attenuation.
    -- Build it in Lua so clients cannot retain an older cached lit VMT.
    local heat = CreateMaterial(heatName, "UnlitGeneric", {
        ["$basetexture"] = "probe_droid/thermal/heat",
        ["$model"] = "1",
        ["Proxies"] = {AnimatedTexture = {
            animatedtexturevar = "$basetexture", animatedtextureframenumvar = "$frame",
            animatedtextureframerate = "60"
        }}
    })
    local vehicleHeat = CreateMaterial("probe_droid_vehicle_heat_unlit_v1", "UnlitGeneric", {
        ["$basetexture"] = "probe_droid/thermal/heat",
        ["$model"] = "1",
        ["$color2"] = "[2 2 2]",
        ["Proxies"] = {AnimatedTexture = {
            animatedtexturevar = "$basetexture", animatedtextureframenumvar = "$frame",
            animatedtextureframerate = "60"
        }}
    })
    local function isVehicle(ent)
        return ent:IsVehicle() or ent.LVS or ent.LFS or ent.IsSimfphyscar
    end
    local function isHeatSource(ent)
        -- Scripted vehicle bodies are often separate from their vehicle seats.
        return ent:IsPlayer() or ent:IsNPC() or ent:IsNextBot() or isVehicle(ent)
    end
    -- Recover actors left tinted by the older cleanup. GetMaterial can report
    -- a replicated server material while a client-only heat override remains.
    for _, ent in ipairs(ents.GetAll()) do
        if IsValid(ent) and isHeatSource(ent) then
            local material = ent:GetMaterial()
            ent:SetMaterial((material == heatPath or material == legacyHeatPath) and "" or material)
        end
    end
    local lookup = Material("probe_droid/thermal/lookup")
    local heatAsset = Material(legacyHeatPath)
    local noise = Material("probe_droid/thermal/noise")
    local saved, nextScan, lastProbe = {}, 0, nil
    local vehicleParts = {}
    local grassMaterials = nil
    local terrainMaterialStatus
    local environmentTexture, environmentMaterial, environmentWidth, environmentHeight
    local projector, warned
    local heatColor = Color(255, 255, 255, 254)
    local palette = {
        ["$pp_colour_addr"] = 0, ["$pp_colour_addg"] = 0, ["$pp_colour_addb"] = 0,
        ["$pp_colour_mulr"] = 15.5, ["$pp_colour_mulg"] = 11, ["$pp_colour_mulb"] = 4.5,
        ["$pp_colour_brightness"] = 0.04, ["$pp_colour_contrast"] = 0.15,
        ["$pp_colour_colour"] = 0
    }
    local correction = {
        ["$pp_colour_addr"] = 0, ["$pp_colour_addg"] = 0, ["$pp_colour_addb"] = 0,
        ["$pp_colour_mulr"] = 0, ["$pp_colour_mulg"] = 0, ["$pp_colour_mulb"] = 0,
        ["$pp_colour_brightness"] = 0.01, ["$pp_colour_contrast"] = 2,
        ["$pp_colour_colour"] = 1
    }
    local function rememberGrass(material, confirmedGrass)
        if not material or material:IsError() or grassMaterials[material] then return end
        local surfaceProp = string.lower((material:GetString("$surfaceprop") or "") .. " "
            .. (material:GetString("$surfaceprop2") or ""))
        local description = string.lower(material:GetName() .. " "
            .. (material:GetString("$basetexture") or "") .. " "
            .. (material:GetString("$basetexture2") or ""))
        if confirmedGrass or string.find(surfaceProp, "grass", 1, true)
            or string.find(description, "grass", 1, true) then
            grassMaterials[material] = true
        end
    end
    local function readTerrainMaterials()
        -- Displacements are not reliably exposed by GetBrushSurfaces, and
        -- TraceLine reports "**displacement**" instead of their material name.
        -- Read only the BSP texture-name lump, never the entire map/embedded pak.
        local bsp = file.Open("maps/" .. game.GetMap() .. ".bsp", "rb", "GAME")
        if not bsp then return "BSP unavailable" end
        if bsp:Read(4) ~= "VBSP" then bsp:Close() return "Invalid BSP header" end
        bsp:Seek(8 + 43 * 16) -- LUMP_TEXDATA_STRING_DATA
        local offset, length = bsp:ReadLong(), bsp:ReadLong()
        if not offset or not length or offset < 1036 or length < 0
            or length > 16 * 1024 * 1024 or offset + length > bsp:Size() then
            bsp:Close()
            return "Invalid BSP texture-name lump"
        end
        bsp:Seek(offset)
        local names = bsp:Read(length) or ""
        bsp:Close()
        if string.sub(names, 1, 4) == "LZMA" then
            return "Compressed BSP texture-name lump; brush materials only"
        end
        local count = 0
        for name in string.gmatch(names, "[^%z]+") do
            rememberGrass(Material(name))
            count = count + 1
        end
        return "Read " .. count .. " BSP material names"
    end
    local terrainRecovered = false
    local function recoverTerrainMaterials()
        if terrainRecovered then return end
        grassMaterials = {}
        terrainMaterialStatus = readTerrainMaterials()
        -- Recover colours left in the material cache by the previous renderer.
        -- Use the original VMT rather than a possibly already-darkened snapshot.
        for material in pairs(grassMaterials) do
            local source = file.Read("materials/" .. material:GetName() .. ".vmt", "GAME")
            local values = source and util.KeyValuesToTable(source)
            if values and not values.include then
                for _, key in ipairs({"$color", "$color2", "$selfillumtint", "$envmaptint"}) do
                    if material:GetVector(key) then
                        local value = values[key]
                        local original = Vector(1, 1, 1)
                        if isstring(value) then
                            local x, y, z = string.match(value,
                                "([%+%-%.%deE]+)%s+([%+%-%.%deE]+)%s+([%+%-%.%deE]+)")
                            if x and tonumber(x) and tonumber(y) and tonumber(z) then
                                local scale = string.find(value, "{", 1, true) and 1 / 255 or 1
                                original = Vector(tonumber(x) * scale, tonumber(y) * scale, tonumber(z) * scale)
                            end
                        elseif isnumber(value) then
                            original = Vector(value, value, value)
                        end
                        material:SetVector(key, original)
                    end
                end
                material:Recompute()
            end
        end
        terrainRecovered = string.sub(terrainMaterialStatus, 1, 5) == "Read "
    end
    local function restore(ent, record)
        if not IsValid(ent) then return end
        -- Always reapply the reported normal material; a server-priority getter
        -- does not prove that the client's heat override has already gone away.
        local material = ent:GetMaterial()
        ent:SetMaterial(material == heatPath and record.material or material)
        local mode = ent:GetRenderMode()
        ent:SetRenderMode(mode == RENDERMODE_GLOW and record.mode or mode)
        local color = ent:GetColor()
        if color.r == 255 and color.g == 255 and color.b == 255 and color.a == 254 then
            color = record.color
        end
        ent:SetColor(color)
    end
    local function cleanup()
        for ent, record in pairs(saved) do restore(ent, record) end
        saved, lastProbe, nextScan = {}, nil, 0
        vehicleParts = {}
        if IsValid(projector) then projector:Remove() end
        projector = nil
    end
    _G.ProbeDroidNPCHeatCleanup = cleanup
    cvars.AddChangeCallback("probe_droid_thermal", function(_, _, value)
        if tonumber(value) == 0 then cleanup() end
    end, "ProbeDroid.ThermalCleanup")
    local function activeProbe()
        local probe = controlledProbe(LocalPlayer())
        if not probe or not thermalVision:GetBool() then return end
        -- Never cover the view with an error material if downloads are missing.
        if heat:IsError() or vehicleHeat:IsError() or heatAsset:IsError() or lookup:IsError() or noise:IsError() then
            if not warned then
                warned = true
                ErrorNoHalt("[Probe Droid] NVG thermal materials missing; reconnect to download addon assets.\n")
            end
            return
        end
        return probe
    end
    local inspectRequested = false
    concommand.Add("probe_droid_thermal_inspect", function()
        if not activeProbe() then
            print("[Probe Droid IR] Enable thermal vision while piloting the probe first.")
            return
        end
        inspectRequested = true
    end)
    local function inspectGround(probe)
        local position = probe:GetCameraPosition()
        local angles = probe.ClientViewAngles or LocalPlayer():EyeAngles()
        local trace = util.TraceLine({start = position, endpos = position + angles:Forward() * 16384,
            filter = {probe, LocalPlayer()}, mask = MASK_SOLID_BRUSHONLY})
        print("[Probe Droid IR] Ground under the centre of the view: " .. tostring(trace.HitTexture))
        if not trace.Hit or not trace.HitTexture then return end
        local materials = {}
        if trace.HitTexture == "**displacement**" then
            print("[Probe Droid IR] " .. (terrainMaterialStatus or "BSP materials not scanned"))
            print("[Probe Droid IR] Grass terrain candidates from the map (not an exact face lookup):")
            for material in pairs(grassMaterials or {}) do materials[#materials + 1] = material end
            table.sort(materials, function(a, b) return a:GetName() < b:GetName() end)
        elseif string.sub(trace.HitTexture, 1, 2) ~= "**" then
            local material = Material(trace.HitTexture)
            if not material:IsError() then materials[1] = material end
        end
        if #materials == 0 then print("[Probe Droid IR] No valid terrain material resolved.") end
        for _, material in ipairs(materials) do
            print("[Probe Droid IR] Material: " .. material:GetName() .. "; shader: " .. material:GetShader()
                .. "; environment cooling: framebuffer")
            for _, key in ipairs({"$basetexture", "$basetexture2", "$surfaceprop", "$surfaceprop2"}) do
                print("[Probe Droid IR] " .. key .. " = " .. tostring(material:GetString(key) or "<unset>"))
            end
            for _, key in ipairs({"$color", "$color2"}) do
                print("[Probe Droid IR] " .. key .. " = " .. tostring(material:GetVector(key) or "<unset>"))
            end
        end
        print("[Probe Droid IR] Pixel samples include all geometry at the centre, including grass models.")
    end
    local function inspectPixel(stage)
        -- Synchronous GPU readback is deliberately limited to one requested frame.
        render.CapturePixels()
        local r, g, b = render.ReadPixel(math.floor(ScrW() / 2), math.floor(ScrH() / 2))
        print(string.format("[Probe Droid IR] %-18s RGB = %d, %d, %d", stage, r, g, b))
    end
    local function eligible(ent, probe)
        return IsValid(ent) and ent ~= probe and not ent:IsDormant() and not ent:GetNoDraw()
            and isHeatSource(ent) and (not ent:IsPlayer() or ent:Alive())
    end
    local function collectVehicleParts(ent, probe, visited)
        if not IsValid(ent) or ent == probe or ent:IsDormant() or visited[ent] then return end
        -- Do not include passengers or their equipment in the vehicle pass.
        if ent:IsPlayer() or ent:IsNPC() or ent:IsNextBot() or ent:IsWeapon() then return end
        visited[ent] = true
        local model = ent:GetModel()
        if not ent:GetNoDraw() and model and model ~= "" then
            vehicleParts[ent] = true
        end
        for _, child in ipairs(ent:GetChildren()) do
            collectVehicleParts(child, probe, visited)
        end
    end
    local function prepare(probe)
        if lastProbe ~= probe then cleanup() lastProbe = probe end
        if CurTime() < nextScan then return end
        nextScan = CurTime() + 0.25
        local present = {}
        vehicleParts = {}
        local visited = {}
        for _, ent in ipairs(ents.GetAll()) do
            if IsValid(ent) and isVehicle(ent) then
                collectVehicleParts(ent, probe, visited)
            elseif eligible(ent, probe) then
                present[ent] = true
                if not saved[ent] then
                    local color = ent:GetColor()
                    saved[ent] = {material = ent:GetMaterial(), mode = ent:GetRenderMode(),
                        color = Color(color.r, color.g, color.b, color.a)}
                    ent:SetMaterial(heatPath)
                    ent:SetRenderMode(RENDERMODE_GLOW)
                    ent:SetColor(heatColor)
                end
            end
        end
        for ent, record in pairs(saved) do
            if not present[ent] then restore(ent, record) saved[ent] = nil end
        end
    end
    hook.Add("PreDrawOpaqueRenderables", "ProbeDroid.NVGThermal", function(depth, sky)
        if depth or sky then return end
        local probe = activeProbe()
        if probe then prepare(probe) else cleanup() end
    end)
    local function captureEnvironment()
        local width, height = ScrW(), ScrH()
        if environmentWidth ~= width or environmentHeight ~= height then
            local name = "probe_droid_thermal_environment_" .. width .. "x" .. height
            environmentTexture = GetRenderTargetEx(name, width, height, RT_SIZE_NO_CHANGE,
                MATERIAL_RT_DEPTH_NONE, bit.bor(4, 8), 0, IMAGE_FORMAT_RGBA8888)
            environmentMaterial = CreateMaterial(name .. "_copy", "UnlitGeneric", {
                ["$basetexture"] = environmentTexture:GetName(),
                ["$ignorez"] = "1", ["$vertexcolor"] = "1", ["$vertexalpha"] = "1"
            })
            environmentWidth, environmentHeight = width, height
        end
        -- Preserve the actual map textures and shadows before reducing the
        -- scene brightness for the heat palette.
        render.CopyRenderTargetToTexture(environmentTexture)
    end
    local function drawEnvironmentDetails()
        -- Add the preserved texture detail in a cold red range after the hot
        -- palette. It cannot be promoted to yellow by either bloom pass.
        -- Exclude source silhouettes, while leaving their existing glow intact.
        render.SetStencilEnable(true)
        render.SetStencilWriteMask(0)
        render.SetStencilReferenceValue(1)
        render.SetStencilCompareFunction(STENCILCOMPARISONFUNCTION_NOTEQUAL)
        render.SetStencilPassOperation(STENCILOPERATION_KEEP)
        cam.Start2D()
        render.OverrideBlend(true, BLEND_ONE, BLEND_ONE, BLENDFUNC_ADD,
            BLEND_ZERO, BLEND_ONE, BLENDFUNC_ADD)
        surface.SetMaterial(environmentMaterial)
        surface.SetDrawColor(95, 42, 30, 255)
        surface.DrawTexturedRect(0, 0, ScrW(), ScrH())
        render.OverrideBlend(false)
        cam.End2D()
        render.SetStencilEnable(false)
        render.SetStencilWriteMask(255)
    end
    local function drawThermalScene(probe)
        -- Cool the framebuffer, not shared map materials. This covers terrain,
        -- static foliage, decals, signs and emissive decorations at any distance.
        cam.Start2D()
        render.OverrideBlend(true, BLEND_ZERO, BLEND_SRC_COLOR, BLENDFUNC_ADD,
            BLEND_ZERO, BLEND_ONE, BLENDFUNC_ADD)
        draw.NoTexture()
        surface.SetDrawColor(4, 4, 4, 255)
        surface.DrawRect(0, 0, ScrW(), ScrH())
        render.OverrideBlend(false)
        cam.End2D()

        -- Redraw only real heat sources before the original palette/bloom.
        -- Keep the scene depth: actors behind walls stay hidden. Applying bloom
        -- afterwards preserves the soft glow beyond the model silhouette.
        local blend = render.GetBlend()
        local r, g, b = render.GetColorModulation()
        render.ClearStencil()
        render.SetStencilWriteMask(255)
        render.SetStencilTestMask(255)
        render.SetStencilReferenceValue(1)
        render.SetStencilCompareFunction(STENCILCOMPARISONFUNCTION_ALWAYS)
        render.SetStencilFailOperation(STENCILOPERATION_KEEP)
        render.SetStencilZFailOperation(STENCILOPERATION_KEEP)
        render.SetStencilPassOperation(STENCILOPERATION_REPLACE)
        render.SetStencilEnable(true)
        cam.Start3D()
        render.OverrideDepthEnable(true, false)
        render.SetBlend(1)
        render.SetColorModulation(1, 1, 1)
        render.MaterialOverride(heat)
        for ent in pairs(saved) do
            if eligible(ent, probe) then ent:DrawModel() end
        end
        render.MaterialOverride(vehicleHeat)
        for ent in pairs(vehicleParts) do
            if IsValid(ent) and not ent:IsDormant() and not ent:GetNoDraw() then
                ent:DrawModel()
            end
        end
        render.MaterialOverride()
        render.SetColorModulation(r, g, b)
        render.SetBlend(blend)
        render.OverrideDepthEnable(false)
        cam.End3D()
        render.SetStencilEnable(false)
    end
    hook.Add("Think", "ProbeDroid.NVGThermal", function()
        local probe = activeProbe()
        if not probe then cleanup() return end
        prepare(probe)
        -- Match the NVG preset's broad illuminator, following the drone camera.
        if not IsValid(projector) then
            projector = ProjectedTexture()
            if not IsValid(projector) then return end
            projector:SetTexture("effects/flashlight/soft")
            projector:SetEnableShadows(false)
            projector:SetFOV(179)
            projector:SetVerticalFOV(179)
            projector:SetBrightness(3)
            -- Keep distant heat targets illuminated as well as nearby actors.
            projector:SetFarZ(16384)
        end
        projector:SetPos(probe:GetCameraPosition())
        projector:SetAngles(probe.ClientViewAngles or LocalPlayer():EyeAngles())
        projector:Update()
    end)
    hook.Add("RenderScreenspaceEffects", "ProbeDroid.ThermalVision", function()
        local probe = activeProbe()
        if not probe then inspectRequested = false cleanup() return end
        local inspect = inspectRequested
        inspectRequested = false
        if inspect then inspectGround(probe) inspectPixel("scene") end
        captureEnvironment()
        drawThermalScene(probe)
        if inspect then inspectPixel("cooled scene + heat") end
        -- The original preset's colour lookup, two bloom passes and ghosting.
        DrawColorModify(palette)
        if inspect then inspectPixel("colour modify") end
        DrawBloom(0.65, 3.1, 1.75, 0.45, 2, -7, 155 / 255, 155 / 255, 155 / 255)
        if inspect then inspectPixel("negative bloom") end
        -- Preserve brightness-based colours without repeating the palette over the screen.
        DrawTexturize(0, lookup)
        if inspect then inspectPixel("lookup") end
        DrawBloom(0.65, 3.1, 1.75, 0.45, 2, 1, 155 / 255, 155 / 255, 155 / 255)
        if inspect then inspectPixel("positive bloom") end
        DrawMotionBlur(0.3, 1, 0)
        if inspect then inspectPixel("motion blur") end
        DrawColorModify(correction)
        if inspect then inspectPixel("final correction") end
        drawEnvironmentDetails()
        if inspect then inspectPixel("environment detail") end
        cam.Start2D()
        surface.SetMaterial(noise)
        surface.SetDrawColor(155, 155, 155, 64)
        surface.DrawTexturedRect(math.Rand(-1, 1), math.Rand(-1, 1), ScrW(), ScrH())
        cam.End2D()
    end)
    recoverTerrainMaterials()
    hook.Add("InitPostEntity", "ProbeDroid.ThermalMaterialRecovery", function()
        terrainRecovered = false
        recoverTerrainMaterials()
    end)
    hook.Add("ShutDown", "ProbeDroid.NVGThermal", cleanup)
end
