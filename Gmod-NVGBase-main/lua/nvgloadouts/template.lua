local TEMPLATE = {};
TEMPLATE.Goggles = {};

-- Base settings.
TEMPLATE.Settings = {

	-- Animation gesture to use if your playermodels support it.
	Gestures = {
		On = nil,
		Off = nil
	},

	-- Bodygroup to set if your playermodels have special bodygroups for goggles on/off.
	BodyGroups = {
		Group = nil,  -- Should be an int, or nil if you don't use bodygroups
		Values = {
			On = nil, -- Should be an int, or nil if you don't use bodygroups
			Off = nil -- Should be an int, or nil if you don't use bodygroups
		}
	},

	-- Goggle overlays.
	-- Goggle is a static fullscreen texture.
	-- Transition is the texture used when animating the transition in and out.
	Overlays = {
		Goggle = nil,    -- Should be a Material() or nil
		Transition = nil -- Should be a Material() or nil
	},

	-- Transition timings for transition overlay.
	Transition = {
		Rate = 5,
		Delay = 0.225,
		Switch = 0.5,
		Sound = nil -- String representing the path to the sound file.
	},

	-- True to remove on death, false otherwise.
	RemoveOnDeath = true
};

-- First goggle settings.
TEMPLATE.Goggles[1] = {

	Name = "first_goggle_name",

	-- Whitelist should be a table of playermodel strings.
	Whitelist = nil,

	-- Full screen material overlay.
	MaterialOverlay   = nil,   -- Should be a material or nil
	OverlayFirst      = false, -- Used to swap rendering order between this and Overlays.Goggle

	-- Full screen material overlay.
	MaterialInterlace = nil,   -- Should be a material or nil
	InterlaceColor    = Color(255, 255, 255, 255),

	-- Material to apply to every entity that passes the filter function.
	MaterialOverride  = nil, -- Should be a string path or nil, not a Material.
	Filter = function(ent)

		-- This will be ran for every entity. Return true to override entity's material.
		return;
	end,

	-- Goggle sounds table. Each sound can be set to nil.
	Sounds = {
		Loop      = nil, -- Plays continuously, must be a looping sound.
		ToggleOn  = nil, -- Played once when toggling on.
		ToggleOff = nil, -- Played once when toggling off.
		Activate  = nil  -- Played once then toggling on, used for special effects.
	},

	-- Lighting example. Dynamic lights are expensive and should be small.
	-- This is better suited for illuminating your viewmodel rather than the world itself.
	-- Set to nil if not using.
	Lighting = {
		Color      = Color(25, 25, 25),
		Min        = 0,
		Style      = 0,
		Brightness = 1,
		Size       = 200,
		Decay      = 200,
		DieTime    = 0.05
	},

	-- Projected texture example. Use this to illuminate the world rather
	-- than the lighting table as it yields better results. Set to nil if not using.
	ProjectedTexture = {
		FOV        = 140,
		VFOV       = 100,
		Brightness = 2,
		Distance   = 2500
	},

	-- Photosensitive influences the goggles light sensitivity. Set to nil if not using.
	PhotoSensitive = 0.9,

	-- Color correction example.
	ColorCorrection = {
		ColorAdd   = Color(0.2, 0.4, 0.05),
		ColorMul   = Color(0, 0, 0),
		ColorMod   = 0.25,
		Contrast   = 1,
		Brightness = 0.05
	},

	PostProcess = function(self)
		-- Set to nil if you are not doing postprocessing.
		-- * self refers this goggle table.

		-- This is where you would call DrawBloom, DrawSobel, etc.
	end,

	OffscreenRendering = function(self, texture)
		-- Set to nil if you are not doing offscreen rendering.
		-- * self refers this goggle table.
		-- * texture is a full screen material of the player's view before any processing. 
		--   Useful for UV effects.
	end,

	PreDrawOpaque = function(self)
		-- Set to nil if you are not doing opaque effects
		-- * self refers this goggle table.
		-- This hook should be used to affect entity render modes, etc.
	end,

	PreDrawHalos = function(self)
		-- Set to nil if you are not doing halo effects.
		-- * self refers this goggle table.
		-- This hook should be used to draw halos around entities, for more info:
		-- https://wiki.facepunch.com/gmod/halo.Add
	end
};

-- Define second goggle of the loadout, so on and so forth.
TEMPLATE.Goggles[2] = {}

-- Register the loadout. Commented to prevent adding the template to the loadouts.
-- NVGBASE.Register("loadout_name", TEMPLATE);
