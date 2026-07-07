-- ANTIGRAVITY AUTO-DEBUGGER v9
-- https://github.com/svx6/debugging-tool
-- Paste this ONE file in your executor and run it.

local _env = getfenv and getfenv(0) or _G or {}

local function safe_get(name)
    local ok, val = pcall(function() return _env[name] end)
    if ok and val ~= nil then return val end
    return nil
end

local _type = type
local _pcall = pcall
local _tostring = tostring
local _print = print
local _warn = warn or print

-- SAFE GLOBALS (Prevent "attempt to call a nil value" in ALL executors)
local _getgenv = safe_get("getgenv")
local _syn = safe_get("syn")
local _request = safe_get("request")
local _http = safe_get("http")
local _http_request = safe_get("http_request")
local _HttpGet = safe_get("HttpGet")
local _task = safe_get("task")
local _readfile = safe_get("readfile")
local _writefile = safe_get("writefile")
local _makefolder = safe_get("makefolder")
local _isfolder = safe_get("isfolder")
local _unpack = safe_get("unpack") or (_type(table)=="table" and table.unpack)

-- RESOLVE GETGENV
local getg
if _type(_getgenv) == "function" then
    getg = _getgenv
elseif _type(_syn) == "table" and _type((_syn).getgenv) == "function" then
    getg = _syn.getgenv
else
    getg = function() return _env end
end

local _g = getg()
if _g.DebuggerLoaded then
    _warn("[Debugger v9]: Already running. Close GUI first.")
    return
end
_g.DebuggerLoaded = true
_g.DebuggerScanners = {}
_g.DebuggerModules = {}

-- TASK POLYFILL
local _t = _task
if not _t or _type(_t) ~= "table" then
    local RS = game:GetService("RunService")
    local up = _unpack or function(...) return ... end
    _t = {
        spawn = function(f,...) local a={...}; return coroutine.wrap(function() f(up(a)) end)() end,
        wait  = function(t) local s=os.clock(); repeat RS.Heartbeat:Wait() until os.clock()-s>=(t or 0); return os.clock()-s end,
        delay = function(t,f,...) local a={...}; coroutine.wrap(function()
            local s=os.clock(); repeat RS.Heartbeat:Wait() until os.clock()-s>=(t or 0); f(up(a)) end)() end,
        defer = function(f,...) local a={...}; coroutine.wrap(function() RS.Heartbeat:Wait(); f(up(a)) end)() end,
    }
    _g.task = _t
end

-- CONFIG
local CFG = {
    Owner        = "svx6",
    Repo         = "debugging-tool",
    Branch       = "main",
    ManifestFile = "manifest.json",
    CacheFile    = "debugger_cache.json",
    LocalVer     = "9.0.0",
    AutoDiscover = true,
    ParallelDL   = true,
    UseCache     = true,
    RetryCount   = 3,
    RetryDelay   = 0.8,
    YieldBetween = 0.06,
    HeavyYield   = 0.14,
    HeavyModules = {"gui.lua", "ai_analyzer", "bug_finder", "core_debugger"},
}

local RAW_BASE = string.format("https://raw.githubusercontent.com/%s/%s/%s", CFG.Owner, CFG.Repo, CFG.Branch)
local API_BASE = string.format("https://api.github.com/repos/%s/%s", CFG.Owner, CFG.Repo)

