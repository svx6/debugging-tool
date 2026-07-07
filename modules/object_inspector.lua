--[[
    ========================================================================
    ULTIMATE ROBLOX AUTO-DEBUGGER  ·  OBJECT INSPECTOR  (v8)
    ========================================================================
    A click-to-inspect tool that works exactly like Roblox Studio's
    "Select" mode but in-game via the executor.

    Features:
      · Enable/disable via GUI toggle button or Data.Inspector.Enabled
      · Visual crosshair cursor overlay when active
      · Hover highlight: outlines hovered parts with a SelectionBox
      · Click any 3D object → show full info panel in the GUI
      · Click any GUI element → show GUI ancestry + properties
      · Inspection includes:
          - Class, Name, FullPath, Parent chain
          - All readable properties (Position, Size, CFrame, Color…)
          - All Attributes
          - Children list (with class icons)
          - Scripts inside (if any)
          - Custom tags (CollectionService)
          - AI diagnosis: what's wrong with this object
      · Works on PC (mouse) and Mobile (touch tap)
      · Crosshair cursor is a visual overlay (not a real mouse icon)
    ========================================================================
--]]

local Data = getgenv().DebuggerSharedData
if not Data then warn("[Inspector v8]: Core not loaded.") return end

local Players        = game:GetService("Players")
local UIS            = game:GetService("UserInputService")
local RunService     = game:GetService("RunService")
local CollSvc        = game:GetService("CollectionService")
local TweenSvc       = game:GetService("TweenService")
local LP             = Players.LocalPlayer

-- ── Inspector State ───────────────────────────────────────────────────────
Data.Inspector = Data.Inspector or {
    Enabled       = false,
    LastObject    = nil,   -- last inspected Instance
    History       = {},    -- last 20 inspected objects (path strings)
    Inspecting    = false, -- true while hover loop is running
}
local INS = Data.Inspector

-- ── SelectionBox overlay for hover highlight ──────────────────────────────
local selectionBox = nil
local function ensureSelBox()
    if selectionBox and selectionBox.Parent then return selectionBox end
    selectionBox = Instance.new("SelectionBox")
    selectionBox.Color3          = Color3.fromRGB(90, 130, 255)
    selectionBox.LineThickness   = 0.08
    selectionBox.SurfaceTransparency = 0.85
    selectionBox.SurfaceColor3   = Color3.fromRGB(90, 130, 255)
    selectionBox.Parent          = workspace
    return selectionBox
end

local function clearSelBox()
    if selectionBox then selectionBox.Adornee = nil end
end

-- ── Property reader — gets ALL readable properties safely ─────────────────
local PROP_LISTS = {
    BasePart = {
        "Position","Size","CFrame","Anchored","CanCollide","CanTouch",
        "Transparency","Reflectance","CastShadow","Massless",
        "Material","Color","BrickColor",
        "Velocity","RotVelocity","AssemblyLinearVelocity",
        "ClassName","Name","Parent",
    },
    Model = {
        "Name","ClassName","PrimaryPart",
        "ModelLOD","LevelOfDetail",
    },
    Humanoid = {
        "Health","MaxHealth","WalkSpeed","JumpPower","JumpHeight",
        "HipHeight","AutoRotate","DisplayName",
        "RigType","FloorMaterial","MoveDirection",
        "CameraOffset","NameDisplayDistance","HealthDisplayDistance",
    },
    Script = {"Name","ClassName","Disabled","RunContext"},
    LocalScript  = {"Name","ClassName","Disabled"},
    ModuleScript = {"Name","ClassName"},
    RemoteEvent  = {"Name","ClassName"},
    RemoteFunction = {"Name","ClassName"},
    ScreenGui    = {"Name","ResetOnSpawn","DisplayOrder","Enabled","IgnoreGuiInset"},
    Frame        = {"Name","BackgroundColor3","BackgroundTransparency","Visible","ZIndex","Size","Position"},
    TextLabel    = {"Name","Text","TextColor3","Font","TextSize","Visible","ZIndex"},
    TextButton   = {"Name","Text","TextColor3","Font","TextSize","Visible","Active"},
    ImageLabel   = {"Name","Image","ImageColor3","ImageTransparency","Visible"},
    Sound        = {"Name","SoundId","Volume","Pitch","Playing","Looped","RollOffMaxDistance"},
    Light        = {"Name","ClassName","Brightness","Color","Enabled","Range"},
}

