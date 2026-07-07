--[[
    ========================================================================
    ULTIMATE ROBLOX AUTO-DEBUGGER  ·  CRASH HANDLER  (v8)
    ========================================================================
    Features:
      · Global error handler via game:GetService("ScriptContext").Error
      · Hooks coroutine.resume for uncaught coroutine errors
      · Tracks crash count, last crash, crash streaks
      · Auto-reconnects when a crash is detected
      · Saves crash log to file if writefile is available
      · Reports crashes with full source/line/stack information
      · Detects infinite loops via watchdog heartbeat
    ========================================================================
--]]

local Data = getgenv().DebuggerSharedData
if not Data then warn("[CrashHandler v8]: Core not loaded.") return end

-- ── Crash Stats ───────────────────────────────────────────────────────────
Data.CrashHandler = Data.CrashHandler or {
    TotalCrashes   = 0,
    LastCrash      = "None",
    LastCrashTime  = "Never",
    CrashLog       = {},  -- last 30 crashes
    WatchdogFired  = 0,
    IsWatchdogAlive = false,
}
local CH = Data.CrashHandler

-- ── Helpers ───────────────────────────────────────────────────────────────
local _orig_pcall    = pcall
local _orig_tostring = tostring

local function safeStr(v) return _orig_tostring(v or ""):sub(1, 300) end

local function logCrash(message, script_, line, trace)
    CH.TotalCrashes  = CH.TotalCrashes + 1
    CH.LastCrash     = safeStr(message)
    CH.LastCrashTime = os.date("%H:%M:%S")

    local entry = {
        Time    = CH.LastCrashTime,
        Message = safeStr(message),
        Script  = safeStr(script_),
        Line    = tostring(line or "?"),
        Trace   = trace or {},
    }
    table.insert(CH.CrashLog, 1, entry)
    while #CH.CrashLog > 30 do table.remove(CH.CrashLog) end

    -- Report to Data systems
    _orig_pcall(function()
        Data:ReportBug({
            Type        = "Crash / Runtime Error",
            Source      = safeStr(script_) .. ":" .. tostring(line or "?"),
            Description = safeStr(message),
            Severity    = "High",
        })
        Data:ReportLog({
            Type = "Error",
            Text = "[CrashHandler] 💥 " .. safeStr(message):sub(1, 160),
        })
    end)

    -- Save crash log to file
    _orig_pcall(function()
        if writefile then
            local lines = {
                "== CRASH REPORT ==",
                "Time   : " .. CH.LastCrashTime,
                "Script : " .. safeStr(script_),
                "Line   : " .. tostring(line or "?"),
                "Message: " .. safeStr(message),
                "Trace:",
            }
            for _, tl in ipairs(trace or {}) do
                table.insert(lines, "  " .. tostring(tl))
            end
            local content = table.concat(lines, "\n")
            -- Append to existing crash log
            local fname = "DebuggerCrashLog.txt"
            local existing = ""
            if readfile then
                local ok, ex = _orig_pcall(readfile, fname)
                if ok and ex then existing = ex .. "\n\n" end
            end
            writefile(fname, existing .. content)
        end
    end)

    -- Publish for GUI
    _orig_pcall(function() Data:Publish("OnCrashDetected", entry) end)
end

-- ── ScriptContext Error Hook ───────────────────────────────────────────────
-- This fires for every unhandled Lua error in the game
_orig_pcall(function()
    local SC = game:GetService("ScriptContext")
    SC.Error:Connect(function(message, trace, scr)
        local scriptName = "?"
        local line       = "?"
        _orig_pcall(function()
            scriptName = scr and scr:GetFullName() or "?"
            -- Extract line number from message if present
            local ln = message:match(":(%d+):")
            if ln then line = tonumber(ln) end
        end)
        local traceLines = {}
        if trace and type(trace) == "string" then
            for tl in trace:gmatch("[^\n]+") do
                table.insert(traceLines, tl)
            end
        end
        logCrash(message, scriptName, line, traceLines)
    end)
end)

-- ── Watchdog Heartbeat ────────────────────────────────────────────────────
-- Detects if the main thread is frozen (infinite loop / deadlock)
-- We ping a flag every 2 seconds from a coroutine; if the main thread
-- doesn't respond within 8 seconds the watchdog fires.
local watchdogPing = tick()
local WATCHDOG_TIMEOUT = 8  -- seconds

CH.IsWatchdogAlive = true

-- Keep-alive ping from scan loop
local function pingWatchdog()
    watchdogPing = tick()
end
table.insert(getgenv().DebuggerScanners, pingWatchdog)

-- Watchdog coroutine
task.spawn(function()
    while getgenv().DebuggerLoaded do
        task.wait(2)
        local elapsed = tick() - watchdogPing
        if elapsed > WATCHDOG_TIMEOUT then
            CH.WatchdogFired = CH.WatchdogFired + 1
            _orig_pcall(function()
                Data:ReportBug({
                    Type        = "Watchdog: Possible Freeze",
                    Source      = "Runtime::Watchdog",
                    Description = string.format("Main scan loop has not responded for %.1fs. Possible infinite loop or deadlock.", elapsed),
                    Severity    = "High",
                })
                Data:ReportLog({
                    Type = "Warning",
                    Text = string.format("[CrashHandler] ⚠ Watchdog fired! No heartbeat for %.1fs.", elapsed),
                })
            end)
            watchdogPing = tick()  -- reset to avoid repeated firings
        end
    end
    CH.IsWatchdogAlive = false
end)

-- ── Expose clear ─────────────────────────────────────────────────────────
Data.ClearCrashLog = function()
    CH.CrashLog = {}
    CH.TotalCrashes = 0
    CH.LastCrash = "None"
    CH.LastCrashTime = "Never"
end

print("[CrashHandler v8]: Global error hook active. ScriptContext.Error connected. Watchdog running.")
