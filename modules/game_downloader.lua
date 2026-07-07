--[[
    ========================================================================
    ULTIMATE ROBLOX AUTO-DEBUGGER  ·  GAME DOWNLOADER  (v6)
    ========================================================================
    Author   : Antigravity
    Features :
      · Download the ENTIRE game hierarchy as Lua source files
      · Decompiles LocalScript / Script / ModuleScript sources
      · Serializes instances to human-readable Lua constructors
      · Organizes output by game service (ReplicatedStorage, Workspace, etc.)
      · Writes a manifest file listing all downloaded files
      · Progress reporting via Data events
      · Supports readfile/writefile executors (Synapse, Krnl, Wave, Codex)
      · Auto-creates folder structure matching game hierarchy
      · Download stats (file count, total size, time taken)
    ========================================================================
--]]

local Data = getgenv().DebuggerSharedData
if not Data then warn("[GameDownloader v6]: Core not loaded.") return end

-- ── Check if file I/O is available ────────────────────────────────────────
local function hasFileIO()
    return (typeof(writefile) == "function") and (typeof(makefolder) == "function")
end

-- ── Download State ────────────────────────────────────────────────────────
Data.Downloader = Data.Downloader or {
    Running    = false,
    Progress   = 0,
    Total      = 0,
    FileCount  = 0,
    TotalBytes = 0,
    StatusMsg  = "Ready",
    LastOutput = nil,  -- root folder name of last download
    Log        = {},
}

local DL = Data.Downloader

-- ── Utilities ─────────────────────────────────────────────────────────────
local function sanitizeName(name)
    -- Remove characters not safe for file/folder names
    name = tostring(name or "Unknown")
    name = name:gsub('[/\\:*?"<>|]', "_")
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    if #name == 0 then name = "Unnamed" end
    if #name > 60 then name = name:sub(1, 60) end
    return name
end

local function dlLog(msg)
    table.insert(DL.Log, 1, "[" .. os.date("%H:%M:%S") .. "] " .. msg)
    while #DL.Log > 100 do table.remove(DL.Log) end
    Data:Publish("OnDownloaderLog", msg)
end

local function ensureFolder(path)
    pcall(function()
        if isfolder and not isfolder(path) then
            makefolder(path)
        elseif not isfolder then
            -- Some executors don't have isfolder, just try creating
            makefolder(path)
        end
    end)
end

-- ── Lua Source Serializer ─────────────────────────────────────────────────
-- Converts an Instance + its children to a human-readable Lua file
local function serializeValue(v)
    local t = typeof(v)
    if t == "string"  then return string.format("%q", v:sub(1, 500)) end
    if t == "number"  then return tostring(v) end
    if t == "boolean" then return tostring(v) end
    if t == "nil"     then return "nil" end
    if t == "Vector3" then return string.format("Vector3.new(%s, %s, %s)", v.X, v.Y, v.Z) end
    if t == "Vector2" then return string.format("Vector2.new(%s, %s)", v.X, v.Y) end
    if t == "CFrame"  then
        local p = v.Position
        local rx, ry, rz = v:ToEulerAnglesYXZ()
        return string.format("CFrame.new(%s,%s,%s) * CFrame.Angles(%s,%s,%s)", p.X,p.Y,p.Z, rx,ry,rz)
    end
    if t == "Color3"  then return string.format("Color3.fromRGB(%d,%d,%d)", math.floor(v.R*255), math.floor(v.G*255), math.floor(v.B*255)) end
    if t == "BrickColor" then return string.format("BrickColor.new(%q)", v.Name) end
    if t == "UDim2"   then return string.format("UDim2.new(%s,%s,%s,%s)", v.X.Scale, v.X.Offset, v.Y.Scale, v.Y.Offset) end
    if t == "UDim"    then return string.format("UDim.new(%s,%s)", v.Scale, v.Offset) end
    if t == "EnumItem" then return "Enum." .. tostring(v.EnumType) .. "." .. v.Name end
    if t == "Instance" then
        local ok, fp = pcall(function() return v:GetFullName() end)
        return ok and ("game:GetService(\"" .. v.ClassName .. "\") --[[ " .. fp .. " ]]") or "nil --[[destroyed]]"
    end
    return "nil --[[" .. t .. "]]"
end

-- Properties to skip (read-only, deprecated, or non-serializable)
local SKIP_PROPS = {
    "AbsolutePosition","AbsoluteSize","AbsoluteRotation","AbsoluteContentSize",
    "ContentSize","ExtentsOffset","ExtentsOffsetWorldSpace","SizeInStuds",
    "TextBounds","DataCost","Handle","SelectionBox","LocalizationTable",
    "RootLocalizationTable","AnimationTrack",
}
local skipSet = {}
for _, p in ipairs(SKIP_PROPS) do skipSet[p] = true end

