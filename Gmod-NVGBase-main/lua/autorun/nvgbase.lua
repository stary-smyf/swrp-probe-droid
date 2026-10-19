
-- Admin ConVars for whitelist and player loadouts.
CreateConVar("NVGBASE_WHITELIST", "0",          { FCVAR_ARCHIVE, FCVAR_CHEAT, FCVAR_REPLICATED });
CreateConVar("NVGBASE_ALLOWPLAYERLOADOUT", "0", { FCVAR_ARCHIVE, FCVAR_CHEAT, FCVAR_REPLICATED });
CreateConVar("NVGBASE_DEFAULTLOADOUT", "",      { FCVAR_ARCHIVE, FCVAR_CHEAT, FCVAR_REPLICATED });

-- Setup player convars to determine which key to use for the goggles. By default:
-- * KEY_N (24): Toggle goggle.
-- * KEY_M (23): Cycle goggle.
CreateClientConVar("NVGBASE_INPUT", "24", true, true, "Which key to toggle goggle. Must be a number, refer to: https://wiki.facepunch.com/gmod/Enums/KEY.", 1, 159);
CreateClientConVar("NVGBASE_CYCLE", "23", true, true, "Which key to cycle goggle. Must be a number, refer to: https://wiki.facepunch.com/gmod/Enums/KEY.",  1, 159);
CreateClientConVar("NVGBASE_TOGGLE", "0", false, true, "Internal only, you should use +NVGBASE_TOGGLE instead.");
CreateClientConVar("NVGBASE_LOADOUT", "", true, true, "Internal only, you should use NVGBASE_PLAYERLOADOUT instead.");

-- Admin console command for setting the gamemode's NVG loadout.
concommand.Add("NVGBASE_GAMEMODELOADOUT", function(ply, cmd, args)

	if (args[1] == nil) then return; end

	GetConVar("NVGBASE_DEFAULTLOADOUT"):SetString(args[1]);
	for k,v in pairs(player.GetAll()) do
		v:NVGBASE_SetLoadout(args[1]);
	end
end, nil, nil, FCVAR_CHEAT);

-- Player console command to show all available NVG loadouts.
concommand.Add("NVGBASE_SHOWLOADOUTS", function(ply, cmd, args)

	for k,v in pairs(NVGBASE.Loadouts) do
		print(k);
	end
end, nil, nil, 0);

-- Player console command to define the loadout on the fly.
concommand.Add("NVGBASE_PLAYERLOADOUT", function(ply, cmd, args)

	if (args[1] == nil || ply == NULL || !GetConVar("NVGBASE_ALLOWPLAYERLOADOUT"):GetBool()) then return; end
	ply:NVGBASE_SetLoadout(args[1]);
end, nil, nil, 0);

-- Player console command to toggle the goggles on from the console.
concommand.Add("+NVGBASE_TOGGLE", function(ply, cmd, args)

	-- Do nothing if executing from the server's console.
	if (ply == NULL) then return; end

	-- Do nothing if the player is not using a loadout at the moment.
	local loadout = ply:NVGBASE_GetLoadout();
	if (loadout == nil) then return; end

	-- Toggle goggle.
	if (args[1] != nil && isnumber(tonumber(args[1]))) then
		ply:NVGBASE_ToggleGoggleAnim(loadout, nil, args[1]);
	else
		ply:NVGBASE_ToggleGoggleAnim(loadout, nil);
	end
end, nil, nil, 0);

-- Player console command to switch the goggles from the console.
concommand.Add("+NVGBASE_SWITCH", function(ply, cmd, args)

	-- Do nothing if executing from the server's console.
	if (ply == NULL) then return; end

	-- Do nothing if the player is not using a loadout at the moment.
	local loadout = ply:NVGBASE_GetLoadout();
	if (loadout == nil) then return; end

	-- Switch goggle.
	if (ply:NVGBASE_CanSwitchGoggle()) then
		if (args[1] != nil && isnumber(tonumber(args[1]))) then
			ply:NVGBASE_SwitchToNextGoggle(loadout, args[1]);
		else
			ply:NVGBASE_SwitchToNextGoggle(loadout);
		end
	end
end, nil, nil, 0);

if (SERVER) then
	util.AddNetworkString("NVGBASE_TOGGLE_ANIM");
end

--! 
--! Used to handle animations clientside since the input handler will only be serverside.
--!
net.Receive("NVGBASE_TOGGLE_ANIM", function()

	-- Simple conversion function for nil (-1) int on network thread.
	local function cast(int)
		if (int == -1) then return nil; end
		return int;
	end

	local ply = net.ReadEntity();
	local gogglesActive = net.ReadBool();
	local anim = cast(net.ReadInt(14));
	local bodygroup = cast(net.ReadInt(14));
	local bodygroupOn = cast(net.ReadInt(14));
	local bodygroupOff = cast(net.ReadInt(14));

	ply:NVGBASE_AnimGoggle(gogglesActive, anim, bodygroup, bodygroupOn, bodygroupOff);
end);

--! 
--! Main input entry point for the goggles. Will process the toggle and cycle key.
--!
hook.Add("PlayerButtonDown", "NVGBASE_INPUT", function(ply, button)

	-- Server only code. PlayerButtonDown is not called clientside in singleplayer. It is
	-- simpler and cleaner to handle everything server-side and do network calls ourselves
	-- to the client realm for animations. This will ensure compatibility in singleplayer and multiplayer.
	if (!SERVER) then return; end

	-- Do nothing if the player is not using a loadout at the moment.
	local loadout = ply:NVGBASE_GetLoadout();
	if (loadout == nil) then return; end

	-- Process toggle key, if pressed.
	ply:NVGBASE_ToggleGoggleAnim(loadout, button);

	-- Cycle between different goggle modes.
	if (ply:NVGBASE_CanSwitchGoggle(button)) then
		ply:NVGBASE_SwitchToNextGoggle(loadout);
	end
end);

--! 
--! Simple hook to remove goggle on death.
--!
hook.Add("PlayerDeath", "NVGBASE_DEATH", function(victim, inflictor, attacker)

	-- Do nothing if the player is not using a loadout at the moment.
	local loadout = victim:NVGBASE_GetLoadout();
	if (loadout == nil) then return; end

	if (loadout.Settings.RemoveOnDeath) then
		victim:NVGBASE_ToggleGoggle(loadout, true, 0);
	end
end);