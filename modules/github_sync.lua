--[[
    ========================================================================
    ULTIMATE ROBLOX AUTO-DEBUGGER  ·  GITHUB SYNC ENGINE  (v8)
    ========================================================================
    Pre-configured for: https://github.com/svx6/debugging-tool
    Branch: main
    
    HOW IT WORKS:
      1. On boot, fetches manifest.json from the repo to get the file list
         and current version number.
      2. Compares remote version against local VERSION file.
      3. If remote is newer (or force-pull requested), downloads every file
         listed in the manifest and writes them to the executor workspace.
      4. New modules added to the repo are automatically detected and
         downloaded — no code changes needed.
      5. Each file is downloaded with proper error handling and retry logic.
      6. Progress is published to the GUI in real-time.
    
    FUTURE-PROOF DESIGN:
      · New files: just add them to manifest.json in the repo — the tool
        will automatically download them on next sync.
      · Version bumps: update "version" in manifest.json — tools with
        older local versions will auto-update.
      · Branch switching: change GH.Branch and re-sync.
    
    EXECUTOR COMPATIBILITY:
      · Synapse X  — syn.request / request
      · KRNL       — request
      · Wave       — request
      · Hydrogen   — request
      · Fluxus     — request / syn.request
      · Codex      — request
      · Fallback   — game:HttpGetAsync (for older executors)
    ========================================================================
--]]

local Data = getgenv().DebuggerSharedData
if not Data then warn("[GitHubSync v8]: Core not loaded.") return end

local _pcall     = pcall
local _tostring  = tostring

-- ── Configuration ─────────────────────────────────────────────────────────
local DEFAULT_REPO   = "svx6/debugging-tool"
local DEFAULT_BRANCH = "main"
local RAW_BASE       = "https://raw.githubusercontent.com"
local API_BASE       = "https://api.github.com/repos"
local MANIFEST_PATH  = "manifest.json"
local VERSION_FILE   = "VERSION"
local LOCAL_VERSION  = "8.0.0"

-- ── GitHub State ───────────────────────────────────────────────────────────
Data.GitHub = Data.GitHub or {
    Repo        = DEFAULT_REPO,
    Branch      = DEFAULT_BRANCH,
    AutoSync    = true,     -- pull on every boot
    SyncStatus  = "Idle",
    LastSync    = "Never",
    RemoteVersion = nil,
    LocalVersion  = LOCAL_VERSION,
    SyncLog     = {},       -- last 50 log lines
    FilesUpdated  = 0,
    FilesSkipped  = 0,
    SyncInProgress = false,
}
local GH = Data.GitHub

-- ── Logging ───────────────────────────────────────────────────────────────
local function ghLog(msg, isError)
    local line = string.format("[%s] %s", os.date("%H:%M:%S"), msg)
    table.insert(GH.SyncLog, 1, line)
    while #GH.SyncLog > 50 do table.remove(GH.SyncLog) end
    local logType = isError and "Warning" or "Info"
    _pcall(function()
        Data:ReportLog({Type = logType, Text = "[GitHubSync] " .. msg})
    end)
    _pcall(function() Data:Publish("OnGitHubStatus", GH) end)
end

local function setStatus(status)
    GH.SyncStatus = status
    _pcall(function() Data:Publish("OnGitHubStatus", GH) end)
end

