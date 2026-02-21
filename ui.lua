local GT = GorilThreat
if not GT then
  return
end

GT.VISUALS = GT.VISUALS or {
  [GT.STATE_SAFE] = { r = 0.20, g = 0.85, b = 0.30, a = 0.90 },
  [GT.STATE_RISING] = { r = 0.98, g = 0.84, b = 0.30, a = 0.92 },
  [GT.STATE_DANGER] = { r = 0.98, g = 0.56, b = 0.18, a = 0.95 },
  [GT.STATE_AGGRO] = { r = 0.95, g = 0.22, b = 0.22, a = 1.00 },
}

GT.BAR_TEXTURE_STYLES = GT.BAR_TEXTURE_STYLES or {
  default = {
    label = "Default",
    texture = "Interface\\TARGETINGFRAME\\UI-StatusBar",
  },
  flat = {
    label = "Flat",
    texture = "Interface\\Buttons\\WHITE8X8",
  },
  raid = {
    label = "Raid",
    texture = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill",
  },
}

function GT:GetBarTextureStyleKeys()
  return { "default", "flat", "raid" }
end

function GT:GetLibSharedMedia()
  if not LibStub then
    return nil
  end
  local ok, lsm = pcall(LibStub, "LibSharedMedia-3.0", true)
  if ok and type(lsm) == "table" then
    return lsm
  end
  return nil
end

