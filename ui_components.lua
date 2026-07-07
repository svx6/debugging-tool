--[[
    ========================================================================
    UI COMPONENTS MODULE - Factory Pattern for UI Elements
    ========================================================================
    Responsibilities:
      • Factory functions for Button, Toggle, Slider, Tabs components
      • Responsive design (Scale-based sizing for all platforms)
      • OOP-based component architecture
      • Mobile & PC input compatibility
      • Animation integration
    ========================================================================
--]]

local UIComponents = {}

-- ============================================================
-- IMPORTS & DEPENDENCIES
-- ============================================================
local getg = getgenv or (function() return _G end)
local G = getg()
local UICore = G.UICore or require(script.Parent:FindFirstChild("ui_core"))

if not UICore then
    error("[UIComponents] UICore module not found")
end

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

-- ============================================================
-- COMPONENT BASE CLASS
-- ============================================================
local Component = {}
Component.__index = Component

function Component.new()
    return setmetatable({
        Instance = nil,
        Config = {},
        State = {},
        Callbacks = {},
    }, Component)
end

function Component:setConfig(config)
    self.Config = config or {}
    return self
end

function Component:setState(key, value)
    self.State[key] = value
    return self
end

function Component:getState(key)
    return self.State[key]
end

function Component:on(event, callback)
    if not self.Callbacks[event] then
        self.Callbacks[event] = {}
    end
    table.insert(self.Callbacks[event], callback)
    return self
end

function Component:emit(event, ...)
    if self.Callbacks[event] then
        for _, callback in ipairs(self.Callbacks[event]) do
            pcall(callback, ...)
        end
    end
    return self
end

function Component:destroy()
    if self.Instance then
        self.Instance:Destroy()
    end
    self.Instance = nil
    self.Callbacks = {}
    self.State = {}
    return self
end

-- ============================================================
-- BUTTON COMPONENT
-- ============================================================
local Button = setmetatable({}, Component)
Button.__index = Button

function Button.new(parent, config)
    local self = Component.new()
    setmetatable(self, Button)
    
    config = config or {}
    self.Config = {
        Text = config.Text or "Button",
        Size = config.Size or UDim2.new(0.3, 0, 0, 40),
        Position = config.Position or UDim2.new(0, 0, 0, 0),
        BackgroundColor = config.BackgroundColor or UICore.PALETTE.accent,
        TextColor = config.TextColor or UICore.PALETTE.text0,
        HoverColor = config.HoverColor or UICore.PALETTE.accentLt,
        PressColor = config.PressColor or UICore.PALETTE.accentDk,
        CornerRadius = config.CornerRadius or 6,
        Font = config.Font or Enum.Font.GothamBold,
        TextSize = config.TextSize or UICore.scaleSize(11),
        Enabled = config.Enabled ~= false,
        OnClick = config.OnClick or nil,
    }
    
    self.State = {
        IsHovering = false,
        IsPressed = false,
    }
    
    -- Create button instance
    local button = Instance.new("TextButton")
    button.Name = config.Name or "Button"
    button.Size = self.Config.Size
    button.Position = self.Config.Position
    button.BackgroundColor3 = self.Config.BackgroundColor
    button.TextColor3 = self.Config.TextColor
    button.Font = self.Config.Font
    button.TextSize = self.Config.TextSize
    button.Text = self.Config.Text
    button.AutoButtonColor = false
    button.BorderSizePixel = 0
    button.Parent = parent
    
    self.Instance = button
    
    -- Add visual elements
    UICore.createCorner(button, self.Config.CornerRadius)
    UICore.createStroke(button, UICore.PALETTE.stroke, 1)
    
    -- Setup interactions
    self:_setupInteractions()
    
    return self
end

function Button:_setupInteractions()
    local button = self.Instance
    local config = self.Config
    local state = self.State
    
    -- Mouse Enter
    button.MouseEnter:Connect(function()
        if not config.Enabled then return end
        state.IsHovering = true
        UICore.colorShift(button, config.HoverColor, 0.15, "BackgroundColor3")
    end)
    
    -- Mouse Leave
    button.MouseLeave:Connect(function()
        state.IsHovering = false
        UICore.colorShift(button, config.BackgroundColor, 0.15, "BackgroundColor3")
    end)
    
    -- Mouse Button Down
    button.MouseButton1Down:Connect(function()
        if not config.Enabled then return end
        state.IsPressed = true
        local originalSize = button.Size
        UICore.createTween(button, UICore.TWEEN_PRESETS.FAST, {
            Size = UDim2.new(
                originalSize.X.Scale, math.max(0, originalSize.X.Offset - 2),
                originalSize.Y.Scale, math.max(0, originalSize.Y.Offset - 2)
            )
        })
        UICore.colorShift(button, config.PressColor, 0.08, "BackgroundColor3")
    end)
    
    -- Mouse Button Up
    button.MouseButton1Up:Connect(function()
        state.IsPressed = false
        local originalSize = button.Size
        UICore.createTween(button, UICore.TWEEN_PRESETS.BOUNCE, {
            Size = UDim2.new(
                originalSize.X.Scale, originalSize.X.Offset + 2,
                originalSize.Y.Scale, originalSize.Y.Offset + 2
            )
        })
        UICore.colorShift(button, config.HoverColor, 0.12, "BackgroundColor3")
        
        self:emit("clicked")
        if config.OnClick then
            config.OnClick()
        end
    end)
