-- ANTIGRAVITY AUTO-DEBUGGER v9
-- https://github.com/svx6/debugging-tool
-- loadstring(game:HttpGet("https://raw.githubusercontent.com/svx6/debugging-tool/main/main.lua"))()
--
-- ARCHITECTURE: GUI-FIRST LAZY LOAD
--   1. GUI appears instantly (< 1 frame)
--   2. Manifest + files download silently in background
--   3. Modules execute one-per-frame, never blocking the game
--   4. Heavy features only activate when the user opens the panel
--   RESULT: Zero lag, zero camera freeze, zero crash.

-- SAFE ENVIRONMENT BOOTSTRAP
local _env = (pcall(function() return getfenv(0) end) and getfenv(0)) or _G or {}

local function sg(name)
    local ok, v = pcall(function() return _env[name] end)
    return (ok and v ~= nil) and v or nil
end

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
local _hreq     = sg("http_request")
local _HttpGet  = sg("HttpGet")
local _unpack   = sg("unpack") or table.unpack

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
    _warn("[Debugger] Already running. Close the GUI first.")
    return
end
G.DebuggerLoaded   = true
G.DebuggerModules  = {}
G.DebuggerScanners = {}

-- TASK POLYFILL
local _t = _task
if not _t or _type(_t) ~= "table" then
    local RS = game:GetService("RunService")
    local up = _unpack or function(...) return ... end
    _t = {
        spawn = function(f, ...) local a = {...}
            return coroutine.wrap(function() f(up(a)) end)() end,
        wait = function(n) local s = os.clock()
            repeat RS.Heartbeat:Wait() until os.clock() - s >= (n or 0)
            return os.clock() - s end,
        delay = function(n, f, ...) local a = {...}
            coroutine.wrap(function() local s = os.clock()
                repeat RS.Heartbeat:Wait() until os.clock() - s >= (n or 0)
                f(up(a)) end)() end,
        defer = function(f, ...) local a = {...}
            coroutine.wrap(function() RS.Heartbeat:Wait(); f(up(a)) end)() end,
    }
    G.task = _t
end

-- CONFIG
local CFG = {
    Owner    = "svx6",
    Repo     = "debugging-tool",
    Branch   = "main",
    Manifest = "manifest.json",
    Retries  = 3,
}
local RAW = ("https://raw.githubusercontent.com/%s/%s/%s"):format(CFG.Owner, CFG.Repo, CFG.Branch)
local API = ("https://api.github.com/repos/%s/%s"):format(CFG.Owner, CFG.Repo)

-- HTTP ENGINE
local function httpGet(url)
    local ok, r
    if _type(_syn) == "table" and _type((_syn).request) == "function" then
        ok, r = _pcall((_syn).request, {Url=url, Method="GET"})
        if ok and r and r.StatusCode == 200 then return r.Body end
    end
    if _type(_request) == "function" then
        ok, r = _pcall(_request, {Url=url, Method="GET"})
        if ok and r and r.StatusCode == 200 then return r.Body end
    end
    if _type(_http) == "table" and _type((_http).request) == "function" then
        ok, r = _pcall((_http).request, {Url=url, Method="GET"})
        if ok and r and r.StatusCode == 200 then return r.Body end
    end
    if _type(_hreq) == "function" then
        ok, r = _pcall(_hreq, {Url=url, Method="GET"})
        if ok and r and r.StatusCode == 200 then return r.Body end
    end
    if _type(_HttpGet) == "function" then
        ok, r = _pcall(_HttpGet, game, url)
        if ok and _type(r) == "string" and #r > 0 then return r end
    end
    ok, r = _pcall(function() return game:HttpGetAsync(url) end)
    if ok and _type(r) == "string" and #r > 0 then return r end
    return nil
end

local function fetch(url, retries)
    retries = retries or CFG.Retries
    for i = 1, retries do
        local r = httpGet(url)
        if r and #r > 5 then return r end
        if i < retries then _t.wait(0.5 * i) end
    end
    return nil
end

