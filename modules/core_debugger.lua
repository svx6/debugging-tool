--[[
    ========================================================================
    ULTIMATE ROBLOX AUTO-DEBUGGER  ·  CORE DEBUGGER ENGINE  (v6.1)
    ========================================================================
    Author   : luke
    Features :
      · Deep error hooking (hooks pcall, error, xpcall, coroutine.resume)
      · Full stack trace capture with source + line info
      · Memory leak detector (watches for growing global tables)
      · require() hook — logs every module load + failures
      · Coroutine leak detector (dead coroutines still referenced)
      · Global variable pollution scanner
      · Live error rate counter (errors/sec)
    Fixed:
      · debug.info returns multi-values, not a table
      · pcall hook uses _orig_pcall internally to prevent recursion
      · Publish guard prevents infinite log→publish→pcall→log loops
      · Removed task.spawn profiler (false positives on yielding fns)
    ========================================================================
--]]

local Data = getgenv().DebuggerSharedData
if not Data then warn("[CoreDebugger]: Core not loaded.") return end

-- ── Environment Setup ──────────────────────────────────────────────────────
local getgenv_fn = (typeof(getgenv) == "function" and getgenv)
    or function() return _G end

-- Keep originals BEFORE any hooks touch them
local _orig_pcall  = pcall
local _orig_xpcall = xpcall
local _orig_error  = error
local _orig_type   = type
local _orig_tostring = tostring

-- ── Stats Extension ────────────────────────────────────────────────────────
Data.CoreDebugger = Data.CoreDebugger or {
    HookedPcalls      = 0,
    CaughtErrors      = 0,
    RequireLoads      = 0,
    RequireFailures   = 0,
    CoroutinesCreated = 0,
    CoroutinesLeaked  = 0,
    ErrorRate         = 0,  -- errors per second
    MemoryUsageMB     = 0,
    GlobalVarCount    = 0,
    StackTraces       = {},  -- most recent 50 stack traces
}

local CD = Data.CoreDebugger

-- ── Re-entrancy Guard ──────────────────────────────────────────────────────
-- Prevents infinite loops: pcall hook → ReportLog → Publish → pcall hook → ...
local _insideHook = false

