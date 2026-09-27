-- Prompt.lua
-- The zone-in prompt: "Change talents for <place>?" with one button per
-- build tagged here. It's our own frame rather than Blizzard's yes/no
-- popup, because there can be several good answers at once (a Mythic
-- build AND a Mythic+ build, or a build per boss).

local addonName, ns = ...

local WIDTH = 330
local ROW_HEIGHT = 34
local MAX_ROWS = 6

-- Blizzard's metal-bordered panel with a title bar (Style.lua).
local prompt = ns.Style.CreatePanel("LoadoutPlannerPrompt", UIParent)
prompt:SetWidth(WIDTH)
prompt:SetPoint("TOP", 0, -140)
prompt:SetFrameStrata("DIALOG")
prompt:EnableMouse(true)
prompt:SetMovable(true)
prompt:SetClampedToScreen(true)
prompt:RegisterForDrag("LeftButton")
prompt:SetScript("OnDragStart", prompt.StartMoving)
prompt:SetScript("OnDragStop", prompt.StopMovingOrSizing)
prompt:Hide()

prompt.subtitle = prompt:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
prompt.subtitle:SetPoint("TOPLEFT", 12, ns.Style.CONTENT_TOP)
prompt.subtitle:SetPoint("RIGHT", -12, 0)
prompt.subtitle:SetJustifyH("LEFT") -- may wrap to two lines; rows start below that

local close = prompt.CloseButton
close:SetScript("OnClick", function() prompt:Hide() end)

-- "Keep current": say no for this visit. (CheckContext already remembers
-- it asked here, so it won't ask again until you leave and come back.)
local keep = CreateFrame("Button", nil, prompt, "UIPanelButtonTemplate")
keep:SetSize(WIDTH - 20, 22)
keep:SetPoint("BOTTOM", 0, 10)
keep:SetScript("OnClick", function(self)
    prompt:Hide()
    if self.currentName then
        ns.Print(("Keeping |cffffd100%s|r for this visit."):format(self.currentName))
    end
end)

-- The name of what you're wearing now: the selected Blizzard loadout, or
-- the custom build whose talents match yours exactly.
local function currentLoadoutName()
    for _, group in ipairs(ns.GetGroups()) do
        for _, build in ipairs(group.builds) do
            if build.specID == ns.GetSpecID() and ns.ItemMatchesCurrent(ns.ItemFromBuild(build)) then
                return build.name
            end
        end
    end
    local selected = ns.GetSelectedConfigID()
    local info = selected and not ns.IsStarterBuild(selected) and C_Traits.GetConfigInfo(selected)
    return info and info.name or nil
end

local rows = {}
local function createRow(index)
    local row = CreateFrame("Button", nil, prompt)
    row:SetSize(WIDTH - 20, ROW_HEIGHT - 4)
    row:SetPoint("TOPLEFT", 10, -64 - (index - 1) * ROW_HEIGHT)
    row.bg = ns.Style.AddRowBackground(row)
    ns.Style.SetRowHighlight(row)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(26, 26)
    row.icon:SetPoint("LEFT", 4, 0)
    row.ring = ns.Style.AddIconBorder(row, row.icon)

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, -1)
    row.name:SetPoint("RIGHT", -6, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    -- A visible "Switch" on each option, so it's obvious rows are buttons.
    row.action = row:CreateFontString(nil, "OVERLAY", "GameFontGreen")
    row.action:SetPoint("RIGHT", -8, 0)
    row.name:SetPoint("RIGHT", row.action, "LEFT", -6, 0)

    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.label:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -2)
    row.label:SetPoint("RIGHT", -6, 0)
    row.label:SetJustifyH("LEFT")

    -- The same row serves two prompts, so what a click (and hover) does
    -- is stored on the row each time it's filled in.
    row:SetScript("OnClick", function(self)
        ns.HideDiff()
        prompt:Hide()
        self.onClick()
    end)
    row:SetScript("OnEnter", function(self)
        if self.onEnter then self.onEnter(self) end
    end)
    row:SetScript("OnLeave", function()
        ns.HideDiff()
        GameTooltip:Hide()
    end)
    return row
