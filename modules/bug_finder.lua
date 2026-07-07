--[[
    ========================================================================
    ULTIMATE ROBLOX AUTO-DEBUGGER  ·  BUG FINDER  (v5)
    ========================================================================
    Smart detection rules:
      1. Broken joints / constraints
      2. Instance flood (exponential growth detector)
      3. Sound leaks + looping sounds with no parent Part
      4. Decal / Texture spam
      5. Script backdoors (extended virus DB + content scanning)
      6. Invisible brick traps (fully transparent + non-cancollide)
      7. ScreenGui / BillboardGui injection into PlayerGui
      8. RemoteEvent/Function count anomaly (>100 in one container)
      9. Model with no PrimaryPart (common NPC rig bug)
     10. Unreachable scripts (Disabled=true but still present in workspace)
    ========================================================================
--]]

local Data = getgenv().DebuggerSharedData
if not Data then warn("[Bug-Finder v6]: Core not loaded.") return end

local Players = game:GetService("Players")

-- ── Local helper (isPlayerDescendant) ────────────────────────────────────
local function isPlayerDescendant(part)
    local ok, res = pcall(function() return part:IsDescendantOf(Players) end)
    return ok and res
end

-- ────────────────────────────────────────────────────────────────────────────
-- 1. BROKEN JOINTS / CONSTRAINTS
-- ────────────────────────────────────────────────────────────────────────────
local function scanJoints()
    for _, item in ipairs(workspace:GetDescendants()) do
        pcall(function()
            if item:IsA("JointInstance") or item:IsA("Constraint") then
                local p0 = item:FindFirstChild("Part0") ~= nil
                -- Read properties safely
                local okP0, valP0 = pcall(function() return item.Part0 end)
                local okP1, valP1 = pcall(function() return item.Part1 end)
                if not (okP0 and valP0) or not (okP1 and valP1) then
                    Data:ReportBug({
                        Type        = "Broken Joint",
                        Source      = item:GetFullName(),
                        Description = string.format("%s (%s) has nil Part0/Part1. Physics instability risk.", item.Name, item.ClassName),
                        Severity    = "Low",
                    })
                end
            end
        end)
    end
end

-- ────────────────────────────────────────────────────────────────────────────
-- 2. INSTANCE FLOOD — exponential growth heuristic
--    Track count across successive scans; alert if growth rate > 2×
-- ────────────────────────────────────────────────────────────────────────────
local prevTotalCount = 0
local function scanInstanceFlood()
    local currentCount = Data.Stats.InstanceCount
    if prevTotalCount > 500 then   -- only check when game is "loaded"
        local ratio = currentCount / math.max(prevTotalCount, 1)
        if ratio > 2.5 then   -- doubled in one scan cycle
            Data:ReportBug({
                Type        = "Instance Flood",
                Source      = "Game::InstanceTree",
                Description = string.format("Instance count jumped from %d → %d (×%.1f growth). Possible infinite clone/spawn loop.", prevTotalCount, currentCount, ratio),
                Severity    = "High",
            })
        end
    end
    prevTotalCount = currentCount

    -- Name-based duplicate flood (original check, raised threshold)
    local counts = {}
    for _, item in ipairs(game:GetDescendants()) do
        pcall(function()
            counts[item.Name] = (counts[item.Name] or 0) + 1
        end)
    end
    for name, count in pairs(counts) do
        if count > 300 and name ~= "" and name ~= "Workspace" then
            Data:ReportBug({
                Type        = "Duplicate Name Flood",
                Source      = "Hierarchy::"..name,
                Description = string.format("'%s' appears %d times. Likely infinite spawn/clone.", name, count),
                Severity    = "High",
            })
        end
    end
end

-- ────────────────────────────────────────────────────────────────────────────
-- 3. SOUND LEAKS
-- ────────────────────────────────────────────────────────────────────────────
local function scanSoundLeaks()
    for _, item in ipairs(workspace:GetDescendants()) do
        pcall(function()
            if not item:IsA("Sound") then return end
            -- Playing directly in workspace root
            if item.Playing and item.Parent == workspace then
                Data:ReportBug({
                    Type        = "Sound: Workspace Leak",
                    Source      = item:GetFullName(),
                    Description = "Sound is playing at workspace root instead of a Part/Attachment. Bypasses 3D attenuation and wastes audio channels.",
                    Severity    = "Low",
                })
            end
            -- Orphaned looping sound with no valid parent (parent is a service, not a part)
            if item.Looped and item.Playing and not item.Parent:IsA("BasePart") and not item.Parent:IsA("Attachment") then
                Data:ReportBug({
                    Type        = "Sound: Looping Orphan",
                    Source      = item:GetFullName(),
                    Description = "Looping sound parented to a non-spatial object ("..item.Parent.ClassName.."). Will play forever and leak audio memory.",
                    Severity    = "Medium",
                })
            end
        end)
    end