local function instanceToLua(inst, indent)
    indent = indent or 0
    local pad = string.rep("    ", indent)
    local lines = {}

    local className = inst.ClassName
    local name = inst.Name
    local varName = sanitizeName(name):gsub("[^%w]", "_"):lower()
    if varName:match("^%d") then varName = "_" .. varName end

    table.insert(lines, pad .. "-- " .. string.rep("─", 60))
    table.insert(lines, pad .. string.format("-- [%s] %s", className, name))
    table.insert(lines, pad .. "-- " .. string.rep("─", 60))
    table.insert(lines, pad .. string.format("local %s = Instance.new(%q)", varName, className))

    -- Serialize notable properties
    local writtenProps = {}
    local safeProps = {
        "Name","Value","Text","Source","Disabled","Visible","ZIndex",
        "Position","Size","BackgroundColor3","TextColor3","Font","TextSize",
        "BackgroundTransparency","TextTransparency","BorderSizePixel",
        "AnchorPoint","LayoutOrder","AutomaticSize","ClipsDescendants",
        "Active","Draggable","Selectable","ResetOnSpawn","IgnoreGuiInset",
        "Archivable","Transparency","Reflectance","Material","BrickColor",
        "Color","Anchored","CanCollide","CastShadow","Locked","Massless",
        "CFrame","PivotOffset","Size","Shape","TopSurface","BottomSurface",
        "LeftSurface","RightSurface","FrontSurface","BackSurface",
        "Enabled","MaxActivationDistance","RequiresLineOfSight",
        "SoundId","Volume","Pitch","Looped","PlayOnRemove",
        "Image","ImageColor3","ImageTransparency","ScaleType","TileSize",
        "AnimationId","Priority","Speed","Weight",
    }

    for _, prop in ipairs(safeProps) do
        if not skipSet[prop] and not writtenProps[prop] then
            pcall(function()
                local val = inst[prop]
                if val ~= nil then
                    -- Don't serialize default Name if same as ClassName
                    if prop == "Name" and val == className then return end
                    local serialized = serializeValue(val)
                    table.insert(lines, pad .. string.format("%s.%s = %s", varName, prop, serialized))
                    writtenProps[prop] = true
                end
            end)
        end
    end

    -- Script source
    if inst:IsA("LuaSourceContainer") then
        local ok, src = pcall(function() return inst.Source end)
        if ok and type(src) == "string" and #src > 0 then
            table.insert(lines, pad .. "-- [SOURCE] --")
            table.insert(lines, pad .. "--[=[")
            -- Indent source
            for srcLine in (src .. "\n"):gmatch("([^\n]*)\n") do
                table.insert(lines, pad .. srcLine)
            end
            table.insert(lines, pad .. "]=]")
        end
    end

    table.insert(lines, pad .. string.format("%s.Parent = parent", varName))
    table.insert(lines, "")

    -- Children
    local children = {}
    pcall(function() children = inst:GetChildren() end)
    if #children > 0 then
        table.insert(lines, pad .. "do -- children of " .. name)
        table.insert(lines, pad .. "    local parent = " .. varName)
        for _, child in ipairs(children) do
            pcall(function()
                local childLines = instanceToLua(child, indent + 1)
                for _, l in ipairs(childLines) do
                    table.insert(lines, l)
                end
            end)
        end
        table.insert(lines, pad .. "end")
        table.insert(lines, "")
    end

    return lines
end

-- ── Services to Download ──────────────────────────────────────────────────
local TARGET_SERVICES = {
    "Workspace",
    "ReplicatedStorage",
    "ReplicatedFirst",
    "StarterGui",
    "StarterPack",
    "StarterPlayer",
    "ServerScriptService",
    "ServerStorage",
    "Teams",
    "SoundService",
    "Lighting",
    "MaterialService",
}