end

-- Fill rows from a list of { icon, name, label, onClick, onEnter, action }.
local function showRows(entries, keepText)
    local shown = math.min(#entries, MAX_ROWS)
    for i = 1, shown do
        rows[i] = rows[i] or createRow(i)
        local row, entry = rows[i], entries[i]
        row.name:SetText(entry.name)
        row.label:SetText(entry.label)
        ns.SetIcon(row.icon, entry.icon, true)
        row.onClick, row.onEnter = entry.onClick, entry.onEnter
        row.action:SetText(entry.action or "Switch")
        row:Show()
    end
    for i = shown + 1, #rows do
        rows[i]:Hide()
    end
    keep:SetText(keepText)
    prompt:SetHeight(64 + shown * ROW_HEIGHT + 40)
    prompt:Show()
    PlaySound(SOUNDKIT.IG_MAINMENU_OPEN)
end

local function placeName(instance)
    local difficulty = ns.DIFFICULTY_BY_ID[instance.difficulty]
    return instance.name .. (difficulty and (" (" .. difficulty.name .. ")") or "")
end

-- candidates: from ns.GetCandidates: { { item, ref, label }, ... }
function ns.ShowZonePrompt(instance, candidates)
    prompt.title:SetText(("Change talents for %s?"):format(placeName(instance)))
    local current = currentLoadoutName()
    keep.currentName = current or "your current talents"
    prompt.subtitle:SetText(("You're on: |cffffffff%s|r. Switch to a tagged build (hover to compare)?")
        :format(current or "untagged talents"))

    local specIcon = select(4, GetSpecializationInfoByID(ns.GetSpecID() or 0))
    local entries = {}
    for _, candidate in ipairs(candidates) do
        local item = candidate.item
        table.insert(entries, {
            name = item.name,
            label = "Tagged: " .. candidate.label,
            icon = (item.build and item.build.icon) or (candidate.ref and candidate.ref.icon) or specIcon,
            onClick = function() ns.LoadItem(item) end, -- applies, like a double-click
            onEnter = function(row) ns.ShowDiff(row, item) end,
        })
    end
    showRows(entries, current and ("Keep " .. current) or "Keep current talents")
end

-- The place is tagged, but only in OTHER specs. others: from
-- ns.GetOtherSpecMatches: { { specID, name, icon, candidates }, ... }
function ns.ShowSpecPrompt(instance, others)
    local _, currentName = GetSpecializationInfoByID(ns.GetSpecID() or 0)
    prompt.title:SetText(("%s is tagged for another spec"):format(placeName(instance)))
    prompt.subtitle:SetText(("You're %s. Switch spec to get its builds offered:"):format(currentName or "in another spec"))

    local entries = {}
    for _, other in ipairs(others) do
        local names = {}
        for _, candidate in ipairs(other.candidates) do
            table.insert(names, (candidate.ref.name or "?") .. " (" .. candidate.label .. ")")
        end
        local specIndex = ns.SpecIndexForID(other.specID)
        table.insert(entries, {
            name = other.name,
            action = "Switch spec",
            label = "Tagged: " .. table.concat(names, ", "),
            icon = other.icon,
            onClick = function()
                if specIndex then
                    ns.SwitchSpec(specIndex) -- the build prompt follows once it's done
                end
            end,
            onEnter = function(row)
                GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
                GameTooltip:SetText(other.name .. " builds tagged here:")
                for _, name in ipairs(names) do
                    GameTooltip:AddLine(name, 1, 1, 1)
                end
                GameTooltip:AddLine("After switching, you'll be offered these builds.", 0.7, 0.7, 0.7, true)
                GameTooltip:Show()
            end,
        })
    end
    keep.currentName = currentName
    showRows(entries, ("Stay %s"):format(currentName or "in this spec"))
end

function ns.HideZonePrompt()
    prompt:Hide()
end
