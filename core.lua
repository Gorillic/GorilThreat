local ADDON_NAME = ...

GorilThreat = GorilThreat or {}
local GT = GorilThreat

GT.ADDON_NAME = ADDON_NAME or "GorilThreat"
GT.VERSION = "0.1.0"
GT.THROTTLE_SECONDS = 0.2

GT.STATE_SAFE = "SAFE"
GT.STATE_RISING = "RISING"
GT.STATE_DANGER = "DANGER"
GT.STATE_AGGRO = "AGGRO"

GT.DEFAULTS = {
  RisingStart = 55,
  DangerStart = 75,
  showOnlyInCombat = true,
  showOnlyInGroup = false,
  showOnlyInRaid = false,
  showOnlyInInstances = false,
  showPercentText = true,
  enableSound = true,
  enableFlash = true,
  enableCombatFade = true,
  outOfCombatAlpha = 60,
  enableLowNoise = true,
  lowNoiseAlpha = 72,
  alertCooldownSeconds = 3,
  enableAggroBlink = true,
  barWidth = 180,
  barHeight = 18,
  barTextureStyle = "default",
  barLocked = true,
  barPoint = "CENTER",
  barRelativePoint = "CENTER",
  barOffsetX = 0,
  barOffsetY = 120,
  minimapIconAngle = 220,
  minimapIconHidden = false,
}

GT.state = GT.STATE_SAFE
GT.lastAlertAt = 0
GT.threatEnabled = false
GT.threatLib = nil
GT.didWarnMissingLib = false
GT.testMode = nil
GT.testSequence = nil
GT.elapsed = 0
GT.didWarnUIUnavailable = false
GT.lastTargetGUID = nil
GT.stylePreviewActive = false

local function shallowCopy(tbl)
  local out = {}
  for k, v in pairs(tbl) do
    out[k] = v
  end
  return out
end

local function copyDefaults()
  local out = {}
  for k, v in pairs(GT.DEFAULTS) do
    out[k] = v
  end
  return out
end

local function trimString(value)
  if type(value) ~= "string" then
    return ""
  end
  return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function isLegacyFlatDB(db)
  if type(db) ~= "table" then
    return false
  end
  if type(db.profiles) == "table" then
    return false
  end
  return db.RisingStart ~= nil or db.DangerStart ~= nil or db.barWidth ~= nil
end

local function clamp(value, minValue, maxValue)
  if value == nil then
    return minValue
  end
  if value < minValue then
    return minValue
  end
  if value > maxValue then
    return maxValue
  end
  return value
end

local function playerInGroup()
  if IsInGroup then
    return IsInGroup()
  end
  local count = (GetNumPartyMembers and GetNumPartyMembers()) or 0
  local raidCount = (GetNumRaidMembers and GetNumRaidMembers()) or 0
  if raidCount > 0 then
    return true
  end
  return count > 0
end

local function playerInRaid()
  if IsInRaid then
    return IsInRaid()
  end
  local count = (GetNumRaidMembers and GetNumRaidMembers()) or 0
  return count > 0
end

local function inInstance()
  if not IsInInstance then
    return false
  end
  local inside = IsInInstance()
  return inside and true or false
end

function GT:Print(msg)
  local text = "|cff77dd77GorilThreat|r: " .. tostring(msg)
  if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
    DEFAULT_CHAT_FRAME:AddMessage(text)
    return
  end
  print(text)
end

