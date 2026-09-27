-- Background.lua
-- Transparency for the talent window's background art, plus a reusable
-- slider widget.
--
-- From Blizzard's source (Blizzard_ClassTalentsFrame.xml), the talents tab
-- has a solid black layer (BlackBG) under the spec painting (Background).
-- Fading both lets the game world show through. We leave the animated
-- layers (OverlayBackground*, Clouds, particles) alone: Blizzard animates
-- their alpha, so it would just overwrite ours.

local addonName, ns = ...

local function artTextures()
    local talents = PlayerSpellsFrame and PlayerSpellsFrame.TalentsFrame
    if not talents then
        return {}
    end
    return { talents.BlackBG, talents.Background, PlayerSpellsFrame.Bg }
end

function ns.ApplyArtAlpha()
    local alpha = ns.db and ns.db.artAlpha or 1
    for _, texture in ipairs(artTextures()) do
        if texture then -- any of these could be missing in a future patch
            texture:SetAlpha(alpha)
        end
    end
end

-- Blizzard swaps the spec painting when you open the window or change
-- spec, so re-apply our alpha after both.
EventUtil.ContinueOnAddOnLoaded("Blizzard_PlayerSpells", function()
    if PlayerSpellsFrame and PlayerSpellsFrame.TalentsFrame then
        PlayerSpellsFrame.TalentsFrame:HookScript("OnShow", ns.ApplyArtAlpha)
        ns.ApplyArtAlpha()
    end
end)

ns.On("PLAYER_SPECIALIZATION_CHANGED", function(unit)
    if unit == "player" then
        C_Timer.After(0.5, ns.ApplyArtAlpha)
    end
end)

------------------------------------------------------------------------
-- A slider built from basic parts
------------------------------------------------------------------------
-- Blizzard's slider templates have changed several times, so this one is
-- built from a plain Slider frame and long-standing textures instead.
-- onChange(value) receives 0-100.
function ns.CreatePercentSlider(parent, labelText, onChange)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(200, 34)

    local label = holder:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOPLEFT")

    local valueText = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    valueText:SetPoint("TOPRIGHT")

    local slider = CreateFrame("Slider", nil, holder, "BackdropTemplate")
    slider:SetPoint("BOTTOMLEFT")
    slider:SetPoint("BOTTOMRIGHT")
    slider:SetHeight(16)
    slider:SetOrientation("HORIZONTAL")
    slider:SetBackdrop({
        bgFile = "Interface\\Buttons\\UI-SliderBar-Background",
        edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = { left = 3, right = 3, top = 6, bottom = 6 },
    })
    slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    slider:SetMinMaxValues(0, 100)
    slider:SetValueStep(5)
    slider:SetObeyStepOnDrag(true)
    slider:EnableMouseWheel(true)

    slider:SetScript("OnValueChanged", function(_, value)
        value = math.floor(value + 0.5)
        label:SetText(labelText)
        valueText:SetText(value .. "%")
        onChange(value)
    end)
    slider:SetScript("OnMouseWheel", function(self, delta)
        self:SetValue(self:GetValue() + delta * 5)
    end)

    holder.slider = slider
    return holder
end
