
-- This acts like a static class.
NVGBASE_GOGGLES = {};
NVGBASE_GOGGLES.PreDrawReady = false;
NVGBASE_GOGGLES.SoundsCacheReady = false;
NVGBASE_GOGGLES.PreDrawHaloReady = false;

-- Toggle flags used to switch animation states.
NVGBASE_GOGGLES.Toggled = nil;
NVGBASE_GOGGLES.ToggledSound = false;

-- State vars for rendering and cleanup.
NVGBASE_GOGGLES.CurrentGoggles = nil;
NVGBASE_GOGGLES.ShouldCleanupMaterials = false;

-- Used to handle transition and blending. NextTransition
-- is only used to delay the screenspace effects and overlays.
NVGBASE_GOGGLES.Transition = 0;
NVGBASE_GOGGLES.NextTransition = 0;
NVGBASE_GOGGLES.ProjectedTexture = nil;
NVGBASE_GOGGLES.PhotoSensitivity = 0;

--!
--! @brief      Utility function to cleanup goggle model material overrides.
--!             If you are modifying the material of a model in your goggle hooks,
--!             you must raise the flag NVGBASE_MATERIALOVERRIDE on it for
--!             it to be processed in this hook since we don't want to break other addons.
--!
function NVGBASE_GOGGLES:CleanupMaterials()

	-- Do nothing if no cleanup is required.
	if (!self.ShouldCleanupMaterials) then return; end

	-- Reset entity material.
	for k,v in pairs(ents.GetAll()) do

		if (!v.NVGBASE_MATERIALOVERRIDE) then continue; end

		v:SetMaterial(v:GetMaterial());
		v.NVGBASE_MATERIALOVERRIDE = false;
	end

	-- Cleanup finished, reset flag to avoid using unnecessary CPU time.
	self.ShouldCleanupMaterials = false;
end

--!
--! @brief      Utility function to cleanup goggle rendermode overrides.
--!             If you are modifying the rendermode of a model in your goggle hooks,
--!             you must raise the flag NVGBASE_RENDEROVERRIDE on it for
--!             it to be processed in this hook since we don't want to break other addons.
--!             You must use NVGBASE_OldColor and NVGBASE_OldRenderMode on the entity to
--!             keep references to the old settings in order to be properly cleaned up.
--!
function NVGBASE_GOGGLES:CleanupPreDrawOpaques()

	-- Do nothing if no cleanup is required.
	if (!self.ShouldCleanupPreDrawOpaques) then return; end

	-- Reset entity material.
	for k,v in pairs(ents.GetAll()) do

		if (!v.NVGBASE_RENDEROVERRIDE) then continue; end
		v:NVGBASE_ResetRenderingSettings();
		v.NVGBASE_RENDEROVERRIDE = nil;
	end

	-- Cleanup finished, reset flag to avoid using unnecessary CPU time.
	self.ShouldCleanupPreDrawOpaques = false;
	self.PreDrawReady = false;
end

--!
--! @brief      Utility function to handle model material override when using a goggle.
--!             It works by using the filter function found in the goggle's config
--!             to determine if the entity should receive the material. We also raise a flag on the
--!             entity for eventual cleanup. This way we'll only use CPU time when necessary.
--!
--! @param      goggle  The goggle config being processed.
--!
function NVGBASE_GOGGLES:HandleMaterialOverrides(goggle)

	for k,v in pairs(ents.GetAll()) do

		-- Do nothing if the entity does not pass the filter.
		if (!goggle.Filter(v)) then continue; end

		v:SetMaterial(goggle.MaterialOverride);
		v.NVGBASE_MATERIALOVERRIDE = true;
	end

	-- Raise the cleanup flag for later use.
	NVGBASE_GOGGLES.ShouldCleanupMaterials = true;
end

--!
--! @brief      Used to render the lens transitioning in view.
--!
function NVGBASE_GOGGLES:TransitionIn(rate, overlay)

	-- Render lens coming in.
	self.Transition = Lerp(FrameTime() * rate, self.Transition, 2);

	local transition = math.Clamp(self.Transition, 0, 1);
	if (transition < 0.9) then
		surface.SetMaterial(overlay);
		surface.SetDrawColor(255, 255, 255, transition * 255);
		surface.DrawTexturedRect(0, -ScrH() + (ScrH() * 1.3 * transition), ScrW(), ScrH());
	end
