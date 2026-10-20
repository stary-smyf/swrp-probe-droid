-- Adapted from the Splinter Cell NVG "Thermal" preset and NVGBase.
-- See THIRD_PARTY_NOTICES.md for the source of the preset and textures.
return function(controlledProbe, thermalVision)
    if isfunction(_G.ProbeDroidNPCHeatCleanup) then _G.ProbeDroidNPCHeatCleanup() end
    -- Remove hooks left by the previous renderer during Lua auto-refresh.
    for _, event in ipairs({"PreDrawOpaqueRenderables", "PostDrawOpaqueRenderables", "ShutDown"}) do
        hook.Remove(event, "ProbeDroid.NPCHeatMask")
    end
    hook.Remove("Think", "ProbeDroid.NPCHeatMaskCleanup")

    local heatPath = "probe_droid/thermal/heat"
    -- Recover actors left tinted by the older cleanup. GetMaterial can report
    -- a replicated server material while a client-only heat override remains.
    for _, ent in ipairs(ents.GetAll()) do
        if IsValid(ent) and (ent:IsPlayer() or ent:IsNPC() or ent:IsNextBot()) then
            local material = ent:GetMaterial()
            ent:SetMaterial(material == heatPath and "" or material)
        end
    end
    local lookup = Material("probe_droid/thermal/lookup")
    local heat = Material(heatPath)
    local noise = Material("probe_droid/thermal/noise")
    local saved, nextScan, lastProbe = {}, 0, nil
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
        if heat:IsError() or lookup:IsError() or noise:IsError() then
            if not warned then
                warned = true
                ErrorNoHalt("[Probe Droid] NVG thermal materials missing; reconnect to download addon assets.\n")
            end
            return
        end
        return probe
    end
    local function eligible(ent, probe)
        return IsValid(ent) and ent ~= probe and not ent:IsDormant() and not ent:GetNoDraw()
            and ((ent:IsPlayer() and ent:Alive()) or ent:IsNPC() or ent:IsNextBot())
    end
    local function prepare(probe)
        if lastProbe ~= probe then cleanup() lastProbe = probe end
        if CurTime() < nextScan then return end
        nextScan = CurTime() + 0.25
        local present = {}
        for _, ent in ipairs(ents.GetAll()) do
            if eligible(ent, probe) then
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
            projector:SetFarZ(4096)
        end
        projector:SetPos(probe:GetCameraPosition())
        projector:SetAngles(probe.ClientViewAngles or LocalPlayer():EyeAngles())
        projector:Update()
    end)
    hook.Add("RenderScreenspaceEffects", "ProbeDroid.ThermalVision", function()
        if not activeProbe() then cleanup() return end
        -- The original preset's colour lookup, two bloom passes and ghosting.
        DrawColorModify(palette)
        DrawBloom(0.65, 3.1, 1.75, 0.45, 2, -7, 155 / 255, 155 / 255, 155 / 255)
        -- Preserve brightness-based colours without repeating the palette over the screen.
        DrawTexturize(0, lookup)
        DrawBloom(0.65, 3.1, 1.75, 0.45, 2, 1, 155 / 255, 155 / 255, 155 / 255)
        DrawMotionBlur(0.3, 1, 0)
        DrawColorModify(correction)
        cam.Start2D()
        surface.SetMaterial(noise)
        surface.SetDrawColor(155, 155, 155, 64)
        surface.DrawTexturedRect(math.Rand(-1, 1), math.Rand(-1, 1), ScrW(), ScrH())
        cam.End2D()
    end)
    hook.Add("ShutDown", "ProbeDroid.NVGThermal", cleanup)
end