function GT:GetBarTextureDropdownValues()
  local gameValues = {}
  local sharedValues = {}
  local seen = {}

  for _, key in ipairs(self:GetBarTextureStyleKeys()) do
    local info = self.BAR_TEXTURE_STYLES and self.BAR_TEXTURE_STYLES[key]
    local label = (info and info.label) or key
    table.insert(gameValues, { text = label, value = key })
    seen[key] = true
  end

  local lsm = self:GetLibSharedMedia()
  if lsm and type(lsm.HashTable) == "function" then
    local hash = lsm:HashTable("statusbar")
    local names = {}
    if type(hash) == "table" then
      for name in pairs(hash) do
        if type(name) == "string" and name ~= "" then
          table.insert(names, name)
        end
      end
    end
    table.sort(names, function(a, b)
      return string.lower(a) < string.lower(b)
    end)
    for _, name in ipairs(names) do
      local value = "lsm:" .. name
      if not seen[value] then
        table.insert(sharedValues, { text = name, value = value })
        seen[value] = true
      end
    end
  end

  if #sharedValues == 0 then
    table.insert(sharedValues, {
      text = "(No SharedMedia statusbar textures found)",
      value = "__none__",
      disabled = true,
    })
  end

  local sharedEntries = sharedValues
  if #sharedValues > 20 then
    sharedEntries = {}
    local pageSize = 20
    local pageIndex = 1
    for i = 1, #sharedValues, pageSize do
      local last = math.min(i + pageSize - 1, #sharedValues)
      local pageItems = {}
      for j = i, last do
        table.insert(pageItems, sharedValues[j])
      end
      table.insert(sharedEntries, {
        text = string.format("Items %d-%d", i, last),
        value = "__shared_page_" .. tostring(pageIndex),
        entries = pageItems,
      })
      pageIndex = pageIndex + 1
    end
  end

  return {
    {
      text = "Game Textures",
      entries = gameValues,
    },
    {
      separator = true,
    },
    {
      text = "SharedMedia",
      entries = sharedEntries,
    },
  }
end

function GT:GetBarTexturePath(styleKey)
  local key = tostring(styleKey or "default")
  if string.sub(key, 1, 4) == "lsm:" then
    local mediaName = string.sub(key, 5)
    local lsm = self:GetLibSharedMedia()
    if lsm and type(lsm.Fetch) == "function" and mediaName ~= "" then
      local texture = lsm:Fetch("statusbar", mediaName, true)
      if type(texture) == "string" and texture ~= "" then
        return texture
      end
    end
  end
  local info = self.BAR_TEXTURE_STYLES and self.BAR_TEXTURE_STYLES[key]
  if info and type(info.texture) == "string" and info.texture ~= "" then
    return info.texture
  end
  return "Interface\\TARGETINGFRAME\\UI-StatusBar"
end

function GT:ApplyBarStyle()
  if not self.overlayFrame or not self.overlayFrame.bar then
    return
  end
  local styleKey = self.db and self.db.barTextureStyle or "default"
  self.overlayFrame.bar:SetStatusBarTexture(self:GetBarTexturePath(styleKey))
end

function GT:PreviewBarStyle(styleKey)
  if not styleKey then
    return
  end
  if not self.overlayFrame then
    self:InitUI()
  end
  if not self.overlayFrame or not self.overlayFrame.bar then
    return
  end

  self.stylePreviewActive = true
  self.overlayFrame.bar:SetStatusBarTexture(self:GetBarTexturePath(styleKey))
  self.overlayFrame.targetPercent = math.max(self.overlayFrame.targetPercent or 0, 60)
  self.overlayFrame.targetR, self.overlayFrame.targetG, self.overlayFrame.targetB, self.overlayFrame.targetA = 0.98, 0.84, 0.30, 0.95
  self.overlayFrame.targetAlpha = 0.95
  self.overlayFrame.valueText:SetText("Style Preview")
  self.overlayFrame.valueText:Show()
  self.overlayFrame:Show()
end

function GT:RestoreBarStylePreview()
  self.stylePreviewActive = false
  self:ApplyBarStyle()
  if self.RefreshNow then
    self:RefreshNow()
  end
end

local function clampPercent(v)
  if type(v) ~= "number" then
    return 0
  end
  if v < 0 then
    return 0
  end
  if v > 100 then
    return 100
  end
  return v
end

local function clamp(v, lo, hi)
  if type(v) ~= "number" then
    return lo
  end
  if v < lo then
    return lo
  end
  if v > hi then
    return hi
  end
  return v
end

local function formatThreatValue(v)
  local n = tonumber(v) or 0
  if n >= 1000000 then
    return string.format("%.1fm", n / 1000000)
  end
  if n >= 1000 then
    return string.format("%.1fk", n / 1000)
  end
  return string.format("%d", math.floor(n + 0.5))
end

local function deg2rad(v)
  return v * math.pi / 180
end

function GT:EnsureBarAnchor()
  local target = _G.TargetFrame
  if target and target.GetObjectType then
    return target, "BOTTOM", "TOP", 0, -22
  end
  return UIParent, "CENTER", "CENTER", 0, 120
end

function GT:UpdateMinimapButtonPosition()
  if not self.minimapButton or not self.db or not Minimap then
    return
  end
  local angle = tonumber(self.db.minimapIconAngle) or 220
  local radius = 80
  local x = math.cos(deg2rad(angle)) * radius
  local y = math.sin(deg2rad(angle)) * radius
  self.minimapButton:ClearAllPoints()
  self.minimapButton:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

function GT:InitMinimapButton()
  if self.minimapButton then
    self:UpdateMinimapButtonPosition()
    self.minimapButton:SetShown(not (self.db and self.db.minimapIconHidden))
    return
  end
  if not Minimap then
    return
  end

  local btn = CreateFrame("Button", "GorilThreatMinimapButton", Minimap)
  btn:SetSize(31, 31)
  btn:SetFrameStrata("MEDIUM")
  btn:SetMovable(true)
  btn:SetClampedToScreen(true)
  btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  btn:RegisterForDrag("LeftButton", "RightButton")
  btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

  btn.bg = btn:CreateTexture(nil, "BACKGROUND")
  btn.bg:SetSize(20, 20)
  btn.bg:SetPoint("TOPLEFT", btn, "TOPLEFT", 7, -5)
  btn.bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")

  btn.border = btn:CreateTexture(nil, "OVERLAY")
  btn.border:SetSize(53, 53)
  btn.border:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
  btn.border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

  btn.icon = btn:CreateTexture(nil, "ARTWORK")
  btn.icon:SetSize(17, 17)
  btn.icon:SetPoint("TOPLEFT", btn, "TOPLEFT", 7, -6)
  btn.icon:SetTexture("Interface\\Icons\\Ability_Devour.blp")
  btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

  btn:SetScript("OnEnter", function(self)
    if not GameTooltip then
      return
    end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:ClearLines()
    GameTooltip:AddLine("GorilThreat")
    GameTooltip:AddDoubleLine("Left-click:", "Open options", 0.60, 1.00, 0.60, 1, 1, 1)
    local lockAction = "Lock bar"
    if GT and GT.db and GT.db.barLocked then
      lockAction = "Unlock bar"
    end
    GameTooltip:AddDoubleLine("Right-click:", lockAction, 0.60, 1.00, 0.60, 1, 1, 1)
    GameTooltip:Show()
  end)

  btn:SetScript("OnLeave", function(self)
    if GameTooltip and GameTooltip:IsOwned(self) then
      GameTooltip:Hide()
    end
  end)

  btn:SetScript("OnClick", function(self, button)
    if self._ignoreNextClick then
      self._ignoreNextClick = nil
      return
    end
    if button == "RightButton" then
      if GT and GT.db and GT.SetBarLocked then
        GT:SetBarLocked(not GT.db.barLocked)
      end
      return
    end
    if button == "LeftButton" and GT and GT.ToggleOptions then
      GT:ToggleOptions()
    end
  end)

  btn:SetScript("OnDragStart", function(self)
    if GameTooltip and GameTooltip:IsOwned(self) then
      GameTooltip:Hide()
    end
    self:SetScript("OnUpdate", function()
      local mx, my = GetCursorPosition()
      local scale = Minimap:GetEffectiveScale()
      mx = mx / scale
      my = my / scale
      local cx, cy = Minimap:GetCenter()
      if not cx or not cy then
        return
      end
      local dx = mx - cx
      local dy = my - cy
      local angle = math.deg(math.atan2(dy, dx))
      if angle < 0 then
        angle = angle + 360
      end
      if GT and GT.db then
        GT.db.minimapIconAngle = angle
      end
      if GT and GT.UpdateMinimapButtonPosition then
        GT:UpdateMinimapButtonPosition()
      end
    end)
  end)

  btn:SetScript("OnDragStop", function(self)
    self:SetScript("OnUpdate", nil)
    self._ignoreNextClick = true
  end)

  self.minimapButton = btn
  self:UpdateMinimapButtonPosition()
  btn:SetShown(not (self.db and self.db.minimapIconHidden))
end

function GT:GetDefaultBarOffsets()
  local target = _G.TargetFrame
  if target and target.GetCenter and UIParent and UIParent.GetCenter then
    local tx, ty = target:GetCenter()
    local ux, uy = UIParent:GetCenter()
    if tx and ty and ux and uy then
      return math.floor((tx - ux) + 0.5), math.floor((ty - uy) - 42 + 0.5)
    end
  end
  return 0, 120
end

function GT:ApplyBarLayout()
  if not self.overlayFrame or not self.db then
    return
  end
  if self.overlayFrame.isSizing then
    return
  end
  self.db.barWidth = clamp(tonumber(self.db.barWidth) or 180, 120, 600)
  self.db.barHeight = clamp(tonumber(self.db.barHeight) or 18, 10, 80)
  self.overlayFrame:SetSize(self.db.barWidth, self.db.barHeight)
end

function GT:ApplyBarPosition()
  if not self.overlayFrame or not self.db then
    return
  end
  self.overlayFrame:ClearAllPoints()
  self.overlayFrame:SetPoint(
    self.db.barPoint or "CENTER",
    UIParent,
    self.db.barRelativePoint or "CENTER",
    tonumber(self.db.barOffsetX) or 0,
    tonumber(self.db.barOffsetY) or 120
  )
end

function GT:UpdateSoundToggleButton()
  if not self.overlayFrame or not self.overlayFrame.soundToggleButton then
    return
  end
  local enabled = self.db and self.db.enableSound
  local icon = self.overlayFrame.soundToggleButton.icon
  if icon then
    if enabled then
      icon:SetTexture("Interface\\COMMON\\VoiceChat-Speaker")
      icon:SetVertexColor(1, 1, 1, 0.95)
    else
      icon:SetTexture("Interface\\COMMON\\VoiceChat-Muted")
      icon:SetVertexColor(1, 0.60, 0.60, 0.95)
    end
  end
end

function GT:SetAddonSoundEnabled(enabled)
  if not self.db then
    return
  end
  self.db.enableSound = not not enabled
  self:ValidateDB()
  self:UpdateSoundToggleButton()
  if self.RefreshOptionsUI then
    self:RefreshOptionsUI()
  end
end

function GT:ToggleAddonSound()
  if not self.db then
    return
  end
  self:SetAddonSoundEnabled(not self.db.enableSound)
end

function GT:SaveBarPosition()
  if not self.overlayFrame or not self.db then
    return
  end
  local cx, cy = self.overlayFrame:GetCenter()
  local ux, uy = UIParent:GetCenter()
  if not cx or not cy or not ux or not uy then
    return
  end
  self.db.barPoint = "CENTER"
  self.db.barRelativePoint = "CENTER"
  self.db.barOffsetX = math.floor((cx - ux) + 0.5)
  self.db.barOffsetY = math.floor((cy - uy) + 0.5)
end

function GT:SaveBarSize()
  if not self.overlayFrame or not self.db then
    return
  end
  local w = clamp(self.overlayFrame:GetWidth(), 120, 600)
  local h = clamp(self.overlayFrame:GetHeight(), 10, 80)
  self.db.barWidth = math.floor(w + 0.5)
  self.db.barHeight = math.floor(h + 0.5)
  self:ApplyBarLayout()
end

function GT:ResetBarPosition()
  if not self.db then
    return
  end
  local x, y = self:GetDefaultBarOffsets()
  self.db.barPoint = "CENTER"
  self.db.barRelativePoint = "CENTER"
  self.db.barOffsetX = x
  self.db.barOffsetY = y
  self:ApplyBarPosition()
  self:Print("Bar position reset.")
end

function GT:SetBarLocked(locked)
  if not self.db then
    return
  end
  self.db.barLocked = not not locked
  if self.overlayFrame then
    self.overlayFrame:EnableMouse(not self.db.barLocked)
    if self.overlayFrame.resizeHandle then
      self.overlayFrame.resizeHandle:SetShown(not self.db.barLocked)
    end
    self:UpdateUnlockOverlay()
  end
  if self.db.barLocked then
    self:Print("Bar locked.")
    self:RefreshNow()
  else
    self:Print("Bar unlocked. Drag bar or resize from bottom-right handle.")
    if self.overlayFrame then
      self.overlayFrame.targetPercent = math.max(self.overlayFrame.targetPercent or 0, 60)
      self.overlayFrame.targetR, self.overlayFrame.targetG, self.overlayFrame.targetB, self.overlayFrame.targetA = 0.98, 0.84, 0.30, 0.95
      self.overlayFrame.targetAlpha = 0.95
      self.overlayFrame.valueText:SetText("Drag / Resize")
      self.overlayFrame.valueText:Show()
      self.overlayFrame:Show()
    end
  end
end

function GT:UpdateUnlockOverlay()
  if not self.overlayFrame or not self.overlayFrame.unlockOverlay then
    return
  end
  if self.db and not self.db.barLocked then
    self.overlayFrame.unlockOverlay:Show()
  else
    self.overlayFrame.unlockOverlay:Hide()
  end
end

function GT:InitUI()
  if self.db then
    self:InitMinimapButton()
  end

  if self.overlayFrame then
    self:ApplyBarLayout()
    self:ApplyBarPosition()
    self:ApplyBarStyle()
    self:UpdateSoundToggleButton()
    return
  end

  local parent, point, relPoint, x, y = self:EnsureBarAnchor()
  local frame = CreateFrame("Frame", "GorilThreatBarFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate")
  frame:SetPoint(point, parent, relPoint, x, y)
  frame:SetFrameStrata("HIGH")
  frame:SetFrameLevel(25)
  frame:Hide()

  frame.bg = frame:CreateTexture(nil, "BACKGROUND")
  frame.bg:SetAllPoints(frame)
  frame.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
  frame.bg:SetVertexColor(0.02, 0.02, 0.02, 0.78)

  frame.bar = CreateFrame("StatusBar", nil, frame)
  frame.bar:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
  frame.bar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
  frame.bar:SetMinMaxValues(0, 100)
  frame.bar:SetStatusBarTexture(self:GetBarTexturePath(self.db and self.db.barTextureStyle))
  frame.bar:SetStatusBarColor(0.2, 0.85, 0.3, 1)
  frame.bar:SetValue(0)

  frame.unlockOverlay = frame.bar:CreateTexture(nil, "OVERLAY")
  frame.unlockOverlay:SetAllPoints(frame.bar)
  frame.unlockOverlay:SetTexture("Interface\\Buttons\\WHITE8X8")
  frame.unlockOverlay:SetVertexColor(0.15, 0.95, 0.20, 0.18)
  frame.unlockOverlay:Hide()

  frame.soundToggleButton = CreateFrame("Button", nil, frame)
  frame.soundToggleButton:SetSize(16, 16)
  frame.soundToggleButton:SetPoint("TOPLEFT", frame, "TOPLEFT", 2, -2)
  frame.soundToggleButton:SetFrameLevel(frame:GetFrameLevel() + 8)
  frame.soundToggleButton:SetHitRectInsets(-4, -4, -4, -4)
  frame.soundToggleButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  frame.soundToggleButton.icon = frame.soundToggleButton:CreateTexture(nil, "ARTWORK")
  frame.soundToggleButton.icon:SetAllPoints(frame.soundToggleButton)
  frame.soundToggleButton:SetScript("OnClick", function(_, button)
    if button == "RightButton" then
      if GT and GT.ToggleOptions then
        GT:ToggleOptions()
      end
      return
    end
    if GT and GT.ToggleAddonSound then
      GT:ToggleAddonSound()
    end
  end)

  frame.flashBorder = { layers = {} }
  local function createGlowLayer(offset, thickness, alphaScale)
    local layer = { alphaScale = alphaScale or 1 }
    layer.top = frame:CreateTexture(nil, "OVERLAY")
    layer.top:SetTexture("Interface\\Buttons\\WHITE8X8")
    layer.top:SetPoint("TOPLEFT", frame, "TOPLEFT", -offset, offset)
    layer.top:SetPoint("TOPRIGHT", frame, "TOPRIGHT", offset, offset)
    layer.top:SetHeight(thickness)

    layer.bottom = frame:CreateTexture(nil, "OVERLAY")
    layer.bottom:SetTexture("Interface\\Buttons\\WHITE8X8")
    layer.bottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", -offset, -offset)
    layer.bottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", offset, -offset)
    layer.bottom:SetHeight(thickness)

    layer.left = frame:CreateTexture(nil, "OVERLAY")
    layer.left:SetTexture("Interface\\Buttons\\WHITE8X8")
    layer.left:SetPoint("TOPLEFT", frame, "TOPLEFT", -offset, offset)
    layer.left:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", -offset, -offset)
    layer.left:SetWidth(thickness)

    layer.right = frame:CreateTexture(nil, "OVERLAY")
    layer.right:SetTexture("Interface\\Buttons\\WHITE8X8")
    layer.right:SetPoint("TOPRIGHT", frame, "TOPRIGHT", offset, offset)
    layer.right:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", offset, -offset)
    layer.right:SetWidth(thickness)

    table.insert(frame.flashBorder.layers, layer)
  end
  createGlowLayer(1, 2, 1.00)
  createGlowLayer(3, 4, 0.55)
  createGlowLayer(6, 6, 0.28)

  frame.flashEnabled = false
  frame.flashAlpha = 0

  frame.valueText = frame.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  frame.valueText:SetPoint("CENTER", frame.bar, "CENTER", 0, 0)
  frame.valueText:SetDrawLayer("OVERLAY", 7)
  frame.valueText:SetTextColor(1, 1, 1, 1)
  frame.valueText:SetText("")

  frame.targetPercent = 0
  frame.currentPercent = 0
  frame.targetR, frame.targetG, frame.targetB, frame.targetA = 0.2, 0.85, 0.3, 1
  frame.currentR, frame.currentG, frame.currentB, frame.currentA = 0.2, 0.85, 0.3, 1
  frame.targetAlpha = 1
  frame.currentAlpha = 1
  frame:SetMovable(true)
  frame:SetResizable(true)
  if frame.SetResizeBounds then
    frame:SetResizeBounds(120, 10, 600, 80)
  else
    if frame.SetMinResize then
      frame:SetMinResize(120, 10)
    end
    if frame.SetMaxResize then
      frame:SetMaxResize(600, 80)
    end
  end
  frame:EnableMouse(not (self.db and self.db.barLocked))
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function(self)
    if GT.db and not GT.db.barLocked and not self.isSizing then
      self:StartMoving()
    end
  end)
  frame:SetScript("OnDragStop", function(self)
    if self.isSizing then
      return
    end
    self:StopMovingOrSizing()
    GT:SaveBarPosition()
  end)

  frame.resizeHandle = CreateFrame("Button", nil, frame)
  frame.resizeHandle:SetSize(16, 16)
  frame.resizeHandle:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
  frame.resizeHandle:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  frame.resizeHandle:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  frame.resizeHandle:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
  local function finishResize()
    if not frame.isSizing then
      return
    end
    frame:StopMovingOrSizing()
    frame.isSizing = nil
    GT:SaveBarSize()
    GT:SaveBarPosition()
  end

  frame.resizeHandle:SetScript("OnMouseDown", function(_, button)
    if button ~= "LeftButton" then
      return
    end
    if GT.db and not GT.db.barLocked then
      frame.isSizing = true
      frame:StartSizing("BOTTOMRIGHT")
    end
  end)
  frame.resizeHandle:SetScript("OnMouseUp", function()
    finishResize()
  end)
  frame.resizeHandle:SetScript("OnHide", function()
    finishResize()
  end)
  frame:SetScript("OnMouseUp", function(_, button)
    if button == "LeftButton" then
      finishResize()
    end
  end)

  frame:SetScript("OnUpdate", function(self, elapsed)
    local rate = math.min(1, elapsed * 16)

    self.currentPercent = self.currentPercent + (self.targetPercent - self.currentPercent) * rate
    self.currentR = self.currentR + (self.targetR - self.currentR) * rate
    self.currentG = self.currentG + (self.targetG - self.currentG) * rate
    self.currentB = self.currentB + (self.targetB - self.currentB) * rate
    self.currentA = self.currentA + (self.targetA - self.currentA) * rate
    self.currentAlpha = self.currentAlpha + (self.targetAlpha - self.currentAlpha) * rate

    self.bar:SetValue(self.currentPercent)
    self.bar:SetStatusBarColor(self.currentR, self.currentG, self.currentB, self.currentA)
    self:SetAlpha(self.currentAlpha)

    local borderAlpha = 0
    if self.flashEnabled then
      local pulse = (math.sin(GetTime() * 14) + 1) * 0.5
      borderAlpha = 0.30 + (pulse * 0.70)
    end
    self.flashAlpha = self.flashAlpha + (borderAlpha - self.flashAlpha) * rate
    if self.flashBorder and self.flashBorder.layers then
      local r, g, b = 1, 0.10, 0.10
      for _, layer in ipairs(self.flashBorder.layers) do
        local a = self.flashAlpha * (layer.alphaScale or 1)
        layer.top:SetVertexColor(r, g, b, a)
        layer.bottom:SetVertexColor(r, g, b, a)
        layer.left:SetVertexColor(r, g, b, a)
        layer.right:SetVertexColor(r, g, b, a)
      end
    end
  end)

  self.overlayFrame = frame
  self:ApplyBarLayout()
  if self.db and self.db.barOffsetX == 0 and self.db.barOffsetY == 120 then
    self:ResetBarPosition()
  else
    self:ApplyBarPosition()
  end
  if self.overlayFrame.resizeHandle then
    self.overlayFrame.resizeHandle:SetShown(not (self.db and self.db.barLocked))
  end
  self:UpdateUnlockOverlay()
  self:UpdateSoundToggleButton()
  self:ApplyBarStyle()
