-- test_load.lua
-- Loads the whole addon in TOC order, fires ADDON_LOADED, opens the talent
-- window and LoadoutPlanner's window, and opens Top builds.
-- Run with a mode: modern (today's game), fallback (no atlases or modern
-- scroll bars), missing (Blizzard templates renamed or removed).

package.path = "tools/test/?.lua;" .. package.path
local wow = require("wow")
local mode = arg[1] or "modern"
wow.install({ modern = mode == "modern", missing = mode == "missing" })
print("load test, mode: " .. mode)

local ns = {}
local files = wow.tocFiles()
local loaded = 0
for _, file in ipairs(files) do
    local ok, err = pcall(wow.loadAddonFile, file, ns)
    wow.check(ok, "loads " .. file .. (ok and "" or (": " .. tostring(err))))
    if ok then loaded = loaded + 1 end
end
if loaded < #files then wow.finish() end

-- What WoW does once the talent window's own addon loads.
for _, fn in ipairs(wow.hooks) do
    local ok, err = pcall(fn)
    wow.check(ok, "talent-window hook runs" .. (ok and "" or (": " .. tostring(err))))
end

-- Find the addon's event frame and send it ADDON_LOADED.
local dispatcher
for _, o in ipairs(wow.created) do
    if o.scripts and o.scripts.OnEvent then dispatcher = o break end
end
wow.check(dispatcher ~= nil, "has an event frame")
dispatcher.scripts.OnEvent(dispatcher, "ADDON_LOADED", "LoadoutPlanner")
wow.check(ns.db ~= nil, "saved settings created on ADDON_LOADED")

-- Open the talent window, then LoadoutPlanner's window.
PlayerSpellsFrame.shown = true
local window = _G.LoadoutPlannerWindow
wow.check(window ~= nil, "main window exists")
window.shown = false
local ok, err = pcall(window.Show, window)
wow.check(ok, "main window opens" .. (ok and "" or (": " .. tostring(err))))
wow.check(window.title and window.title.text == "LoadoutPlanner", "main window has its title")
if mode == "modern" then
    wow.check(window.specArt and window.specArt.shown, "spec art shows behind the list")
else
    wow.check(not (window.specArt and window.specArt.shown), "spec art stays hidden without atlases")
end

ok, err = pcall(ns.Notify)
wow.check(ok, "list refresh runs" .. (ok and "" or (": " .. tostring(err))))

ok, err = pcall(SlashCmdList.LOADOUTPLANNER, "top")
wow.check(ok, "/lp top runs" .. (ok and "" or (": " .. tostring(err))))
wow.check(_G.LoadoutPlannerTopBuilds and _G.LoadoutPlannerTopBuilds.shown, "Top builds panel opens")

-- The build editor (Import button): opens, and its icon grid draws.
ok, err = pcall(ns.OpenEditor, {})
wow.check(ok, "build editor opens" .. (ok and "" or (": " .. tostring(err))))
wow.check(_G.LoadoutPlannerEditor and _G.LoadoutPlannerEditor.shown, "build editor is shown")
local lit = 0
for _, o in ipairs(wow.created) do
    if o.isSelectedTab then lit = lit + 1 end
end
wow.check(lit >= 1, "the chosen Top builds tab shows as selected")

-- The zone-in / boss prompt opens with its measured layout code running
-- (the fake game can't check sizes; the layout itself is checked in game).
local entries = {
    { item = { name = "Sszorak Keepers" }, note = "Next boss: Sszorak" },
    { item = { name = "Twin Fangs" }, note = "Only if you're using a different kill order (boss 6)" },
}
ok, err = pcall(ns.ShowZonePrompt, { name = "Raid", difficulty = 15 }, entries, "Change talents for Sszorak?")
wow.check(ok, "the prompt opens" .. (ok and "" or (": " .. tostring(err))))
local promptFrame = _G.LoadoutPlannerPrompt
wow.check(promptFrame and promptFrame.shown and promptFrame.title.text == "Change talents for Sszorak?",
    "the boss prompt shows with the boss in its title")
if mode == "missing" then
    wow.check((wow.templates.BackdropTemplate or 0) > 1, "falls back to plain frames when templates are gone")
end
wow.finish()
