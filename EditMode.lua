local addonName, ns = ...
local editMode = ns.LibEditMode
local settings = ns.GetSettings()
local alert = ns.GetAlertFrame()
local fields = { "enabled", "sound", "soundChannel", "glowStyle", "timeout", "broodDuration", "size", "x", "y" }

-- Match Falcon/AbilityTimeline: addon settings follow named Edit Mode layouts.
-- LibEditMode saves settings immediately; Blizzard layout export does not include addon data.
if type(settings.layouts) ~= "table" then settings.layouts = {} end
local layouts = settings.layouts

local function CopySettings(source)
    local copy = {}
    for _, key in ipairs(fields) do copy[key] = source[key] end
    return copy
end

local function GetLayout(name)
    name = name or editMode:GetActiveLayoutName()
    if not name then return end
    if type(layouts[name]) ~= "table" then layouts[name] = CopySettings(settings) end
    if layouts[name].broodDuration == nil then layouts[name].broodDuration = 45 end
    layouts[name].soundChannel = ns.NormalizeSoundChannel(layouts[name].soundChannel)
    return layouts[name]
end

local function SaveLayout()
    local layout = GetLayout()
    if layout then
        for _, key in ipairs(fields) do layout[key] = settings[key] end
    end
    ns.ApplySettings()
end

local function ApplyLayout(name)
    local layout = GetLayout(name)
    if layout then
        for _, key in ipairs(fields) do settings[key] = layout[key] end
        ns.ApplySettings()
    end
end

local function SoundOptions()
    local options = {}
    local selectedAvailable = false
    for _, sound in ipairs(ns.soundOptions) do
        options[#options + 1] = { value = sound.key, text = sound.label }
        if settings.sound == sound.key then selectedAvailable = true end
    end
    local media = LibStub("LibSharedMedia-3.0", true)
    if media then
        for _, name in ipairs(media:List("sound")) do
            if name ~= "None" then
                local key = "LSM:" .. name
                options[#options + 1] = { value = key, text = name }
                if settings.sound == key then selectedAvailable = true end
            end
        end
    end
    if not selectedAvailable then
        options[#options + 1] = { value = settings.sound, text = settings.sound:sub(5) .. " (unavailable)" }
    end
    return options
end

local function Setting(key, name, kind, default)
    return {
        name = name,
        kind = kind,
        default = default,
        get = function() return settings[key] end,
        set = function(_, value, fromReset)
            settings[key] = value
            SaveLayout()
            if (key == "sound" or key == "soundChannel") and not fromReset then ns.PreviewSound() end
        end,
    }
end

local enabled = Setting("enabled", "Enable whisper alerts", editMode.SettingType.Checkbox, true)
local sound = Setting("sound", "Alert sound", editMode.SettingType.Dropdown, "None")
sound.values = SoundOptions
sound.height = 300
sound.desc = "Includes shared sounds from enabled addons such as Northern Sky."
local channel = Setting("soundChannel", "Sound channel", editMode.SettingType.Dropdown, "Master")
channel.values = ns.soundChannelOptions
channel.desc = "Applies to alerts and previews. Master uses master volume; other channels also follow their own volume and mute settings."
local glow = Setting("glowStyle", "Glow style", editMode.SettingType.Dropdown, "None")
glow.values = ns.glowOptions
local size = Setting("size", "Icon size", editMode.SettingType.Slider, 72)
size.minValue, size.maxValue, size.valueStep = 32, 160, 1
size.formatter = function(value) return value .. " px" end
local timeout = Setting("timeout", "Timeout", editMode.SettingType.Slider, 10)
timeout.minValue, timeout.maxValue, timeout.valueStep = 1, 60, 1
timeout.formatter = function(value) return value .. " sec" end
timeout.desc = "Each whisper restarts the timeout. A successful interrupt cast clears the alert early."
local brood = Setting("broodDuration", "Brood window", editMode.SettingType.Slider, 45)
brood.minValue, brood.maxValue, brood.valueStep = 5, 120, 1
brood.formatter = function(value) return value .. " sec" end
brood.desc = "Accept whispers from 5 seconds before Rouse the Brood until this many seconds after its timer expires. Mythic Twin Fangs only; requires BigWigs or DBM mechanic timers. This is separate from the icon timeout."

editMode:AddFrame(alert, function(frame)
    local x, y = frame:GetCenter()
    local parentX, parentY = UIParent:GetCenter()
    settings.x, settings.y = x - parentX, y - parentY
    SaveLayout()
end, { point = "CENTER", x = 0, y = 100 }, "WhisperTrigger")
editMode.internal.dialog:SetWidthPadding(72)
editMode:AddFrameSettings(alert, { enabled, sound, channel, glow, size, timeout, brood })
editMode:AddFrameSettingsButtons(alert, {
    { text = "Preview sound", click = ns.PreviewSound },
    { text = "Show status", click = function()
        DEFAULT_CHAT_FRAME:AddMessage("WhisperTrigger: " .. ns.GetStatus() .. ". " .. ns.GetInterruptName())
    end },
})

editMode:RegisterCallback("layout", ApplyLayout)
editMode:RegisterCallback("create", function(name, _, sourceName)
    layouts[name] = CopySettings((sourceName and layouts[sourceName]) or settings)
    if name == editMode:GetActiveLayoutName() then ApplyLayout(name) end
end)
editMode:RegisterCallback("rename", function(oldName, newName)
    if layouts[oldName] then
        layouts[newName], layouts[oldName] = layouts[oldName], nil
    end
end)
editMode:RegisterCallback("delete", function(name) layouts[name] = nil end)
editMode:RegisterCallback("enter", function() ns.SetPreview(true) end)
editMode:RegisterCallback("exit", function() ns.SetPreview(false) end)
if editMode:IsInEditMode() then ns.SetPreview(true) end
