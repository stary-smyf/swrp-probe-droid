if SERVER then
    AddCSLuaFile()
    AddCSLuaFile("autorun/client/probe_droid_audio.lua")
    resource.AddFile("materials/entities/weapon_probe_droid.png")
    for _, name in ipairs({"probedroidhover.wav", "probedroidspeak1.wav",
        "probedroidspeak2.wav", "probedroidspeak3.wav"}) do
        resource.AddFile("sound/probe_droid/" .. name)
    end
    CreateConVar("probe_droid_battery", "120", FCVAR_ARCHIVE, "Probe battery lifetime in seconds (new flights).", 5, 3600)
    CreateConVar("probe_droid_range", "5000", FCVAR_ARCHIVE, "Maximum distance from launch point in Source units (new flights).", 128, 100000)
    local rangeMigrated = CreateConVar("probe_droid_range_migrated_5000", "0", FCVAR_ARCHIVE,
        "Internal marker for the one-time upgrade of the old 3000-unit range.", 0, 1)
    -- Archived values survive changes to CreateConVar's default. Wait until
    -- startup configuration has run; also handles Lua refresh on a live server.
    timer.Simple(0, function()
        if rangeMigrated:GetBool() then return end
        local range = GetConVar("probe_droid_range")
        if range:GetFloat() == 3000 then
            range:SetFloat(5000)
            for _, probe in ipairs(ents.FindByClass("sent_probe_droid")) do
                if probe:GetMaxRange() == 3000 then probe:SetMaxRange(5000) end
            end
        end
        rangeMigrated:SetBool(true)
    end)
    CreateConVar("probe_droid_speed", "350", FCVAR_ARCHIVE, "Normal probe speed in units per second; boost is 1.8x.", 50, 2000)
    CreateConVar("probe_droid_health", "60", FCVAR_ARCHIVE, "Probe health (new flights).", 1, 10000)
end

local function controlledProbe(ply)
    if not IsValid(ply) then return end
    local probe = ply:GetNW2Entity("ProbeDroidControlled")
    -- An entity reference can arrive before the client installs its SENT methods
    -- and data table accessors. Wait for that initialization before using it.
    if IsValid(probe) and probe:GetClass() == "sent_probe_droid"
        and isfunction(probe.GetCameraPosition) and isfunction(probe.GetCameraOffset)
        and isfunction(probe.GetPilot) and probe:GetPilot() == ply then
        return probe
    end
end

if SERVER then
    util.AddNetworkString("ProbeDroid.SensorMode")
    net.Receive("ProbeDroid.SensorMode", function(_, ply)
        local probe = controlledProbe(ply)
        if not probe then return end
        local mode = net.ReadUInt(2)
        if mode > 2 or mode == (probe.SensorMode or 0) then return end
        -- Charge time spent in the old sensor mode before applying the new one.
        probe:UpdateBatteryDrain()
        probe.SensorMode = mode
    end)
end

hook.Add("StartCommand", "ProbeDroid.FlightInput", function(ply, cmd)
    local probe = controlledProbe(ply)
    if not probe then return end

    if CLIENT then
        local angles = cmd:GetViewAngles()
        probe.ClientViewAngles = Angle(angles.p, angles.y, 0)
    end

    if SERVER then
        local now = CurTime()
        if cmd:KeyDown(IN_USE) and not cmd:IsForced() and now - probe.ControlStarted > 0.5 then
            -- A release or missing input cancels progress; stale backup
            -- commands must not finish an exit while the pilot is disconnected.
            if not probe.ExitHoldStarted or now - probe.LastExitCommand > 0.25 then
                probe.ExitHoldStarted = now
                probe:SetNW2Float("ProbeDroidExitEnd", now + 2)
            end
            probe.LastExitCommand = now
        elseif probe.ExitHoldStarted then
            probe.ExitHoldStarted, probe.LastExitCommand = nil, nil
            probe:SetNW2Float("ProbeDroidExitEnd", 0)
        end
        if probe.ExitHoldStarted and now - probe.ExitHoldStarted >= 2 then
            probe:DestroyProbe("flight ended by pilot")
        else
            local stealthDown = cmd:KeyDown(IN_ATTACK2)
            if stealthDown and not probe.StealthKeyDown then
                probe:SetStealthMode(not probe:GetStealth())
            end
            probe.StealthKeyDown = stealthDown
            local angles = cmd:GetViewAngles()
            local direction = Vector(0, 0, 0)
            if cmd:KeyDown(IN_FORWARD) then direction = direction + angles:Forward() end
            if cmd:KeyDown(IN_BACK) then direction = direction - angles:Forward() end
            if cmd:KeyDown(IN_MOVERIGHT) then direction = direction + angles:Right() end
            if cmd:KeyDown(IN_MOVELEFT) then direction = direction - angles:Right() end
            if cmd:KeyDown(IN_JUMP) then direction.z = direction.z + 1 end
            if cmd:KeyDown(IN_DUCK) then direction.z = direction.z - 1 end
            if direction:LengthSqr() > 1 then direction:Normalize() end
            probe.InputDirection = direction
            probe.FlightAngles = angles
            probe.Boosting = cmd:KeyDown(IN_SPEED)
            probe.LastInputTime = CurTime()
        end
    end

    -- Client commands still need to reach the server with their flight inputs.
    -- Clear them only after the server reads them; MOVETYPE_NONE holds the body.
    if SERVER then
        cmd:ClearMovement()
        cmd:ClearButtons()
        -- The command angles steer the drone, but must not turn the pilot.
        if probe.PreviousEyeAngles then
            cmd:SetViewAngles(probe.PreviousEyeAngles)
        end
    else
        -- Keep secondary attack in the transmitted command for stealth.
        -- The controller's SecondaryAttack is empty, so prediction is harmless;
        -- the server clears it above after reading the toggle.
        cmd:RemoveKey(IN_ATTACK)
        cmd:RemoveKey(IN_RELOAD)
    end
    cmd:SetImpulse(0)
    local weapon = ply:GetActiveWeapon()
    if IsValid(weapon) then cmd:SelectWeapon(weapon) end
end)

hook.Add("PlayerSwitchWeapon", "ProbeDroid.BlockSwitch", function(ply)
    if controlledProbe(ply) then return true end
end)

if SERVER then
    local function removeProbe(ply)
        local probe = controlledProbe(ply)
        if probe then probe:DestroyProbe() end
    end
    hook.Add("PlayerDeath", "ProbeDroid.PilotDeath", removeProbe)
    hook.Add("PlayerSilentDeath", "ProbeDroid.PilotSilentDeath", removeProbe)
    hook.Add("PlayerDisconnected", "ProbeDroid.PilotDisconnected", removeProbe)
    hook.Add("PlayerSpawn", "ProbeDroid.PilotSpawn", removeProbe)
    hook.Add("CanPlayerEnterVehicle", "ProbeDroid.BlockVehicle", function(ply)
        if controlledProbe(ply) then return false end
    end)
    hook.Add("PlayerNoClip", "ProbeDroid.BlockNoclip", function(ply)
        if controlledProbe(ply) then return false end
    end)
    hook.Add("SetupPlayerVisibility", "ProbeDroid.Visibility", function(ply)
        local probe = controlledProbe(ply)
        if probe then AddOriginToPVS(probe:GetCameraPosition()) end
    end)
    hook.Add("PhysgunPickup", "ProbeDroid.NoPhysgun", function(_, ent)
        if ent:GetClass() == "sent_probe_droid" then return false end
    end)
    hook.Add("CanTool", "ProbeDroid.NoTool", function(_, trace)
        if IsValid(trace.Entity) and trace.Entity:GetClass() == "sent_probe_droid" then return false end
    end)
    hook.Add("CanProperty", "ProbeDroid.NoProperty", function(_, _, ent)
        if ent:GetClass() == "sent_probe_droid" then return false end
    end)
    return
end

-- Restore temporary entity hooks before replacing this file during hot reload.
if isfunction(_G.ProbeDroidNPCHeatCleanup) then _G.ProbeDroidNPCHeatCleanup() end
local cameraSway = CreateClientConVar("probe_droid_camera_sway", "1", true, false,
    "Drone camera banking and flight sway strength (0 disables it).", 0, 1)
