--[[
    ========================================================================
    UI CORE MODULE - Foundation Layer
    ========================================================================
    Responsibilities:
      • Theme definitions (colors, fonts, corner radius)
      • Animation utility functions (TweenService wrapper)
      • Global shared settings (getgenv())
      • Device detection & scaling
      • Safe environment initialization
    ========================================================================
--]]

local UICore = {}
UICore.__index = UICore

-- ============================================================
-- ENVIRONMENT & SAFE GLOBALS
-- ============================================================
local getg = getgenv or (function() return _G end)
local G = getg()

-- Safe function references
local _type = type
local _pcall = pcall
local _tostr = tostring
local _print = print
local _warn = warn or print
local _unpack = table.unpack

-- Safe service references
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")

-- ============================================================
-- DEVICE DETECTION & SCALING
-- ============================================================
local function detectDevice()
    local isMobile = false
    _pcall(function()
        isMobile = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
    end)
    return isMobile
end

local IS_MOBILE = detectDevice()
local SCALE_FACTOR = IS_MOBILE and 1.18 or 1.0

local function scaleSize(value)
    return math.floor(value * SCALE_FACTOR + 0.5)
end

-- ============================================================
-- THEME PALETTE
-- ============================================================
local PALETTE = {
    -- Background shades
    bg0      = Color3.fromRGB(8,  10, 18),
    bg1      = Color3.fromRGB(12, 15, 26),
    bg2      = Color3.fromRGB(18, 22, 38),
    
    -- Card & surface colors
    card     = Color3.fromRGB(22, 26, 44),
    cardHov  = Color3.fromRGB(28, 33, 55),
    sidebar  = Color3.fromRGB(11, 14, 24),
    header   = Color3.fromRGB(14, 17, 30),
    
    -- Borders & strokes
    stroke   = Color3.fromRGB(40, 48, 80),
    strokeLt = Color3.fromRGB(60, 70, 110),
    
    -- Accent colors
    accent   = Color3.fromRGB(90, 105, 248),
    accentDk = Color3.fromRGB(30, 38, 88),
    accentLt = Color3.fromRGB(130, 145, 255),
    
    -- Text colors
    text0    = Color3.fromRGB(230, 232, 255),
    text1    = Color3.fromRGB(140, 150, 190),
    text2    = Color3.fromRGB(80,  90, 130),
    code     = Color3.fromRGB(185, 200, 240),
    
    -- Status colors
    red      = Color3.fromRGB(240, 70,  70),   redDk   = Color3.fromRGB(55, 15, 15),
    orange   = Color3.fromRGB(245, 168, 50),   orangeDk= Color3.fromRGB(55, 35, 10),
    green    = Color3.fromRGB(72,  215, 128),  greenDk = Color3.fromRGB(12, 52, 28),
    blue     = Color3.fromRGB(65,  145, 248),  blueDk  = Color3.fromRGB(12, 32, 65),
    purple   = Color3.fromRGB(172, 120, 255),  purpleDk= Color3.fromRGB(30, 20, 58),
    teal     = Color3.fromRGB(48,  210, 198),  tealDk  = Color3.fromRGB(8,  48, 46),
    yellow   = Color3.fromRGB(255, 218, 50),
}