end

function GT:HideThreatUI()
  if not self.overlayFrame then
    return
  end
  if self.db and not self.db.barLocked then
    self.overlayFrame.targetPercent = math.max(self.overlayFrame.targetPercent or 0, 60)
    self.overlayFrame.targetR, self.overlayFrame.targetG, self.overlayFrame.targetB, self.overlayFrame.targetA = 0.98, 0.84, 0.30, 0.95
    self.overlayFrame.targetAlpha = 0.95
    self.overlayFrame.valueText:SetText("Drag / Resize")
    self.overlayFrame.valueText:Show()
    self.overlayFrame:Show()
    return
  end
  self.overlayFrame:Hide()
  self.overlayFrame.valueText:SetText("")
  if self.overlayFrame.flashBorder and self.overlayFrame.flashBorder.layers then
    self.overlayFrame.flashEnabled = false
    self.overlayFrame.flashAlpha = 0
    for _, layer in ipairs(self.overlayFrame.flashBorder.layers) do
      layer.top:SetVertexColor(1, 0.1, 0.1, 0)
      layer.bottom:SetVertexColor(1, 0.1, 0.1, 0)
      layer.left:SetVertexColor(1, 0.1, 0.1, 0)
      layer.right:SetVertexColor(1, 0.1, 0.1, 0)
    end
  end
