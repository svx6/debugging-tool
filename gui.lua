--[[
    ========================================================================
    ULTIMATE ROBLOX AUTO-DEBUGGER  ·  GUI DASHBOARD  (v7.1)
    ========================================================================
    Mobile + PC compatible:
      · UserInputService drag (touch & mouse — both work)
      · Touch-friendly hit areas (min 44px height)
      · Responsive: detects mobile and scales UI accordingly
    Animations:
      · Window fade-in + scale entrance on open
      · Tab switch: outgoing fades, incoming slides in
      · Sidebar tabs stagger in one by one on load
      · Buttons: press scale-down feedback
      · Cards: hover lift effect
      · Header accent line pulses
      · Boot: each section fades in with a delay
    ========================================================================
--]]

local Data = getgenv().DebuggerSharedData
if not Data then warn("[GUI v7.1]: Core not loaded.") return end

local Players    = game:GetService("Players")
local TweenSvc   = game:GetService("TweenService")
local UIS        = game:GetService("UserInputService")
local LP         = Players.LocalPlayer

-- ── Detect mobile ──────────────────────────────────────────────────────────
local isMobile = false
pcall(function()
    isMobile = UIS.TouchEnabled and not UIS.MouseEnabled
end)

-- Scale factor: mobile gets slightly larger touch targets
local SCALE = isMobile and 1.18 or 1.0
local function S(n) return math.floor(n * SCALE + 0.5) end  -- scale a pixel value

-- ── Safe UI Parent ─────────────────────────────────────────────────────────
local UIParent
do
    local ok, cg = pcall(function()
        local g = game:GetService("CoreGui")
        local t = Instance.new("Frame"); t.Parent = g; t:Destroy()
        return g
    end)
    UIParent = (ok and cg) or LP:WaitForChild("PlayerGui")
end

pcall(function()
    for _, name in ipairs({"AutoDebuggerUI_v7", "AutoDebuggerUI"}) do
        local old = UIParent:FindFirstChild(name)
        if old then old:Destroy() end
    end
end)

-- ── ScreenGui ──────────────────────────────────────────────────────────────
local Screen = Instance.new("ScreenGui")
Screen.Name            = "AutoDebuggerUI_v7"
Screen.ResetOnSpawn    = false
Screen.ZIndexBehavior  = Enum.ZIndexBehavior.Sibling
Screen.DisplayOrder    = 999
Screen.IgnoreGuiInset  = true
Screen.Parent          = UIParent

-- ── Palette ────────────────────────────────────────────────────────────────
local C = {
    bg0      = Color3.fromRGB(8,  10, 18),
    bg1      = Color3.fromRGB(12, 15, 26),
    bg2      = Color3.fromRGB(18, 22, 38),
    card     = Color3.fromRGB(22, 26, 44),
    cardHov  = Color3.fromRGB(28, 33, 55),
    sidebar  = Color3.fromRGB(11, 14, 24),
    header   = Color3.fromRGB(14, 17, 30),
    stroke   = Color3.fromRGB(40, 48, 80),
    strokeLt = Color3.fromRGB(60, 70, 110),
    accent   = Color3.fromRGB(90, 105, 248),
    accentDk = Color3.fromRGB(30, 38, 88),
    accentLt = Color3.fromRGB(130, 145, 255),
    text0    = Color3.fromRGB(230, 232, 255),
    text1    = Color3.fromRGB(140, 150, 190),
    text2    = Color3.fromRGB(80,  90, 130),
    code     = Color3.fromRGB(185, 200, 240),
    red      = Color3.fromRGB(240, 70,  70),  redDk  = Color3.fromRGB(55, 15, 15),
    orange   = Color3.fromRGB(245, 168, 50),  orangeDk=Color3.fromRGB(55, 35, 10),
    green    = Color3.fromRGB(72,  215, 128), greenDk= Color3.fromRGB(12, 52, 28),
    blue     = Color3.fromRGB(65,  145, 248), blueDk = Color3.fromRGB(12, 32, 65),
    purple   = Color3.fromRGB(172, 120, 255), purpleDk=Color3.fromRGB(30, 20, 58),
    teal     = Color3.fromRGB(48,  210, 198), tealDk = Color3.fromRGB(8,  48, 46),
    yellow   = Color3.fromRGB(255, 218, 50),
}

-- ── Tween presets ──────────────────────────────────────────────────────────
local FAST   = TweenInfo.new(0.14, Enum.EasingStyle.Quad)
local MED    = TweenInfo.new(0.25, Enum.EasingStyle.Quad)
local SLOW   = TweenInfo.new(0.45, Enum.EasingStyle.Sine)
local BOUNCE = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local function tw(obj, info, props) TweenSvc:Create(obj, info, props):Play() end

-- ── Primitives ─────────────────────────────────────────────────────────────
local function corner(p, r)
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r or 8); c.Parent = p; return c
end
local function strok(p, col, th)
    local s = Instance.new("UIStroke"); s.Color = col or C.stroke; s.Thickness = th or 1.2; s.Parent = p; return s
end
local function pad(p, t, b, l, r)
    local pd = Instance.new("UIPadding")
    pd.PaddingTop    = UDim.new(0, t or 0); pd.PaddingBottom = UDim.new(0, b or 0)
    pd.PaddingLeft   = UDim.new(0, l or 0); pd.PaddingRight  = UDim.new(0, r or 0)
    pd.Parent = p; return pd
end
local function vlist(p, spacing)
    local l = Instance.new("UIListLayout")
    l.FillDirection = Enum.FillDirection.Vertical
    l.Padding       = UDim.new(0, spacing or 5)
    l.SortOrder     = Enum.SortOrder.LayoutOrder
    l.Parent = p; return l
end
local function lbl(parent, props)
    local l = Instance.new("TextLabel")
    l.BackgroundTransparency = 1; l.Font = Enum.Font.GothamMedium
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.TextYAlignment = Enum.TextYAlignment.Center
    l.TextWrapped = false
    for k, v in pairs(props) do pcall(function() l[k] = v end) end
    l.Parent = parent; return l
end

-- Smart button: press scale + hover glow
local function mkBtn(parent, props)
    local b = Instance.new("TextButton")
    b.BackgroundColor3 = C.accentDk; b.TextColor3 = C.text0
    b.Font = Enum.Font.GothamBold; b.TextSize = S(11)
    b.AutoButtonColor = false
    for k, v in pairs(props) do pcall(function() b[k] = v end) end
    b.Parent = parent
    corner(b, 6)
    b.MouseEnter:Connect(function()  tw(b, FAST, {BackgroundColor3 = C.cardHov}) end)
    b.MouseLeave:Connect(function()  tw(b, FAST, {BackgroundColor3 = b.BackgroundColor3}) end)
    -- Press feedback
    b.MouseButton1Down:Connect(function()
        tw(b, TweenInfo.new(0.08), {Size = UDim2.new(
            b.Size.X.Scale, b.Size.X.Offset - 2,
            b.Size.Y.Scale, b.Size.Y.Offset - 2)})
    end)
    b.MouseButton1Up:Connect(function()
        tw(b, BOUNCE, {Size = b.Size})
    end)
    return b
end

local function miniBtn(parent, text_, bgCol, txCol, w, x, y)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(0, w or 80, 0, S(26))
    if x then b.Position = UDim2.new(0, x, 0, y or 0) end
    b.BackgroundColor3 = bgCol or C.accentDk
    b.TextColor3 = txCol or C.text0
    b.Font = Enum.Font.GothamBold; b.TextSize = S(10)
    b.Text = text_; b.AutoButtonColor = false
    b.Parent = parent
    corner(b, 5); strok(b, txCol or C.stroke, 1)
    b.MouseButton1Down:Connect(function()
        tw(b, TweenInfo.new(0.07), {BackgroundTransparency = 0.35})
    end)
    b.MouseButton1Up:Connect(function()
        tw(b, TweenInfo.new(0.12), {BackgroundTransparency = 0})
    end)
    return b
end

-- ── Window dimensions ──────────────────────────────────────────────────────
local WIN_W = isMobile and 680 or 900
local WIN_H = isMobile and 420 or 560
local SIDE_W = isMobile and 140 or 172
local HEADER_H = S(50)

-- ── Main Window ────────────────────────────────────────────────────────────
local Main = Instance.new("Frame")
Main.Name              = "Main"
Main.AnchorPoint       = Vector2.new(0.5, 0.5)
Main.Size              = UDim2.new(0, WIN_W, 0, WIN_H)
Main.Position          = UDim2.new(0.5, 0, 0.5, 0)
Main.BackgroundColor3  = C.bg0
Main.BorderSizePixel   = 0
Main.ClipsDescendants  = true
Main.Parent            = Screen
corner(Main, 14); strok(Main, C.stroke, 1.5)

-- Background gradient
local bgGrad = Instance.new("UIGradient")
bgGrad.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0,   Color3.fromRGB(12, 15, 28)),
    ColorSequenceKeypoint.new(0.5, Color3.fromRGB(8,  10, 18)),
    ColorSequenceKeypoint.new(1,   Color3.fromRGB(14, 10, 22)),
})
bgGrad.Rotation = 135; bgGrad.Parent = Main

-- ── ENTRANCE ANIMATION ──────────────────────────────────────────────────────
-- Start invisible and scaled down, then animate in
Main.BackgroundTransparency = 1
Main.Size = UDim2.new(0, WIN_W * 0.88, 0, WIN_H * 0.88)

task.defer(function()
    -- Fade + scale in over 0.4s
    tw(Main, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
        Size = UDim2.new(0, WIN_W, 0, WIN_H),
        BackgroundTransparency = 0,
    })
end)

-- ══════════════════════════════════════════════════════════════════════════
--  DRAG SYSTEM — works on both PC (mouse) and mobile (touch)
-- ══════════════════════════════════════════════════════════════════════════
do
    local dragging   = false
    local dragStart  = nil   -- Vector2 cursor position when drag began
    local startPos   = nil   -- Main.Position when drag began

    local function beginDrag(inputPos)
        dragging  = true
        dragStart = inputPos
        -- Convert current position to absolute for math
        startPos  = Main.AbsolutePosition + Main.AbsoluteSize * Main.AnchorPoint
    end

    local function moveDrag(inputPos)
        if not dragging then return end
        local delta   = inputPos - dragStart
        local vp      = Camera and Camera.ViewportSize or Vector2.new(1920, 1080)
        pcall(function() vp = workspace.CurrentCamera.ViewportSize end)

        -- Clamp so window can't leave screen
        local newX = math.clamp(startPos.X + delta.X, WIN_W/2, vp.X - WIN_W/2)
        local newY = math.clamp(startPos.Y + delta.Y, WIN_H/2, vp.Y - WIN_H/2)

        Main.Position = UDim2.new(0, newX, 0, newY)
    end

    local function endDrag()
        dragging = false
    end

    -- Mouse
    UIS.InputBegan:Connect(function(input, gpe)
        if gpe then return end
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            local hdr = Main:FindFirstChild("Header")
            if hdr then
                local mp = input.Position
                local ap = hdr.AbsolutePosition
                local as = hdr.AbsoluteSize
                if mp.X >= ap.X and mp.X <= ap.X + as.X
                and mp.Y >= ap.Y and mp.Y <= ap.Y + as.Y then
                    beginDrag(Vector2.new(mp.X, mp.Y))
                end
            end
        end
    end)
    UIS.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement then
            moveDrag(Vector2.new(input.Position.X, input.Position.Y))
        end
    end)
    UIS.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then endDrag() end
    end)

    -- Touch (mobile)
    local touchId = nil
    UIS.InputBegan:Connect(function(input, gpe)
        if gpe then return end
        if input.UserInputType == Enum.UserInputType.Touch and touchId == nil then
            local hdr = Main:FindFirstChild("Header")
            if hdr then
                local tp = input.Position
                local ap = hdr.AbsolutePosition
                local as = hdr.AbsoluteSize
                if tp.X >= ap.X and tp.X <= ap.X + as.X
                and tp.Y >= ap.Y and tp.Y <= ap.Y + as.Y then
                    touchId = input
                    beginDrag(Vector2.new(tp.X, tp.Y))
                end
            end
        end
    end)
    UIS.InputChanged:Connect(function(input)
        if input == touchId then
            moveDrag(Vector2.new(input.Position.X, input.Position.Y))
        end
    end)
    UIS.InputEnded:Connect(function(input)
        if input == touchId then touchId = nil; endDrag() end
    end)
