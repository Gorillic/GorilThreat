local GT = GorilThreat
if not GT then
  return
end

local controls = {}
local sliderIndex = 0
local checkboxIndex = 0
local optionsRegistered = false
local previewHooksInstalled = false

local function applyPreviewValue(dropdown, value)
  if not dropdown or not dropdown.previewApply then
    return
  end
  dropdown.previewApply(value)
end

local function resetPreviewValue(dropdown)
  if not dropdown or not dropdown.previewRestore then
    return
  end
  dropdown.previewRestore()
end

local function installDropdownPreviewHooks()
  if previewHooksInstalled or not hooksecurefunc then
    return
  end
  previewHooksInstalled = true

  if UIDropDownMenuButton_OnEnter then
    hooksecurefunc("UIDropDownMenuButton_OnEnter", function(button)
      if not button then
        return
      end
      local dropdown = button.gtPreviewDropdown or button.arg1
      local value = button.gtPreviewValue
      if value == nil then
        value = button.arg2
      end
      if not dropdown or value == nil then
        return
      end
      applyPreviewValue(dropdown, value)
    end)
  end

  if UIDropDownMenuButton_OnLeave then
    hooksecurefunc("UIDropDownMenuButton_OnLeave", function(button)
      if not button then
        return
      end
      local dd = button.gtPreviewDropdown or button.arg1
      if dd.valueKey and GT and GT.db then
        resetPreviewValue(dd)
      end
    end)
  end
end

local function registerOptionsPanel(panel)
  if not panel then
    return false
  end

  if InterfaceOptionsFrame_AddCategory then
    InterfaceOptionsFrame_AddCategory(panel)
    return true
  end

  if InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(panel)
    return true
  end

  if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
    local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name or "GorilThreat", panel.name or "GorilThreat")
    if category then
      Settings.RegisterAddOnCategory(category)
      panel.settingsCategory = category
      return true
    end
  end

  return false
end

local function createTitle(panel, text, yOffset)
  local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 16, yOffset)
  title:SetText(text)
  return title
end

local function createSubtitle(panel, text, yOffset)
  local sub = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  sub:SetPoint("TOPLEFT", 16, yOffset)
  sub:SetText(text)
  return sub
end

local function createCheckbox(panel, label, key, yOffset, onChanged, xOffset)
  checkboxIndex = checkboxIndex + 1
  local name = "GorilThreatOptionCheck" .. checkboxIndex
  local cb = CreateFrame("CheckButton", name, panel, "InterfaceOptionsCheckButtonTemplate")
  cb:SetPoint("TOPLEFT", xOffset or 16, yOffset)
  local textRegion = _G[name .. "Text"] or cb.Text
  if textRegion then
    textRegion:SetText(label)
  end
  cb:SetScript("OnClick", function(self)
    GT.db[key] = not not self:GetChecked()
    GT:ValidateDB()
    if onChanged then
      onChanged(GT.db[key])
    end
    GT:RefreshNow()
  end)
  controls[key] = cb
  return cb
end

