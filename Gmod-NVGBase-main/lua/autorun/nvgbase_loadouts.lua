
NVGBASE = {};
NVGBASE.Loadouts = {};

-- Loadout register function, must be added to the end of a loadout file.
NVGBASE.Register = function(name, loadout)
	NVGBASE.Loadouts[name] = loadout;
end

-- Auto loader for all loadouts found in the nvgloadouts lua directory.
local loadouts,_ = file.Find("nvgloadouts/*.lua", "LUA");
for k,v in pairs(loadouts) do
	AddCSLuaFile("nvgloadouts/" .. v);
	include("nvgloadouts/" .. v);
end