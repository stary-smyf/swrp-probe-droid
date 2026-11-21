-- Local cockpit alerts; BASS playback supports stereo warning WAVs.
if isfunction(_G.ProbeDroidStopWarnings) then _G.ProbeDroidStopWarnings() end
local lastProbe, channel, loading, nextSound, generation = nil, nil, false, 0, 0
local function stop()
    generation = generation + 1
    if IsValid(channel) then channel:Stop() end
    lastProbe, channel, loading, nextSound = nil, nil, false, 0
end
_G.ProbeDroidStopWarnings = stop
hook.Add("ShutDown", "ProbeDroid.Warnings", stop)
hook.Add("Think", "ProbeDroid.Warnings", function()
    local ply = LocalPlayer()
    local probe = IsValid(ply) and ply:Alive() and ply:GetNW2Entity("ProbeDroidControlled")
    if not IsValid(probe) then stop() return end
    if lastProbe ~= probe then stop() lastProbe = probe end
    local battery = (probe:GetBatteryEnd() - CurTime()) / math.max(probe:GetBatteryDuration(), 1)
    local distance = probe:GetCameraPosition():Distance(probe:GetLaunchPosition())
    local range = math.max(probe:GetMaxRange(), 1)
    local signal = (range - distance) / range
    if battery >= 0.1 and signal >= 0.1 then stop() return end
    if IsValid(channel) or loading or RealTime() < nextSound then return end
    loading = true
    local serial = generation
    sound.PlayFile("sound/customsounds/warning.wav", "noplay", function(voice)
        if serial ~= generation then
            if IsValid(voice) then voice:Stop() end
            return
        end
        loading = false
        nextSound = RealTime() + 3
        if not IsValid(voice) then return end
        if IsValid(channel) then channel:Stop() end
        channel = voice
        voice:EnableLooping(true)
        voice:SetVolume(1)
        voice:Play()
    end)
end)