local function createSlider(panel, label, key, minValue, maxValue, yOffset, xOffset)
  sliderIndex = sliderIndex + 1
  local name = "GorilThreatOptionSlider" .. sliderIndex
  local slider = CreateFrame("Slider", name, panel, "OptionsSliderTemplate")
  slider:SetPoint("TOPLEFT", xOffset or 20, yOffset)
  slider:SetMinMaxValues(minValue, maxValue)
  slider:SetValueStep(1)
  slider:SetObeyStepOnDrag(true)
  slider:SetWidth(220)
  slider:SetOrientation("HORIZONTAL")

  if slider.SetThumbTexture then
    slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    if slider.GetThumbTexture then
      local thumb = slider:GetThumbTexture()
      if thumb and thumb.SetSize then
        thumb:SetSize(16, 24)
      end
    end
  end

  slider.trackBg = slider:CreateTexture(nil, "BACKGROUND")
  slider.trackBg:SetPoint("LEFT", slider, "LEFT", 0, 0)
  slider.trackBg:SetPoint("RIGHT", slider, "RIGHT", 0, 0)
  slider.trackBg:SetHeight(10)
  slider.trackBg:SetTexture("Interface\\Buttons\\WHITE8X8")
  slider.trackBg:SetVertexColor(0.08, 0.08, 0.08, 0.75)

  slider.track = slider:CreateTexture(nil, "ARTWORK")
  slider.track:SetPoint("LEFT", slider, "LEFT", 1, 0)
  slider.track:SetPoint("RIGHT", slider, "RIGHT", -1, 0)
  slider.track:SetHeight(6)
  slider.track:SetTexture("Interface\\Buttons\\WHITE8X8")
  slider.track:SetVertexColor(0.95, 0.80, 0.25, 0.70)

  slider.valueText = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  slider.valueText:SetPoint("LEFT", slider, "RIGHT", 14, 0)
  slider.valueText:SetText("")
  slider:SetScript("OnValueChanged", function(self, value)
    if self._ignore then
      return
    end
    GT.db[key] = math.floor(value + 0.5)
    if self.valueText then
      self.valueText:SetText(tostring(GT.db[key]))
    end
    GT:ValidateDB()
    GT:RefreshOptionsUI()
    GT:RefreshNow()
  end)

  local textRegion = _G[name .. "Text"]
  local lowRegion = _G[name .. "Low"]
  local highRegion = _G[name .. "High"]
  if textRegion then
    textRegion:SetText(label)
  end
  if lowRegion then
    lowRegion:SetText(tostring(minValue))
  end
  if highRegion then
    highRegion:SetText(tostring(maxValue))
  end
  controls[key] = slider
  return slider
end

local function createEditBox(panel, label, key, yOffset)
  local labelText = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  labelText:SetPoint("TOPLEFT", 16, yOffset)
  labelText:SetText(label)

  local edit = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
  edit:SetPoint("TOPLEFT", labelText, "BOTTOMLEFT", 0, -6)
  edit:SetWidth(280)
  edit:SetHeight(24)
  edit:SetAutoFocus(false)
  edit:SetScript("OnEnterPressed", function(self)
    GT.db[key] = self:GetText() or ""
    GT:ValidateDB()
    self:ClearFocus()
  end)
  edit:SetScript("OnEditFocusLost", function(self)
    GT.db[key] = self:GetText() or ""
    GT:ValidateDB()
  end)

  controls[key] = edit
  return edit
end

local function createProfileDropdown(panel, yOffset, xOffset)
  local label = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  local x = xOffset or 16
  label:SetPoint("TOPLEFT", x, yOffset)
  label:SetText("Profile")

  local dd = CreateFrame("Frame", "GorilThreatProfileDropdown", panel, "UIDropDownMenuTemplate")
  dd:SetPoint("TOPLEFT", label, "BOTTOMLEFT", -16, -4)
  dd.isProfileDropdown = true

  local function setProfileText(profileName)
    if UIDropDownMenu_SetText then
      UIDropDownMenu_SetText(dd, tostring(profileName or "Default"))
    end
  end

  if UIDropDownMenu_SetWidth then
    UIDropDownMenu_SetWidth(dd, 180)
  end

  if UIDropDownMenu_Initialize then
    UIDropDownMenu_Initialize(dd, function(_, level)
      if level ~= 1 then
        return
      end
      local profileNames = (GT.GetProfileNames and GT:GetProfileNames()) or { "Default" }
      for _, name in ipairs(profileNames) do
        local info = UIDropDownMenu_CreateInfo and UIDropDownMenu_CreateInfo() or {}
        info.text = name
        info.value = name
        info.checked = (GT.GetActiveProfileName and GT:GetActiveProfileName() == name) and true or false
        info.func = function(btn)
          if GT.SetActiveProfile then
            GT:SetActiveProfile(btn.value)
          end
          setProfileText(btn.value)
        end
        if UIDropDownMenu_AddButton then
          UIDropDownMenu_AddButton(info, level)
        end
      end
    end)
  end

  dd.refreshProfile = function()
    local current = GT.GetActiveProfileName and GT:GetActiveProfileName() or "Default"
    setProfileText(current)
  end

  controls.__profile_dropdown = dd
  return dd