local flightCamera
local zoomLevels = {1, 3, 6}
local function zoomFactor(probe)
    return zoomLevels[probe.ClientZoomLevel or 1] or 1
end
hook.Add("PlayerBindPress", "ProbeDroid.Zoom", function(ply, bind, pressed)
    local probe = controlledProbe(ply)
    if not probe or string.lower(bind) ~= "+attack" then return end
    if pressed then
        probe.ClientZoomLevel = (probe.ClientZoomLevel or 1) % #zoomLevels + 1
        surface.PlaySound("buttons/lightswitch2.wav")
    end
    return true
end)
hook.Add("AdjustMouseSensitivity", "ProbeDroid.Zoom", function()
    local probe = controlledProbe(LocalPlayer())
    if probe then return 1 / zoomFactor(probe) end
end)
hook.Add("CalcView", "ProbeDroid.FirstPerson", function(ply, _, _, fov)
    local probe = controlledProbe(ply)
    if not probe then flightCamera = nil return end
    local steering = probe.ClientViewAngles or ply:EyeAngles()
    local angles = Angle(steering.p, steering.y, 0)
    if not flightCamera or flightCamera.probe ~= probe then
        flightCamera = {probe = probe, velocity = Vector(0, 0, 0), pitch = 0, roll = 0}
    end
    local state = flightCamera
    if state.frame ~= FrameNumber() then
        state.frame = FrameNumber()
        local dt = math.Clamp(FrameTime(), 0.001, 0.1)
        local blend = 1 - math.exp(-dt * 8)
        local velocity = LerpVector(blend, state.velocity, probe:GetNW2Vector("ProbeDroidVelocity", vector_origin))
        local acceleration = (velocity - state.velocity) / dt
        local forward, right = angles:Forward(), angles:Right()
        local motion = math.Clamp(velocity:Length() / 350, 0, 1.8)
        local pitch = math.Clamp(-velocity:Dot(forward) / 350 * 1.2
            - acceleration:Dot(forward) / 700, -3, 3)
        local roll = math.Clamp(velocity:Dot(right) / 350 * 2.5
            + acceleration:Dot(right) / 500, -5, 5)
        local time = CurTime()
        pitch = pitch + math.sin(time * 2.3) * 0.18 * motion
        roll = roll + math.sin(time * 1.7) * 0.25 * motion
        state.pitch = Lerp(blend, state.pitch, pitch)
        state.roll = Lerp(blend, state.roll, roll)
        state.velocity = velocity
    end
    angles.p = angles.p + state.pitch * cameraSway:GetFloat()
    angles.r = state.roll * cameraSway:GetFloat()
    return {
        origin = probe:GetCameraPosition(),
        angles = angles,
        -- Divide the projected image width for true optical magnification.
        fov = math.deg(2 * math.atan(math.tan(math.rad(fov) * 0.5) / zoomFactor(probe))),
        znear = 2,
        drawviewer = true
    }
end)

local thermalVision = CreateClientConVar("probe_droid_thermal", "0", true, false,
    "Enable red-hot thermovision while piloting a probe droid.")
local nightVision = CreateClientConVar("probe_droid_nightvision", "0", true, false,
    "Enable green low-light night vision while piloting a probe droid.")
local nightLight = CreateClientConVar("probe_droid_nightvision_light", "1", true, false,
    "Enable the short-range night-vision illuminator (disable to save GPU work).")

do
    local lastProbe, lastMode
    hook.Add("Think", "ProbeDroid.SensorBatteryMode", function()
        local probe = controlledProbe(LocalPlayer())
        if not probe then lastProbe, lastMode = nil, nil return end
        local mode = thermalVision:GetBool() and 1 or nightVision:GetBool() and 2 or 0
        if probe == lastProbe and mode == lastMode then return end
        net.Start("ProbeDroid.SensorMode")
        net.WriteUInt(mode, 2)
        net.SendToServer()
        lastProbe, lastMode = probe, mode
    end)
end

-- Keep console commands and keyboard toggles consistent: one sensor at a time.
cvars.AddChangeCallback("probe_droid_thermal", function(_, _, value)
    if tonumber(value) ~= 0 and nightVision:GetBool() then
        RunConsoleCommand("probe_droid_nightvision", "0")
    end
end, "ProbeDroid.SensorMode")
cvars.AddChangeCallback("probe_droid_nightvision", function(_, _, value)
    if tonumber(value) ~= 0 and thermalVision:GetBool() then
        RunConsoleCommand("probe_droid_thermal", "0")
    end
end, "ProbeDroid.SensorMode")
if thermalVision:GetBool() and nightVision:GetBool() then
    RunConsoleCommand("probe_droid_nightvision", "0")
end

local function toggleNightVision()
    if not controlledProbe(LocalPlayer()) then return end
    RunConsoleCommand("probe_droid_nightvision", nightVision:GetBool() and "0" or "1")
    surface.PlaySound("buttons/lightswitch2.wav")
end
concommand.Add("probe_droid_toggle_nightvision", toggleNightVision)

local function tintSensorImage(r, g, b)
    -- Multiply the existing image directly instead of copying and sampling
    -- the full framebuffer again. Keep its alpha unchanged for other effects.
    cam.Start2D()
    render.OverrideBlend(true, BLEND_ZERO, BLEND_SRC_COLOR, BLENDFUNC_ADD,
        BLEND_ZERO, BLEND_ONE, BLENDFUNC_ADD)
    draw.NoTexture()
    surface.SetDrawColor(r, g, b, 255)
    surface.DrawRect(0, 0, ScrW(), ScrH())
    render.OverrideBlend(false)
    cam.End2D()
end

do
    local wasDown, hadLight, lightKey, nextLight = false, false, 0, 0
    hook.Add("Think", "ProbeDroid.NightVisionInput", function()
        local down = input.IsKeyDown(KEY_N)
        local ply = LocalPlayer()
        local probe = controlledProbe(ply)
        if probe and down and not wasDown and not vgui.CursorVisible()
            and not IsValid(vgui.GetKeyboardFocus()) and not gui.IsConsoleVisible()
            and not gui.IsGameUIVisible() then
            toggleNightVision()
        end
        wasDown = down
        if probe and nightVision:GetBool() and not thermalVision:GetBool() and nightLight:GetBool() then
            if RealTime() < nextLight then return end
            nextLight = RealTime() + 0.05
            lightKey = 524288 + ply:EntIndex()
            local light = DynamicLight(lightKey)
            if light then
                light.pos = probe:GetCameraPosition()
                light.r, light.g, light.b = 210, 255, 210
                light.brightness, light.decay, light.size = 1.5, 0, 384
                light.nomodel = true
                light.dietime = CurTime() + 0.15
                hadLight = true
            end
        elseif hadLight then
            -- Reacquire the light by ID rather than retaining a reusable dlight.
            local light = DynamicLight(lightKey)
            if light then
                light.brightness, light.size, light.dietime = 0, 0, CurTime() + 0.001
            end
            hadLight = false
        end
    end)

    local palette = {
        ["$pp_colour_addr"] = 0, ["$pp_colour_addg"] = 0, ["$pp_colour_addb"] = 0,
        ["$pp_colour_brightness"] = 0.015, ["$pp_colour_contrast"] = 1.3,
        ["$pp_colour_colour"] = 0, ["$pp_colour_mulr"] = 0,
        ["$pp_colour_mulg"] = 0, ["$pp_colour_mulb"] = 0
    }
    hook.Add("RenderScreenspaceEffects", "ProbeDroid.NightVision", function()
        if not nightVision:GetBool() or thermalVision:GetBool() or not controlledProbe(LocalPlayer()) then return end
        DrawColorModify(palette)
        tintSensorImage(255, 0, 0)
    end)
end

do
    local stealthBlur
    hook.Add("RenderScreenspaceEffects", "ProbeDroid.StealthBlur", function()
        local probe = controlledProbe(LocalPlayer())
        if not probe or not probe:GetStealth() then return end
        -- One light spatial-blur pass; the HUD is drawn afterward and stays sharp.
        stealthBlur = stealthBlur or Material("pp/blurscreen")
        stealthBlur:SetFloat("$blur", 1.6)
        stealthBlur:Recompute()
        render.UpdateScreenEffectTexture()
        render.SetMaterial(stealthBlur)
        render.DrawScreenQuad()
    end)