end

--!
--! @brief      Used to render the lens transitioning out of view.
--!
function NVGBASE_GOGGLES:TransitionOut(rate, overlay)

	-- Render lens going out.
	self.Transition = Lerp(FrameTime() * rate, self.Transition, 0);

	local transition = math.Clamp(self.Transition - 1, 0, 1);
	if (transition > 0.1) then
		surface.SetMaterial(overlay);
		surface.SetDrawColor(255, 255, 255, transition * 255);
		surface.DrawTexturedRect(0, -ScrH() + (ScrH() * 1.3 * transition), ScrW(), ScrH());
	end
end

--!
--! @brief      Renders the overlay effect for vignette and animated lens.
--!
function NVGBASE_GOGGLES:DrawOverlay(overlay, swap, secondOverlay)

	local transition = math.Clamp(self.Transition - 1, 0, 1);

	-- Vignetting effect.
	if (!swap && secondOverlay != nil) then
		surface.SetMaterial(secondOverlay);
		surface.SetDrawColor(255, 255, 255, transition * 255);
		surface.DrawTexturedRect(0, 0, ScrW(), ScrH());
	end

	-- Animated overlay texture.
	if (overlay != nil) then
		surface.SetMaterial(overlay);
		surface.SetDrawColor(255, 255, 255, transition * 255);
		surface.DrawTexturedRect(0, 0, ScrW(), ScrH());
	end

	-- Vignetting effect.
	if (swap && secondOverlay != nil) then
		surface.SetMaterial(secondOverlay);
		surface.SetDrawColor(255, 255, 255, transition * 255);
		surface.DrawTexturedRect(0, 0, ScrW(), ScrH());
	end
end

--!
--! @brief      Creates a sound cache client side to handle looping sounds for
--!             all goggle types. Each sound will be a CSoundPatch. 
--!
function NVGBASE_GOGGLES:SetupLoopingSounds(loadout)

	if (loadout.SoundsCacheReady) then return; end

	-- Initialize looping sound cache, this 
	for k,goggle in pairs(loadout) do
		if (goggle.Sounds != nil) then
			if (goggle.SoundsCache == nil) then goggle.SoundsCache = {}; end
			if (goggle.Sounds.Loop == nil) then continue; end
			goggle.SoundsCache["Loop"] = CreateSound(LocalPlayer(), Sound(goggle.Sounds.Loop));
		end
	end

	loadout.SoundsCacheReady = true;
end

function NVGBASE_GOGGLES:PlayLoopingSound(goggle, fadeIn)

	if (goggle.SoundsCache != nil && goggle.SoundsCache["Loop"] != nil) then
		goggle.SoundsCache["Loop"]:Play();
		goggle.SoundsCache["Loop"]:ChangeVolume(0);
		goggle.SoundsCache["Loop"]:ChangeVolume(1, fadeIn);
	end
end

function NVGBASE_GOGGLES:StopLoopingSound(goggle, fadeOut)

	if (goggle.SoundsCache != nil && goggle.SoundsCache["Loop"] != nil) then
		goggle.SoundsCache["Loop"]:FadeOut(fadeOut)
	end
end

local __OffScreenRenderingTarget = nil;
local __OffScreenRenderingTexture = nil;
function NVGBASE_GOGGLES:PrepareOffScreenRendering()

	if (__OffScreenRenderingTarget != nil && ScrW() == __OffScreenRenderingTexture:Width() && ScrH() == __OffScreenRenderingTexture:Height()) then
		return;
	end

	local offScreenRenderingID = ScrW() .. "x" .. ScrH();
	__OffScreenRenderingTarget = GetRenderTarget("NVGBASE_OffScreen_" .. offScreenRenderingID, ScrW(), ScrH());
	__OffScreenRenderingTexture = CreateMaterial("NVGBASE_OffScreenTexture_" .. offScreenRenderingID, "UnlitGeneric", {
		["$basetexture"] = __OffScreenRenderingTarget:GetName();
	});
end