-- ── Main Download Function ─────────────────────────────────────────────────
local function downloadGame()
    if DL.Running then
        dlLog("Download already in progress!")
        return false
    end

    if not hasFileIO() then
        dlLog("ERROR: writefile/makefolder not available on this executor. Use Synapse, Krnl, or Wave.")
        Data:ReportLog({
            Type = "Error",
            Text = "[GameDownloader] No file I/O available. Cannot download.",
        })
        return false
    end

    DL.Running    = true
    DL.Progress   = 0
    DL.Total      = 0
    DL.FileCount  = 0
    DL.TotalBytes = 0
    DL.Log        = {}

    local gameName = sanitizeName(game.Name or "RobloxGame")
    local timestamp = os.date("%Y%m%d_%H%M%S")
    local rootFolder = "DebuggerDownload_" .. gameName .. "_" .. timestamp

    DL.LastOutput = rootFolder
    DL.StatusMsg  = "Initializing..."
    Data:Publish("OnDownloaderProgress", DL)

    local startTime = os.clock()

    -- Create root
    pcall(makefolder, rootFolder)
    dlLog("Created root folder: " .. rootFolder)

    -- Manifest
    local manifest = {
        "-- ================================================================",
        "-- ROBLOX GAME DOWNLOAD MANIFEST",
        "-- Generated by: Antigravity Auto-Debugger v6",
        "-- Game: " .. tostring(game.Name),
        "-- Place ID: " .. tostring(game.PlaceId),
        "-- Job ID: " .. tostring(game.JobId),
        "-- Downloaded: " .. os.date("%Y-%m-%d %H:%M:%S"),
        "-- ================================================================",
        "",
    }

    -- Count total work
    local allItems = {}
    for _, svcName in ipairs(TARGET_SERVICES) do
        pcall(function()
            local svc = game:GetService(svcName)
            for _, desc in ipairs(svc:GetDescendants()) do
                if desc:IsA("LuaSourceContainer") then
                    table.insert(allItems, {svc = svcName, inst = desc})
                end
            end
        end)
    end
    DL.Total = math.max(1, #allItems + #TARGET_SERVICES)
    dlLog(string.format("Found %d script instances across %d services.", #allItems, #TARGET_SERVICES))

    local processed = 0

    -- Process each service
    for _, svcName in ipairs(TARGET_SERVICES) do
        task.wait()  -- yield between services
        pcall(function()
            local svc = game:GetService(svcName)
            local svcFolder = rootFolder .. "/" .. svcName
            ensureFolder(svcFolder)

            DL.StatusMsg = "Downloading " .. svcName .. "..."
            Data:Publish("OnDownloaderProgress", DL)
            dlLog("Processing: " .. svcName)

            -- Write service overview
            local overviewLines = {
                string.format("-- ================================================================"),
                string.format("-- SERVICE: %s", svcName),
                string.format("-- Children: %d, Descendants: %d", #svc:GetChildren(), #svc:GetDescendants()),
                string.format("-- ================================================================"),
                "",
                "local parent = game:GetService(" .. string.format("%q", svcName) .. ")",
                "",
            }

            -- Serialize all children
            for _, child in ipairs(svc:GetChildren()) do
                task.wait()
                pcall(function()
                    local childLines = instanceToLua(child, 0)
                    for _, l in ipairs(childLines) do
                        table.insert(overviewLines, l)
                    end
                end)
            end

            local overviewContent = table.concat(overviewLines, "\n")
            local overviewFile = svcFolder .. "/" .. svcName .. "_overview.lua"
            pcall(writefile, overviewFile, overviewContent)
            DL.FileCount = DL.FileCount + 1
            DL.TotalBytes = DL.TotalBytes + #overviewContent
            table.insert(manifest, "SERVICE: " .. svcName .. " → " .. overviewFile)

            -- Individual script files
            for _, desc in ipairs(svc:GetDescendants()) do
                task.wait()
                pcall(function()
                    if desc:IsA("LuaSourceContainer") then
                        processed = processed + 1
                        DL.Progress = math.floor((processed / DL.Total) * 100)
                        Data:Publish("OnDownloaderProgress", DL)

                        -- Build folder path matching hierarchy
                        local pathParts = {}
                        local cur = desc.Parent
                        while cur and cur ~= svc do
                            table.insert(pathParts, 1, sanitizeName(cur.Name))
                            cur = cur.Parent
                        end

                        local folderPath = svcFolder
                        for _, part in ipairs(pathParts) do
                            folderPath = folderPath .. "/" .. part
                            ensureFolder(folderPath)
                        end

                        local ext = ".lua"
                        if desc:IsA("ModuleScript") then ext = "_module.lua"
                        elseif desc:IsA("LocalScript") then ext = "_local.lua"
                        elseif desc:IsA("Script") then ext = "_server.lua" end

                        local fileName = folderPath .. "/" .. sanitizeName(desc.Name) .. ext

                        -- Get source
                        local ok, src = pcall(function() return desc.Source end)
                        if not ok or type(src) ~= "string" then
                            src = "-- Source not accessible (server-side script)\n-- Path: " .. desc:GetFullName()
                        end

                        -- Build file content
                        local lineCount = 0
                        for _ in src:gmatch("\n") do lineCount = lineCount + 1 end
                        local content = table.concat({
                            "-- ================================================================",
                            "-- Script: " .. desc.Name,
                            "-- Class:  " .. desc.ClassName,
                            "-- Path:   " .. desc:GetFullName(),
                            "-- Lines:  " .. tostring(lineCount + 1),
                            "-- ================================================================",
                            "",
                            src,
                        }, "\n")

                        local writeOk, writeErr = pcall(writefile, fileName, content)
                        if writeOk then
                            DL.FileCount = DL.FileCount + 1
                            DL.TotalBytes = DL.TotalBytes + #content
                            table.insert(manifest, string.format("  SCRIPT [%s]: %s → %s", desc.ClassName, desc:GetFullName(), fileName))
                            dlLog(string.format("  ✓ %s (%d chars)", desc:GetFullName(), #content))
                        else
                            dlLog(string.format("  ✗ Failed to write %s: %s", desc:GetFullName(), tostring(writeErr)))
                        end
                    end
                end)
            end

            processed = processed + 1
            DL.Progress = math.floor((processed / DL.Total) * 100)
        end)
    end

    -- Write manifest
    local manifestContent = table.concat(manifest, "\n") .. "\n\n-- Total Files: " .. DL.FileCount .. "\n-- Total Size: " .. math.floor(DL.TotalBytes / 1024) .. " KB\n"
    pcall(writefile, rootFolder .. "/MANIFEST.txt", manifestContent)
    DL.FileCount = DL.FileCount + 1

    -- Done
    local elapsed = os.clock() - startTime
    DL.Progress = 100
    DL.Running  = false
    DL.StatusMsg = string.format("Done! %d files, %.1f KB, %.1fs", DL.FileCount, DL.TotalBytes / 1024, elapsed)
    Data:Publish("OnDownloaderProgress", DL)
    Data:Publish("OnDownloaderComplete", DL)

    dlLog(string.format("Download complete! Folder: %s | Files: %d | Size: %.1f KB | Time: %.1fs", rootFolder, DL.FileCount, DL.TotalBytes / 1024, elapsed))
    Data:ReportLog({
        Type = "Info",
        Text = string.format("[GameDownloader] Complete! %d files → '%s'", DL.FileCount, rootFolder),
    })

    return true
end

-- ── Quick Script-Only Download ────────────────────────────────────────────
local function downloadScriptsOnly()
    if DL.Running then return false end
    if not hasFileIO() then
        dlLog("ERROR: No file I/O available.")
        return false
    end

    DL.Running   = true
    DL.StatusMsg = "Downloading scripts only..."
    DL.Progress  = 0
    DL.FileCount = 0
    DL.TotalBytes = 0
    Data:Publish("OnDownloaderProgress", DL)

    local gameName = sanitizeName(game.Name or "RobloxGame")
    local rootFolder = "Scripts_" .. gameName .. "_" .. os.date("%Y%m%d_%H%M%S")
    DL.LastOutput = rootFolder
    pcall(makefolder, rootFolder)

    local scripts = {}
    for _, inst in ipairs(game:GetDescendants()) do
        pcall(function()
            if inst:IsA("LuaSourceContainer") then
                table.insert(scripts, inst)
            end
        end)
    end

    DL.Total = #scripts
    dlLog(string.format("Found %d scripts total.", #scripts))

    for i, sc in ipairs(scripts) do
        task.wait()
        pcall(function()
            DL.Progress = math.floor(i / DL.Total * 100)
            Data:Publish("OnDownloaderProgress", DL)

            local ok, src = pcall(function() return sc.Source end)
            if not ok or type(src) ~= "string" then
                src = "-- Source not readable\n"
            end

            local safeFP = sc:GetFullName():gsub("[%.%[%]]", "_")
            local ext = sc:IsA("ModuleScript") and "_mod.lua" or sc:IsA("LocalScript") and "_local.lua" or "_srv.lua"
            local fname = rootFolder .. "/" .. safeFP .. ext

            local content = "-- Path: " .. sc:GetFullName() .. "\n-- Class: " .. sc.ClassName .. "\n\n" .. src
            pcall(writefile, fname, content)
            DL.FileCount = DL.FileCount + 1
            DL.TotalBytes = DL.TotalBytes + #content
        end)
    end

    DL.Progress  = 100
    DL.Running   = false
    DL.StatusMsg = string.format("Scripts done! %d files in '%s'", DL.FileCount, rootFolder)
    Data:Publish("OnDownloaderProgress", DL)
    Data:Publish("OnDownloaderComplete", DL)
    dlLog(DL.StatusMsg)
    return true
end

-- ── Export to Data ─────────────────────────────────────────────────────────
Data.DownloadGame        = downloadGame
Data.DownloadScriptsOnly = downloadScriptsOnly
Data.HasFileIO           = hasFileIO

print(string.format("[GameDownloader v6]: Ready. File I/O available: %s", tostring(hasFileIO())))