end

hook.Add("PlayerBindPress", "ProbeDroid.ToggleThermal", function(ply, bind, pressed)
    if not pressed or string.lower(bind) ~= "+reload" or not controlledProbe(ply) then return end
    RunConsoleCommand("probe_droid_thermal", thermalVision:GetBool() and "0" or "1")
    surface.PlaySound("buttons/lightswitch2.wav")
    return true
end)

do
    local coldPalette = {
        ["$pp_colour_addr"] = 0.025, ["$pp_colour_addg"] = 0, ["$pp_colour_addb"] = 0,
        ["$pp_colour_brightness"] = -0.06, ["$pp_colour_contrast"] = 0.9,
        ["$pp_colour_colour"] = 0, ["$pp_colour_mulr"] = 0,
        ["$pp_colour_mulg"] = 0, ["$pp_colour_mulb"] = 0
    }
    local heatMaterial
    local function getHeatMaterial()
        if heatMaterial then return heatMaterial end
        -- Small, once-generated noise texture gives surfaces a mottled IR grain.
        local target = GetRenderTargetEx("ProbeDroidHeatGrainFast", 64, 64,
            RT_SIZE_LITERAL, MATERIAL_RT_DEPTH_NONE, 0, 0, IMAGE_FORMAT_RGBA8888)
        render.PushRenderTarget(target)
        render.OverrideAlphaWriteEnable(true, true)
        render.Clear(255, 255, 255, 255, false, false)
        cam.Start2D()
        for y = 0, 31 do
            for x = 0, 31 do
                local value = 155 + ((x * 73 + y * 151 + x * y * 17) % 101)
                surface.SetDrawColor(255, value, math.max(0, (value - 195) * 4), 255)
                surface.DrawRect(x * 2, y * 2, 2, 2)
            end
        end
        cam.End2D()
        render.OverrideAlphaWriteEnable(false)
        render.PopRenderTarget()
        heatMaterial = CreateMaterial("ProbeDroidHeatSurfaceFast", "UnlitGeneric", {
            ["$basetexture"] = target:GetName(), ["$model"] = "1",
            ["$nodecal"] = "1", ["$nofog"] = "1"
        })
        return heatMaterial
    end

    local candidates, nextScan, lastProbe = {}, 0, nil
    local drawErrors = setmetatable({}, {__mode = "k"})
    local npcMaskFrame = -1
    local wrappedNPCs = {}
    local installedCandidates, maskActive, maskOrigin, maskRangeSquared
    local nativeDrawModel = FindMetaTable("Entity").DrawModel
    local heatDrawFlags = bit.bor(STUDIO_RENDER, STUDIO_NOSHADOWS,
        STUDIO_SKIP_FLEXES or 0, STUDIO_SKIP_DECALS or 0)
    local depthDrawFlags = bit.bor(STUDIO_SHADOWDEPTHTEXTURE or 0, STUDIO_SSAODEPTHTEXTURE or 0)
    local function opaqueNativeNPC(ent, record)
        if not record or record.custom or ent.RenderOverride ~= record.wrapper then return false end
        -- A missing engine draw is normally visibility/occlusion culling. Do
        -- not submit that model again in Lua and undo the engine's decision.
        -- BOTH/translucent renderers still need the compatibility fallback.
        local group = ent:GetRenderGroup()
        return group == RENDERGROUP_OPAQUE or group == RENDERGROUP_OPAQUE_HUGE
    end
    local function visibleWeapon(ent)
        local owner = ent:GetOwner()
        -- Inventory weapons can have a model and GetNoDraw() == false even
        -- though the engine hides their world model. Do not redraw the backpack.
        return not IsValid(owner)
            or not (owner:IsPlayer() or owner:IsNPC() or owner:IsNextBot())
            or not isfunction(owner.GetActiveWeapon)
            or owner:GetActiveWeapon() == ent
    end
    local function thermalTarget(ent, probe)
        if not IsValid(ent) or ent:IsDormant() or ent:GetNoDraw() then return false end
        if ent == probe or ent:IsWorld() then return false end
        local class = ent:GetClass()
        -- Source vehicles use prop_vehicle_* classes; keep them hot while
        -- ordinary physics/dynamic props remain part of the cold environment.
        if (string.sub(class, 1, 5) == "prop_" and not ent:IsVehicle())
            or class == "gmod_cameraprop" or class == "predicted_viewmodel"
            or class == "viewmodel" or class == "gmod_hands" then return false end
        -- Brush geometry and invisible logic entities have no heat silhouette.
        local model = ent:GetModel()
        if not model or string.sub(string.lower(model), -4) ~= ".mdl" then return false end
        if ent:IsPlayer() then return ent:Alive() end
        return true
    end

    local function scanTargets(probe)
        if probe == lastProbe and CurTime() < nextScan then return end
        candidates = {}
        for _, ent in ipairs(ents.GetAll()) do
            if thermalTarget(ent, probe) then
                candidates[#candidates + 1] = {entity = ent,
                    radius = ent:BoundingRadius(), draw = ent.DrawModel,
                    weapon = ent:IsWeapon(), npc = ent:IsNPC() or ent:IsNextBot()}
            end
        end
        nextScan, lastProbe = CurTime() + 0.5, probe
    end

    local function restoreNPCs()
        for ent, saved in pairs(wrappedNPCs) do
            if IsValid(ent) then
                if ent.RenderOverride == saved.wrapper then
                    ent.RenderOverride = saved.previous
                end
            end
        end
        table.Empty(wrappedNPCs)
        installedCandidates, maskActive = nil, false
    end
    _G.ProbeDroidNPCHeatCleanup = restoreNPCs

    -- Write only the high stencil bit, leaving the remaining bits available.
    local function stencilWriter(reference)
        render.SetStencilEnable(true)
        render.SetStencilWriteMask(128)
        render.SetStencilTestMask(128)
        render.SetStencilReferenceValue(reference)
        render.SetStencilCompareFunction(STENCIL_ALWAYS)
        render.SetStencilPassOperation(STENCIL_REPLACE)
        render.SetStencilFailOperation(STENCIL_KEEP)
        render.SetStencilZFailOperation(STENCIL_KEEP)
    end
    local function endStencil()
        render.SetStencilEnable(false)
        render.SetStencilWriteMask(255)
        render.SetStencilTestMask(255)
        render.SetStencilReferenceValue(0)
        render.SetStencilCompareFunction(STENCIL_ALWAYS)
        render.SetStencilPassOperation(STENCIL_KEEP)
        render.SetStencilFailOperation(STENCIL_KEEP)
        render.SetStencilZFailOperation(STENCIL_KEEP)
    end

    hook.Add("PreDrawOpaqueRenderables", "ProbeDroid.NPCHeatMask", function(depth, sky)
        if depth or sky then maskActive = false return end
        npcMaskFrame = -1
        if not thermalVision:GetBool() then
            if installedCandidates then restoreNPCs() end
            return
        end
        local probe = controlledProbe(LocalPlayer())
        if not probe then
            if installedCandidates then restoreNPCs() end
            return
        end
        scanTargets(probe)
        getHeatMaterial()
        local view = render.GetViewSetup(true)
        local origin = view.origin or probe:GetCameraPosition()
        local rangeSquared = math.min(probe:GetMaxRange(), 6000) ^ 2
        maskOrigin, maskRangeSquared = origin, rangeSquared
        if installedCandidates ~= candidates then
            installedCandidates = candidates
            local present = {}
            for _, candidate in ipairs(candidates) do
                local ent = candidate.entity
                if candidate.npc and IsValid(ent) then
                    present[ent] = true
                    local saved = wrappedNPCs[ent]
                    if not saved or ent.RenderOverride ~= saved.wrapper then
                        local vars = ent:GetTable()
                        local previous = rawget(vars, "RenderOverride")
                        local original = ent.RenderOverride
                        local draw = ent.Draw
                        local custom = isfunction(original) or isfunction(draw)
                        local record = {previous = previous, custom = custom}
                        local drawModel = isfunction(original) and original or isfunction(draw) and draw or nativeDrawModel
                        local wrapper = function(self, flags)
                            local heat = maskActive and npcMaskFrame == FrameNumber()
                                and bit.band(flags or STUDIO_RENDER, depthDrawFlags) == 0
                                and self:WorldSpaceCenter():DistToSqr(maskOrigin) <= maskRangeSquared
                            -- Outside the heat pass, leave the engine's normal
                            -- draw path alone (including depth/shadow passes).
                            if not heat then return drawModel(self, flags) end
                            if custom then stencilWriter(128) else render.SetStencilReferenceValue(128) end
                            render.MaterialOverride(heatMaterial)
                            flags = bit.bor(flags or STUDIO_RENDER, heatDrawFlags)
                            -- Preserve scripted rendering and existing overrides. This
                            -- is the normal engine draw, not a second heat-model draw.
                            local ok, err = pcall(drawModel, self, flags)
                            -- Subsequent opaque occluders clear the heat bit wherever
                            -- they win the depth test, so walls/props still hide NPCs.
                            if ok then record.heatFrame = FrameNumber() end
                            render.MaterialOverride(nil)
                            if custom then stencilWriter(0) else render.SetStencilReferenceValue(0) end
                            if not ok and CurTime() >= (drawErrors[self] or 0) then
                                drawErrors[self] = CurTime() + 5
                                ErrorNoHalt("[Probe Droid NPC heat] " .. tostring(err) .. "\n")
                            end
                        end
                        record.wrapper = wrapper
                        wrappedNPCs[ent] = record
                        ent.RenderOverride = wrapper
                    end
                end
            end
            for ent, saved in pairs(wrappedNPCs) do
                if not present[ent] then
                    if IsValid(ent) and ent.RenderOverride == saved.wrapper then
                        ent.RenderOverride = saved.previous
                    end
                    wrappedNPCs[ent] = nil
                end
            end
        end
        render.ClearStencil()
        stencilWriter(0)
        npcMaskFrame, maskActive = FrameNumber(), true
    end)
    hook.Add("PostDrawOpaqueRenderables", "ProbeDroid.NPCHeatMask", function(depth, sky)
        if depth or sky or npcMaskFrame ~= FrameNumber() then return end
        maskActive = false
        endStencil()
    end)
    hook.Add("ShutDown", "ProbeDroid.NPCHeatMask", restoreNPCs)
    hook.Add("Think", "ProbeDroid.NPCHeatMaskCleanup", function()
        if installedCandidates and (not thermalVision:GetBool() or not controlledProbe(LocalPlayer())) then
            restoreNPCs()
            npcMaskFrame = -1
        end
    end)

    hook.Add("RenderScreenspaceEffects", "ProbeDroid.ThermalVision", function()
        local ply = LocalPlayer()
        local probe = controlledProbe(ply)
        if not probe or not thermalVision:GetBool() then
            lastProbe = nil
            return
        end
        local view = render.GetViewSetup(true)
        local origin = view.origin or probe:GetCameraPosition()
        local rangeSquared = math.min(probe:GetMaxRange(), 6000) ^ 2
        scanTargets(probe)

        local maskedNPCs = npcMaskFrame == FrameNumber()
        if maskedNPCs then
            -- NPCs already used the cheap heat material in their normal draw.
            -- Apply the cold image filter only to the remaining scene pixels.
            render.SetStencilEnable(true)
            render.SetStencilWriteMask(0)
            render.SetStencilTestMask(128)
            render.SetStencilReferenceValue(128)
            render.SetStencilCompareFunction(STENCIL_NOTEQUAL)
            render.SetStencilPassOperation(STENCIL_KEEP)
            render.SetStencilFailOperation(STENCIL_KEEP)
            render.SetStencilZFailOperation(STENCIL_KEEP)
        end
        DrawColorModify(coldPalette)
        tintSensorImage(170, 6, 2)
        if maskedNPCs then endStencil() end
        local material = getHeatMaterial()
        local angles = view.angles or probe.ClientViewAngles or ply:EyeAngles()
        local forward, right, up = angles:Forward(), angles:Right(), angles:Up()
        -- Conservative sphere/frustum rejection preserves partly visible models.
        -- Keep a generous FOV margin for engine aspect-ratio adjustments.
        local tanH = math.tan(math.rad(math.Clamp(math.max(view.fov or 120, 120) + 10, 1, 175) * 0.5))
        local tanV = tanH / (ScrW() / math.max(ScrH(), 1))
        local sideMargin, topMargin = math.sqrt(1 + tanH * tanH), math.sqrt(1 + tanV * tanV)
        -- Inherit the actual world-view projection, including the engine's
        -- aspect-adjusted FOV and clipping planes. Reconstructing it from the
        -- player's base FOV makes the heat pass drift on widescreen displays.
        cam.Start3D()
        render.MaterialOverride(material)
        -- Heat colors are baked into the texture: avoid a second model-lighting
        -- calculation for every actor, weapon, and scripted model each frame.
        local ok, err = xpcall(function()
            for i = 1, #candidates do
                local candidate = candidates[i]
                local ent = candidate.entity
                local npcState = candidate.npc and wrappedNPCs[ent]
                -- Class/model eligibility and bounds are cached by the scanner.
                -- An opaque native NPC skipped by the engine is culled, not
                -- missing a heat pass. Only custom/translucent NPCs need the
                -- fallback when they did not contribute to this frame's mask.
                if IsValid(ent) and not (npcState and npcState.heatFrame == FrameNumber())
                    and not (maskedNPCs and opaqueNativeNPC(ent, npcState))
                    and not ent:IsDormant() and not ent:GetNoDraw()
                    and (not candidate.weapon or visibleWeapon(ent)) then
                    local delta = ent:WorldSpaceCenter() - origin
                    local radius = candidate.radius
                    local depth = delta:Dot(forward)
                    if delta:LengthSqr() <= rangeSquared and depth >= -radius
                        and math.abs(delta:Dot(right)) <= math.max(depth, 0) * tanH + radius * sideMargin
                        and math.abs(delta:Dot(up)) <= math.max(depth, 0) * tanV + radius * topMargin then
                        -- Keep normal depth testing: terrain and walls occlude heat.
                        -- Let the renderer clip models at the edge of the view;
                        -- their centre may be behind us while part is visible.
                        -- A broken addon model must not cancel all later targets.
                        local drawn, drawError = pcall(candidate.draw, ent, heatDrawFlags)
                        if not drawn and CurTime() >= (drawErrors[ent] or 0) then
                            drawErrors[ent] = CurTime() + 5
                            ErrorNoHalt("[Probe Droid thermal entity " .. ent:EntIndex() .. "] " .. tostring(drawError) .. "\n")
                        end
                    end
                end
            end
        end, debug.traceback)
        render.MaterialOverride(nil)
        cam.End3D()
        if not ok then ErrorNoHalt("[Probe Droid thermal] " .. tostring(err) .. "\n") end
    end)