local GENERIC_PROPS = {
    "Name","ClassName","Archivable",
}

local function readProps(inst)
    local results = {}
    local cls = inst.ClassName

    -- Try class-specific list first
    local propList = PROP_LISTS[cls]
    if propList then
        for _, p in ipairs(propList) do
            local ok, v = pcall(function() return inst[p] end)
            if ok and v ~= nil then
                local vstr = tostring(v)
                if #vstr > 80 then vstr = vstr:sub(1, 77) .. "..." end
                table.insert(results, {key = p, val = vstr})
            end
        end
    else
        -- Generic fallback
        for _, p in ipairs(GENERIC_PROPS) do
            local ok, v = pcall(function() return inst[p] end)
            if ok and v ~= nil then
                table.insert(results, {key = p, val = tostring(v):sub(1, 80)})
            end
        end
        -- Try common BasePart props on any part
        if inst:IsA("BasePart") then
            for _, p in ipairs(PROP_LISTS.BasePart) do
                local ok, v = pcall(function() return inst[p] end)
                if ok and v ~= nil then
                    table.insert(results, {key = p, val = tostring(v):sub(1, 80)})
                end
            end
        end
    end
    return results
end

-- ── Read attributes ────────────────────────────────────────────────────────
local function readAttributes(inst)
    local results = {}
    local ok, attrs = pcall(function() return inst:GetAttributes() end)
    if ok and attrs then
        for k, v in pairs(attrs) do
            table.insert(results, {key = k, val = tostring(v):sub(1, 80)})
        end
    end
    return results
end

-- ── Build parent chain ─────────────────────────────────────────────────────
local function getParentChain(inst)
    local chain = {}
    local cur = inst.Parent
    local depth = 0
    while cur and cur ~= game and depth < 12 do
        local ok, fn = pcall(function() return cur.Name .. " (" .. cur.ClassName .. ")" end)
        table.insert(chain, 1, ok and fn or "?")
        cur = cur.Parent
        depth = depth + 1
    end
    return chain
end

-- ── Children list (first 30) ───────────────────────────────────────────────
local CLASS_ICONS = {
    Script = "📜", LocalScript = "📜", ModuleScript = "📦",
    RemoteEvent = "📡", RemoteFunction = "🔁",
    Part = "🧱", MeshPart = "🧱", UnionOperation = "🧱",
    Model = "📐", Folder = "📁",
    ScreenGui = "🖥️", Frame = "▭", TextLabel = "🏷", TextButton = "🔘",
    Sound = "🔊", PointLight = "💡", SpotLight = "💡", SurfaceLight = "💡",
    Humanoid = "🧍", HumanoidRootPart = "⚙",
    Decal = "🖼", Texture = "🖼", SpecialMesh = "⬡",
    Weld = "🔗", WeldConstraint = "🔗", Motor6D = "⚙",
    Animation = "▶", AnimationController = "▶",
    BillboardGui = "🪧", SurfaceGui = "🪟",
    StringValue = "💬", IntValue = "🔢", NumberValue = "📊",
    BoolValue = "✅", ObjectValue = "🔶", CFrameValue = "📐",
    Fire = "🔥", Smoke = "💨", Sparkles = "✨",
    Explosion = "💥",
}
local function getChildIcon(cls) return CLASS_ICONS[cls] or "●" end

