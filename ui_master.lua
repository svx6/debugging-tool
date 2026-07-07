--[[
    ========================================================================
    UI MASTER MODULE - Orchestrator & Main GUI Controller
    ========================================================================
    Responsibilities:
      • Orchestrate Core and Components modules
      • Build main GUI window with proper hierarchy
      • Handle window dragging (PC & Mobile)
      • Implement tab switching logic
      • Manage main container layout
      • Expose API through getgenv()
    ========================================================================
--]]

local UIMaster = {}
UIMaster.__index = UIMaster

-- ============================================================
-- IMPORTS & DEPENDENCIES
-- ============================================================
local getg = getgenv or (function() return _G end)
local G = getg()

local UICore = G.UICore or require(script.Parent:FindFirstChild("ui_core"))
local UIComponents = G.UIComponents or require(script.Parent:FindFirstChild("ui_components"))

if not UICore or not UIComponents then
    error("[UIMaster] Dependencies not found (UICore, UIComponents)")
end

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

-- ============================================================
-- CONFIGURATION
-- ============================================================
local WINDOW_CONFIG = {
    Width = UICore.IS_MOBILE and 680 or 900,
    Height = UICore.IS_MOBILE and 420 or 560,
    CornerRadius = 14,
    HasDragBar = true,
    DragBarHeight = UICore.scaleSize(50),
    Title = "UI Library",
    Resizable = false,
}

-- ============================================================
-- WINDOW CLASS
-- ============================================================
function UIMaster.new()
    local self = setmetatable({
        Instance = nil,
        MainFrame = nil,
        Header = nil,
        ContentArea = nil,
        Components = {},
        State = {
            IsOpen = false,
            IsDragging = false,
            DragStart = nil,
            StartPos = nil,
        },
        Config = {},
    }, UIMaster)
    
    return self
end

--- Initialize the main GUI window
function UIMaster:Initialize(config)
    config = config or {}
    self.Config = {
        Title = config.Title or WINDOW_CONFIG.Title,
        Width = config.Width or WINDOW_CONFIG.Width,
        Height = config.Height or WINDOW_CONFIG.Height,
        CornerRadius = config.CornerRadius or WINDOW_CONFIG.CornerRadius,
        Parent = config.Parent or self:_getUIParent(),
        CanDrag = config.CanDrag ~= false,
        ShowCloseButton = config.ShowCloseButton ~= false,
    }
    
    -- Create screen GUI if not provided
    if not self.Config.Parent then
        self.Config.Parent = self:_getUIParent()
    end
    
    -- Build main window
    self:_buildMainWindow()
    self:_buildHeader()
    self:_buildContentArea()
    self:_setupDragSystem()
    
    self.State.IsOpen = true
    
    -- Entrance animation
    self:_playEntranceAnimation()
    
    return self
end

--- Get or create UI parent
function UIMaster:_getUIParent()
    local ok, cg = pcall(function()
        local g = game:GetService("CoreGui")
        local t = Instance.new("Frame")
        t.Parent = g
        t:Destroy()
        return g
    end)
    
    if ok and cg then
        return cg
    else
        return Players.LocalPlayer:WaitForChild("PlayerGui")
    end
end

--- Build main window frame
function UIMaster:_buildMainWindow()
    -- Clean up old UI if exists
    pcall(function()
        local existing = self.Config.Parent:FindFirstChild("UILibraryWindow")
        if existing then existing:Destroy() end
    end)
    
    -- Create screen gui wrapper
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "UILibraryScreen"
    screenGui.ResetOnSpawn = false
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.DisplayOrder = 999
    screenGui.IgnoreGuiInset = true
    screenGui.Parent = self.Config.Parent
    
    -- Create main window
    local mainFrame = Instance.new("Frame")
    mainFrame.Name = "UILibraryWindow"
    mainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
    mainFrame.Size = UDim2.new(0, self.Config.Width, 0, self.Config.Height)
    mainFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
    mainFrame.BackgroundColor3 = UICore.PALETTE.bg0
    mainFrame.BorderSizePixel = 0
    mainFrame.ClipsDescendants = true
    mainFrame.Parent = screenGui
    
    -- Visual elements
    UICore.createCorner(mainFrame, self.Config.CornerRadius)
    UICore.createStroke(mainFrame, UICore.PALETTE.stroke, 1.5)
    
    -- Background gradient
    local gradient = UICore.createGradient(mainFrame, ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(12, 15, 28)),
        ColorSequenceKeypoint.new(0.5, Color3.fromRGB(8, 10, 18)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(14, 10, 22)),
    }), 135)
    
    self.Instance = mainFrame
    self.ScreenGui = screenGui
    
    return mainFrame
end