end

function Button:setText(text)
    self.Config.Text = text
    self.Instance.Text = text
    return self
end

function Button:setEnabled(enabled)
    self.Config.Enabled = enabled
    self.Instance.TextTransparency = enabled and 0 or 0.5
    self.Instance.BackgroundTransparency = enabled and 0 or 0.3
    return self
end

function Button:getIsPressed()
    return self.State.IsPressed
end

-- ============================================================
-- TOGGLE COMPONENT
-- ============================================================
local Toggle = setmetatable({}, Component)
Toggle.__index = Toggle

function Toggle.new(parent, config)
    local self = Component.new()
    setmetatable(self, Toggle)
    
    config = config or {}
    self.Config = {
        Text = config.Text or "Toggle",
        Size = config.Size or UDim2.new(0.4, 0, 0, 40),
        Position = config.Position or UDim2.new(0, 0, 0, 0),
        Default = config.Default or false,
        OnColor = config.OnColor or UICore.PALETTE.green,
        OffColor = config.OffColor or UICore.PALETTE.card,
        Font = config.Font or Enum.Font.GothamMedium,
        TextSize = config.TextSize or UICore.scaleSize(11),
        OnChanged = config.OnChanged or nil,
    }
    
    self.State = {
        IsToggled = self.Config.Default,
        IsHovering = false,
    }
    
    -- Create container
    local container = Instance.new("Frame")
    container.Name = config.Name or "Toggle"
    container.Size = self.Config.Size
    container.Position = self.Config.Position
    container.BackgroundColor3 = UICore.PALETTE.bg1
    container.BorderSizePixel = 0
    container.Parent = parent
    
    UICore.createCorner(container, 6)
    UICore.createStroke(container, UICore.PALETTE.stroke, 1)
    
    -- Add label
    local label = Instance.new("TextLabel")
    label.Name = "Label"
    label.Size = UDim2.new(0.7, 0, 1, 0)
    label.Position = UDim2.new(0, 10, 0, 0)
    label.BackgroundTransparency = 1
    label.Font = self.Config.Font
    label.TextSize = self.Config.TextSize
    label.TextColor3 = UICore.PALETTE.text0
    label.Text = self.Config.Text
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.TextYAlignment = Enum.TextYAlignment.Center
    label.Parent = container
    
    -- Create toggle switch
    local switch = Instance.new("Frame")
    switch.Name = "Switch"
    switch.Size = UDim2.new(0.25, 0, 0.6, 0)
    switch.Position = UDim2.new(0.7, 0, 0.5, 0)
    switch.AnchorPoint = Vector2.new(0.5, 0.5)
    switch.BackgroundColor3 = self.State.IsToggled and self.Config.OnColor or self.Config.OffColor
    switch.BorderSizePixel = 0
    switch.Parent = container
    
    UICore.createCorner(switch, 4)
    UICore.createStroke(switch, UICore.PALETTE.stroke, 1)
    
    self.Instance = container
    self.SwitchInstance = switch
    
    -- Setup interactions
    self:_setupInteractions()
    
    return self
end