function GT:EnsureDB()
  local raw = GorilThreatDB
  if isLegacyFlatDB(raw) then
    local migrated = copyDefaults()
    for k, v in pairs(raw) do
      if self.DEFAULTS[k] ~= nil then
        migrated[k] = v
      end
    end
    raw = {
      activeProfile = "Default",
      profiles = {
        Default = migrated,
      },
    }
  end

  if type(raw) ~= "table" then
    raw = {}
  end
  raw.profiles = type(raw.profiles) == "table" and raw.profiles or {}
  raw.profileOrder = type(raw.profileOrder) == "table" and raw.profileOrder or {}

  local ordered = {}
  local seen = {}
  for _, name in ipairs(raw.profileOrder) do
    if type(name) == "string" and type(raw.profiles[name]) == "table" and not seen[name] then
      table.insert(ordered, name)
      seen[name] = true
    end
  end

  if type(raw.profiles["Default"]) == "table" and not seen["Default"] then
    table.insert(ordered, "Default")
    seen["Default"] = true
  end

  local extraNames = {}
  for name, profileData in pairs(raw.profiles) do
    if type(name) == "string" and type(profileData) == "table" and not seen[name] then
      table.insert(extraNames, name)
      seen[name] = true
    end
  end
  table.sort(extraNames, function(a, b)
    return string.lower(a) < string.lower(b)
  end)
  for _, name in ipairs(extraNames) do
    table.insert(ordered, name)
  end

  if #ordered == 0 then
    raw.profiles.Default = copyDefaults()
    ordered = { "Default" }
  end

  raw.profileOrder = ordered
  local active = tostring(raw.activeProfile or ordered[1] or "Default")
  if type(raw.profiles[active]) ~= "table" then
    active = ordered[1] or "Default"
  end

  raw.activeProfile = active
  GorilThreatDB = raw
  self.dbRoot = raw
  self.dbProfileName = active
  self.db = raw.profiles[active]
  self:ValidateDB()
end

function GT:GetActiveProfileName()
  if self.dbProfileName then
    return tostring(self.dbProfileName)
  end
  if self.dbRoot and type(self.dbRoot.profileOrder) == "table" and #self.dbRoot.profileOrder > 0 then
    return tostring(self.dbRoot.profileOrder[1])
  end
  return "Default"
end

function GT:GetProfileNames()
  if not self.dbRoot or type(self.dbRoot.profileOrder) ~= "table" then
    self:EnsureDB()
  end
  local names = {}
  if self.dbRoot and type(self.dbRoot.profileOrder) == "table" then
    for _, name in ipairs(self.dbRoot.profileOrder) do
      if type(name) == "string" then
        table.insert(names, name)
      end
    end
  end
  if #names == 0 then
    table.insert(names, "Default")
  end
  return names
end

function GT:NormalizeProfileName(name)
  local cleaned = trimString(tostring(name or ""))
  if cleaned == "" then
    return nil
  end
  if string.len(cleaned) > 32 then
    cleaned = string.sub(cleaned, 1, 32)
  end
  return cleaned
end

function GT:CreateProfile(name)
  if not self.dbRoot or type(self.dbRoot.profiles) ~= "table" then
    self:EnsureDB()
  end
  local profileName = self:NormalizeProfileName(name)
  if not profileName then
    self:Print("Profile name is empty.")
    return false
  end
  if type(self.dbRoot.profiles[profileName]) == "table" then
    self:Print("Profile already exists: " .. profileName)
    return false
  end

  self.dbRoot.profiles[profileName] = shallowCopy(self.db or copyDefaults())
  self.dbRoot.profileOrder = type(self.dbRoot.profileOrder) == "table" and self.dbRoot.profileOrder or {}
  table.insert(self.dbRoot.profileOrder, profileName)
  self:SetActiveProfile(profileName)
  self:Print("Profile created: " .. profileName)
  return true
end

function GT:RenameProfile(oldName, newName)
  if not self.dbRoot or type(self.dbRoot.profiles) ~= "table" then
    self:EnsureDB()
  end
  local fromName = tostring(oldName or self:GetActiveProfileName() or "")
  local toName = self:NormalizeProfileName(newName)
  if not toName then
    self:Print("New profile name is empty.")
    return false
  end
  if fromName == "" or type(self.dbRoot.profiles[fromName]) ~= "table" then
    self:Print("Profile not found: " .. fromName)
    return false
  end
  if fromName == toName then
    return true
  end
  if type(self.dbRoot.profiles[toName]) == "table" then
    self:Print("Profile already exists: " .. toName)
    return false
  end

  self.dbRoot.profiles[toName] = self.dbRoot.profiles[fromName]
  self.dbRoot.profiles[fromName] = nil
  if type(self.dbRoot.profileOrder) == "table" then
    for i, name in ipairs(self.dbRoot.profileOrder) do
      if name == fromName then
        self.dbRoot.profileOrder[i] = toName
      end
    end
  end
  if self.dbRoot.activeProfile == fromName then
    self.dbRoot.activeProfile = toName
    self.dbProfileName = toName
    self.db = self.dbRoot.profiles[toName]
  end
  if self.RefreshOptionsUI then
    self:RefreshOptionsUI()
  end
  self:Print("Profile renamed: " .. fromName .. " -> " .. toName)
  return true