-- FILE HELPERS
local function readLocal(p)
    if _type(_readfile) ~= "function" then return nil end
    local ok, c = _pcall(_readfile, p)
    return (ok and _type(c) == "string" and #c > 5) and c or nil
end

local function writeLocal(p, data)
    _pcall(function()
        if _type(_wfile) ~= "function" then return end
        local dir = p:match("^(.+)/[^/]+$")
        if dir and _type(_mkfolder) == "function" and _type(_isfolder) == "function" then
            local built = ""
            for seg in dir:gmatch("[^/]+") do
                built = (built == "" and seg) or (built .. "/" .. seg)
                if not _isfolder(built) then _pcall(_mkfolder, built) end
            end
        end
        _wfile(p, data)
    end)
end

-- MANIFEST PARSER
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
            table.insert(files, {path=path, lpath=lpath, priority=prio, required=req, group=grp})
        end
    end
    if #files == 0 then return nil end
    table.sort(files, function(a, b)
        return a.priority ~= b.priority and a.priority < b.priority or a.path < b.path
    end)
    return {version=ver, files=files, seen=seen}
end

-- SHARED STATE
local State = {
    ready      = false,
    manifest   = nil,
    sources    = {},
    loaded     = 0,
    errors     = 0,
    total      = 0,
    statusText = "Starting...",
    triggered  = false,
}
G.DebuggerState = State

-- INSTANT GUI (appears before any download starts)
local GUI = {}
_pcall(function()
    local TW   = game:GetService("TweenService")
    local LP   = game:GetService("Players").LocalPlayer
    local PGui = LP and LP:FindFirstChildOfClass("PlayerGui")
    if not PGui then return end

    local SPRING  = TweenInfo.new(0.5,  Enum.EasingStyle.Back,  Enum.EasingDirection.Out)
    local EASE_IN = TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.In)

    local sg = Instance.new("ScreenGui")
    sg.Name = "AntigravityDebugger9"; sg.ResetOnSpawn = false
    sg.DisplayOrder = 9999; sg.IgnoreGuiInset = true; sg.Parent = PGui

    -- Collapsed pill (always visible, click to open)
    local pill = Instance.new("Frame")
    pill.Name = "Pill"; pill.Active = true
    pill.Size = UDim2.new(0, 180, 0, 36)
    pill.Position = UDim2.new(1, 16, 0, 12)
    pill.BackgroundColor3 = Color3.fromRGB(10, 12, 28)
    pill.BorderSizePixel = 0; pill.Parent = sg
    Instance.new("UICorner", pill).CornerRadius = UDim.new(1, 0)
    local pillStroke = Instance.new("UIStroke", pill)
    pillStroke.Color = Color3.fromRGB(90, 110, 255); pillStroke.Thickness = 1.5

    local pillDot = Instance.new("Frame", pill)
    pillDot.Size = UDim2.new(0, 8, 0, 8); pillDot.Position = UDim2.new(0, 10, 0.5, -4)
    pillDot.BackgroundColor3 = Color3.fromRGB(90, 110, 255); pillDot.BorderSizePixel = 0
    Instance.new("UICorner", pillDot).CornerRadius = UDim.new(1, 0)

    local pillLabel = Instance.new("TextLabel", pill)
    pillLabel.Size = UDim2.new(1, -28, 1, 0); pillLabel.Position = UDim2.new(0, 24, 0, 0)
    pillLabel.BackgroundTransparency = 1; pillLabel.Text = "ANTIGRAVITY  v9"
    pillLabel.TextColor3 = Color3.fromRGB(180, 195, 255); pillLabel.Font = Enum.Font.GothamBold
    pillLabel.TextSize = 10; pillLabel.TextXAlignment = Enum.TextXAlignment.Left

    TW:Create(pill, SPRING, {Position = UDim2.new(1, -196, 0, 12)}):Play()

    -- Main panel (hidden until pill clicked)
    local panel = Instance.new("Frame")
    panel.Name = "Panel"; panel.Visible = false
    panel.Size = UDim2.new(0, 340, 0, 430)
    panel.Position = UDim2.new(1, 16, 0, 56)
    panel.BackgroundColor3 = Color3.fromRGB(8, 10, 22)
    panel.BorderSizePixel = 0; panel.Parent = sg
    Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 14)
    local panelStroke = Instance.new("UIStroke", panel)
    panelStroke.Color = Color3.fromRGB(90, 110, 255); panelStroke.Thickness = 1.5

    -- Header
    local header = Instance.new("Frame", panel)
    header.Size = UDim2.new(1, 0, 0, 48)
    header.BackgroundColor3 = Color3.fromRGB(12, 15, 35); header.BorderSizePixel = 0
    Instance.new("UICorner", header).CornerRadius = UDim.new(0, 14)
    local hfix = Instance.new("Frame", header)
    hfix.Size = UDim2.new(1, 0, 0, 14); hfix.Position = UDim2.new(0, 0, 1, -14)
    hfix.BackgroundColor3 = Color3.fromRGB(12, 15, 35); hfix.BorderSizePixel = 0
    local htitle = Instance.new("TextLabel", header)
    htitle.Size = UDim2.new(1, -16, 1, 0); htitle.Position = UDim2.new(0, 16, 0, 0)
    htitle.BackgroundTransparency = 1; htitle.Text = "ANTIGRAVITY AUTO-DEBUGGER  v9"
    htitle.TextColor3 = Color3.fromRGB(200, 215, 255); htitle.Font = Enum.Font.GothamBold
    htitle.TextSize = 12; htitle.TextXAlignment = Enum.TextXAlignment.Left

    -- Status
    local statusBar = Instance.new("Frame", panel)
    statusBar.Size = UDim2.new(1, -24, 0, 28); statusBar.Position = UDim2.new(0, 12, 0, 54)
    statusBar.BackgroundColor3 = Color3.fromRGB(14, 17, 38); statusBar.BorderSizePixel = 0
    Instance.new("UICorner", statusBar).CornerRadius = UDim.new(0, 8)
    local statusLabel = Instance.new("TextLabel", statusBar)
    statusLabel.Size = UDim2.new(1, -12, 1, 0); statusLabel.Position = UDim2.new(0, 8, 0, 0)
    statusLabel.BackgroundTransparency = 1; statusLabel.Text = "Loading in background..."
    statusLabel.TextColor3 = Color3.fromRGB(120, 140, 200); statusLabel.Font = Enum.Font.GothamMedium
    statusLabel.TextSize = 10; statusLabel.TextXAlignment = Enum.TextXAlignment.Left

    -- Progress
    local track = Instance.new("Frame", panel)
    track.Size = UDim2.new(1, -24, 0, 4); track.Position = UDim2.new(0, 12, 0, 88)
    track.BackgroundColor3 = Color3.fromRGB(20, 25, 55); track.BorderSizePixel = 0
    Instance.new("UICorner", track).CornerRadius = UDim.new(1, 0)
    local bar = Instance.new("Frame", track)
    bar.Size = UDim2.new(0, 0, 1, 0)
    bar.BackgroundColor3 = Color3.fromRGB(90, 110, 255); bar.BorderSizePixel = 0
    Instance.new("UICorner", bar).CornerRadius = UDim.new(1, 0)

    -- Stats grid
    local statsFrame = Instance.new("Frame", panel)
    statsFrame.Size = UDim2.new(1, -24, 0, 80); statsFrame.Position = UDim2.new(0, 12, 0, 102)
    statsFrame.BackgroundColor3 = Color3.fromRGB(14, 17, 38); statsFrame.BorderSizePixel = 0
    Instance.new("UICorner", statsFrame).CornerRadius = UDim.new(0, 8)
    local sg2 = Instance.new("UIGridLayout", statsFrame)
    sg2.CellSize = UDim2.new(0.5, -6, 0, 34); sg2.CellPadding = UDim2.new(0, 4, 0, 4)
    sg2.HorizontalAlignment = Enum.HorizontalAlignment.Center
    sg2.VerticalAlignment   = Enum.VerticalAlignment.Center

    local statLabels = {}
    for _, def in ipairs({{"FPS","fps"},{"Ping","ping"},{"Memory","mem"},{"Modules","mods"}}) do
        local cell = Instance.new("Frame", statsFrame)
        cell.BackgroundColor3 = Color3.fromRGB(18, 22, 48); cell.BorderSizePixel = 0
        Instance.new("UICorner", cell).CornerRadius = UDim.new(0, 6)
        local lbl = Instance.new("TextLabel", cell)
        lbl.Size = UDim2.new(1, 0, 1, 0); lbl.BackgroundTransparency = 1
        lbl.Text = def[1] .. "\n--"; lbl.TextColor3 = Color3.fromRGB(160, 180, 255)
        lbl.Font = Enum.Font.GothamMedium; lbl.TextSize = 10
        statLabels[def[2]] = lbl
    end

    -- Module scroll list
    local scroll = Instance.new("ScrollingFrame", panel)
    scroll.Size = UDim2.new(1, -24, 0, 172); scroll.Position = UDim2.new(0, 12, 0, 194)
    scroll.BackgroundColor3 = Color3.fromRGB(14, 17, 38); scroll.BorderSizePixel = 0
    scroll.ScrollBarThickness = 3; scroll.ScrollBarImageColor3 = Color3.fromRGB(90, 110, 255)
    scroll.CanvasSize = UDim2.new(0, 0, 0, 0); scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    Instance.new("UICorner", scroll).CornerRadius = UDim.new(0, 8)
    local sLayout = Instance.new("UIListLayout", scroll)
    sLayout.Padding = UDim.new(0, 2); sLayout.SortOrder = Enum.SortOrder.LayoutOrder
    local sPad = Instance.new("UIPadding", scroll)
    sPad.PaddingLeft = UDim.new(0, 6); sPad.PaddingTop = UDim.new(0, 4)

    -- Close button
    local closeBtn = Instance.new("TextButton", panel)
    closeBtn.Size = UDim2.new(1, -24, 0, 30); closeBtn.Position = UDim2.new(0, 12, 1, -42)
    closeBtn.BackgroundColor3 = Color3.fromRGB(160, 40, 40)
    closeBtn.Text = "CLOSE DEBUGGER"; closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    closeBtn.Font = Enum.Font.GothamBold; closeBtn.TextSize = 10; closeBtn.BorderSizePixel = 0
    Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 8)

    GUI.sg = sg; GUI.pill = pill; GUI.pillDot = pillDot; GUI.pillStroke = pillStroke
    GUI.panel = panel; GUI.panelStroke = panelStroke; GUI.statusLabel = statusLabel
    GUI.bar = bar; GUI.scroll = scroll; GUI.statLabels = statLabels
    GUI.TW = TW; GUI.SPRING = SPRING; GUI.EASE_IN = EASE_IN
    GUI.active = true; GUI.open = false

    local function openPanel()
        if GUI.open then return end
        GUI.open = true; panel.Visible = true
        panel.Position = UDim2.new(1, 16, 0, 56)
        TW:Create(panel, SPRING, {Position = UDim2.new(1, -356, 0, 56)}):Play()
        -- Trigger module execution the first time the panel opens
        if not State.triggered then
            State.triggered = true
            _t.spawn(function() G._DebuggerExecute() end)
        end
    end

    local function closePanel()
        if not GUI.open then return end
        GUI.open = false
        TW:Create(panel, EASE_IN, {Position = UDim2.new(1, 16, 0, 56)}):Play()
        _t.delay(0.3, function() panel.Visible = false end)
    end

    pill.InputBegan:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 or
           inp.UserInputType == Enum.UserInputType.Touch then
            if GUI.open then closePanel() else openPanel() end
        end
    end)

    closeBtn.MouseButton1Click:Connect(function()
        _t.spawn(function()
            closePanel(); _t.wait(0.4)
            _pcall(function() sg:Destroy() end)
            G.DebuggerLoaded = nil
        end)
    end)

    -- Dot pulse (ultra lightweight)
    _t.spawn(function()
        while GUI.active and pill.Parent do
            TW:Create(pillDot, TweenInfo.new(0.8), {BackgroundTransparency = 0}):Play(); _t.wait(0.8)
            TW:Create(pillDot, TweenInfo.new(0.8), {BackgroundTransparency = 0.8}):Play(); _t.wait(0.8)
        end
    end)

    -- Accent color cycle (every 3s, 4 tweens — negligible cost)
    _t.spawn(function()
        local palette = {
            Color3.fromRGB(90,110,255), Color3.fromRGB(80,210,160),
            Color3.fromRGB(210,90,255), Color3.fromRGB(255,160,60),
        }
        local i = 1
        while GUI.active and pill.Parent do
            _t.wait(3); i = (i % #palette) + 1; local c = palette[i]
            TW:Create(pillStroke,  TweenInfo.new(1.2), {Color = c}):Play()
            TW:Create(pillDot,     TweenInfo.new(1.2), {BackgroundColor3 = c}):Play()
            TW:Create(panelStroke, TweenInfo.new(1.2), {Color = c}):Play()
            TW:Create(bar,         TweenInfo.new(1.2), {BackgroundColor3 = c}):Play()
        end
    end)
end)

