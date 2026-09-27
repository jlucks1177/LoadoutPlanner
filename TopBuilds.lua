-- TopBuilds.lua
-- "Top builds": the most-played build for your spec on each of this
-- season's dungeons and raid bosses, from a data addon, plus an Archon
-- link for each (see Archon.lua).
--
-- Where the builds come from: addons can't use the internet, so build data
-- has to arrive as ANOTHER addon full of Lua tables, updated outside the
-- game. There are two sources, switchable at the top of the panel:
--
-- Both sources can come BUILT IN: Data/Builtin.lua (global
-- LoadoutPlannerBuiltin = { parses = {...}, raiderio = {...} }) is refreshed
-- daily by a GitHub Action and shipped with each release, so players need no
-- setup. A personal sync or a separately installed data addon is used
-- instead when it's newer.
--
-- 1. Raider.IO: the LoadoutPlannerData addon, written by our own
--    companion script (LoadoutPlannerSync) from the official Raider.IO API.
--    Global LoadoutPlannerData = { generated, season, mythic = {
--      [specID] = { { target, isAll, samples, builds = { {code, count, share}, ... } }, ... } },
--      raid = { heroic = { [specID] = {...} }, mythic = {...} } }
--
-- 2. parses.gg: the shared "PeaversTalentsData" interface, provided by:
--   * ArchonTalentsData (github.com/EliteTC/ArchonTalentsData) - updated
--     daily from parses.gg, real logged pulls. Recommended.
--   * PeaversTalentsData - the original addon with the same interface.
-- Both expose API.GetBuilds(classID, specID), returning a list of
--   { category, dungeonID (0 = "All ..."), label, talentString, updated }
-- where category is "mythic" (Mythic+), "lfr_raid", "normal_raid",
-- "heroic_raid" or "mythic_raid". Labels are dungeon/boss names, so we
-- match them to the Encounter Journal by name.

local addonName, ns = ...

local WIDTH, HEIGHT = 420, 540
local ROW_HEIGHT = 40

-- The five tabs, in display order. `difficulty` is our difficulty ID
-- (Journal.lua), used for tagging and the Archon link.
local TABS = {
    { key = "mythic", text = "M+", name = "Mythic+", type = "party", difficulty = 8 },
    { key = "lfr_raid", text = "LFR", name = "Raid Finder", type = "raid", difficulty = 17 },
    { key = "normal_raid", text = "Normal", name = "Normal", type = "raid", difficulty = 14 },
    { key = "heroic_raid", text = "Heroic", name = "Heroic", type = "raid", difficulty = 15 },
    { key = "mythic_raid", text = "Mythic", name = "Mythic", type = "raid", difficulty = 16 },
}
local TAB_BY_KEY = {}
for _, tab in ipairs(TABS) do TAB_BY_KEY[tab.key] = tab end

------------------------------------------------------------------------
-- Reading the data addon
------------------------------------------------------------------------
local function dataAPI()
    local lib = _G.PeaversTalentsData
    local api = type(lib) == "table" and lib.API
    if type(api) == "table" and type(api.GetBuilds) == "function" then
        return api
    end
end

-- Which data addon is providing it, for the header line.
local function providerName()
    if C_AddOns and C_AddOns.IsAddOnLoaded then
        if C_AddOns.IsAddOnLoaded("ArchonTalentsData") then return "ArchonTalentsData" end
        if C_AddOns.IsAddOnLoaded("PeaversTalentsData") then return "PeaversTalentsData" end
    end
    return "a data addon"
end

-- A real talent string: base64 characters only, and long enough. This
-- filters out placeholders like "No data on wowcompare.io - Coming soon!"
-- that an older data addon shipped.
local function looksLikeCode(text)
    return type(text) == "string" and #text > 40 and text:match("^[%w+/=]+$") ~= nil
end

-- "Nek'zali the Soulcoiler" and "Nekzali the soulcoiler" compare equal.
local function norm(name)
    return (tostring(name or ""):lower():gsub("[^%w]", ""))
end

------------------------------------------------------------------------
-- Source 1: Raider.IO (LoadoutPlannerData, from LoadoutPlannerSync)
------------------------------------------------------------------------
local RAIDERIO_RAID_CATEGORY = { lfr = "lfr_raid", normal = "normal_raid", heroic = "heroic_raid", mythic = "mythic_raid" }

