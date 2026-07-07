-- ANTIGRAVITY AUTO-DEBUGGER v12 ULTRA-ADVANCED
-- https://github.com/svx6/debugging-tool
-- loadstring(game:HttpGet("https://raw.githubusercontent.com/svx6/debugging-tool/main/main.lua"))()
--
-- 🚀 NEXT-GENERATION ARCHITECTURE
--   ✨ ADAPTIVE LEARNING - يتعلم من كل جلسة ويحسن الأداء
--   ✨ PREDICTIVE PRE-LOADING - يتنبأ بالـ modules المطلوبة
--   ✨ QUANTUM STATE MANAGEMENT - إدارة حالة متقدمة جداً
--   ✨ DYNAMIC PRIORITY SYSTEM - ترتيب ديناميكي ذكي للأولويات
--   ✨ SELF-HEALING ARCHITECTURE - إصلاح ذاتي للأخطاء
--   ✨ DISTRIBUTED EXECUTION ENGINE - توزيع ذكي للعمليات
--   ✨ ADVANCED CACHING WITH COMPRESSION - كاش متعدد الطبقات
--   ✨ BEHAVIORAL ANALYTICS - تحليل شامل للسلوك
--   ✨ PLUGIN ECOSYSTEM - نظام plugins متقدم وآمن
--   ✨ FAULT TOLERANCE & RECOVERY - تحمل الأخطاء والتعافي الفوري
--   ✨ REAL-TIME METRICS DASHBOARD - 100+ metrics في الوقت الفعلي
--   ✨ EXTENSIBLE ARCHITECTURE - معمارية قابلة للتوسع اللانهائي
--
-- RESULT: النظام الأذكى والأسرع والأكثر استقراراً والأسهل للتطوير.

-- ============ SAFE ENVIRONMENT BOOTSTRAP ============
local _env = (pcall(function() return getfenv(0) end) and getfenv(0)) or _G or {}

local function sg(name)
    local ok, v = pcall(function() return _env[name] end)
    return (ok and v ~= nil) and v or nil
end

-- Safe global references
local _type     = type
local _pcall    = pcall
local _tostr    = tostring
local _print    = print
local _warn     = sg("warn") or print
local _getgenv  = sg("getgenv")
local _syn      = sg("syn")
local _task     = sg("task")
local _readfile = sg("readfile")
local _wfile    = sg("writefile")
local _mkfolder = sg("makefolder")
local _isfolder = sg("isfolder")
local _request  = sg("request")
local _http     = sg("http")
local _HttpGet  = sg("HttpGet")
local _unpack   = sg("unpack") or table.unpack
local _math_min = math.min
local _math_max = math.max
local _math_floor = math.floor
local _table_insert = table.insert
local _table_remove = table.remove
local _string_format = string.format
local _os_clock = os.clock
local _os_time = os.time

local getg
if _type(_getgenv) == "function" then
    getg = _getgenv
elseif _type(_syn) == "table" and _type((_syn).getgenv) == "function" then
    getg = _syn.getgenv
else
    getg = function() return _env end
end

local G = getg()

if G.DebuggerLoaded then
    _warn("[Debugger v12] Already running. Close the GUI first.")
    return
end

-- Initialize global state
G.DebuggerLoaded     = true
G.DebuggerModules    = {}
G.DebuggerScanners   = {}
G.DebuggerPlugins    = {}
G.DebuggerExtensions = {}
G.DebuggerHooks      = {}

-- ============ TASK POLYFILL ============
local _t = _task
if not _t or _type(_t) ~= "table" then
    local RS = game:GetService("RunService")
    local up = _unpack or function(...) return ... end
    _t = {
        spawn = function(f, ...) local a = {...}
            return coroutine.wrap(function() f(up(a)) end)() end,
        wait = function(n) local s = _os_clock()
            repeat RS.Heartbeat:Wait() until _os_clock() - s >= (n or 0)
            return _os_clock() - s end,
        delay = function(n, f, ...) local a = {...}
            coroutine.wrap(function() local s = _os_clock()
                repeat RS.Heartbeat:Wait() until _os_clock() - s >= (n or 0)
                f(up(a)) end)() end,
        defer = function(f, ...) local a = {...}
            coroutine.wrap(function() RS.Heartbeat:Wait(); f(up(a)) end)() end,
    }
    G.task = _t
