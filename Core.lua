local addonName, ns = ...

-- DungeonEncounterID, not the Encounter Journal's encounter ID (2887).
-- Verified against BigWigs_TheVenomousAbyss: TwinFangs.lua / its instance TOC.
local RAID_INSTANCE_ID, ENCOUNTER_ID = 3004, 3421
local events = CreateFrame("Frame")
local settings, alert
local inRaid, inEncounter, listening, pending, preview, testMode = false, false, false, false, false, false
local mythicRaid = false
local interruptID
local expiryTimer
local glowLibrary = LibStub("LibCustomGlow-1.0")
local activeGlow, glowSize

ns.glowOptions = { { value = "None", text = "None" } }
for _, style in ipairs(glowLibrary.glowList) do
    ns.glowOptions[#ns.glowOptions + 1] = { value = style, text = style }
end

ns.soundOptions = {
    { key = "None", label = "None" },
    { key = "RaidWarning", label = "Raid warning" },
    { key = "ReadyCheck", label = "Ready check" },
    { key = "Alarm", label = "Alarm" },
}

ns.soundChannelOptions = {
    { value = "Master", text = "Master" },
    { value = "SFX", text = "Effects (SFX)" },
    { value = "Music", text = "Music" },
    { value = "Ambience", text = "Ambience" },
    { value = "Dialog", text = "Dialog" },
}

function ns.NormalizeSoundChannel(channel)
    for _, option in ipairs(ns.soundChannelOptions) do
        if channel == option.value then return channel end
    end
    return "Master"
end

local function InitializeSettings()
    if settings then return end
    if type(WhisperTriggerDB) ~= "table" then WhisperTriggerDB = {} end
    settings = WhisperTriggerDB
    if type(settings.enabled) ~= "boolean" then settings.enabled = true end
    if settings.glowStyle == nil then
        settings.glowStyle = settings.glow == true and "Action Button Glow" or "None"
    end
    settings.glow = nil
    if settings.glowStyle ~= "None" and not glowLibrary.startList[settings.glowStyle] then
        settings.glowStyle = "None"
    end
    -- Keep shared-media selections even if their provider is disabled this session.
    local validSound = type(settings.sound) == "string" and settings.sound:sub(1, 4) == "LSM:" and #settings.sound > 4
    for _, sound in ipairs(ns.soundOptions) do
        if settings.sound == sound.key then validSound = true; break end
    end
    if not validSound then settings.sound = "None" end
    settings.soundChannel = ns.NormalizeSoundChannel(settings.soundChannel)
    local function Number(value, default, minimum, maximum)
        if type(value) ~= "number" or value ~= value then return default end
        return math.max(minimum, math.min(maximum, value))
    end
    settings.size = Number(settings.size, 72, 32, 160)
    settings.timeout = Number(settings.timeout, 10, 1, 60)
    settings.broodDuration = Number(settings.broodDuration, 45, 5, 120)
    settings.x = Number(settings.x, 0, -10000, 10000)
    settings.y = Number(settings.y, 100, -10000, 10000)
end

function ns.GetSettings()
    InitializeSettings()
    return settings
end

local function UpdateAppearance()
    if not alert then return end
    alert:SetSize(settings.size, settings.size)
    alert:ClearAllPoints()
    alert:SetPoint("CENTER", UIParent, "CENTER", settings.x, settings.y)
    alert.Icon:SetTexture(interruptID and C_Spell.GetSpellTexture(interruptID) or 134400)
    alert.Label:SetText(preview and "WhisperTrigger" or "YOUR KICK")
    alert:SetShown(preview or pending)
    local style = (preview or pending) and settings.glowStyle or "None"
    if activeGlow and (style ~= activeGlow or glowSize ~= settings.size) then
        -- Hide the host first so Action Button Glow releases immediately, without a fade-out.
        alert.Glow:Hide()
        glowLibrary.stopList[activeGlow](alert.Glow)
        activeGlow = nil
    end
    if style ~= "None" and not activeGlow then
        if not alert.Glow then
            alert.Glow = CreateFrame("Frame", nil, alert)
            alert.Glow:SetAllPoints(alert)
            alert.Glow:EnableMouse(false)
        end
        alert.Glow:Show()
        glowLibrary.startList[style](alert.Glow)
        activeGlow, glowSize = style, settings.size
    end
end

function ns.GetAlertFrame()
    InitializeSettings()
    if not alert then
        alert = CreateFrame("Frame", "WhisperTriggerAlert", UIParent)
        alert:Hide()
        alert:SetFrameStrata("HIGH")
        alert:SetClampedToScreen(true)
        alert:EnableMouse(false)
        local border = alert:CreateTexture(nil, "BACKGROUND")
        border:SetAllPoints()
        border:SetColorTexture(1, 0.75, 0.15, 1)
        alert.Icon = alert:CreateTexture(nil, "ARTWORK")
        alert.Icon:SetPoint("TOPLEFT", alert, "TOPLEFT", 2, -2)
        alert.Icon:SetPoint("BOTTOMRIGHT", alert, "BOTTOMRIGHT", -2, 2)
        alert.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        alert.Label = alert:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        alert.Label:SetPoint("TOP", alert, "BOTTOM", 0, -6)
        UpdateAppearance()
    end
    return alert
end

local function Dismiss()
    if expiryTimer then
        expiryTimer:Cancel()
        expiryTimer = nil
    end
    pending = false
    events:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    UpdateAppearance()
end

function ns.PreviewSound()
    InitializeSettings()
    if settings.sound:sub(1, 4) == "LSM:" then
        local media = LibStub and LibStub("LibSharedMedia-3.0", true)
        local file = media and media:Fetch("sound", settings.sound:sub(5), true)
        if file and file ~= 1 then return PlaySoundFile(file, settings.soundChannel) end
        return
    end
    local soundID
    if settings.sound == "RaidWarning" then soundID = SOUNDKIT.RAID_WARNING
    elseif settings.sound == "ReadyCheck" then soundID = SOUNDKIT.READY_CHECK
    elseif settings.sound == "Alarm" then soundID = SOUNDKIT.ALARM_CLOCK_WARNING_3 end
    if soundID then
        -- Respect the selected channel's mute and volume settings.
        return PlaySound(soundID, settings.soundChannel)
    end
end

local function UpdateRuntime()
    local encounterScope = inRaid and mythicRaid and inEncounter
    -- Keep the boss countdown while disabled so re-enabling mid-wave still works.
    ns.UpdateBroodWindow(encounterScope, settings.broodDuration)
    local scoped = settings.enabled and (testMode or (encounterScope and ns.IsBroodWindowOpen()))
    if scoped then
        -- Spell and pet changes are only watched where alerts could actually run.
        events:RegisterEvent("SPELLS_CHANGED")
        events:RegisterUnitEvent("PLAYER_SPECIALIZATION_CHANGED", "player")
        events:RegisterUnitEvent("UNIT_PET", "player")
        interruptID = ns.GetInterruptSpellID()
    else
        events:UnregisterEvent("SPELLS_CHANGED")
        events:UnregisterEvent("PLAYER_SPECIALIZATION_CHANGED")
        events:UnregisterEvent("UNIT_PET")
    end
    listening = scoped and interruptID ~= nil
    if listening then
        events:RegisterEvent("CHAT_MSG_WHISPER")
    else
        events:UnregisterEvent("CHAT_MSG_WHISPER")
        Dismiss()
    end
    UpdateAppearance()
end

local function UpdateLocation()
    local _, instanceType, difficultyID, _, _, _, _, instanceID = GetInstanceInfo()
    inRaid = instanceType == "raid" and instanceID == RAID_INSTANCE_ID
    mythicRaid = difficultyID == 16
    if inRaid then
        -- Keep encounter boundaries even while disabled, so re-enabling mid-pull works.
        events:RegisterEvent("ENCOUNTER_START")
        events:RegisterEvent("ENCOUNTER_END")
        if not C_InstanceEncounter.IsEncounterInProgress() then inEncounter = false end
    else
        inEncounter = false
        events:UnregisterEvent("ENCOUNTER_START")
        events:UnregisterEvent("ENCOUNTER_END")
    end
    UpdateRuntime()
end

function ns.ApplySettings()
    InitializeSettings()
    UpdateLocation()
end

function ns.SetPreview(enabled)
    InitializeSettings()
    preview = not not enabled
    if preview then
        interruptID = ns.GetInterruptSpellID()
        ns.GetAlertFrame()
    end
    UpdateAppearance()
end

function ns.GetInterruptName()
    local spellID = ns.GetInterruptSpellID()
    return spellID and C_Spell.GetSpellName(spellID) or "No interrupt available for your current talents or pet"
end

function ns.GetStatus()
    InitializeSettings()
    if not settings.enabled then return "Disabled" end
    if not ns.GetInterruptSpellID() then return "Inactive: no interrupt available" end
    if testMode then return "TEST MODE: regular whispers trigger anywhere (until reload)" end
    if not inRaid then return "Inactive: outside The Venomous Abyss" end
    if not mythicRaid then return "Inactive: Mythic raid difficulty required" end
    if not inEncounter then return "Waiting for The Twin Fangs encounter to start" end
    if not ns.IsBroodWindowOpen() then return "Waiting for Rouse the Brood — BigWigs or DBM timers required" end
    return "Active: Mythic Twin Fangs — Rouse the Brood window"
end

local function Announce(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cffffc040WhisperTrigger:|r " .. message)
end

SLASH_WHISPERTRIGGER1 = "/wt"
SLASH_WHISPERTRIGGER2 = "/whispertrigger"
SlashCmdList.WHISPERTRIGGER = function(message)
    local command = message:lower():match("^%s*(.-)%s*$")
    if command == "test" or command == "test on" or command == "test off" then
        if command == "test" then testMode = not testMode
        else testMode = command == "test on" end
        Dismiss()
        ns.ApplySettings()
        Announce(testMode and "Encounter/difficulty/mechanic restrictions OFF for this session. The Enable setting still applies. Use /wt test off to restore them." or "Restrictions ON: Mythic Twin Fangs, around Rouse the Brood only.")
        Announce(ns.GetStatus())
    elseif command == "" or command == "status" then
        Announce(ns.GetStatus())
        Announce("Configure: Esc > Edit Mode > WhisperTrigger. /wt test toggles the scope restriction; /wt test on|off sets it explicitly.")
    else
        Announce("Commands: /wt status, /wt test, /wt test on, /wt test off. Configure through Esc > Edit Mode.")
    end
end

events:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        if ... ~= addonName then return end
        InitializeSettings()
        events:UnregisterEvent("ADDON_LOADED")
        return
    end
    InitializeSettings()
    if event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
        Dismiss()
        ns.UpdateBroodWindow(false, settings.broodDuration)
        UpdateLocation()
    elseif event == "ENCOUNTER_START" then
        local encounterID, _, difficultyID = ...
        Dismiss()
        ns.UpdateBroodWindow(false, settings.broodDuration)
        mythicRaid = difficultyID == 16
        inEncounter = encounterID == ENCOUNTER_ID
        UpdateRuntime()
    elseif event == "ENCOUNTER_END" then
        Dismiss()
        inEncounter = false
        UpdateRuntime()
    elseif event == "CHAT_MSG_WHISPER" then
        -- Intentionally ignore ALL payload fields: sender and text may be secret.
        if not listening or preview then return end
        Dismiss()
        pending = true
        ns.GetAlertFrame()
        UpdateAppearance()
        expiryTimer = C_Timer.NewTimer(settings.timeout, Dismiss)
        events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "pet")
        ns.PreviewSound()
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit, _, spellID = ...
        if pending and ns.IsInterruptCast(unit, spellID) then Dismiss() end
    else
        UpdateRuntime()
    end
end)
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("ZONE_CHANGED_NEW_AREA")