end

function GT:DeleteProfile(name)
  if not self.dbRoot or type(self.dbRoot.profiles) ~= "table" then
    self:EnsureDB()
  end
  local target = tostring(name or self:GetActiveProfileName() or "")
  if target == "" or type(self.dbRoot.profiles[target]) ~= "table" then
    self:Print("Profile not found: " .. target)
    return false
  end

  local names = self:GetProfileNames()
  if #names <= 1 then
    self:Print("At least one profile is required.")
    return false
  end

  self.dbRoot.profiles[target] = nil
  if type(self.dbRoot.profileOrder) == "table" then
    for i = #self.dbRoot.profileOrder, 1, -1 do
      if self.dbRoot.profileOrder[i] == target then
        table.remove(self.dbRoot.profileOrder, i)
      end
    end
  end

  local nextProfile = self.dbRoot.profileOrder and self.dbRoot.profileOrder[1] or "Default"
  if self.dbRoot.activeProfile == target then
    self:SetActiveProfile(nextProfile)
  else
    if self.RefreshOptionsUI then
      self:RefreshOptionsUI()
    end
  end
  self:Print("Profile deleted: " .. target)
  return true
end

function GT:ConfirmDeleteActiveProfile()
  local activeName = self:GetActiveProfileName()
  if not activeName or activeName == "" then
    return
  end

  local dialogs = _G.StaticPopupDialogs
  local showPopup = _G.StaticPopup_Show
  if dialogs and showPopup then
    if not dialogs.GORILTHREAT_CONFIRM_DELETE_PROFILE then
      dialogs.GORILTHREAT_CONFIRM_DELETE_PROFILE = {
        text = "Are you sure you want to delete profile '%s'?",
        button1 = YES,
        button2 = NO,
        OnAccept = function(dialog)
          local profileName = dialog and dialog.data
          if GT and GT.DeleteProfile then
            GT:DeleteProfile(profileName)
          end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
      }
    end
    showPopup("GORILTHREAT_CONFIRM_DELETE_PROFILE", activeName, nil, activeName)
    return
  end

  self:Print("Delete confirmation popup is unavailable. Profile was not deleted.")
end

function GT:SetActiveProfile(name)
  if not self.dbRoot or type(self.dbRoot.profiles) ~= "table" then
    self:EnsureDB()
  end
  local target = tostring(name or self:GetActiveProfileName() or "Default")
  if type(self.dbRoot.profiles[target]) ~= "table" then
    return
  end

  self.dbRoot.profiles[target] = type(self.dbRoot.profiles[target]) == "table" and self.dbRoot.profiles[target] or copyDefaults()
  self.dbRoot.activeProfile = target
  self.dbProfileName = target
  self.db = self.dbRoot.profiles[target]
  self:ValidateDB()

  if self.ApplyBarLayout then
    self:ApplyBarLayout()
  end
  if self.ApplyBarPosition then
    self:ApplyBarPosition()
  end
  if self.ApplyBarStyle then
    self:ApplyBarStyle()
  end
  if self.SetBarLocked and self.db then
    self:SetBarLocked(self.db.barLocked)
  end
  if self.UpdateMinimapButtonPosition then
    self:UpdateMinimapButtonPosition()
  end
  if self.minimapButton then
    self.minimapButton:SetShown(not (self.db and self.db.minimapIconHidden))
  end
  if self.RefreshOptionsUI then
    self:RefreshOptionsUI()
  end
  self:RefreshNow()
end

