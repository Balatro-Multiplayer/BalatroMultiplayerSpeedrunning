-- Title-screen art for the speedrun logo. The layered swap itself is driven by MPAPI via the
-- `title` config in register_mod (see core.lua); these atlases supply its base/extra layers.
SMODS.Atlas({ key = 'speedrun_title_base', path = 'speedrun_title_base.png', px = 333, py = 216 })
SMODS.Atlas({ key = 'speedrun_title_extra', path = 'speedrun_title_extra.png', px = 333, py = 216 })