-- HTTP ENGINE
local function httpGet(url)
    local methods = {}
    if _type(_syn) == "table" and _type((_syn).request) == "function" then
        table.insert(methods, function()
            local ok, r = _pcall(_syn.request, {Url=url, Method="GET", Headers={["User-Agent"]="AntigravityDebugger/9"}})
            if ok and r and r.StatusCode == 200 then return r.Body end
            if ok and r and r.StatusCode then error("HTTP ".._tostring(r.StatusCode)) end
        end)
    end
    if _type(_request) == "function" then
        table.insert(methods, function()
            local ok, r = _pcall(_request, {Url=url, Method="GET", Headers={["User-Agent"]="AntigravityDebugger/9"}})
            if ok and r and r.StatusCode == 200 then return r.Body end
            if ok and r and r.StatusCode then error("HTTP ".._tostring(r.StatusCode)) end
        end)
    end
    if _type(_http) == "table" and _type((_http).request) == "function" then
        table.insert(methods, function()
            local ok, r = _pcall(_http.request, {Url=url, Method="GET"})
            if ok and r and r.StatusCode == 200 then return r.Body end
        end)
    end
    if _type(_http_request) == "function" then
        table.insert(methods, function()
            local ok, r = _pcall(_http_request, {Url=url, Method="GET"})
            if ok and r and r.StatusCode == 200 then return r.Body end
        end)
    end
    if _type(_HttpGet) == "function" then
        table.insert(methods, function()
            local ok, b = _pcall(_HttpGet, game, url)
            if ok and _type(b) == "string" and #b > 0 then return b end
        end)
    end
    table.insert(methods, function()
        local ok, b = _pcall(function() return game:HttpGetAsync(url) end)
        if ok and _type(b) == "string" and #b > 0 then return b end
    end)

    for _, fn in ipairs(methods) do
        local ok, body = _pcall(fn)
        if ok and _type(body) == "string" and #body > 0 then return true, body end
    end
    return false, "No HTTP method succeeded."
end

local function fetch(url, retries, quiet)
    retries = retries or CFG.RetryCount
    local lastErr = "unknown"
    for attempt = 1, retries do
        local ok, body = httpGet(url)
        if ok and body and #body > 5 then return body end
        lastErr = _tostring(body)
        if attempt < retries then _t.wait(CFG.RetryDelay * attempt) end
    end
    if not quiet then
        _warn(string.format("[Boot] FAIL %s (%d tries): %s", url:match("[^/]+$") or url, retries, lastErr))
    end
    return nil
end

-- CACHE
local hashCache = {}
local function loadHashCache()
    _pcall(function()
        if _type(_readfile) ~= "function" then return end
        local raw = _readfile(CFG.CacheFile)
        if not raw or #raw < 3 then return end
        for p, s in raw:gmatch('"([^"]+)"%s*:%s*"([^"]+)"') do hashCache[p] = s end
    end)
end
local function saveHashCache(entries)
    _pcall(function()
        if _type(_writefile) ~= "function" then return end
        local parts = {}
        for p, s in pairs(entries) do
            table.insert(parts, string.format('"%s":"%s"', p, s))
        end
        _writefile(CFG.CacheFile, "{" .. table.concat(parts, ",") .. "}")
    end)
end
local function writeLocal(localPath, content)
    _pcall(function()
        if _type(_writefile) ~= "function" then return end
        local dir = localPath:match("^(.+)/[^/]+$")
        if dir and _type(_makefolder) == "function" and _type(_isfolder) == "function" then
            local built = ""
            for seg in dir:gmatch("[^/]+") do
                built = built == "" and seg or (built .. "/" .. seg)
                if not _isfolder(built) then _pcall(_makefolder, built) end
            end
        end
        _writefile(localPath, content)
    end)