function GT:ValidateDB()
  if not self.db then
    return
  end

  self.db.RisingStart = clamp(tonumber(self.db.RisingStart) or self.DEFAULTS.RisingStart, 0, 99)
  self.db.DangerStart = clamp(tonumber(self.db.DangerStart) or self.DEFAULTS.DangerStart, 1, 100)
  if self.db.DangerStart <= self.db.RisingStart then
    self.db.DangerStart = clamp(self.db.RisingStart + 1, 1, 100)
  end

  self.db.alertCooldownSeconds = clamp(tonumber(self.db.alertCooldownSeconds) or self.DEFAULTS.alertCooldownSeconds, 1, 30)
  self.db.showOnlyInCombat = not not self.db.showOnlyInCombat
  self.db.showOnlyInGroup = not not self.db.showOnlyInGroup
  self.db.showOnlyInRaid = not not self.db.showOnlyInRaid
  self.db.showOnlyInInstances = not not self.db.showOnlyInInstances
  self.db.showPercentText = not not self.db.showPercentText
  self.db.enableSound = not not self.db.enableSound
  self.db.enableFlash = not not self.db.enableFlash
  self.db.enableCombatFade = not not self.db.enableCombatFade
  self.db.outOfCombatAlpha = clamp(tonumber(self.db.outOfCombatAlpha) or self.DEFAULTS.outOfCombatAlpha, 15, 100)
  self.db.enableLowNoise = not not self.db.enableLowNoise
  self.db.lowNoiseAlpha = clamp(tonumber(self.db.lowNoiseAlpha) or self.DEFAULTS.lowNoiseAlpha, 15, 100)
  self.db.enableAggroBlink = not not self.db.enableAggroBlink
  self.db.barWidth = clamp(tonumber(self.db.barWidth) or self.DEFAULTS.barWidth, 120, 600)
  self.db.barHeight = clamp(tonumber(self.db.barHeight) or self.DEFAULTS.barHeight, 10, 80)
  self.db.barTextureStyle = tostring(self.db.barTextureStyle or self.DEFAULTS.barTextureStyle)
  if self.db.barTextureStyle == "" then
    self.db.barTextureStyle = self.DEFAULTS.barTextureStyle
  end
  self.db.barLocked = not not self.db.barLocked
  self.db.barPoint = tostring(self.db.barPoint or self.DEFAULTS.barPoint)
  self.db.barRelativePoint = tostring(self.db.barRelativePoint or self.DEFAULTS.barRelativePoint)
  self.db.barOffsetX = clamp(tonumber(self.db.barOffsetX) or self.DEFAULTS.barOffsetX, -2000, 2000)
  self.db.barOffsetY = clamp(tonumber(self.db.barOffsetY) or self.DEFAULTS.barOffsetY, -2000, 2000)
  self.db.minimapIconAngle = clamp(tonumber(self.db.minimapIconAngle) or self.DEFAULTS.minimapIconAngle, 0, 359)
  self.db.minimapIconHidden = not not self.db.minimapIconHidden
end

function GT:ResetDB()
  if not self.dbRoot or type(self.dbRoot.profiles) ~= "table" then
    self:EnsureDB()
  end
  local profile = self:GetActiveProfileName()
  self.dbRoot.profiles[profile] = copyDefaults()
  self.db = self.dbRoot.profiles[profile]
  self:ValidateDB()
  if self.ApplyBarStyle then
    self:ApplyBarStyle()
  end
  self.lastAlertAt = 0
  self.state = self.STATE_SAFE
  self:RefreshOptionsUI()
  self:RefreshNow()
end

