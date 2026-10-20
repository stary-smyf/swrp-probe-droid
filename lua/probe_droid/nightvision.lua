-- Adapted from Splinter Cell NVG's "Night" preset and NVGBase rendering.
-- See THIRD_PARTY_NOTICES.md. The probe retains its own controls and HUD.
return function(controlledProbe, nightVision, thermalVision, nightLight)
    if isfunction(_G.ProbeDroidNightVisionCleanup) then _G.ProbeDroidNightVisionCleanup() end
    hook.Remove("RenderScreenspaceEffects", "ProbeDroid.NightVision")
    local grain = Material("probe_droid/nightvision/grain")
    local projector, lastProbe, warned
    local photoSensitivity = 0
    local palette = {
        ["$pp_colour_addr"] = 0.1, ["$pp_colour_addg"] = 0.1, ["$pp_colour_addb"] = 0.1,
        ["$pp_colour_mulr"] = 0, ["$pp_colour_mulg"] = 0, ["$pp_colour_mulb"] = 0,
        ["$pp_colour_brightness"] = -0.04, ["$pp_colour_contrast"] = 1.5,
        ["$pp_colour_colour"] = 0
    }
    local function removeLight()
        if IsValid(projector) then projector:Remove() end
        projector = nil
    end
    local function cleanup()
        removeLight()
        photoSensitivity, lastProbe = 0, nil
    end
    _G.ProbeDroidNightVisionCleanup = cleanup
    cvars.AddChangeCallback("probe_droid_nightvision", function(_, _, value)
        if tonumber(value) == 0 then cleanup() end
    end, "ProbeDroid.NightVisionCleanup")
    cvars.AddChangeCallback("probe_droid_thermal", function(_, _, value)
        if tonumber(value) ~= 0 then cleanup() end
    end, "ProbeDroid.NightVisionCleanup")
    local function activeProbe()
        -- Control lookup resets sensors before a new flight's first render.
        local probe = controlledProbe(LocalPlayer())
        if probe and nightVision:GetBool() and not thermalVision:GetBool() then return probe end
    end
    local function prepare(probe)
        if lastProbe ~= probe then cleanup() lastProbe = probe end
    end
    hook.Add("Think", "ProbeDroid.NVGNightVision", function()
        local probe = activeProbe()
        if not probe then cleanup() return end
        prepare(probe)
        if not nightLight:GetBool() then removeLight() return end
        if not IsValid(projector) then
            projector = ProjectedTexture()
            if not IsValid(projector) then return end
            projector:SetTexture("effects/flashlight/soft")
            projector:SetEnableShadows(false)
            projector:SetFOV(140)
            projector:SetVerticalFOV(100)
            projector:SetBrightness(2)
            projector:SetFarZ(2500)
        end
        projector:SetPos(probe:GetCameraPosition())
        projector:SetAngles(probe.ClientViewAngles or LocalPlayer():EyeAngles())
        projector:Update()
    end)
    hook.Add("RenderScreenspaceEffects", "ProbeDroid.NightVision", function()
        local probe = activeProbe()
        if not probe then cleanup() return end
        prepare(probe)
        -- Match the preset's bloom order and camera-local light adaptation.
        DrawBloom(0.65, 3.1, 1.75, 0.45, 2, 1, 155 / 255, 155 / 255, 155 / 255)
        DrawBloom(0.1, 2, 0.5, 0.25, 1, 0.6, 130 / 255, 135 / 255, 35 / 255)
        local light = render.GetLightColor(probe:GetCameraPosition())
        local intensity = (light.x + light.y + light.z) / 3
        photoSensitivity = Lerp(math.Clamp(FrameTime() * 2, 0, 1), photoSensitivity, intensity)
        palette["$pp_colour_brightness"] = -0.04 + photoSensitivity
        DrawColorModify(palette)
        if grain:IsError() then
            -- Keep a red image if the client has not received the grain yet.
            cam.Start2D()
            render.OverrideBlend(true, BLEND_ZERO, BLEND_SRC_COLOR, BLENDFUNC_ADD,
                BLEND_ZERO, BLEND_ONE, BLENDFUNC_ADD)
            draw.NoTexture()
            surface.SetDrawColor(255, 45, 25, 255)
            surface.DrawRect(0, 0, ScrW(), ScrH())
            render.OverrideBlend(false)
            cam.End2D()
            if not warned then
                warned = true
                ErrorNoHalt("[Probe Droid night vision] NVG grain material missing; reconnect to download it.\n")
            end
            return
        end
        cam.Start2D()
        surface.SetMaterial(grain)
        surface.SetDrawColor(255, 45, 25, 80)
        surface.DrawTexturedRect(math.Rand(-1, 1), math.Rand(-1, 1), ScrW(), ScrH())
        cam.End2D()
    end)
    hook.Add("ShutDown", "ProbeDroid.NVGNightVision", cleanup)
end