end

-- ────────────────────────────────────────────────────────────────────────────
-- 4. DECAL / TEXTURE SPAM
-- ────────────────────────────────────────────────────────────────────────────
local function scanDecalSpam()
    for _, item in ipairs(workspace:GetDescendants()) do
        pcall(function()
            if not item:IsA("BasePart") then return end
            local n = 0
            for _, child in ipairs(item:GetChildren()) do
                if child:IsA("Decal") or child:IsA("Texture") then n = n + 1 end
            end
            if n > 5 then
                Data:ReportBug({
                    Type        = "Decal Spam",
                    Source      = item:GetFullName(),
                    Description = string.format("Part holds %d decals/textures (>5 threshold). Excessive GPU texture calls.", n),
                    Severity    = "Medium",
                })
            end
        end)
    end
end

-- ────────────────────────────────────────────────────────────────────────────
-- 5. BACKDOOR / VIRUS DETECTION  (extended DB + source content scanning)
-- ────────────────────────────────────────────────────────────────────────────
local SUSPECT_SERVICES = {"JointsService", "TestService", "InsertService"}
local VIRUS_NAME_PATTERNS = {
    "VACCINE", "FIXLAG", "BACKDOOR", "SERVERSTEALER",
    "DARKDEX", "DEXPLORER", "EXPLOIT", "VEINJECT",
    "FREEADMIN", "CMDR", "NANOBYTE", "ADONIS_LOADER",
}
local DANGER_SOURCE_PATTERNS = {
    "require%s*%(%s*%d+",   -- require(assetId)
    "loadstring%s*%(",       -- loadstring(
    "getfenv%s*%(",          -- getfenv(
    "setfenv%s*%(",          -- setfenv(
    "game%.HttpGet",         -- HTTP data fetch
    "HttpService:Get",
}

local function isVirusName(name)
    local u = name:upper()
    for _, pat in ipairs(VIRUS_NAME_PATTERNS) do
        if u:find(pat, 1, true) then return true, pat end
    end
    return false
end

local function hasDangerousSource(script)
    -- Try reading script source (only works on LocalScripts in executor context)
    local ok, src = pcall(function() return script.Source end)
    if not ok or type(src) ~= "string" or #src == 0 then return false end
    local srcLow = src:lower()
    for _, pat in ipairs(DANGER_SOURCE_PATTERNS) do
        if srcLow:find(pat) then return true, pat end
    end
    return false
end

local function scanBackdoors()
    -- Hidden scripts in restricted services
    for _, svcName in ipairs(SUSPECT_SERVICES) do
        pcall(function()
            local svc = game:GetService(svcName)
            for _, child in ipairs(svc:GetDescendants()) do
                if child:IsA("LuaSourceContainer") then
                    Data:ReportBug({
                        Type        = "Backdoor: Hidden Script",
                        Source      = child:GetFullName(),
                        Description = string.format("Script found inside restricted service '%s'. Strongly indicates a backdoor.", svcName),
                        Severity    = "High",
                    })
                end
            end
        end)
    end

    -- Virus pattern scan across common containers
    local roots = {}
    for _, svcName in ipairs({"ReplicatedStorage","StarterPack","StarterPlayerScripts","StarterGui"}) do
        pcall(function() table.insert(roots, game:GetService(svcName)) end)
    end
    table.insert(roots, workspace)

    for _, root in ipairs(roots) do
        pcall(function()
            for _, child in ipairs(root:GetDescendants()) do
                if child:IsA("LuaSourceContainer") then
                    local isVirus, pat = isVirusName(child.Name)
                    if isVirus then
                        Data:ReportBug({
                            Type        = "Backdoor: Virus Signature",
                            Source      = child:GetFullName(),
                            Description = string.format("Script name matches virus signature '%s'.", pat),
                            Severity    = "High",
                        })
                    end
                    -- Source-level heuristics
                    local isDangerous, dangPat = hasDangerousSource(child)
                    if isDangerous then
                        Data:ReportBug({
                            Type        = "Backdoor: Dangerous Code Pattern",
                            Source      = child:GetFullName(),
                            Description = string.format("Script source contains suspicious pattern: `%s`. Review immediately.", dangPat),
                            Severity    = "High",
                        })
                    end
                end
            end
        end)
    end
end

-- ────────────────────────────────────────────────────────────────────────────
-- 6. INVISIBLE BRICK TRAPS
--    Fully transparent, non-cancollide parts can be used to freeze or glitch players
-- ────────────────────────────────────────────────────────────────────────────
local function scanInvisibleTraps()
    for _, part in ipairs(workspace:GetDescendants()) do
        pcall(function()
            if not part:IsA("BasePart") then return end
            if part.Transparency == 1 and not part.CanCollide and not isPlayerDescendant(part) then
                Data:ReportBug({
                    Type        = "Invisible Trap Part",
                    Source      = part:GetFullName(),
                    Description = "Part is fully transparent AND CanCollide=false. Common pattern for invisible kill bricks or trigger zones that can trap players.",
                    Severity    = "Low",
                })
            end
        end)
    end
end

-- ────────────────────────────────────────────────────────────────────────────
-- 7. GUI INJECTION  (foreign ScreenGuis in PlayerGui)
-- ────────────────────────────────────────────────────────────────────────────
local KNOWN_GUI_NAMES = {"AutoDebuggerUI"}  -- our own GUIs are safe
local function scanGuiInjection()
    local lp = Players.LocalPlayer
    if not lp then return end
    local pg = lp:FindFirstChildOfClass("PlayerGui")
    if not pg then return end
    for _, child in ipairs(pg:GetChildren()) do
        pcall(function()
            if child:IsA("ScreenGui") then
                local known = false
                for _, n in ipairs(KNOWN_GUI_NAMES) do
                    if child.Name == n then known = true; break end
                end
                -- Flag if it has no children or has a suspicious name
                if not known then
                    local upper = child.Name:upper()
                    if upper:find("EXPLOIT") or upper:find("HUB") or upper:find("HACK") or upper:find("CHEAT") then
                        Data:ReportBug({
                            Type        = "GUI Injection",
                            Source      = child:GetFullName(),
                            Description = "Suspicious ScreenGui detected in PlayerGui. Name matches exploit UI pattern.",
                            Severity    = "High",
                        })
                    end
                end
            end
        end)
    end
end

-- ────────────────────────────────────────────────────────────────────────────
-- 8. REMOTE FLOOD in single container (>100 remotes in one folder)
-- ────────────────────────────────────────────────────────────────────────────
local function scanRemoteFlood()
    local function countRemotes(container)
        local count = 0
        pcall(function()
            for _, child in ipairs(container:GetChildren()) do
                if child:IsA("RemoteEvent") or child:IsA("RemoteFunction") then
                    count = count + 1
                end
            end
        end)
        return count
    end

    local function checkContainer(container)
        local n = countRemotes(container)
        if n > 100 then
            Data:ReportBug({
                Type        = "Remote Flood",
                Source      = container:GetFullName(),
                Description = string.format("Container holds %d RemoteEvents/Functions. Extremely high counts slow replication and may be generated by exploit tooling.", n),
                Severity    = "Medium",
            })
        end
    end

    pcall(function() checkContainer(game:GetService("ReplicatedStorage")) end)
    for _, child in ipairs(game:GetService("ReplicatedStorage"):GetChildren()) do
        pcall(checkContainer, child)
    end
end

-- ────────────────────────────────────────────────────────────────────────────
-- 9. MODEL WITH NO PRIMARY PART
-- ────────────────────────────────────────────────────────────────────────────
local function scanMissingPrimaryParts()
    for _, item in ipairs(workspace:GetDescendants()) do
        pcall(function()
            if item:IsA("Model") and item.PrimaryPart == nil then
                -- Only flag models that look like NPCs/characters (have a Humanoid)
                if item:FindFirstChildOfClass("Humanoid") then
                    Data:ReportBug({
                        Type        = "Missing PrimaryPart",
                        Source      = item:GetFullName(),
                        Description = "Model has a Humanoid but no PrimaryPart set. MoveTo/GetPivot calls will error or behave unexpectedly.",
                        Severity    = "Low",
                    })
                end
            end
        end)
    end
end

-- ────────────────────────────────────────────────────────────────────────────
-- 10. DISABLED SCRIPTS IN WORKSPACE (dead code risk / hidden trigger)
-- ────────────────────────────────────────────────────────────────────────────
local function scanDisabledScripts()
    for _, item in ipairs(workspace:GetDescendants()) do
        pcall(function()
            if (item:IsA("Script") or item:IsA("LocalScript")) and item.Disabled == true then
                Data:ReportBug({
                    Type        = "Disabled Script in Workspace",
                    Source      = item:GetFullName(),
                    Description = "Script is Disabled but still lives in Workspace. Could be a remnant exploit trigger waiting to be re-enabled via a backdoor.",
                    Severity    = "Low",
                })
            end
        end)
    end
end

-- ── Master runner ─────────────────────────────────────────────────────────
local function runAll()
    scanJoints()
    scanInstanceFlood()
    scanSoundLeaks()
    scanDecalSpam()
    scanBackdoors()
    scanInvisibleTraps()
    scanGuiInjection()
    scanRemoteFlood()
    scanMissingPrimaryParts()
    scanDisabledScripts()
end

table.insert(getgenv().DebuggerScanners, runAll)
print("[Bug-Finder v5]: 10 detection rules loaded.")