function GT:TryLoadThreatLibrary()
  self.threatEnabled = false
  self.threatLib = nil
  self.useNativeThreatApi = false

  local function looksLikeThreatProvider(candidate)
    if type(candidate) ~= "table" then
      return false
    end
    if type(candidate.UnitThreatSituation) == "function" then
      return true
    end
    if type(candidate.GetThreatSituation) == "function" then
      return true
    end
    if type(candidate.GetUnitThreat) == "function" then
      return true
    end
    if type(candidate.GetThreatOnUnit) == "function" then
      return true
    end
    if type(candidate.GetPlayerThreat) == "function" then
      return true
    end
    return false
  end

  local lib
  if LibStub then
    local ok, loaded = pcall(LibStub, "LibThreatClassic2", true)
    if ok and looksLikeThreatProvider(loaded) then
      lib = loaded
    end
  end

  if not lib then
    local globalsToTry = {
      _G.LibThreatClassic2,
      _G.ThreatClassic2,
      _G.ThreatClassic2Lib,
    }
    for _, candidate in ipairs(globalsToTry) do
      if looksLikeThreatProvider(candidate) then
        lib = candidate
        break
      end
    end
  end

  if lib then
    self.threatLib = lib
    self.threatEnabled = true
    return
  end

  if type(UnitDetailedThreatSituation) == "function" then
    self.useNativeThreatApi = true
    self.threatEnabled = true
    return
  end

  if not self.didWarnMissingLib then
    self.didWarnMissingLib = true
    self:Print("Threat library missing (LibThreatClassic2). Install it to enable live threat. Standalone LibThreatClassic2 required for embedded mode.")
  end
end

local function parseThreatResult(a, b, c, d, e)
  local hasAggro = false
  local percent = nil
  local threatValue = nil

  if type(a) == "boolean" then
    hasAggro = a
    if type(b) == "number" and b >= 3 then
      hasAggro = true
    end
    if type(c) == "number" then
      percent = c
    elseif type(d) == "number" then
      percent = d
    end
    if type(e) == "number" then
      threatValue = e
    end
  elseif type(a) == "number" then
    percent = a
    if type(b) == "boolean" then
      hasAggro = b
    elseif type(b) == "number" and b >= 3 then
      hasAggro = true
    end
  elseif type(a) == "table" then
    percent = tonumber(a.scaledPercent or a.percent or a.threatPercent or a.rawPercent)
    hasAggro = not not (a.isTanking or a.hasAggro or a.aggro or a.status == 3)
    threatValue = tonumber(a.threatValue or a.rawThreat or a.value)
  end

  if type(percent) ~= "number" then
    return nil, false, nil
  end

  percent = clamp(percent, 0, 100)
  if type(threatValue) == "number" then
    threatValue = math.max(0, math.floor(threatValue + 0.5))
  end
  return percent, hasAggro, threatValue
end

local function safeCall(methodOwner, methodName, ...)
  if not methodOwner or type(methodOwner[methodName]) ~= "function" then
    return nil
  end
  local fn = methodOwner[methodName]
  local ok, a, b, c, d, e = pcall(fn, methodOwner, ...)
  if not ok then
    ok, a, b, c, d, e = pcall(fn, ...)
  end
  if not ok then
    return nil
  end
  return a, b, c, d, e
end

local function getNativeThreatData()
  if type(UnitDetailedThreatSituation) ~= "function" then
    return nil, false, nil
  end
  if not UnitExists("target") then
    return nil, false, nil
  end

  local ok, isTanking, status, scaledPercent, rawPercent, threatValue = pcall(UnitDetailedThreatSituation, "player", "target")
  if not ok then
    return nil, false, nil
  end

  local percent = tonumber(scaledPercent or rawPercent)
  if type(percent) ~= "number" then
    return nil, false, nil
  end

  percent = clamp(percent, 0, 100)
  local hasAggro = (isTanking == true) or (type(status) == "number" and status >= 3)
  local value = tonumber(threatValue)
  if type(value) == "number" then
    value = math.max(0, math.floor(value + 0.5))
  end
  return percent, hasAggro, value
end