-- ── HTTP Fetcher — tries every known executor API ─────────────────────────
local function httpGet(url)
    -- Safely resolve executor globals (some executors error on undefined global access)
    local _syn          = rawget(_G, "syn")
    local _request      = rawget(_G, "request")
    local _http         = rawget(_G, "http")
    local _HttpGet      = rawget(_G, "HttpGet")

    -- Method 1: syn.request (Synapse X)
    if _syn and type(_syn) == "table" and type(_syn.request) == "function" then
        local ok, res = _pcall(function()
            return _syn.request({Url = url, Method = "GET"})
        end)
        if ok and res and res.StatusCode == 200 then
            return true, res.Body
        end
        if ok and res and res.StatusCode then
            return false, "HTTP " .. res.StatusCode
        end
    end

    -- Method 2: request (KRNL, Wave, Hydrogen, Fluxus, Codex)
    if type(_request) == "function" then
        local ok, res = _pcall(function()
            return _request({Url = url, Method = "GET"})
        end)
        if ok and res and res.StatusCode == 200 then
            return true, res.Body
        end
        if ok and res and res.StatusCode then
            return false, "HTTP " .. res.StatusCode
        end
    end

    -- Method 3: http.request (some older executors)
    if type(_http) == "table" and type(_http.request) == "function" then
        local ok, res = _pcall(function()
            return _http.request({Url = url, Method = "GET"})
        end)
        if ok and res and res.StatusCode == 200 then
            return true, res.Body
        end
    end

    -- Method 4: HttpGet string form (some Roblox-side executors)
    if type(_HttpGet) == "function" then
        local ok, body = _pcall(_HttpGet, game, url)
        if ok and type(body) == "string" and #body > 0 then
            return true, body
        end
    end

    -- Method 5: game:HttpGetAsync (fallback, limited)
    local ok2, body2 = _pcall(function()
        return game:HttpGetAsync(url)
    end)
    if ok2 and type(body2) == "string" and #body2 > 0 then
        return true, body2
    end

    return false, "No HTTP method available (executor does not support HTTP requests)"
end

-- ── HTTP with retry logic ──────────────────────────────────────────────────
local function httpGetRetry(url, maxRetries)
    maxRetries = maxRetries or 3
    for attempt = 1, maxRetries do
        local ok, body = httpGet(url)
        if ok then return true, body end
        if attempt < maxRetries then
            task.wait(1.5 * attempt)  -- exponential backoff
        else
            return false, body
        end
    end
end

-- ── Build raw URL for a file in the repo ─────────────────────────────────
local function rawUrl(filePath)
    return string.format("%s/%s/%s/%s",
        RAW_BASE, GH.Repo, GH.Branch, filePath)
end

-- ── JSON parser — lightweight, handles the manifest format ────────────────
-- We only need to parse the specific manifest.json structure
local function parseManifest(jsonStr)
    if not jsonStr or #jsonStr < 10 then return nil, "Empty response" end

    -- Extract version
    local version = jsonStr:match('"version"%s*:%s*"([^"]+)"')
    -- Extract base URL
    local baseUrl = jsonStr:match('"baseUrl"%s*:%s*"([^"]+)"')
    -- Extract files array — parse each {path, local, required} object
    local files = {}
    for block in jsonStr:gmatch('{[^{}]*"path"[^{}]*}') do
        local path     = block:match('"path"%s*:%s*"([^"]+)"')
        local localPath = block:match('"local"%s*:%s*"([^"]+)"')
        local required = block:match('"required"%s*:%s*(true)') and true or false
        if path and localPath then
            table.insert(files, {path = path, localPath = localPath, required = required})
        end
    end

    if #files == 0 then
        return nil, "Manifest has no files listed"
    end

    return {
        version = version or "unknown",
        baseUrl = baseUrl,
        files   = files,
    }
end

-- ── Version comparison ─────────────────────────────────────────────────────
local function versionGT(a, b)
    -- Returns true if version a > version b
    -- Handles "8.0.0" style semver strings
    if not a or not b then return false end
    local function parts(v)
        local p = {}
        for n in tostring(v):gmatch("%d+") do table.insert(p, tonumber(n) or 0) end
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

-- ── Write file to executor workspace ──────────────────────────────────────
local function writeLocalFile(localPath, content)
    if not writefile then return false, "writefile not available" end

    -- Create parent directories as needed
    local dir = localPath:match("^(.*)/[^/]+$")
    if dir and dir ~= "" and makefolder then
        _pcall(function()
            -- Create nested dirs
            local parts = {}
            for part in dir:gmatch("[^/]+") do
                table.insert(parts, part)
            end
            local current = ""
            for _, part in ipairs(parts) do
                current = current == "" and part or (current .. "/" .. part)
                if not isfolder(current) then
                    makefolder(current)
                end
            end
        end)
    end

    local ok, err = _pcall(writefile, localPath, content)
    return ok, err
