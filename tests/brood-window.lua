-- Run from the addon directory: lua tests/brood-window.lua
-- WoW supplies frames/audio/timers; exercise the real addon at those boundaries.
local function World()
    local w = { now = 0, difficulty = 16, instance = 3004, frames = {}, timers = {}, bw = {}, dbm = {} }
    local env = setmetatable({}, { __index = _G })
    local Frame = {}; Frame.__index = Frame
    local function noop() end
    for _, name in ipairs({ "SetPoint", "ClearAllPoints", "SetAllPoints", "SetColorTexture", "SetTexCoord", "SetTexture", "SetText", "SetFrameStrata", "SetClampedToScreen", "EnableMouse", "SetWidthPadding" }) do Frame[name] = noop end
    function Frame:SetSize(width, height) self.width, self.height = width, height end
    function Frame:SetShown(shown) self.shown = shown end
    function Frame:Hide() self.shown = false end
    function Frame:SetScript(name, fn) self[name] = fn end
    function Frame:RegisterEvent(event) self.events[event] = true end
    Frame.RegisterUnitEvent = Frame.RegisterEvent
    function Frame:UnregisterEvent(event) self.events[event] = nil end
    function Frame:UnregisterAllEvents() self.events = {} end
    function env.CreateFrame()
        local frame = setmetatable({ events = {} }, Frame)
        w.frames[#w.frames + 1] = frame
        return frame
    end
    Frame.CreateTexture = env.CreateFrame; Frame.CreateFontString = env.CreateFrame
    env.UIParent = env.CreateFrame()
    env.GetTime = function() return w.now end
    env.issecretvalue = function(value) return value == w.secret end
    w.secret = {}
    env.GetInstanceInfo = function() return "", "raid", w.difficulty, "", 0, 0, false, w.instance end
    env.C_InstanceEncounter = { IsEncounterInProgress = function() return w.encounter end }
    env.C_Spell = { GetSpellTexture = function() return 1766 end, GetSpellName = function() return "Kick" end }
    env.SOUNDKIT = {}; env.SlashCmdList = {}; env.DEFAULT_CHAT_FRAME = { AddMessage = noop }
    env.LibStub = function(name) if name == "LibCustomGlow-1.0" then return { glowList = {}, startList = {} } end end
    env.C_Timer = { NewTimer = function(delay, fn)
        local timer = { at = w.now + delay, fn = fn }
        function timer:Cancel() self.cancelled = true end
        w.timers[#w.timers + 1] = timer
        return timer
    end }
    env.BigWigsLoader = {
        RegisterMessage = function(owner, event, fn) w.bw[event] = { owner, fn } end,
        UnregisterMessage = function(owner, event) if w.bw[event] and w.bw[event][1] == owner then w.bw[event] = nil end end,
    }
    env.DBM = {
        RegisterCallback = function(_, event, fn) w.dbm[event] = fn end,
        UnregisterCallback = function(_, event, fn) if w.dbm[event] == fn then w.dbm[event] = nil end end,
    }
    local lem = { SettingType = { Checkbox = 2, Dropdown = 0, Slider = 1 }, internal = { dialog = env.CreateFrame() }, callbacks = {}, layout = "Raid" }
    function lem:GetActiveLayoutName() return self.layout end
    function lem:AddFrame() end
    function lem:AddFrameSettings(_, entries) w.controls = {}; for _, entry in ipairs(entries) do w.controls[entry.name] = entry end end
    function lem:AddFrameSettingsButtons() end
    function lem:RegisterCallback(event, fn) self.callbacks[event] = fn; if event == "layout" then fn(self.layout) end end
    function lem:IsInEditMode() return false end
    local ns = { LibEditMode = lem, GetInterruptSpellID = function() return 1766 end, IsInterruptCast = function(unit, spell) return unit == "player" and spell == 1766 end }
    env.WhisperTriggerDB = { layouts = { Raid = { enabled = true, sound = "None", glowStyle = "None", timeout = 10, size = 72, x = 0, y = 100 } } }
    local function load(path) local chunk = assert(loadfile(path)); setfenv(chunk, env); chunk("WhisperTrigger", ns) end
    load("BroodWindow.lua")
    load("Core.lua"); load("EditMode.lua")
    function w:fire(event, ...)
        local frames = {}; for _, frame in ipairs(self.frames) do frames[#frames + 1] = frame end
        for _, frame in ipairs(frames) do if frame.events[event] and frame.OnEvent then frame.OnEvent(frame, event, ...) end end
    end
    function w:advance(seconds)
        local target = self.now + seconds
        while true do
            local nextTimer
            for _, timer in ipairs(self.timers) do
                if not timer.cancelled and not timer.fired and timer.at <= target and (not nextTimer or timer.at < nextTimer.at) then nextTimer = timer end
            end
            if not nextTimer then break end
            self.now = nextTimer.at; nextTimer.fired = true; nextTimer.fn()
        end
        self.now = target
    end
    function w:begin(difficulty, encounter)
        self.difficulty = difficulty or 16; self.encounter = true
        self:fire("PLAYER_ENTERING_WORLD")
        self:fire("ENCOUNTER_START", encounter or 3421, "Twin Fangs", self.difficulty, 20)
    end
    function w:message(provider, event, ...)
        if provider == "BigWigs" then local cb = self.bw[event]; if cb then cb[2](event, ...) end
        elseif self.dbm[event] then self.dbm[event](event, ...) end
    end
    w.module = { GetEncounterID = function() return 3421 end }
    function w:start(provider, seconds, id)
        id = id or "rouse"
        if provider == "BigWigs" then self:message(provider, "BigWigs_Timer", self.module, 1308356, seconds, nil, id)
        else self:message(provider, "DBM_TimerBegin", id, "Rouse", seconds, nil, "cd", 1308356, 1, "2887") end
    end
    function w:stop(provider, id)
        if provider == "BigWigs" then self:message(provider, "BigWigs_StopBar", self.module, id or "rouse")
        else self:message(provider, "DBM_TimerStop", id or "rouse") end
    end
    function w:whisper(expected, message)
        self:fire("CHAT_MSG_WHISPER", self.secret, self.secret)
        assert(not not ns.GetAlertFrame().shown == expected, message)
        self:fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast", 1766)
    end
    w.ns, w.env, w.lem = ns, env, lem
    return w
end

for _, difficulty in ipairs({ 14, 15, 17 }) do
    local w = World(); w:begin(difficulty); w:start("BigWigs", 5)
    w:whisper(false, "Non-Mythic encounters must not accept whispers")
end
for _, provider in ipairs({ "BigWigs", "DBM" }) do
    local w = World(); w:begin(); w:whisper(false, "Wait for a mechanic timer")
    w:start(provider, 20); w:advance(14.9); w:whisper(false, "Do not open before the five-second lead-in")
    w:advance(0.1); w:whisper(true, "Open exactly five seconds before Rouse")
    w:advance(5); w:stop(provider); w:advance(44.9); w:whisper(true, "Countdown completion must preserve the post-Rouse window")
    w:fire("CHAT_MSG_WHISPER"); w:advance(0.1)
    assert(not w.ns.GetAlertFrame().shown, "Closing the mechanic window must dismiss a pending alert")
    w:whisper(false, "Close exactly 45 seconds after Rouse")
    w:start(provider, 20); w:advance(16); w:stop(provider); w:advance(0)
    w:whisper(false, "Canceling a future Rouse closes its lead-in")
    w:advance(60); w:whisper(false, "Canceled callbacks must not reopen the window")
    print("PASS: " .. provider .. " lead-in, post-start duration, cancellation, and alert cleanup")
end
local w = World(); w:begin(); w:start("DBM", 20); w:advance(10)
w:message("DBM", "DBM_TimerPause", "rouse"); w:advance(30); w:whisper(false, "Paused timers must not activate")
w:message("DBM", "DBM_TimerResume", "rouse"); w:advance(5); w:whisper(true, "Resuming preserves remaining countdown")
w:message("DBM", "DBM_TimerUpdate", "rouse", 0, 30); w:whisper(false, "A timer correction can move the lead-in later")
w:advance(25); w:whisper(true, "Corrected countdown reopens at the new boundary")
w.controls["Brood window"].set("Raid", 15, false); w:advance(20); w:whisper(false, "Configured duration replaces the default")
w.lem.layout = "Other"; w.lem.callbacks.layout("Other"); w.controls["Brood window"].set("Other", 60, false)
w.lem.layout = "Raid"; w.lem.callbacks.layout("Raid")
assert(w.ns.GetSettings().broodDuration == 15, "Duration follows Edit Mode layouts")
print("PASS: pause/resume, corrected timers, configurable duration, and layout persistence")
w = World(); w:begin(); w:start("BigWigs", 5); w:advance(5)
w:start("BigWigs", 61, "next"); w:advance(10); w:whisper(true, "A future countdown must not close the current wave")
w:start("DBM", 5); w:advance(35); w:whisper(false, "A second provider must not extend the chosen provider's window")
w:advance(11); w:whisper(true, "The following Rouse opens its own window")
w:fire("ENCOUNTER_END", 3421); w.encounter = false; w:advance(100); w:whisper(false, "Encounter end clears all windows")
for _, timer in ipairs(w.timers) do assert(timer.fired or timer.cancelled, "No pending timers may survive encounter end") end
assert(next(w.bw) == nil and next(w.dbm) == nil, "Boss callbacks must detach after the encounter")
print("PASS: overlapping waves, provider deduplication, and encounter teardown")
w = World(); w:begin(16, 9999); w:start("BigWigs", 5); w:whisper(false, "Other encounters stay inactive")
w.env.SlashCmdList.WHISPERTRIGGER("test on"); w:whisper(true, "Test mode bypasses encounter and mechanic restrictions")
w.ns.GetSettings().enabled = false; w.ns.ApplySettings(); w:whisper(false, "Enable toggle still applies in test mode")
print("PASS: Mythic-only scope, unrelated encounters, and test-mode precedence")
w = World(); w:begin()
local timeline = { state = 0, remaining = 20 }
w.env.C_EncounterTimeline = {
    GetEventState = function() return timeline.state end,
    GetEventTimeRemaining = function() return timeline.remaining end,
}
w:message("BigWigs", "BigWigs_StartBar", w.module, 1308356, "rouse", 20, nil, true, nil, nil, 101)
w:start("BigWigs", 20)
w:advance(10); timeline.state, timeline.remaining = 1, 10
w:fire("ENCOUNTER_TIMELINE_EVENT_STATE_CHANGED", 101)
w:advance(30); w:whisper(false, "Native paused BigWigs timelines must not activate")
timeline.state = 0; w:fire("ENCOUNTER_TIMELINE_EVENT_STATE_CHANGED", 101)
w:advance(5); w:whisper(true, "Native timeline resume restores the lead-in")
w:fire("CHAT_MSG_WHISPER"); w:advance(4.75)
timeline.state = 2; w:stop("BigWigs")
w:fire("ENCOUNTER_TIMELINE_EVENT_STATE_CHANGED", 101)
assert(w.ns.GetAlertFrame().shown, "Native completion must not dismiss an existing alert when the estimate was slightly late")
w:advance(45); w:whisper(false, "The actual native completion anchors the post-Rouse cutoff")
print("PASS: native BigWigs pause/resume and early countdown completion")
w = World()
local loader = w.env.BigWigsLoader
w.env.BigWigsLoader, w.env.DBM = nil, nil
w:begin(); w:advance(60); w:whisper(false, "Missing boss mods must not fall back to the whole encounter")
w.env.BigWigsLoader = loader; w:fire("ADDON_LOADED", "BigWigs")
w:message("BigWigs", "BigWigs_Timer", w.module, 9999, 5, nil, "unrelated")
w:start("BigWigs", w.secret)
w:whisper(false, "Unrelated abilities and secret timing values must not activate")
w:start("BigWigs", 5); w:whisper(true, "A boss mod loaded mid-encounter can supply timers")
w.ns.GetSettings().enabled = false; w.ns.ApplySettings()
w:whisper(false, "Disabling during a mechanic suppresses whispers")
w:advance(10); w.ns.GetSettings().enabled = true; w.ns.ApplySettings()
w:whisper(true, "Re-enabling preserves the current mechanic window")
w.instance = 0; w:fire("ZONE_CHANGED_NEW_AREA"); w:advance(100)
w:whisper(false, "Leaving the raid clears the mechanic window")
print("PASS: missing/late providers, invalid timing signals, enable transitions, and leaving the raid")