-- Data built into LoadoutPlanner (Data/Builtin.lua), by source key.
local function builtin(key)
    local all = _G.LoadoutPlannerBuiltin
    local data = type(all) == "table" and all[key]
    if type(data) == "table" and type(data.mythic) == "table" then
        return data
    end
end

-- Whole days since an ISO timestamp like "2026-09-26T23:44:32Z" (nil if unreadable).
local function ageDays(stamp)
    local y, m, d = tostring(stamp or ""):match("^(%d+)-(%d+)-(%d+)")
    if not y then return nil end
    local then_ = time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 })
    return math.floor((time() - then_) / 86400 + 0.5)
end

-- The newer of two datasets. ISO timestamps sort as plain text.
local function newer(a, b)
    if not a then return b end
    if not b then return a end
    return tostring(b.generated or "") > tostring(a.generated or "") and b or a
end

-- Raider.IO data: your own sync (LoadoutPlannerData) or the built-in copy,
-- whichever is newer. Second value: true if it's the built-in one.
local function raiderioData()
    local personal = _G.LoadoutPlannerData
    if not (type(personal) == "table" and personal.source == "raider.io") then
        personal = nil
    end
    local data = newer(personal, builtin("raiderio"))
    return data, data ~= nil and data ~= personal
end

-- Convert one spec's entries into the same shape parses.gg data has, plus
-- popularity: share, samples, and the runner-up builds.
local function convertEntries(entries, category, updated, out)
    for index, entry in ipairs(type(entries) == "table" and entries or {}) do
        local builds = type(entry.builds) == "table" and entry.builds or {}
        local top = builds[1]
        if top and looksLikeCode(top.code) then
            local alternatives = {}
            for i = 2, #builds do
                if looksLikeCode(builds[i].code) then
                    table.insert(alternatives, builds[i])
                end
            end
            table.insert(out, {
                category = category,
                dungeonID = entry.isAll and 0 or index,
                label = entry.target,
                talentString = top.code,
                updated = updated,
                share = tonumber(top.share),
                samples = tonumber(entry.samples),
                alternatives = alternatives,
            })
        end
    end
end

-- Any dataset in the LoadoutPlannerData shape -> a flat list of builds.
local function buildsFromData(data, specID)
    if not data then return nil end
    local list = {}
    convertEntries(data.mythic and data.mythic[specID], "mythic", data.generated, list)
    for difficulty, bySpec in pairs(type(data.raid) == "table" and data.raid or {}) do
        local category = RAIDERIO_RAID_CATEGORY[difficulty]
        if category and type(bySpec) == "table" then
            convertEntries(bySpec[specID], category, data.generated, list)
        end
    end
    return list
end

local function raiderioBuilds(specID)
    return buildsFromData(raiderioData(), specID)
end

------------------------------------------------------------------------
-- Source 2: parses.gg (PeaversTalentsData interface)
------------------------------------------------------------------------
-- Built-in parses.gg data wins, unless it's over 3 days old (you haven't
-- updated the addon) and a data addon like ArchonTalentsData is installed.
local function useBuiltinParses()
    local data = builtin("parses")
    if not data then return nil end
    local age = ageDays(data.generated)
    if dataAPI() and age and age > 3 then return nil end
    return data
end

local function parsesBuilds(specID)
    local data = useBuiltinParses()
    if data then return buildsFromData(data, specID) end
    local api = dataAPI()
    if not api then return nil end
    local _, _, classID = UnitClass("player")
    local ok, builds = pcall(api.GetBuilds, classID, specID)
    return (ok and type(builds) == "table") and builds or {}
end

-- The sources, in the order their buttons appear.
local SOURCES = {
    { key = "raiderio", text = "Raider.IO", read = raiderioBuilds, available = function() return raiderioData() ~= nil end },
    { key = "parses", text = "parses.gg", read = parsesBuilds,
        available = function() return builtin("parses") ~= nil or dataAPI() ~= nil end },
}
local SOURCE_BY_KEY = {}
for _, source in ipairs(SOURCES) do SOURCE_BY_KEY[source.key] = source end