end

-- The local player's model uses predicted camera angles. Keep its rendered
-- body and aiming pose at the launch orientation as well as locking the server.
hook.Add("PrePlayerDraw", "ProbeDroid.PilotOrientation", function(ply)
    if not IsValid(ply) or ply ~= LocalPlayer() or not controlledProbe(ply) then return end
    local angles = ply:GetNW2Angle("ProbeDroidBodyAngles", ply:EyeAngles())
    local previousAngles = ply:GetRenderAngles()
    if not isangle(previousAngles) then previousAngles = ply:GetAngles() end
    ply.ProbeDroidRenderAngles = previousAngles
    ply:SetRenderAngles(Angle(0, angles.y, 0))
    ply:SetPoseParameter("aim_yaw", 0)
    ply:SetPoseParameter("head_yaw", 0)
    ply:SetPoseParameter("aim_pitch", angles.p)
    ply:SetPoseParameter("head_pitch", angles.p)
end)

hook.Add("PostPlayerDraw", "ProbeDroid.RestoreRenderAngles", function(ply)
    if not IsValid(ply) then return end
    local previousAngles = ply.ProbeDroidRenderAngles
    ply.ProbeDroidRenderAngles = nil
    if not isangle(previousAngles) then return end
    ply:SetRenderAngles(previousAngles)
end)