function GT:GetThreatData()
  if not self.threatEnabled then
    return nil, false, nil
  end
  if not UnitExists("target") then
    return nil, false, nil
  end

  if self.threatLib then
    local fallbackPlayerThreatValue = nil
    if UnitGUID and type(self.threatLib.GetThreat) == "function" then
      local playerGUID = UnitGUID("player")
      local targetGUID = UnitGUID("target")
      if playerGUID and targetGUID then
        local ok, raw = pcall(self.threatLib.GetThreat, self.threatLib, playerGUID, targetGUID)
        if ok and type(raw) == "number" then
          fallbackPlayerThreatValue = math.max(0, math.floor(raw + 0.5))
        end
      end
    end

    local a, b, c, d, e
    local playerPercent, playerAggro, playerThreatValue = nil, false, fallbackPlayerThreatValue
    a, b, c, d, e = safeCall(self.threatLib, "UnitDetailedThreatSituation", "player", "target")
    if a ~= nil then
      playerPercent, playerAggro, playerThreatValue = parseThreatResult(a, b, c, d, e)
      if type(playerThreatValue) ~= "number" then
        playerThreatValue = fallbackPlayerThreatValue
      end
    end

    local percent = playerPercent
    local hasAggro = (playerAggro == true)
    local threatValue = playerThreatValue
    if percent ~= nil or threatValue ~= nil then
      return percent, hasAggro, threatValue
    end

    return nil, false, nil
  end

  if self.useNativeThreatApi then
    return getNativeThreatData()
  end

  return nil, false, nil
end

function GT:ShouldDisplay()
  if self.testMode then
    return true
  end

  local inRaidNow = playerInRaid()
  local inGroupNow = playerInGroup()
  if self.db.showOnlyInRaid then
    if not inRaidNow then
      return false
    end
  elseif self.db.showOnlyInGroup and not inGroupNow then
    return false
  end
  if self.db.showOnlyInInstances and not inInstance() then
    return false
  end

  if self.db.showOnlyInCombat and not UnitAffectingCombat("player") then
    return false
  end
  return true
end

function GT:ResolveState(percent, hasAggro)
  if hasAggro then
    return self.STATE_AGGRO
  end
  if percent and percent >= self.db.DangerStart then
    return self.STATE_DANGER
  end
  if percent and percent >= self.db.RisingStart then
    return self.STATE_RISING
  end
  return self.STATE_SAFE
end

function GT:ResolveTestState(percent)
  if type(percent) ~= "number" then
    return self.STATE_SAFE
  end
  if percent >= 100 then
    return self.STATE_AGGRO
  end
  if percent >= self.db.DangerStart then
    return self.STATE_DANGER
  end
  if percent > self.db.RisingStart then
    return self.STATE_RISING
  end
  return self.STATE_SAFE
end

function GT:MaybePlayDangerSound(previousPercent, currentPercent)
  if not self.db then
    return
  end
  if self.db.enableSound ~= true then
    return
  end
  local prev = tonumber(previousPercent)
  local curr = tonumber(currentPercent)
  if type(prev) ~= "number" or type(curr) ~= "number" then
    return
  end
  local threshold = tonumber(self.db.DangerStart) or self.DEFAULTS.DangerStart
  if not (prev < threshold and curr >= threshold) then
    return
  end
  local now = GetTime()
  if self.lastAlertAt > 0 and (now - self.lastAlertAt) < self.db.alertCooldownSeconds then
    return
  end

  local played = false
  local function didPlay(result1, result2)
    if result1 == true then
      return true
    end
    if type(result2) == "number" then
      return true
    end
    return false
  end
  if type(PlaySound) == "function" then
    local ok, result1, result2 = pcall(PlaySound, 544959, "Master")
    played = ok and didPlay(result1, result2)
  end
  if not played and type(PlaySoundFile) == "function" then
    local soundPaths = {
      "sound/creature/bear/mbearattackb.ogg",
      "Sound\\Creature\\Bear\\MBearAttackB.ogg",
      "Sound/Creature/Bear/MBearAttackB.ogg",
      "sound/creature/bear/mbearaggroa.ogg",
      "Sound\\Creature\\Bear\\MBearAggroA.ogg",
      "Sound/Creature/Bear/MBearAggroA.ogg",
    }
    for _, path in ipairs(soundPaths) do
      local ok, result1, result2 = pcall(PlaySoundFile, path, "Master")
      if ok and didPlay(result1, result2) then
        played = true
        break
      end
    end
  end

  if played then
    self.lastAlertAt = now
  end
end

function GT:GetBlinkAlpha(state)
  if state ~= self.STATE_AGGRO or not self.db.enableAggroBlink then
    return 1
  end
  local t = GetTime()
  local pulse = (math.sin(t * 10) + 1) * 0.5
  return 0.45 + (pulse * 0.55)
end

