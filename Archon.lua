-- Archon.lua
-- Getting builds from archon.gg, by hand.
--
-- Why by hand: since 2026-08-27 archon.gg answers automated requests with
-- a "Human Verification" page (Cloudflare), and its operator has asked an
-- addon author to stop using its data. Addons can't reach the internet
-- anyway, and data addons that used to ship Archon builds have dropped
-- them. So LoadoutPlanner doesn't fetch anything from Archon. Instead it
-- gives you the exact archon.gg link for your spec and a boss or dungeon,
-- you open it in your browser as a normal visitor, and paste the talent
-- string back in. One paste saves AND tags the build.

local addonName, ns = ...

------------------------------------------------------------------------
-- archon.gg links
------------------------------------------------------------------------
-- specID -> archon.gg's "<spec>/<class>" path. From the MIT-licensed
-- ArchonTalentsData project (tools/maps.mjs), which built these URLs
-- while Archon still allowed it.
local SPEC_SLUGS = {
    [71] = "arms/warrior", [72] = "fury/warrior", [73] = "protection/warrior",
    [65] = "holy/paladin", [66] = "protection/paladin", [70] = "retribution/paladin",
    [253] = "beast-mastery/hunter", [254] = "marksmanship/hunter", [255] = "survival/hunter",
    [259] = "assassination/rogue", [260] = "outlaw/rogue", [261] = "subtlety/rogue",
    [256] = "discipline/priest", [257] = "holy/priest", [258] = "shadow/priest",
    [250] = "blood/death-knight", [251] = "frost/death-knight", [252] = "unholy/death-knight",
    [262] = "elemental/shaman", [263] = "enhancement/shaman", [264] = "restoration/shaman",
    [62] = "arcane/mage", [63] = "fire/mage", [64] = "frost/mage",
    [265] = "affliction/warlock", [266] = "demonology/warlock", [267] = "destruction/warlock",
    [268] = "brewmaster/monk", [269] = "windwalker/monk", [270] = "mistweaver/monk",
    [102] = "balance/druid", [103] = "feral/druid", [104] = "guardian/druid", [105] = "restoration/druid",
    [577] = "havoc/demon-hunter", [581] = "vengeance/demon-hunter", [1480] = "devourer/demon-hunter",
    [1467] = "devastation/evoker", [1468] = "preservation/evoker", [1473] = "augmentation/evoker",
}

-- Most archon slugs are just the English name, lowercased and hyphenated
-- ("Den of Nalorakk" -> "den-of-nalorakk"). These are the current
-- season's exceptions (same source). Update them when a season changes.
local SLUG_OVERRIDES = {
    ["temple of sethraliss"] = "sethraliss",
    ["nymrissa wavecaller"] = "nymrissa",
    ["nek'zali the soulcoiler"] = "nekzali",
    ["entombed sentinels"] = "sentinels",
    ["the lost explorers"] = "explorers",
    ["vashnik the malignant"] = "vashnik",
}

-- "Kings' Rest" -> "kings-rest"
local function slugify(name)
    local lower = name:lower()
    if SLUG_OVERRIDES[lower] then
        return SLUG_OVERRIDES[lower]
    end
    local slug = lower:gsub("'", "")          -- apostrophes vanish: "ula'tek" -> "ulatek"
    slug = slug:gsub("[^%w]+", "-")           -- anything else becomes a hyphen
    slug = slug:gsub("^%-+", ""):gsub("%-+$", "")
    return slug
end
ns.ArchonSlug = slugify

-- Archon's difficulty words for raids. It has no Raid Finder data.
local RAID_DIFFICULTY = { [14] = "normal", [15] = "heroic", [16] = "mythic" }

-- The archon.gg URL for a spec and target.
-- target: { label, isAll, instanceType ("party"/"raid"), difficulty }
-- Returns url, note (note explains a substitution, e.g. LFR -> Normal).
function ns.ArchonURL(specID, target)
    local specSlug = SPEC_SLUGS[specID]
    if not specSlug then
        return "https://www.archon.gg/wow", "Archon link for this spec isn't known; this is Archon's home page."
    end
    local base = "https://www.archon.gg/wow/builds/" .. specSlug
    if target.instanceType == "party" then
        local slug = target.isAll and "all-dungeons" or slugify(target.label)
        -- "10" = Archon's keystone level filter; "this-week" = current affixes.
        return ("%s/mythic-plus/talents/10/%s/this-week"):format(base, slug)
    end
    local difficulty, note = RAID_DIFFICULTY[target.difficulty], nil
    if not difficulty then
        difficulty = "normal"
        note = "Archon has no Raid Finder builds, so this links to Normal."
    end
    local slug = target.isAll and "all-bosses" or slugify(target.label)
    return ("%s/raid/talents/%s/%s"):format(base, difficulty, slug), note
end

------------------------------------------------------------------------
-- The link + paste dialog
------------------------------------------------------------------------
local WIDTH = 460

-- Blizzard's metal-bordered panel with a title bar (Style.lua).
local dialog = ns.Style.CreatePanel("LoadoutPlannerArchonDialog", UIParent)
dialog:SetSize(WIDTH, 250)
dialog:SetPoint("CENTER", 0, 80)
dialog:SetFrameStrata("FULLSCREEN_DIALOG")
dialog:EnableMouse(true)
dialog:SetMovable(true)
dialog:SetClampedToScreen(true)
dialog:RegisterForDrag("LeftButton")
dialog:SetScript("OnDragStart", dialog.StartMoving)
dialog:SetScript("OnDragStop", dialog.StopMovingOrSizing)
dialog:Hide()
table.insert(UISpecialFrames, "LoadoutPlannerArchonDialog")