hook.Add("PreDrawViewModel", "ProbeDroid.HideController", function()
    if controlledProbe(LocalPlayer()) then return true end
end)

hook.Add("HUDShouldDraw", "ProbeDroid.HideDefaultHUD", function(name)
    if controlledProbe(LocalPlayer()) and (name == "CHudCrosshair" or name == "CHudAmmo"
        or name == "CHudSecondaryAmmo" or name == "CHudHealth" or name == "CHudBattery"
        or name == "CHudSuitPower") then
        return false
    end
end)

do
-- Vector-drawn optical overlay: no external textures or font downloads required.
local amber = Color(255, 89, 83, 255)
local dim = Color(255, 81, 75, 155)
local faint = Color(255, 96, 75, 80)
local white = Color(199, 36, 15, 255)
local danger = Color(255, 87, 63, 255)
local backing = Color(5, 9, 13, 215)
local shadow = Color(0, 0, 0, 240)
local stealthHighlight = Color(255, 205, 170, 255)
local stealthBacking = Color(24, 7, 8, 235)
-- Source map-scale conversion used consistently for every optical readout.
local METERS_PER_UNIT = 0.01905
local RADAR_RANGE = 1000
local function meters(units)
    return units * METERS_PER_UNIT
end
local effects = CreateClientConVar("probe_droid_hud_effects", "1", true, false,
    "Enable probe camera scanlines, edge shading, and weak-signal interference.")
local hudScale = CreateClientConVar("probe_droid_hud_scale", "1", true, false,
    "Optical HUD size multiplier. Automatically limited to keep instruments on screen.", 0.6, 1.5)
local scale = 1
local layout = {}
local function layoutFor(w, h, preference)
    return {
        -- Size by height on wide screens, then fit a minimum usable canvas.
        -- There is no fixed upper/lower scale cap: 4K and small windows both fit.
        scale = math.min(h / 900 * math.Clamp(preference, 0.6, 1.5), w / 1280, h / 720),
        compact = w < 1280 or h < 720,
        width = w,
        height = h,
        preference = preference
    }
end
local function updateLayout(w, h)
    local preference = hudScale:GetFloat()
    if layout.width == w and layout.height == h and layout.preference == preference then return end
    layout = layoutFor(w, h, preference)
    scale = layout.scale
    for name, size in pairs({Small = 14, Text = 17, Value = 25, Stealth = 28}) do
        surface.CreateFont("ProbeOptics." .. name, {
            font = "Consolas", size = math.max(7, math.Round(size * scale)),
            weight = (name == "Value" or name == "Stealth") and 700 or 600, antialias = true
        })
    end
end
updateLayout(ScrW(), ScrH())
hook.Add("OnScreenSizeChanged", "ProbeDroid.OpticsFonts", function()
    -- Rebuild from the next frame's actual dimensions, not the event's old size.
    layout.width = nil
end)

local function line(x1, y1, x2, y2, color)
    surface.SetDrawColor(color or amber)
    surface.DrawLine(x1, y1, x2, y2)
end

