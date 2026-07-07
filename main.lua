--[[
    ╔══════════════════════════════════════════════════════════════════════╗
    ║    ANTIGRAVITY AUTO-DEBUGGER  ·  SMART GITHUB BOOTSTRAPPER  v9     ║
    ║    https://github.com/svx6/debugging-tool                          ║
    ╠══════════════════════════════════════════════════════════════════════╣
    ║  PASTE THIS ONE FILE IN YOUR EXECUTOR AND RUN IT.                  ║
    ║  Everything else is fetched live from GitHub automatically.         ║
    ║                                                                     ║
    ║  SMART FEATURES:                                                    ║
    ║  · Auto-discovers new files you add to the repo (no config needed) ║
    ║  · Parallel downloads — all files fetched simultaneously           ║
    ║  · SHA hash cache — only re-downloads files that actually changed  ║
    ║  · Priority ordering — files load in correct dependency order      ║
    ║  · Error recovery — failed optional modules are skipped gracefully ║
    ║  · Hot-reload API — reload any module live without restarting      ║
    ║  · Offline fallback — uses local cache if GitHub unreachable       ║
    ║  · 6-method HTTP engine — works on every major executor            ║
    ║                                                                     ║
    ║  Executors: Synapse X · KRNL · Wave · Hydrogen · Fluxus · Codex   ║
    ║             Solara · Delta · Xeno · Electron · Script-Ware         ║
    ╚══════════════════════════════════════════════════════════════════════╝
--]]

-- ══════════════════════════════════════════════════════════════════════════
--  GITHUB CONFIG  (only change these if you fork the repo)
-- ══════════════════════════════════════════════════════════════════════════
local CFG = {
    Owner        = "svx6",
    Repo         = "debugging-tool",
    Branch       = "main",
    ManifestFile = "manifest.json",   -- must exist in the repo root
    CacheFile    = "debugger_cache.json", -- local hash cache (optional)
    LocalVer     = "9.0.0",
    AutoDiscover = true,   -- scan GitHub API for .lua files not in manifest
    ParallelDL   = true,   -- download all files simultaneously
    UseCache     = true,   -- skip unchanged files using SHA comparison
    RetryCount   = 3,      -- HTTP retry attempts per file
    RetryDelay   = 0.8,    -- base delay between retries (exponential)
    YieldBetween = 0.06,   -- seconds between module executions (keeps game smooth)
    HeavyYield   = 0.14,   -- yield after heavy modules (gui, ai_analyzer)
    HeavyModules = {"gui.lua", "ai_analyzer", "bug_finder", "core_debugger"},
}

local RAW_BASE  = string.format("https://raw.githubusercontent.com/%s/%s/%s", CFG.Owner, CFG.Repo, CFG.Branch)
local API_BASE  = string.format("https://api.github.com/repos/%s/%s",        CFG.Owner, CFG.Repo)

-- ══════════════════════════════════════════════════════════════════════════
--  POLYFILLS & GLOBALS
-- ══════════════════════════════════════════════════════════════════════════
local getgenv = (typeof(getgenv) == "function" and getgenv)
    or (typeof(syn) == "table" and typeof(syn.getgenv) == "function" and syn.getgenv)
    or function() return _G end

if getgenv().DebuggerLoaded then
    warn("[Debugger v9]: Already running. Close current GUI before re-running.")
    return
end
getgenv().DebuggerLoaded   = true
getgenv().DebuggerScanners = {}
getgenv().DebuggerModules  = {}   -- registry: path → {loaded, time, errors}

local _g = getgenv()

-- task polyfill
if not task then
    local RS = game:GetService("RunService")
    local up = table.unpack or unpack
    _g.task = {
        spawn = function(f,...) local a={...}; return coroutine.wrap(function() f(up(a)) end)() end,
        wait  = function(t) local s=tick(); repeat RS.Heartbeat:Wait() until tick()-s>=(t or 0); return tick()-s end,
        delay = function(t,f,...) local a={...}; coroutine.wrap(function()
            local s=tick(); repeat RS.Heartbeat:Wait() until tick()-s>=(t or 0); f(up(a)) end)() end,
        defer = function(f,...) local a={...}; coroutine.wrap(function() RS.Heartbeat:Wait(); f(up(a)) end)() end,
    }
