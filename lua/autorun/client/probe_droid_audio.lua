-- Every nearby listener hears the drone; its pilot keeps a centered background mix.
-- Stereo WAVs use native 2D looping plus distance/pan mixing: BASS rejects these
-- files as 3D streams even with its mono flag (BASS_ERROR_NO3D).
if isfunction(_G.ProbeDroidStopAudio) then _G.ProbeDroidStopAudio() end

local hoverVolume = CreateClientConVar("probe_droid_hover_volume", "0.3", true, false,
    "Probe hover volume (pilot and nearby drones).", 0, 1)
local speechVolume = CreateClientConVar("probe_droid_speech_volume", "0.7", true, false,
    "Probe speech volume (pilot and nearby drones).", 0, 1)
local hoverFile = "sound/probe_droid/probedroidhover.wav"
local speechFiles = {
    "sound/probe_droid/probedroidspeak1.wav",
    "sound/probe_droid/probedroidspeak2.wav",
    "sound/probe_droid/probedroidspeak3.wav"
}
local sessions, nextScan = {}, 0
local innerRange, startRange, outerRange = 128, 1600, 1800
local channelKeys = {"hover", "speech"}

local function stopChannel(channel)
    if IsValid(channel) then channel:Stop() end
end
local function stopSession(probe)
    local session = sessions[probe]
    if not session then return end
    sessions[probe] = nil
    stopChannel(session.hover)
    stopChannel(session.speech)
end
local function stopAudio()
    for probe in pairs(sessions) do stopSession(probe) end
end
_G.ProbeDroidStopAudio = stopAudio
hook.Add("ShutDown", "ProbeDroid.Audio", stopAudio)

local function probePilot(probe)
    if not IsValid(probe) or probe:GetClass() ~= "sent_probe_droid"
        or not isfunction(probe.GetPilot) then return end
    local pilot = probe:GetPilot()
    if IsValid(pilot) and pilot:Alive() then return pilot end
end
local function position(probe)
    return isfunction(probe.GetCameraPosition) and probe:GetCameraPosition() or probe:WorldSpaceCenter()
end
local function voiceVolume(session, volume)
    -- Apply to both the pilot and nearby listeners, including clips loaded
    -- asynchronously after the drone has entered or left stealth.
    return volume:GetFloat() * session.gain * (session.probe:GetStealth() and 0.25 or 1)
end
local function updateMix(session, listener, right)
    local delta = position(session.probe) - listener
    local distance = delta:Length()
    session.gain = session.pilot and 1 or 1 - math.Clamp((distance - innerRange) / (outerRange - innerRange), 0, 1)
    session.pan = session.pilot and 0 or math.Clamp(delta:Dot(right) / math.max(distance, 1), -1, 1)
    for _, voice in ipairs(channelKeys) do
        local channel = session[voice]
        if IsValid(channel) then
            local volume = voiceVolume(session, voice == "hover" and hoverVolume or speechVolume)
            local previousVolume = session[voice .. "Volume"]
            if not previousVolume or math.abs(previousVolume - volume) > 0.001 then
                channel:SetVolume(volume)
                session[voice .. "Volume"] = volume
            end
            local previousPan = session[voice .. "Pan"]
            if not previousPan or math.abs(previousPan - session.pan) > 0.001 then
                channel:SetPan(session.pan)
                session[voice .. "Pan"] = session.pan
            end
        end
    end
    return distance
end
local function loadAudio(session, path, looped, cue, started)
    sound.PlayFile(path, "noplay noblock", function(channel, errorID, errorName)
        if sessions[session.probe] ~= session or not IsValid(session.probe)
            or (not looped and session.lastCue ~= cue) then
            stopChannel(channel)
            return
        end
        if looped then session.loadingHover = false end
        if not IsValid(channel) then
            if not session.warned[path] then
                session.warned[path] = true
                ErrorNoHalt("[Probe Droid audio] " .. path .. ": " .. tostring(errorName or errorID) .. "\n")
            end
            if looped then session.retryHover = RealTime() + 5 end
            return
        end
        channel:EnableLooping(looped)
        local key = looped and "hover" or "speech"
        if not looped then
            local age = math.max(CurTime() - started, 0)
            if age >= channel:GetLength() then channel:Stop() return end
            if age > 0.05 then channel:SetTime(age) end
        end
        session[key] = channel
        local volume = voiceVolume(session, looped and hoverVolume or speechVolume)
        channel:SetVolume(volume)
        session[key .. "Volume"] = volume
        channel:SetPan(session.pan)
        session[key .. "Pan"] = session.pan
        channel:Play()
    end)
end

hook.Add("Think", "ProbeDroid.Audio", function()
    local ply = LocalPlayer()
    if not IsValid(ply) then stopAudio() return end
    local controlled = ply:Alive() and ply:GetNW2Entity("ProbeDroidControlled")
    local listener, right, now = EyePos(), EyeAngles():Right(), RealTime()
    if now >= nextScan then
        nextScan = now + 0.25
        for _, probe in ipairs(ents.FindByClass("sent_probe_droid")) do
            local pilot = probePilot(probe)
            local own = pilot == ply and probe == controlled
            if pilot and (own or (pilot ~= ply and position(probe):DistToSqr(listener) <= startRange ^ 2)) then
                if sessions[probe] and sessions[probe].pilot ~= own then stopSession(probe) end
                sessions[probe] = sessions[probe] or {probe = probe, pilot = own, retryHover = 0, warned = {}}
            end
        end
    end
    for probe, session in pairs(sessions) do
        local pilot = probePilot(probe)
        local own = pilot == ply and probe == controlled
        if not pilot or (pilot == ply and not own) or session.pilot ~= own
            or (not own and position(probe):DistToSqr(listener) > outerRange ^ 2) then
            stopSession(probe)
        else
            updateMix(session, listener, right)
            if not IsValid(session.hover) and not session.loadingHover and now >= session.retryHover then
                session.loadingHover = true
                loadAudio(session, hoverFile, true)
            end
            local cue = probe:GetNW2String("ProbeDroidSpeechCue", "")
            if cue ~= session.lastCue then
                session.lastCue = cue
                local index, started = string.match(cue, "^(%d):([%d%.]+)$")
                index, started = tonumber(index), tonumber(started)
                if speechFiles[index] and started and CurTime() - started >= -1 and CurTime() - started < 2 then
                    stopChannel(session.speech)
                    loadAudio(session, speechFiles[index], false, cue, started)
                end
            end
        end
    end
end)