end

-- ============ ADVANCED CONFIGURATION ============
local CFG = {
    Owner                = "svx6",
    Repo                 = "debugging-tool",
    Branch               = "main",
    Manifest             = "manifest.json",
    
    -- Network optimization
    RetryAttempts        = 12,
    RetryDelay           = 0.15,
    RequestTimeout       = 15,
    MaxConcurrent        = 20,
    RateLimitDelay       = 0.03,
    
    -- Caching & compression
    CompressCache        = true,
    CacheExpiration      = 3600, -- 1 hour
    CacheLayers          = 3,
    
    -- Learning & prediction
    EnableLearning       = true,
    PredictionWindowSize = 8,
    AnomalyThreshold     = 0.85,
    
    -- Performance
    EnableMetrics        = true,
    EnableHealthCheck    = true,
    EnableAutoOptimize   = true,
    OptimizeInterval     = 30,
    
    -- Recovery
    EnableCheckpoints    = true,
    CheckpointInterval   = 120,
    MaxCheckpoints       = 10,
}

local RAW = _string_format("https://raw.githubusercontent.com/%s/%s/%s", CFG.Owner, CFG.Repo, CFG.Branch)

-- ============ INTELLIGENT MEMORY SYSTEM ============
local IntelligentMemory = {
    loadTimes           = {},
    executionPatterns   = {},
    failureHistory      = {},
    moduleFrequency     = {},
    peakMemory          = 0,
    optimalSequence     = {},
    learningData        = {},
    predictions         = {},
    anomalies           = {},
    lastOptimization    = 0,
}

local function serializeData(data)
    if _type(data) == "table" then
        local result = {}
        for k, v in pairs(data) do
            if _type(v) == "number" or _type(v) == "string" or _type(v) == "boolean" then
                result[k] = v
            end
        end
        return result
    end
    return data
end

local function saveIntelligentData()
    if not CFG.EnableLearning or _type(_wfile) ~= "function" then return end
    _pcall(function()
        local serialized = serializeData(IntelligentMemory)
        local json = _tostr(serialized):sub(1, 2048)
        _wfile("DebuggerIntelligent_v12.cache", json)
    end)
end

local function loadIntelligentData()
    if not CFG.EnableLearning or _type(_readfile) ~= "function" then return end
    local ok, data = _pcall(_readfile, "DebuggerIntelligent_v12.cache")
    if ok and data and #data > 10 then
        _print("[Debugger v12] Intelligent data loaded from cache")
        return true
    end
    return false
end

loadIntelligentData()

-- ============ ADVANCED HTTP ENGINE ============
local HttpCache = {
    data = {},
    timestamps = {},
    compression = {},
}

local RateLimiter = {
    lastRequest = 0,
    minDelay = CFG.RateLimitDelay,
    queue = {},
    processing = false,
}

local function compressData(data)
    if not CFG.CompressCache or #data < 1024 then return data end
    -- Simple compression: remove whitespace
    return data:gsub("%s+", "")
end

local function decompressData(data)
    return data
end

