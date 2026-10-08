-- test_importdialog.lua
-- The checkbox LoadoutPlanner adds under Blizzard's talent Import dialog:
-- ticked, the pasted code is applied onto your selected loadout (like a
-- custom build) instead of Blizzard creating a new loadout.

package.path = "tools/test/?.lua;" .. package.path
local wow = require("wow")
wow.install({ modern = true })
print("Blizzard import dialog test")

-- A code whose header reads as "Balance (102), current format".
local CODE = ("C"):rep(60)
ExportUtil = { MakeImportDataStream = function() return {
    GetNumberOfBits = function() return 999 end,
    ExtractValue = function(_, bits) if bits == 8 then return 2 end return 102 end } end }

-- Blizzard's dialog, as the talent window's addon would create it.
local pasted, typedName = CODE, "My import"
local blizzardImports = 0
local dialog = wow.newObj("ClassTalentLoadoutImportDialog")
dialog.ImportControl = { GetText = function() return pasted end }
dialog.NameControl = wow.newObj()
dialog.NameControl.GetText = function() return typedName end
dialog.AcceptButton = wow.newObj()
dialog.AcceptButton:SetScript("OnClick", function() blizzardImports = blizzardImports + 1 end)
dialog.shown = true

local ns = {}
for _, file in ipairs(wow.tocFiles()) do wow.loadAddonFile(file, ns) end
local dispatcher
for _, o in ipairs(wow.created) do
    if o.scripts and o.scripts.OnEvent then dispatcher = o break end
end
dispatcher.scripts.OnEvent(dispatcher, "ADDON_LOADED", "LoadoutPlanner")
for _, fn in ipairs(wow.hooks) do fn() end -- the talent window's addon has loaded

local option = dialog.loadoutPlannerOption
wow.check(type(option) == "table", "the checkbox is added to Blizzard's Import dialog")
if not option then wow.finish() end

-- Stand-ins for the talent-changing code (tested in game, not here).
local applied, applyResult = {}, true
ns.GetBuildEntries = function(code) if code == CODE then return {} end return nil, "This build is for Feral. Switch spec first." end
ns.ApplyBuild = function(build) table.insert(applied, build) return applyResult end

-- Off by default: Blizzard's own Import button is what you click.
wow.check(option.check:GetChecked() == false and not option.apply.shown,
    "unticked by default: Blizzard's Import button is left alone")

-- Tick it.
option.check.checked = true
option.check.scripts.OnClick(option.check)
wow.check(ns.db.importOntoActive == true, "ticking it is remembered")
wow.check(option.apply.shown == true, "ticked: our \"Apply to loadout\" button covers Blizzard's Import button")
wow.check(wow.plain(option.status.text):find("No new loadout", 1, true) ~= nil, "it says no new loadout will be made")

-- Click Apply: the code goes through ns.ApplyBuild, and the dialog closes.
option.apply.scripts.OnClick(option.apply)
wow.check(#applied == 1 and applied[1].code == CODE and applied[1].specID == 102 and applied[1].name == "My import",
    "applies the pasted code like a custom build (code, spec, and the typed name)")
wow.check(blizzardImports == 0, "Blizzard's import (a new loadout) doesn't run")
wow.check(dialog.shown == false, "the dialog closes after applying")

-- No name typed: still works (no loadout is being named).
dialog.shown, typedName = true, ""
option.apply.scripts.OnClick(option.apply)
wow.check(#applied == 2 and applied[2].name == "Imported talents", "a name isn't needed")

-- A code that can't be used: say why, change nothing, stay open.
dialog.shown, pasted = true, ("D"):rep(60)
option.apply.scripts.OnClick(option.apply)
wow.check(#applied == 2 and dialog.shown == true, "a code for another spec isn't applied, and the dialog stays open")
wow.check(wow.plain(option.status.text):find("Feral", 1, true) ~= nil, "and the reason is shown under the checkbox")

-- The game refuses (combat, ...): stay open.
pasted, applyResult = CODE, nil
option.apply.scripts.OnClick(option.apply)
wow.check(#applied == 3 and dialog.shown == true, "if the change is refused, the dialog stays open")

-- Starter Build selected: nothing to save into, so the option is off.
ns.GetSelectedConfigID = function() return Constants.TraitConsts.STARTER_BUILD_TRAIT_CONFIG_ID end
option.refresh()
wow.check(option.check:GetChecked() == false and not option.apply.shown and option.check.enabled == false,
    "with the Starter Build selected, the option is disabled")

-- Untick: back to Blizzard's behaviour.
ns.GetSelectedConfigID = function() return 11 end
option.check.checked = false
option.check.scripts.OnClick(option.check)
wow.check(ns.db.importOntoActive == false and not option.apply.shown, "unticking gives Blizzard's Import button back")

wow.finish()
