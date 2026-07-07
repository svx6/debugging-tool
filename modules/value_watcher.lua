--[[
    ========================================================================
    ULTIMATE ROBLOX AUTO-DEBUGGER  ·  VALUE WATCHER  (v8)
    ========================================================================
    Watch any Instance property or Attribute for changes in real-time.
    Features:
      · Watch arbitrary properties (Position, Health, Enabled, Value…)
      · Watch Attributes on any instance
      · Configurable alert thresholds (min/max bounds)
      · Change log with timestamps + old/new values
      · One-click add from GUI (enter path + property name)
      · Auto-remove dead watchers when instance is destroyed
      · Signal-based (GetPropertyChangedSignal) for zero polling cost
    ========================================================================
--]]

local Data = getgenv().DebuggerSharedData
if not Data then warn("[ValueWatcher v8]: Core not loaded.") return end

local _orig_pcall    = pcall
local _orig_tostring = tostring

-- ── State ─────────────────────────────────────────────────────────────────
Data.ValueWatcher = Data.ValueWatcher or {
    Watchers   = {},  -- { id, instance, prop, lastValue, connection, log }
    ChangeLog  = {},  -- newest first, max 200
    WatchCount = 0,
    NextId     = 1,
}
local VW = Data.ValueWatcher

-- ── Helpers ───────────────────────────────────────────────────────────────
local function safeRead(inst, prop)
    local ok, val = _orig_pcall(function() return inst[prop] end)
    return ok, val
end

local function valToStr(v)
    local t = type(v)
    if t == "number"  then return string.format("%.4g", v) end
    if t == "boolean" then return tostring(v) end
    if t == "string"  then return '"' .. v:sub(1, 60) .. '"' end
    if t == "nil"     then return "nil" end
    return _orig_tostring(v):sub(1, 80)
end

local function logChange(watcher, oldVal, newVal)
    local entry = {
        Time     = os.date("%H:%M:%S"),
        Id       = watcher.id,
        Path     = watcher.path,
        Property = watcher.prop,
        Old      = valToStr(oldVal),
        New      = valToStr(newVal),
    }
    table.insert(VW.ChangeLog, 1, entry)
    while #VW.ChangeLog > 200 do table.remove(VW.ChangeLog) end
    table.insert(watcher.log, 1, entry)
    while #watcher.log > 20 do table.remove(watcher.log) end

    _orig_pcall(function() Data:Publish("OnValueChanged", entry) end)
    _orig_pcall(function()
        Data:ReportLog({
            Type = "Info",
            Text = string.format("[ValueWatcher] %s.%s: %s → %s", watcher.path, watcher.prop, entry.Old, entry.New),
        })
    end)

    -- Threshold alerts
    if watcher.min ~= nil or watcher.max ~= nil then
        local n = tonumber(newVal)
        if n then
            if watcher.min and n < watcher.min then
                _orig_pcall(function()
                    Data:ReportBug({
                        Type = "Value Watcher: Below Minimum",
                        Source = watcher.path .. "." .. watcher.prop,
                        Description = string.format("%s.%s = %s is below min threshold %s",
                            watcher.path, watcher.prop, entry.New, valToStr(watcher.min)),
                        Severity = "Medium",
                    })
                end)
            end
            if watcher.max and n > watcher.max then
                _orig_pcall(function()
                    Data:ReportBug({
                        Type = "Value Watcher: Above Maximum",
                        Source = watcher.path .. "." .. watcher.prop,
                        Description = string.format("%s.%s = %s exceeds max threshold %s",
                            watcher.path, watcher.prop, entry.New, valToStr(watcher.max)),
                        Severity = "Medium",
                    })
                end)
            end
        end
    end
end