function Toggle:_setupInteractions()
    local container = self.Instance
    local switch = self.SwitchInstance
    local config = self.Config
    local state = self.State
    
    -- Click handler
    container.MouseButton1Click:Connect(function()
        state.IsToggled = not state.IsToggled
        
        local targetColor = state.IsToggled and config.OnColor or config.OffColor
        UICore.colorShift(switch, targetColor, 0.2, "BackgroundColor3")
        
        self:emit("toggled", state.IsToggled)
        if config.OnChanged then
            config.OnChanged(state.IsToggled)
        end
    end)
    
    -- Make container clickable
    local button = Instance.new("TextButton")
    button.Size = UDim2.new(1, 0, 1, 0)
    button.Position = UDim2.new(0, 0, 0, 0)
    button.BackgroundTransparency = 1
    button.Text = ""
    button.Parent = container
    
    button.MouseButton1Click:Connect(function()
        container.MouseButton1Click:Fire()
    end)
    
    button.MouseEnter:Connect(function()
        state.IsHovering = true
        UICore.createTween(container, UICore.TWEEN_PRESETS.FAST, {
            BackgroundColor3 = UICore.PALETTE.bg2
        })
    end)
    
    button.MouseLeave:Connect(function()
        state.IsHovering = false
        UICore.createTween(container, UICore.TWEEN_PRESETS.FAST, {
            BackgroundColor3 = UICore.PALETTE.bg1
        })
    end)
end

function Toggle:toggle(state)
    if state ~= nil then
        self.State.IsToggled = state
    else
        self.State.IsToggled = not self.State.IsToggled
    end
    
    local targetColor = self.State.IsToggled and self.Config.OnColor or self.Config.OffColor
    UICore.colorShift(self.SwitchInstance, targetColor, 0.2, "BackgroundColor3")
    
    return self.State.IsToggled
end

function Toggle:isToggled()
    return self.State.IsToggled
end

-- ============================================================
-- SLIDER COMPONENT
-- ============================================================
local Slider = setmetatable({}, Component)
Slider.__index = Slider

function Slider.new(parent, config)
    local self = Component.new()
    setmetatable(self, Slider)
    
    config = config or {}
    self.Config = {
        Text = config.Text or "Slider",
        Size = config.Size or UDim2.new(0.4, 0, 0, 50),
        Position = config.Position or UDim2.new(0, 0, 0, 0),
        Min = config.Min or 0,
        Max = config.Max or 100,
        Default = config.Default or 50,
        Precision = config.Precision or 1,
        OnChanged = config.OnChanged or nil,
    }
    
    self.State = {
        Value = self.Config.Default,
        IsDragging = false,
    }
    
    -- Create container
    local container = Instance.new("Frame")
    container.Name = config.Name or "Slider"
    container.Size = self.Config.Size
    container.Position = self.Config.Position
    container.BackgroundColor3 = UICore.PALETTE.bg1
    container.BorderSizePixel = 0
    container.Parent = parent
    
    UICore.createCorner(container, 6)
    UICore.createStroke(container, UICore.PALETTE.stroke, 1)
    
    -- Label
    local label = Instance.new("TextLabel")
    label.Name = "Label"
    label.Size = UDim2.new(0.5, -5, 0, 20)
    label.Position = UDim2.new(0, 5, 0, 2)
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.GothamMedium
    label.TextSize = UICore.scaleSize(10)
    label.TextColor3 = UICore.PALETTE.text0
    label.Text = self.Config.Text
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = container
    
    -- Value display
    local valueLabel = Instance.new("TextLabel")
    valueLabel.Name = "Value"
    valueLabel.Size = UDim2.new(0.4, 0, 0, 20)
    valueLabel.Position = UDim2.new(0.55, 0, 0, 2)
    valueLabel.BackgroundTransparency = 1
    valueLabel.Font = Enum.Font.GothamBold
    valueLabel.TextSize = UICore.scaleSize(10)
    valueLabel.TextColor3 = UICore.PALETTE.accent
    valueLabel.Text = tostring(self.State.Value)
    valueLabel.TextXAlignment = Enum.TextXAlignment.Right
    valueLabel.Parent = container
    
    -- Slider background
    local sliderBg = Instance.new("Frame")
    sliderBg.Name = "SliderBG"
    sliderBg.Size = UDim2.new(1, -10, 0, 4)
    sliderBg.Position = UDim2.new(0, 5, 0.5, 0)
    sliderBg.AnchorPoint = Vector2.new(0, 0.5)
    sliderBg.BackgroundColor3 = UICore.PALETTE.bg2
    sliderBg.BorderSizePixel = 0
    sliderBg.Parent = container
    
    UICore.createCorner(sliderBg, 2)
    
    -- Slider fill
    local sliderFill = Instance.new("Frame")
    sliderFill.Name = "Fill"
    sliderFill.Size = UDim2.new(0, 0, 1, 0)
    sliderFill.BackgroundColor3 = UICore.PALETTE.accent
    sliderFill.BorderSizePixel = 0
    sliderFill.Parent = sliderBg
    
    UICore.createCorner(sliderFill, 2)
    
    -- Slider handle
    local handle = Instance.new("Frame")
    handle.Name = "Handle"
    handle.Size = UDim2.new(0, 12, 0, 20)
    handle.Position = UDim2.new(0, 0, 0.5, 0)
    handle.AnchorPoint = Vector2.new(0.5, 0.5)
    handle.BackgroundColor3 = UICore.PALETTE.accent
    handle.BorderSizePixel = 0
    handle.Parent = sliderBg
    
    UICore.createCorner(handle, 3)
    UICore.createStroke(handle, UICore.PALETTE.accentLt, 1.5)
    
    self.Instance = container
    self.SliderBG = sliderBg
    self.SliderFill = sliderFill
    self.Handle = handle
    self.ValueLabel = valueLabel
    
    self:_setupInteractions()
    self:_updateSliderPosition()
    
    return self