end

local function createValueDropdown(panel, labelText, key, values, yOffset, onChanged, xOffset)
  local label = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  local x = xOffset or 16
  label:SetPoint("TOPLEFT", x, yOffset)
  label:SetText(labelText)

  local ddName = "GorilThreatValueDropdown" .. tostring(key)
  local dd = CreateFrame("Frame", ddName, panel, "UIDropDownMenuTemplate")
  dd:SetPoint("TOPLEFT", label, "BOTTOMLEFT", -16, -4)
  dd.isValueDropdown = true
  dd.valueKey = key
  dd.previewApply = function(value)
    if key == "barTextureStyle" and GT.PreviewBarStyle then
      GT:PreviewBarStyle(value)
    end
  end
  dd.previewRestore = function()
    if key == "barTextureStyle" and GT.RestoreBarStylePreview then
      GT:RestoreBarStylePreview()
    end
  end
  dd._previewValue = nil

  local function getHoveredDropdownValue()
    local maxButtons = UIDROPDOWNMENU_MAXBUTTONS or 32
    for level = 1, 4 do
      local list = _G["DropDownList" .. tostring(level)]
      if list and list:IsShown() then
        for i = 1, maxButtons do
          local button = _G["DropDownList" .. tostring(level) .. "Button" .. tostring(i)]
          if button and button:IsShown() and button:IsMouseOver() then
            local value = button.value
            if type(value) == "string" and value ~= "__none__" and not string.find(value, "^__shared_page_") then
              return value
            end
          end
        end
      end
    end
    return nil
  end

  dd:SetScript("OnUpdate", function(self)
    if not GT or not GT.db then
      return
    end

    local openMenu = _G.UIDROPDOWNMENU_OPEN_MENU
    if openMenu ~= self then
      if self._previewValue ~= nil then
        resetPreviewValue(self)
        self._previewValue = nil
      end
      return
    end

    local hoveredValue = getHoveredDropdownValue()

    if hoveredValue ~= nil then
      if self._previewValue ~= hoveredValue then
        applyPreviewValue(self, hoveredValue)
        self._previewValue = hoveredValue
      end
      return
    end

    if self._previewValue ~= nil then
      resetPreviewValue(self)
      self._previewValue = nil
    end
  end)

  if UIDropDownMenu_SetWidth then
    UIDropDownMenu_SetWidth(dd, 180)
  end

  local function resolveValues()
    if type(values) == "function" then
      local out = values()
      if type(out) == "table" then
        return out
      end
      return {}
    end
    if type(values) == "table" then
      return values
    end
    return {}
  end

  local function getLabelForValue(value)
    local resolved = resolveValues()
    for _, entry in ipairs(resolved) do
      if type(entry) == "table" and type(entry.entries) == "table" then
        for _, subEntry in ipairs(entry.entries) do
          if subEntry.value == value then
            if entry.text == "SharedMedia" then
              return "[LSM] " .. tostring(subEntry.text or value)
            end
            return tostring(subEntry.text or value)
          end
        end
      elseif type(entry) == "table" and entry.value == value then
        return entry.text
      end
    end
    if type(value) == "string" and string.sub(value, 1, 4) == "lsm:" then
      return "[LSM] " .. string.sub(value, 5)
    end
    return tostring(value or "")
  end

  local function setDropdownText(value)
    if UIDropDownMenu_SetText then
      UIDropDownMenu_SetText(dd, getLabelForValue(value))
    end
  end

  if UIDropDownMenu_Initialize then
    UIDropDownMenu_Initialize(dd, function(_, level, menuList)
      if level == 1 then
        for _, entry in ipairs(resolveValues()) do
          local info = UIDropDownMenu_CreateInfo and UIDropDownMenu_CreateInfo() or {}
          if type(entry) == "table" and entry.separator then
            info.text = "--------------------"
            info.isTitle = true
            info.notCheckable = true
            info.disabled = true
          elseif type(entry) == "table" and type(entry.entries) == "table" then
            info.text = tostring(entry.text or "Group")
            info.notCheckable = true
            info.hasArrow = true
            info.value = entry.entries
            info.menuList = entry.entries
          else
            info.text = entry.text
            info.value = entry.value
            info.disabled = entry.disabled and true or false
            info.notCheckable = entry.disabled and true or false
            if not entry.disabled then
              info.checked = (GT.db and GT.db[key] == entry.value) and true or false
              info.func = function(btn)
                if not GT.db then
                  return
                end
                GT.db[key] = btn.value
                GT:ValidateDB()
                if onChanged then
                  onChanged(btn.value)
                end
                setDropdownText(btn.value)
                GT:RefreshNow()
              end
              info.arg1 = dd
              info.arg2 = entry.value
              info.gtPreviewDropdown = dd
              info.gtPreviewValue = entry.value
            end
          end
          if UIDropDownMenu_AddButton then
            UIDropDownMenu_AddButton(info, level)
          end
        end
        return
      end

      local entries = nil
      if type(menuList) == "table" then
        entries = menuList
      elseif type(UIDROPDOWNMENU_MENU_VALUE) == "table" then
        entries = UIDROPDOWNMENU_MENU_VALUE
      end

      if type(entries) == "table" then
        for _, entry in ipairs(entries) do
          local info = UIDropDownMenu_CreateInfo and UIDropDownMenu_CreateInfo() or {}
          if type(entry) == "table" and type(entry.entries) == "table" then
            info.text = tostring(entry.text or "Group")
            info.notCheckable = true
            info.hasArrow = true
            info.value = entry.entries
            info.menuList = entry.entries
          else
            info.text = entry.text
            info.value = entry.value
            info.disabled = entry.disabled and true or false
            info.notCheckable = entry.disabled and true or false
            if not entry.disabled then
              info.checked = (GT.db and GT.db[key] == entry.value) and true or false
              info.func = function(btn)
                if not GT.db then
                  return
                end
                GT.db[key] = btn.value
                GT:ValidateDB()
                if onChanged then
                  onChanged(btn.value)
                end
                setDropdownText(btn.value)
                GT:RefreshNow()
              end
              info.arg1 = dd
              info.arg2 = entry.value
              info.gtPreviewDropdown = dd
              info.gtPreviewValue = entry.value
            end
          end
          if UIDropDownMenu_AddButton then
            UIDropDownMenu_AddButton(info, level)
          end
        end
      end
    end)
  end

  dd.refreshValue = function()
    if not GT.db then
      return
    end
    setDropdownText(GT.db[key])
  end

  controls["__dropdown_" .. key] = dd
  installDropdownPreviewHooks()
  return dd