end

-- ── Read local file ────────────────────────────────────────────────────────
local function readLocalFile(localPath)
    if not readfile then return nil end
    local ok, content = _pcall(readfile, localPath)
    return (ok and type(content) == "string") and content or nil
end

-- ── Core Sync Function ─────────────────────────────────────────────────────
local function doSync(forcePull)
    if GH.SyncInProgress then
        ghLog("Sync already in progress — skipping.", true)
        return false
    end

    if not GH.Repo or GH.Repo == "" then
        ghLog("No repository configured.", true)
        setStatus("Error: No repo set")
        return false
    end

    GH.SyncInProgress = true
    GH.FilesUpdated   = 0
    GH.FilesSkipped   = 0
    setStatus("Connecting to GitHub...")
    ghLog("Starting sync from " .. GH.Repo .. " @ " .. GH.Branch)

    -- Step 1: Fetch manifest
    ghLog("Fetching manifest.json...")
    local manifestUrl = rawUrl(MANIFEST_PATH)
    local ok, body = httpGetRetry(manifestUrl, 3)
    if not ok then
        ghLog("Failed to fetch manifest: " .. _tostring(body), true)
        setStatus("Error: Cannot reach GitHub")
        GH.SyncInProgress = false
        return false
    end

    -- Step 2: Parse manifest
    local manifest, parseErr = parseManifest(body)
    if not manifest then
        ghLog("Manifest parse error: " .. _tostring(parseErr), true)
        -- Fallback: try to load individual files without manifest
        setStatus("Error: Bad manifest")
        GH.SyncInProgress = false
        return false
    end

    ghLog(string.format("Manifest OK — remote v%s, %d files", manifest.version, #manifest.files))
    GH.RemoteVersion = manifest.version

    -- Step 3: Version check
    local localVer = readLocalFile(VERSION_FILE) or LOCAL_VERSION
    GH.LocalVersion = localVer:gsub("%s+", "")

    if not forcePull and not versionGT(manifest.version, GH.LocalVersion) then
        ghLog(string.format("Already up to date (local: v%s, remote: v%s)", GH.LocalVersion, manifest.version))
        setStatus("Up to date — v" .. GH.LocalVersion)
        GH.LastSync = os.date("%H:%M:%S")
        GH.SyncInProgress = false
        _pcall(function() Data:Publish("OnGitHubStatus", GH) end)
        return true
    end

    if versionGT(manifest.version, GH.LocalVersion) then
        ghLog(string.format("Update available: v%s → v%s", GH.LocalVersion, manifest.version))
    else
        ghLog("Force pull requested — downloading all files")
    end

    -- Step 4: Download each file
    setStatus("Downloading " .. #manifest.files .. " files...")
    local totalFiles = #manifest.files
    local downloaded = 0

    for i, fileEntry in ipairs(manifest.files) do
        local remoteUrl = rawUrl(fileEntry.path)
        local localPath = fileEntry.localPath

        setStatus(string.format("Downloading [%d/%d]: %s", i, totalFiles, fileEntry.path))
        ghLog(string.format("[%d/%d] %s", i, totalFiles, fileEntry.path))

        -- Download
        local dlOk, dlBody = httpGetRetry(remoteUrl, 3)
        if dlOk and dlBody and #dlBody > 0 then
            -- Write to local workspace
            local writeOk, writeErr = writeLocalFile(localPath, dlBody)
            if writeOk then
                downloaded = downloaded + 1
                GH.FilesUpdated = downloaded
                ghLog("  ✓ " .. localPath)
            else
                ghLog("  ✗ Write failed for " .. localPath .. ": " .. _tostring(writeErr), true)
                if fileEntry.required then
                    ghLog("  CRITICAL: Required file failed to write.", true)
                end
            end
        else
            ghLog("  ✗ Download failed for " .. fileEntry.path .. ": " .. _tostring(dlBody), true)
            GH.FilesSkipped = GH.FilesSkipped + 1
            if fileEntry.required then
                ghLog("  WARNING: Required file could not be downloaded.", true)
            end
        end

        -- Yield between files to keep the game responsive
        task.wait(0.1)
    end

    -- Step 5: Update local version file
    if downloaded > 0 then
        _pcall(function()
            if writefile then
                writefile(VERSION_FILE, manifest.version)
            end
        end)
        GH.LocalVersion = manifest.version
    end

    -- Done
    GH.LastSync = os.date("%H:%M:%S")
    local summary = string.format("Sync complete: %d/%d files updated, %d skipped",
        downloaded, totalFiles, GH.FilesSkipped)
    ghLog(summary)
    setStatus(string.format("✓ v%s — %s", manifest.version, GH.LastSync))

    _pcall(function()
        Data:ReportLog({
            Type = "Info",
            Text = "[GitHubSync] " .. summary,
        })
    end)
    _pcall(function() Data:Publish("OnGitHubSyncComplete", GH) end)

    GH.SyncInProgress = false
    return true
end

-- ── Version Check Only (no download) ─────────────────────────────────────
local function checkVersion()
    local url = rawUrl(MANIFEST_PATH)
    local ok, body = httpGetRetry(url, 2)
    if not ok then return nil, "HTTP failed: " .. _tostring(body) end
    local manifest = parseManifest(body)
    if not manifest then return nil, "Could not parse manifest" end
    GH.RemoteVersion = manifest.version
    return manifest.version, nil
end

-- ── Fetch and Execute a Single Script from URL ───────────────────────────
local function fetchScript(url, chunkName)
    chunkName = chunkName or url:match("[^/]+$") or "remote_script"
    ghLog("Fetching script: " .. url)
    local ok, body = httpGetRetry(url, 2)
    if not ok then
        ghLog("Script fetch failed: " .. _tostring(body), true)
        return false, body
    end
    local fn, compileErr = loadstring(body, "@" .. chunkName)
    if not fn then
        ghLog("Script compile error: " .. _tostring(compileErr), true)
        return false, compileErr
    end
    local runOk, runErr = _pcall(fn)
    if not runOk then
        ghLog("Script runtime error: " .. _tostring(runErr), true)
        return false, runErr
    end
    ghLog("Script executed: " .. chunkName)
    return true
end

-- ── Pull Latest from Repo ─────────────────────────────────────────────────
local function pullLatest()
    return task.spawn(function() doSync(true) end)
end

-- ── Expose API ────────────────────────────────────────────────────────────
GH.PullLatest    = pullLatest
GH.CheckVersion  = checkVersion
GH.FetchScript   = fetchScript
GH.Sync          = function(force) return task.spawn(function() doSync(force) end) end

-- ── Auto-Sync on Boot ──────────────────────────────────────────────────────
if GH.AutoSync then
    -- Delay so other modules load first, then run sync in background
    task.delay(4, function()
        ghLog("Auto-sync starting (boot)...")
        doSync(false)  -- only downloads if version is newer
    end)
else
    ghLog("Auto-sync disabled. Use 'Pull Latest' in GitHub Sync tab to update.")
    setStatus("Manual mode — " .. GH.LocalVersion)
end

-- ── Periodic Update Check (every 10 minutes while tool is open) ───────────
task.spawn(function()
    task.wait(600)  -- first check after 10 minutes
    while getgenv().DebuggerLoaded do
        local remoteVer, err = checkVersion()
        if remoteVer and versionGT(remoteVer, GH.LocalVersion) then
            ghLog(string.format("🔔 Update available: v%s → v%s. Use 'Pull Latest' to update.", GH.LocalVersion, remoteVer))
            _pcall(function()
                Data:ReportBug({
                    Type = "GitHub: Update Available",
                    Source = "github.com/" .. GH.Repo,
                    Description = string.format("Remote version v%s is available (you have v%s). Pull from GitHub Sync tab.", remoteVer, GH.LocalVersion),
                    Severity = "Low",
                })
            end)
        end
        task.wait(600)  -- check every 10 minutes
    end
end)

print(string.format("[GitHubSync v8]: Linked to github.com/%s @ %s. AutoSync=%s LocalVersion=%s",
    GH.Repo, GH.Branch, tostring(GH.AutoSync), LOCAL_VERSION))
