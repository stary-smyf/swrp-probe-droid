The probe thermal renderer adapts the **Thermal** preset (goggle 2) from the
supplied `NVG-1/lua/nvgloadouts/splintercell.lua`, together with material lifecycle
handling from `Gmod-NVGBase-main/lua/autorun/client/nvgbase_hud.lua`.

Upstream projects: SplinterCellNVG and NVGBase by JWalkerMailly:
https://github.com/JWalkerMailly/SplinterCellNVG
https://github.com/JWalkerMailly/Gmod-NVGBase

`materials/probe_droid/thermal/heat.vtf` is the supplied
`effects/splinter_cell/thermal_noise.vtf`. The heat material preserves its animated
texture proxy. `lookup.vtf` preserves the pixels of the supplied `thermal.png`,
converted to native VTF format for Source material loading and distribution.
`noise.vtf` is the supplied `vgui/splinter_cell/noise.vtf`, with its animated
material adapted to the probe's material namespace.
The bloom, colour correction, lookup, motion blur, noise, and illuminator settings
come from that preset. The goggles framework, player-model restrictions, key
bindings, lens animations, and sounds are not installed or activated.

Night vision adapts the **Night** preset (goggle 1) from the same supplied
SplinterCellNVG loadout. Its two bloom passes, colour correction, light adaptation,
static overlay and projected illuminator settings replace the former probe
night-vision effect, with the tint changed to red. `materials/probe_droid/nightvision/grain.vtf` is the supplied
`vgui/splinter_cell/noise.vtf`; `grain.vmt` adapts
`effects/splinter_cell/scct_green_static.vmt` to the probe material namespace.
The probe keeps its own N toggle, vignette and HUD instead of the goggles lens
animations, player-model restrictions or framework bindings.

