-- wow.lua
-- A pretend World of Warcraft, just big enough to load LoadoutPlanner's
-- files outside the game. Real WoW is Lua 5.1 plus hundreds of API
-- functions and frame types; this file fakes the ones the addon touches.
--
-- The trick: every fake frame answers ANY capitalized method call
-- (SetPoint, SetAtlas, ...) with "do nothing", except the handful we need
-- to behave (Show/Hide, SetText, scripts). That keeps the stubs small.
--
-- Usage (from a test file, run from the repository root):
--     package.path = "tools/test/?.lua;" .. package.path
--     local wow = require("wow")
--     local env = wow.install({ modern = true })

local M = {}

-- Lua 5.2+ moved unpack into table. WoW is 5.1, but the tests should run
-- on whatever Lua you have installed.
unpack = unpack or table.unpack

M.created = {}   -- every fake frame/texture, in creation order
M.templates = {} -- template name -> how many times CreateFrame used it

-- Plain-text version of a string with |cAARRGGBB colour codes removed.
function M.plain(text)
    return (tostring(text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

-- Keys that must read as "missing" (nil) instead of as a method.
local NOT_METHODS = { Instructions = true, TalentsFrame = true, BlackBG = true, Background = true,
    Bg = true, LoadSystem = true, TitleContainer = true, CloseButton = true, ScrollBar = true }

local function newObj(name)
    local o = { shown = false }
    setmetatable(o, { __index = function(_, k)
        if type(k) ~= "string" or not k:match("^%u") or NOT_METHODS[k] then return nil end
        return function(self, ...)
            if k == "SetText" then self.text = ... return end
            if k == "GetText" then return self.text or "" end
            if k == "Show" then
                local was = self.shown
                self.shown = true
                if not was and self.scripts and self.scripts.OnShow then self.scripts.OnShow(self) end
                return
            end
            if k == "Hide" then self.shown = false return end
            if k == "IsShown" then return self.shown end
            if k == "SetShown" then self.shown = (...) and true or false return end
            if k == "SetScript" then
                local event, fn = ...
                self.scripts = self.scripts or {}
                self.scripts[event] = fn
                return
            end
            if k == "HookScript" then
                local event, fn = ...
                self.scripts = self.scripts or {}
                local old = self.scripts[event]
                self.scripts[event] = function(...) if old then old(...) end fn(...) end
                return
            end
            if k == "GetWidth" then return 380 end
            if k == "GetHeight" then return 500 end
            if k == "GetFrameLevel" then return 5 end
            if k == "GetScale" or k == "GetEffectiveScale" then return 1 end
            if k == "GetRight" then return 1500 end
            if k == "GetLeft" then return 100 end
            if k == "GetTop" then return 900 end
            if k == "GetBottom" then return 50 end
            if k == "GetFrameStrata" then return "MEDIUM" end
            if k == "GetPoint" then return "TOP", nil, "TOP", 0, -41 end
            if k == "CreateTexture" or k == "CreateFontString" or k == "CreateMaskTexture" or k == "CreateLine" then
                return newObj()
            end
        end
    end })
    table.insert(M.created, o)
    if name then _G[name] = o end
    return o
end
M.newObj = newObj

-- Find a fake button by its label and click it.
function M.click(text)
    for _, o in ipairs(M.created) do
        if o.text == text and o.scripts and o.scripts.OnClick and not o.row then
            o.scripts.OnClick(o, "LeftButton")
            return true
        end
    end
    return false
end

-- opts.modern:  Blizzard's newer pieces exist (atlases, ScrollUtil, CreateColor)
-- opts.missing: the newer templates are gone (tests the fallbacks)
function M.install(opts)
    opts = opts or {}
    M.hooks = {}

    CreateFrame = function(frameType, name, parent, template)
        if template then M.templates[template] = (M.templates[template] or 0) + 1 end
        local gone = { DefaultPanelFlatTemplate = true, UIPanelCloseButtonDefaultAnchors = true,
            MinimalScrollBar = true, TooltipBackdropTemplate = true }
        if opts.missing and gone[template] then error("unknown template " .. template) end
        local o = newObj(name)
        if template == "DefaultPanelFlatTemplate" then o.TitleContainer = { TitleText = newObj() } end
        return o
    end

    UIParent = newObj()
    UISpecialFrames, SlashCmdList, StaticPopupDialogs = {}, {}, {}
    M.popups = {}
    StaticPopup_Show = function(which, a, b, data) table.insert(M.popups, { which = which, a = a, data = data }) end
    GameTooltip = newObj()
    GameTooltip_Hide = function() end
    EventUtil = { ContinueOnAddOnLoaded = function(_, fn) table.insert(M.hooks, fn) end }
    C_Timer = { After = function() end, NewTimer = function(_, f) return { Cancel = function() end, fn = f } end }
    C_Texture = { GetAtlasInfo = function()
        if opts.modern then
            return { file = 1234, width = 1612, height = 774, leftTexCoord = 0, rightTexCoord = 0.78,
                topTexCoord = 0, bottomTexCoord = 0.37 }
        end
    end }
    if opts.modern then
        ScrollUtil = { InitScrollFrameWithScrollBar = function(s, b) assert(s and b) end }
        CreateColor = function(...) return { ... } end
    end
    C_AddOns = { IsAddOnLoaded = function() return false end }
    time = os.time
    geterrorhandler = function() return function(e) error(e, 2) end end
    InCombatLockdown = function() return false end
    hooksecurefunc = function() end
    UpdateUIPanelPositions = function() end
    PlaySound = function() end
    SOUNDKIT = {}
    YES, NO, ACCEPT, CANCEL, CLOSE = "Yes", "No", "Accept", "Cancel", "Close"

    -- A Balance druid standing in Silvermoon.
    UnitClass = function() return "Druid", "DRUID", 11 end
    local SPECS = { [102] = "Balance", [103] = "Feral", [104] = "Guardian", [105] = "Restoration" }
    GetSpecializationInfoByID = function(id) return id, SPECS[id], "", 1000 + id, "DAMAGER", "DRUID" end
    GetSpecialization = function() return 1 end
    GetNumSpecializations = function() return 4 end
    GetSpecializationInfo = function(i) return 101 + i, SPECS[101 + i], "", 1000 + i, "DAMAGER" end
    PlayerUtil = { GetCurrentSpecID = function() return 102 end }
    C_SpecializationInfo = {}
    GetInstanceInfo = function() return "Silvermoon", "none" end
    C_Map = { GetBestMapForUnit = function() end }

    Enum = { TraitNodeType = { Single = 0, Tiered = 1, Selection = 2, SubTreeSelection = 3 },
        LoadConfigResult = { Error = 0, NoChangesNecessary = 1, LoadInProgress = 2, Ready = 3 },
        TraitConfigType = { Combat = 1 } }
    Constants = { TraitConsts = { STARTER_BUILD_TRAIT_CONFIG_ID = -2 } }
    C_ClassTalents = { GetActiveConfigID = function() return 1 end, GetConfigIDsBySpecID = function() return { 11, 12 } end,
        GetLastSelectedSavedConfigID = function() return 11 end, GetTraitTreeForSpec = function() return 790 end }
    C_Traits = { GetConfigInfo = function(id) return { ID = id, name = "Loadout " .. id, treeIDs = { 790 } } end,
        GetTreeNodes = function() return {} end, ConfigHasStagedChanges = function() return false end,
        GenerateImportString = function() return "CODE" end, GetTreeHash = function() return {} end,
        GetLoadoutSerializationVersion = function() return 2 end }

    -- Right-click menus: remember the last one built, as a flat list.
    MenuUtil = { CreateContextMenu = function(owner, fn)
        local items, root = {}, nil
        root = { CreateTitle = function(_, t) table.insert(items, "[" .. t .. "]") end,
            CreateButton = function(_, t, f) table.insert(items, { text = t, fn = f }) return root end,
            CreateDivider = function() end }
        fn(owner, root)
        M.lastMenu = items
    end }

    -- The talent window, as the game would have it once opened.
    PlayerSpellsFrame = newObj("PlayerSpellsFrame")
    PlayerSpellsFrame.TalentsFrame = newObj()
    PlayerSpellsFrame.TalentsFrame.Background = { GetAtlas = function() return "talents-background-druid-balance" end }
    return M
end

-- Load one addon file the way WoW does: with the addon name and shared namespace.
function M.loadAddonFile(path, ns)
    local chunk, err = loadfile(path)
    if not chunk then error(err, 2) end
    chunk("LoadoutPlanner", ns)
end

-- The Lua files the TOC lists, in load order.
function M.tocFiles()
    local toc = assert(io.open("LoadoutPlanner.toc")):read("*a")
    local files = {}
    for line in toc:gmatch("[^\r\n]+") do
        if not line:match("^#") and line:match("%.lua$") then
            table.insert(files, (line:gsub("\\", "/")))
        end
    end
    return files
end

-- Tiny assertion helper: counts failures instead of stopping at the first.
M.failures = 0
function M.check(ok, message)
    if ok then
        print("  ok   " .. message)
    else
        print("  FAIL " .. message)
        M.failures = M.failures + 1
    end
end

function M.finish()
    os.exit(M.failures == 0 and 0 or 1)
end

return M
