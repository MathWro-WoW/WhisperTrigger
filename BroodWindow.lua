local _, ns = ...
local ENCOUNTER_ID, DBM_MOD_ID, BROOD_SPELL_ID = 3421, 2887, 1308356
local LEAD_TIME = 5
local events = CreateFrame("Frame")
local tracking, windowOpen = false, false
local duration = 45
local source, boundaryTimer, bigWigs, dbm
local countdowns = {}

local function IsDuration(value)
    return not issecretvalue(value) and type(value) == "number"
        and value == value and value >= 0 and value < math.huge
end

local function IsID(value, expected)
    return not issecretvalue(value) and (value == expected or (type(value) == "string" and tonumber(value) == expected))
end

local function IsBoss(module)
    return type(module) == "table" and module.GetEncounterID and module:GetEncounterID() == ENCOUNTER_ID
end

local function CancelBoundary()
    if boundaryTimer then boundaryTimer:Cancel(); boundaryTimer = nil end
end

local function RefreshWindow()
    CancelBoundary()
    local now, nextBoundary, open = GetTime(), nil, false
    for id, timer in pairs(countdowns) do
        if not timer.remaining then
            local opens, closes = timer.due - LEAD_TIME, timer.due + duration
            if now >= closes then
                countdowns[id] = nil
            else
                local boundary = opens
                if now >= opens then open, boundary = true, closes end
                if not nextBoundary or boundary < nextBoundary then nextBoundary = boundary end
            end
        end
    end
    if nextBoundary then boundaryTimer = C_Timer.NewTimer(nextBoundary - now, RefreshWindow) end
    if open ~= windowOpen then
        windowOpen = open
        ns.ApplySettings()
    end
end

local function Start(provider, id, seconds)
    if not tracking or (source and source ~= provider) or issecretvalue(id)
        or type(id) ~= "string" or not IsDuration(seconds) then return end
    -- The first provider with a matching timer owns this pull, avoiding duplicate windows.
    source = provider
    countdowns[id] = { due = GetTime() + seconds }
    RefreshWindow()
end

local function GetTimer(provider, id)
    if not tracking or source ~= provider or issecretvalue(id) then return end
    return countdowns[id]
end

local function Stop(provider, id)
    local timer = GetTimer(provider, id)
    if not timer or timer.eventID then return end -- Native timeline state owns its cancellation/completion.
    -- At expiry, a stopped bar means the countdown ended, not that the brood is gone.
    if timer.remaining or timer.due > GetTime() then countdowns[id] = nil end
    RefreshWindow()
end

local function Pause(provider, id)
    local timer = GetTimer(provider, id)
    if timer and not timer.remaining then
        timer.remaining = math.max(0, timer.due - GetTime())
        RefreshWindow()
    end
end

local function Resume(provider, id)
    local timer = GetTimer(provider, id)
    if timer and timer.remaining then
        timer.due, timer.remaining = GetTime() + timer.remaining, nil
        RefreshWindow()
    end
end

local function ClearWindows()
    for id in pairs(countdowns) do countdowns[id] = nil end
    source = nil
end

local function StopBigWigs(_, module)
    if source == "BigWigs" and IsBoss(module) then ClearWindows(); RefreshWindow() end
end

local function UpdateTimeline(eventID, removed)
    if source ~= "BigWigs" or issecretvalue(eventID) then return end
    for id, timer in pairs(countdowns) do
        if timer.eventID == eventID then
            if removed then
                timer.eventID = nil
                Stop("BigWigs", id)
                return
            end
            local state = C_EncounterTimeline.GetEventState(eventID)
            if state == 2 then -- Finished: the mechanic starts now.
                timer.due, timer.remaining, timer.eventID = GetTime(), nil, nil
            elseif state == 3 then -- Canceled
                countdowns[id] = nil
            else
                local remaining = C_EncounterTimeline.GetEventTimeRemaining(eventID)
                if not IsDuration(remaining) then return end
                timer.due = GetTime() + remaining
                timer.remaining = state == 1 and remaining or nil
            end
            RefreshWindow()
            return
        end
    end
end