--!
--! @brief      Sets up rendering space quad on top of the screen for the current goggle.
--!             This will copy the postprocessing color texture for upcoming render operations.
--!
--! @param      goggle  The current goggle configuration.
--!
local __PostProcessRenderTarget = Material("pp/colour");
function NVGBASE_GOGGLES:Render(goggle)

	-- Setup lighting from configuration.
	local lighting = goggle.Lighting;
	if (lighting != nil) then
		local dlight      = DynamicLight(LocalPlayer():EntIndex());
		dlight.r          = lighting.Color.r;
		dlight.g          = lighting.Color.g;
		dlight.b          = lighting.Color.b;
		dlight.minlight   = lighting.Min;
		dlight.style      = lighting.Style;
		dlight.Brightness = lighting.Brightness;
		dlight.Pos        = EyePos();
		dlight.Size       = lighting.Size;
		dlight.Decay      = lighting.Decay;
		dlight.DieTime    = CurTime() + lighting.DieTime;
	end

	local colorCorrect = goggle.ColorCorrection;
	if (colorCorrect != nil) then

		local finalBrightness = colorCorrect.Brightness;

		-- Apply photo sensitivity.
		if (goggle.PhotoSensitive != nil) then

			-- Compute light intensity at player's eye position.
			local light = render.GetLightColor(EyePos());
			local lightIntensity = light.r / 3 + light.g / 3 + light.b / 3;

			-- Lerp the photosensitivy factor in order to avoid sudden changes in light intensity.
			NVGBASE_GOGGLES.PhotoSensitivity = Lerp(FrameTime() * 2, NVGBASE_GOGGLES.PhotoSensitivity, lightIntensity);
			finalBrightness = finalBrightness + NVGBASE_GOGGLES.PhotoSensitivity;
		end

		-- Offload to rendertarget.
		render.UpdateScreenEffectTexture();

			__PostProcessRenderTarget:SetTexture("$fbtexture",          render.GetScreenEffectTexture());
			__PostProcessRenderTarget:SetFloat("$pp_colour_addr",       colorCorrect.ColorAdd.r);
			__PostProcessRenderTarget:SetFloat("$pp_colour_addg",       colorCorrect.ColorAdd.g);
			__PostProcessRenderTarget:SetFloat("$pp_colour_addb",       colorCorrect.ColorAdd.b);
			__PostProcessRenderTarget:SetFloat("$pp_colour_mulr",       colorCorrect.ColorMul.r);
			__PostProcessRenderTarget:SetFloat("$pp_colour_mulg",       colorCorrect.ColorMul.g);
			__PostProcessRenderTarget:SetFloat("$pp_colour_mulb",       colorCorrect.ColorMul.b);
			__PostProcessRenderTarget:SetFloat("$pp_colour_brightness", finalBrightness);
			__PostProcessRenderTarget:SetFloat("$pp_colour_contrast",   colorCorrect.Contrast);
			__PostProcessRenderTarget:SetFloat("$pp_colour_colour",     colorCorrect.ColorMod);

		render.SetMaterial(__PostProcessRenderTarget);
		render.DrawScreenQuad();
	end

	-- Render interlace material over screen, if provided.
	if (goggle.MaterialInterlace != nil) then
		local interlaceColor = goggle.InterlaceColor;
		surface.SetMaterial(goggle.MaterialInterlace);
		surface.SetDrawColor(interlaceColor.r, interlaceColor.g, interlaceColor.b, interlaceColor.a);
		surface.DrawTexturedRect(0 + math.Rand(-1,1), 0 + math.Rand(-1,1), ScrW(), ScrH());
	end
end