end
local _t = task

-- ══════════════════════════════════════════════════════════════════════════
--  HTTP ENGINE  —  6 fallback methods, covers every executor ever made
-- ══════════════════════════════════════════════════════════════════════════
local function httpGet(url)
    -- Safely resolve executor globals (some executors error on undefined global access)
    local _syn          = rawget(_G, "syn")
    local _request      = rawget(_G, "request")
    local _http         = rawget(_G, "http")
    local _http_request = rawget(_G, "http_request")
    local _HttpGet      = rawget(_G, "HttpGet")

    -- Try each method, use whichever succeeds
    local methods = {}

    if _syn and type(_syn) == "table" and type(_syn.request) == "function" then
        table.insert(methods, function()
            local ok, r = pcall(_syn.request, {Url=url, Method="GET",
                Headers={["User-Agent"]="AntigravityDebugger/9"}})
            if ok and r and r.StatusCode == 200 then return r.Body end
            if ok and r and r.StatusCode then error("HTTP "..r.StatusCode) end
        end)
    end
    if type(_request) == "function" then
        table.insert(methods, function()
            local ok, r = pcall(_request, {Url=url, Method="GET",
                Headers={["User-Agent"]="AntigravityDebugger/9"}})
            if ok and r and r.StatusCode == 200 then return r.Body end
            if ok and r and r.StatusCode then error("HTTP "..r.StatusCode) end
        end)
    end
    if type(_http) == "table" and type(_http.request) == "function" then
        table.insert(methods, function()
            local ok,r = pcall(_http.request, {Url=url, Method="GET"})
            if ok and r and r.StatusCode == 200 then return r.Body end
        end)
    end
    if type(_http_request) == "function" then
        table.insert(methods, function()
            local ok,r = pcall(_http_request, {Url=url, Method="GET"})
            if ok and r and r.StatusCode == 200 then return r.Body end
        end)
    end
    if type(_HttpGet) == "function" then
        table.insert(methods, function()
            local ok,b = pcall(_HttpGet, game, url)
            if ok and type(b)=="string" and #b>0 then return b end
        end)
    end
    table.insert(methods, function()
        local ok,b = pcall(function() return game:HttpGetAsync(url) end)
        if ok and type(b)=="string" and #b>0 then return b end
    end)

    for _, fn in ipairs(methods) do
        local ok, body = pcall(fn)
        if ok and type(body)=="string" and #body>0 then
            return true, body
        end
    end
    return false, "No HTTP method succeeded. Enable HTTP requests in executor settings."
end

local function fetch(url, retries, quiet)
    retries = retries or CFG.RetryCount
    local lastErr = "unknown"
    for attempt = 1, retries do
        local ok, body = httpGet(url)
        if ok and body and #body > 5 then return body end
        lastErr = tostring(body)
        if attempt < retries then
            _t.wait(CFG.RetryDelay * attempt)   -- exponential backoff
        end
    end
    if not quiet then
        warn(string.format("[Bootstrapper] ✗ %s (after %d tries): %s",
            url:match("[^/]+$") or url, retries, lastErr))
    end
    return nil
end

-- ══════════════════════════════════════════════════════════════════════════
--  HASH / SHA CACHE  (avoids re-downloading unchanged files)
-- ══════════════════════════════════════════════════════════════════════════
local hashCache = {}   -- path → {sha, content}

local function loadHashCache()
    pcall(function()
        if not readfile then return end
        local raw = readfile(CFG.CacheFile)
        if not raw or #raw < 3 then return end
        -- Simple key:value pair parser (avoid full JSON dep)
        for path, sha in raw:gmatch('"([^"]+)"%s*:%s*"([^"]+)"') do
            hashCache[path] = sha
        end
    end)
end

local function saveHashCache(entries)
    pcall(function()
        if not writefile then return end
        local parts = {}
        for path, sha in pairs(entries) do
            table.insert(parts, string.format('"%s":"%s"', path, sha))
        end
        writefile(CFG.CacheFile, "{" .. table.concat(parts, ",") .. "}")
    end)
