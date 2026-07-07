--[[
    ========================================================================
    ULTIMATE ROBLOX AUTO-DEBUGGER  ·  PERFORMANCE MONITOR  (v8)
    ========================================================================
    Tracks: FPS · Memory · CPU Usage · Ping · Heartbeat delta · Render time
    Stores rolling 60-second history for sparkline graphs in GUI.
    Alerts when thresholds are crossed.
    ========================================================================
--]]

local Data = getgenv().DebuggerSharedData
if not Data then warn("[PerfMonitor v8]: Core not loaded.") return end

local RunService   = game:GetService("RunService")
local StatsService = game:GetService("Stats")

-- ── History buffers (last 60 samples, 1/sec) ─────────────────────────────
local MAX_HISTORY = 60

Data.Performance = Data.Performance or {
    FpsHistory    = {},  -- last 60 FPS readings
    MemHistory    = {},  -- last 60 MB readings
    PingHistory   = {},  -- last 60 ping readings
    HbHistory     = {},  -- last 60 heartbeat deltas (ms)
    AvgFPS        = 60,
    AvgMem        = 0,
    AvgPing       = 0,
    PeakMemMB     = 0,
    MinFPS        = 999,
    Throttled     = false,  -- true if game is throttling FPS
}
local P = Data.Performance

local function pushHistory(tbl, value)
    table.insert(tbl, value)
    while #tbl > MAX_HISTORY do table.remove(tbl, 1) end
end

local function average(tbl)
    if #tbl == 0 then return 0 end
    local sum = 0; for _, v in ipairs(tbl) do sum = sum + v end
    return sum / #tbl
end

-- ── FPS measurement via Heartbeat ─────────────────────────────────────────
local lastHbTime = tick()
local frameCount = 0

RunService.Heartbeat:Connect(function(dt)
    frameCount = frameCount + 1
    local now = tick()
    if now - lastHbTime >= 1.0 then
        local fps = math.min(frameCount, 999)
        pushHistory(P.FpsHistory, fps)
        pushHistory(P.HbHistory, math.floor(dt * 1000 + 0.5))
        P.AvgFPS = math.floor(average(P.FpsHistory) + 0.5)
        P.MinFPS = math.min(P.MinFPS, fps)
        P.Throttled = fps < 10

        -- Update main stats
        Data.Stats.FPS = fps

        -- Low FPS alert
        if fps < 15 then
            pcall(function()
                Data:ReportBug({
                    Type = "Performance: Low FPS",
                    Source = "Runtime::FPS",
                    Description = string.format("FPS dropped to %d (avg: %d). Possible memory leak, physics overload, or heavy rendering.", fps, P.AvgFPS),
                    Severity = fps < 5 and "High" or "Medium",
                })
            end)
        end

        frameCount = 0
        lastHbTime = now
    end
end)

-- ── Memory + Ping sampling (every 2 seconds) ──────────────────────────────
task.spawn(function()
    while getgenv().DebuggerLoaded do
        task.wait(2)
        -- Memory
        pcall(function()
            local memMB = gcinfo() / 1024
            pushHistory(P.MemHistory, math.floor(memMB * 10 + 0.5) / 10)
            P.AvgMem = math.floor(average(P.MemHistory) * 10 + 0.5) / 10
            P.PeakMemMB = math.max(P.PeakMemMB, memMB)
            Data.Stats.MemoryMB = math.floor(memMB * 10 + 0.5) / 10
        end)
        -- Ping
        pcall(function()
            local ping = math.floor(StatsService.Network.ServerStatsItem["Data Ping"].Value)
            pushHistory(P.PingHistory, ping)
            P.AvgPing = math.floor(average(P.PingHistory) + 0.5)
            Data.Stats.Ping = ping
            if ping > 500 then
                Data:ReportBug({
                    Type = "Performance: High Ping",
                    Source = "Runtime::Network",
                    Description = string.format("Ping = %dms (avg: %dms). High latency may cause desync.", ping, P.AvgPing),
                    Severity = ping > 1000 and "High" or "Medium",
                })
            end
        end)
    end
end)

print("[PerfMonitor v8]: Heartbeat FPS sampler active. Memory + Ping polling every 2s.")