end

function GT:RefreshOptionsUI()
  if not self.optionsPanel then
    return
  end
  if not self.db then
    return
  end

  for key, control in pairs(controls) do
    local value = self.db[key]
    if control:GetObjectType() == "CheckButton" then
      control:SetChecked(value and true or false)
    elseif control:GetObjectType() == "Slider" then
      control._ignore = true
      control:SetValue(tonumber(value) or 0)
      control._ignore = false
      if control.valueText then
        control.valueText:SetText(tostring(math.floor((tonumber(value) or 0) + 0.5)))
      end
    elseif control:GetObjectType() == "EditBox" then
      control:SetText(tostring(value or ""))
    elseif control.isValueDropdown and control.refreshValue then
      control.refreshValue()
    elseif control.isProfileDropdown and control.refreshProfile then
      control.refreshProfile()
    end
  end
end

function GT:ToggleOptions()
  if not self.optionsPanel then
    self:InitOptions()
    if not self.optionsPanel then
      return
    end
  end

  if InterfaceOptionsFrame and InterfaceOptionsFrame:IsShown() and HideUIPanel then
    HideUIPanel(InterfaceOptionsFrame)
    return
  end

  if Settings and Settings.OpenToCategory then
    if self.optionsPanel.settingsCategory and self.optionsPanel.settingsCategory.GetID then
      Settings.OpenToCategory(self.optionsPanel.settingsCategory:GetID())
      return
    end
    local opened = pcall(Settings.OpenToCategory, self.optionsPanel.name or "GorilThreat")
    if opened then
      return
    end
  end

  if InterfaceOptionsFrame_OpenToCategory then
    InterfaceOptionsFrame_OpenToCategory(self.optionsPanel)
    InterfaceOptionsFrame_OpenToCategory(self.optionsPanel)
    return
  end

  self:Print("Use /gt help for slash commands.")
