-- One shared cooldown prevents alternating thermal/NV keys from cutting off
-- or overlapping the stereo activation/deactivation clips.
return function(controlledProbe)
    if isfunction(_G.ProbeDroidStopSensorAudio) then _G.ProbeDroidStopSensorAudio() end
    local channel, loading, nextToggleAt, generation = nil, false, 0, 0
    local function stop()
        generation = generation + 1
        if IsValid(channel) then channel:Stop() end
        channel, loading, nextToggleAt = nil, false, 0
    end
    _G.ProbeDroidStopSensorAudio = stop
    hook.Add("ShutDown", "ProbeDroid.SensorAudio", stop)

    return function(name)
        if not controlledProbe(LocalPlayer()) or loading or RealTime() < nextToggleAt then return end
        local enabled = not GetConVar(name):GetBool()
        loading = true
        local serial = generation
        RunConsoleCommand(name, enabled and "1" or "0")
        sound.PlayFile("sound/customsounds/" .. (enabled and "nvon.wav" or "nvoff.wav"), "noplay",
            function(voice, errorID, errorName)
                if serial ~= generation then
                    if IsValid(voice) then voice:Stop() end
                    return
                end
                loading = false
                if not IsValid(voice) then
                    nextToggleAt = RealTime() + 0.25
                    ErrorNoHalt("[Probe Droid sensor audio] " .. tostring(errorName or errorID) .. "\n")
                    return
                end
                if IsValid(channel) then channel:Stop() end
                channel = voice
                voice:EnableLooping(false)
                voice:SetVolume(1)
                nextToggleAt = RealTime() + math.max(voice:GetLength(), 0.05) + 0.05
                voice:Play()
            end)
    end
end