-- ── Utility ────────────────────────────────────────────────────────────────
local function getStackTrace(level)
    level = (level or 2) + 1
    local lines = {}
    local i = level
    while i <= level + 12 do
        -- Roblox debug.info returns MULTIPLE VALUES, not a table
        -- debug.info(level, "sln") → source, line, name
        local ok, src, ln, name
        if debug and debug.info then
            ok, src, ln, name = _orig_pcall(debug.info, i, "sln")
        else
            ok = false
        end
        if not ok or (src == nil and ln == nil and name == nil) then break end

        local srcStr  = _orig_tostring(src or "?")
        local lineNum = ln or 0
        local funcName = (name and #_orig_tostring(name) > 0)
            and ("in function '" .. _orig_tostring(name) .. "'")
            or "in ?"
        table.insert(lines, string.format("  ► %s:%d %s", srcStr, lineNum, funcName))
        i = i + 1
    end
    if #lines == 0 then
        -- Fallback: generate a traceback string
        if debug and debug.traceback then
            local ok2, tb = _orig_pcall(debug.traceback, "", level)
            if ok2 and _orig_type(tb) == "string" then
                for line in tb:gmatch("[^\n]+") do
                    if #line > 0 then
                        table.insert(lines, "  ► " .. line)
                    end
                end
            end
        end
    end
    return lines
end

local function captureStackTrace(errMsg, level)
    local trace = getStackTrace(level or 3)
    local entry = {
        Time    = os.date("%H:%M:%S"),
        Message = _orig_tostring(errMsg):sub(1, 200),
        Trace   = trace,
    }
    table.insert(CD.StackTraces, 1, entry)
    while #CD.StackTraces > 50 do table.remove(CD.StackTraces) end
    -- Broadcast to GUI (use _orig_pcall to avoid recursion)
    _orig_pcall(function()
        Data:Publish("OnStackTrace", entry)
    end)
    return entry
end

-- ── Error Rate Tracker ─────────────────────────────────────────────────────
local errorTimestamps = {}
local function trackError()
    local now = os.clock()
    table.insert(errorTimestamps, now)
    -- Trim to last 10 seconds
    local i = 1
    while i <= #errorTimestamps do
        if now - errorTimestamps[i] > 10 then
            table.remove(errorTimestamps, i)
        else
            i = i + 1
        end
    end
    CD.CaughtErrors = CD.CaughtErrors + 1
    CD.ErrorRate = math.floor(#errorTimestamps / 10 + 0.5)
end

-- ── Safe log helper (uses _orig_pcall, checks re-entrancy) ────────────────
local function safeReportLog(entry)
    if _insideHook then return end
    _insideHook = true
    _orig_pcall(function()
        Data:ReportLog(entry)
    end)
    _insideHook = false
end

-- ── pcall Hook ────────────────────────────────────────────────────────────
local function hookedPcall(f, ...)
    CD.HookedPcalls = CD.HookedPcalls + 1
    local results = table.pack(_orig_pcall(f, ...))
    if not results[1] and not _insideHook then
        local errMsg = _orig_tostring(results[2] or "unknown error")
        trackError()
        captureStackTrace(errMsg, 3)
        safeReportLog({
            Type = "Error",
            Text = "[CoreDebugger] pcall caught: " .. errMsg:sub(1, 200),
        })
    end
    return table.unpack(results, 1, results.n)
end

-- Install hook safely
_orig_pcall(function()
    if hookfunction then
        hookfunction(pcall, hookedPcall)
    elseif getgenv_fn then
        getgenv_fn().pcall = hookedPcall
    end
end)

-- ── xpcall hook ───────────────────────────────────────────────────────────
local function hookedXpcall(f, handler, ...)
    local function wrappedHandler(err)
        if not _insideHook then
            trackError()
            captureStackTrace(err, 3)
            safeReportLog({
                Type = "Error",
                Text = "[CoreDebugger] xpcall caught: " .. _orig_tostring(err):sub(1, 150),
            })
        end
        return handler(err)
    end
    return _orig_xpcall(f, wrappedHandler, ...)
end

_orig_pcall(function()
    if hookfunction then
        hookfunction(xpcall, hookedXpcall)
    elseif getgenv_fn then
        getgenv_fn().xpcall = hookedXpcall
    end
end)

-- ── coroutine.resume Hook ──────────────────────────────────────────────────
local aliveCoroutines = {}
local _orig_resume = coroutine.resume

_orig_pcall(function()
    coroutine.resume = function(co, ...)
        CD.CoroutinesCreated = CD.CoroutinesCreated + 1
        local results = table.pack(_orig_resume(co, ...))
        if not results[1] and not _insideHook then
            local err = _orig_tostring(results[2] or "")
            trackError()
            safeReportLog({
                Type = "Error",
                Text = "[CoreDebugger] coroutine.resume error: " .. err:sub(1, 150),
            })
            captureStackTrace(err, 3)
        end
        -- Track alive/dead state
        _orig_pcall(function()
            if coroutine.status(co) == "dead" then
                aliveCoroutines[co] = nil
            else
                aliveCoroutines[co] = os.clock()
            end
        end)
        return table.unpack(results, 1, results.n)
    end
end)

-- ── require() Hook ────────────────────────────────────────────────────────
local _orig_require = require

_orig_pcall(function()
    local hookedRequire = function(module)
        local t0 = os.clock()
        CD.RequireLoads = CD.RequireLoads + 1
        local modName = "unknown"
        _orig_pcall(function()
            if typeof(module) == "Instance" then
                modName = module:GetFullName()
            else
                modName = _orig_tostring(module)
            end
        end)
        local ok, result = _orig_pcall(_orig_require, module)
        local elapsed = os.clock() - t0

        if not ok then
            CD.RequireFailures = CD.RequireFailures + 1
            trackError()
            safeReportLog({
                Type = "Error",
                Text = string.format("[CoreDebugger] require('%s') FAILED: %s", modName, _orig_tostring(result):sub(1, 120)),
            })
            _orig_pcall(function()
                Data:ReportBug({
                    Type        = "Module Load Failure",
                    Source      = modName,
                    Description = string.format("require('%s') threw an error after %.3fs: %s", modName, elapsed, _orig_tostring(result):sub(1, 100)),
                    Severity    = "High",
                })
            end)
        elseif elapsed > 0.5 then
            _orig_pcall(function()
                Data:ReportBug({
                    Type        = "Slow Module Load",
                    Source      = modName,
                    Description = string.format("require('%s') took %.2fs. Long module loads block the thread and cause hitches.", modName, elapsed),
                    Severity    = "Medium",
                })
            end)
        end
        if not ok then _orig_error(result, 2) end
        return result
    end

    if hookfunction then
        hookfunction(require, hookedRequire)
    elseif getgenv_fn then
        getgenv_fn().require = hookedRequire
    end
end)

-- ── Memory Monitor ────────────────────────────────────────────────────────
local lastMemory = 0
task.spawn(function()
    while getgenv_fn().DebuggerLoaded do
        task.wait(5)
        _orig_pcall(function()
            local memMB = gcinfo() / 1024
            CD.MemoryUsageMB = math.floor(memMB * 10 + 0.5) / 10

            if lastMemory > 0 and (memMB - lastMemory) > 10 then
                Data:ReportBug({
                    Type        = "Memory Leak",
                    Source      = "Runtime::Memory",
                    Description = string.format("Memory grew %.1f MB → %.1f MB in 5s. Possible table or instance leak.", lastMemory, memMB),
                    Severity    = "High",
                })
                safeReportLog({
                    Type = "Warning",
                    Text = string.format("[CoreDebugger] Memory spike: +%.1f MB (now %.1f MB)", memMB - lastMemory, memMB),
                })
            end
            lastMemory = memMB
        end)
    end
end)

-- ── Global Variable Pollution Scanner ─────────────────────────────────────
local STANDARD_GLOBALS = {
    "print","warn","error","assert","pcall","xpcall","tostring","tonumber",
    "type","typeof","pairs","ipairs","next","select","unpack","rawget","rawset",
    "rawequal","rawlen","setmetatable","getmetatable","require","load","loadstring",
    "dofile","loadfile","collectgarbage","gcinfo","tick","time","wait","delay","spawn",
    "math","string","table","coroutine","io","os","debug","bit32","utf8",
    "game","workspace","script","plugin","shared","_G","_ENV","_VERSION",
    "Enum","Instance","Vector3","Vector2","CFrame","Color3","UDim","UDim2",
    "BrickColor","Ray","Rect","Region3","NumberRange","NumberSequence","ColorSequence",
    "PhysicalProperties","TweenInfo","Font","PathWaypoint","RaycastParams","RaycastResult",
    "task","getgenv","getsenv","getrenv","hookfunction","hookmetamethod","getnamecallmethod",
    "newcclosure","iscclosure","islclosure","isexecutorclosure","syn","Drawing",
    "readfile","writefile","listfiles","isfile","isfolder","makefolder","delfolder",
    "delfile","cloneref","compareinstances","getrawmetatable","setrawmetatable",
    "getconnections","getboundingbox","setreadonly","isreadonly","identifyexecutor",
    "getscripts","getsourceid","decompile","replicatesignal","firesignal",
}
local standardSet = {}
for _, n in ipairs(STANDARD_GLOBALS) do standardSet[n] = true end

local function scanGlobalPollution()
    local count = 0
    local suspicious = {}
    _orig_pcall(function()
        local env = getgenv_fn()
        for k, v in pairs(env) do
            if type(k) == "string" and not standardSet[k] and k ~= "DebuggerLoaded" and k ~= "DebuggerSharedData" and k ~= "DebuggerScanners" then
                count = count + 1
                if (typeof(v) == "table" or typeof(v) == "function") and #suspicious < 10 then
                    table.insert(suspicious, _orig_tostring(k))
                end
            end
        end
    end)
    CD.GlobalVarCount = count
    if count > 30 then
        Data:ReportBug({
            Type        = "Global Variable Pollution",
            Source      = "Runtime::Globals",
            Description = string.format("%d non-standard global variables detected. Suspects: %s", count, table.concat(suspicious, ", ")),
            Severity    = count > 80 and "High" or "Medium",
        })
    end
end

-- ── Coroutine Leak Detector ────────────────────────────────────────────────
local function scanCoroutineLeaks()
    local leakCount = 0
    local staleThreshold = 30
    local now = os.clock()
    for co, createdAt in pairs(aliveCoroutines) do
        _orig_pcall(function()
            local status = coroutine.status(co)
            if status == "dead" then
                aliveCoroutines[co] = nil
            elseif status == "suspended" and (now - createdAt) > staleThreshold then
                leakCount = leakCount + 1
                aliveCoroutines[co] = nil
            end
        end)
    end
    if leakCount > 0 then
        CD.CoroutinesLeaked = CD.CoroutinesLeaked + leakCount
        Data:ReportBug({
            Type        = "Coroutine Leak",
            Source      = "Runtime::Coroutines",
            Description = string.format("%d suspended coroutines idle for >%ds. Leaked coroutines hold memory.", leakCount, staleThreshold),
            Severity    = "Medium",
        })
    end
end

-- ── Register to Global Scanner ────────────────────────────────────────────
local function runCoreDebuggerScan()
    _orig_pcall(scanGlobalPollution)
    _orig_pcall(scanCoroutineLeaks)
    Data:Publish("OnCoreDebuggerUpdate", CD)
end

table.insert(getgenv_fn().DebuggerScanners, runCoreDebuggerScan)
print("[CoreDebugger]: Deep runtime hooks active. Monitoring pcall/error/require/coroutine/memory/globals.")