-- ── Add a watcher ─────────────────────────────────────────────────────────
Data.ValueWatcher.Watch = function(inst, prop, options)
    -- inst: Instance or full path string
    -- prop: property name string, or "__ATTRIBUTE:AttrName" for attributes
    -- options: { min, max, label }

    options = options or {}

    -- Resolve string path to instance
    if type(inst) == "string" then
        local ok, resolved = _orig_pcall(function()
            local obj = game
            for part in inst:gmatch("[^%.]+") do
                obj = obj:FindFirstChild(part) or obj[part]
            end
            return obj
        end)
        if not ok or type(resolved) ~= "userdata" then
            Data:ReportLog({Type="Warning", Text="[ValueWatcher] Cannot resolve path: " .. tostring(inst)})
            return nil
        end
        inst = resolved
    end

    local id = VW.NextId; VW.NextId = VW.NextId + 1
    local pathOk, pathStr = _orig_pcall(function() return inst:GetFullName() end)
    local path = pathOk and pathStr or _orig_tostring(inst)

    local watcher = {
        id         = id,
        instance   = inst,
        path       = path,
        prop       = prop,
        min        = options.min,
        max        = options.max,
        label      = options.label or (path .. "." .. prop),
        connection = nil,
        log        = {},
        active     = true,
    }

    -- Read initial value
    local initOk, initVal = safeRead(inst, prop)
    watcher.lastValue = initOk and initVal or nil

    -- Connect change signal
    local connOk = _orig_pcall(function()
        if prop:sub(1, 13) == "__ATTRIBUTE:" then
            local attrName = prop:sub(14)
            watcher.connection = inst:GetAttributeChangedSignal(attrName):Connect(function()
                local ok, newVal = _orig_pcall(function() return inst:GetAttribute(attrName) end)
                if ok then
                    logChange(watcher, watcher.lastValue, newVal)
                    watcher.lastValue = newVal
                end
            end)
        else
            watcher.connection = inst:GetPropertyChangedSignal(prop):Connect(function()
                local ok, newVal = safeRead(inst, prop)
                if ok then
                    logChange(watcher, watcher.lastValue, newVal)
                    watcher.lastValue = newVal
                end
            end)
        end
    end)

    if not connOk then
        Data:ReportLog({Type="Warning", Text="[ValueWatcher] Cannot watch " .. path .. "." .. prop .. " (property may not support change signals)"})
        return nil
    end

    -- Auto-remove when instance is destroyed
    _orig_pcall(function()
        inst.Destroying:Connect(function()
            watcher.active = false
            if watcher.connection then watcher.connection:Disconnect() end
            Data:ReportLog({Type="Info", Text="[ValueWatcher] Auto-removed watcher for destroyed instance: " .. path})
            Data:Publish("OnWatcherRemoved", watcher)
        end)
    end)

    table.insert(VW.Watchers, watcher)
    VW.WatchCount = VW.WatchCount + 1

    Data:ReportLog({Type="Info", Text=string.format("[ValueWatcher] Watching %s.%s (id=%d, value=%s)",
        path, prop, id, valToStr(watcher.lastValue))})
    _orig_pcall(function() Data:Publish("OnWatcherAdded", watcher) end)

    return id
end

-- ── Remove a watcher by ID ────────────────────────────────────────────────
Data.ValueWatcher.Unwatch = function(id)
    for i, w in ipairs(VW.Watchers) do
        if w.id == id then
            w.active = false
            if w.connection then _orig_pcall(function() w.connection:Disconnect() end) end
            table.remove(VW.Watchers, i)
            Data:ReportLog({Type="Info", Text="[ValueWatcher] Removed watcher id=" .. id})
            _orig_pcall(function() Data:Publish("OnWatcherRemoved", w) end)
            return true
        end
    end
    return false
end

-- ── Pre-built useful watchers ─────────────────────────────────────────────
task.spawn(function()
    task.wait(3)  -- Let everything settle first
    _orig_pcall(function()
        local Players = game:GetService("Players")
        local LP = Players.LocalPlayer
        if LP and LP.Character then
            local hum = LP.Character:FindFirstChildOfClass("Humanoid")
            if hum then
                -- Watch local player health
                Data.ValueWatcher.Watch(hum, "Health", {label = "LocalPlayer Health", min = 0})
                -- Watch walk speed
                Data.ValueWatcher.Watch(hum, "WalkSpeed", {label = "LocalPlayer WalkSpeed", max = 50})
            end
        end
    end)
end)

print("[ValueWatcher v8]: Property + Attribute watcher ready. GetPropertyChangedSignal-based (zero poll cost).")