--- Build header with title and close button
function UIMaster:_buildHeader()
    local header = Instance.new("Frame")
    header.Name = "Header"
    header.Size = UDim2.new(1, 0, 0, self.Config.Height * 0.08)
    header.Position = UDim2.new(0, 0, 0, 0)
    header.BackgroundColor3 = UICore.PALETTE.header
    header.BorderSizePixel = 0
    header.Parent = self.Instance
    
    UICore.createStroke(header, UICore.PALETTE.stroke, 1)
    
    -- Title label
    local titleLabel = Instance.new("TextLabel")
    titleLabel.Name = "Title"
    titleLabel.Size = UDim2.new(0.8, -20, 1, 0)
    titleLabel.Position = UDim2.new(0, 15, 0, 0)
    titleLabel.BackgroundTransparency = 1
    titleLabel.Font = Enum.Font.GothamBold
    titleLabel.TextSize = UICore.scaleSize(14)
    titleLabel.TextColor3 = UICore.PALETTE.text0
    titleLabel.Text = self.Config.Title
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.TextYAlignment = Enum.TextYAlignment.Center
    titleLabel.Parent = header
    
    -- Close button
    if self.Config.ShowCloseButton then
        local closeBtn = Instance.new("TextButton")
        closeBtn.Name = "CloseBtn"
        closeBtn.Size = UDim2.new(0, 30, 0, 30)
        closeBtn.Position = UDim2.new(1, -35, 0.5, 0)
        closeBtn.AnchorPoint = Vector2.new(0.5, 0.5)
        closeBtn.BackgroundColor3 = UICore.PALETTE.red
        closeBtn.TextColor3 = UICore.PALETTE.text0
        closeBtn.Font = Enum.Font.GothamBold
        closeBtn.TextSize = UICore.scaleSize(16)
        closeBtn.Text = "✕"
        closeBtn.AutoButtonColor = false
        closeBtn.BorderSizePixel = 0
        closeBtn.Parent = header
        
        UICore.createCorner(closeBtn, 4)
        
        closeBtn.MouseButton1Click:Connect(function()
            self:Close()
        end)
        
        closeBtn.MouseEnter:Connect(function()
            UICore.colorShift(closeBtn, UICore.PALETTE.redDk, 0.1, "BackgroundColor3")
        end)
        
        closeBtn.MouseLeave:Connect(function()
            UICore.colorShift(closeBtn, UICore.PALETTE.red, 0.1, "BackgroundColor3")
        end)
    end
    
    -- Accent line animation
    local accentLine = Instance.new("Frame")
    accentLine.Name = "AccentLine"
    accentLine.Size = UDim2.new(0.3, 0, 0, 2)
    accentLine.Position = UDim2.new(0, 0, 1, -2)
    accentLine.BackgroundColor3 = UICore.PALETTE.accent
    accentLine.BorderSizePixel = 0
    accentLine.Parent = header
    
    self.Header = header
    
    return header
end

--- Build content area
function UIMaster:_buildContentArea()
    local contentArea = Instance.new("Frame")
    contentArea.Name = "ContentArea"
    contentArea.Size = UDim2.new(1, 0, 1, -self.Config.Height * 0.08)
    contentArea.Position = UDim2.new(0, 0, 0, self.Config.Height * 0.08)
    contentArea.BackgroundColor3 = UICore.PALETTE.bg1
    contentArea.BorderSizePixel = 0
    contentArea.ClipsDescendants = true
    contentArea.Parent = self.Instance
    
    -- Add padding and vertical layout
    UICore.createPadding(contentArea, 12, 12, 12, 12)
    UICore.createVerticalLayout(contentArea, 8)
    
    self.ContentArea = contentArea
    
    return contentArea
end

--- Setup drag system for both PC and mobile
function UIMaster:_setupDragSystem()
    if not self.Config.CanDrag then return end
    
    local mainFrame = self.Instance
    local header = self.Header
    local state = self.State
    
    -- =========== MOUSE DRAG ===========
    UserInputService.InputBegan:Connect(function(input, gpe)
        if gpe then return end
        
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            -- Check if mouse is over header
            if header then
                local mp = input.Position
                local ap = header.AbsolutePosition
                local as = header.AbsoluteSize
                
                if mp.X >= ap.X and mp.X <= ap.X + as.X
                and mp.Y >= ap.Y and mp.Y <= ap.Y + as.Y then
                    self:_beginDrag(Vector2.new(mp.X, mp.Y))
                end
            end
        end
    end)
    
    UserInputService.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement and state.IsDragging then
            self:_moveDrag(Vector2.new(input.Position.X, input.Position.Y))
        end
    end)
    
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            state.IsDragging = false
        end
    end)
    
    -- =========== TOUCH DRAG ===========
    local touchId = nil
    
    UserInputService.InputBegan:Connect(function(input, gpe)
        if gpe or touchId then return end
        
        if input.UserInputType == Enum.UserInputType.Touch then
            if header then
                local tp = input.Position
                local ap = header.AbsolutePosition
                local as = header.AbsoluteSize
                
                if tp.X >= ap.X and tp.X <= ap.X + as.X
                and tp.Y >= ap.Y and tp.Y <= ap.Y + as.Y then
                    touchId = input
                    self:_beginDrag(Vector2.new(tp.X, tp.Y))
                end
            end
        end
    end)
    
    UserInputService.InputChanged:Connect(function(input)
        if input == touchId then
            self:_moveDrag(Vector2.new(input.Position.X, input.Position.Y))
        end
    end)
    
    UserInputService.InputEnded:Connect(function(input)
        if input == touchId then
            touchId = nil
            state.IsDragging = false
        end
    end)