-- GUI STATUS HELPERS
local function setStatus(msg, pct)
    State.statusText = msg
    _pcall(function()
        if GUI.statusLabel then GUI.statusLabel.Text = msg end
        if GUI.bar and pct then
            GUI.TW:Create(GUI.bar, TweenInfo.new(0.25, Enum.EasingStyle.Quad),
                {Size = UDim2.new(math.clamp(pct, 0, 1), 0, 1, 0)}):Play()
        end
    end)
end

local function addRow(path, ok)
    _pcall(function()
        if not GUI.scroll then return end
        local row = Instance.new("TextLabel")
        row.Size = UDim2.new(1, -6, 0, 18); row.BackgroundTransparency = 1
        row.Text = (ok and "OK  " or "ERR ") .. (path:match("[^/]+$") or path)
        row.TextColor3 = ok and Color3.fromRGB(80, 220, 120) or Color3.fromRGB(220, 80, 80)
        row.Font = Enum.Font.Gotham; row.TextSize = 9
        row.TextXAlignment = Enum.TextXAlignment.Left; row.Parent = GUI.scroll
    end)
end

-- BACKGROUND DOWNLOAD (silent, never blocks game)
_t.spawn(function()
    setStatus("Fetching manifest...", 0.02)
    local mSrc = fetch(RAW .. "/" .. CFG.Manifest) or readLocal(CFG.Manifest)
    if not mSrc then
        setStatus("GitHub unreachable and no cache", 0)
        _warn("[Debugger] Cannot reach GitHub. Enable HTTP in your executor.")
        return
    end
    writeLocal(CFG.Manifest, mSrc)
    local mf = parseManifest(mSrc)
    if not mf then setStatus("Bad manifest", 0); return end

    State.manifest = mf
    State.total    = #mf.files
    setStatus(("v%s | %d files"):format(mf.version, State.total), 0.05)

    -- Parallel download — all fire at once, none block each other
    local done = 0
    for _, entry in ipairs(mf.files) do
        local e = entry
        _t.spawn(function()
            local src = readLocal(e.lpath) or fetch(RAW .. "/" .. e.path)
            State.sources[e.path] = src or false
            if src then writeLocal(e.lpath, src) end
            done = done + 1
            setStatus(("Downloading %d/%d..."):format(done, State.total),
                0.05 + (done / State.total) * 0.65)
        end)
    end

    -- Wait for downloads (poll every 3 frames)
    local t = 0
    while done < State.total and t < 300 do _t.wait(0.05); t = t + 1 end

    State.ready = true
    setStatus(("Ready — click pill to load (%d files)"):format(State.total), 0.70)

    -- If user already opened the panel, start executing immediately
    if State.triggered then
        G._DebuggerExecute()
    end
end)