end

function Slider:_updateSliderPosition()
    local min = self.Config.Min
    local max = self.Config.Max
    local value = self.State.Value
    
    local percentage = (value - min) / (max - min)
    percentage = math.clamp(percentage, 0, 1)
    
    local bgSize = self.SliderBG.AbsoluteSize.X
    local fillWidth = bgSize * percentage
    
    UICore.createTween(self.SliderFill, UICore.TWEEN_PRESETS.FAST, {
        Size = UDim2.new(0, fillWidth, 1, 0)
    })
    
    UICore.createTween(self.Handle, UICore.TWEEN_PRESETS.FAST, {
        Position = UDim2.new(0, fillWidth, 0.5, 0)
    })
    
    self.ValueLabel.Text = string.format("%.0f", value)
end

function Slider:_setupInteractions()
    local sliderBg = self.SliderBG
    local handle = self.Handle
    local state = self.State
    local config = self.Config
    
    local function getValueFromPosition(x)
        local bgPosition = sliderBg.AbsolutePosition.X
        local bgSize = sliderBg.AbsoluteSize.X
        
        local relativeX = x - bgPosition
        relativeX = math.clamp(relativeX, 0, bgSize)
        
        local percentage = relativeX / bgSize
        local range = config.Max - config.Min
        local value = config.Min + (percentage * range)
        
        return math.round(value / config.Precision) * config.Precision
    end
    
    sliderBg.MouseButton1Down:Connect(function()
        state.IsDragging = true
        local mousePos = UserInputService:GetMouseLocation()
        state.Value = getValueFromPosition(mousePos.X)
        self:_updateSliderPosition()
        self:emit("changed", state.Value)
        if config.OnChanged then
            config.OnChanged(state.Value)
        end
    end)
    
    handle.MouseButton1Down:Connect(function()
        state.IsDragging = true
    end)
    
    UserInputService.InputChanged:Connect(function(input)
        if state.IsDragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            local mousePos = input.Position
            state.Value = getValueFromPosition(mousePos.X)
            self:_updateSliderPosition()
            self:emit("changed", state.Value)
            if config.OnChanged then
                config.OnChanged(state.Value)
            end
        end
    end)
    
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            state.IsDragging = false
        end
    end)
    
    handle.MouseEnter:Connect(function()
        UICore.colorShift(handle, UICore.PALETTE.accentLt, 0.1, "BackgroundColor3")
    end)
    
    handle.MouseLeave:Connect(function()
        UICore.colorShift(handle, UICore.PALETTE.accent, 0.1, "BackgroundColor3")
    end)
end

function Slider:setValue(value)
    self.State.Value = math.clamp(value, self.Config.Min, self.Config.Max)
    self:_updateSliderPosition()
    return self
end

function Slider:getValue()
    return self.State.Value
end

-- ============================================================
-- TABS COMPONENT
-- ============================================================
local Tabs = setmetatable({}, Component)
Tabs.__index = Tabs