local function getChildrenList(inst)
    local list = {}
    local ok, ch = pcall(function() return inst:GetChildren() end)
    if ok and ch then
        for i, child in ipairs(ch) do
            if i > 30 then table.insert(list, "… +" .. (#ch - 30) .. " more"); break end
            local ok2, name = pcall(function() return child.Name end)
            local ok3, cls  = pcall(function() return child.ClassName end)
            table.insert(list, getChildIcon(ok3 and cls or "?") .. "  " .. (ok2 and name or "?") .. "  (" .. (ok3 and cls or "?") .. ")")
        end
    end
    return list
end

-- ── Get CollectionService tags ─────────────────────────────────────────────
local function getTags(inst)
    local ok, tags = pcall(function() return CollSvc:GetTags(inst) end)
    return (ok and tags) and tags or {}
end

-- ── Quick AI diagnosis for a single object ────────────────────────────────
local function diagnoseObject(inst)
    local issues = {}
    local cls = inst.ClassName

    -- BasePart checks
    if inst:IsA("BasePart") then
        local ok1, pos = pcall(function() return inst.Position end)
        if ok1 then
            if pos.Y < -500 then
                table.insert(issues, "⚠ Below world limit (Y=" .. math.floor(pos.Y) .. ") — physics leak")
            end
            if pos.X ~= pos.X or pos.Y ~= pos.Y or pos.Z ~= pos.Z then  -- NaN check
                table.insert(issues, "🔴 NaN position detected — corrupt physics state")
            end
            local huge = 1e300
            if math.abs(pos.X) > huge or math.abs(pos.Y) > huge or math.abs(pos.Z) > huge then
                table.insert(issues, "🔴 Infinite position — corrupt CFrame")
            end
        end
        local ok2, sz = pcall(function() return inst.Size end)
        if ok2 and (sz.X > 2048 or sz.Y > 2048 or sz.Z > 2048) then
            table.insert(issues, "⚠ Extremely large part (size > 2048) — render performance hit")
        end
        local ok3, anc = pcall(function() return inst.Anchored end)
        local ok4, col = pcall(function() return inst.CanCollide end)
        if ok3 and ok4 and not anc and not col then
            table.insert(issues, "⚠ Not anchored + CanCollide=false — likely noclip/ghost part")
        end
    end

    -- Script checks
    if inst:IsA("LuaSourceContainer") then
        local ok, disabled = pcall(function() return inst.Disabled end)
        if ok and disabled then
            table.insert(issues, "ℹ Script is disabled — may be a backdoor or unused code")
        end
        -- Count scripts with no parent check
        if inst.Parent == workspace then
            table.insert(issues, "⚠ Script directly in Workspace — unusual placement")
        end
    end

    -- Humanoid checks
    if cls == "Humanoid" then
        local ok1, ws = pcall(function() return inst.WalkSpeed end)
        if ok1 and ws > 36 then
            table.insert(issues, "🔴 WalkSpeed=" .. math.floor(ws) .. " — above normal (16)")
        end
        local ok2, hp = pcall(function() return inst.Health end)
        local ok3, mh = pcall(function() return inst.MaxHealth end)
        if ok2 and ok3 and mh > 0 and hp / mh > 1.01 then
            table.insert(issues, "🔴 Health exceeds MaxHealth — possible god mode")
        end
    end

    -- RemoteEvent/Function checks
    if inst:IsA("RemoteEvent") or inst:IsA("RemoteFunction") then
        local rec = Data.Remotes and Data.Remotes[inst:GetFullName()]
        if rec then
            if rec.CallRate and rec.CallRate > 20 then
                table.insert(issues, "🔴 Call rate: " .. rec.CallRate .. "/sec — rapid fire")
            end
            if rec.Blocked then
                table.insert(issues, "🚫 Currently blocked by AutoRemote")
            end
            table.insert(issues, "ℹ Called " .. (rec.Calls or 0) .. " times since monitoring started")
        end
    end

    if #issues == 0 then
        table.insert(issues, "✅ No obvious issues detected")
    end

    return issues
end

-- ── Full inspection data builder ───────────────────────────────────────────
local function buildInspection(inst)
    if not inst then return nil end
    local ok, fn = pcall(function() return inst:GetFullName() end)
    local fullPath = ok and fn or tostring(inst)

    -- Track in history
    table.insert(INS.History, 1, fullPath)
    while #INS.History > 20 do table.remove(INS.History) end

    INS.LastObject = inst

    local result = {
        Name        = inst.Name,
        ClassName   = inst.ClassName,
        FullPath    = fullPath,
        ParentChain = getParentChain(inst),
        Props       = readProps(inst),
        Attributes  = readAttributes(inst),
        Children    = getChildrenList(inst),
        Tags        = getTags(inst),
        Diagnosis   = diagnoseObject(inst),
        Time        = os.date("%H:%M:%S"),
    }

    -- Publish for GUI
    pcall(function() Data:Publish("OnObjectInspected", result) end)

    Data:ReportLog({
        Type = "Info",
        Text = string.format("[Inspector] Inspected: %s (%s)  —  %d issues",
            result.Name, result.ClassName, #result.Diagnosis),
    })

    return result
end

-- ── Mouse / Touch ray cast ─────────────────────────────────────────────────
local camera = workspace.CurrentCamera
local mouse  = LP:GetMouse()

local function getHoveredInstance()
    -- Use Mouse.Target for simplicity (works cross-executor)
    local ok, tgt = pcall(function() return mouse.Target end)
    return (ok and tgt) or nil
end

-- ── Hover loop (runs when inspector is enabled) ────────────────────────────
local hoverConn = nil
local lastHovered = nil

local function startHoverLoop()
    if hoverConn then return end  -- already running
    local sb = ensureSelBox()
    hoverConn = RunService.Heartbeat:Connect(function()
        if not INS.Enabled then
            clearSelBox()
            return
        end
        local hov = getHoveredInstance()
        if hov ~= lastHovered then
            lastHovered = hov
            if hov and hov:IsA("BasePart") then
                sb.Adornee = hov
            else
                sb.Adornee = nil
            end
        end
    end)
end

local function stopHoverLoop()
    if hoverConn then hoverConn:Disconnect(); hoverConn = nil end
    clearSelBox()
    lastHovered = nil
end

-- ── Click handler ─────────────────────────────────────────────────────────
local function onInspectorClick(inputType)
    if not INS.Enabled then return end

    -- Check if the mouse is over the debugger GUI
    local guiTarget = nil
    pcall(function()
        local guis = LP.PlayerGui:GetGuiObjectsAtPosition(mouse.X, mouse.Y)
        for _, g in ipairs(guis) do
            if g:FindFirstAncestorOfClass("ScreenGui") and
               g:FindFirstAncestorOfClass("ScreenGui").Name == "AutoDebuggerUI_v7" then
                guiTarget = g
                break
            end
        end
    end)

    if guiTarget then
        -- Inspecting a GUI element
        buildInspection(guiTarget)
        return
    end

    -- Inspect 3D object under cursor
    local hov = getHoveredInstance()
    if hov then
        buildInspection(hov)
    else
        -- Try ray from screen center
        pcall(function()
            local cam = workspace.CurrentCamera
            local unit = cam:ScreenPointToRay(mouse.X, mouse.Y, 0)
            local ray = Ray.new(unit.Origin, unit.Direction * 1000)
            local ignore = {LP.Character, workspace:FindFirstChild("AutoDebuggerUI_v7")}
            local hit = workspace:FindPartOnRayWithIgnoreList(ray, ignore)
            if hit then buildInspection(hit) end
        end)
    end
end

-- PC click
UIS.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if not INS.Enabled then return end
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        onInspectorClick("mouse")
    end
end)

-- Mobile touch
UIS.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if not INS.Enabled then return end
    if input.UserInputType == Enum.UserInputType.Touch then
        task.delay(0.05, function() onInspectorClick("touch") end)
    end
end)

-- ── Toggle API ────────────────────────────────────────────────────────────
Data.Inspector.Toggle = function(enabled)
    INS.Enabled = (enabled ~= nil) and enabled or (not INS.Enabled)
    if INS.Enabled then
        startHoverLoop()
        Data:ReportLog({Type="Info", Text="[Inspector] Enabled — click any object to inspect"})
        pcall(function() Data:Publish("OnInspectorToggled", true) end)
    else
        stopHoverLoop()
        clearSelBox()
        Data:ReportLog({Type="Info", Text="[Inspector] Disabled"})
        pcall(function() Data:Publish("OnInspectorToggled", false) end)
    end
end

-- ── Expose buildInspection for programmatic use ──────────────────────────
Data.Inspector.Inspect = buildInspection
Data.Inspector.DiagnoseObject = diagnoseObject

print("[Inspector v8]: Click-to-inspect active. Toggle via Data.Inspector.Toggle() or GUI button.")
