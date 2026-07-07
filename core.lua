--[[
    ========================================================================
    ULTIMATE ROBLOX AUTO-DEBUGGER  ·  CORE RUNTIME KERNEL  (v7)
    ========================================================================
    Author   : Antigravity
    Features : Shared state · pub-sub dispatcher · centralized helpers
               · O(1) duplicate bug dedup · extended stats · GitHub config
               · executor-safe · works on Synapse, Krnl, Wave, Codex, Delta
    ========================================================================
--]]

-- ── Executor-safe global env ──────────────────────────────────────────────
local getgenv = (typeof(getgenv) == "function" and getgenv)
    or (typeof(syn) == "table" and typeof(syn.getgenv) == "function" and syn.getgenv)
    or function() return _G end

-- ── Shared Data Model ─────────────────────────────────────────────────────
local Data = {
    Version    = "7",
    Logs       = {},
    Remotes    = {},        -- network_spy records  (key = path)
    AutoRemotes = {},       -- auto_remote records  (key = path)
    Bugs       = {},        -- ordered list, newest first
    BugSet     = {},        -- {type:source} → true   (O(1) dedup)
    AIInsights = {},

    Stats = {
        Errors        = 0,
        Warnings      = 0,
        RemotesHooked = 0,
        BugsFound     = 0,
        InstanceCount = 0,
        FPS           = 60,
        Ping          = 0,
        AutoHealCount = 0,
        ScanCount     = 0,
        Uptime        = 0,  -- seconds since start
        ExecutorName  = "Unknown",
        GameName      = "?",
        PlaceId       = 0,
    },

    Settings = {
        AutoClean    = false,
        ScanInterval = 3,
        MaxLogs      = 500,
        MaxBugs      = 400,
        MaxInsights  = 100,
        MaxRemotes   = 300,
    },

    -- GitHub integration config
    GitHub = {
        Repo       = "",          -- "owner/repo"
        Branch     = "main",
        AutoSync   = false,
        LastSync   = "Never",
        SyncStatus = "Idle",      -- "Idle" | "Syncing" | "OK" | "Error"
    },

    Listeners = {},
    StartTime = os.clock(),

    -- Sub-module states (populated by their modules)
    CoreDebugger   = nil,
    Downloader     = nil,
    BlockedRemotes = {},

    -- APIs (filled by modules)
    DownloadGame        = nil,
    DownloadScriptsOnly = nil,
    HasFileIO           = nil,
    FireRemote          = nil,
    BlockRemote         = nil,
    UnblockRemote       = nil,
}

-- ── Detect executor name ──────────────────────────────────────────────────
pcall(function()
    if identifyexecutor then
        Data.Stats.ExecutorName = identifyexecutor() or "Unknown"
    elseif syn then
        Data.Stats.ExecutorName = "Synapse X"
    elseif KRNL_LOADED then
        Data.Stats.ExecutorName = "Krnl"
    end
end)

-- ── Game info ─────────────────────────────────────────────────────────────
pcall(function()
    Data.Stats.GameName = game.Name or "?"
    Data.Stats.PlaceId  = game.PlaceId or 0
end)

-- ── Pub-Sub Dispatcher ────────────────────────────────────────────────────
function Data:Subscribe(event, callback)
    if not self.Listeners[event] then
        self.Listeners[event] = {}
    end
    table.insert(self.Listeners[event], callback)
end

function Data:Publish(event, payload)
    local list = self.Listeners[event]
    if not list then return end
    for _, cb in ipairs(list) do
        if task and task.spawn then
            pcall(task.spawn, cb, payload)
        else
            pcall(cb, payload)
        end
    end
end

-- ── Bug Reporter (O(1) dedup via BugSet) ──────────────────────────────────
function Data:ReportBug(bugData)
    local typeKey = (bugData.Type or ""):lower()
    local srcKey  = (bugData.Source or ""):lower()
    local setKey  = typeKey .. "\0" .. srcKey

    if self.BugSet[setKey] then return false end
    self.BugSet[setKey] = true

    bugData.Time     = bugData.Time or os.date("%H:%M:%S")
    bugData.Severity = bugData.Severity or "Low"

    table.insert(self.Bugs, 1, bugData)
    self.Stats.BugsFound = self.Stats.BugsFound + 1

    -- Trim oldest if over limit, removing its set entry too
    while #self.Bugs > self.Settings.MaxBugs do
        local old = table.remove(self.Bugs)
        if old then
            local ok = (old.Type or ""):lower() .. "\0" .. (old.Source or ""):lower()
            self.BugSet[ok] = nil
        end
    end

    self:Publish("OnBugAdded", bugData)
    return true
end

-- ── Log Reporter ──────────────────────────────────────────────────────────
function Data:ReportLog(entry)
    entry.Time = entry.Time or os.date("%H:%M:%S")
    if entry.Type == "Error" then
        self.Stats.Errors = self.Stats.Errors + 1
    elseif entry.Type == "Warning" then
        self.Stats.Warnings = self.Stats.Warnings + 1
    end
    table.insert(self.Logs, 1, entry)
    while #self.Logs > self.Settings.MaxLogs do table.remove(self.Logs) end
    self:Publish("OnLogAdded", entry)
end

-- ── Clear All State ───────────────────────────────────────────────────────
function Data:Clear()
    self.Logs       = {}
    self.Bugs       = {}
    self.BugSet     = {}
    self.AIInsights = {}
    self.Stats.Errors    = 0
    self.Stats.Warnings  = 0
    self.Stats.BugsFound = 0
    self:Publish("OnCleared", true)
end

-- ── Uptime String ─────────────────────────────────────────────────────────
function Data:Uptime()
    local s = math.floor(os.clock() - self.StartTime)
    self.Stats.Uptime = s
    return string.format("%02d:%02d:%02d",
        math.floor(s / 3600),
        math.floor((s % 3600) / 60),
        s % 60)
end

-- ── Export ────────────────────────────────────────────────────────────────
getgenv().DebuggerSharedData = Data
print(string.format("[Core v7]: Kernel ready | Executor: %s | Game: %s (%d)",
    Data.Stats.ExecutorName, Data.Stats.GameName, Data.Stats.PlaceId))