end

-- ── Header ─────────────────────────────────────────────────────────────────
local Header = Instance.new("Frame")
Header.Name            = "Header"
Header.Size            = UDim2.new(1, 0, 0, HEADER_H)
Header.BackgroundColor3 = C.header
Header.BorderSizePixel = 0
Header.ZIndex          = 2
Header.Parent          = Main

local hGrad = Instance.new("UIGradient")
hGrad.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0,   Color3.fromRGB(16, 20, 44)),
    ColorSequenceKeypoint.new(0.5, Color3.fromRGB(22, 26, 54)),
    ColorSequenceKeypoint.new(1,   Color3.fromRGB(14, 18, 38)),
})
hGrad.Rotation = 90; hGrad.Parent = Header

-- Pulsing accent underline
local hLine = Instance.new("Frame")
hLine.Name             = "AccentLine"
hLine.Size             = UDim2.new(1, 0, 0, 2)
hLine.Position         = UDim2.new(0, 0, 1, 0)
hLine.BackgroundColor3 = C.accent
hLine.BackgroundTransparency = 0.3
hLine.BorderSizePixel  = 0
hLine.Parent           = Header

task.spawn(function()
    while Screen.Parent do
        tw(hLine, SLOW, {BackgroundTransparency = 0.05})
        task.wait(0.55)
        tw(hLine, SLOW, {BackgroundTransparency = 0.7})
        task.wait(0.55)
    end
end)

-- Title
lbl(Header, {
    Text="⚙  ANTIGRAVITY  AUTO-DEBUGGER",
    Size=UDim2.new(0, 260, 1, 0), Position=UDim2.new(0, 10, 0, 0),
    TextColor3=C.text0, Font=Enum.Font.GothamBold, TextSize=S(13), ZIndex=3,
})
lbl(Header, {
    Text="v7.1",
    Size=UDim2.new(0, 30, 0, 16), Position=UDim2.new(0, 272, 0, 17),
    TextColor3=C.accent, Font=Enum.Font.GothamBold, TextSize=S(9), ZIndex=3,
})

-- Runtime pills
local execLbl = lbl(Header, {
    Text="● " .. (Data.Stats.ExecutorName or "?"),
    Size=UDim2.new(0, 110, 1, 0), Position=UDim2.new(0, 310, 0, 0),
    TextColor3=C.green, Font=Enum.Font.GothamMedium, TextSize=S(10), ZIndex=3,
})
lbl(Header, {
    Text=(Data.Stats.GameName or "?"):sub(1, 20),
    Size=UDim2.new(0, 148, 1, 0), Position=UDim2.new(0, 422, 0, 0),
    TextColor3=C.text1, Font=Enum.Font.GothamMedium, TextSize=S(10), ZIndex=3,
})
local uptimeLbl = lbl(Header, {
    Text="⏱ 00:00:00",
    Size=UDim2.new(0, 80, 1, 0), Position=UDim2.new(0, 572, 0, 0),
    TextColor3=C.text2, Font=Enum.Font.GothamMedium, TextSize=S(9), ZIndex=3,
})

-- Uptime ticker
task.spawn(function()
    while Screen.Parent do
        task.wait(1)
        pcall(function() uptimeLbl.Text = "⏱ " .. Data:Uptime() end)
    end
end)

-- Mobile indicator
if isMobile then
    lbl(Header, {
        Text="📱", Size=UDim2.new(0, 20, 1, 0), Position=UDim2.new(0, 654, 0, 0),
        TextColor3=C.text2, Font=Enum.Font.GothamBold, TextSize=14, ZIndex=3,
    })
end

-- Min / Close
local minBtn = Instance.new("TextButton")
minBtn.Size=UDim2.new(0, S(32), 0, S(32)); minBtn.Position=UDim2.new(1, -S(72), 0, S(9))
minBtn.BackgroundColor3=C.bg2; minBtn.Text="—"; minBtn.TextColor3=C.text1
minBtn.Font=Enum.Font.GothamBold; minBtn.TextSize=S(14)
minBtn.AutoButtonColor=false; minBtn.ZIndex=3; minBtn.Parent=Header
corner(minBtn, 7)

local closeBtn = Instance.new("TextButton")
closeBtn.Size=UDim2.new(0, S(32), 0, S(32)); closeBtn.Position=UDim2.new(1, -S(36), 0, S(9))
closeBtn.BackgroundColor3=Color3.fromRGB(185, 40, 40); closeBtn.Text="✕"
closeBtn.TextColor3=Color3.new(1,1,1); closeBtn.Font=Enum.Font.GothamBold
closeBtn.TextSize=S(13); closeBtn.AutoButtonColor=false; closeBtn.ZIndex=3; closeBtn.Parent=Header
corner(closeBtn, 7)

local minimised = false
minBtn.MouseButton1Click:Connect(function()
    minimised = not minimised
    tw(Main, MED, {Size = minimised
        and UDim2.new(0, WIN_W, 0, HEADER_H)
        or  UDim2.new(0, WIN_W, 0, WIN_H)})
    minBtn.Text = minimised and "▲" or "—"
end)
closeBtn.MouseButton1Click:Connect(function()
    tw(Main, MED, {Size = UDim2.new(0, WIN_W*0.9, 0, WIN_H*0.9), BackgroundTransparency = 1})
    task.delay(0.25, function()
        Screen:Destroy()
        getgenv().DebuggerLoaded = nil
    end)
end)

-- ── Sidebar ─────────────────────────────────────────────────────────────────
local Sidebar = Instance.new("ScrollingFrame")
Sidebar.Name              = "Sidebar"
Sidebar.Size              = UDim2.new(0, SIDE_W, 1, -(HEADER_H + 2))
Sidebar.Position          = UDim2.new(0, 0, 0, HEADER_H + 2)
Sidebar.BackgroundColor3  = C.sidebar
Sidebar.BorderSizePixel   = 0
Sidebar.ScrollBarThickness = 3
Sidebar.ScrollBarImageColor3 = C.accentDk
Sidebar.Parent            = Main
strok(Sidebar, C.stroke, 1)
pad(Sidebar, 8, 8, 0, 0)
vlist(Sidebar, 3)

-- ── Page Area ───────────────────────────────────────────────────────────────
local PAD_L = SIDE_W + 6
local PageArea = Instance.new("Frame")
PageArea.Name = "PageArea"
PageArea.Size = UDim2.new(1, -PAD_L - 4, 1, -(HEADER_H + 4))
PageArea.Position = UDim2.new(0, PAD_L, 0, HEADER_H + 4)
PageArea.BackgroundTransparency = 1
PageArea.Parent = Main

-- ══════════════════════════════════════════════════════════════════════════
--  TAB SYSTEM with fade animations
-- ══════════════════════════════════════════════════════════════════════════
local pageMap  = {}
local tabBtns  = {}
local curTab   = nil

local function makePage(name)
    local sf = Instance.new("ScrollingFrame")
    sf.Name                  = name
    sf.Size                  = UDim2.new(1, 0, 1, 0)
    sf.BackgroundTransparency = 1
    sf.BorderSizePixel       = 0
    sf.CanvasSize            = UDim2.new(0, 0, 0, 0)
    sf.AutomaticCanvasSize   = Enum.AutomaticSize.Y
    sf.ScrollBarThickness    = 4
    sf.ScrollBarImageColor3  = C.accentDk
    sf.Visible               = false
    sf.Parent                = PageArea
    vlist(sf, 5)
    pad(sf, 4, 10, 4, 6)
    pageMap[name] = sf
    return sf
end

local function switchTab(name, tabBtn)
    if curTab == name then return end

    -- Fade out current page
    if curTab and pageMap[curTab] then
        local old = pageMap[curTab]
        tw(old, FAST, {GroupTransparency = 1})
        task.delay(0.14, function()
            if old.Parent then old.Visible = false; old.GroupTransparency = 0 end
        end)
    end

    curTab = name

    -- Fade + slide in new page
    if pageMap[name] then
        local pg = pageMap[name]
        pg.Position = UDim2.new(0.04, 0, 0, 0)
        pg.GroupTransparency = 1
        pg.Visible = true
        tw(pg, MED, {GroupTransparency = 0, Position = UDim2.new(0, 0, 0, 0)})
    end

    -- Update tab button styles
    for n, tb in pairs(tabBtns) do
        if n == name then
            tw(tb, FAST, {BackgroundColor3 = C.accent, TextColor3 = Color3.new(1,1,1)})
        else
            tw(tb, FAST, {BackgroundColor3 = C.bg2, TextColor3 = C.text1})
        end
    end
end

local tabOrder = 0
local function addTab(icon, labelTxt, pageName)
    tabOrder = tabOrder + 1
    local tb = Instance.new("TextButton")
    tb.Size             = UDim2.new(1, -14, 0, S(38))
    tb.BackgroundColor3 = C.bg2
    tb.TextColor3       = C.text1
    tb.Font             = Enum.Font.GothamMedium
    tb.TextSize         = S(11)
    tb.TextXAlignment   = Enum.TextXAlignment.Left
    tb.AutoButtonColor  = false
    tb.Text             = icon .. "  " .. labelTxt
    -- Start invisible for stagger animation
    tb.BackgroundTransparency = 1
    tb.TextTransparency = 1
    tb.Parent           = Sidebar
    corner(tb, 7); pad(tb, 0, 0, 12, 0)

    -- Stagger reveal animation (each tab appears 0.06s after the previous)
    local order = tabOrder
    task.delay(0.05 + order * 0.06, function()
        if tb.Parent then
            tw(tb, MED, {BackgroundTransparency = 0, TextTransparency = 0})
        end
    end)

    tb.MouseEnter:Connect(function()
        if curTab ~= pageName then tw(tb, FAST, {BackgroundColor3 = C.cardHov}) end
    end)
    tb.MouseLeave:Connect(function()
        if curTab ~= pageName then tw(tb, FAST, {BackgroundColor3 = C.bg2}) end
    end)
    tb.MouseButton1Down:Connect(function()
        tw(tb, TweenInfo.new(0.07), {Size = UDim2.new(1, -18, 0, S(35))})
    end)
    tb.MouseButton1Up:Connect(function()
        tw(tb, BOUNCE, {Size = UDim2.new(1, -14, 0, S(38))})
        switchTab(pageName, tb)
    end)
    -- Touch support
    tb.TouchTap:Connect(function() switchTab(pageName, tb) end)

    tabBtns[pageName] = tb
    return tb
end

