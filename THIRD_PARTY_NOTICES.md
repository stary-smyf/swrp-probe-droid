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