local function text(value, x, y, font, color, align)
    -- Two passes instead of the outline helper's 10-17 full text draws.
    local face = "ProbeOptics." .. (font or "Small")
    draw.SimpleText(value, face, x + 1, y + 1, shadow, align or TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    draw.SimpleText(value, face, x, y, color or amber, align or TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
end

-- Bake static line art once per size. Subsequent frames draw one textured quad.
local graphics = {}
local function graphic(name, width, height, paint, repeatTexture)
    width, height = math.ceil(width), math.ceil(height)
    local key = name .. "_" .. width .. "x" .. height
    if graphics[key] then return graphics[key] end
    local tw, th = 2 ^ math.ceil(math.log(math.max(width, 2)) / math.log(2)),
        2 ^ math.ceil(math.log(math.max(height, 2)) / math.log(2))
    local target = GetRenderTargetEx("ProbeOpticsCache_" .. key, tw, th,
        RT_SIZE_LITERAL, MATERIAL_RT_DEPTH_NONE, repeatTexture and 0 or 12, 0, IMAGE_FORMAT_RGBA8888)
    render.PushRenderTarget(target)
    render.OverrideAlphaWriteEnable(true, true)
    render.Clear(0, 0, 0, 0, false, false)
    render.OverrideBlend(true, BLEND_SRC_ALPHA, BLEND_ONE_MINUS_SRC_ALPHA, BLENDFUNC_ADD,
        BLEND_ONE, BLEND_ONE_MINUS_SRC_ALPHA, BLENDFUNC_ADD)
    cam.Start2D()
    draw.NoTexture()
    paint()
    cam.End2D()
    render.OverrideBlend(false)
    render.OverrideAlphaWriteEnable(false)
    render.PopRenderTarget()
    local cached = {
        width = width, height = height, u = width / tw, v = height / th,
        material = CreateMaterial("ProbeOpticsMaterial_" .. key, "UnlitGeneric", {
            ["$basetexture"] = target:GetName(), ["$translucent"] = "1",
            ["$vertexcolor"] = "1", ["$vertexalpha"] = "1"
        })
    }
    graphics[key] = cached
    return cached
end

local function drawGraphic(cached, x, y, width, height, flipX, flipY)
    surface.SetMaterial(cached.material)
    surface.SetDrawColor(255, 255, 255, 255)
    surface.DrawTexturedRectUV(x, y, width or cached.width, height or cached.height,
        flipX and cached.u or 0, flipY and cached.v or 0,
        flipX and 0 or cached.u, flipY and 0 or cached.v)
end

local function arc(x, y, radius, first, last, color, step)
    step = step or 5
    local previousX, previousY
    for degrees = first, last + step, step do
        local angle = math.rad(math.min(degrees, last))
        local px, py = x + math.cos(angle) * radius, y + math.sin(angle) * radius
        if previousX then line(previousX, previousY, px, py, color) end
        previousX, previousY = px, py
    end
end

local function bracket(x, y, w, h, color)
    local length = math.min(14 * scale, w / 4, h / 4)
    for _, sx in ipairs({0, 1}) do
        for _, sy in ipairs({0, 1}) do
            local px, py = x + w * sx, y + h * sy
            line(px, py, px + length * (sx == 0 and 1 or -1), py, color)
            line(px, py, px, py + length * (sy == 0 and 1 or -1), color)
        end
    end
end

local function panel(x, y, w, h, title)
    surface.SetDrawColor(backing)
    surface.DrawRect(x, y, w, h)
    bracket(x, y, w, h)
    line(x + 8 * scale, y + 25 * scale, x + w - 8 * scale, y + 25 * scale, dim)
    text(title, x + 12 * scale, y + 8 * scale)
end

local function meter(x, y, width, fraction, color)
    local count, gap = 24, 3 * scale
    local segment = (width - gap * (count - 1)) / count
    for i = 1, count do
        surface.SetDrawColor(i <= math.ceil(fraction * count) and color or faint)
        surface.DrawRect(x + (i - 1) * (segment + gap), y, segment, 5 * scale)
    end
end

local state = {nextScan = 0, contacts = {}, profile = {}}
local function scan(probe, position, angles, range)
    local now = CurTime()
    if state.probe ~= probe then
        state = {probe = probe, nextScan = 0, contacts = {}, profile = {}, speed = 0}
    end
    -- The HUD can paint twice while warming its textures. Never spend another
    -- scan budget in the same engine frame.
    local frame = FrameNumber()
    if state.scanFrame == frame then return end
    state.scanFrame = frame
    local ply = LocalPlayer()
    if now >= state.nextScan then
        if state.lastPosition then
            local speed = position:Distance(state.lastPosition) / math.max(now - state.lastTime, 0.01)
            state.speed = Lerp(0.5, state.speed, speed)
        end
        state.lastPosition, state.lastTime = position, now
        state.nextScan = now + 0.2
        local scanRange = math.min(range, 6000)
        local filter = {probe, ply, probe:GetAimTarget()}
        state.trace = util.TraceLine({start = position, endpos = position + angles:Forward() * scanRange,
            filter = filter, mask = MASK_SHOT})
        -- Keep one camera snapshot for the entire surface profile. If rendering
        -- stalls, finish the pending sweep instead of discarding its last rays.
        if not state.depthSweep then
            state.depthSweep = {position = position, pitch = angles.p, yaw = angles.y,
                range = scanRange, filter = filter, index = 1, profile = {}}
        end
    end
    if now >= (state.nextRadar or 0) and not state.radarSweep then
        state.nextRadar = now + 0.5
        local targets = {}
        for _, ent in ipairs(ents.FindInSphere(position, RADAR_RANGE)) do
            if #targets >= 16 then break end
            if ent ~= ply and ent:GetClass() ~= "npc_bullseye"
                and (ent:IsNPC() or (ent:IsPlayer() and ent:Alive())) then
                targets[#targets + 1] = ent
            end
        end
        state.radarSweep = {position = position, filter = {probe, ply, probe:GetAimTarget()},
            targets = targets, index = 1, contacts = {}}
    end
    -- Bound expensive collision work to eleven rays per HUD update: one aim,
    -- six depth and four radar rays, rather than a burst of up to 34 traces.
    local depth = state.depthSweep
    if depth then
        for i = depth.index, math.min(depth.index + 5, 17) do
            local ray = Angle(depth.pitch, depth.yaw + (i - 9) * 4, 0)
            local trace = util.TraceLine({start = depth.position,
                endpos = depth.position + ray:Forward() * depth.range,
                filter = depth.filter, mask = MASK_SOLID})
            depth.profile[i] = trace.Fraction
            depth.index = i + 1
        end
        if depth.index > 17 then
            state.profile, state.sounding = depth.profile, depth.range
            state.depthSweep = nil
        end
    end
    local radar = state.radarSweep
    if radar then
        for i = radar.index, math.min(radar.index + 3, #radar.targets) do
            local ent = radar.targets[i]
            if IsValid(ent) and (not ent:IsPlayer() or ent:Alive()) then
                local target = ent:WorldSpaceCenter()
                if target:DistToSqr(radar.position) <= RADAR_RANGE ^ 2 then
                    local trace = util.TraceLine({start = radar.position, endpos = target,
                        filter = radar.filter, mask = MASK_VISIBLE})
                    if not trace.Hit or trace.Entity == ent then
                        radar.contacts[#radar.contacts + 1] = target
                    end
                end
            end
            radar.index = i + 1
        end
        if radar.index > #radar.targets then
            state.contacts = radar.contacts
            state.radarSweep = nil
        end
    end
end

local function compass(w, yaw)
    local cx, y = w / 2, 33 * scale
    local width = math.min(650 * scale, w * (layout.compact and 0.38 or 0.46))
    line(cx - width / 2, y, cx + width / 2, y, dim)
    local heading = (-yaw + 90) % 360
    local cardinal = {[0] = "N", [90] = "E", [180] = "S", [270] = "W"}
    for value = math.floor((heading - 65) / 5) * 5, heading + 65, 5 do
        local x = cx + (value - heading) * width / 130
        local major = value % 30 == 0
        line(x, y, x, y - (major and 12 or 5) * scale, major and amber or dim)
        if major then text(cardinal[value % 360] or string.format("%03d", value % 360), x, y + 7 * scale, "Small", nil, TEXT_ALIGN_CENTER) end
    end
    line(cx - 5 * scale, y - 21 * scale, cx, y - 28 * scale, white)
    line(cx, y - 28 * scale, cx + 5 * scale, y - 21 * scale, white)
    text(string.format("HDG %03d", heading), cx, y + 30 * scale, "Text", white, TEXT_ALIGN_CENTER)
end

local radarFill = {}
local sweepColors = {}
for i = 0, 8 do sweepColors[i] = Color(255, 111, 67, 80 - i * 9) end
local function radar(x, y, radius, position, angles, home)
    local disc = graphic("radar", radius * 2 + 4, radius * 2 + 4, function()
    local x, y = radius + 2, radius + 2
    for i = 1, 64 do
        local angle = math.rad((i - 1) * 360 / 64)
        radarFill[i] = radarFill[i] or {}
        radarFill[i].x = x + math.cos(angle) * radius
        radarFill[i].y = y + math.sin(angle) * radius
    end
    draw.NoTexture()
    surface.SetDrawColor(backing)
    surface.DrawPoly(radarFill)
    for i = 1, 4 do arc(x, y, radius * i / 4, 0, 360, i == 4 and amber or faint) end
    for angle = 0, 330, 30 do
        local a = math.rad(angle)
        line(x, y, x + math.cos(a) * radius, y + math.sin(a) * radius, faint)
    end
    end)
    drawGraphic(disc, x - radius - 2, y - radius - 2)
    local sweep = RealTime() * 55
    for i = 0, 8 do
        local a = math.rad(sweep - i * 2)
        line(x, y, x + math.cos(a) * radius, y + math.sin(a) * radius, sweepColors[i])
    end
    local forward, right = Angle(0, angles.y, 0):Forward(), Angle(0, angles.y, 0):Right()
    local function project(target, limit)
        local delta = target - position
        local px, py = delta:Dot(right) / RADAR_RANGE, -delta:Dot(forward) / RADAR_RANGE
        local length = math.sqrt(px * px + py * py)
        if limit and length > 0.9 then px, py = px / length * 0.9, py / length * 0.9 end
        return x + px * radius, y + py * radius, length
    end
    for _, target in ipairs(state.contacts) do
        local px, py, length = project(target)
        if length < 0.95 then
            surface.SetDrawColor(white)
            surface.DrawRect(px - 2 * scale, py - 2 * scale, 4 * scale, 4 * scale)
        end
    end
    local hx, hy = project(home, true)
    bracket(hx - 4 * scale, hy - 4 * scale, 8 * scale, 8 * scale, white)
    text("H", hx + 7 * scale, hy - 6 * scale, "Small", white)
    line(x - 4 * scale, y + 4 * scale, x, y - 4 * scale, white)
    line(x, y - 4 * scale, x + 4 * scale, y + 4 * scale, white)
    text(string.format("TARGETS DETECTED / %02d", #state.contacts), x - radius, y - radius - 24 * scale)
    text("H / UPLINK", x, y + radius + 12 * scale, "Small", nil, TEXT_ALIGN_CENTER)
end

local function drawStealthIndicator(probe, w)
    if not probe:GetStealth() then return end
    local s, cx = scale, w / 2
    surface.SetDrawColor(stealthBacking)
    surface.DrawRect(cx - 180 * s, 88 * s, 360 * s, 46 * s)
    surface.SetDrawColor(stealthHighlight)
    surface.DrawOutlinedRect(cx - 180 * s, 88 * s, 360 * s, 46 * s)
    text("STEALTH ACTIVE", cx, 97 * s, "Stealth", stealthHighlight, TEXT_ALIGN_CENTER)
end

local function drawExitProgress(probe, w, h)
    local deadline = probe:GetNW2Float("ProbeDroidExitEnd", 0)
    if deadline == 0 then return end
    local s, cx, y = scale, w / 2, h / 2 + 139 * scale
    local remaining = math.max(0, deadline - CurTime())
    local progress = math.Clamp(1 - remaining / 2, 0, 1)
    surface.SetDrawColor(backing)
    surface.DrawRect(cx - 160 * s, y, 320 * s, 64 * s)
    text(string.format("DEACTIVATING / %.1f s", remaining), cx, y + 8 * s,
        "Text", stealthHighlight, TEXT_ALIGN_CENTER)
    text("RELEASE TO CANCEL", cx, y + 33 * s, "Small", stealthHighlight, TEXT_ALIGN_CENTER)
    surface.SetDrawColor(dim)
    surface.DrawRect(cx - 146 * s, y + 54 * s, 292 * s, 4 * s)
    surface.SetDrawColor(stealthHighlight)
    surface.DrawRect(cx - 146 * s, y + 54 * s, 292 * s * progress, 4 * s)
end

local function installHUD(controlledProbe)
    local vignette
    local function vignetteMaterial()
        if vignette then return vignette end
        -- Build a radial alpha texture locally; no downloaded material needed.
        -- Render once at small resolution, then let texture filtering smooth it.
        local size = 128
        local target = GetRenderTargetEx("ProbeDroidRadialVignetteV1", size, size,
            RT_SIZE_LITERAL, MATERIAL_RT_DEPTH_NONE, 12, 0, IMAGE_FORMAT_RGBA8888)
        render.PushRenderTarget(target)
        render.OverrideAlphaWriteEnable(true, true)
        render.Clear(0, 0, 0, 0, false, false)
        render.OverrideBlend(true, BLEND_ONE, BLEND_ZERO, BLENDFUNC_ADD,
            BLEND_ONE, BLEND_ZERO, BLENDFUNC_ADD)
        cam.Start2D()
        draw.NoTexture()
        for y = 0, size - 1 do
            local ny = 2 * y / (size - 1) - 1
            for x = 0, size - 1 do
                local nx = 2 * x / (size - 1) - 1
                local fade = math.Clamp((math.sqrt(nx * nx + ny * ny) - 0.4) / 0.95, 0, 1)
                surface.SetDrawColor(0, 0, 0, math.floor(255 * fade * fade * (3 - 2 * fade) + 0.5))
                surface.DrawRect(x, y, 1, 1)
            end
        end
        cam.End2D()
        render.OverrideBlend(false)
        render.OverrideAlphaWriteEnable(false)
        render.PopRenderTarget()
        vignette = CreateMaterial("ProbeDroidRadialVignetteMaterialV1", "UnlitGeneric", {
            ["$basetexture"] = target:GetName(), ["$translucent"] = "1",
            ["$vertexcolor"] = "1", ["$vertexalpha"] = "1"
        })
        return vignette
    end
    local vignetteProbe, vignetteAlpha
    local function drawVignette(probe, w, h)
        local material = vignetteMaterial()
        local target = probe:GetStealth() and 235 or 125
        if vignetteProbe ~= probe then
            vignetteProbe, vignetteAlpha = probe, target
        end
        vignetteAlpha = Lerp(1 - math.exp(-FrameTime() * 7), vignetteAlpha, target)
        surface.SetDrawColor(255, 255, 255, vignetteAlpha)
        surface.SetMaterial(material)
        surface.DrawTexturedRect(0, 0, w, h)
    end
    local refreshRate = CreateClientConVar("probe_droid_hud_fps", "20", true, false,
        "Instrument refresh rate; the world and camera still render every frame.", 15, 60)
    local function renderHUD()
        local probe = controlledProbe(LocalPlayer())
        if not probe then state.probe = nil return end
        updateLayout(ScrW(), ScrH())
        local w, h, s = ScrW(), ScrH(), scale
        local cx, cy = w / 2, h / 2
        local position = probe:GetCameraPosition()
        local angles = probe.ClientViewAngles or LocalPlayer():EyeAngles()
        local home = probe:GetLaunchPosition()
        local range = math.max(probe:GetMaxRange(), 1)
        local distance = position:Distance(home)
        local remaining = math.max(0, probe:GetBatteryEnd() - CurTime())
        local battery = math.Clamp(remaining / math.max(probe:GetBatteryDuration(), 1), 0, 1)
        local signal = math.Clamp(1 - distance / range, 0, 1)
        scan(probe, position, angles, range)

        if effects:GetBool() then
            local scanlines = graphic("scanlines", 16, 16, function()
                surface.SetDrawColor(0, 0, 0, 20)
                for y = 0, 15, 4 do surface.DrawRect(0, y, 16, 1) end
            end, true)
            surface.SetMaterial(scanlines.material)
            surface.SetDrawColor(255, 255, 255, 255)
            surface.DrawTexturedRectUV(0, 0, w, h, 0, 0, w / 16, h / 16)
            local vertical = graphic("verticalfade", 112 * s, 2, function()
                for i = 0, 15 do
                    surface.SetDrawColor(1, 5, 10, math.floor((1 - i / 16) ^ 2 * 95))
                    surface.DrawRect(i * 7 * s, 0, 7 * s, 2)
                end
            end)
            local horizontal = graphic("horizontalfade", 2, 64 * s, function()
                for i = 0, 15 do
                    surface.SetDrawColor(1, 5, 10, math.floor((1 - i / 16) ^ 2 * 95))
                    surface.DrawRect(0, i * 4 * s, 2, 4 * s)
                end
            end)
            drawGraphic(vertical, 0, 0, 112 * s, h)
            drawGraphic(vertical, w - 112 * s, 0, 112 * s, h, true)
            drawGraphic(horizontal, 0, 0, w, 64 * s)
            drawGraphic(horizontal, 0, h - 64 * s, w, 64 * s, false, true)
            if signal < 0.2 then
                surface.SetDrawColor(255, 145, 95, math.floor((0.2 - signal) * 100))
                surface.DrawRect(0, (RealTime() * 120) % h, w, 4 * s)
            end
        end

        bracket(24 * s, 19 * s, w - 48 * s, h - 38 * s, dim)
        text(layout.compact and "PROBE // OPTICS" or "ARAKYD // PROBE SYSTEMS", 46 * s, 34 * s, "Text")
        if not layout.compact then
            text("OPTICAL RECONNAISSANCE / CHANNEL 01", 46 * s, 57 * s, "Small", dim)
        end
        text("LIVE  /  " .. string.format("%06.1f", CurTime()), w - 46 * s, 34 * s, "Text", nil, TEXT_ALIGN_RIGHT)
        local sensor = thermalVision:GetBool() and "IR / RED HOT [R]"
            or nightVision:GetBool() and "NIGHT VISION [N]" or "OPTICAL [R IR / N NV]"
        text(sensor,
            w - 46 * s, 57 * s, "Small", white, TEXT_ALIGN_RIGHT)
        if not probe:GetStealth() then
            text("STEALTH OFF", cx, 79 * s, "Small", dim, TEXT_ALIGN_CENTER)
        end
        compass(w, angles.y)

        -- Optical reference globe and compact flight telemetry.
        local globe = graphic("globe", 120 * s, 120 * s, function()
        local gx, gy, gr = 60 * s, 60 * s, 47 * s
        arc(gx, gy, gr, 0, 360, amber)
        for _, flatten in ipairs({0.35, 0.7}) do
            local px, py
            for a = 0, 360, 10 do
                local r = math.rad(a)
                local x, y = gx + math.cos(r) * gr * flatten, gy + math.sin(r) * gr
                if px then line(px, py, x, y, dim) end
                px, py = x, y
            end
        end
        for _, offset in ipairs({-0.5, 0, 0.5}) do
            local extent = math.sqrt(1 - offset * offset) * gr
            line(gx - extent, gy + offset * gr, gx + extent, gy + offset * gr, dim)
        end
        line(gx, gy - gr, gx, gy + gr, dim)
        end)
        drawGraphic(globe, 38 * s, 94 * s)
        text("NAV REFERENCE", 46 * s, 217 * s)
        surface.SetDrawColor(backing)
        surface.DrawRect(36 * s, 237 * s, 193 * s, 83 * s)
        text(string.format("VEL   %.1f m/s", meters(state.speed or 0)), 46 * s, 247 * s, "Text", white)
        text(string.format("ALT   %+.1f m", meters(position.z - home.z)), 46 * s, 271 * s, "Text", white)
        text(string.format("PITCH %+03d", -angles.p), 46 * s, 295 * s)

        -- Split annular reticle leaves the centre unobstructed.
        local reticle = graphic("reticle", 320 * s, 200 * s, function()
        local cx, cy, radius = 160 * s, 100 * s, 81 * s
        for _, section in ipairs({{12, 78}, {102, 168}, {192, 258}, {282, 348}}) do
            arc(cx, cy, radius, section[1], section[2], amber, 3)
            arc(cx, cy, radius + 4 * s, section[1], section[2], dim, 3)
        end
        for i = -1, 1, 2 do
            line(cx + i * 14 * s, cy, cx + i * 35 * s, cy)
            line(cx, cy + i * 14 * s, cx, cy + i * 35 * s)
            line(cx + i * 96 * s, cy, cx + i * 148 * s, cy, dim)
            for j = -3, 3 do line(cx + i * 98 * s, cy + j * 4 * s, cx + i * 109 * s, cy + j * 4 * s, dim) end
        end
        surface.SetDrawColor(white)
        surface.DrawRect(cx - s, cy - s, 2 * s, 2 * s)
        end)
        drawGraphic(reticle, cx - 160 * s, cy - 100 * s)
        local trace = state.trace
        local target = trace and trace.Hit and position:Distance(trace.HitPos)
        text(string.format("ZOOM %dx", zoomFactor(probe)), cx, cy - 120 * s, "Small", white, TEXT_ALIGN_CENTER)
        text(target and string.format("RNG %.1f m", meters(target)) or "RNG --- m", cx, cy + 109 * s, "Small", white, TEXT_ALIGN_CENTER)
        if trace and IsValid(trace.Entity) and (trace.Entity:IsNPC() or trace.Entity:IsPlayer()) then
            local screen = trace.Entity:WorldSpaceCenter():ToScreen()
            if screen.visible then
                bracket(screen.x - 28 * s, screen.y - 38 * s, 56 * s, 76 * s, white)
                text("CONTACT", screen.x, screen.y + 44 * s, "Small", white, TEXT_ALIGN_CENTER)
            end
        end

        -- Right-side pitch ruler.
        local rx = w - 42 * s
        for i = -6, 6 do
            local y = cy + i * 20 * s
            line(rx - (i % 3 == 0 and 14 or 7) * s, y, rx, y, dim)
            if i % 3 == 0 then text(string.format("%+03d", math.Clamp(-angles.p - i * 5, -90, 90)), rx - 22 * s, y - 6 * s, "Small", amber, TEXT_ALIGN_RIGHT) end
        end
        line(rx - 4 * s, cy - 4 * s, rx - 10 * s, cy, white)
        line(rx - 10 * s, cy, rx - 4 * s, cy + 4 * s, white)

        local pw, px, py = 294 * s, w - 340 * s, 91 * s
        panel(px, py, pw, 139 * s, layout.compact and "SURFACE SCAN" or "OPTICAL DEPTH / SURFACE SCAN")
        for i = 1, 3 do line(px + 12 * s, py + (34 + i * 23) * s, px + pw - 12 * s, py + (34 + i * 23) * s, faint) end
        for i = 1, #state.profile - 1 do
            local x1, x2 = px + (12 + (i - 1) * 16.8) * s, px + (12 + i * 16.8) * s
            local y1, y2 = py + (112 - state.profile[i] * 70) * s, py + (112 - state.profile[i + 1] * 70) * s
            line(x1, y1, x2, y2, amber)
            line(x1, y1 + 6 * s, x2, y2 + 6 * s, dim)
        end
        text(string.format("DEPTH %.1f m / 17 SAMPLES", meters(state.sounding or 0)), px + 12 * s, py + 120 * s)

        radar(155 * s, h - 185 * s, 103 * s, position, angles, home)
        local ty = h - 226 * s
        panel(px, ty, pw, 164 * s, layout.compact and "POWER / LINK" or "REMOTE LINK / POWER CORE")
        local batteryColor, signalColor = battery < 0.2 and danger or amber, signal < 0.2 and danger or amber
        text("BATTERY", px + 12 * s, ty + 38 * s)
        text(string.format("%02d:%02d  %03d%%", math.floor(remaining / 60), math.floor(remaining % 60), math.ceil(battery * 100)), px + pw - 12 * s, ty + 32 * s, "Value", batteryColor, TEXT_ALIGN_RIGHT)
        meter(px + 12 * s, ty + 64 * s, pw - 24 * s, battery, batteryColor)
        text("SIGNAL", px + 12 * s, ty + 84 * s)
        text(string.format("%03d%%", signal * 100), px + pw - 12 * s, ty + 78 * s, "Value", signalColor, TEXT_ALIGN_RIGHT)
        meter(px + 12 * s, ty + 110 * s, pw - 24 * s, signal, signalColor)
        text(string.format("UPLINK %.1f / %.1f m", meters(distance), meters(range)), px + 12 * s, ty + 134 * s, "Text", white)
        if layout.compact then
            text("WASD / FLY | SPACE CTRL / ALT", cx, h - 48 * s, "Small", nil, TEXT_ALIGN_CENTER)
            text("SHIFT BOOST | LMB ZOOM | R IR | N NV | RMB STEALTH | HOLD E 2s EXIT", cx, h - 28 * s, "Small", nil, TEXT_ALIGN_CENTER)
        else
            text("WASD FLY | SPACE CTRL ALT | SHIFT BOOST | LMB ZOOM | R IR | N NV | RMB STEALTH | HOLD E 2s EXIT", cx, h - 42 * s, "Small", nil, TEXT_ALIGN_CENTER)
        end
        if battery < 0.2 or signal < 0.2 then
            local warning = battery < 0.2 and "POWER CORE DEPLETING" or "TRANSMISSION LIMIT"
            if battery < 0.2 and signal < 0.2 then warning = "POWER LOW / TRANSMISSION LIMIT" end
            local pulse = Color(255, 75, 45, 165 + math.sin(RealTime() * 5) * 60)
            text("// " .. warning .. " //", cx, h - 91 * s, "Text", pulse, TEXT_ALIGN_CENTER)
        end
    end
    local cached, nextPaint, lastProbe, lastMode, lastScale, lastEffects, lastStealth
    nextPaint = 0
    hook.Add("HUDPaint", "ProbeDroid.Telemetry", function()
        local probe = controlledProbe(LocalPlayer())
        if not probe then lastProbe = nil state.probe = nil return end
        local w, h = ScrW(), ScrH()
        -- Shade the world before drawing instruments, outside the cached HUD.
        drawVignette(probe, w, h)
        local mode = thermalVision:GetBool() and 1 or nightVision:GetBool() and 2 or 0
        if not cached or cached.width ~= w or cached.height ~= h then
            -- Warm the small instrument textures before entering the outer RT.
            renderHUD()
            local key = "ProbeOpticsFrame_" .. w .. "x" .. h
            local target = GetRenderTargetEx(key, w, h, RT_SIZE_LITERAL,
                MATERIAL_RT_DEPTH_NONE, 12, 0, IMAGE_FORMAT_RGBA8888)
            cached = {width = w, height = h, target = target,
                material = CreateMaterial(key .. "Material", "UnlitGeneric", {
                    ["$basetexture"] = target:GetName(), ["$translucent"] = "1",
                    ["$vertexcolor"] = "1", ["$vertexalpha"] = "1"
                })}
            nextPaint = 0
            drawStealthIndicator(probe, w)
            drawExitProgress(probe, w, h)
            return
        end
        if RealTime() >= nextPaint or lastProbe ~= probe or lastMode ~= mode or lastStealth ~= probe:GetStealth()
            or lastScale ~= hudScale:GetFloat() or lastEffects ~= effects:GetBool() then
            -- A scale change can create new instrument textures; warm them first.
            if lastScale ~= hudScale:GetFloat() then renderHUD() end
            render.PushRenderTarget(cached.target)
            render.OverrideAlphaWriteEnable(true, true)
            render.Clear(0, 0, 0, 0, false, false)
            render.OverrideBlend(true, BLEND_SRC_ALPHA, BLEND_ONE_MINUS_SRC_ALPHA, BLENDFUNC_ADD,
                BLEND_ONE, BLEND_ONE_MINUS_SRC_ALPHA, BLENDFUNC_ADD)
            cam.Start2D()
            renderHUD()
            cam.End2D()
            render.OverrideBlend(false)
            render.OverrideAlphaWriteEnable(false)
            render.PopRenderTarget()
            nextPaint = RealTime() + 1 / math.Clamp(refreshRate:GetFloat(), 15, 60)
            lastProbe, lastMode = probe, mode
            lastStealth = probe:GetStealth()
            lastScale, lastEffects = hudScale:GetFloat(), effects:GetBool()
        end
        surface.SetMaterial(cached.material)
        surface.SetDrawColor(255, 255, 255, probe:GetStealth() and 127.5 or 255)
        surface.DrawTexturedRect(0, 0, w, h)
        -- Keep the active status prominent above the half-opacity HUD layer.
        drawStealthIndicator(probe, w)
        drawExitProgress(probe, w, h)
    end)
end

installHUD(controlledProbe)
end