function Tabs.new(parent, config)
    local self = Component.new()
    setmetatable(self, Tabs)
    
    config = config or {}
    self.Config = {
        Size = config.Size or UDim2.new(1, 0, 1, 0),
        Position = config.Position or UDim2.new(0, 0, 0, 0),
        TabNames = config.TabNames or {"Tab 1", "Tab 2"},
        TabWidth = config.TabWidth or 120,
        OnTabChanged = config.OnTabChanged or nil,
    }
    
    self.State = {
        CurrentTab = 1,
        Tabs = {},
    }
    
    -- Create container
    local container = Instance.new("Frame")
    container.Name = config.Name or "Tabs"
    container.Size = self.Config.Size
    container.Position = self.Config.Position
    container.BackgroundTransparency = 1
    container.BorderSizePixel = 0
    container.Parent = parent
    
    -- Create tab header
    local tabHeader = Instance.new("Frame")
    tabHeader.Name = "TabHeader"
    tabHeader.Size = UDim2.new(1, 0, 0, 50)
    tabHeader.Position = UDim2.new(0, 0, 0, 0)
    tabHeader.BackgroundColor3 = UICore.PALETTE.bg0
    tabHeader.BorderSizePixel = 0
    tabHeader.Parent = container
    
    UICore.createStroke(tabHeader, UICore.PALETTE.stroke, 1)
    
    -- Create content area
    local contentArea = Instance.new("Frame")
    contentArea.Name = "ContentArea"
    contentArea.Size = UDim2.new(1, 0, 1, -50)
    contentArea.Position = UDim2.new(0, 0, 0, 50)
    contentArea.BackgroundColor3 = UICore.PALETTE.bg1
    contentArea.BorderSizePixel = 0
    contentArea.Parent = container
    
    self.Instance = container
    self.TabHeader = tabHeader
    self.ContentArea = contentArea
    
    -- Create tab buttons and content frames
    for i, tabName in ipairs(self.Config.TabNames) do
        local tabBtn = Instance.new("TextButton")
        tabBtn.Name = "Tab_" .. i
        tabBtn.Size = UDim2.new(0, self.Config.TabWidth, 1, 0)
        tabBtn.Position = UDim2.new(0, (i - 1) * self.Config.TabWidth, 0, 0)
        tabBtn.BackgroundColor3 = i == 1 and UICore.PALETTE.accent or UICore.PALETTE.bg2
        tabBtn.TextColor3 = UICore.PALETTE.text0
        tabBtn.Font = Enum.Font.GothamBold
        tabBtn.TextSize = UICore.scaleSize(11)
        tabBtn.Text = tabName
        tabBtn.AutoButtonColor = false
        tabBtn.BorderSizePixel = 0
        tabBtn.Parent = tabHeader
        
        UICore.createStroke(tabBtn, UICore.PALETTE.stroke, 1)
        
        -- Create content frame
        local content = Instance.new("Frame")
        content.Name = "Content_" .. i
        content.Size = UDim2.new(1, 0, 1, 0)
        content.Position = UDim2.new(0, 0, 0, 0)
        content.BackgroundTransparency = 1
        content.BorderSizePixel = 0
        content.Visible = i == 1
        content.Parent = contentArea
        
        UICore.createVerticalLayout(content, 5)
        UICore.createPadding(content, 10, 10, 10, 10)
        
        table.insert(self.State.Tabs, {
            Button = tabBtn,
            Content = content,
            Index = i,
        })
        
        -- Tab click handler
        local tabIndex = i
        tabBtn.MouseButton1Click:Connect(function()
            self:selectTab(tabIndex)
        end)
        
        tabBtn.MouseEnter:Connect(function()
            if tabIndex ~= self.State.CurrentTab then
                UICore.colorShift(tabBtn, UICore.PALETTE.bg2, 0.1, "BackgroundColor3")
            end
        end)
        
        tabBtn.MouseLeave:Connect(function()
            if tabIndex ~= self.State.CurrentTab then
                UICore.colorShift(tabBtn, UICore.PALETTE.card, 0.1, "BackgroundColor3")
            end
        end)
    end
    
    return self
end

function Tabs:selectTab(index)
    if index < 1 or index > #self.State.Tabs then return end
    
    -- Hide all content
    for i, tab in ipairs(self.State.Tabs) do
        tab.Content.Visible = (i == index)
        
        -- Update button appearance
        if i == index then
            UICore.colorShift(tab.Button, UICore.PALETTE.accent, 0.2, "BackgroundColor3")
        else
            UICore.colorShift(tab.Button, UICore.PALETTE.card, 0.2, "BackgroundColor3")
        end
    end
    
    self.State.CurrentTab = index
    self:emit("tabChanged", index)
    
    if self.Config.OnTabChanged then
        self.Config.OnTabChanged(index)
    end
    
    return self
end

function Tabs:getContent(index)
    if self.State.Tabs[index] then
        return self.State.Tabs[index].Content
    end
    return nil
end

function Tabs:getCurrentTab()
    return self.State.CurrentTab
end

function Tabs:getContentArea()
    return self.ContentArea
end

-- ============================================================
-- PUBLIC FACTORY FUNCTIONS
-- ============================================================
UIComponents.Button = Button
UIComponents.Toggle = Toggle
UIComponents.Slider = Slider
UIComponents.Tabs = Tabs

-- Store in global
if not G.UIComponents then
    G.UIComponents = UIComponents
end

return UIComponents
