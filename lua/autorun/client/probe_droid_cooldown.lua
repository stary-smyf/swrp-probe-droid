local background = Color(30, 43, 47, 210)
local fill = Color(185, 185, 185, 255)

hook.Add("HUDPaint", "ProbeDroid.SpawnCooldown", function()
    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:Alive()
        or IsValid(ply:GetNW2Entity("ProbeDroidControlled")) then return end
    local weapon = ply:GetActiveWeapon()
    if not IsValid(weapon) or weapon:GetClass() ~= "weapon_probe_droid" then return end

    local started = ply:GetNW2Float("ProbeDroidCooldownStarted", -1)
    local duration = GetGlobalFloat("ProbeDroidSpawnCooldown", 0)
        * ply:GetNW2Float("ProbeDroidCooldownMultiplier", 1)
    local elapsed = CurTime() - started
    if started < 0 or duration <= 0 or elapsed >= duration then return end

    local progress = math.Clamp(elapsed / duration, 0, 1)
    local scale = math.Clamp(ScrH() / 1080, 0.65, 1.5)
    local width, height = 300 * scale, 8 * scale
    local x, y = (ScrW() - width) * 0.5, ScrH() * 0.5 + 32 * scale
    draw.RoundedBox(2 * scale, x, y, width, height, background)
    if progress > 0 then
        draw.RoundedBox(2 * scale, x, y, width * progress, height, fill)
    end
end)