--! 
--! Draw hook entry point for all goggles. This will use the network var currently set on the player
--! to determine which goggle to use.
--!
hook.Add("HUDPaintBackground", "NVGBASE_HUD", function()

	-- This is the autoload logic for the network var. Network vars will be handled serverside.
	local currentGoggle = LocalPlayer():GetNWInt("NVGBASE_CURRENT_GOGGLE", 1);
	if (currentGoggle == 0) then return; end

	-- Initializes the looping sound cache.
	local loadout = LocalPlayer():NVGBASE_GetLoadout();
	if (loadout == nil) then return; end
	NVGBASE_GOGGLES:SetupLoopingSounds(loadout.Goggles);

	-- Get clientside var toggle for active status.
	local toggle = GetConVar("NVGBASE_TOGGLE"):GetBool();
	if (NVGBASE_GOGGLES.Toggled == nil) then
		NVGBASE_GOGGLES.Toggled = toggle;
		NVGBASE_GOGGLES.CurrentGoggles = currentGoggle;
	end

	-- Delegate call to the configuration file for which goggle to render.
	local currentConfig = loadout.Goggles[currentGoggle];
	if (toggle) then

		-- Do transition animation in.
		if (loadout.Settings.Overlays != nil) then
			NVGBASE_GOGGLES:TransitionIn(loadout.Settings.Transition.Rate, loadout.Settings.Overlays.Transition);
		end

		if (!NVGBASE_GOGGLES.Toggled) then
			NVGBASE_GOGGLES.NextTransition = CurTime() + loadout.Settings.Transition.Delay;
			NVGBASE_GOGGLES.Toggled = true;
		end

		-- Goggles don't match with the cache, user must've switched goggles.
		if (currentGoggle != NVGBASE_GOGGLES.CurrentGoggles) then

			-- Stop looping sound of previous goggles and cleanup materials.
			local previousConfig = loadout.Goggles[NVGBASE_GOGGLES.CurrentGoggles];
			NVGBASE_GOGGLES:CleanupMaterials();
			NVGBASE_GOGGLES:CleanupPreDrawOpaques();
			NVGBASE_GOGGLES:StopLoopingSound(previousConfig, 0.5);

			-- Play goggle mode switch sound only clientside and start looping sound.
			NVGBASE_GOGGLES.CurrentGoggles = currentGoggle;
			NVGBASE_GOGGLES:PlayLoopingSound(currentConfig, 1.5);
			if (loadout.Settings.Transition.Sound != nil) then surface.PlaySound(loadout.Settings.Transition.Sound); end
		end

		if (CurTime() > NVGBASE_GOGGLES.NextTransition) then

			-- Raise pre draw opaque flag.
			NVGBASE_GOGGLES.PreDrawReady = true;
			NVGBASE_GOGGLES.PreDrawHaloReady = true;

			-- Do offscreen rendering now before any processing occurs.
			if (currentConfig.OffscreenRendering != nil) then
				NVGBASE_GOGGLES:PrepareOffScreenRendering();
				NVGBASE_GOGGLES:CleanupMaterials();
				render.PushRenderTarget(__OffScreenRenderingTarget);
					render.RenderView({
						origin = EyePos(),
						angles = EyeAngles(),
						x = 0, y = 0,
						w = ScrW(), h = ScrH(),
						drawviewmodel = true,
						dopostprocess = false
					});
				render.PopRenderTarget();
			end

			-- Handle material overrides for the goggle being used.
			if (currentConfig.Filter != nil) then
				NVGBASE_GOGGLES:HandleMaterialOverrides(currentConfig);
			end

			-- Render screen space effects of current config.
			loadout.Goggles[currentGoggle].PostProcess(currentConfig);
			NVGBASE_GOGGLES:Render(currentConfig);

			-- Play activate sound on client only after delay expired and start looping sound.
			if (!NVGBASE_GOGGLES.ToggledSound) then
				NVGBASE_GOGGLES.ToggledSound = true;
				NVGBASE_GOGGLES:PlayLoopingSound(currentConfig, 1.5);
				if (currentConfig.Sounds != nil && currentConfig.Sounds.Activate != nil) then
					surface.PlaySound(currentConfig.Sounds.Activate);
				end
			end

			-- Current config does not use projected texture feature, remove it if it exists.
			if (currentConfig.ProjectedTexture == nil && IsValid(NVGBASE_GOGGLES.ProjectedTexture)) then
				NVGBASE_GOGGLES.ProjectedTexture:Remove();
				NVGBASE_GOGGLES.ProjectedTexture = nil;
			end

			-- Current config uses a projected texture for lighting, create it if not already done.
			if (currentConfig.ProjectedTexture != nil && !IsValid(NVGBASE_GOGGLES.ProjectedTexture)) then
				NVGBASE_GOGGLES.ProjectedTexture = ProjectedTexture();
				NVGBASE_GOGGLES.ProjectedTexture:SetTexture("effects/flashlight/soft");
				NVGBASE_GOGGLES.ProjectedTexture:SetEnableShadows(false);
			end

			-- Update projected texture with current config data.
			if (IsValid(NVGBASE_GOGGLES.ProjectedTexture)) then
				NVGBASE_GOGGLES.ProjectedTexture:SetPos(EyePos());
				NVGBASE_GOGGLES.ProjectedTexture:SetAngles(EyeAngles());
				NVGBASE_GOGGLES.ProjectedTexture:SetFOV(currentConfig.ProjectedTexture.FOV);
				NVGBASE_GOGGLES.ProjectedTexture:SetVerticalFOV(currentConfig.ProjectedTexture.VFOV);
				NVGBASE_GOGGLES.ProjectedTexture:SetBrightness(currentConfig.ProjectedTexture.Brightness);
				NVGBASE_GOGGLES.ProjectedTexture:SetFarZ(currentConfig.ProjectedTexture.Distance);
				NVGBASE_GOGGLES.ProjectedTexture:Update();
			end

			-- Do final post processing pass using offscreen render target sampling for special effects.
			if (currentConfig.OffscreenRendering != nil) then
				currentConfig.OffscreenRendering(currentConfig, __OffScreenRenderingTexture);
			end
		end
	else

		-- Transition lens out.
		if (loadout.Settings.Overlays != nil) then
			NVGBASE_GOGGLES:TransitionOut(loadout.Settings.Transition.Rate, loadout.Settings.Overlays.Transition);
		end

		-- Reset defaults for next toggle.
		NVGBASE_GOGGLES.Toggled = false;
		NVGBASE_GOGGLES.ToggledSound = false;

		-- Restore default materials on entities.
		NVGBASE_GOGGLES:CleanupMaterials();
		NVGBASE_GOGGLES:CleanupPreDrawOpaques();
		NVGBASE_GOGGLES:StopLoopingSound(currentConfig, 0);
		NVGBASE_GOGGLES.PreDrawHaloReady = false;

		-- Remove projected texture.
		if (IsValid(NVGBASE_GOGGLES.ProjectedTexture)) then
			NVGBASE_GOGGLES.ProjectedTexture:Remove();
			NVGBASE_GOGGLES.ProjectedTexture = nil;
		end
	end

	-- This is always called but will not interfere with other addons.
	if (loadout.Settings.Overlays != nil) then
		NVGBASE_GOGGLES:DrawOverlay(currentConfig.MaterialOverlay, currentConfig.OverlayFirst, loadout.Settings.Overlays.Goggle);
	end
end);

