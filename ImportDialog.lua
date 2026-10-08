-- ImportDialog.lua
-- A checkbox on BLIZZARD'S talent Import dialog (talent window > loadout
-- dropdown > Import): "Apply to my current loadout instead of creating a
-- new one".
--
-- Blizzard's Import always makes a NEW loadout. With the box ticked, the
-- pasted code is applied the way LoadoutPlanner applies your custom builds
-- (ns.ApplyBuild in Import.lua): your talents change, and the result saves
-- into the Blizzard loadout you have selected.
--
-- How it's added without touching Blizzard's code (CLAUDE.md, "Taint"):
--   * the checkbox sits on a small strip of OUR OWN, attached under the
--     dialog, so it can't overlap anything Blizzard put inside it;
--   * when ticked, a button of ours covers Blizzard's Import button. A
--     click then lands on ours, and Blizzard's "create a new loadout" code
--     simply never runs. Nothing of Blizzard's is replaced or hooked
--     except HookScript("OnShow").
-- If the dialog isn't there, or isn't shaped as expected (a future patch),
-- we add nothing.

local addonName, ns = ...
local Style = ns.Style

-- VERIFY: frame and field names, from Blizzard_PlayerSpells
-- (ClassTalentLoadoutImportDialog: ImportControl, NameControl,
-- AcceptButton, CancelButton). Check with /fstack if the box is missing.
local DIALOG_NAME = "ClassTalentLoadoutImportDialog"

-- The text typed into one of the dialog's two fields.
local function controlText(control)
    if type(control) ~= "table" then return "" end
    if type(control.GetText) == "function" then
        local ok, text = pcall(control.GetText, control)
        if ok and type(text) == "string" then return text end
    end
    local box = type(control.InputContainer) == "table" and control.InputContainer.EditBox or control.EditBox
    if type(box) == "table" and box.GetText then
        return box:GetText() or ""
    end
    return ""
end

-- The Blizzard loadout an applied code would save into, or nil if there
-- isn't one you can change (none selected, or the Starter Build).
local function targetLoadoutName()
    local selected = ns.GetSelectedConfigID()
    if not selected or ns.IsStarterBuild(selected) then return nil end
    local info = C_Traits.GetConfigInfo(selected)
    return info and info.name or nil
end

local function closeDialog(dialog)
    -- Blizzard's own Cancel does this; fall back to plain Hide.
    if StaticPopupSpecial_Hide then
        local ok = pcall(StaticPopupSpecial_Hide, dialog)
        if ok then return end
    end
    dialog:Hide()
end

local function setup()
    local dialog = _G[DIALOG_NAME]
    if type(dialog) ~= "table" or dialog.loadoutPlannerOption then return end
    local accept = dialog.AcceptButton
    if type(accept) ~= "table" or type(dialog.ImportControl) ~= "table" then
        return -- not the dialog we know: leave it alone
    end

    --------------------------------------------------------------------
    -- Our strip under the dialog
    --------------------------------------------------------------------
    local strip, isTooltipTemplate = Style.CreateTooltipFrame(nil, dialog)
    if not isTooltipTemplate and strip.SetBackdrop then
        strip:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 14,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        strip:SetBackdropColor(0.03, 0.03, 0.05, 0.95)
    end
    strip:SetPoint("TOPLEFT", dialog, "BOTTOMLEFT", 6, 2)
    strip:SetPoint("TOPRIGHT", dialog, "BOTTOMRIGHT", -6, 2)
    strip:SetHeight(58)

    local check = CreateFrame("CheckButton", nil, strip, "UICheckButtonTemplate")
    check:SetSize(26, 26)
    check:SetPoint("TOPLEFT", 8, -6)

    local label = strip:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("LEFT", check, "RIGHT", 4, 0)
    label:SetPoint("RIGHT", strip, "RIGHT", -10, 0)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)

    -- One line under the checkbox: what will happen, or what went wrong.
    local status = strip:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    status:SetPoint("TOPLEFT", 14, -34)
    status:SetPoint("RIGHT", strip, "RIGHT", -10, 0)
    status:SetJustifyH("LEFT")
    status:SetWordWrap(false)

    --------------------------------------------------------------------
    -- Our button, covering Blizzard's Import button while the box is ticked
    --------------------------------------------------------------------
    local apply = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
    apply:SetAllPoints(accept)
    apply:SetFrameLevel((accept:GetFrameLevel() or 1) + 10)
    apply:SetText("Apply to loadout")
    apply:Hide()

    local function refresh()
        local target = targetLoadoutName()
        local wanted = ns.db and ns.db.importOntoActive == true
        local on = wanted and target ~= nil
        check:SetEnabled(target ~= nil)
        check:SetChecked(on)
        apply:SetShown(on)
        if target then
            label:SetText(("Apply to my current loadout (|cffffd100%s|r) instead"):format(target))
            label:SetTextColor(1, 1, 1)
        else
            label:SetText("Apply to my current loadout instead")
            label:SetTextColor(0.5, 0.5, 0.5)
        end
        -- With the box ticked no new loadout is made, so its name isn't used.
        if type(dialog.NameControl) == "table" and dialog.NameControl.SetAlpha then
            dialog.NameControl:SetAlpha(on and 0.35 or 1)
        end
        if not target then
            status:SetText("Select one of your own loadouts first (not the Starter Build).")
        elseif on then
            status:SetText("Changes your talents now and saves them into that loadout. No new loadout is made.")
        else
            status:SetText("LoadoutPlanner: leave unticked to import as a new loadout, as usual.")
        end
    end

    check:SetScript("OnClick", function(self)
        if ns.db then
            ns.db.importOntoActive = self:GetChecked() and true or false
        end
        refresh()
    end)

    apply:SetScript("OnClick", function()
        local code = (controlText(dialog.ImportControl):gsub("%s", ""))
        local specID, problem = ns.ReadCodeHeader(code)
        if specID then
            -- Catches "wrong spec" and "the tree changed" before anything is touched.
            local entries, err = ns.GetBuildEntries(code)
            if not entries then specID, problem = nil, err end
        end
        if not specID then
            status:SetText("|cffff6060" .. tostring(problem or "That code can't be used.") .. "|r")
            return
        end
        local name = strtrim(controlText(dialog.NameControl))
        local ok = ns.ApplyBuild({ code = code, specID = specID, name = name ~= "" and name or "Imported talents" })
        if ok then
            closeDialog(dialog)
        else
            -- ApplyBuild already said why in chat (combat, Starter Build, ...).
            status:SetText("|cffff6060Couldn't apply it. See the chat window for why.|r")
        end
    end)

    dialog:HookScript("OnShow", refresh)
    dialog.loadoutPlannerOption = { check = check, apply = apply, status = status, refresh = refresh }
    refresh()
end
ns.SetupImportDialog = setup -- for the tests

-- The dialog is created with the talent window's addon. Try then, and
-- again whenever the talent window opens, in case it's created later.
EventUtil.ContinueOnAddOnLoaded("Blizzard_PlayerSpells", function()
    setup()
    if PlayerSpellsFrame and PlayerSpellsFrame.HookScript then
        PlayerSpellsFrame:HookScript("OnShow", setup)
    end
end)