function GT:GetVisualAlpha(state)
  local alpha = self:GetBlinkAlpha(state)
  if not self.db then
    return alpha
  end
  if self.db.enableCombatFade and not self.testMode and not UnitAffectingCombat("player") then
    alpha = alpha * ((tonumber(self.db.outOfCombatAlpha) or 100) / 100)
  end
  if self.db.enableLowNoise and not self.testMode and (state == self.STATE_SAFE or state == self.STATE_RISING) then
    alpha = alpha * ((tonumber(self.db.lowNoiseAlpha) or 100) / 100)
  end
  return clamp(alpha, 0.05, 1)
end

function GT:SetState(newState, percent, threatValue)
  local previousPercent = self.lastPercent
  self.state = newState
  self.lastPercent = percent
  if type(threatValue) == "number" then
    self.lastThreatValue = threatValue
  elseif percent == 0 then
    self.lastThreatValue = nil
  end
  self:MaybePlayDangerSound(previousPercent, percent)

  local alpha = self:GetVisualAlpha(newState)
  self:UpdateThreatUI(newState, percent, alpha, threatValue or self.lastThreatValue)
end

function GT:Tick()
  if not self.db then
    return
  end

  if self.stylePreviewActive then
    return
  end

  if self.uiUnavailable then
    return
  end

  if self.testSequence then
    self:AdvanceTestSequence()
  end

  if not self:ShouldDisplay() then
    self.state = self.STATE_SAFE
    self.lastPercent = nil
    self:UpdateThreatUI(self.STATE_SAFE, nil, 1)
    return
  end

  if self.testMode then
    local percent = self.testMode.percent
    local state = self:ResolveTestState(percent)
    self:SetState(state, percent, nil)
    return
  end

  local currentTargetGUID = UnitGUID and UnitGUID("target")
  if currentTargetGUID ~= self.lastTargetGUID then
    self.lastTargetGUID = currentTargetGUID
    self.lastPercent = nil
    self.lastThreatValue = nil
  end

  local hasTarget = UnitExists and UnitExists("target")
  local targetFriendly = hasTarget and UnitIsFriend and UnitIsFriend("player", "target")
  local targetAttackable = hasTarget and UnitCanAttack and UnitCanAttack("player", "target")
  if (not hasTarget) or targetFriendly or (not targetAttackable) then
    if not hasTarget then
      self.lastTargetGUID = nil
    end
    self:SetState(self.STATE_SAFE, 0, nil)
    return
  end

  if not self.threatEnabled then
    self:SetState(self.STATE_SAFE, 0, nil)
    return
  end

  local percent, hasAggro, threatValue = self:GetThreatData()
  if percent == nil then
    self:SetState(self.STATE_SAFE, 0, nil)
    return
  end

  local nextState = self:ResolveState(percent, hasAggro)
  self:SetState(nextState, percent, threatValue)
end

function GT:RefreshNow()
  self.elapsed = self.THROTTLE_SECONDS
  self:Tick()
end

function GT:SetTestMode(stateName)
  if not stateName then
    self.testSequence = nil
    self.testMode = nil
    self:Print("Test mode disabled.")
    self:RefreshNow()
    return
  end

  local lookup = {
    rising = { percent = self.db.RisingStart },
    danger = { percent = self.db.DangerStart },
    aggro = { percent = 100 },
  }
  local entry = lookup[string.lower(stateName)]
  if not entry then
    self:Print("Usage: /gt test [rising|danger|aggro|off]")
    return
  end

  self.testSequence = nil
  self.testMode = entry
  self:Print("Test mode: " .. string.upper(stateName))
  self:RefreshNow()
end

function GT:StartTestSequence()
  local startPercent = clamp(tonumber(self.db and self.db.RisingStart) or self.DEFAULTS.RisingStart, 0, 99)
  local dangerThreshold = tonumber(self.db and self.db.DangerStart) or self.DEFAULTS.DangerStart
  self.lastAlertAt = 0
  self.lastPercent = math.min(startPercent, dangerThreshold - 1)
  self.testSequence = {
    startedAt = GetTime(),
    duration = 6.0,
    startPercent = startPercent,
    endPercent = 100,
  }
  self.testMode = { percent = startPercent }
  self:Print("Test sequence: Dynamic simulation to 100%.")
  self:RefreshNow()