-- The chosen source: your last choice, else the first one installed.
local function currentSource()
    local chosen = ns.db and SOURCE_BY_KEY[ns.db.topSource or ""]
    if chosen then return chosen end
    for _, source in ipairs(SOURCES) do
        if source.available() then return source end
    end
    return SOURCES[1]
end

-- Builds for a spec from a source, grouped by category:
-- { mythic = { build, ... }, heroic_raid = {...}, ... }.
-- Returns nil when that source isn't installed.
function ns.GetTopBuilds(specID, sourceKey)
    local source = SOURCE_BY_KEY[sourceKey or ""] or currentSource()
    local builds = source.read(specID)
    if not builds then return nil end
    local byCategory = {}
    for _, build in ipairs(builds) do
        if type(build) == "table" and TAB_BY_KEY[build.category] and looksLikeCode(build.talentString) then
            local list = byCategory[build.category] or {}
            byCategory[build.category] = list
            table.insert(list, build)
        end
    end
    return byCategory
end

------------------------------------------------------------------------
-- Rows: this season's targets, each with its top build (if any)
------------------------------------------------------------------------
-- Row data: { label, icon, isAll, tag = {kind, id, label, icon, difficulty},
--             build = { code, specID, name } or nil }
local function buildRows(tab, specID, byCategory)
    local rows = {}
    local season = ns.GetSeason()
    local category = ns.CATEGORY_BY_ID[tab.type]

    -- Data builds by normalized label, and the "All ..." build (index 0).
    local dataBuilds, allBuild, used = {}, nil, {}
    for _, b in ipairs(byCategory and byCategory[tab.key] or {}) do
        if b.dungeonID == 0 then
            allBuild = allBuild or b
        else
            dataBuilds[norm(b.label)] = dataBuilds[norm(b.label)] or b
        end
    end

    local function add(label, icon, isAll, tag, b)
        if b then used[b] = true end
        table.insert(rows, {
            label = label, icon = icon, isAll = isAll, tag = tag,
            build = b and { code = b.talentString, specID = specID, name = ("%s (%s)"):format(label, tab.text) },
            updated = b and b.updated,
            share = b and b.share,
            samples = b and b.samples,
            alternatives = b and b.alternatives,
        })
    end

    -- "All dungeons" / "All bosses" first; tagged as the All dungeons /
    -- All raids category at this difficulty.
    add(tab.type == "party" and "All dungeons" or "All bosses", category and category.icon, true,
        category and { kind = "categories", id = category.id, label = category.label,
            icon = category.icon, difficulty = tab.difficulty },
        allBuild)

    if tab.type == "party" then
        for _, dungeon in ipairs(season.dungeons) do
            add(dungeon.name, dungeon.icon, false,
                dungeon.mapID and { kind = "instances", id = dungeon.mapID, label = dungeon.name,
                    icon = dungeon.icon, difficulty = tab.difficulty },
                dataBuilds[norm(dungeon.name)])
        end
    else
        for _, raid in ipairs(season.raids) do
            for _, boss in ipairs(raid.bosses) do
                local icon = boss.icon or raid.icon
                add(boss.name, icon, false,
                    { kind = "bosses", id = boss.encounterID, label = boss.name, icon = icon,
                        difficulty = tab.difficulty },
                    dataBuilds[norm(boss.name)])
            end
        end
    end

    -- Data for places the journal didn't list (name mismatch, e.g. another
    -- game language): still browsable and usable, just not taggable.
    for _, b in ipairs(byCategory and byCategory[tab.key] or {}) do
        if not used[b] and b.dungeonID ~= 0 then
            add(b.label, 134400, false, nil, b)
        end
    end
    return rows
end

------------------------------------------------------------------------
-- The panel
------------------------------------------------------------------------
-- Blizzard's metal-bordered panel with a title bar (Style.lua).
local panel = ns.Style.CreatePanel("LoadoutPlannerTopBuilds", UIParent)
panel:SetSize(WIDTH, HEIGHT)
panel:SetFrameStrata("FULLSCREEN")
panel:EnableMouse(true)
panel:SetClampedToScreen(true)
panel:Hide()
table.insert(UISpecialFrames, "LoadoutPlannerTopBuilds")