-- LAZY EXECUTOR: one module per Heartbeat frame = zero stutter
G._DebuggerExecute = function()
    if not State.ready then
        setStatus("Waiting for downloads...", 0.70)
        while not State.ready do _t.wait(0.3) end
    end

    local files = State.manifest and State.manifest.files or {}
    local total = #files
    local RS    = game:GetService("RunService")

    setStatus("Executing modules...", 0.72)

    for i, entry in ipairs(files) do
        local src = State.sources[entry.path]
        if not src or src == false then src = readLocal(entry.lpath) end

        if src and _type(src) == "string" and #src > 0 then
            local fn, cerr
            if loadstring then fn, cerr = loadstring(src, "@" .. entry.path) end
            if fn then
                local ok, rerr = _pcall(fn)
                if ok then
                    State.loaded = State.loaded + 1
                    G.DebuggerModules[entry.path] = {loaded = true}
                    addRow(entry.path, true)
                else
                    State.errors = State.errors + 1
                    G.DebuggerModules[entry.path] = {loaded = false, error = rerr}
                    addRow(entry.path, false)
                    if entry.required then _warn("[Debugger] Required failed: " .. entry.path) end
                end
            else
                State.errors = State.errors + 1
                addRow(entry.path, false)
            end
        else
            if entry.required then
                _warn("[Debugger] Required missing: " .. entry.path)
                State.errors = State.errors + 1
                addRow(entry.path, false)
            end
        end

        -- Update stats label
        _pcall(function()
            if GUI.statLabels and GUI.statLabels.mods then
                GUI.statLabels.mods.Text = "Modules\n" .. State.loaded .. "/" .. total
            end
        end)

        setStatus(("[%d/%d] %s"):format(i, total, entry.path:match("[^/]+$") or entry.path),
            0.72 + (i / total) * 0.27)

        -- ONE frame yield per module — game loop NEVER blocked
        RS.Heartbeat:Wait()
    end

    setStatus(("Done — %d/%d loaded"):format(State.loaded, total), 1.0)
    _print(("[Debugger v9] Complete: %d/%d loaded, %d errors"):format(State.loaded, total, State.errors))