local function label(text, y)
    local fs = dialog:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetPoint("TOPLEFT", 18, y)
    fs:SetPoint("RIGHT", -18, 0)
    fs:SetJustifyH("LEFT")
    fs:SetText(text)
    return fs
end

local function box(y)
    local b = CreateFrame("EditBox", nil, dialog, "InputBoxTemplate")
    b:SetSize(WIDTH - 44, 20)
    b:SetPoint("TOPLEFT", 24, y)
    b:SetAutoFocus(false)
    b:SetMaxLetters(0)
    b:SetScript("OnEscapePressed", b.ClearFocus)
    return b
end

label("1. Copy this link (|cffffffffCtrl+C|r) and open it in your web browser:", -44)
local linkBox = box(-62)
dialog.note = dialog:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
dialog.note:SetPoint("TOPLEFT", linkBox, "BOTTOMLEFT", -4, -4)
dialog.note:SetPoint("RIGHT", -18, 0)
dialog.note:SetJustifyH("LEFT")

label("2. On Archon, copy the talent string, then paste it here (|cffffffffCtrl+V|r):", -112)
local pasteBox = box(-130)

local status = dialog:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
status:SetPoint("TOPLEFT", pasteBox, "BOTTOMLEFT", -4, -6)
status:SetPoint("RIGHT", -18, 0)
status:SetJustifyH("LEFT")

-- The link box is for copying only: whatever you type, the link comes back,
-- and clicking into it selects everything so Ctrl+C grabs the whole URL.
local currentURL = ""
linkBox:SetScript("OnTextChanged", function(self, userInput)
    if userInput then
        self:SetText(currentURL)
        self:HighlightText()
    end
end)
linkBox:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
linkBox:SetScript("OnMouseUp", function(self) self:HighlightText() end)

local target -- what the dialog is for (see ns.OpenArchonDialog)
local validSpecID

local saveTagButton = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
local saveButton = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")

local function validate()
    local specID, specNameOrError = ns.ReadCodeHeader(pasteBox:GetText())
    validSpecID = specID
    local canTag = specID and target and target.tag and specID == ns.GetSpecID()
    if specID then
        if specID == ns.GetSpecID() then
            status:SetText("|cff40ff40OK:|r " .. specNameOrError .. " build")
        else
            status:SetText("|cffffd100" .. specNameOrError .. " build.|r Tags belong to your current spec, "
                .. "so this can be saved but not tagged. Switch spec to tag it.")
        end
    elseif pasteBox:GetText() == "" then
        status:SetText("")
    else
        status:SetText("|cffff6060" .. specNameOrError .. "|r")
    end
    saveButton:SetEnabled(specID ~= nil)
    saveTagButton:SetEnabled(canTag and true or false)
end
pasteBox:SetScript("OnTextChanged", validate)

local function save(withTag)
    if not (validSpecID and target) then return end
    local name = ("%s (%s, Archon)"):format(target.label, target.difficultyText)
    local build, reused = ns.SaveExternalBuild(pasteBox:GetText(), name, "Archon", target.icon,
        withTag and target.tag or nil)
    ns.Print(("%s |cffffd100%s|r%s."):format(reused and "Already in your library:" or "Saved",
        build.name, withTag and (" and tagged to " .. target.label .. " (" .. target.difficultyText .. ")") or ""))
    dialog:Hide()
end

saveTagButton:SetSize(120, 22)
saveTagButton:SetPoint("BOTTOMRIGHT", -16, 14)
saveTagButton:SetText("Save and tag")
saveTagButton:SetScript("OnClick", function() save(true) end)

saveButton:SetSize(90, 22)
saveButton:SetPoint("RIGHT", saveTagButton, "LEFT", -6, 0)
saveButton:SetText("Save")
saveButton:SetScript("OnClick", function() save(false) end)

local cancel = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
cancel:SetSize(80, 22)
cancel:SetPoint("RIGHT", saveButton, "LEFT", -6, 0)
cancel:SetText("Cancel")
cancel:SetScript("OnClick", function() dialog:Hide() end)

-- t = {
--   label          = "Murder Row" / "All dungeons"
--   isAll          = true for the whole-content ("All ...") target
--   instanceType   = "party" or "raid"
--   difficulty     = our difficulty ID (8 = Mythic+, 14-17 = raid)
--   difficultyText = "Mythic+", "Heroic", ...
--   icon           = icon for the saved build
--   tag            = { kind, id, label, icon, difficulty } for "Save and tag", or nil
-- }
function ns.OpenArchonDialog(t)
    target = t
    local url, note = ns.ArchonURL(ns.GetSpecID(), t)
    currentURL = url
    dialog.title:SetText(("Archon: %s (%s)"):format(t.label, t.difficultyText))
    dialog.note:SetText(note or "Archon may ask you to confirm you're human; that's normal in a browser.")
    linkBox:SetText(url)
    linkBox:SetCursorPosition(0)
    pasteBox:SetText("")
    saveTagButton:SetShown(t.tag ~= nil)
    validate()
    dialog:Show()
    linkBox:SetFocus()
    linkBox:HighlightText()
end
