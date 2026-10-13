# Changelog

## v0.20.1

### Updated for patch 12.1.5
- Marked compatible with 12.1.5 (`## Interface: 120105`), so the addon isn't listed as out of date. It still loads on 12.1.0.
- Checked against Blizzard's 12.1.5 UI source: the talent, loadout, Adventure Guide, raid lockout, map and encounter APIs the addon uses are unchanged, and it doesn't use any of the helper functions Blizzard removed.
- The new raid, **The Unbinding of Kith'ix**, shows up automatically (tag panel, icons, boss prompts). Its **flexible Mythic** difficulty counts as **Mythic**, so your M tags apply, and **Story Mode** counts as **LFR**.

### Fixed
- **Boss prompts often didn't work at all:** inside a raid, the addon frequently couldn't read the raid's boss list, so it reported "no boss left" and offered nothing. The game's Adventure Guide only lists a raid's bosses once that raid is selected in it, and this lookup didn't select it. The same issue caused the missing boss icons fixed in v0.19. It now uses the season's boss list (the same one your tags come from), and selects the raid first when it has to ask the Adventure Guide directly. This also affected the boss part of the zone-in prompt and `/lp bosses`, `/lp boss`, `/lp tagboss`.
- Boss prompts sometimes didn't appear after a kill (reported with "Any"-difficulty boss tags). If the game's kill event didn't match the Adventure Guide's boss ID and your lockout hadn't updated yet, the boss you'd just killed still counted as "next". You were wearing its build, so nothing was offered. Kills are now also matched by the boss's name, and the addon checks again a few seconds later once the lockout catches up.
- `/lp why` now shows how many bosses it found and how many count as dead, and the last boss kill it saw (and whether it was matched to a boss).
