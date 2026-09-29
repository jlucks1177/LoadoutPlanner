-- SpecBar.lua
-- Spec switching buttons. ns.CreateSpecButtons builds a row of them
-- anywhere; it's used in our window's header, and optionally on the
-- talent tab's bottom bar (off by default, since other addons often put
-- their own buttons there).

local addonName, ns = ...

-- Position of the optional talent-tab bar, from the talent window's
-- bottom-right corner (negative X = further left).
local BAR_OFFSET_X = -375
local BAR_OFFSET_Y = 22

-- Blizzard has been moving spec functions into C_SpecializationInfo.
-- Use the classic global if it exists, otherwise the newer version.
local specAPI = C_SpecializationInfo or {}
local getSpecIndex = GetSpecialization or specAPI.GetSpecialization
local getSpecInfo = GetSpecializationInfo or specAPI.GetSpecializationInfo
local setSpec = SetSpecialization or specAPI.SetSpecialization

-- How many selectable specs this class has (4 for druids, 2 for demon
-- hunters, 3 for most). Tries the classic function, then the newer one.
local function numSpecs()
    if GetNumSpecializations then
        return GetNumSpecializations()
    end
    local _, _, classID = UnitClass("player")
    local count = specAPI.GetNumSpecializationsForClassID
        and specAPI.GetNumSpecializationsForClassID(classID)
    return count or 4
end

function ns.SwitchSpec(index)
    if InCombatLockdown() then
        ns.Print("Can't change specialization in combat.")
        return
    end
    if index == getSpecIndex() then
        return
    end
    setSpec(index) -- starts the "Changing Specialization" cast
end

-- Spec index (1-4, what SwitchSpec wants) for a spec ID (e.g. 102).
function ns.SpecIndexForID(specID)
    for index = 1, numSpecs() do
        if getSpecInfo(index) == specID then
            return index
        end
    end
end

-- The class's specs as { icon, name } items (used by the icon picker).
function ns.GetSpecList()
    local list = {}
    for index = 1, numSpecs() do
        local specID, name, _, icon = getSpecInfo(index)
        if specID then
            table.insert(list, { icon = icon, name = name })
        end
    end
    return list
end

-- Every row of spec buttons we've made, so one update refreshes them all.
local allRows = {}

local function updateRow(row)
    local current = getSpecIndex()
    for index, button in ipairs(row.buttons) do
        local active = (index == current)
        button.icon:SetDesaturated(not active) -- gray out inactive specs
        button.icon:SetAlpha(active and 1 or 0.75)
        ns.Style.SetIconActive(button.ring, active) -- gold = your spec, grey = the others
    end
end

local function updateAll()
    for _, row in ipairs(allRows) do
        updateRow(row)
    end
end

local function showTooltip(button)
    GameTooltip:SetOwner(button, "ANCHOR_TOP")
    GameTooltip:SetText(button.specName)
    if button.role and _G[button.role] then
        -- "TANK", "HEALER", "DAMAGER" are also names of global,
        -- already-translated strings. Handy for localization.
        GameTooltip:AddLine(_G[button.role], 1, 1, 1)
    end
    if button.index == getSpecIndex() then
        GameTooltip:AddLine("Active", 0.25, 1, 0.25)
    else
        GameTooltip:AddLine("Click to switch", 0.7, 0.7, 0.7)
    end
    GameTooltip:Show()
end

-- Build a row of spec buttons inside `parent`. Returns the row frame
-- (sized to fit), which the caller positions.
function ns.CreateSpecButtons(parent, size, spacing)
    local row = CreateFrame("Frame", nil, parent)
    row.buttons = {}

    -- BUG FIX (v0.5): the old loop asked for specs 1-5 and stopped at the
    -- first empty slot. But every class also has a hidden level-1 "starter"
    -- spec, and the game hands it back at index 5, so druids got a fifth
    -- button that couldn't do anything. Ask how many REAL specs there are.
    for index = 1, numSpecs() do
        local specID, name, _, icon, role = getSpecInfo(index)
        if not specID then
            break
        end

        local button = CreateFrame("Button", nil, row)
        button:SetSize(size, size)
        button:SetPoint("LEFT", row, "LEFT", (index - 1) * (size + spacing), 0)
        button.index, button.specName, button.role = index, name, role

        button.icon = button:CreateTexture(nil, "ARTWORK")
        button.icon:SetAllPoints()
        button.icon:SetTexture(icon)
        button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) -- trim the icon's built-in border

        -- The same ring as the loadout list (Style.lua): gold for your
        -- current spec, a grey square for the others, corners masked.
        button.ring = ns.Style.AddIconBorder(button, button.icon)

        button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

        -- `index` is a fresh local each loop pass (a numeric for-loop gives
        -- every iteration its own copy), so each button remembers its spec.
        button:SetScript("OnClick", function() ns.SwitchSpec(index) end)
        button:SetScript("OnEnter", showTooltip)
        button:SetScript("OnLeave", GameTooltip_Hide)

        row.buttons[index] = button
    end

    row:SetSize(math.max(1, #row.buttons * (size + spacing) - spacing), size)
    table.insert(allRows, row)
    updateRow(row)
    return row
end

ns.On("PLAYER_SPECIALIZATION_CHANGED", function(unit)
    if unit == "player" then
        updateAll()
    end
end)

------------------------------------------------------------------------
-- Optional bar on the talent tab itself
------------------------------------------------------------------------
local talentTabBar

function ns.UpdateTalentTabBar()
    if talentTabBar then
        talentTabBar:SetShown(ns.db and ns.db.showTalentTabBar or false)
    end
end

EventUtil.ContinueOnAddOnLoaded("Blizzard_PlayerSpells", function()
    if not PlayerSpellsFrame then return end
    -- Parented to the Talents TAB, so it only shows on that tab.
    local host = PlayerSpellsFrame.TalentsFrame or PlayerSpellsFrame
    talentTabBar = ns.CreateSpecButtons(host, 34, 10) -- room for the rings between icons
    talentTabBar:SetFrameLevel(host:GetFrameLevel() + 200)
    talentTabBar:SetPoint("BOTTOMRIGHT", PlayerSpellsFrame, "BOTTOMRIGHT", BAR_OFFSET_X, BAR_OFFSET_Y)
    ns.UpdateTalentTabBar()
end)