-- ============================================================
-- TWEEN PRESETS
-- ============================================================
local TWEEN_PRESETS = {
    INSTANT = TweenInfo.new(0.0),
    FAST    = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut),
    MEDIUM  = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut),
    SLOW    = TweenInfo.new(0.45, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
    BOUNCE  = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
    ELASTIC = TweenInfo.new(0.5,  Enum.EasingStyle.Elastic, Enum.EasingDirection.Out),
    SMOOTH  = TweenInfo.new(0.6,  Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
}

-- ============================================================
-- GLOBAL SETTINGS STORAGE
-- ============================================================
if not G.UILibrarySettings then
    G.UILibrarySettings = {
        Theme = "dark",
        EnableAnimations = true,
        EnableSounds = false,
        Palette = PALETTE,
        IsMobile = IS_MOBILE,
        ScaleFactor = SCALE_FACTOR,
        DefaultFont = Enum.Font.GothamMedium,
        DefaultBoldFont = Enum.Font.GothamBold,
    }
end

-- ============================================================
-- ANIMATION UTILITY FUNCTIONS
-- ============================================================

--- Create a tween on an object
---@param object Instance - The object to tween
---@param info TweenInfo - Tween information (use presets)
---@param properties table - Properties to tween
---@return Tween - The created tween
local function createTween(object, info, properties)
    if not object or not info or not properties then
        _warn("[UICore] Invalid tween parameters")
        return nil
    end
    
    local ok, tween = _pcall(function()
        return TweenService:Create(object, info, properties)
    end)
    
    if ok and tween then
        tween:Play()
        return tween
    end
    
    return nil
end

--- Fade in an object
---@param object Instance - The object to fade in
---@param duration number - Duration in seconds (default: 0.25)
---@param callback function - Optional callback when finished
local function fadeIn(object, duration, callback)
    duration = duration or 0.25
    local info = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    local tween = createTween(object, info, {BackgroundTransparency = 0, TextTransparency = 0})
    
    if tween and callback then
        tween.Completed:Connect(callback)
    end
    
    return tween
end

--- Fade out an object
---@param object Instance - The object to fade out
---@param duration number - Duration in seconds (default: 0.25)
---@param callback function - Optional callback when finished
local function fadeOut(object, duration, callback)
    duration = duration or 0.25
    local info = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
    local tween = createTween(object, info, {BackgroundTransparency = 1, TextTransparency = 1})
    
    if tween and callback then
        tween.Completed:Connect(callback)
    end
    
    return tween
end

--- Scale an object (entrance/exit)
---@param object Instance - The object to scale
---@param targetScale number - Target scale (1.0 = original)
---@param duration number - Duration in seconds (default: 0.35)
---@param callback function - Optional callback when finished
local function scaleObject(object, targetScale, duration, callback)
    duration = duration or 0.35
    local info = TweenInfo.new(duration, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
    
    local originalSize = object.Size
    local newSize = UDim2.new(
        originalSize.X.Scale * targetScale,
        originalSize.X.Offset * targetScale,
        originalSize.Y.Scale * targetScale,
        originalSize.Y.Offset * targetScale
    )
    
    local tween = createTween(object, info, {Size = newSize})
    
    if tween and callback then
        tween.Completed:Connect(callback)
    end
    
    return tween
end

--- Pulse animation (scale in and out)
---@param object Instance - The object to pulse
---@param intensity number - Pulse intensity (default: 1.1)
---@param duration number - Duration in seconds (default: 0.5)
local function pulse(object, intensity, duration)
    intensity = intensity or 1.1
    duration = duration or 0.5
    
    local originalSize = object.Size
    local newSize = UDim2.new(
        originalSize.X.Scale * intensity,
        originalSize.X.Offset * intensity,
        originalSize.Y.Scale * intensity,
        originalSize.Y.Offset * intensity
    )
    
    local info = TweenInfo.new(duration / 2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    local tween1 = createTween(object, info, {Size = newSize})
    
    if tween1 then
        tween1.Completed:Connect(function()
            createTween(object, info, {Size = originalSize})
        end)
    end
    
    return tween1
end

--- Slide animation
---@param object Instance - The object to slide
---@param direction string - "in" or "out"
---@param axis string - "x" or "y"
---@param distance number - Distance in pixels
---@param duration number - Duration in seconds (default: 0.3)
---@param callback function - Optional callback when finished
local function slide(object, direction, axis, distance, duration, callback)
    duration = duration or 0.3
    local info = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
    
    local originalPos = object.Position
    local newPos = originalPos
    
    if axis == "x" then
        local offset = direction == "in" and -distance or distance
        newPos = UDim2.new(originalPos.X.Scale, originalPos.X.Offset + offset, originalPos.Y.Scale, originalPos.Y.Offset)
    elseif axis == "y" then
        local offset = direction == "in" and -distance or distance
        newPos = UDim2.new(originalPos.X.Scale, originalPos.X.Offset, originalPos.Y.Scale, originalPos.Y.Offset + offset)
    end
    
    local tween = createTween(object, info, {Position = newPos})
    
    if tween and callback then
        tween.Completed:Connect(callback)
    end
    
    return tween
end

--- Rotate animation (color rotation for gradients, etc.)
---@param object Instance - The object with UIGradient
---@param targetRotation number - Target rotation in degrees
---@param duration number - Duration in seconds
---@param callback function - Optional callback when finished
local function rotate(object, targetRotation, duration, callback)
    duration = duration or 1.0
    local info = TweenInfo.new(duration, Enum.EasingStyle.Linear)
    
    local tween = createTween(object, info, {Rotation = targetRotation})
    
    if tween and callback then
        tween.Completed:Connect(callback)
    end
    
    return tween
end

--- Animate color change
---@param object Instance - The object to color
---@param targetColor Color3 - Target color
---@param duration number - Duration in seconds (default: 0.25)
---@param property string - Property to change (default: "BackgroundColor3")
---@param callback function - Optional callback when finished
local function colorShift(object, targetColor, duration, property, callback)
    duration = duration or 0.25
    property = property or "BackgroundColor3"
    
    local info = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
    local props = {[property] = targetColor}
    
    local tween = createTween(object, info, props)
    
    if tween and callback then
        tween.Completed:Connect(callback)
    end
    
    return tween
end

-- ============================================================
-- UI PRIMITIVE BUILDERS
-- ============================================================

--- Create a UICorner
---@param parent Instance - Parent object
---@param radius number - Corner radius in pixels (default: 8)
---@return UICorner
local function createCorner(parent, radius)
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, radius or 8)
    corner.Parent = parent
    return corner
end

--- Create a UIStroke
---@param parent Instance - Parent object
---@param color Color3 - Stroke color (default: stroke)
---@param thickness number - Stroke thickness (default: 1.2)
---@return UIStroke
local function createStroke(parent, color, thickness)
    local stroke = Instance.new("UIStroke")
    stroke.Color = color or PALETTE.stroke
    stroke.Thickness = thickness or 1.2
    stroke.Parent = parent
    return stroke
end

--- Create a UIPadding
---@param parent Instance - Parent object
---@param top number - Top padding
---@param bottom number - Bottom padding
---@param left number - Left padding
---@param right number - Right padding
---@return UIPadding
local function createPadding(parent, top, bottom, left, right)
    local padding = Instance.new("UIPadding")
    padding.PaddingTop = UDim.new(0, top or 0)
    padding.PaddingBottom = UDim.new(0, bottom or 0)
    padding.PaddingLeft = UDim.new(0, left or 0)
    padding.PaddingRight = UDim.new(0, right or 0)
    padding.Parent = parent
    return padding
end

--- Create a UIListLayout (vertical)
---@param parent Instance - Parent object
---@param spacing number - Spacing between items
---@return UIListLayout
local function createVerticalLayout(parent, spacing)
    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Vertical
    layout.Padding = UDim.new(0, spacing or 5)
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Parent = parent
    return layout
end

--- Create a UIListLayout (horizontal)
---@param parent Instance - Parent object
---@param spacing number - Spacing between items
---@return UIListLayout
local function createHorizontalLayout(parent, spacing)
    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Horizontal
    layout.Padding = UDim.new(0, spacing or 5)
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Parent = parent
    return layout
end

--- Create a UIGridLayout
---@param parent Instance - Parent object
---@param cellSize UDim2 - Size of each cell
---@param spacing number - Spacing between cells
---@return UIGridLayout
local function createGridLayout(parent, cellSize, spacing)
    local layout = Instance.new("UIGridLayout")
    layout.CellSize = cellSize or UDim2.new(0, 100, 0, 100)
    layout.CellPadding = UDim2.new(0, spacing or 5, 0, spacing or 5)
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Parent = parent
    return layout
end

--- Create a gradient background
---@param parent Instance - Parent object
---@param colorSequence ColorSequence - Color gradient
---@param rotation number - Gradient rotation (default: 135)
---@return UIGradient
local function createGradient(parent, colorSequence, rotation)
    local gradient = Instance.new("UIGradient")
    gradient.Color = colorSequence
    gradient.Rotation = rotation or 135
    gradient.Parent = parent
    return gradient
end

-- ============================================================
-- PUBLIC MODULE INTERFACE
-- ============================================================
UICore.PALETTE = PALETTE
UICore.TWEEN_PRESETS = TWEEN_PRESETS
UICore.IS_MOBILE = IS_MOBILE
UICore.SCALE_FACTOR = SCALE_FACTOR

-- Animation functions
UICore.createTween = createTween
UICore.fadeIn = fadeIn
UICore.fadeOut = fadeOut
UICore.scaleObject = scaleObject
UICore.pulse = pulse
UICore.slide = slide
UICore.rotate = rotate
UICore.colorShift = colorShift
UICore.scaleSize = scaleSize

-- UI builders
UICore.createCorner = createCorner
UICore.createStroke = createStroke
UICore.createPadding = createPadding
UICore.createVerticalLayout = createVerticalLayout
UICore.createHorizontalLayout = createHorizontalLayout
UICore.createGridLayout = createGridLayout
UICore.createGradient = createGradient

-- Device helpers
UICore.detectDevice = detectDevice
UICore.getScaleFactor = function() return SCALE_FACTOR end
UICore.getIsMobile = function() return IS_MOBILE end

-- Settings access
UICore.getSettings = function() return G.UILibrarySettings end
UICore.updateSettings = function(key, value)
    if G.UILibrarySettings then
        G.UILibrarySettings[key] = value
    end
end

-- Store in global for other modules
if not G.UICore then
    G.UICore = UICore
end

return UICore
