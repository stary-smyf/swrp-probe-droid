include("shared.lua")

function ENT:Draw()
    if self:GetStealth() then return end
    local ply = LocalPlayer()
    if IsValid(ply) and ply:GetNW2Entity("ProbeDroidControlled") == self then return end
    self:DrawModel()
end

function ENT:DrawTranslucent()
    if not self:GetStealth() then return end
    local ply = LocalPlayer()
    if IsValid(ply) and ply:GetNW2Entity("ProbeDroidControlled") == self then return end
    local blend = render.GetBlend()
    render.SetBlend(blend * 0.5)
    self:DrawModel()
    render.SetBlend(blend)
end