end

function GT:InitOptions()
  if self.optionsPanel then
    return
  end

  local panel = CreateFrame("Frame", "GorilThreatOptionsPanel")
  panel.name = "GorilThreat"

  local scrollFrame = CreateFrame("ScrollFrame", "GorilThreatOptionsScrollFrame", panel, "UIPanelScrollFrameTemplate")
  scrollFrame:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -8)
  scrollFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -28, 8)

  local content = CreateFrame("Frame", "GorilThreatOptionsScrollContent", scrollFrame)
  content:SetPoint("TOPLEFT")
  content:SetSize(1, 1)
  scrollFrame:SetScrollChild(content)

  createTitle(content, "GorilThreat", -16)
  createSubtitle(content, "Minimal threat bar awareness", -42)

  local leftX = 16
  local rightX = 300
  local y = -72
  createProfileDropdown(content, y, leftX)
  y = y - 62

  local profileNameLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  profileNameLabel:SetPoint("TOPLEFT", leftX, y)
  profileNameLabel:SetText("Profile name")
  y = y - 20

  local profileNameEdit = CreateFrame("EditBox", nil, content, "InputBoxTemplate")
  profileNameEdit:SetPoint("TOPLEFT", leftX, y)
  profileNameEdit:SetWidth(200)
  profileNameEdit:SetHeight(24)
  profileNameEdit:SetAutoFocus(false)
  profileNameEdit:SetScript("OnEnterPressed", function(self)
    if GT.CreateProfile and GT:CreateProfile(self:GetText()) then
      self:SetText("")
    end
    self:ClearFocus()
  end)

  local createProfileButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
  createProfileButton:SetSize(84, 24)
  createProfileButton:SetText("Create")
  createProfileButton:SetPoint("LEFT", profileNameEdit, "RIGHT", 8, 0)
  createProfileButton:SetScript("OnClick", function()
    if GT.CreateProfile and GT:CreateProfile(profileNameEdit:GetText()) then
      profileNameEdit:SetText("")
    end
  end)

  y = y - 32
  local renameProfileButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
  renameProfileButton:SetSize(128, 24)
  renameProfileButton:SetText("Rename Active")
  renameProfileButton:SetPoint("TOPLEFT", 16, y)
  renameProfileButton:SetScript("OnClick", function()
    if GT.RenameProfile then
      GT:RenameProfile(GT.GetActiveProfileName and GT:GetActiveProfileName() or nil, profileNameEdit:GetText())
      profileNameEdit:SetText("")
    end
  end)

  local deleteProfileButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
  deleteProfileButton:SetSize(96, 24)
  deleteProfileButton:SetText("Delete Active")
  deleteProfileButton:SetPoint("LEFT", renameProfileButton, "RIGHT", 8, 0)
  deleteProfileButton:SetScript("OnClick", function()
    if GT.ConfirmDeleteActiveProfile then
      GT:ConfirmDeleteActiveProfile()
    end
  end)

  y = y - 44

  createSlider(content, "Rising threshold (%)", "RisingStart", 0, 99, y, leftX + 4)
  createSlider(content, "Danger threshold (%)", "DangerStart", 1, 100, y, rightX + 4)
  y = y - 58
  createSlider(content, "Alert Cooldown (seconds)", "alertCooldownSeconds", 1, 15, y, leftX + 4)
  createValueDropdown(content, "Bar style", "barTextureStyle", function()
    if GT.GetBarTextureDropdownValues then
      return GT:GetBarTextureDropdownValues()
    end
    return {
      { text = "Default", value = "default" },
    }
  end, y + 2, function()
    if GT.ApplyBarStyle then
      GT:ApplyBarStyle()
    end
  end, rightX)
  local barStyleNote = content:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  barStyleNote:SetPoint("TOPLEFT", rightX, y - 46)
  barStyleNote:SetTextColor(1.0, 0.25, 0.25, 1.0)
  barStyleNote:SetText("More styles: install SharedMedia (AddOns\\SharedMedia).")

  y = y - 62
  createCheckbox(content, "Lock bar (disable move/resize)", "barLocked", y, function(value)
    if GT.SetBarLocked then
      GT:SetBarLocked(value)
    end
  end, leftX)
  createCheckbox(content, "Show percent text", "showPercentText", y, nil, rightX)
  y = y - 28
  createCheckbox(content, "Show only in combat", "showOnlyInCombat", y, nil, leftX)
  createCheckbox(content, "Enable sounds (Master channel)", "enableSound", y, function(value)
    if GT.SetAddonSoundEnabled then
      GT:SetAddonSoundEnabled(value)
    elseif GT.UpdateSoundToggleButton then
      GT:UpdateSoundToggleButton()
    end
  end, rightX)
  y = y - 24
  local soundInfo = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  soundInfo:SetPoint("TOPLEFT", rightX + 16, y)
  soundInfo:SetText("Fixed sound: Bear Aggro")
  y = y - 22
  createCheckbox(content, "Show only in group", "showOnlyInGroup", y, nil, leftX)
  createCheckbox(content, "Enable combat fade", "enableCombatFade", y, nil, rightX)
  y = y - 28
  createCheckbox(content, "Show only in raid", "showOnlyInRaid", y, nil, leftX)
  createCheckbox(content, "Enable low noise", "enableLowNoise", y, nil, rightX)
  local lowNoiseInfo = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  lowNoiseInfo:SetPoint("TOPLEFT", rightX + 170, y + 2)
  lowNoiseInfo:SetText("Less SAFE/RISING glow.")
  y = y - 28
  createCheckbox(content, "Show only in instances", "showOnlyInInstances", y, nil, leftX)
  createCheckbox(content, "Enable flash", "enableFlash", y, nil, rightX)
  y = y - 28
  createCheckbox(content, "Enable aggro blink", "enableAggroBlink", y, nil, leftX)
  y = y - 30
  createSlider(content, "Out of combat alpha (%)", "outOfCombatAlpha", 15, 100, y, leftX + 4)
  createSlider(content, "Low noise alpha (%)", "lowNoiseAlpha", 15, 100, y, rightX + 4)

  y = y - 72
  local resetButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
  resetButton:SetSize(120, 24)
  resetButton:SetText("Reset Defaults")
  resetButton:SetPoint("TOPLEFT", 16, y)
  resetButton:SetScript("OnClick", function()
    GT:ResetDB()
    GT:Print("Settings reset.")
  end)

  local testButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
  testButton:SetSize(120, 24)
  testButton:SetText("Run Test Cycle")
  testButton:SetPoint("LEFT", resetButton, "RIGHT", 8, 0)
  testButton:SetScript("OnClick", function()
    GT:CycleTestMode()
  end)

  local minContentHeight = -y + 60
  content._neededHeight = minContentHeight
  local function updateScrollLayout()
    local width = panel:GetWidth()
    if type(width) ~= "number" or width < 200 then
      width = 420
    end
    content:SetWidth(width - 52)
    local panelHeight = panel:GetHeight()
    if type(panelHeight) ~= "number" or panelHeight < 200 then
      panelHeight = 500
    end
    content:SetHeight(math.max(content._neededHeight or 1, panelHeight - 20))
  end
  panel:SetScript("OnSizeChanged", updateScrollLayout)

  panel:SetScript("OnShow", function()
    updateScrollLayout()
    GT:RefreshOptionsUI()
  end)

  optionsRegistered = registerOptionsPanel(panel)

  self.optionsPanel = panel
  updateScrollLayout()
  self:RefreshOptionsUI()
end