-- Source buttons, right under the title bar: which data the list shows.
local refresh -- defined below
local sourceButtons = {}
for i = #SOURCES, 1, -1 do -- laid out right to left
    local source = SOURCES[i]
    local button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    button:SetSize(76, 20)
    if i == #SOURCES then
        button:SetPoint("TOPRIGHT", -12, ns.Style.CONTENT_TOP)
    else
        button:SetPoint("RIGHT", sourceButtons[i + 1], "LEFT", -4, 0)
    end
    button:SetText(source.text)
    button:SetScript("OnClick", function()
        ns.db.topSource = source.key
        refresh()
    end)
    sourceButtons[i] = button
end

panel.source = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
panel.source:SetPoint("TOPLEFT", 14, -54)
panel.source:SetPoint("RIGHT", -14, 0)
panel.source:SetJustifyH("LEFT")

local sourceLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
sourceLabel:SetPoint("RIGHT", sourceButtons[1], "LEFT", -6, 0)
sourceLabel:SetText("Source:")

-- Tabs
local selectedTab = "mythic"
local tabButtons = {}

for i, tab in ipairs(TABS) do
    local button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    button:SetSize(64, 20)
    button:SetPoint("TOPLEFT", 12 + (i - 1) * 68, -84)
    button:SetText(tab.text)
    button:SetScript("OnClick", function()
        selectedTab = tab.key
        refresh()
    end)
    tabButtons[tab.key] = button
end

local hint = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
hint:SetPoint("TOPLEFT", 14, -110)
hint:SetPoint("RIGHT", -14, 0)
hint:SetJustifyH("LEFT")
hint:SetText("Click: put on talent screen | Double-click: apply | Right-click: save / tag | Hover: compare")

local scroll = ns.Style.CreateScrollFrame(panel, "LoadoutPlannerTopBuildsScroll")
scroll:SetPoint("TOPLEFT", 12, -126)
scroll:SetPoint("BOTTOMRIGHT", -24, 10)
local content = CreateFrame("Frame", nil, scroll)
content:SetSize(WIDTH - 36, 1)
scroll:SetScrollChild(content)

-- Is this exact build already in your library?
local function inLibrary(code)
    for _, group in ipairs(ns.GetGroups()) do
        for _, build in ipairs(group.builds) do
            if build.code == code then return build end
        end
    end
end

local function difficultyText(tab)
    return tab.name
end

local function archonTarget(row, tab)
    return {
        label = row.label, isAll = row.isAll, instanceType = tab.type,
        difficulty = tab.difficulty, difficultyText = difficultyText(tab),
        icon = row.icon, tag = row.tag,
    }
end

local function openRowMenu(frame, row, tab)
    MenuUtil.CreateContextMenu(frame, function(_, root)
        root:CreateTitle(("%s (%s)"):format(row.label, tab.name))
        local groupName = "Top builds: " .. tab.name
        if row.build then
            root:CreateButton("Save to library", function()
                local build, reused = ns.SaveExternalBuild(row.build.code, row.build.name, groupName, row.icon)
                ns.Print(("%s |cffffd100%s|r."):format(reused and "Already in your library:" or "Saved", build.name))
            end)
            if row.tag then
                root:CreateButton(("Save and tag to %s (%s)"):format(row.tag.label, tab.name), function()
                    local build = ns.SaveExternalBuild(row.build.code, row.build.name, groupName, row.icon, row.tag)
                    ns.Print(("Saved |cffffd100%s|r and tagged it to %s (%s)."):format(build.name, row.tag.label, tab.name))
                end)
            end
            root:CreateButton("Copy talent string", function()
                StaticPopup_Show("LOADOUTPLANNER_COPY", row.build.name, nil, { code = row.build.code })
            end)
            -- Runner-up builds (Raider.IO data has the top few per place).
            if row.alternatives and #row.alternatives > 0 then
                local others = root:CreateButton("Other popular builds")
                for rank, alt in ipairs(row.alternatives) do
                    local altBuild = { code = alt.code, specID = row.build.specID,
                        name = ("%s (%s, #%d)"):format(row.label, tab.text, rank + 1) }
                    local share = alt.share and (" - %d%%"):format(math.floor(alt.share * 100 + 0.5)) or ""
                    local sub = others:CreateButton(("#%d%s"):format(rank + 1, share))
                    sub:CreateButton("Put on talent screen", function() ns.StageBuild(altBuild) end)
                    sub:CreateButton("Apply now", function() ns.ApplyBuild(altBuild) end)
                    sub:CreateButton("Save to library", function()
                        local build, reused = ns.SaveExternalBuild(altBuild.code, altBuild.name, groupName, row.icon)
                        ns.Print(("%s |cffffd100%s|r."):format(reused and "Already in your library:" or "Saved", build.name))
                    end)
                    if row.tag then
                        sub:CreateButton("Save and tag", function()
                            local build = ns.SaveExternalBuild(altBuild.code, altBuild.name, groupName, row.icon, row.tag)
                            ns.Print(("Saved |cffffd100%s|r and tagged it to %s (%s)."):format(build.name, row.tag.label, tab.name))
                        end)
                    end
                end
            end
            root:CreateDivider()
        end
        root:CreateButton("Get from Archon...", function()
            ns.OpenArchonDialog(archonTarget(row, tab))
        end)
    end)