end

function GT:UpdateThreatUI(state, percent, alpha, threatValue)
  if not self.overlayFrame then
    self:InitUI()
    if not self.overlayFrame then
      return
    end
  end

  if type(percent) ~= "number" then
    self:HideThreatUI()
    return
  end

  self:ApplyBarLayout()

  local p = clampPercent(percent)
  local style = GT.VISUALS[state] or GT.VISUALS[GT.STATE_SAFE]
  local r, g, b, a = style.r, style.g, style.b, style.a
  local fullAggro = (state == GT.STATE_AGGRO and p >= 100)
  if fullAggro then
    r, g, b, a = 1.00, 0.08, 0.08, 1.00
  end
  if self.db and self.db.enableLowNoise and not self.testMode and (state == GT.STATE_SAFE or state == GT.STATE_RISING) then
    -- Desaturate safe/rising visuals in low-noise mode.
    r = (r * 0.45) + 0.20
    g = (g * 0.45) + 0.20
    b = (b * 0.45) + 0.20
    a = a * 0.85
  end
  local targetAlpha = alpha or 1

  self.overlayFrame.targetPercent = p
  self.overlayFrame.targetR = r
  self.overlayFrame.targetG = g
  self.overlayFrame.targetB = b
  self.overlayFrame.targetA = a
  self.overlayFrame.targetAlpha = targetAlpha
  local flashAllowed = not (self.db and self.db.enableFlash == false)
  self.overlayFrame.flashEnabled = flashAllowed and ((self.testMode ~= nil) or (state == GT.STATE_DANGER) or fullAggro)

  local showPercentMode = self.testMode or (self.db and self.db.showPercentText)

  if fullAggro then
    self.overlayFrame.valueText:SetText("AGGRO!!")
    self.overlayFrame.valueText:Show()
  elseif showPercentMode then
    self.overlayFrame.valueText:SetFormattedText("%d%%", p)
    self.overlayFrame.valueText:Show()
  else
    local displayValue = tonumber(threatValue)
    self.overlayFrame.valueText:SetText(formatThreatValue(displayValue))
    self.overlayFrame.valueText:Show()
  end

  self.overlayFrame:Show()
end