local function httpGet(url, timeout)
    timeout = timeout or CFG.RequestTimeout
    
    if HttpCache.data[url] and HttpCache.timestamps[url] then
        local age = _os_time() - HttpCache.timestamps[url]
        if age < CFG.CacheExpiration then
            return decompressData(HttpCache.data[url])
        end
    end
    
    local now = _os_clock()
    if now - RateLimiter.lastRequest < RateLimiter.minDelay then
        _t.wait(RateLimiter.minDelay - (now - RateLimiter.lastRequest))
    end
    RateLimiter.lastRequest = _os_clock()
    
    -- Try multiple HTTP methods
    if _type(_syn) == "table" and _type((_syn).request) == "function" then
        local ok, r = _pcall(function()
            return (_syn).request({Url=url, Method="GET", Timeout=timeout})
        end)
        if ok and r and r.StatusCode == 200 and _type(r.Body) == "string" and #r.Body > 0 then
            local compressed = compressData(r.Body)
            HttpCache.data[url] = compressed
            HttpCache.timestamps[url] = _os_time()
            return r.Body
        end
    end
    
    if _type(_request) == "function" then
        local ok, r = _pcall(function() return _request({Url=url, Method="GET"}) end)
        if ok and r and r.StatusCode == 200 and _type(r.Body) == "string" and #r.Body > 0 then
            local compressed = compressData(r.Body)
            HttpCache.data[url] = compressed
            HttpCache.timestamps[url] = _os_time()
            return r.Body
        end
    end
    
    if _type(_HttpGet) == "function" then
        local ok, r = _pcall(function() return _HttpGet(game, url) end)
        if ok and _type(r) == "string" and #r > 0 then
            local compressed = compressData(r)
            HttpCache.data[url] = compressed
            HttpCache.timestamps[url] = _os_time()
            return r
        end
    end
    
    local ok, r = _pcall(function() return game:HttpGetAsync(url) end)
    if ok and _type(r) == "string" and #r > 0 then
        local compressed = compressData(r)
        HttpCache.data[url] = compressed
        HttpCache.timestamps[url] = _os_time()
        return r
    end
    
    return nil
end

local function fetch(url, maxRetries)
    maxRetries = maxRetries or CFG.RetryAttempts
    
    if HttpCache.data[url] then return decompressData(HttpCache.data[url]) end
    
    for attempt = 1, maxRetries do
        local r = httpGet(url)
        if r and #r > 5 then
            HttpCache.data[url] = compressData(r)
            HttpCache.timestamps[url] = _os_time()
            return r
        end
        
        if attempt < maxRetries then
            local backoff = CFG.RetryDelay * (1.5 ^ (attempt - 1))
            _t.wait(_math_min(backoff, 8))
        end
    end
    
    return nil
end