end
local function readLocal(localPath)
    if _type(_readfile) ~= "function" then return nil end
    local ok, c = _pcall(_readfile, localPath)
    return (ok and _type(c) == "string" and #c > 5) and c or nil
end

-- MANIFEST
local function parseManifest(json)
    if not json or #json < 5 then return nil, "Empty" end
    local version = json:match('"version"%s*:%s*"([^"]+)"') or "?"
    local files, fileSet = {}, {}
    for block in json:gmatch("{[^{}]+}") do
        local path      = block:match('"path"%s*:%s*"([^"]+)"')
        local localPath = block:match('"local"%s*:%s*"([^"]+)"') or path
        local required  = block:match('"required"%s*:%s*true') and true or false
        local disabled  = block:match('"disabled"%s*:%s*true') and true or false
        local priority  = tonumber(block:match('"priority"%s*:%s*(%d+)')) or 50
        local group     = block:match('"group"%s*:%s*"([^"]+)"') or "module"
        local desc      = block:match('"description"%s*:%s*"([^"]+)"') or ""
        if path and not disabled and not fileSet[path] then
            fileSet[path] = true
            table.insert(files, {path=path, localPath=localPath, required=required,
                priority=priority, group=group, desc=desc})
        end
    end
    if #files == 0 then return nil, "No files in manifest" end
    table.sort(files, function(a, b)
        if a.priority ~= b.priority then return a.priority < b.priority end
        return a.path < b.path
    end)
    return {version=version, files=files, fileSet=fileSet}
end

local function autoDiscover(manifest)
    local treeUrl = string.format("%s/git/trees/%s?recursive=1", API_BASE, CFG.Branch)
    local body = fetch(treeUrl, 2, true)
    if not body then return end
    local discovered = 0
    for path in body:gmatch('"path"%s*:%s*"([^"]+%.lua)"') do
        if path ~= "main.lua" and not manifest.fileSet[path] then
            local priority = 50
            if path == "core.lua" then priority = 0 elseif path == "gui.lua" then priority = 99 end
            table.insert(manifest.files, {path=path, localPath=path, required=false,
                priority=priority, group=path:match("^modules/") and "module" or "root",
                desc="Auto-discovered"})
            manifest.fileSet[path] = true
            discovered = discovered + 1
        end
    end
    if discovered > 0 then
        table.sort(manifest.files, function(a, b)
            if a.priority ~= b.priority then return a.priority < b.priority end
            return a.path < b.path
        end)
        _print(string.format("[Boot] Auto-discovered %d new file(s)", discovered))
    end
end

-- GITHUB SYNC
local GH = {
    Repo="svx6/debugging-tool", Branch="main", AutoSync=true,
    SyncStatus="Idle", LastSync="Never", RemoteVersion=nil,
    LocalVersion=CFG.LocalVer, SyncLog={},
    FilesUpdated=0, FilesSkipped=0, SyncInProgress=false,
}
local function ghLog(msg, isErr)
    local line = string.format("[%s] %s", os.date("%H:%M:%S"), msg)
    table.insert(GH.SyncLog, 1, line)
    while #GH.SyncLog > 50 do table.remove(GH.SyncLog) end
    if isErr then _warn("[GitHubSync] " .. msg) else _print("[GitHubSync] " .. msg) end
    _pcall(function()
        local Data = getg().DebuggerSharedData
        if Data and _type(Data.Publish) == "function" then Data:Publish("OnGitHubStatus", GH) end
    end)
end
local function versionGT(a, b)
    if not a or not b then return false end
    local function parts(v)
        local p = {}
        for n in _tostring(v):gmatch("%d+") do table.insert(p, tonumber(n) or 0) end
        while #p < 3 do table.insert(p, 0) end
        return p
    end
    local pa, pb = parts(a), parts(b)
    for i = 1, 3 do
        if pa[i] > pb[i] then return true end
        if pa[i] < pb[i] then return false end
    end
    return false
end
local function doGitHubSync(forcePull)
    if GH.SyncInProgress then ghLog("Sync already running.", true); return false end
    GH.SyncInProgress = true; GH.FilesUpdated = 0; GH.FilesSkipped = 0
    GH.SyncStatus = "Connecting..."
    ghLog("Sync start: " .. GH.Repo .. " @ " .. GH.Branch)
    local mSrc = fetch(RAW_BASE .. "/" .. CFG.ManifestFile, 3, true)
    if not mSrc then
        ghLog("Cannot reach GitHub.", true); GH.SyncStatus = "Error: offline"
        GH.SyncInProgress = false; return false
    end
    local mf, mErr = parseManifest(mSrc)
    if not mf then
        ghLog("Manifest error: " .. _tostring(mErr), true)
        GH.SyncStatus = "Error: bad manifest"
        GH.SyncInProgress = false; return false
    end
    ghLog(string.format("Manifest OK v%s, %d files", mf.version, #mf.files))
    GH.RemoteVersion = mf.version
    local localVerRaw = readLocal("VERSION") or CFG.LocalVer
    GH.LocalVersion = localVerRaw:gsub("%s+", "")
    if not forcePull and not versionGT(mf.version, GH.LocalVersion) then
        ghLog("Up to date v" .. GH.LocalVersion)
        GH.SyncStatus = "Up to date v" .. GH.LocalVersion
        GH.LastSync = os.date("%H:%M:%S"); GH.SyncInProgress = false; return true
    end
    ghLog(forcePull and "Force pull." or string.format("Update v%s->v%s downloading...", GH.LocalVersion, mf.version))
    local downloaded = 0
    for i, entry in ipairs(mf.files) do
        ghLog(string.format("[%d/%d] %s", i, #mf.files, entry.path))
        local src = fetch(RAW_BASE .. "/" .. entry.path, 3, true)
        if src and #src > 0 then
            writeLocal(entry.localPath, src)
            downloaded = downloaded + 1; GH.FilesUpdated = downloaded
            ghLog("  OK: " .. entry.localPath)
        else
            ghLog("  FAIL: " .. entry.path, true); GH.FilesSkipped = GH.FilesSkipped + 1
        end
        _t.wait(0.1)
    end
    if downloaded > 0 then
        _pcall(function()
            if _type(_writefile) == "function" then _writefile("VERSION", mf.version) end
        end)
        GH.LocalVersion = mf.version
    end
    GH.LastSync = os.date("%H:%M:%S")
    GH.SyncStatus = string.format("OK v%s %s", mf.version, GH.LastSync)
    GH.SyncInProgress = false
    ghLog(string.format("Sync done: %d/%d updated, %d skipped", downloaded, #mf.files, GH.FilesSkipped))
    return true
end
_g.DebuggerGitHub = GH
_g.DebuggerGitHubPull = function(force) _t.spawn(function() doGitHubSync(force == true) end) end

-- EXECUTOR
local function execSource(src, chunkName)
    local fn, compErr
    if loadstring then
        fn, compErr = loadstring(src, "@" .. chunkName)
    else
        return false, "loadstring is not supported on this executor"
    end
    if not fn then return false, "Compile error: " .. _tostring(compErr) end
    local ok, runErr = _pcall(fn)
    if not ok then return false, "Runtime error: " .. _tostring(runErr) end
    return true
end

-- BOOT UI
local Boot = {}
do
    local uiOk = _pcall(function()
        local TW     = game:GetService("TweenService")
        local LP     = game:GetService("Players").LocalPlayer
        local pg     = LP and LP:FindFirstChildOfClass("PlayerGui")
        local SPRING = TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
        if not pg then return end

        local sg = Instance.new("ScreenGui")
        sg.Name = "DebuggerBoot9"; sg.ResetOnSpawn = false
        sg.DisplayOrder = 1001; sg.IgnoreGuiInset = true; sg.Parent = pg

        local panel = Instance.new("Frame")
        panel.Size = UDim2.new(0,330,0,72); panel.Position = UDim2.new(0.5,-165,1,80)
        panel.BackgroundColor3 = Color3.fromRGB(8,10,20)
        panel.BorderSizePixel = 0; panel.Parent = sg
        Instance.new("UICorner", panel).CornerRadius = UDim.new(0,12)
        local stroke = Instance.new("UIStroke", panel)
        stroke.Color = Color3.fromRGB(80,100,240); stroke.Thickness = 1.2

        local accent = Instance.new("Frame", panel)
        accent.Size = UDim2.new(0,3,0,72); accent.Position = UDim2.new(0,0,0,0)
        accent.BackgroundColor3 = Color3.fromRGB(80,100,240); accent.BorderSizePixel = 0
        Instance.new("UICorner", accent).CornerRadius = UDim.new(0,3)

        local dot = Instance.new("Frame", panel)
        dot.Size = UDim2.new(0,8,0,8); dot.Position = UDim2.new(0,16,0.5,-4)
        dot.BackgroundColor3 = Color3.fromRGB(80,100,240); dot.BorderSizePixel = 0
        Instance.new("UICorner", dot).CornerRadius = UDim.new(1,0)

        local title = Instance.new("TextLabel", panel)
        title.Size = UDim2.new(1,-36,0,20); title.Position = UDim2.new(0,34,0,10)
        title.BackgroundTransparency = 1; title.Text = "ANTIGRAVITY AUTO-DEBUGGER  v9"
        title.TextColor3 = Color3.fromRGB(200,210,255); title.Font = Enum.Font.GothamBold
        title.TextSize = 11; title.TextXAlignment = Enum.TextXAlignment.Left

        local status = Instance.new("TextLabel", panel)
        status.Size = UDim2.new(1,-36,0,14); status.Position = UDim2.new(0,34,0,32)
        status.BackgroundTransparency = 1; status.Text = "Connecting to GitHub..."
        status.TextColor3 = Color3.fromRGB(80,100,150); status.Font = Enum.Font.GothamMedium
        status.TextSize = 9; status.TextXAlignment = Enum.TextXAlignment.Left

        local track = Instance.new("Frame", panel)
        track.Size = UDim2.new(1,-24,0,3); track.Position = UDim2.new(0,12,0,56)
        track.BackgroundColor3 = Color3.fromRGB(25,30,55); track.BorderSizePixel = 0
        Instance.new("UICorner", track).CornerRadius = UDim.new(1,0)

        local bar = Instance.new("Frame", track)
        bar.Size = UDim2.new(0,0,1,0); bar.Position = UDim2.new(0,0,0,0)
        bar.BackgroundColor3 = Color3.fromRGB(80,100,240); bar.BorderSizePixel = 0
        Instance.new("UICorner", bar).CornerRadius = UDim.new(1,0)

        TW:Create(panel, SPRING, {Position=UDim2.new(0.5,-165,1,-82)}):Play()

        _t.spawn(function()
            while panel.Parent do
                TW:Create(dot, TweenInfo.new(0.5), {BackgroundTransparency=0}):Play(); _t.wait(0.5)
                TW:Create(dot, TweenInfo.new(0.5), {BackgroundTransparency=0.75}):Play(); _t.wait(0.5)
            end
        end)
        _t.spawn(function()
            local colors = {Color3.fromRGB(80,100,240), Color3.fromRGB(100,200,160), Color3.fromRGB(200,100,240), Color3.fromRGB(240,160,60)}
            local i = 1
            while panel.Parent do
                _t.wait(2); i = (i % #colors) + 1
                TW:Create(stroke, TweenInfo.new(1), {Color=colors[i]}):Play()
                TW:Create(accent, TweenInfo.new(1), {BackgroundColor3=colors[i]}):Play()
                TW:Create(dot,    TweenInfo.new(1), {BackgroundColor3=colors[i]}):Play()
                TW:Create(bar,    TweenInfo.new(1), {BackgroundColor3=colors[i]}):Play()
            end
        end)

        Boot.sg = sg; Boot.panel = panel; Boot.status = status
        Boot.bar = bar; Boot.TW = TW; Boot.active = true
    end)
    if not uiOk then Boot.active = false end
end

local function bootMsg(msg, progress)
    _print("[Boot] " .. msg)
    if Boot.active then
        _pcall(function() Boot.status.Text = msg end)
        if progress and Boot.bar then
            _pcall(function()
                Boot.TW:Create(Boot.bar, TweenInfo.new(0.3, Enum.EasingStyle.Quad),
                    {Size=UDim2.new(math.clamp(progress,0,1),0,1,0)}):Play()
            end)
        end
    end
end
local function dismissBoot(finalMsg, isError)
    if not Boot.active then return end
    Boot.active = false
    _t.spawn(function()
        local col = isError and Color3.fromRGB(200,60,60) or Color3.fromRGB(60,200,120)
        _pcall(function()
            Boot.TW:Create(Boot.bar, TweenInfo.new(0.3), {Size=UDim2.new(1,0,1,0), BackgroundColor3=col}):Play()
            Boot.status.Text = finalMsg or "Done"; Boot.status.TextColor3 = col
        end)
        _t.wait(1.8)
        _pcall(function()
            Boot.TW:Create(Boot.panel, TweenInfo.new(0.3,Enum.EasingStyle.Quad,Enum.EasingDirection.In), {Position=UDim2.new(0.5,-165,1,80)}):Play()
        end)
        _t.wait(0.4)
        _pcall(function() Boot.sg:Destroy() end)
    end)
end

local function downloadAll(files)
    local results = {}; local total = #files; local finished = 0
    if CFG.ParallelDL then
        for _, entry in ipairs(files) do
            local path = entry.path; results[path] = false
            _t.spawn(function()
                local src = nil
                if CFG.UseCache and hashCache[path] then src = readLocal(entry.localPath) end
                if not src then src = fetch(RAW_BASE .. "/" .. path, CFG.RetryCount, true) end
                results[path] = src or false; finished = finished + 1
            end)
        end
        local timeout, elapsed = 30, 0
        while finished < total and elapsed < timeout do
            _t.wait(0.08); elapsed = elapsed + 0.08
            bootMsg(string.format("Downloading... %d/%d", finished, total), finished/total*0.7)
        end
    else
        for i, entry in ipairs(files) do
            local src = fetch(RAW_BASE .. "/" .. entry.path, CFG.RetryCount, true)
            results[entry.path] = src or false; finished = finished + 1
            bootMsg(string.format("[%d/%d] %s", i, total, entry.path:match("[^/]+$")), i/total*0.7)
            _t.wait(0.03)
        end
    end
    return results
end

_print("-- ANTIGRAVITY AUTO-DEBUGGER v9 -- github.com/svx6/debugging-tool --")
loadHashCache()

bootMsg("Fetching manifest...", 0.02)
local manifestSrc = fetch(RAW_BASE .. "/" .. CFG.ManifestFile, 4)
if not manifestSrc then
    bootMsg("GitHub unreachable - checking cache...", 0.01)
    manifestSrc = readLocal(CFG.ManifestFile)
    if manifestSrc then
        _print("[Boot] Using cached manifest (offline mode)")
    else
        _warn("[Boot] FATAL: No GitHub + no local manifest. Enable HTTP in executor.")
        dismissBoot("GitHub unreachable", true)
        getg().DebuggerLoaded = nil; return
    end
else
    writeLocal(CFG.ManifestFile, manifestSrc)
end

local manifest, parseErr = parseManifest(manifestSrc)
if not manifest then
    _warn("[Boot] FATAL: Manifest parse failed: " .. _tostring(parseErr))
    dismissBoot("Bad manifest", true); getg().DebuggerLoaded = nil; return
end

bootMsg(string.format("Manifest v%s - %d files", manifest.version, #manifest.files), 0.05)
if CFG.AutoDiscover then
    bootMsg("Scanning repo...", 0.08); autoDiscover(manifest)
end
bootMsg(string.format("Downloading %d files...", #manifest.files), 0.10)
local sources = downloadAll(manifest.files)
bootMsg("Executing modules...", 0.72)

local executed, skipped, errored = 0, 0, 0
local newHashes = {}
local total     = #manifest.files
local startTime = os.clock()

for i, entry in ipairs(manifest.files) do
    local src = sources[entry.path]
    local pct = 0.72 + (i / total) * 0.26
    if not src or src == false then
        local cached = readLocal(entry.localPath)
        if cached then
            src = cached
            _print(string.format("  [%d/%d] cache: %s", i, total, entry.path))
        else
            if entry.required then
                _warn(string.format("  [%d/%d] REQUIRED MISSING: %s", i, total, entry.path))
                errored = errored + 1
            else
                _print(string.format("  [%d/%d] skip: %s", i, total, entry.path))
                skipped = skipped + 1
            end
            _g.DebuggerModules[entry.path] = {loaded=false, time=0, error="Download failed"}
        end
    end

    if src and src ~= false then
        writeLocal(entry.localPath, src)
        newHashes[entry.path] = _tostring(#src)
        bootMsg(string.format("[%d/%d] %s", i, total, entry.path:match("[^/]+%.?[^/]*$") or entry.path), pct)
        local t0 = os.clock()
        local ok, err = execSource(src, entry.path)
        local dt = os.clock() - t0
        if ok then
            executed = executed + 1
            _g.DebuggerModules[entry.path] = {loaded=true, time=dt, error=nil}
            _print(string.format("  [%d/%d] OK %s (%.0fms)", i, total, entry.path, dt*1000))
        else
            errored = errored + 1
            _g.DebuggerModules[entry.path] = {loaded=false, time=dt, error=err}
            if entry.required then
                _warn(string.format("  [%d/%d] REQUIRED FAIL: %s\n     %s", i, total, entry.path, err))
            else
                _warn(string.format("  [%d/%d] ERR %s\n     %s", i, total, entry.path, err))
            end
        end
        local isHeavy = false
        for _, name in ipairs(CFG.HeavyModules) do
            if entry.path:find(name, 1, true) then isHeavy = true; break end
        end
        _t.wait(isHeavy and CFG.HeavyYield or CFG.YieldBetween)
    end
end

saveHashCache(newHashes)
local totalTime = os.clock() - startTime
_print(string.format("-- Boot done %.2fs | v%s | OK:%d skip:%d err:%d --", totalTime, manifest.version, executed, skipped, errored))
dismissBoot(string.format("v%s - %d/%d (%.1fs)", manifest.version, executed, total, totalTime), errored > 0 and executed == 0)

if GH.AutoSync then
    _t.spawn(function()
        _t.wait(4)
        ghLog("Auto-sync starting...")
        doGitHubSync(false)
    end)
end

_t.spawn(function()
    _t.wait(600)
    while getg().DebuggerLoaded do
        local newSrc = fetch(RAW_BASE .. "/" .. CFG.ManifestFile, 2, true)
        if newSrc then
            local m = parseManifest(newSrc)
            if m and versionGT(m.version, manifest.version) then
                ghLog(string.format("Update available: v%s -> v%s", manifest.version, m.version))
            end
        end
        _t.wait(600)
    end
end)

_g.DebuggerHotReload = function(path)
    if not path then _print("[HotReload] Usage: DebuggerHotReload('file.lua')"); return end
    _print("[HotReload] Reloading: " .. path)
    local src = fetch(RAW_BASE .. "/" .. path, 3)
    if not src then _warn("[HotReload] Download failed: " .. path); return end
    writeLocal(path, src)
    local ok, err = execSource(src, path)
    if ok then
        _print("[HotReload] OK: " .. path)
        _g.DebuggerModules[path] = {loaded=true, time=0, reloaded=true}
    else
        _warn("[HotReload] Error " .. path .. ": " .. _tostring(err))
    end
end

_t.spawn(function()
    local Data, tries = nil, 0
    repeat _t.wait(0.15); Data = getg().DebuggerSharedData; tries = tries + 1
    until Data or tries >= 60
    if not Data then _warn("[Boot] Core not found - scan loop aborted."); return end
    local RS = game:GetService("RunService")
    local scannerErrors = {}
    _t.wait(3)
    local startTick = os.clock()
    _t.spawn(function()
        while getg().DebuggerLoaded do
            _t.wait(1)
            _pcall(function() Data.Stats.Uptime = math.floor(os.clock() - startTick) end)
        end
    end)
    local lastHb, frames = os.clock(), 0
    RS.Heartbeat:Connect(function()
        frames = frames + 1
        local now = os.clock()
        if now - lastHb >= 1 then
            _pcall(function() Data.Stats.FPS = math.min(frames, 999) end)
            frames = 0; lastHb = now
        end
    end)
    while getg().DebuggerLoaded do
        _t.spawn(function()
            _pcall(function()
                local SS = game:GetService("Stats")
                Data.Stats.Ping = math.floor(SS.Network.ServerStatsItem["Data Ping"].Value)
            end)
        end)
        _t.wait()
        _pcall(function() Data.Stats.InstanceCount = #game:GetDescendants() end)
        _t.wait()
        _pcall(function() Data.Stats.MemoryMB = math.floor(gcinfo() / 102.4) / 10 end)
        Data.Stats.ScanCount = (Data.Stats.ScanCount or 0) + 1
        local scanners = getg().DebuggerScanners or {}
        for idx, scanner in ipairs(scanners) do
            _t.wait()
            local ok, err = _pcall(scanner)
            if not ok then
                scannerErrors[idx] = (scannerErrors[idx] or 0) + 1
                if scannerErrors[idx] == 3 then
                    _warn(string.format("[Scan] Scanner #%d failing: %s", idx, _tostring(err)))
                end
                if scannerErrors[idx] > 10 then
                    table.remove(scanners, idx)
                    _warn(string.format("[Scan] Scanner #%d removed after 10 errors.", idx)); break
                end
            else
                scannerErrors[idx] = 0
            end
        end
        local interval = (Data.Settings and Data.Settings.ScanInterval) or 3
        _t.wait(interval)
    end
end)

_print("[Boot] v9 complete. DebuggerHotReload('file.lua') | DebuggerGitHubPull()")