end

function GT:AdvanceTestSequence()
  local seq = self.testSequence
  if not seq then
    return
  end

  local now = GetTime()
  local elapsed = now - (seq.startedAt or now)
  local duration = seq.duration or 6.0
  local progress = duration > 0 and clamp(elapsed / duration, 0, 1) or 1
  local startPercent = tonumber(seq.startPercent) or 0
  local endPercent = tonumber(seq.endPercent) or 100
  local percent = startPercent + ((endPercent - startPercent) * progress)
  percent = clamp(math.floor(percent + 0.5), 0, 100)

  if self.testMode then
    self.testMode.percent = percent
  end

  if progress >= 1 then
    self.testSequence = nil
    self.testMode = nil
    self.state = self.STATE_SAFE
    self:UpdateThreatUI(self.STATE_SAFE, nil, 1)
    self:Print("Test sequence complete.")
  end
end

function GT:CycleTestMode()
  self:StartTestSequence()
end

function GT:HandleSlash(args)
  local cmd, rest = args:match("^(%S+)%s*(.-)$")
  cmd = cmd and string.lower(cmd) or ""
  rest = rest or ""

  if cmd == "" then
    self:ToggleOptions()
    return
  end

  if cmd == "reset" then
    self:ResetDB()
    self:Print("Settings reset to defaults.")
    return
  end

  if cmd == "test" then
    local mode = rest and string.lower(rest) or ""
    if mode == "" then
      self:StartTestSequence()
    elseif mode == "off" then
      self:SetTestMode(nil)
    else
      self:SetTestMode(mode)
    end
    return
  end

  if cmd == "help" then
    self:Print("Commands: /gt (open options), /gt test, /gt reset")
    self:Print("Use the 'Lock bar' checkbox in options to move/resize the bar.")
    self:Print("/gt reset restores all settings to defaults.")
    return
  end

  self:Print("Unknown command. Use /gt help")
end

GT.eventFrame = CreateFrame("Frame")
GT.eventFrame:RegisterEvent("ADDON_LOADED")
GT.eventFrame:RegisterEvent("PLAYER_LOGIN")
GT.eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
GT.eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
GT.eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
GT.eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
GT.eventFrame:RegisterEvent("RAID_ROSTER_UPDATE")
GT.eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
GT.eventFrame:RegisterEvent("UNIT_THREAT_LIST_UPDATE")
GT.eventFrame:RegisterEvent("UNIT_THREAT_SITUATION_UPDATE")

GT.eventFrame:SetScript("OnEvent", function(_, event, ...)
  if event == "ADDON_LOADED" then
    local addon = ...
    if addon == GT.ADDON_NAME then
      GT:EnsureDB()
    end
    return
  end

  if event == "PLAYER_LOGIN" then
    GT:TryLoadThreatLibrary()
    if GT.InitUI then
      GT:InitUI()
    end
    if GT.InitOptions then
      GT:InitOptions()
    end
    GT:RefreshNow()
    return
  end

  if event == "UNIT_THREAT_LIST_UPDATE" or event == "UNIT_THREAT_SITUATION_UPDATE" then
    local unit = ...
    if unit == "player" or unit == "pet" or unit == "target" or unit == "targettarget" then
      GT:Tick()
      return
    end
  end

  GT:RefreshNow()
end)

GT.eventFrame:SetScript("OnUpdate", function(_, elapsed)
  GT.elapsed = GT.elapsed + elapsed
  if GT.elapsed < GT.THROTTLE_SECONDS then
    if (not GT.stylePreviewActive) and GT.state == GT.STATE_AGGRO and GT.db and GT.db.enableAggroBlink and GT.UpdateThreatUI then
      local alpha = GT:GetVisualAlpha(GT.state)
      GT:UpdateThreatUI(GT.state, GT.lastPercent, alpha, GT.lastThreatValue)
    end
    return
  end
  GT.elapsed = 0
  GT:Tick()
end)