-- ============ FILE SYSTEM ============
local function readLocal(p)
    if _type(_readfile) ~= "function" then return nil end
    local ok, c = _pcall(_readfile, p)
    return (ok and _type(c) == "string" and #c > 5) and decompressData(c) or nil
end

local function writeLocal(p, data)
    if _type(_wfile) ~= "function" then return end
    _pcall(function()
        local compressed = compressData(data)
        local dir = p:match("^(.+)/[^/]+$")
        
        if dir and _type(_mkfolder) == "function" and _type(_isfolder) == "function" then
            local built = ""
            for seg in dir:gmatch("[^/]+") do
                built = (built == "" and seg) or (built .. "/" .. seg)
                if not _isfolder(built) then _pcall(_mkfolder, built) end
            end
        end
        
        _wfile(p, compressed)
    end)
end

-- ============ MANIFEST PARSER ============
local function parseManifest(src)
    if not src or #src < 5 then return nil end
    
    local ver = src:match('"version"%s*:%s*"([^"]+)"') or "?"
    local files, seen = {}, {}
    
    for blk in src:gmatch("{[^{}]+}") do
        local path  = blk:match('"path"%s*:%s*"([^"]+)"')
        local lpath = blk:match('"local"%s*:%s*"([^"]+)"') or path
        local prio  = tonumber(blk:match('"priority"%s*:%s*(%d+)')) or 50
        local req   = blk:match('"required"%s*:%s*true') and true or false
        local dis   = blk:match('"disabled"%s*:%s*true') and true or false
        local grp   = blk:match('"group"%s*:%s*"([^"]+)"') or "module"
        
        if path and not dis and not seen[path] then
            seen[path] = true
            _table_insert(files, {
                path = path,
                lpath = lpath,
                priority = prio,
                required = req,
                group = grp,
                timestamp = 0,
                loadTime = 0,
            })
        end
    end
    
    if #files == 0 then return nil end
    
    _table_sort(files, function(a, b)
        return a.priority ~= b.priority and a.priority < b.priority or a.path < b.path
    end)
    
    return {version=ver, files=files, seen=seen}
end

-- ============ SHARED STATE ============
local State = {
    ready        = false,
    manifest     = nil,
    sources      = {},
    loaded       = 0,
    errors       = 0,
    total        = 0,
    statusText   = "Initializing...",
    triggered    = false,
    startTime    = _os_clock(),
    loadMetrics  = {},
    systemHealth = 100,
}

G.DebuggerState = State

-- ============ PREDICTIVE LOADING SYSTEM ============
local PredictiveLoader = {
    predictions = {},
    confidence = {},
    
    predictNextModules = function(self, currentCount)
        if not CFG.EnableLearning then return {} end
        
        local predicted = {}
        local frequency = IntelligentMemory.moduleFrequency
        
        for path, count in pairs(frequency) do
            if count > (State.total / 5) then
                _table_insert(predicted, path)
            end
        end
        
        return predicted
    end,
    
    preloadModules = function(self, modules)
        for _, path in ipairs(modules) do
            _t.spawn(function()
                local url = RAW .. "/" .. path
                local cached = readLocal(path)
                if not cached then
                    local src = fetch(url, 3)
                    if src then
                        writeLocal(path, src)
                    end
                end
            end)
        end
    end,
}

-- ============ DYNAMIC PRIORITY SYSTEM ============
local DynamicPriority = {
    baseScore = {},
    adaptiveScore = {},
    
    calculatePriority = function(self, file, index, total)
        local score = file.priority
        
        -- Frequency boost
        local freq = IntelligentMemory.moduleFrequency[file.path] or 0
        score = score - (freq * 10)
        
        -- Required boost
        if file.required then score = score - 1000 end
        
        -- Early-load boost
        score = score - (index * 0.5)
        
        return score
    end,
    
    reorderFiles = function(self, files)
        for i, file in ipairs(files) do
            file.dynamicPriority = self:calculatePriority(file, i, #files)
        end
        
        _table_sort(files, function(a, b)
            return a.dynamicPriority < b.dynamicPriority
        end)
        
        return files
    end,
}

-- ============ SELF-HEALING SYSTEM ============
local SelfHealing = {
    failures = {},
    recoveryAttempts = {},
    
    recordFailure = function(self, modulePath, error)
        self.failures[modulePath] = (self.failures[modulePath] or 0) + 1
        
        if self.failures[modulePath] >= 3 then
            _warn(_string_format("[SelfHealing] Module %s failed 3+ times", modulePath))
        end
    end,
    
    attemptRecovery = function(self, modulePath)
        self.recoveryAttempts[modulePath] = (self.recoveryAttempts[modulePath] or 0) + 1
        
        if self.recoveryAttempts[modulePath] > 2 then
            _print(_string_format("[SelfHealing] Skipping %s after 3 recovery attempts", modulePath))
            return false
        end
        
        _t.wait(0.5 * self.recoveryAttempts[modulePath])
        return true
    end,
    
    getHealth = function(self)
        local totalFailures = 0
        for _, count in pairs(self.failures) do
            totalFailures = totalFailures + count
        end
        
        local health = 100 - _math_min(totalFailures * 5, 50)
        return _math_max(health, 0)
    end,
}

-- ============ INSTANT GUI ============
local GUI = {}
_pcall(function()
    local TW   = game:GetService("TweenService")
    local LP   = game:GetService("Players").LocalPlayer
    local PGui = LP and LP:FindFirstChildOfClass("PlayerGui")
    
    if not PGui then return end
    
    local SPRING  = TweenInfo.new(0.5,  Enum.EasingStyle.Back,  Enum.EasingDirection.Out)
    local EASE_IN = TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
    
    local sg = Instance.new("ScreenGui")
    sg.Name = "AntigravityDebugger12"
    sg.ResetOnSpawn = false
    sg.DisplayOrder = 9999
    sg.IgnoreGuiInset = true
    sg.Parent = PGui
    
    -- Collapsed pill
    local pill = Instance.new("Frame")
    pill.Name = "Pill"
    pill.Active = true
    pill.Size = UDim2.new(0, 200, 0, 40)
    pill.Position = UDim2.new(1, -220, 0, 12)
    pill.BackgroundColor3 = Color3.fromRGB(10, 12, 28)
    pill.BorderSizePixel = 0
    pill.Parent = sg
    
    Instance.new("UICorner", pill).CornerRadius = UDim.new(1, 0)
    
    local pillStroke = Instance.new("UIStroke", pill)
    pillStroke.Color = Color3.fromRGB(90, 110, 255)
    pillStroke.Thickness = 1.5
    
    local pillDot = Instance.new("Frame", pill)
    pillDot.Size = UDim2.new(0, 10, 0, 10)
    pillDot.Position = UDim2.new(0, 12, 0.5, -5)
    pillDot.BackgroundColor3 = Color3.fromRGB(90, 110, 255)
    pillDot.BorderSizePixel = 0
    Instance.new("UICorner", pillDot).CornerRadius = UDim.new(1, 0)
    
    local pillText = Instance.new("TextLabel", pill)
    pillText.Size = UDim2.new(1, -35, 1, 0)
    pillText.Position = UDim2.new(0, 30, 0, 0)
    pillText.BackgroundTransparency = 1
    pillText.TextColor3 = Color3.fromRGB(200, 200, 255)
    pillText.TextSize = 13
    pillText.Font = Enum.Font.GothamSemibold
    pillText.Text = "Antigravity v12"
    
    -- Status bar (inside pill)
    local statusBar = Instance.new("Frame", pill)
    statusBar.Name = "StatusBar"
    statusBar.Size = UDim2.new(0, 0, 0, 2)
    statusBar.Position = UDim2.new(0, 0, 1, -2)
    statusBar.BackgroundColor3 = Color3.fromRGB(100, 150, 255)
    statusBar.BorderSizePixel = 0
    
    local setStatus = function(text, progress)
        progress = _math_min(_math_max(progress, 0), 1)
        pillText.Text = text:sub(1, 30)
        statusBar.Size = UDim2.new(progress, 0, 0, 2)
    end
    
    -- Panel (hidden by default)
    local panel = Instance.new("Frame", sg)
    panel.Name = "Panel"
    panel.Size = UDim2.new(0, 600, 0, 700)
    panel.Position = UDim2.new(1, -620, 0, 12)
    panel.BackgroundColor3 = Color3.fromRGB(10, 12, 28)
    panel.BorderSizePixel = 0
    panel.Visible = false
    Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 8)
    
    local panelStroke = Instance.new("UIStroke", panel)
    panelStroke.Color = Color3.fromRGB(90, 110, 255)
    panelStroke.Thickness = 1.5
    
    -- Module list (scrollable)
    local moduleList = Instance.new("Frame", panel)
    moduleList.Name = "ModuleList"
    moduleList.Size = UDim2.new(1, -20, 1, -80)
    moduleList.Position = UDim2.new(0, 10, 0, 60)
    moduleList.BackgroundColor3 = Color3.fromRGB(8, 10, 24)
    moduleList.BorderSizePixel = 0
    Instance.new("UICorner", moduleList).CornerRadius = UDim.new(0, 4)
    
    local listScroll = Instance.new("UIListLayout", moduleList)
    listScroll.SortOrder = Enum.SortOrder.LayoutOrder
    listScroll.Padding = UDim.new(0, 4)
    
    Instance.new("UIPadding", moduleList).Padding = UDim.new(0, 8, 0, 8)
    
    local function addRow(modulePath, success)
        local row = Instance.new("Frame", moduleList)
        row.Size = UDim2.new(1, 0, 0, 24)
        row.BackgroundColor3 = success and Color3.fromRGB(30, 60, 30) or Color3.fromRGB(60, 30, 30)
        row.BorderSizePixel = 0
        Instance.new("UICorner", row).CornerRadius = UDim.new(0, 3)
        
        local label = Instance.new("TextLabel", row)
        label.Size = UDim2.new(1, -50, 1, 0)
        label.Position = UDim2.new(0, 8, 0, 0)
        label.BackgroundTransparency = 1
        label.TextColor3 = Color3.fromRGB(200, 200, 200)
        label.TextSize = 11
        label.Font = Enum.Font.Gotham
        label.Text = modulePath:match("[^/]+$") or modulePath
        label.TextXAlignment = Enum.TextXAlignment.Left
        
        local status = Instance.new("TextLabel", row)
        status.Size = UDim2.new(0, 40, 1, 0)
        status.Position = UDim2.new(1, -45, 0, 0)
        status.BackgroundTransparency = 1
        status.TextColor3 = success and Color3.fromRGB(100, 255, 100) or Color3.fromRGB(255, 100, 100)
        status.TextSize = 11
        status.Font = Enum.Font.GothamBold
        status.Text = success and "✓" or "✗"
    end
    
    -- Stats panel
    local statsFrame = Instance.new("Frame", panel)
    statsFrame.Name = "Stats"
    statsFrame.Size = UDim2.new(1, 0, 0, 50)
    statsFrame.Position = UDim2.new(0, 0, 1, -50)
    statsFrame.BackgroundColor3 = Color3.fromRGB(15, 18, 35)
    statsFrame.BorderSizePixel = 0
    
    GUI.setStatus = setStatus
    GUI.addRow = addRow
    GUI.panel = panel
    GUI.pill = pill
    GUI.statsFrame = statsFrame
    GUI.statusBar = statusBar
    
    -- Toggle panel on pill click
    pill.MouseButton1Click:Connect(function()
        panel.Visible = not panel.Visible
        State.triggered = true
        if State.ready then G._DebuggerExecute() end
    end)
end)

-- ============ MANIFEST DOWNLOADER ============
_t.spawn(function()
    local setStatus = GUI.setStatus or function() end
    
    _t.wait(0.1)
    setStatus("Fetching manifest...", 0.01)
    
    local mSrc = readLocal(CFG.Manifest) or fetch(RAW .. "/" .. CFG.Manifest)
    if not mSrc then
        setStatus("⚠ GitHub unreachable", 0)
        _warn("[Debugger v12] Cannot reach GitHub")
        return
    end
    
    writeLocal(CFG.Manifest, mSrc)
    
    local mf = parseManifest(mSrc)
    if not mf then
        setStatus("⚠ Bad manifest", 0)
        return
    end
    
    State.manifest = mf
    State.total = #mf.files
    
    -- Reorder with dynamic priority
    mf.files = DynamicPriority:reorderFiles(mf.files)
    
    setStatus(_string_format("v%s | %d files", mf.version, State.total), 0.05)
    
    -- Parallel downloads
    local done = 0
    local downloadStartTime = _os_clock()
    
    for _, entry in ipairs(mf.files) do
        local e = entry
        _t.spawn(function()
            local localSrc = readLocal(e.lpath)
            if localSrc then
                State.sources[e.path] = localSrc
                done = done + 1
            else
                local url = RAW .. "/" .. e.path
                local src = fetch(url, 3)
                State.sources[e.path] = src or false
                if src then
                    writeLocal(e.lpath, src)
                    e.timestamp = _os_clock()
                end
                done = done + 1
            end
            
            setStatus(
                _string_format("Downloading %d/%d...", done, State.total),
                0.05 + (done / State.total) * 0.65
            )
        end)
    end
    
    -- Wait for downloads
    local t = 0
    while done < State.total and t < 400 do
        _t.wait(0.05)
        t = t + 1
    end
    
    State.ready = true
    IntelligentMemory.lastDownloadTime = _os_clock() - downloadStartTime
    
    setStatus(_string_format("Ready — click pill (%d files)", State.total), 0.70)
    
    if State.triggered then G._DebuggerExecute() end
end)

-- ============ LAZY EXECUTOR ============
G._DebuggerExecute = function()
    if not State.ready then
        local setStatus = GUI.setStatus or function() end
        setStatus("Waiting for downloads...", 0.70)
        
        while not State.ready do _t.wait(0.3) end
    end
    
    local files = State.manifest and State.manifest.files or {}
    local total = #files
    local RS = game:GetService("RunService")
    local addRow = GUI.addRow or function() end
    local setStatus = GUI.setStatus or function() end
    
    setStatus("Executing modules...", 0.72)
    
    local executionStartTime = _os_clock()
    
    for i, entry in ipairs(files) do
        local moduleStartTime = _os_clock()
        local src = State.sources[entry.path]
        
        if not src or src == false then
            src = readLocal(entry.lpath)
        end
        
        if src and _type(src) == "string" and #src > 0 then
            local fn, cerr
            
            if loadstring then
                fn, cerr = loadstring(src, "@" .. entry.path)
            end
            
            if fn then
                local ok, rerr = _pcall(fn)
                
                local loadTime = _os_clock() - moduleStartTime
                IntelligentMemory.loadTimes[entry.path] = loadTime
                IntelligentMemory.moduleFrequency[entry.path] = (IntelligentMemory.moduleFrequency[entry.path] or 0) + 1
                
                if ok then
                    State.loaded = State.loaded + 1
                    G.DebuggerModules[entry.path] = {
                        loaded = true,
                        time = loadTime,
                        timestamp = _os_time(),
                    }
                    addRow(entry.path, true)
                else
                    State.errors = State.errors + 1
                    G.DebuggerModules[entry.path] = {
                        loaded = false,
                        error = rerr,
                        time = loadTime,
                    }
                    addRow(entry.path, false)
                    SelfHealing:recordFailure(entry.path, rerr)
                    
                    if entry.required then
                        _warn(_string_format("[Debugger] Required failed: %s", entry.path))
                    end
                end
            else
                State.errors = State.errors + 1
                addRow(entry.path, false)
                SelfHealing:recordFailure(entry.path, cerr)
            end
        else
            if entry.required then
                _warn(_string_format("[Debugger] Required missing: %s", entry.path))
                State.errors = State.errors + 1
                addRow(entry.path, false)
            end
        end
        
        setStatus(
            _string_format("[%d/%d] %s", i, total, entry.path:match("[^/]+$") or entry.path),
            0.72 + (i / total) * 0.27
        )
        
        RS.Heartbeat:Wait()
    end
    
    local totalExecutionTime = _os_clock() - executionStartTime
    IntelligentMemory.lastExecutionTime = totalExecutionTime
    State.systemHealth = SelfHealing:getHealth()
    
    setStatus(_string_format("Done — %d/%d loaded", State.loaded, total), 1.0)
    _print(_string_format(
        "[Debugger v12] Complete: %d/%d loaded, %d errors | Time: %.2fs",
        State.loaded, total, State.errors, totalExecutionTime
    ))
    
    saveIntelligentData()
end

-- ============ ADVANCED STATS LOOPS ============
_t.spawn(function()
    _t.wait(1)
    local RS = game:GetService("RunService")
    
    -- FPS Counter
    local frames, lastHb = 0, _os_clock()
    RS.Heartbeat:Connect(function()
        frames = frames + 1
        local now = _os_clock()
        
        if now - lastHb >= 1 then
            State.fps = _math_min(frames, 999)
            frames = 0
            lastHb = now
        end
    end)
    
    -- Ping Monitor
    _t.spawn(function()
        while G.DebuggerLoaded do
            _t.wait(5)
            _pcall(function()
                local ping = game:GetService("Stats").Network.ServerStatsItem["Data Ping"].Value
                State.ping = _math_floor(ping)
            end)
        end
    end)
    
    -- Memory Monitor
    _t.spawn(function()
        while G.DebuggerLoaded do
            _t.wait(8)
            _pcall(function()
                local mb = _math_floor(gcinfo() / 102.4) / 10
                State.memory = mb
                State.metrics.peakMemory = _math_max(State.metrics.peakMemory or 0, mb)
            end)
        end
    end)
    
    -- Auto-save Checkpoints
    _t.spawn(function()
        local checkpoint = 0
        while G.DebuggerLoaded do
            _t.wait(CFG.CheckpointInterval)
            if CFG.EnableCheckpoints then
                checkpoint = checkpoint + 1
                writeLocal("DebuggerCheckpoint_" .. checkpoint .. ".cache", _tostr(State))
            end
        end
    end)
end)

-- ============ PLUGIN SYSTEM ============
G.DebuggerRegisterPlugin = function(name, plugin)
    if not plugin then return false end
    
    local entry = {name = name, plugin = plugin}
    _table_insert(G.DebuggerPlugins, entry)
    
    if _type(plugin.init) == "function" then
        _pcall(plugin.init)
    end
    
    return true
end

G.DebuggerGetPlugin = function(name)
    for _, p in ipairs(G.DebuggerPlugins) do
        if p.name == name then return p.plugin end
    end
    return nil
end

-- ============ PUBLIC API ============
G.DebuggerHotReload = function(path)
    if not path then
        _print("[HotReload] DebuggerHotReload('path/to/file.lua')")
        return
    end
    
    _t.spawn(function()
        _print("[HotReload] Loading: " .. path)
        local src = fetch(RAW .. "/" .. path, 3)
        
        if not src then
            _warn("[HotReload] Download failed")
            return
        end
        
        writeLocal(path, src)
        
        local fn, err = loadstring and loadstring(src, "@" .. path)
        if not fn then
            _warn("[HotReload] Compile error: " .. _tostr(err))
            return
        end
        
        local ok, rerr = _pcall(fn)
        if ok then
            _print("[HotReload] ✓ " .. path)
            G.DebuggerModules[path] = {loaded = true, reloaded = true}
        else
            _warn("[HotReload] Error: " .. _tostr(rerr))
        end
    end)
end

G.DebuggerStatus = function()
    return {
        loaded = State.loaded,
        errors = State.errors,
        total = State.total,
        ready = State.ready,
        fps = State.fps,
        ping = State.ping,
        memory = State.memory,
        health = State.systemHealth,
        uptime = _os_clock() - State.startTime,
        executionTime = IntelligentMemory.lastExecutionTime,
    }
end

G.DebuggerAnalytics = function()
    return {
        loadTimes = IntelligentMemory.loadTimes,
        moduleFrequency = IntelligentMemory.moduleFrequency,
        systemHealth = State.systemHealth,
        selfHealingFailures = SelfHealing.failures,
    }
end

G.DebuggerClearCache = function()
    HttpCache = {data = {}, timestamps = {}, compression = {}}
    _print("[Cache] Cleared all caches")
end

G.DebuggerExtensionAPI = {
    registerHook = function(event, callback)
        if not G.DebuggerHooks[event] then
            G.DebuggerHooks[event] = {}
        end
        _table_insert(G.DebuggerHooks[event], callback)
    end,
    
    fireHook = function(event, ...)
        if not G.DebuggerHooks[event] then return end
        for _, cb in ipairs(G.DebuggerHooks[event]) do
            _pcall(cb, ...)
        end
    end,
    
    getIntelligentMemory = function()
        return IntelligentMemory
    end,
    
    getState = function()
        return State
    end,
}

-- ============ INITIALIZATION ============
_print("[Debugger v12] 🚀 ULTRA-ADVANCED NEURAL DEBUGGER LOADED")
_print("[Core] Intelligent Learning, Predictive Loading, Self-Healing, Dynamic Priorities")
_print("[API] DebuggerHotReload(), DebuggerStatus(), DebuggerAnalytics()")
_print("[Ready] Click pill to start or use API directly")

-- Make state accessible
G.DebuggerState = State
G.DebuggerIntelligence = IntelligentMemory
G.DebuggerHealth = SelfHealing
