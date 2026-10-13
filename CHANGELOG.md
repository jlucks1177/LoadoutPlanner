# Changelog

## v0.20.2

### Updated for patch 12.1.5
- Marked compatible with 12.1.5 (`## Interface: 120105`), so the addon isn't listed as out of date. It still loads on 12.1.0.
- Checked against Blizzard's 12.1.5 UI source: the talent, loadout, Adventure Guide, raid lockout, map and encounter APIs the addon uses are unchanged, and it doesn't use any of the helper functions Blizzard removed.
- The new raid, **The Unbinding of Kith'ix**, shows up automatically (tag panel, icons, boss prompts). Its **flexible Mythic** difficulty counts as **Mythic**, so your M tags apply, and **Story Mode** counts as **LFR**.

### Improved
- `/lp why`: when the next boss has no build to offer, it now says which difficulty it looked for and lists the tags that boss **does** have in your current spec (for example "M Vash on Mythic"), so a tag on the wrong difficulty or in your other spec is obvious.