-- ── Widget helpers ──────────────────────────────────────────────────────────
local function sectionTitle(parent, text, order)
    local f = Instance.new("Frame")
    f.Size = UDim2.new(1, 0, 0, S(20)); f.BackgroundTransparency = 1
    f.LayoutOrder = order or 0; f.Parent = parent
    lbl(f, {Text=text, Size=UDim2.new(1,0,1,0), TextColor3=C.text2, Font=Enum.Font.GothamBold, TextSize=S(9)})
    return f
end

-- Card with hover lift animation
local function card(parent, heightPx, order)
    local f = Instance.new("Frame")
    f.Size = UDim2.new(1, 0, 0, heightPx or S(60))
    f.BackgroundColor3 = C.card; f.BorderSizePixel = 0
    f.LayoutOrder = order or 0; f.Parent = parent
    corner(f, 8); strok(f, C.stroke, 1)
    -- Hover lift
    local origColor = C.card
    f.MouseEnter:Connect(function()
        tw(f, FAST, {BackgroundColor3 = C.cardHov})
    end)
    f.MouseLeave:Connect(function()
        tw(f, FAST, {BackgroundColor3 = origColor})
    end)
    return f
end

-- ── Create all pages ────────────────────────────────────────────────────────
local dashPage = makePage("Dashboard")
local conPage  = makePage("Console")
local netPage  = makePage("Network")
local arPage   = makePage("AutoRemote")
local bugPage  = makePage("Bugs")
local cdPage   = makePage("CoreDebug")
local dlPage   = makePage("Download")
local ghPage   = makePage("GitHub")
local aiPage   = makePage("AI")
local shPage   = makePage("ScriptHook")   -- NEW
local crashPage= makePage("CrashLog")     -- NEW
local vwPage   = makePage("ValueWatch")   -- NEW

local dashBtn = addTab("📊", "Dashboard",    "Dashboard")
               addTab("💻", "Console",       "Console")
               addTab("📡", "Network Spy",   "Network")
               addTab("🔗", "Auto Remote",   "AutoRemote")
               addTab("⚠️", "Bug Center",    "Bugs")
               addTab("🔬", "Core Debugger", "CoreDebug")
               addTab("📥", "Download Game", "Download")
               addTab("⬡", "GitHub Sync",   "GitHub")
               addTab("🤖", "AI Insights",   "AI")
               addTab("🔐", "Script Hook",   "ScriptHook")   -- NEW
               addTab("💥", "Crash Log",     "CrashLog")     -- NEW
               addTab("👁", "Value Watcher", "ValueWatch")   -- NEW

-- Small separator above first tab
local sep = Instance.new("Frame")
sep.Size=UDim2.new(0.9,0,0,1); sep.BackgroundColor3=C.stroke
sep.BorderSizePixel=0; sep.Parent=Sidebar
local sepLayout = Instance.new("UIPadding"); sepLayout.PaddingLeft=UDim.new(0,7); sepLayout.Parent=sep

-- Switch to Dashboard after stagger animations are queued
task.delay(0.08, function()
    switchTab("Dashboard", dashBtn)
end)

-- ══════════════════════════════════════════════════════════════════════════
--  HELPER: lazy render — adds content gradually to a page to avoid lag
--  Usage: lazyRender(list, renderFn, batchSize, delayBetween)
-- ══════════════════════════════════════════════════════════════════════════
local function lazyRender(list, renderFn, batchSize, delay)
    batchSize = batchSize or 5
    delay     = delay     or 0.05
    task.spawn(function()
        local i = 1
        while i <= #list do
            for b = 1, batchSize do
                if list[i] then
                    pcall(renderFn, list[i])
                    i = i + 1
                else
                    break
                end
            end
            task.wait(delay)
        end
    end)
end

-- ══════════════════════════════════════════════════════════════════════════
--  DASHBOARD
-- ══════════════════════════════════════════════════════════════════════════
local statGrid = Instance.new("Frame")
statGrid.Size = UDim2.new(1, 0, 0, S(175))
statGrid.BackgroundTransparency = 1; statGrid.LayoutOrder = 1; statGrid.Parent = dashPage

local gridL = Instance.new("UIGridLayout")
gridL.CellSize = UDim2.new(0.30, -4, 0, S(76))
gridL.CellPadding = UDim2.new(0.018, 0, 0, S(6))
gridL.HorizontalAlignment = Enum.HorizontalAlignment.Center; gridL.Parent = statGrid

local statVals = {}
local function makeStatCard(title)
    local f = Instance.new("Frame"); f.BackgroundColor3=C.card; f.BorderSizePixel=0; f.Parent=statGrid
    corner(f,8); strok(f, C.strokeLt, 1)
    lbl(f,{Text=title:upper(), Size=UDim2.new(1,-12,0,S(16)), Position=UDim2.new(0,8,0,S(6)),
        TextColor3=C.text2, Font=Enum.Font.GothamBold, TextSize=S(8)})
    local vl=lbl(f,{Text="—", Size=UDim2.new(1,-12,0,S(36)), Position=UDim2.new(0,8,0,S(22)),
        TextColor3=C.text0, Font=Enum.Font.GothamBold, TextSize=S(23)})
    return vl
end

statVals.errors   = makeStatCard("Errors")
statVals.remotes  = makeStatCard("Remotes")
statVals.bugs     = makeStatCard("Bugs")
statVals.instances= makeStatCard("Instances")
statVals.fps      = makeStatCard("FPS")
statVals.ping     = makeStatCard("Ping")
statVals.memory   = makeStatCard("Memory MB")
statVals.scans    = makeStatCard("Scan Passes")
statVals.errRate  = makeStatCard("Err / sec")

local ctrlCard = card(dashPage, S(80), 2)
lbl(ctrlCard, {Text="QUICK CONTROLS", Size=UDim2.new(1,-24,0,S(18)), Position=UDim2.new(0,12,0,S(6)),
    TextColor3=C.text2, Font=Enum.Font.GothamBold, TextSize=S(8)})

local healBtn = Instance.new("TextButton")
healBtn.Size=UDim2.new(0.46,0,0,S(34)); healBtn.Position=UDim2.new(0,12,0,S(28))
healBtn.BackgroundColor3=C.accentDk; healBtn.Text="🩹  Auto-Heal Physics:  OFF"
healBtn.TextColor3=C.text0; healBtn.Font=Enum.Font.GothamBold; healBtn.TextSize=S(11)
healBtn.AutoButtonColor=false; healBtn.Parent=ctrlCard; corner(healBtn,7)
healBtn.MouseButton1Click:Connect(function()
    Data.Settings.AutoClean = not Data.Settings.AutoClean
    local on = Data.Settings.AutoClean
    healBtn.Text="🩹  Auto-Heal Physics:  " .. (on and "ON" or "OFF")
    tw(healBtn, MED, {BackgroundColor3 = on and Color3.fromRGB(22,80,45) or C.accentDk})
end)

local qDlBtn = Instance.new("TextButton")
qDlBtn.Size=UDim2.new(0.46,0,0,S(34)); qDlBtn.Position=UDim2.new(0.52,0,0,S(28))
qDlBtn.BackgroundColor3=C.tealDk; qDlBtn.Text="📥  Quick Download"
qDlBtn.TextColor3=C.teal; qDlBtn.Font=Enum.Font.GothamBold; qDlBtn.TextSize=S(11)
qDlBtn.AutoButtonColor=false; qDlBtn.Parent=ctrlCard; corner(qDlBtn,7); strok(qDlBtn,C.teal,1)
qDlBtn.MouseButton1Click:Connect(function()
    qDlBtn.Text="⟳  Downloading..."; qDlBtn.Active=false
    task.spawn(function()
        if Data.DownloadScriptsOnly then Data.DownloadScriptsOnly() end
        task.wait(1.5)
        pcall(function() qDlBtn.Text="📥  Quick Download"; qDlBtn.Active=true end)
    end)
end)

-- Dashboard poll
task.spawn(function()
    while Screen.Parent do
        task.wait(1)
        pcall(function()
            statVals.errors.Text    = tostring(Data.Stats.Errors)
            statVals.remotes.Text   = tostring(Data.Stats.RemotesHooked)
            statVals.bugs.Text      = tostring(Data.Stats.BugsFound)
            statVals.instances.Text = tostring(Data.Stats.InstanceCount)
            statVals.fps.Text       = tostring(Data.Stats.FPS)
            statVals.ping.Text      = tostring(Data.Stats.Ping) .. "ms"
            statVals.scans.Text     = tostring(Data.Stats.ScanCount)
            if Data.CoreDebugger then
                statVals.memory.Text  = tostring(Data.CoreDebugger.MemoryUsageMB) .. "MB"
                statVals.errRate.Text = tostring(Data.CoreDebugger.ErrorRate) .. "/s"
            end
            statVals.fps.TextColor3    = Data.Stats.FPS < 25 and C.red or C.green
            statVals.ping.TextColor3   = Data.Stats.Ping > 300 and C.orange or C.green
            statVals.errors.TextColor3 = Data.Stats.Errors > 0 and C.red or C.text0
            statVals.bugs.TextColor3   = Data.Stats.BugsFound > 0 and C.orange or C.text0
        end)
    end
end)

-- ══════════════════════════════════════════════════════════════════════════
--  CONSOLE LOG
-- ══════════════════════════════════════════════════════════════════════════
local typeColor = {Error=C.red, Warning=C.orange, Info=C.blue}
local typeBg    = {Error=C.redDk, Warning=C.orangeDk, Info=C.blueDk}

local conFilterBar = card(conPage, S(40), -1000)
local conAll = miniBtn(conFilterBar,"All",    C.accentDk,C.text0, S(48),  S(8), S(8))
local conErr = miniBtn(conFilterBar,"Errors", C.redDk,   C.red,   S(56),  S(62),S(8))
local conWrn = miniBtn(conFilterBar,"Warns",  C.orangeDk,C.orange,S(54), S(124),S(8))
local conInf = miniBtn(conFilterBar,"Info",   C.blueDk,  C.blue,  S(48), S(184),S(8))
local conClr = miniBtn(conFilterBar,"⊘ Clear",C.bg2,     C.text1, S(60), S(238),S(8))

local conFilterType = nil
local function setConFilter(t, ab)
    conFilterType = t
    for _, b in ipairs({conAll,conErr,conWrn,conInf}) do
        tw(b, FAST, {BackgroundTransparency = b==ab and 0 or 0.55})
    end
end
conAll.MouseButton1Click:Connect(function() setConFilter(nil, conAll) end)
conErr.MouseButton1Click:Connect(function() setConFilter("Error", conErr) end)
conWrn.MouseButton1Click:Connect(function() setConFilter("Warning", conWrn) end)
conInf.MouseButton1Click:Connect(function() setConFilter("Info", conInf) end)
conClr.MouseButton1Click:Connect(function()
    for _, ch in ipairs(conPage:GetChildren()) do
        if ch:IsA("Frame") and ch ~= conFilterBar then ch:Destroy() end
    end
    table.clear(Data.Logs)
end)

local function renderLog(entry)
    if conFilterType and entry.Type ~= conFilterType then return end
    local lt  = entry.Type or "Info"
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, S(24)); row.BackgroundColor3 = typeBg[lt] or C.card
    row.BorderSizePixel=0; row.AutomaticSize=Enum.AutomaticSize.Y; row.Parent=conPage
    corner(row, 4)
    local bar = Instance.new("Frame")
    bar.Size=UDim2.new(0,3,1,-4); bar.Position=UDim2.new(0,2,0,2)
    bar.BackgroundColor3=typeColor[lt] or C.blue; bar.BorderSizePixel=0; bar.Parent=row; corner(bar,2)
    lbl(row, {
        Text=string.format("[%s][%s] %s", entry.Time or "?", lt, entry.Text or ""),
        Size=UDim2.new(1,-14,1,4), Position=UDim2.new(0,10,0,0),
        TextColor3=typeColor[lt] or C.code, Font=Enum.Font.Code, TextSize=S(10),
        TextWrapped=true, TextYAlignment=Enum.TextYAlignment.Top,
    })