end

local rowFrames = {}

local function createRowFrame(index)
    local frame = CreateFrame("Button", nil, content)
    frame:SetSize(content:GetWidth(), ROW_HEIGHT - 4)
    frame:SetPoint("TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
    frame:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    frame.bg = ns.Style.AddRowBackground(frame)
    ns.Style.SetRowHighlight(frame)

    frame.icon = frame:CreateTexture(nil, "ARTWORK")
    frame.icon:SetSize(32, 32)
    frame.icon:SetPoint("LEFT", 4, 0)
    frame.ring = ns.Style.AddIconBorder(frame, frame.icon)

    frame.archon = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.archon:SetSize(64, 20)
    frame.archon:SetPoint("RIGHT", -4, 0)
    frame.archon:SetText("Archon")

    frame.name = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.name:SetPoint("TOPLEFT", frame.icon, "TOPRIGHT", 8, -1)
    frame.name:SetPoint("RIGHT", frame.archon, "LEFT", -6, 0)
    frame.name:SetJustifyH("LEFT")
    frame.name:SetWordWrap(false)

    frame.status = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.status:SetPoint("TOPLEFT", frame.name, "BOTTOMLEFT", 0, -3)
    frame.status:SetPoint("RIGHT", frame.archon, "LEFT", -6, 0)
    frame.status:SetJustifyH("LEFT")
    frame.status:SetWordWrap(false)

    frame:SetScript("OnClick", function(self, button)
        ns.HideDiff()
        if button == "RightButton" then
            openRowMenu(self, self.row, self.tab)
        elseif self.row.build then
            ns.HandleBuildClick(self, self.row.build)
        else
            ns.Print("No logged build here yet. Right-click for Archon.")
        end
    end)
    frame:SetScript("OnEnter", function(self)
        if self.row.build then
            ns.ShowDiff(self, { key = "t:" .. self.row.build.code, name = self.row.build.name, build = self.row.build })
        end
    end)
    frame:SetScript("OnLeave", ns.HideDiff)
    frame.archon:SetScript("OnClick", function()
        ns.OpenArchonDialog(archonTarget(frame.row, frame.tab))
    end)
    return frame
end

local function ageText(stamp)
    local age = ageDays(stamp)
    local text = age and ((age <= 0 and "today") or (age == 1 and "1 day ago") or (age .. " days ago")) or "?"
    if age and age >= 3 then
        text = "|cffff8040" .. text .. "|r"
    end
    return text
end

-- The header line under the title, per source.
local function sourceLine(source, byCategory)
    if source.key == "raiderio" then
        local data, isBuiltin = raiderioData()
        if not data then
            return "|cffffd100No Raider.IO data yet.|r It isn't included in this version of LoadoutPlanner. "
                .. "Advanced: run LoadoutPlannerSync yourself (see its README). Or use parses.gg."
        end
        return ("Most-played builds among top Raider.IO keys and guilds%s. %s, updated %s.")
            :format(data.season and data.season.name and (", " .. data.season.name) or "",
                isBuiltin and "Built in" or "Your own sync", ageText(data.generated))
    end
    local data = useBuiltinParses()
    if data then
        return ("Most-played builds from parses.gg logs%s. Built in, updated %s. Update LoadoutPlanner for fresh builds.")
            :format(data.season and data.season.name and (", " .. data.season.name) or "", ageText(data.generated))
    end
    if not byCategory then
        return "|cffffd100No parses.gg data.|r Update LoadoutPlanner (builds are included), or install "
            .. "|cffffffffArchonTalentsData|r. The Archon buttons work either way."
    end
    local updated
    for _, list in pairs(byCategory) do
        updated = updated or (list[1] and list[1].updated)
    end
    return ("Most-played builds from parses.gg logs, via %s%s.")
        :format(providerName(), updated and (" (updated " .. tostring(updated):sub(1, 10) .. ")") or "")
end

refresh = function()
    if not panel:IsShown() then return end
    local specID = ns.GetSpecID()
    local _, specName = GetSpecializationInfoByID(specID or 0)
    panel.title:SetText("Top builds: " .. (specName or "?"))

    local tab = TAB_BY_KEY[selectedTab]
    for key, button in pairs(tabButtons) do
        button:SetEnabled(key ~= selectedTab) -- the selected tab looks pressed
    end

    local source = currentSource()
    for i, button in ipairs(sourceButtons) do
        button:SetEnabled(SOURCES[i] ~= source) -- the selected source looks pressed
    end

    local byCategory = ns.GetTopBuilds(specID, source.key)
    local rows = buildRows(tab, specID, byCategory)
    panel.rows = rows -- kept for debugging (/dump LoadoutPlannerTopBuilds.rows)

    -- Header line: where the data comes from and how fresh it is.
    panel.source:SetText(sourceLine(source, byCategory))

    for i, row in ipairs(rows) do
        rowFrames[i] = rowFrames[i] or createRowFrame(i)
        local frame = rowFrames[i]
        frame.row, frame.tab = row, tab
        frame.name:SetText(row.label)
        ns.SetIcon(frame.icon, row.icon or 134400, true)

        local status, matches
        if not row.build then
            status = byCategory and "|cff808080No logged build yet|r" or ""
        else
            local item = { key = "t:" .. row.build.code, name = row.build.name, build = row.build }
            matches = ns.ItemMatchesCurrent(item)
            status = matches and "|cff40ff40Matches your talents|r" or "Top build"
            if row.share and row.samples then
                status = status .. (" |cffffffff%d%%|r of %d players"):format(math.floor(row.share * 100 + 0.5), row.samples)
            end
            local saved = inLibrary(row.build.code)
            if saved then
                status = status .. " |cff808080- saved as " .. saved.name .. "|r"
            end
        end
        frame.status:SetText(status)
        ns.Style.SetIconActive(frame.ring, matches) -- gold ring = your talents
        frame:Show()
    end
    for i = #rows + 1, #rowFrames do
        rowFrames[i]:Hide()
    end
    content:SetHeight(math.max(1, #rows * ROW_HEIGHT))
end

ns.OnRefresh(refresh)
panel:SetScript("OnShow", refresh)

-- Pick the tab that fits where you are: a dungeon shows M+, a raid shows
-- its difficulty. Elsewhere, keep the last tab.
local function tabForHere()
    local here = ns.GetCurrentInstance()
    if not here then return nil end
    if here.type == "party" then return "mythic" end
    for _, tab in ipairs(TABS) do
        if tab.type == "raid" and tab.difficulty == here.difficulty then
            return tab.key
        end
    end
end

function ns.OpenTopBuilds()
    selectedTab = tabForHere() or selectedTab
    ns.GetSeason(true)
    panel:ClearAllPoints()
    local window = ns.window
    if window and window:IsShown() then
        panel:SetPoint("TOPRIGHT", window, "TOPLEFT", -6, 0)
    else
        panel:SetPoint("CENTER")
    end
    if ns.CloseTagPanel then ns.CloseTagPanel() end -- they open in the same spot
    if panel:IsShown() then refresh() else panel:Show() end
end

function ns.CloseTopBuilds()
    panel:Hide()
end

-- Close along with the talent window.
EventUtil.ContinueOnAddOnLoaded("Blizzard_PlayerSpells", function()
    if PlayerSpellsFrame then
        PlayerSpellsFrame:HookScript("OnHide", function() panel:Hide() end)
    end
end)

ns.commands.top = function()
    if not (PlayerSpellsFrame and PlayerSpellsFrame:IsShown()) then
        ns.Print("Open your talent window first (default key: N).")
        return
    end
    ns.OpenTopBuilds()
end
