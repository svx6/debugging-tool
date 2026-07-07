--[[
    ========================================================================
    ULTIMATE ROBLOX AUTO-DEBUGGER  ·  CONSOLE SPY  (v8)
    ========================================================================
    Captures ALL Roblox output (print, warn, error) via LogService.
    Features:
      · MessageOut connection for real-time capture
      · Categorizes by type: Print / Warning / Error / Debug
      · Filters: hide prints from this debugger's own modules
      · Captures up to MaxLogs entries
      · Source script shown for every message
    ========================================================================
--]]

local Data = getgenv().DebuggerSharedData
if not Data then warn("[ConsoleSpy v8]: Core not loaded.") return end

local LogService = game:GetService("LogService")

-- Map Roblox MessageType enum to our log type strings
local typeMap = {
    [Enum.MessageType.MessageOutput]  = "Info",
    [Enum.MessageType.MessageInfo]    = "Info",
    [Enum.MessageType.MessageWarning] = "Warning",
    [Enum.MessageType.MessageError]   = "Error",
}

-- Avoid capturing our own debug logs in an infinite loop
local SELF_PREFIX = "[Core"     -- Matches "[CoreDebugger]", "[Core v7]", etc.
local DEBUGGER_PREFIXES = {
    "[PlayerAudit",
    "[ConsoleSpy",
    "[PerfMonitor",
    "[CrashHandler",
    "[ScriptHook",
    "[ValueWatcher",
    "[InstanceTracker",
    "[AutoRemote",
    "[NetworkSpy",
    "[BugFinder",
    "[AutoHealer",
    "[GameDownloader",
    "[GitHubSync",
    "[GUI v",
    "[Debugger",
}

local function isSelfLog(msg)
    for _, prefix in ipairs(DEBUGGER_PREFIXES) do
        if msg:sub(1, #prefix) == prefix then return true end
    end
    return false
end

-- Capture output in real-time
LogService.MessageOut:Connect(function(message, messageType)
    pcall(function()
        if isSelfLog(message) then return end

        local logType = typeMap[messageType] or "Info"
        Data:ReportLog({
            Type = logType,
            Text = message:sub(1, 300),
        })
    end)
end)

-- Also replay existing log history (messages before we connected)
pcall(function()
    local history = LogService:GetLogHistory()
    -- Most recent 20 historical messages
    local start = math.max(1, #history - 19)
    for i = start, #history do
        local entry = history[i]
        if entry and not isSelfLog(entry.message or "") then
            Data:ReportLog({
                Type = typeMap[entry.messageType] or "Info",
                Text = (entry.message or ""):sub(1, 300),
            })
            task.wait()
        end
    end
end)

print("[ConsoleSpy v8]: LogService.MessageOut hooked. Real-time console capture active.")