hook.Add("PreDrawOpaqueRenderables", "NVGBASE_PREDRAW", function(depth, sky, sky3D)

	-- This is the autoload logic for the network var. Network vars will be handled serverside.
	local currentGoggle = LocalPlayer():GetNWInt("NVGBASE_CURRENT_GOGGLE", 1);
	if (currentGoggle == 0) then return; end

	local loadout = LocalPlayer():NVGBASE_GetLoadout();
	if (loadout == nil) then return; end
	local toggle = GetConVar("NVGBASE_TOGGLE"):GetBool();
	local currentConfig = loadout.Goggles[currentGoggle];
	if (toggle) then

		-- Handle predraw opaques according to current goggle config.
		if (currentConfig.PreDrawOpaque != nil) then
			if (NVGBASE_GOGGLES.PreDrawReady) then
				currentConfig.PreDrawOpaque(currentConfig);
				NVGBASE_GOGGLES.ShouldCleanupPreDrawOpaques = true;
			end
		else
			NVGBASE_GOGGLES:CleanupPreDrawOpaques();
		end
	else
		NVGBASE_GOGGLES:CleanupPreDrawOpaques();
	end
end);

hook.Add("PreDrawHalos", "NVGBASE_PREDRAWHALOS", function()

	-- This is the autoload logic for the network var. Network vars will be handled serverside.
	local currentGoggle = LocalPlayer():GetNWInt("NVGBASE_CURRENT_GOGGLE", 1);
	if (currentGoggle == 0) then return; end

	local loadout = LocalPlayer():NVGBASE_GetLoadout();
	if (loadout == nil) then return; end
	local toggle = GetConVar("NVGBASE_TOGGLE"):GetBool();
	local currentConfig = loadout.Goggles[currentGoggle];

	-- Handle predraw halos according to current goggle config.
	if (toggle && currentConfig.PreDrawHalos != nil && NVGBASE_GOGGLES.PreDrawHaloReady) then
		currentConfig.PreDrawHalos(currentConfig);
	end
end);