end

-- STATS LOOPS (all throttled, all in separate threads)
_t.spawn(function()
    local Data, tries = nil, 0
    repeat _t.wait(1); Data = G.DebuggerSharedData; tries = tries + 1
    until Data or tries >= 30
    if not Data then return end

    local RS = game:GetService("RunService")

    -- FPS: Heartbeat counter, writes once per second, zero cost
    local frames, lastHb = 0, os.clock()
    RS.Heartbeat:Connect(function()
        frames = frames + 1
        local now = os.clock()
        if now - lastHb >= 1 then
            local fps = math.min(frames, 999)
            _pcall(function() Data.Stats = Data.Stats or {}; Data.Stats.FPS = fps end)
            _pcall(function()
                if GUI.statLabels and GUI.statLabels.fps then
                    GUI.statLabels.fps.Text = "FPS\n" .. fps
                end
            end)
            frames = 0; lastHb = now
        end
    end)

    -- Ping: every 6s, isolated thread
    _t.spawn(function()
        while G.DebuggerLoaded do
            _t.wait(6)
            _pcall(function()
                local v = game:GetService("Stats").Network.ServerStatsItem["Data Ping"].Value
                Data.Stats = Data.Stats or {}; Data.Stats.Ping = math.floor(v)
                if GUI.statLabels and GUI.statLabels.ping then
                    GUI.statLabels.ping.Text = "Ping\n" .. math.floor(v) .. "ms"
                end
            end)
        end
    end)

    -- Memory: every 8s, isolated thread
    _t.spawn(function()
        while G.DebuggerLoaded do
            _t.wait(8)
            _pcall(function()
                local mb = math.floor(gcinfo() / 102.4) / 10
                Data.Stats = Data.Stats or {}; Data.Stats.MemoryMB = mb
                if GUI.statLabels and GUI.statLabels.mem then
                    GUI.statLabels.mem.Text = "Mem\n" .. mb .. "MB"
                end
            end)
        end
    end)

    -- Instance count: every 60s, double-spawned so it can NEVER block
    _t.spawn(function()
        while G.DebuggerLoaded do
            _t.wait(60)
            _t.spawn(function()
                _pcall(function()
                    Data.Stats = Data.Stats or {}
                    Data.Stats.InstanceCount = #game:GetDescendants()
                end)
            end)
        end
    end)

    -- Registered scanners: 8s interval, each in its own isolated thread
    _t.spawn(function()
        local scanErrs = {}
        while G.DebuggerLoaded do
            _t.wait(8)
            local scanners = G.DebuggerScanners or {}
            for idx, fn in ipairs(scanners) do
                _t.spawn(function()
                    local ok, err = _pcall(fn)
                    if not ok then
                        scanErrs[idx] = (scanErrs[idx] or 0) + 1
                        if scanErrs[idx] >= 5 then
                            table.remove(scanners, idx)
                            _warn("[Debugger] Scanner #" .. idx .. " removed: " .. _tostr(err))
                        end
                    else
                        scanErrs[idx] = 0
                    end
                end)
                _t.wait(0.2)
            end
        end
    end)
end)

-- PUBLIC API
G.DebuggerHotReload = function(path)
    if not path then _print("[HotReload] DebuggerHotReload('path/to/file.lua')"); return end
    _t.spawn(function()
        _print("[HotReload] " .. path)
        local src = fetch(RAW .. "/" .. path)
        if not src then _warn("[HotReload] Download failed: " .. path); return end
        writeLocal(path, src)
        local fn, err = loadstring and loadstring(src, "@" .. path)
        if not fn then _warn("[HotReload] Compile: " .. _tostr(err)); return end
        local ok, rerr = _pcall(fn)
        if ok then
            _print("[HotReload] OK: " .. path)
            G.DebuggerModules[path] = {loaded = true, reloaded = true}
        else
            _warn("[HotReload] Error: " .. _tostr(rerr))
        end
    end)
end

_print("[Debugger v9] Booted — click the pill button to open.")
