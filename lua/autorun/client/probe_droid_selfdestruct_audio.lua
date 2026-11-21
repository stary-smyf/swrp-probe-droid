-- Keep the cockpit alarm independent of the drone's hover/speech channels.
if isfunction(_G.ProbeDroidStopSelfDestructAlarm) then _G.ProbeDroidStopSelfDestructAlarm() end
local activeProbe, channel, loading, retryAt, generation = nil, nil, false, 0, 0
local function stop()
    generation = generation + 1
    if IsValid(channel) then channel:Stop() end
    activeProbe, channel, loading, retryAt = nil, nil, false, 0
end
_G.ProbeDroidStopSelfDestructAlarm = stop
hook.Add("ShutDown", "ProbeDroid.SelfDestructAlarm", stop)

local function armedProbe()
    local ply = LocalPlayer()
    local probe = IsValid(ply) and ply:Alive() and ply:GetNW2Entity("ProbeDroidControlled")
    if IsValid(probe) and probe:GetNW2Float("ProbeDroidSelfDestructEnd", 0) > CurTime() then
        return probe
    end
end

hook.Add("Think", "ProbeDroid.SelfDestructAlarm", function()
    local probe = armedProbe()
    if not probe then
        if activeProbe then stop() end
        return
    end
    if activeProbe ~= probe then stop() activeProbe = probe end
    if IsValid(channel) or loading or RealTime() < retryAt then return end
    loading = true
    local serial = generation
    sound.PlayFile("sound/customsounds/selfdestrucalarm.wav", "noplay", function(voice)
        if serial ~= generation or armedProbe() ~= probe then
            if IsValid(voice) then voice:Stop() end
            -- A cancelled countdown may finish loading before the next Think.
            if serial == generation then stop() end
            return
        end
        loading = false
        if not IsValid(voice) then retryAt = RealTime() + 1 return end
        channel = voice
        voice:EnableLooping(true)
        voice:SetVolume(1)
        voice:Play()
    end)
end)