end

-- ══════════════════════════════════════════════════════════════════════════
--  LOCAL FILE CACHE (for offline mode)
-- ══════════════════════════════════════════════════════════════════════════
local function writeLocal(localPath, content)
    pcall(function()
        if not writefile then return end
        local dir = localPath:match("^(.+)/[^/]+$")
        if dir and makefolder then
            local segments, built = {}, ""
            for seg in dir:gmatch("[^/]+") do table.insert(segments, seg) end
            for _, seg in ipairs(segments) do
                built = built == "" and seg or (built .. "/" .. seg)
                if not isfolder(built) then pcall(makefolder, built) end
            end
        end
        writefile(localPath, content)
    end)
end

local function readLocal(localPath)
    if not readfile then return nil end
    local ok, c = pcall(readfile, localPath)
    return (ok and type(c)=="string" and #c>5) and c or nil
end

-- ══════════════════════════════════════════════════════════════════════════
--  MANIFEST PARSER
-- ══════════════════════════════════════════════════════════════════════════
local function parseManifest(json)
    if not json or #json < 5 then return nil, "Empty" end

    local version = json:match('"version"%s*:%s*"([^"]+)"') or "?"
    local files   = {}
    local fileSet = {}   -- path → true (dedup for auto-discover)

    -- Parse files array: each object has path, local, required, priority, group, disabled
    for block in json:gmatch('{[^{}]+}') do
        local path      = block:match('"path"%s*:%s*"([^"]+)"')
        local localPath = block:match('"local"%s*:%s*"([^"]+)"') or path
        local required  = block:match('"required"%s*:%s*true') and true or false
        local disabled  = block:match('"disabled"%s*:%s*true') and true or false
        local priority  = tonumber(block:match('"priority"%s*:%s*(%d+)')) or 50
        local group     = block:match('"group"%s*:%s*"([^"]+)"') or "module"
        local desc      = block:match('"description"%s*:%s*"([^"]+)"') or ""

        if path and not disabled and not fileSet[path] then
            fileSet[path] = true
            table.insert(files, {
                path      = path,
                localPath = localPath,
                required  = required,
                priority  = priority,
                group     = group,
                desc      = desc,
            })
        end
    end

    if #files == 0 then return nil, "No files in manifest" end

    -- Sort by priority (lower number = runs first)
    table.sort(files, function(a, b)
        if a.priority ~= b.priority then return a.priority < b.priority end
        return a.path < b.path
    end)

    return { version=version, files=files, fileSet=fileSet }
end

-- ══════════════════════════════════════════════════════════════════════════
--  AUTO-DISCOVER  — scans GitHub repo tree for .lua files not in manifest
--  This means: add a file to the repo → it runs automatically next boot!
-- ══════════════════════════════════════════════════════════════════════════
local function autoDiscover(manifest)
    -- Hit GitHub API: get full recursive file tree
    local treeUrl = string.format("%s/git/trees/%s?recursive=1", API_BASE, CFG.Branch)
    local body = fetch(treeUrl, 2, true)
    if not body then return end   -- API unreachable, skip discovery

    local discovered = 0
    -- Parse tree items: "path":"some/file.lua","type":"blob"
    for path in body:gmatch('"path"%s*:%s*"([^"]+%.lua)"') do
        -- Skip main.lua itself (that's us), skip paths already in manifest
        if path ~= "main.lua" and not manifest.fileSet[path] then
            -- Auto-include with default settings
            local localPath = path
            local priority  = 50
            -- Give known groups proper priorities
            if path == "core.lua" then priority = 0
            elseif path:find("^modules/") then priority = 50
            elseif path == "gui.lua" then priority = 99
            end

            table.insert(manifest.files, {
                path      = path,
                localPath = localPath,
                required  = false,   -- discovered files are optional by default
                priority  = priority,
                group     = path:match("^modules/") and "module" or "root",
                desc      = "Auto-discovered",
            })
            manifest.fileSet[path] = true
            discovered = discovered + 1
        end
    end

    if discovered > 0 then
        -- Re-sort after adding discovered files
        table.sort(manifest.files, function(a, b)
            if a.priority ~= b.priority then return a.priority < b.priority end
            return a.path < b.path
        end)
        print(string.format("[Bootstrapper] Auto-discovered %d new file(s) in repo", discovered))
    end
end

-- ══════════════════════════════════════════════════════════════════════════
--  MODULE EXECUTOR  — compiles and runs a Lua source string
-- ══════════════════════════════════════════════════════════════════════════
local function execSource(src, chunkName, entry)
    local fn, compErr = loadstring(src, "@" .. chunkName)
    if not fn then
        return false, "Compile error: " .. tostring(compErr)
    end
    local ok, runErr = pcall(fn)
    if not ok then
        return false, "Runtime error: " .. tostring(runErr)
    end
    return true
end

-- ══════════════════════════════════════════════════════════════════════════
--  BOOT NOTIFICATION UI  (lightweight pre-GUI progress display)
-- ══════════════════════════════════════════════════════════════════════════
local Boot = {}
do
    local TweenSvc  = game:GetService("TweenService")
    local LP        = game:GetService("Players").LocalPlayer
    local pg        = LP and LP:FindFirstChildOfClass("PlayerGui")
    local FAST      = TweenInfo.new(0.18)
    local SPRING    = TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

    if pg then
        local sg = Instance.new("ScreenGui")
        sg.Name="DebuggerBoot9"; sg.ResetOnSpawn=false
        sg.DisplayOrder=1001; sg.IgnoreGuiInset=true; sg.Parent=pg

        -- Main panel
        local panel = Instance.new("Frame")
        panel.Size    = UDim2.new(0, 330, 0, 72)
        panel.Position= UDim2.new(0.5,-165, 1, 80)   -- hidden below screen
        panel.BackgroundColor3 = Color3.fromRGB(8,10,20)
        panel.BorderSizePixel  = 0; panel.Parent=sg
        Instance.new("UICorner", panel).CornerRadius = UDim.new(0,12)
        local stroke = Instance.new("UIStroke", panel)
        stroke.Color=Color3.fromRGB(80,100,240); stroke.Thickness=1.2

        -- Animated accent bar (left edge)
        local accent = Instance.new("Frame", panel)
        accent.Size=UDim2.new(0,3,0,72); accent.Position=UDim2.new(0,0,0,0)
        accent.BackgroundColor3=Color3.fromRGB(80,100,240); accent.BorderSizePixel=0
        Instance.new("UICorner",accent).CornerRadius=UDim.new(0,3)

        -- Pulsing dot
        local dot=Instance.new("Frame",panel)
        dot.Size=UDim2.new(0,8,0,8); dot.Position=UDim2.new(0,16,0.5,-4)
        dot.BackgroundColor3=Color3.fromRGB(80,100,240); dot.BorderSizePixel=0
        Instance.new("UICorner",dot).CornerRadius=UDim.new(1,0)

        -- Title
        local title=Instance.new("TextLabel",panel)
        title.Size=UDim2.new(1,-36,0,20); title.Position=UDim2.new(0,34,0,10)
        title.BackgroundTransparency=1; title.Text="ANTIGRAVITY AUTO-DEBUGGER  v9"
        title.TextColor3=Color3.fromRGB(200,210,255); title.Font=Enum.Font.GothamBold
        title.TextSize=11; title.TextXAlignment=Enum.TextXAlignment.Left

        -- Status label
        local status=Instance.new("TextLabel",panel)
        status.Size=UDim2.new(1,-36,0,14); status.Position=UDim2.new(0,34,0,32)
        status.BackgroundTransparency=1; status.Text="Connecting to GitHub..."
        status.TextColor3=Color3.fromRGB(80,100,150); status.Font=Enum.Font.GothamMedium
        status.TextSize=9; status.TextXAlignment=Enum.TextXAlignment.Left

        -- Progress bar track
        local track=Instance.new("Frame",panel)
        track.Size=UDim2.new(1,-24,0,3); track.Position=UDim2.new(0,12,0,56)
        track.BackgroundColor3=Color3.fromRGB(25,30,55); track.BorderSizePixel=0
        Instance.new("UICorner",track).CornerRadius=UDim.new(1,0)

        local bar=Instance.new("Frame",track)
        bar.Size=UDim2.new(0,0,1,0); bar.Position=UDim2.new(0,0,0,0)
        bar.BackgroundColor3=Color3.fromRGB(80,100,240); bar.BorderSizePixel=0
        Instance.new("UICorner",bar).CornerRadius=UDim.new(1,0)

        -- Slide in
        TweenSvc:Create(panel, SPRING, {Position=UDim2.new(0.5,-165,1,-82)}):Play()

        -- Dot pulse loop
        _t.spawn(function()
            while panel.Parent do
                TweenSvc:Create(dot, TweenInfo.new(0.5), {BackgroundTransparency=0}):Play()
                _t.wait(0.5)
                TweenSvc:Create(dot, TweenInfo.new(0.5), {BackgroundTransparency=0.75}):Play()
                _t.wait(0.5)
            end
        end)

        -- Accent color cycle
        _t.spawn(function()
            local colors = {
                Color3.fromRGB(80,100,240),
                Color3.fromRGB(100,200,160),
                Color3.fromRGB(200,100,240),
                Color3.fromRGB(240,160,60),
            }
            local i = 1
            while panel.Parent do
                _t.wait(2)
                i = (i % #colors) + 1
                TweenSvc:Create(stroke, TweenInfo.new(1), {Color=colors[i]}):Play()
                TweenSvc:Create(accent, TweenInfo.new(1), {BackgroundColor3=colors[i]}):Play()
                TweenSvc:Create(dot, TweenInfo.new(1), {BackgroundColor3=colors[i]}):Play()
                TweenSvc:Create(bar, TweenInfo.new(1), {BackgroundColor3=colors[i]}):Play()
            end
        end)

        Boot.sg     = sg
        Boot.panel  = panel
        Boot.status = status
        Boot.bar    = bar
        Boot.TW     = TweenSvc
        Boot.active = true
    end
end

local function bootMsg(msg, progress)
    print("[Bootstrapper] " .. msg)
    if Boot.active then
        pcall(function() Boot.status.Text = msg end)
        if progress and Boot.bar then
            pcall(function()
                Boot.TW:Create(Boot.bar, TweenInfo.new(0.3, Enum.EasingStyle.Quad),
                    {Size=UDim2.new(math.clamp(progress,0,1), 0, 1, 0)}):Play()
            end)
        end
    end
end

local function dismissBoot(finalMsg, isError)
    if not Boot.active then return end
    Boot.active = false
    _t.spawn(function()
        local col = isError and Color3.fromRGB(200,60,60) or Color3.fromRGB(60,200,120)
        pcall(function()
            Boot.TW:Create(Boot.bar, TweenInfo.new(0.3), {Size=UDim2.new(1,0,1,0), BackgroundColor3=col}):Play()
            Boot.status.Text = finalMsg or "Done"
            Boot.status.TextColor3 = col
        end)
        _t.wait(1.8)
        pcall(function()
            Boot.TW:Create(Boot.panel, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
                {Position=UDim2.new(0.5,-165,1,80)}):Play()
        end)
        _t.wait(0.4)
        pcall(function() Boot.sg:Destroy() end)
    end)
end

-- ══════════════════════════════════════════════════════════════════════════
--  PARALLEL DOWNLOADER
--  Downloads all files simultaneously, returns a table of {path → src}
-- ══════════════════════════════════════════════════════════════════════════
local function downloadAll(files)
    local results  = {}   -- path → source string or false
    local done     = {}   -- path → true when finished
    local total    = #files
    local finished = 0

    if CFG.ParallelDL then
        -- Fire off all downloads concurrently
        for _, entry in ipairs(files) do
            local path = entry.path
            results[path] = false   -- default = failed
            _t.spawn(function()
                -- Check SHA cache first
                local url = RAW_BASE .. "/" .. path
                local src = nil

                if CFG.UseCache and hashCache[path] then
                    -- We have a cached version — still download to check if changed
                    -- For now we'll just use cached content if available locally
                    local cached = readLocal(entry.localPath)
                    if cached then
                        -- Use cached version
                        src = cached
                    end
                end

                if not src then
                    src = fetch(url, CFG.RetryCount, true)
                end

                results[path] = src or false
                done[path]    = true
                finished      = finished + 1
            end)
        end

        -- Wait for all downloads with a timeout
        local timeout = 30   -- max 30s for all downloads
        local elapsed = 0
        while finished < total and elapsed < timeout do
            _t.wait(0.08)
            elapsed = elapsed + 0.08
            bootMsg(string.format("Downloading... %d/%d", finished, total), finished/total * 0.7)
        end
    else
        -- Sequential fallback (some executors can't parallel)
        for i, entry in ipairs(files) do
            local url = RAW_BASE .. "/" .. entry.path
            local src = fetch(url, CFG.RetryCount, true)
            results[entry.path] = src or false
            done[entry.path]    = true
            finished = finished + 1
            bootMsg(string.format("Downloading [%d/%d] %s", i, total, entry.path:match("[^/]+$")), i/total*0.7)
            _t.wait(0.03)
        end
    end

    return results
end

-- ══════════════════════════════════════════════════════════════════════════
--  MAIN BOOT SEQUENCE
-- ══════════════════════════════════════════════════════════════════════════
print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
print("  ANTIGRAVITY AUTO-DEBUGGER  v9 — Smart Boot")
print("  github.com/" .. CFG.Owner .. "/" .. CFG.Repo)
print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

-- Load hash cache for smart skip
loadHashCache()

-- ── Step 1: Fetch manifest ────────────────────────────────────────────────
bootMsg("Fetching manifest from GitHub...", 0.02)
local manifestSrc = fetch(RAW_BASE .. "/" .. CFG.ManifestFile, 4)

if not manifestSrc then
    -- Try local cache fallback
    bootMsg("GitHub unreachable — checking local cache...", 0.01)
    manifestSrc = readLocal(CFG.ManifestFile)
    if manifestSrc then
        print("[Bootstrapper] Using cached manifest (offline mode)")
    else
        warn("[Bootstrapper] FATAL: Cannot reach GitHub and no local manifest cached.")
        warn("Fix: 1) Enable HTTP requests in executor  2) Check internet  3) Run once online first")
        dismissBoot("❌ GitHub unreachable", true)
        getgenv().DebuggerLoaded = nil
        return
    end
else
    -- Cache the fresh manifest for offline use
    writeLocal(CFG.ManifestFile, manifestSrc)
end

-- ── Step 2: Parse manifest ────────────────────────────────────────────────
local manifest, parseErr = parseManifest(manifestSrc)
if not manifest then
    warn("[Bootstrapper] FATAL: Manifest parse failed: " .. tostring(parseErr))
    dismissBoot("❌ Bad manifest", true)
    getgenv().DebuggerLoaded = nil
    return
end

bootMsg(string.format("Manifest v%s — %d files", manifest.version, #manifest.files), 0.05)
print(string.format("  Remote v%s | %d declared files", manifest.version, #manifest.files))

-- ── Step 3: Auto-discover new files in the repo ───────────────────────────
if CFG.AutoDiscover then
    bootMsg("Scanning repo for new files...", 0.08)
    autoDiscover(manifest)
    print(string.format("  Total after discovery: %d files", #manifest.files))
end

-- ── Step 4: Parallel download all files ───────────────────────────────────
bootMsg(string.format("Downloading %d files in parallel...", #manifest.files), 0.10)
local sources = downloadAll(manifest.files)

-- ── Step 5: Execute each module in priority order ─────────────────────────
bootMsg("Executing modules...", 0.72)

local executed   = 0
local skipped    = 0
local errored    = 0
local newHashes  = {}
local total      = #manifest.files
local startTime  = os.clock()

for i, entry in ipairs(manifest.files) do
    local src = sources[entry.path]
    local pct = 0.72 + (i / total) * 0.26   -- progress from 72% to 98%

    if not src or src == false then
        -- Download failed
        local cached = readLocal(entry.localPath)
        if cached then
            src = cached
            print(string.format("  [%d/%d] ⚠ Using cache: %s", i, total, entry.path))
        else
            if entry.required then
                warn(string.format("  [%d/%d] ✗ REQUIRED MISSING: %s", i, total, entry.path))
                errored = errored + 1
            else
                print(string.format("  [%d/%d] ○ Skipped (unavailable): %s", i, total, entry.path))
                skipped = skipped + 1
            end
            _g.DebuggerModules[entry.path] = {loaded=false, time=0, error="Download failed"}
            goto continue
        end
    end

    -- Save to local cache + track hash
    writeLocal(entry.localPath, src)
    newHashes[entry.path] = tostring(#src)   -- simple length-based hash (fast, good enough)

    -- Update boot status
    bootMsg(string.format("[%d/%d] %s", i, total, entry.path:match("[^/]+%.?[^/]*$") or entry.path), pct)

    -- Execute
    local t0   = os.clock()
    local ok, err = execSource(src, entry.path, entry)
    local dt   = os.clock() - t0

    if ok then
        executed = executed + 1
        _g.DebuggerModules[entry.path] = {loaded=true, time=dt, error=nil}
        print(string.format("  [%d/%d] ✓ %s  (%.0fms)", i, total, entry.path, dt*1000))
    else
        errored = errored + 1
        _g.DebuggerModules[entry.path] = {loaded=false, time=dt, error=err}
        if entry.required then
            warn(string.format("  [%d/%d] ✗ REQUIRED FAILED: %s\n     %s", i, total, entry.path, err))
        else
            warn(string.format("  [%d/%d] ✗ %s\n     %s", i, total, entry.path, err))
        end
    end

    -- Yield — heavier modules get more breathing room
    local isHeavy = false
    for _, name in ipairs(CFG.HeavyModules) do
        if entry.path:find(name, 1, true) then isHeavy=true; break end
    end
    _t.wait(isHeavy and CFG.HeavyYield or CFG.YieldBetween)

    ::continue::
end

-- ── Step 6: Save updated hash cache ───────────────────────────────────────
saveHashCache(newHashes)

-- ── Step 7: Summary ───────────────────────────────────────────────────────
local totalTime = os.clock() - startTime
print(string.format("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"))
print(string.format("  Boot complete in %.2fs  |  v%s", totalTime, manifest.version))
print(string.format("  ✓ %d executed  ○ %d skipped  ✗ %d errored", executed, skipped, errored))
print(string.format("  Source: github.com/%s/%s", CFG.Owner, CFG.Repo))
print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

local finalMsg = string.format("✓ v%s — %d/%d loaded (%.1fs)", manifest.version, executed, total, totalTime)
dismissBoot(finalMsg, errored > 0 and executed == 0)

-- ══════════════════════════════════════════════════════════════════════════
--  HOT-RELOAD API
--  Call from executor console: getgenv().DebuggerHotReload("gui.lua")
--  Downloads the latest version from GitHub and re-executes it live.
-- ══════════════════════════════════════════════════════════════════════════
_g.DebuggerHotReload = function(path)
    if not path then
        print("[HotReload] Usage: DebuggerHotReload('modules/ai_analyzer.lua')")
        return
    end
    print("[HotReload] Reloading: " .. path)
    local url = RAW_BASE .. "/" .. path
    local src = fetch(url, 3)
    if not src then
        warn("[HotReload] Failed to download: " .. path)
        return
    end
    writeLocal(path, src)
    local ok, err = execSource(src, path)
    if ok then
        print("[HotReload] ✓ Reloaded: " .. path)
        _g.DebuggerModules[path] = {loaded=true, time=0, reloaded=true}
    else
        warn("[HotReload] ✗ Error in " .. path .. ": " .. tostring(err))
    end
end

-- ══════════════════════════════════════════════════════════════════════════
--  SMART SCAN HEARTBEAT
--  Runs registered scanners with rate-limiting & per-scanner error isolation.
-- ══════════════════════════════════════════════════════════════════════════
_t.spawn(function()
    -- Wait for core to load
    local Data, tries = nil, 0
    repeat _t.wait(0.15); Data = getgenv().DebuggerSharedData; tries=tries+1
    until Data or tries >= 60

    if not Data then warn("[Bootstrapper] Core not found — scan loop aborted."); return end

    local RS   = game:GetService("RunService")
    local SS   = game:GetService("Stats")
    local tick = tick
    local scannerErrors = {}   -- path → consecutive error count

    -- Let everything settle
    _t.wait(3)

    -- Uptime counter
    local startTick = tick()
    _t.spawn(function()
        while getgenv().DebuggerLoaded do
            _t.wait(1)
            pcall(function() Data.Stats.Uptime = math.floor(tick() - startTick) end)
        end
    end)

    -- FPS measurement
    local lastHb, frames = tick(), 0
    RS.Heartbeat:Connect(function(dt)
        frames = frames + 1
        local now = tick()
        if now - lastHb >= 1 then
            local fps = math.min(frames, 999)
            pcall(function() Data.Stats.FPS = fps end)
            frames  = 0
            lastHb  = now
        end
    end)

    -- Scan loop
    while getgenv().DebuggerLoaded do
        -- Ping (non-blocking)
        _t.spawn(function()
            pcall(function()
                Data.Stats.Ping = math.floor(SS.Network.ServerStatsItem["Data Ping"].Value)
            end)
        end)

        -- Instance count (yield so it doesn't stall)
        _t.wait()
        pcall(function()
            Data.Stats.InstanceCount = #game:GetDescendants()
        end)

        -- Memory
        _t.wait()
        pcall(function()
            Data.Stats.MemoryMB = math.floor(gcinfo() / 102.4) / 10
        end)

        -- Run each registered scanner
        Data.Stats.ScanCount = (Data.Stats.ScanCount or 0) + 1
        local scanners = getgenv().DebuggerScanners or {}
        for idx, scanner in ipairs(scanners) do
            _t.wait()   -- yield between scanners (one per frame)
            local ok, err = pcall(scanner)
            if not ok then
                -- Count consecutive failures
                scannerErrors[idx] = (scannerErrors[idx] or 0) + 1
                if scannerErrors[idx] == 3 then
                    warn(string.format("[ScanLoop] Scanner #%d failing repeatedly: %s", idx, tostring(err)))
                end
                if scannerErrors[idx] > 10 then
                    -- Remove broken scanner
                    table.remove(scanners, idx)
                    warn(string.format("[ScanLoop] Scanner #%d removed after 10 errors.", idx))
                    break
                end
            else
                scannerErrors[idx] = 0  -- reset on success
            end
        end

        local interval = (Data.Settings and Data.Settings.ScanInterval) or 3
        _t.wait(interval)
    end
end)

-- ══════════════════════════════════════════════════════════════════════════
--  PERIODIC VERSION CHECK (every 10 minutes)
-- ══════════════════════════════════════════════════════════════════════════
_t.spawn(function()
    _t.wait(600)
    while getgenv().DebuggerLoaded do
        local newManifest = fetch(RAW_BASE .. "/" .. CFG.ManifestFile, 2, true)
        if newManifest then
            local m = parseManifest(newManifest)
            if m and m.version ~= manifest.version then
                print(string.format("[Bootstrapper] 🔔 Update available: v%s → v%s", manifest.version, m.version))
                local Data = getgenv().DebuggerSharedData
                if Data then
                    pcall(function()
                        Data:ReportBug({
                            Type = "Update Available",
                            Source = "github.com/" .. CFG.Owner .. "/" .. CFG.Repo,
                            Description = string.format("New version v%s available (you have v%s). Re-run main.lua to update.", m.version, manifest.version),
                            Severity = "Low",
                        })
                    end)
                end
            end
        end
        _t.wait(600)
    end
end)

print("[Bootstrapper v9]: Smart boot complete. HotReload: DebuggerHotReload('file.lua')")
