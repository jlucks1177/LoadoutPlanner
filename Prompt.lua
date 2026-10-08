-- Prompt.lua
-- The zone-in prompt: "Change talents for <place>?" with one button per
-- build tagged here. It's our own frame rather than Blizzard's yes/no
-- popup, because there can be several good answers at once (a Mythic
-- build AND a Mythic+ build, or a build per boss).

local addonName, ns = ...

local WIDTH = 360
local ROW_MIN_HEIGHT = 40 -- rows grow past this when their second line wraps
local ROW_GAP = 4
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
-- A fixed width and ONE anchor (top-left), so its height follows the text.
-- (A "RIGHT" anchor is the middle of the right edge: it would pin the
-- text's vertical centre too and squeeze it, which cut text off in v0.20.)
prompt.subtitle:SetPoint("TOPLEFT", 14, ns.Style.CONTENT_TOP - 2)
prompt.subtitle:SetWidth(WIDTH - 28)
prompt.subtitle:SetJustifyH("LEFT") -- may wrap to two lines; rows start below that

local close = prompt.CloseButton
close:SetScript("OnClick", function() prompt:Hide() end)

-- "Keep current": say no for this visit. (CheckContext already remembers
-- it asked here, so it won't ask again until you leave and come back.)
local keep = CreateFrame("Button", nil, prompt, "UIPanelButtonTemplate")
keep:SetSize(WIDTH - 24, 24)
keep:SetPoint("BOTTOM", 0, 12)
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
-- Rows are laid out top to bottom in showRows, each as tall as its text
-- needs (a long second line wraps instead of spilling out of the row).
local TEXT_LEFT = 8 + 30 + 10 -- icon inset + icon + gap
local ACTION_WIDTH = 64
-- Text column width: the row minus the icon side and the "Switch" column.
-- Set as a WIDTH (not a right-hand anchor; see the subtitle above) so a
-- long line wraps onto more lines instead of being cut off with "...".
local TEXT_WIDTH = (WIDTH - 24) - TEXT_LEFT - ACTION_WIDTH - 16

local function createRow()
    local row = CreateFrame("Button", nil, prompt)
    row:SetWidth(WIDTH - 24)
    row.bg = ns.Style.AddRowBackground(row)
    ns.Style.SetRowHighlight(row)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(30, 30)
    row.icon:SetPoint("LEFT", 8, 0)
    row.ring = ns.Style.AddIconBorder(row, row.icon)

    -- A visible "Switch" on each option, so it's obvious rows are buttons.
    row.action = row:CreateFontString(nil, "OVERLAY", "GameFontGreen")
    row.action:SetPoint("RIGHT", -10, 0)
    row.action:SetWidth(ACTION_WIDTH)
    row.action:SetJustifyH("RIGHT")

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.name:SetPoint("TOPLEFT", TEXT_LEFT, -7)
    row.name:SetWidth(TEXT_WIDTH)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(true)

    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.label:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -3)
    row.label:SetWidth(TEXT_WIDTH)
    row.label:SetJustifyH("LEFT")
    row.label:SetWordWrap(true)

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

-- A font string's height once its text is set (0 if the game can't say yet).
local function textHeight(fontString, fallback)
    local h = fontString.GetStringHeight and fontString:GetStringHeight()
    if type(h) ~= "number" or h <= 0 then return fallback end
    return h
end

-- Fill rows from a list of { icon, name, label, onClick, onEnter, action }.
-- Everything is measured: the rows start below the subtitle (however many
-- lines it took), each row is as tall as its text, and the window's
-- height is the sum, so nothing overlaps or spills past an edge.
local function showRows(entries, keepText)
    local shown = math.min(#entries, MAX_ROWS)
    local y = -(-ns.Style.CONTENT_TOP + textHeight(prompt.subtitle, 24) + 10)
    for i = 1, shown do
        rows[i] = rows[i] or createRow()
        local row, entry = rows[i], entries[i]
        row.name:SetText(entry.name)
        row.label:SetText(entry.label)
        ns.SetIcon(row.icon, entry.icon, true)
        row.onClick, row.onEnter = entry.onClick, entry.onEnter
        row.action:SetText(entry.action or "Switch")
        local height = math.max(ROW_MIN_HEIGHT,
            7 + textHeight(row.name, 14) + 3 + textHeight(row.label, 12) + 8)
        row:SetHeight(height)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 12, y)
        row:Show()
        y = y - height - ROW_GAP
    end
    for i = shown + 1, #rows do
        rows[i]:Hide()
    end
    keep:SetText(keepText)
    -- Rows, then 8px, then the Keep button (24 tall) and 12px below it.
    prompt:SetHeight(-y - ROW_GAP + 8 + 24 + 12)
    prompt:Show()
    PlaySound(SOUNDKIT.IG_MAINMENU_OPEN)
end

local function placeName(instance)
    local difficulty = ns.DIFFICULTY_BY_ID[instance.difficulty]
    return instance.name .. (difficulty and (" (" .. difficulty.name .. ")") or "")
end

-- candidates: from ns.GetCandidates: { { item, ref, label }, ... }
-- title: optional (the boss prompts name the boss instead of the place).
function ns.ShowZonePrompt(instance, candidates, title)
    prompt.title:SetText(title or ("Change talents for %s?"):format(placeName(instance)))
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
            -- candidate.note: a line of its own (the boss prompts use it).
            label = candidate.note or ("Tagged: " .. candidate.label),
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
