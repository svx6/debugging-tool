--[[
    ========================================================================
    ULTIMATE ROBLOX AUTO-DEBUGGER  ·  AUTO-HEALER  (v5)
    ========================================================================
    Detects AND heals:
      · Parts below -500 Y (physics leaks)
      · Massively oversized parts (scale exploits / lag traps)
      · NaN / Inf position corrupted parts
      · Anchored parts infinitely buried underground (< -2000 Y)
      · Character root-part teleports (fall-through floor detection)
    ========================================================================
--]]

local Data    = getgenv().DebuggerSharedData
if not Data then warn("[Auto-Healer]: Core not loaded.") return end

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")

-- ── Helpers ───────────────────────────────────────────────────────────────
local function safeFullName(inst)
    local ok, n = pcall(function() return inst:GetFullName() end)
    return ok and n or tostring(inst)
end

local function isPlayerDescendant(part)
    local ok, res = pcall(function() return part:IsDescendantOf(Players) end)
    return ok and res
end

local function isAnchored(part)
    local ok, a = pcall(function() return part.Anchored end)
    return ok and a
end

local function getPosition(part)
    local ok, pos = pcall(function() return part.Position end)
    if not ok then return nil end
    return pos
end

-- ── Rule 1: Parts fallen below world limit ────────────────────────────────
local function checkFallenPart(part)
    if not part:IsA("BasePart") then return end
    if isPlayerDescendant(part) then return end

    local pos = getPosition(part)
    if not pos then return end

    -- NaN / Inf position — corrupt physics state
    if pos.X ~= pos.X or pos.Y ~= pos.Y or pos.Z ~= pos.Z or
       math.abs(pos.X) == math.huge or math.abs(pos.Y) == math.huge then
        local path = safeFullName(part)
        if Data.Settings.AutoClean then
            pcall(function() part:Destroy() end)
            Data.Stats.AutoHealCount = Data.Stats.AutoHealCount + 1
            Data:ReportLog({ Type="Info", Text="[Healer] Destroyed NaN-position part: "..path })
        else
            Data:ReportBug({
                Type        = "NaN Position",
                Source      = path,
                Description = "Part has an invalid (NaN/Inf) position. Will corrupt physics simulation.",
                Severity    = "High",
            })
        end
        return
    end

    -- Fallen below -500 Y
    if pos.Y < -500 and not isAnchored(part) then
        local path = safeFullName(part)
        if Data.Settings.AutoClean then
            pcall(function() part:Destroy() end)
            Data.Stats.AutoHealCount = Data.Stats.AutoHealCount + 1
            Data:ReportLog({ Type="Info", Text="[Healer] Cleaned physics leak: "..path })
        else
            Data:ReportBug({
                Type        = "Physics Leak",
                Source      = path,
                Description = string.format("Unanchored part at Y=%.1f (below -500). Toggle Auto-Resolve to destroy.", pos.Y),
                Severity    = "Medium",
            })
        end
        return
    end

    -- Anchored but buried extremely deep (> -2000 Y) — likely an unintentional placement
    if pos.Y < -2000 and isAnchored(part) then
        Data:ReportBug({
            Type        = "Buried Anchored Part",
            Source      = safeFullName(part),
            Description = string.format("Anchored part exists at Y=%.1f — extremely far below map. May indicate placement error.", pos.Y),
            Severity    = "Low",
        })
    end
end

-- ── Rule 2: Massively oversized parts (scale exploit / lag trap) ──────────
local function checkPartSize(part)
    if not part:IsA("BasePart") then return end
    local ok, sz = pcall(function() return part.Size end)
    if not ok then return end
    local volume = sz.X * sz.Y * sz.Z
    if volume > 1_000_000 then   -- 100×100×100 cube threshold
        Data:ReportBug({
            Type        = "Oversized Part",
            Source      = safeFullName(part),
            Description = string.format("Part volume is %.0f units³ (%.0f×%.0f×%.0f). Extremely large parts stall the physics engine.", volume, sz.X, sz.Y, sz.Z),
            Severity    = "Medium",
        })
    end
end

-- ── Rule 3: Character falling through floor (local player quality-check) ──
local lastRootY = nil
local function checkLocalFallThrough()
    local char = Players.LocalPlayer and Players.LocalPlayer.Character
    if not char then return end
    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return end
    local ok, pos = pcall(function() return root.Position end)
    if not ok then return end
    if lastRootY and (lastRootY - pos.Y) > 60 then
        -- Fell more than 60 studs in one scan tick — likely clipped through floor
        Data:ReportBug({
            Type        = "Fall-Through Detected",
            Source      = "LocalPlayer::HumanoidRootPart",
            Description = string.format("LocalPlayer dropped %.1f studs in one frame-pass (Y: %.1f→%.1f). Possible noclip or map void.", lastRootY - pos.Y, lastRootY, pos.Y),
            Severity    = "Medium",
        })
    end
    lastRootY = pos.Y
end

-- ── Master scan ───────────────────────────────────────────────────────────
local function runHealerScan()
    Data.Stats.ScanCount = Data.Stats.ScanCount + 1
    for _, part in ipairs(workspace:GetDescendants()) do
        pcall(checkFallenPart, part)
        pcall(checkPartSize, part)
    end
    pcall(checkLocalFallThrough)
end

table.insert(getgenv().DebuggerScanners, runHealerScan)
print("[Auto-Healer v5]: Physics healer active.")
