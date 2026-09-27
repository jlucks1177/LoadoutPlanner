-- Core.lua
-- The foundation: shared namespace, a print helper, an event dispatcher,
-- and slash command routing. Every other file builds on these.

-- WoW passes two values to every file in your addon: the addon's folder name
-- and a private table shared by all your files. Putting things on `ns`
-- instead of creating globals keeps you from colliding with other addons.
local addonName, ns = ...

ns.name = addonName

------------------------------------------------------------------------
-- Printing
------------------------------------------------------------------------
-- |cffRRGGBB ... |r is WoW's inline color code syntax.
function ns.Print(...)
    print("|cff33ff99LoadoutPlanner:|r", ...)
end

------------------------------------------------------------------------
-- Event dispatcher
------------------------------------------------------------------------
-- Addons don't run in a loop. The game calls you when events happen, and
-- only frames can receive events. So we create one invisible frame and let
-- any file register a handler for any event through ns.On().
local eventFrame = CreateFrame("Frame")
local handlers = {} -- event name -> list of handler functions

function ns.On(event, fn)
    if not handlers[event] then
        handlers[event] = {}
        -- Registering an event name that doesn't exist throws an error.
        -- Blizzard renames events between expansions, so catch it with pcall
        -- and warn, instead of letting one bad name break the whole addon.
        local ok = pcall(eventFrame.RegisterEvent, eventFrame, event)
        if not ok then
            print("|cff33ff99LoadoutPlanner:|r unknown event " .. event)
        end
    end
    table.insert(handlers[event], fn)
end

-- Unsubscribe a handler (used for one-time waits, e.g. "tell me when this
-- loadout finishes being created").
function ns.Off(event, fn)
    local list = handlers[event]
    if not list then return end
    for i = #list, 1, -1 do -- walk backwards so removing doesn't skip items
        if list[i] == fn then
            table.remove(list, i)
        end
    end
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    -- Copy the list first: a handler might call ns.Off while we're looping.
    local snapshot = { unpack(handlers[event]) }
    for _, fn in ipairs(snapshot) do
        fn(...)
    end
end)

-- A tiny internal "something changed" signal. UI files subscribe with
-- ns.OnRefresh(fn); everything else just calls ns.Notify() without needing
-- to know which UI pieces exist. (Same idea as ns.On, but for our own
-- events instead of the game's.)
local refreshers = {}

function ns.OnRefresh(fn)
    table.insert(refreshers, fn)
end

-- Each refresher runs in pcall: if one piece of UI has a bug, the others
-- still refresh, AND the code that called Notify (like the zone-in check)
-- keeps going. The error is still reported (BugSack sees it).
function ns.Notify()
    for _, fn in ipairs(refreshers) do
        local ok, err = pcall(fn)
        if not ok then
            geterrorhandler()(err)
        end
    end
end

------------------------------------------------------------------------
-- Slash commands
------------------------------------------------------------------------
-- The game discovers slash commands through globals named SLASH_<KEY><n>
-- and a matching function in SlashCmdList[<KEY>].
SLASH_LOADOUTPLANNER1 = "/lp"
SLASH_LOADOUTPLANNER2 = "/loadoutplanner"

-- Other files add their own commands to this table.
ns.commands = {}

ns.commands.help = function()
    ns.Print("Commands:")
    print("  /lp - open/tuck away the window (talent window must be open)")
    print("  /lp list - list loadouts for your current spec")
    print("  /lp load <name> - load a loadout, or apply a custom build, by name")
    print("  /lp tag <name> - tag a loadout to the current dungeon/raid")
    print("  /lp untag - remove the current instance's tag")
    print("  /lp bosses - list bosses in the current raid/dungeon")
    print("  /lp tagboss <#> <name> - tag a loadout to boss number #")
    print("  /lp boss <#> - load the build tagged to boss number #")
    print("  /lp tags - show all tags for your current spec")
    print("  /lp why - explain what the zone-in prompt sees here")
    print("  /lp prompt - show the zone-in prompt again")
    print("  /lp reset - reopen the window and restore default options")
    print("  /lp importtle - copy groups and loadouts from Talent Loadout Ex")
    print("  /lp top - top builds for your spec (data addon + Archon links)")
    print("  In the window: click a build to put it on the talent screen,")
    print("  double-click to apply it; right-click for options; hover to compare.")
end

SlashCmdList.LOADOUTPLANNER = function(msg)
    -- Split "tag My Raid Build" into cmd = "tag", rest = "My Raid Build".
    -- Lua patterns are like a lightweight regex: %S = non-space, %s = space.
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")
    cmd = cmd:lower()
    if cmd == "" then
        cmd = "toggle"
    end

    local fn = ns.commands[cmd]
    if fn then
        fn(rest)
    else
        ns.commands.help()
    end
end