end

-- Lazy-render existing logs
task.delay(0.3, function()
    lazyRender(Data.Logs, renderLog, 8, 0.04)
end)
Data:Subscribe("OnLogAdded", function(entry) pcall(renderLog, entry) end)

-- ══════════════════════════════════════════════════════════════════════════
--  NETWORK SPY
-- ══════════════════════════════════════════════════════════════════════════
local netFrames = {}
local function renderNet(rd)
    if netFrames[rd.Path] then
        local f = netFrames[rd.Path]
        if f and f.Parent then
            pcall(function()
                f:FindFirstChild("Cnt").Text = "×" .. tostring(rd.Calls)
                f:FindFirstChild("Args").Text = "Args: " .. (#rd.Args>0 and table.concat(rd.Args,"  ") or "—")
            end)
            return
        end
        netFrames[rd.Path] = nil
    end
    local f = card(netPage, S(62))
    netFrames[rd.Path] = f
    lbl(f,{Text="📡  " .. rd.Name .. "  —  " .. (rd.Method or "?"),
        Size=UDim2.new(0.7,0,0,S(22)), Position=UDim2.new(0,10,0,S(4)),
        TextColor3=C.blue, Font=Enum.Font.GothamBold, TextSize=S(11)})
    lbl(f,{Name="Cnt", Text="×" .. tostring(rd.Calls),
        Size=UDim2.new(0.25,0,0,S(22)), Position=UDim2.new(0.73,0,0,S(4)),
        TextColor3=C.green, Font=Enum.Font.GothamBold, TextSize=S(13),
        TextXAlignment=Enum.TextXAlignment.Right})
    lbl(f,{Text=rd.Path, Size=UDim2.new(1,-20,0,S(14)), Position=UDim2.new(0,10,0,S(26)),
        TextColor3=C.text2, Font=Enum.Font.Code, TextSize=S(9)})
    lbl(f,{Name="Args",
        Text="Args: " .. (#rd.Args>0 and table.concat(rd.Args,"  ") or "—"),
        Size=UDim2.new(1,-20,0,S(14)), Position=UDim2.new(0,10,0,S(42)),
        TextColor3=C.code, Font=Enum.Font.Code, TextSize=S(9)})
end

task.delay(0.5, function()
    local rlist = {}
    for _, rd in pairs(Data.Remotes) do table.insert(rlist, rd) end
    lazyRender(rlist, renderNet, 5, 0.06)
end)
Data:Subscribe("OnRemoteSpied", function(rd) pcall(renderNet, rd) end)

-- ══════════════════════════════════════════════════════════════════════════
--  AUTO REMOTE
-- ══════════════════════════════════════════════════════════════════════════
local arHeaderCard = card(arPage, S(40), -1000)
lbl(arHeaderCard, {
    Text="🔗  AUTO REMOTE MANAGER  —  hooks every RemoteEvent & RemoteFunction",
    Size=UDim2.new(0.72,0,1,0), Position=UDim2.new(0,10,0,0),
    TextColor3=C.text1, Font=Enum.Font.GothamMedium, TextSize=S(10),
})
local arCount = lbl(arHeaderCard, {
    Text="0 remotes",
    Size=UDim2.new(0.24,0,1,0), Position=UDim2.new(0.74,0,0,0),
    TextColor3=C.green, Font=Enum.Font.GothamBold, TextSize=S(12),
    TextXAlignment=Enum.TextXAlignment.Right,
})

-- Fire dialog (modal overlay)
local fireDlg = Instance.new("Frame")
fireDlg.Size=UDim2.new(0, S(330), 0, S(168))
fireDlg.Position=UDim2.new(0.5, -S(165), 0.5, -S(84))
fireDlg.BackgroundColor3=C.bg1; fireDlg.BorderSizePixel=0
fireDlg.ZIndex=20; fireDlg.Visible=false; fireDlg.Parent=PageArea
corner(fireDlg, 12); strok(fireDlg, C.accent, 1.5)

lbl(fireDlg, {Text="▶  FIRE REMOTE", Size=UDim2.new(1,-16,0,S(24)), Position=UDim2.new(0,8,0,S(8)),
    TextColor3=C.accent, Font=Enum.Font.GothamBold, TextSize=S(12), ZIndex=21})
lbl(fireDlg, {Text="Arguments (comma-separated: \"str\", 42, true)",
    Size=UDim2.new(1,-16,0,S(18)), Position=UDim2.new(0,8,0,S(34)),
    TextColor3=C.text1, Font=Enum.Font.Gotham, TextSize=S(9), ZIndex=21})

local argBox = Instance.new("TextBox")
argBox.Size=UDim2.new(1,-16,0,S(32)); argBox.Position=UDim2.new(0,8,0,S(54))
argBox.BackgroundColor3=C.bg2; argBox.Text=""; argBox.PlaceholderText="e.g.: \"Action\", 1, true"
argBox.TextColor3=C.text0; argBox.PlaceholderColor3=C.text2
argBox.Font=Enum.Font.Code; argBox.TextSize=S(11); argBox.ClearTextOnFocus=false
argBox.ZIndex=21; argBox.Parent=fireDlg; corner(argBox,5); strok(argBox,C.stroke,1)

local fireDlgPath = nil
local fConfirm = miniBtn(fireDlg, "▶ Fire",   C.greenDk, C.green, S(80), S(8),  S(104))
local fCancel  = miniBtn(fireDlg, "Cancel",   C.bg2,     C.text1, S(72), S(96), S(104))
fConfirm.ZIndex=21; fCancel.ZIndex=21

local function closeFirDlg()
    tw(fireDlg, FAST, {GroupTransparency = 1})
    task.delay(0.15, function() fireDlg.Visible=false; fireDlg.GroupTransparency=0 end)
    fireDlgPath = nil
end
local function openFirDlg(path)
    fireDlgPath = path; argBox.Text=""
    fireDlg.GroupTransparency = 1
    fireDlg.Visible = true
    tw(fireDlg, MED, {GroupTransparency = 0})
end

fCancel.MouseButton1Click:Connect(closeFirDlg)
fConfirm.MouseButton1Click:Connect(function()
    if not fireDlgPath or not Data.FireRemote then closeFirDlg(); return end
    local args = {}
    local raw = argBox.Text
    if raw and #raw > 0 then
        local fn, _ = loadstring("return {" .. raw .. "}")
        if fn then local ok,p = pcall(fn); if ok and type(p)=="table" then args=p end end
    end
    Data.FireRemote(fireDlgPath, args)
    Data:ReportLog({Type="Info", Text="[AutoRemote] Fired: " .. fireDlgPath})
    closeFirDlg()
end)

local arFrames = {}
local function renderAR(rec)
    if arFrames[rec.Path] then
        local f = arFrames[rec.Path]
        if f and f.Parent then
            pcall(function()
                f:FindFirstChild("Calls").Text = "×" .. tostring(rec.Calls) .. "  " .. tostring(rec.CallRate) .. "/s"
                f:FindFirstChild("Args").Text  = "Last: " .. table.concat(rec.LastArgs or {}, "  ")
                f.BackgroundColor3 = rec.Blocked and C.redDk or C.card
            end)
            return
        end
        arFrames[rec.Path] = nil
    end
    local f = card(arPage, S(78))
    arFrames[rec.Path] = f
    local cc = rec.Class=="RemoteEvent" and C.blue or C.purple
    lbl(f, {Text=(rec.Class=="RemoteEvent" and "📡" or "🔁") .. "  " .. tostring(rec.Name),
        Size=UDim2.new(0.6,0,0,S(22)), Position=UDim2.new(0,10,0,S(4)),
        TextColor3=cc, Font=Enum.Font.GothamBold, TextSize=S(11)})
    lbl(f, {Name="Calls",
        Text="×" .. tostring(rec.Calls) .. "  " .. tostring(rec.CallRate) .. "/s",
        Size=UDim2.new(0.35,0,0,S(22)), Position=UDim2.new(0.63,0,0,S(4)),
        TextColor3=C.green, Font=Enum.Font.GothamBold, TextSize=S(11),
        TextXAlignment=Enum.TextXAlignment.Right})
    lbl(f, {Text=tostring(rec.Path),
        Size=UDim2.new(1,-20,0,S(14)), Position=UDim2.new(0,10,0,S(26)),
        TextColor3=C.text2, Font=Enum.Font.Code, TextSize=S(8)})
    lbl(f, {Name="Args",
        Text="Last: " .. table.concat(rec.LastArgs or {}, "  "),
        Size=UDim2.new(0.7,0,0,S(14)), Position=UDim2.new(0,10,0,S(42)),
        TextColor3=C.code, Font=Enum.Font.Code, TextSize=S(8)})

    local fb = miniBtn(f,"▶ Fire",  C.greenDk,C.green, S(54),S(8),  S(58))
    fb.MouseButton1Click:Connect(function() openFirDlg(rec.Path) end)
    local bb = miniBtn(f,"🚫 Block",C.redDk,  C.red,   S(62),S(68), S(58))
    bb.MouseButton1Click:Connect(function()
        if rec.Blocked then
            if Data.UnblockRemote then Data.UnblockRemote(rec.Path) end
            bb.Text="🚫 Block"; tw(f,FAST,{BackgroundColor3=C.card})
        else
            if Data.BlockRemote then Data.BlockRemote(rec.Path) end
            bb.Text="✅ Unblock"; tw(f,FAST,{BackgroundColor3=C.redDk})
        end
    end)
    local cb = miniBtn(f,"⎘ Copy",C.bg2,C.text1, S(56),S(136),S(58))
    cb.MouseButton1Click:Connect(function()
        if setclipboard then
            setclipboard(rec.Path); cb.Text="✓ Copied"
            task.delay(1.5, function() pcall(function() cb.Text="⎘ Copy" end) end)
        end
    end)
end

task.delay(0.6, function()
    if Data.AutoRemotes then
        local list = {}
        for _, r in pairs(Data.AutoRemotes) do table.insert(list, r) end
        lazyRender(list, renderAR, 4, 0.06)
    end
end)
Data:Subscribe("OnAutoRemoteAdded", function(r) pcall(renderAR, r) end)
Data:Subscribe("OnAutoRemoteFired", function(r) pcall(renderAR, r) end)

task.spawn(function()
    while Screen.Parent do
        task.wait(1)
        pcall(function()
            if Data.AutoRemotes then
                local n=0; for _ in pairs(Data.AutoRemotes) do n=n+1 end
                arCount.Text = n .. " remotes"
            end
        end)
    end
end)

-- ══════════════════════════════════════════════════════════════════════════
--  BUG CENTER
-- ══════════════════════════════════════════════════════════════════════════
local sevColor = {High=C.red,Medium=C.orange,Low=C.blue}
local sevBg    = {High=C.redDk,Medium=C.orangeDk,Low=C.blueDk}

local bugBar = card(bugPage, S(40), -1000)
local bAll  = miniBtn(bugBar,"All",   C.accentDk,C.text0,S(48),S(8),  S(8))
local bHi   = miniBtn(bugBar,"High",  C.redDk,   C.red,  S(48),S(62), S(8))
local bMid  = miniBtn(bugBar,"Medium",C.orangeDk,C.orange,S(58),S(116),S(8))
local bLow  = miniBtn(bugBar,"Low",   C.blueDk,  C.blue, S(48),S(180),S(8))
local bScan = miniBtn(bugBar,"▶ Scan",C.accentDk,C.text0,S(58),S(234),S(8))
local bClr  = miniBtn(bugBar,"⊘ Clear",C.bg2,    C.text1,S(58),S(298),S(8))
local bExp  = miniBtn(bugBar,"⤓ Export",C.tealDk,C.teal, S(66),S(362),S(8))

local bugFilterSev = nil
local function setBugF(sev, ab)
    bugFilterSev = sev
    for _, b in ipairs({bAll,bHi,bMid,bLow}) do
        tw(b, FAST, {BackgroundTransparency = b==ab and 0 or 0.55})
    end
end
bAll.MouseButton1Click:Connect(function() setBugF(nil, bAll) end)
bHi.MouseButton1Click:Connect(function()  setBugF("High", bHi) end)
bMid.MouseButton1Click:Connect(function() setBugF("Medium", bMid) end)
bLow.MouseButton1Click:Connect(function() setBugF("Low", bLow) end)
bScan.MouseButton1Click:Connect(function()
    bScan.Text="⟳ Scanning..."
    task.spawn(function()
        for _, fn in ipairs(getgenv().DebuggerScanners or {}) do
            pcall(fn); task.wait()
        end
        pcall(function() bScan.Text="▶ Scan" end)
    end)
end)
bClr.MouseButton1Click:Connect(function()
    for _, ch in ipairs(bugPage:GetChildren()) do
        if ch:IsA("Frame") and ch~=bugBar then ch:Destroy() end
    end
    Data:Clear()
end)
bExp.MouseButton1Click:Connect(function()
    if not writefile then return end
    local lines = {"-- Bug Report — " .. os.date("%Y-%m-%d %H:%M:%S"), ""}
    for _, b in ipairs(Data.Bugs) do
        table.insert(lines, string.format("[%s][%s] %s :: %s", b.Time or "?", b.Severity or "?", b.Type or "?", b.Source or "?"))
        table.insert(lines, "  " .. (b.Description or "")); table.insert(lines, "")
    end
    local fname = "BugReport_" .. os.date("%Y%m%d_%H%M%S") .. ".txt"
    pcall(writefile, fname, table.concat(lines, "\n"))
    Data:ReportLog({Type="Info", Text="[BugCenter] Exported " .. #Data.Bugs .. " bugs → " .. fname})
end)

local function renderBug(bug)
    if bugFilterSev and bug.Severity ~= bugFilterSev then return end
    local sev = bug.Severity or "Low"
    local f   = Instance.new("Frame")
    f.Size=UDim2.new(1,0,0,S(72)); f.BackgroundColor3=sevBg[sev] or C.card
    f.BorderSizePixel=0; f.AutomaticSize=Enum.AutomaticSize.Y; f.Parent=bugPage
    corner(f,7); strok(f, sevColor[sev] or C.stroke, 1)
    local bar=Instance.new("Frame")
    bar.Size=UDim2.new(0,4,1,0); bar.BackgroundColor3=sevColor[sev] or C.stroke
    bar.BorderSizePixel=0; bar.Parent=f; corner(bar,3)
    lbl(f,{Text=string.format("[%s]  %s", sev:upper(), bug.Type or "?"),
        Size=UDim2.new(0.75,0,0,S(22)), Position=UDim2.new(0,12,0,S(5)),
        TextColor3=sevColor[sev] or C.text0, Font=Enum.Font.GothamBold, TextSize=S(11)})
    lbl(f,{Text="⏱ " .. (bug.Time or "?"),
        Size=UDim2.new(0,80,0,S(22)), Position=UDim2.new(1,-86,0,S(5)),
        TextColor3=C.text2, Font=Enum.Font.Gotham, TextSize=S(9),
        TextXAlignment=Enum.TextXAlignment.Right})
    lbl(f,{Text="⚙ " .. (bug.Source or "?"),
        Size=UDim2.new(1,-20,0,S(15)), Position=UDim2.new(0,12,0,S(28)),
        TextColor3=C.text2, Font=Enum.Font.Code, TextSize=S(9)})
    lbl(f,{Text=bug.Description or "",
        Size=UDim2.new(1,-22,0,S(28)), Position=UDim2.new(0,12,0,S(44)),
        TextColor3=C.code, Font=Enum.Font.Gotham, TextSize=S(10),
        TextWrapped=true, TextYAlignment=Enum.TextYAlignment.Top})
end

task.delay(0.7, function()
    lazyRender(Data.Bugs, renderBug, 5, 0.05)
end)
Data:Subscribe("OnBugAdded", function(bug) pcall(renderBug, bug) end)

-- ══════════════════════════════════════════════════════════════════════════
--  CORE DEBUGGER
-- ══════════════════════════════════════════════════════════════════════════
local function makeStatRow(parent, label_, order)
    local row = card(parent, S(30), order)
    lbl(row, {Text=label_, Size=UDim2.new(0.58,0,1,0), Position=UDim2.new(0,10,0,0),
        TextColor3=C.text1, Font=Enum.Font.GothamMedium, TextSize=S(11)})
    return lbl(row, {Text="—", Size=UDim2.new(0.38,0,1,0), Position=UDim2.new(0.6,0,0,0),
        TextColor3=C.text0, Font=Enum.Font.GothamBold, TextSize=S(12),
        TextXAlignment=Enum.TextXAlignment.Right})
end

sectionTitle(cdPage, "RUNTIME STATISTICS", 1)
local cdStats = Instance.new("Frame")
cdStats.Size=UDim2.new(1,0,0,0); cdStats.BackgroundTransparency=1
cdStats.AutomaticSize=Enum.AutomaticSize.Y; cdStats.LayoutOrder=2; cdStats.Parent=cdPage
vlist(cdStats, 3)

local cdHooked  = makeStatRow(cdStats, "pcall() Hooks Intercepted")
local cdCaught  = makeStatRow(cdStats, "Total Errors Caught")
local cdErrRate = makeStatRow(cdStats, "Error Rate  (errors/sec)")
local cdMemory  = makeStatRow(cdStats, "Memory Usage  (MB)")
local cdGlobals = makeStatRow(cdStats, "Non-Standard Globals")
local cdCorLeak = makeStatRow(cdStats, "Coroutines Leaked")
local cdCorCr   = makeStatRow(cdStats, "Coroutines Created")
local cdReqLoad = makeStatRow(cdStats, "require() Loads")
local cdReqFail = makeStatRow(cdStats, "require() Failures")

sectionTitle(cdPage, "RECENT STACK TRACES", 3)
local clearCd = card(cdPage, S(34), 4); clearCd.BackgroundColor3=C.bg2
local ccBtn = miniBtn(clearCd,"⊘  Clear All Stack Traces",C.bg2,C.text1,S(200),S(8),S(5))

local traceFrame = Instance.new("Frame")
traceFrame.Size=UDim2.new(1,0,0,0); traceFrame.BackgroundTransparency=1
traceFrame.AutomaticSize=Enum.AutomaticSize.Y; traceFrame.LayoutOrder=5; traceFrame.Parent=cdPage
vlist(traceFrame, 4)

ccBtn.MouseButton1Click:Connect(function()
    for _, ch in ipairs(traceFrame:GetChildren()) do if ch:IsA("Frame") then ch:Destroy() end end
    if Data.CoreDebugger then Data.CoreDebugger.StackTraces = {} end
end)

local function renderTrace(entry)
    local f = Instance.new("Frame")
    f.Size=UDim2.new(1,0,0,0); f.AutomaticSize=Enum.AutomaticSize.Y
    f.BackgroundColor3=C.redDk; f.BorderSizePixel=0; f.Parent=traceFrame
    corner(f,7); strok(f,C.red,1)
    pad(f, S(6), S(6), S(10), S(8)); vlist(f, 2)
    lbl(f, {Text="🔴 [" .. (entry.Time or "?") .. "]  " .. (entry.Message or ""):sub(1,160),
        Size=UDim2.new(1,0,0,S(18)), TextColor3=C.red, Font=Enum.Font.GothamBold, TextSize=S(10),
        TextWrapped=true, AutomaticSize=Enum.AutomaticSize.Y})
    if entry.Trace then
        for _, line in ipairs(entry.Trace) do
            lbl(f, {Text=line, Size=UDim2.new(1,0,0,S(13)),
                TextColor3=C.code, Font=Enum.Font.Code, TextSize=S(9),
                TextWrapped=true, AutomaticSize=Enum.AutomaticSize.Y})
        end
    end
end

if Data.CoreDebugger and Data.CoreDebugger.StackTraces then
    task.delay(0.8, function()
        lazyRender(Data.CoreDebugger.StackTraces, renderTrace, 3, 0.06)
    end)
end
Data:Subscribe("OnStackTrace", function(e) pcall(renderTrace, e) end)

task.spawn(function()
    while Screen.Parent do
        task.wait(1)
        pcall(function()
            if not Data.CoreDebugger then return end
            local cd = Data.CoreDebugger
            cdHooked.Text  = tostring(cd.HookedPcalls)
            cdCaught.Text  = tostring(cd.CaughtErrors)
            cdErrRate.Text = tostring(cd.ErrorRate) .. "/s"
            cdMemory.Text  = tostring(cd.MemoryUsageMB) .. " MB"
            cdGlobals.Text = tostring(cd.GlobalVarCount)
            cdCorLeak.Text = tostring(cd.CoroutinesLeaked)
            cdCorCr.Text   = tostring(cd.CoroutinesCreated)
            cdReqLoad.Text = tostring(cd.RequireLoads)
            cdReqFail.Text = tostring(cd.RequireFailures)
            cdErrRate.TextColor3 = cd.ErrorRate > 2 and C.red or C.green
            cdMemory.TextColor3  = cd.MemoryUsageMB > 100 and C.orange or C.green
            cdReqFail.TextColor3 = cd.RequireFailures > 0 and C.red or C.green
        end)
    end
end)

-- ══════════════════════════════════════════════════════════════════════════
--  DOWNLOAD GAME
-- ══════════════════════════════════════════════════════════════════════════
local dlHero = card(dlPage, S(130), 1); dlHero.BackgroundColor3=C.tealDk; strok(dlHero,C.teal,1.5)
lbl(dlHero, {Text="📥  DOWNLOAD ENTIRE GAME",
    Size=UDim2.new(1,0,0,S(32)), Position=UDim2.new(0,0,0,S(10)),
    TextColor3=C.teal, Font=Enum.Font.GothamBold, TextSize=S(17),
    TextXAlignment=Enum.TextXAlignment.Center})
lbl(dlHero, {Text="Serializes all scripts & instances to Lua files in executor workspace.",
    Size=UDim2.new(0.88,0,0,S(28)), Position=UDim2.new(0.06,0,0,S(44)),
    TextColor3=C.text1, Font=Enum.Font.Gotham, TextSize=S(11),
    TextWrapped=true, TextXAlignment=Enum.TextXAlignment.Center})

local dlFullBtn = Instance.new("TextButton")
dlFullBtn.Size=UDim2.new(0.56,0,0,S(34)); dlFullBtn.Position=UDim2.new(0.22,0,0,S(84))
dlFullBtn.BackgroundColor3=C.teal; dlFullBtn.Text="⬇  Download Full Game"
dlFullBtn.TextColor3=Color3.fromRGB(8,15,14); dlFullBtn.Font=Enum.Font.GothamBold
dlFullBtn.TextSize=S(13); dlFullBtn.AutoButtonColor=false; dlFullBtn.Parent=dlHero; corner(dlFullBtn,8)
dlFullBtn.MouseButton1Down:Connect(function() tw(dlFullBtn, TweenInfo.new(0.08), {BackgroundTransparency=0.25}) end)
dlFullBtn.MouseButton1Up:Connect(function() tw(dlFullBtn, BOUNCE, {BackgroundTransparency=0}) end)

local progCard = card(dlPage, S(100), 2)
lbl(progCard, {Text="DOWNLOAD PROGRESS", Size=UDim2.new(1,-16,0,S(18)), Position=UDim2.new(0,10,0,S(6)),
    TextColor3=C.text2, Font=Enum.Font.GothamBold, TextSize=S(8)})
local progBg = Instance.new("Frame")
progBg.Size=UDim2.new(1,-20,0,S(14)); progBg.Position=UDim2.new(0,10,0,S(28))
progBg.BackgroundColor3=Color3.fromRGB(18,24,40); progBg.BorderSizePixel=0; progBg.Parent=progCard; corner(progBg,7)
local progFill = Instance.new("Frame")
progFill.Size=UDim2.new(0,0,1,0); progFill.BackgroundColor3=C.teal
progFill.BorderSizePixel=0; progFill.Parent=progBg; corner(progFill,7)
local progPct = lbl(progCard, {Text="0%", Size=UDim2.new(0.5,-20,0,S(18)), Position=UDim2.new(0,10,0,S(46)),
    TextColor3=C.teal, Font=Enum.Font.GothamBold, TextSize=S(12)})
local progStat = lbl(progCard, {Text="Ready", Size=UDim2.new(0.6,-20,0,S(16)), Position=UDim2.new(0,10,0,S(64)),
    TextColor3=C.text1, Font=Enum.Font.Gotham, TextSize=S(10)})
local progFiles = lbl(progCard, {Text="0 files · 0 KB", Size=UDim2.new(0.36,0,0,S(16)), Position=UDim2.new(0.62,0,0,S(64)),
    TextColor3=C.text2, Font=Enum.Font.Gotham, TextSize=S(10), TextXAlignment=Enum.TextXAlignment.Right})

local soCard = card(dlPage, S(50), 3)
lbl(soCard, {Text="Scripts only — faster, extracts only LuaSourceContainer instances.",
    Size=UDim2.new(0.58,0,1,0), Position=UDim2.new(0,12,0,0),
    TextColor3=C.text1, Font=Enum.Font.Gotham, TextSize=S(10), TextWrapped=true})
local soBtn = miniBtn(soCard,"⬇  Scripts Only",C.accentDk,C.text0,S(130))
soBtn.Size=UDim2.new(0,S(130),0,S(28)); soBtn.Position=UDim2.new(1,-S(142),0,S(11))

task.spawn(function()
    task.wait(0.8)
    if Data.HasFileIO and not Data.HasFileIO() then
        local wc = card(dlPage, S(50), 0); wc.BackgroundColor3=C.orangeDk; strok(wc,C.orange,1)
        lbl(wc, {Text="⚠  No file I/O — writefile()/makefolder() unavailable. Use Synapse X, Krnl, Wave, or Codex.",
            Size=UDim2.new(1,-20,1,-8), Position=UDim2.new(0,10,0,4),
            TextColor3=C.orange, Font=Enum.Font.GothamMedium, TextSize=S(11),
            TextWrapped=true, TextYAlignment=Enum.TextYAlignment.Top})
    end
end)

sectionTitle(dlPage, "DOWNLOAD LOG", 4)
local dlLogFrame = Instance.new("Frame")
dlLogFrame.Size=UDim2.new(1,0,0,0); dlLogFrame.AutomaticSize=Enum.AutomaticSize.Y
dlLogFrame.BackgroundTransparency=1; dlLogFrame.LayoutOrder=5; dlLogFrame.Parent=dlPage
vlist(dlLogFrame, 2)

local function addDlLog(msg)
    local row=Instance.new("Frame"); row.Size=UDim2.new(1,0,0,0)
    row.AutomaticSize=Enum.AutomaticSize.Y; row.BackgroundTransparency=1; row.Parent=dlLogFrame
    lbl(row, {Text=msg, Size=UDim2.new(1,0,0,S(16)), TextColor3=C.code, Font=Enum.Font.Code,
        TextSize=S(9), TextWrapped=true, AutomaticSize=Enum.AutomaticSize.Y})
end

Data:Subscribe("OnDownloaderProgress", function(dl)
    pcall(function()
        local pct = math.clamp(dl.Progress or 0, 0, 100)
        tw(progFill, MED, {Size=UDim2.new(pct/100,0,1,0)})
        progPct.Text   = pct .. "%"
        progStat.Text  = dl.StatusMsg or "..."
        progFiles.Text = tostring(dl.FileCount or 0) .. " files · " .. tostring(math.floor((dl.TotalBytes or 0)/1024)) .. " KB"
        progFill.BackgroundColor3 = dl.Running and C.teal or (pct>=100 and C.green or C.orange)
    end)
end)
Data:Subscribe("OnDownloaderLog",      function(msg) addDlLog(msg) end)
Data:Subscribe("OnDownloaderComplete", function()
    pcall(function()
        dlFullBtn.Text="⬇  Download Full Game"; dlFullBtn.Active=true
        soBtn.Text="⬇  Scripts Only"; soBtn.Active=true
    end)
end)

dlFullBtn.MouseButton1Click:Connect(function()
    if Data.Downloader and Data.Downloader.Running then return end
    dlFullBtn.Text="⟳  Downloading..."; dlFullBtn.Active=false
    task.spawn(function()
        if Data.DownloadGame then Data.DownloadGame()
        else addDlLog("Downloader not loaded."); dlFullBtn.Text="⬇  Download Full Game"; dlFullBtn.Active=true end
    end)
end)
soBtn.MouseButton1Click:Connect(function()
    if Data.Downloader and Data.Downloader.Running then return end
    soBtn.Text="⟳  Downloading..."; soBtn.Active=false
    task.spawn(function()
        if Data.DownloadScriptsOnly then Data.DownloadScriptsOnly()
        else addDlLog("Downloader not loaded.") end
        pcall(function() soBtn.Text="⬇  Scripts Only"; soBtn.Active=true end)
    end)
end)

if Data.Downloader and Data.Downloader.Log then
    task.delay(0.4, function()
        lazyRender(Data.Downloader.Log, addDlLog, 10, 0.03)
    end)
end

-- ══════════════════════════════════════════════════════════════════════════
--  GITHUB SYNC
-- ══════════════════════════════════════════════════════════════════════════
local GH = Data.GitHub

local ghStatCard = card(ghPage, S(52), 1); ghStatCard.BackgroundColor3=C.bg2; strok(ghStatCard,C.accent,1)
lbl(ghStatCard, {Text="⬡  GITHUB SYNC", Size=UDim2.new(1,-16,0,S(20)), Position=UDim2.new(0,10,0,S(4)),
    TextColor3=C.accentLt, Font=Enum.Font.GothamBold, TextSize=S(12)})
local ghStatLbl = lbl(ghStatCard, {
    Text="Status: " .. (GH.SyncStatus or "Idle") .. "  ·  Last: " .. (GH.LastSync or "Never"),
    Size=UDim2.new(1,-16,0,S(20)), Position=UDim2.new(0,10,0,S(26)),
    TextColor3=C.text1, Font=Enum.Font.Gotham, TextSize=S(10)})

local ghCfg = card(ghPage, S(120), 2)
lbl(ghCfg, {Text="GitHub Repo  (owner/repo)", Size=UDim2.new(1,-16,0,S(18)), Position=UDim2.new(0,10,0,S(6)),
    TextColor3=C.text2, Font=Enum.Font.GothamBold, TextSize=S(8)})

local repoBox = Instance.new("TextBox")
repoBox.Size=UDim2.new(1,-20,0,S(30)); repoBox.Position=UDim2.new(0,10,0,S(26))
repoBox.BackgroundColor3=C.bg0; repoBox.TextColor3=C.text0
repoBox.PlaceholderText="e.g. YourName/roblox-debugger"; repoBox.PlaceholderColor3=C.text2
repoBox.Text=GH.Repo or ""; repoBox.Font=Enum.Font.Code; repoBox.TextSize=S(12)
repoBox.ClearTextOnFocus=false; repoBox.Parent=ghCfg; corner(repoBox,6); strok(repoBox,C.stroke,1)
repoBox.FocusLost:Connect(function() GH.Repo=repoBox.Text end)

lbl(ghCfg, {Text="Branch", Size=UDim2.new(0.2,-8,0,S(18)), Position=UDim2.new(0,10,0,S(64)),
    TextColor3=C.text2, Font=Enum.Font.GothamBold, TextSize=S(8)})
local branchBox = Instance.new("TextBox")
branchBox.Size=UDim2.new(0.22,-8,0,S(28)); branchBox.Position=UDim2.new(0,10,0,S(84))
branchBox.BackgroundColor3=C.bg0; branchBox.TextColor3=C.text0
branchBox.Text=GH.Branch or "main"; branchBox.Font=Enum.Font.Code; branchBox.TextSize=S(11)
branchBox.ClearTextOnFocus=false; branchBox.Parent=ghCfg; corner(branchBox,6); strok(branchBox,C.stroke,1)
branchBox.FocusLost:Connect(function() GH.Branch=branchBox.Text end)

local autoSyncBtn = Instance.new("TextButton")
autoSyncBtn.Size=UDim2.new(0,S(158),0,S(28)); autoSyncBtn.Position=UDim2.new(0.24,0,0,S(84))
autoSyncBtn.BackgroundColor3=GH.AutoSync and C.greenDk or C.bg2
autoSyncBtn.Text="⟳ Auto-sync on Boot: " .. (GH.AutoSync and "ON" or "OFF")
autoSyncBtn.TextColor3=GH.AutoSync and C.green or C.text1
autoSyncBtn.Font=Enum.Font.GothamBold; autoSyncBtn.TextSize=S(10); autoSyncBtn.AutoButtonColor=false
autoSyncBtn.Parent=ghCfg; corner(autoSyncBtn,6); strok(autoSyncBtn,GH.AutoSync and C.green or C.stroke,1)
autoSyncBtn.MouseButton1Click:Connect(function()
    GH.AutoSync=not GH.AutoSync
    autoSyncBtn.Text="⟳ Auto-sync: " .. (GH.AutoSync and "ON" or "OFF")
    tw(autoSyncBtn, MED, {BackgroundColor3=GH.AutoSync and C.greenDk or C.bg2,
        TextColor3=GH.AutoSync and C.green or C.text1})
end)

local ghAct = card(ghPage, S(50), 3)
local ghPull = Instance.new("TextButton")
ghPull.Size=UDim2.new(0.42,0,0,S(34)); ghPull.Position=UDim2.new(0,10,0,S(8))
ghPull.BackgroundColor3=C.accentDk; ghPull.Text="⬇  Pull Latest from GitHub"
ghPull.TextColor3=C.text0; ghPull.Font=Enum.Font.GothamBold; ghPull.TextSize=S(11)
ghPull.AutoButtonColor=false; ghPull.Parent=ghAct; corner(ghPull,7); strok(ghPull,C.accent,1)

local ghVer = Instance.new("TextButton")
ghVer.Size=UDim2.new(0.28,0,0,S(34)); ghVer.Position=UDim2.new(0.44,0,0,S(8))
ghVer.BackgroundColor3=C.bg2; ghVer.Text="🔍  Check Version"
ghVer.TextColor3=C.text1; ghVer.Font=Enum.Font.GothamBold; ghVer.TextSize=S(11)
ghVer.AutoButtonColor=false; ghVer.Parent=ghAct; corner(ghVer,7)

local ghFetchCard = card(ghPage, S(80), 4)
lbl(ghFetchCard, {Text="Load Script from Raw URL",
    Size=UDim2.new(1,-16,0,S(18)), Position=UDim2.new(0,10,0,S(5)),
    TextColor3=C.text2, Font=Enum.Font.GothamBold, TextSize=S(8)})
local urlBox = Instance.new("TextBox")
urlBox.Size=UDim2.new(1,-20,0,S(28)); urlBox.Position=UDim2.new(0,10,0,S(25))
urlBox.BackgroundColor3=C.bg0; urlBox.TextColor3=C.text0
urlBox.PlaceholderText="https://raw.githubusercontent.com/owner/repo/main/file.lua"
urlBox.PlaceholderColor3=C.text2; urlBox.Text=""
urlBox.Font=Enum.Font.Code; urlBox.TextSize=S(9); urlBox.ClearTextOnFocus=false
urlBox.Parent=ghFetchCard; corner(urlBox,6); strok(urlBox,C.stroke,1)
local ghFetchBtn = miniBtn(ghFetchCard,"▶ Load URL",C.accentDk,C.text0,S(90),S(10),S(56))
ghFetchBtn.MouseButton1Click:Connect(function()
    local url=urlBox.Text; if not url or #url<10 then return end
    ghFetchBtn.Text="⟳ Loading..."
    task.spawn(function()
        if Data.GitHub.FetchScript then Data.GitHub.FetchScript(url, url:match("[^/]+$") or "script.lua") end
        pcall(function() ghFetchBtn.Text="▶ Load URL" end)
    end)
end)

sectionTitle(ghPage, "SYNC LOG", 5)
local ghLogFrame = Instance.new("Frame")
ghLogFrame.Size=UDim2.new(1,0,0,0); ghLogFrame.AutomaticSize=Enum.AutomaticSize.Y
ghLogFrame.BackgroundTransparency=1; ghLogFrame.LayoutOrder=6; ghLogFrame.Parent=ghPage
vlist(ghLogFrame, 2)
local function addGhLog(msg)
    local row=Instance.new("Frame"); row.Size=UDim2.new(1,0,0,0)
    row.AutomaticSize=Enum.AutomaticSize.Y; row.BackgroundTransparency=1; row.Parent=ghLogFrame
    lbl(row, {Text=msg, Size=UDim2.new(1,0,0,S(16)), TextColor3=C.code, Font=Enum.Font.Code,
        TextSize=S(9), TextWrapped=true, AutomaticSize=Enum.AutomaticSize.Y})
end

ghPull.MouseButton1Click:Connect(function()
    if GH.Repo=="" then addGhLog("⚠ Set a repo first"); return end
    ghPull.Text="⟳  Pulling..."; ghPull.Active=false
    task.spawn(function()
        if Data.GitHub.PullLatest then Data.GitHub.PullLatest() end
        pcall(function() ghPull.Text="⬇  Pull Latest from GitHub"; ghPull.Active=true end)
    end)
end)
ghVer.MouseButton1Click:Connect(function()
    task.spawn(function()
        if Data.GitHub.CheckVersion then
            local ver, err = Data.GitHub.CheckVersion()
            addGhLog(ver and ("Remote v" .. ver .. " — local v" .. Data.Version)
                         or ("Version check failed: " .. tostring(err)))
        end
    end)
end)

Data:Subscribe("OnGitHubStatus", function(gh)
    pcall(function()
        ghStatLbl.Text="Status: " .. (gh.SyncStatus or "?") .. "  ·  Last: " .. (gh.LastSync or "Never")
        addGhLog("[" .. os.date("%H:%M:%S") .. "] " .. (gh.SyncStatus or "?"))
    end)
end)

-- ══════════════════════════════════════════════════════════════════════════
--  AI INSIGHTS
-- ══════════════════════════════════════════════════════════════════════════
local aiClrCard = card(aiPage, S(34), -999); aiClrCard.BackgroundColor3=C.bg2
local acb = miniBtn(aiClrCard,"⊘  Clear AI Insights",C.bg2,C.text1,S(160),S(8),S(5))
acb.MouseButton1Click:Connect(function()
    for _, ch in ipairs(aiPage:GetChildren()) do if ch:IsA("Frame") and ch~=aiClrCard then ch:Destroy() end end
    table.clear(Data.AIInsights)
end)

local function renderInsight(ins)
    local f = card(aiPage, 0); f.AutomaticSize=Enum.AutomaticSize.Y
    f.BackgroundColor3=C.purpleDk; strok(f,C.purple,1)
    lbl(f,{Text="🤖  " .. (ins.Title or "?"), Size=UDim2.new(0.72,0,0,S(22)), Position=UDim2.new(0,10,0,S(6)),
        TextColor3=C.purple, Font=Enum.Font.GothamBold, TextSize=S(11)})
    lbl(f,{Text="Confidence: " .. (ins.Confidence or "?"), Size=UDim2.new(0.24,0,0,S(22)), Position=UDim2.new(0.74,0,0,S(6)),
        TextColor3=C.green, Font=Enum.Font.GothamBold, TextSize=S(9), TextXAlignment=Enum.TextXAlignment.Right})
    lbl(f,{Text="⚠ " .. (ins.Problem or ""), Size=UDim2.new(1,-24,0,0), Position=UDim2.new(0,10,0,S(30)),
        TextColor3=C.code, Font=Enum.Font.Gotham, TextSize=S(10), TextWrapped=true, AutomaticSize=Enum.AutomaticSize.Y})
    lbl(f,{Text="✔ " .. (ins.Suggestion or ""), Size=UDim2.new(1,-24,0,0), Position=UDim2.new(0,10,0,S(60)),
        TextColor3=C.green, Font=Enum.Font.GothamMedium, TextSize=S(10), TextWrapped=true, AutomaticSize=Enum.AutomaticSize.Y})
end

task.delay(0.9, function()
  for _, ins in ipairs(Data.AIInsights) do renderInsight(ins) end
end)
Data:Subscribe("OnAIInsightAdded", function(ins) pcall(renderInsight, ins) end)

-- ══════════════════════════════════════════════════════════════════════════
--  SCRIPT HOOK TAB
-- ══════════════════════════════════════════════════════════════════════════
if Data.ScriptHook then
    local SH = Data.ScriptHook

    -- Stats header
    local shStatCard = card(shPage, S(54), 1); shStatCard.BackgroundColor3 = C.bg2
    strok(shStatCard, C.red, 1)
    lbl(shStatCard, {
        Text="🔐  SCRIPT HOOK & VIRUS SCANNER",
        Size=UDim2.new(0.7,0,0,S(22)), Position=UDim2.new(0,10,0,S(4)),
        TextColor3=C.red, Font=Enum.Font.GothamBold, TextSize=S(12),
    })
    local shLsLbl = lbl(shStatCard, {
        Text="loadstring: 0  |  Suspicious: 0  |  Blocked: 0",
        Size=UDim2.new(1,-16,0,S(20)), Position=UDim2.new(0,10,0,S(28)),
        TextColor3=C.text1, Font=Enum.Font.Gotham, TextSize=S(10),
    })

    -- Controls
    local shCtrl = card(shPage, S(40), 2)
    local shToggle = miniBtn(shCtrl, SH.Enabled and "🟢 Scanner: ON" or "🔴 Scanner: OFF",
        SH.Enabled and C.greenDk or C.redDk,
        SH.Enabled and C.green or C.red, S(130), S(8), S(8))
    local shBlock = miniBtn(shCtrl, SH.BlockMode and "🚫 Block Mode: ON" or "🛡 Block Mode: OFF",
        SH.BlockMode and C.redDk or C.bg2,
        SH.BlockMode and C.red or C.text1, S(150), S(146), S(8))

    shToggle.MouseButton1Click:Connect(function()
        SH.Enabled = not SH.Enabled
        shToggle.Text = SH.Enabled and "🟢 Scanner: ON" or "🔴 Scanner: OFF"
        tw(shToggle, FAST, {BackgroundColor3=SH.Enabled and C.greenDk or C.redDk,
            TextColor3=SH.Enabled and C.green or C.red})
    end)
    shBlock.MouseButton1Click:Connect(function()
        SH.BlockMode = not SH.BlockMode
        shBlock.Text = SH.BlockMode and "🚫 Block Mode: ON" or "🛡 Block Mode: OFF"
        tw(shBlock, FAST, {BackgroundColor3=SH.BlockMode and C.redDk or C.bg2,
            TextColor3=SH.BlockMode and C.red or C.text1})
    end)

    -- Suspicious scripts list
    sectionTitle(shPage, "DETECTED SUSPICIOUS SCRIPTS", 3)
    local shListFrame = Instance.new("Frame")
    shListFrame.Size=UDim2.new(1,0,0,0); shListFrame.AutomaticSize=Enum.AutomaticSize.Y
    shListFrame.BackgroundTransparency=1; shListFrame.LayoutOrder=4; shListFrame.Parent=shPage
    vlist(shListFrame, 4)

    local function renderShEntry(e)
        local f = Instance.new("Frame")
        f.Size=UDim2.new(1,0,0,0); f.AutomaticSize=Enum.AutomaticSize.Y
        f.BackgroundColor3=C.redDk; f.BorderSizePixel=0; f.Parent=shListFrame
        corner(f,7); strok(f,C.red,1)
        pad(f,S(6),S(6),S(10),S(8)); vlist(f,2)
        lbl(f, {Text="🔐 [" .. (e.time or "?") .. "]  " .. (e.context or "?"),
            Size=UDim2.new(1,0,0,S(18)), TextColor3=C.red, Font=Enum.Font.GothamBold, TextSize=S(10),
            TextWrapped=true, AutomaticSize=Enum.AutomaticSize.Y})
        lbl(f, {Text="Preview: " .. (e.preview or ""),
            Size=UDim2.new(1,0,0,S(14)), TextColor3=C.code, Font=Enum.Font.Code, TextSize=S(9),
            TextWrapped=true, AutomaticSize=Enum.AutomaticSize.Y})
        for _, r in ipairs(e.reasons or {}) do
            lbl(f, {Text="  ⚠ " .. r,
                Size=UDim2.new(1,0,0,S(13)), TextColor3=C.orange, Font=Enum.Font.Gotham, TextSize=S(9),
                TextWrapped=true, AutomaticSize=Enum.AutomaticSize.Y})
        end
    end

    task.delay(1, function()
        lazyRender(SH.DetectedSources, renderShEntry, 3, 0.08)
    end)
    Data:Subscribe("OnSuspiciousScript", function(e) pcall(renderShEntry, e) end)

    -- Poll stats
    task.spawn(function()
        while Screen.Parent do
            task.wait(1)
            pcall(function()
                shLsLbl.Text = string.format("loadstring: %d  |  Suspicious: %d  |  Blocked: %d",
                    SH.LoadstringCalls, SH.SuspiciousScripts, SH.LoadstringBlocked)
            end)
        end
    end)
end

-- ══════════════════════════════════════════════════════════════════════════
--  CRASH LOG TAB
-- ══════════════════════════════════════════════════════════════════════════
if Data.CrashHandler then
    local CH = Data.CrashHandler

    local crashHdr = card(crashPage, S(52), 1); crashHdr.BackgroundColor3=C.bg2
    strok(crashHdr, C.red, 1)
    lbl(crashHdr, {Text="💥  CRASH LOG",
        Size=UDim2.new(0.6,0,0,S(22)), Position=UDim2.new(0,10,0,S(4)),
        TextColor3=C.red, Font=Enum.Font.GothamBold, TextSize=S(12)})
    local crashStatLbl = lbl(crashHdr, {
        Text="Crashes: 0  |  Watchdog: 0  |  Last: Never",
        Size=UDim2.new(1,-16,0,S(20)), Position=UDim2.new(0,10,0,S(28)),
        TextColor3=C.text1, Font=Enum.Font.Gotham, TextSize=S(10)})

    local crashCtrl = card(crashPage, S(40), 2)
    local crashClr = miniBtn(crashCtrl, "⊘ Clear Crash Log", C.bg2, C.text1, S(140), S(8), S(8))
    crashClr.MouseButton1Click:Connect(function()
        for _, ch in ipairs(crashPage:GetChildren()) do
            if ch:IsA("Frame") and ch~=crashHdr and ch~=crashCtrl then ch:Destroy() end
        end
        if Data.ClearCrashLog then Data.ClearCrashLog() end
    end)

    sectionTitle(crashPage, "RECENT CRASHES", 3)
    local crashListFrame = Instance.new("Frame")
    crashListFrame.Size=UDim2.new(1,0,0,0); crashListFrame.AutomaticSize=Enum.AutomaticSize.Y
    crashListFrame.BackgroundTransparency=1; crashListFrame.LayoutOrder=4; crashListFrame.Parent=crashPage
    vlist(crashListFrame, 4)

    local function renderCrash(entry)
        local f = Instance.new("Frame")
        f.Size=UDim2.new(1,0,0,0); f.AutomaticSize=Enum.AutomaticSize.Y
        f.BackgroundColor3=C.redDk; f.BorderSizePixel=0; f.Parent=crashListFrame
        corner(f,7); strok(f,C.red,1)
        pad(f,S(6),S(6),S(10),S(8)); vlist(f,2)
        lbl(f, {Text="💥 [" .. (entry.Time or "?") .. "]  " .. (entry.Message or ""):sub(1,160),
            Size=UDim2.new(1,0,0,S(18)), TextColor3=C.red, Font=Enum.Font.GothamBold, TextSize=S(10),
            TextWrapped=true, AutomaticSize=Enum.AutomaticSize.Y})
        lbl(f, {Text="Script: " .. (entry.Script or "?") .. "  Line: " .. (entry.Line or "?"),
            Size=UDim2.new(1,0,0,S(14)), TextColor3=C.code, Font=Enum.Font.Code, TextSize=S(9)})
        for _, tl in ipairs(entry.Trace or {}) do
            lbl(f, {Text=tl, Size=UDim2.new(1,0,0,S(13)),
                TextColor3=C.text2, Font=Enum.Font.Code, TextSize=S(8),
                TextWrapped=true, AutomaticSize=Enum.AutomaticSize.Y})
        end
    end

    task.delay(1, function()
        lazyRender(CH.CrashLog, renderCrash, 3, 0.08)
    end)
    Data:Subscribe("OnCrashDetected", function(e) pcall(renderCrash, e) end)

    task.spawn(function()
        while Screen.Parent do
            task.wait(1)
            pcall(function()
                crashStatLbl.Text = string.format(
                    "Crashes: %d  |  Watchdog fired: %d  |  Last: %s",
                    CH.TotalCrashes, CH.WatchdogFired, CH.LastCrashTime)
            end)
        end
    end)
end

-- ══════════════════════════════════════════════════════════════════════════
--  VALUE WATCHER TAB
-- ══════════════════════════════════════════════════════════════════════════
if Data.ValueWatcher then
    local VW = Data.ValueWatcher

    -- Add watcher panel
    local vwAddCard = card(vwPage, S(110), 1)
    lbl(vwAddCard, {Text="ADD WATCHER",
        Size=UDim2.new(1,-16,0,S(18)), Position=UDim2.new(0,10,0,S(6)),
        TextColor3=C.text2, Font=Enum.Font.GothamBold, TextSize=S(8)})

    -- Path input
    lbl(vwAddCard, {Text="Instance path (e.g. Workspace.Part)",
        Size=UDim2.new(0.6,-8,0,S(16)), Position=UDim2.new(0,10,0,S(26)),
        TextColor3=C.text2, Font=Enum.Font.Gotham, TextSize=S(8)})
    lbl(vwAddCard, {Text="Property name",
        Size=UDim2.new(0.38,0,0,S(16)), Position=UDim2.new(0.62,0,0,S(26)),
        TextColor3=C.text2, Font=Enum.Font.Gotham, TextSize=S(8)})

    local pathInput = Instance.new("TextBox")
    pathInput.Size=UDim2.new(0.6,-12,0,S(28)); pathInput.Position=UDim2.new(0,10,0,S(44))
    pathInput.BackgroundColor3=C.bg0; pathInput.TextColor3=C.text0
    pathInput.PlaceholderText="Workspace.Model.Part"; pathInput.PlaceholderColor3=C.text2
    pathInput.Text=""; pathInput.Font=Enum.Font.Code; pathInput.TextSize=S(10)
    pathInput.ClearTextOnFocus=false; pathInput.Parent=vwAddCard
    corner(pathInput,5); strok(pathInput,C.stroke,1)

    local propInput = Instance.new("TextBox")
    propInput.Size=UDim2.new(0.38,-4,0,S(28)); propInput.Position=UDim2.new(0.62,0,0,S(44))
    propInput.BackgroundColor3=C.bg0; propInput.TextColor3=C.text0
    propInput.PlaceholderText="Position"; propInput.PlaceholderColor3=C.text2
    propInput.Text=""; propInput.Font=Enum.Font.Code; propInput.TextSize=S(10)
    propInput.ClearTextOnFocus=false; propInput.Parent=vwAddCard
    corner(propInput,5); strok(propInput,C.stroke,1)

    local addWBtn = miniBtn(vwAddCard,"+ Add Watcher",C.accentDk,C.text0,S(110),S(10),S(78))
    addWBtn.MouseButton1Click:Connect(function()
        local path = pathInput.Text
        local prop = propInput.Text
        if path == "" or prop == "" then return end
        local id = Data.ValueWatcher.Watch(path, prop)
        if id then
            pathInput.Text = ""; propInput.Text = ""
            Data:ReportLog({Type="Info", Text="[ValueWatcher] Added watcher: " .. path .. "." .. prop})
        end
    end)

    -- Watchers list
    sectionTitle(vwPage, "ACTIVE WATCHERS", 2)
    local vwListFrame = Instance.new("Frame")
    vwListFrame.Size=UDim2.new(1,0,0,0); vwListFrame.AutomaticSize=Enum.AutomaticSize.Y
    vwListFrame.BackgroundTransparency=1; vwListFrame.LayoutOrder=3; vwListFrame.Parent=vwPage
    vlist(vwListFrame, 4)

    local vwRows = {}  -- id → frame

    local function renderWatcher(w)
        if vwRows[w.id] then
            local f = vwRows[w.id]
            if f and f.Parent then
                pcall(function()
                    local vl = f:FindFirstChild("ValLbl")
                    if vl then
                        local ok, cv = pcall(function() return w.instance[w.prop] end)
                        vl.Text = "Current: " .. (ok and tostring(cv) or "?")
                    end
                end)
                return
            end
        end

        local f = card(vwListFrame, S(60))
        vwRows[w.id] = f

        lbl(f, {Text="👁  " .. w.label,
            Size=UDim2.new(0.7,0,0,S(22)), Position=UDim2.new(0,10,0,S(4)),
            TextColor3=C.accentLt, Font=Enum.Font.GothamBold, TextSize=S(11)})
        lbl(f, {Text="id="..tostring(w.id),
            Size=UDim2.new(0.25,0,0,S(22)), Position=UDim2.new(0.73,0,0,S(4)),
            TextColor3=C.text2, Font=Enum.Font.Gotham, TextSize=S(9),
            TextXAlignment=Enum.TextXAlignment.Right})
        lbl(f, {Name="ValLbl",
            Text="Current: —",
            Size=UDim2.new(0.7,0,0,S(16)), Position=UDim2.new(0,10,0,S(28)),
            TextColor3=C.green, Font=Enum.Font.GothamMedium, TextSize=S(10)})
        lbl(f, {Text=w.path,
            Size=UDim2.new(1,-20,0,S(14)), Position=UDim2.new(0,10,0,S(44)),
            TextColor3=C.text2, Font=Enum.Font.Code, TextSize=S(8)})

        local rmBtn = miniBtn(f,"✕ Remove",C.redDk,C.red,S(72),nil,S(34))
        rmBtn.Position = UDim2.new(1,-S(80),0,S(34))
        rmBtn.MouseButton1Click:Connect(function()
            Data.ValueWatcher.Unwatch(w.id)
            vwRows[w.id] = nil
            f:Destroy()
        end)
    end

    task.delay(1, function()
        lazyRender(VW.Watchers, renderWatcher, 5, 0.06)
    end)
    Data:Subscribe("OnWatcherAdded", function(w) pcall(renderWatcher, w) end)
    Data:Subscribe("OnWatcherRemoved", function(w)
        if vwRows[w.id] then pcall(function() vwRows[w.id]:Destroy() end); vwRows[w.id]=nil end
    end)

    -- Change log
    sectionTitle(vwPage, "CHANGE LOG", 4)
    local vwLogFrame = Instance.new("Frame")
    vwLogFrame.Size=UDim2.new(1,0,0,0); vwLogFrame.AutomaticSize=Enum.AutomaticSize.Y
    vwLogFrame.BackgroundTransparency=1; vwLogFrame.LayoutOrder=5; vwLogFrame.Parent=vwPage
    vlist(vwLogFrame, 2)

    local function addVwLog(entry)
        local row = Instance.new("Frame")
        row.Size=UDim2.new(1,0,0,S(24)); row.BackgroundColor3=C.card
        row.BorderSizePixel=0; row.Parent=vwLogFrame; corner(row,4)
        lbl(row, {
            Text=string.format("[%s] %s.%s: %s → %s",
                entry.Time, entry.Path, entry.Property, entry.Old, entry.New),
            Size=UDim2.new(1,-8,1,0), Position=UDim2.new(0,6,0,0),
            TextColor3=C.code, Font=Enum.Font.Code, TextSize=S(9),
            TextWrapped=true,
        })
    end

    task.delay(1, function()
        lazyRender(VW.ChangeLog, addVwLog, 10, 0.03)
    end)
    Data:Subscribe("OnValueChanged", function(e) pcall(addVwLog, e) end)

    -- Live value refresh
    task.spawn(function()
        while Screen.Parent do
            task.wait(2)
            for _, w in ipairs(VW.Watchers) do
                pcall(function()
                    if vwRows[w.id] then
                        local vl = vwRows[w.id]:FindFirstChild("ValLbl")
                        if vl then
                            local ok, cv = pcall(function() return w.instance[w.prop] end)
                            vl.Text = "Current: " .. (ok and tostring(cv) or "?")
                        end
                    end
                end)
                task.wait()
            end
        end
    end)
end

-- ══════════════════════════════════════════════════════════════════════════
print(string.format("[GUI v8]: Ready. Mobile=%s Scale=%.2f Tabs=12", tostring(isMobile), SCALE))