local bigWigsCallbacks = {
    BigWigs_StartBar = function(_, module, key, text, seconds, _, _, _, eventID, customEventID)
        if not IsID(key, BROOD_SPELL_ID) or not IsBoss(module) then return end
        -- Custom BigWigs bars carry their native event ID in the indicator slot.
        local timelineID = customEventID or eventID
        if not IsDuration(timelineID) or timelineID <= 0 then return end
        Start("BigWigs", text, seconds)
        local timer = GetTimer("BigWigs", text)
        if timer then
            timer.eventID = timelineID
            UpdateTimeline(timelineID)
        end
    end,
    BigWigs_Timer = function(_, module, key, seconds, _, text)
        local timer = GetTimer("BigWigs", text)
        if timer and timer.eventID then return end -- Already using the authoritative timeline clock.
        if IsID(key, BROOD_SPELL_ID) and IsBoss(module) then Start("BigWigs", text, seconds) end
    end,
    BigWigs_StopBar = function(_, module, text)
        if IsBoss(module) then Stop("BigWigs", text) end
    end,
    BigWigs_PauseBar = function(_, module, text)
        if IsBoss(module) then Pause("BigWigs", text) end
    end,
    BigWigs_ResumeBar = function(_, module, text)
        if IsBoss(module) then Resume("BigWigs", text) end
    end,
    BigWigs_StopBars = StopBigWigs,
    BigWigs_OnBossDisable = StopBigWigs,
    BigWigs_OnBossWipe = StopBigWigs,
}

local dbmCallbacks = {
    DBM_TimerBegin = function(_, id, _, seconds, _, timerType, spellID, _, modID)
        if IsID(spellID, BROOD_SPELL_ID) and IsID(modID, DBM_MOD_ID)
            and not issecretvalue(timerType) and timerType == "cd" then Start("DBM", id, seconds) end
    end,
    DBM_TimerStop = function(_, id) Stop("DBM", id) end,
    DBM_TimerPause = function(_, id) Pause("DBM", id) end,
    DBM_TimerResume = function(_, id) Resume("DBM", id) end,
    DBM_TimerUpdate = function(_, id, elapsed, total)
        local timer = GetTimer("DBM", id)
        if timer and IsDuration(elapsed) and IsDuration(total) then
            local remaining = math.max(0, total - elapsed)
            timer.due = GetTime() + remaining
            if timer.remaining then timer.remaining = remaining end
            RefreshWindow()
        end
    end,
}

local function Connect()
    if not bigWigs and BigWigsLoader then
        bigWigs = BigWigsLoader
        for event, callback in pairs(bigWigsCallbacks) do bigWigs.RegisterMessage(events, event, callback) end
    end
    if not dbm and DBM and DBM.RegisterCallback then
        dbm = DBM
        for event, callback in pairs(dbmCallbacks) do dbm:RegisterCallback(event, callback) end
    end
    if bigWigs and dbm then events:UnregisterEvent("ADDON_LOADED") end
end

events:SetScript("OnEvent", function(_, event, eventID)
    if event == "ADDON_LOADED" then Connect()
    else UpdateTimeline(eventID, event == "ENCOUNTER_TIMELINE_EVENT_REMOVED") end
end)

function ns.UpdateBroodWindow(active, seconds)
    if active == tracking and seconds == duration then return end
    local changed = active ~= tracking
    tracking, duration = active, seconds
    if not tracking then
        CancelBoundary()
        ClearWindows()
        windowOpen = false
        events:UnregisterAllEvents()
        if bigWigs then
            for event in pairs(bigWigsCallbacks) do bigWigs.UnregisterMessage(events, event) end
            bigWigs = nil
        end
        if dbm then
            for event, callback in pairs(dbmCallbacks) do dbm:UnregisterCallback(event, callback) end
            dbm = nil
        end
    else
        if changed then
            events:RegisterEvent("ADDON_LOADED")
            events:RegisterEvent("ENCOUNTER_TIMELINE_EVENT_STATE_CHANGED")
            events:RegisterEvent("ENCOUNTER_TIMELINE_EVENT_REMOVED")
            Connect()
        end
        RefreshWindow()
    end
end

function ns.IsBroodWindowOpen()
    return windowOpen
end