end

--- Begin drag operation
function UIMaster:_beginDrag(inputPos)
    self.State.IsDragging = true
    self.State.DragStart = inputPos
    self.State.StartPos = self.Instance.AbsolutePosition + self.Instance.AbsoluteSize * self.Instance.AnchorPoint
end

--- Move window during drag
function UIMaster:_moveDrag(inputPos)
    if not self.State.IsDragging then return end
    
    local delta = inputPos - self.State.DragStart
    local vp = workspace.CurrentCamera.ViewportSize
    
    local newX = math.clamp(
        self.State.StartPos.X + delta.X,
        self.Config.Width / 2,
        vp.X - self.Config.Width / 2
    )
    
    local newY = math.clamp(
        self.State.StartPos.Y + delta.Y,
        self.Config.Height / 2,
        vp.Y - self.Config.Height / 2
    )
    
    self.Instance.Position = UDim2.new(0, newX, 0, newY)
end

--- Play entrance animation
function UIMaster:_playEntranceAnimation()
    self.Instance.BackgroundTransparency = 1
    local originalSize = self.Instance.Size
    self.Instance.Size = UDim2.new(
        originalSize.X.Scale * 0.88,
        originalSize.X.Offset * 0.88,
        originalSize.Y.Scale * 0.88,
        originalSize.Y.Offset * 0.88
    )
    
    _G.task.defer(function()
        UICore.createTween(self.Instance, UICore.TWEEN_PRESETS.BOUNCE, {
            Size = originalSize,
            BackgroundTransparency = 0,
        })
    end)
end

--- Add a button to content area
function UIMaster:AddButton(config)
    config = config or {}
    config.Size = config.Size or UDim2.new(1, 0, 0, 35)
    
    local btn = UIComponents.Button.new(self.ContentArea, config)
    table.insert(self.Components, btn)
    
    return btn
end

--- Add a toggle to content area
function UIMaster:AddToggle(config)
    config = config or {}
    config.Size = config.Size or UDim2.new(1, 0, 0, 35)
    
    local toggle = UIComponents.Toggle.new(self.ContentArea, config)
    table.insert(self.Components, toggle)
    
    return toggle
end

--- Add a slider to content area
function UIMaster:AddSlider(config)
    config = config or {}
    config.Size = config.Size or UDim2.new(1, 0, 0, 50)
    
    local slider = UIComponents.Slider.new(self.ContentArea, config)
    table.insert(self.Components, slider)
    
    return slider
end

--- Add tabs to content area
function UIMaster:AddTabs(config)
    config = config or {}
    config.Size = config.Size or UDim2.new(1, 0, 1, 0)
    
    local tabs = UIComponents.Tabs.new(self.ContentArea, config)
    table.insert(self.Components, tabs)
    
    return tabs
end

--- Add a label to content area
function UIMaster:AddLabel(text, config)
    config = config or {}
    config.Text = text
    config.Size = config.Size or UDim2.new(1, 0, 0, 25)
    
    local label = Instance.new("TextLabel")
    label.Name = "Label"
    label.Size = config.Size
    label.BackgroundTransparency = 1
    label.Font = config.Font or Enum.Font.GothamMedium
    label.TextSize = config.TextSize or UICore.scaleSize(12)
    label.TextColor3 = config.TextColor or UICore.PALETTE.text1
    label.Text = text
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.TextYAlignment = Enum.TextYAlignment.Center
    label.Parent = self.ContentArea
    
    return label
end

--- Close the GUI window
function UIMaster:Close()
    UICore.fadeOut(self.Instance, 0.2, function()
        self.ScreenGui:Destroy()
        self.State.IsOpen = false
    end)
end

--- Open/show the GUI window
function UIMaster:Open()
    if self.State.IsOpen then return end
    
    self.Instance.Visible = true
    UICore.fadeIn(self.Instance, 0.2)
    self.State.IsOpen = true
end

--- Toggle window visibility
function UIMaster:Toggle()
    if self.State.IsOpen then
        self:Close()
    else
        self:Open()
    end
end

--- Get the content area for custom UI
function UIMaster:GetContentArea()
    return self.ContentArea
end

--- Get the main window frame
function UIMaster:GetMainFrame()
    return self.Instance
end

--- Destroy all components and close GUI
function UIMaster:Destroy()
    for _, component in ipairs(self.Components) do
        component:destroy()
    end
    
    self.Components = {}
    self:Close()
end

-- ============================================================
-- PUBLIC API
-- ============================================================
local function createUI(config)
    local ui = UIMaster.new()
    ui:Initialize(config)
    return ui
end

-- ============================================================
-- GLOBAL EXPORT
-- ============================================================
if not G.UILibrary then
    G.UILibrary = {
        Create = createUI,
        Core = UICore,
        Components = UIComponents,
        Master = UIMaster,
    }
end

return UIMaster
