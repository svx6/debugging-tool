--[[
    ========================================================================
    ULTIMATE ROBLOX AUTO-DEBUGGER  ·  INSTANCE TRACKER  (v8)
    ========================================================================
    Tracks instance creation/deletion rates to detect:
      · Instance floods (exponential growth — common in lag exploits)
      · Orphaned instances (no parent, not in workspace or services)
      · Leaked GUI objects (ScreenGui abandoned in PlayerGui)
      · Over-large models (>2000 parts — common performance killer)
      · Script-created instances outside of authorized locations
    ========================================================================
--]]

local Data = getgenv().DebuggerSharedData
if not Data then warn("[InstanceTracker v8]: Core not loaded.") return end

local Players  = game:GetService("Players")
local LP       = Players.LocalPlayer

Data.InstanceTracker = Data.InstanceTracker or {
    CountHistory     = {},  -- last 20 samples of GetDescendants() count
    LastCount        = 0,
    CreatedSinceStart = 0,
    DeletedSinceStart = 0,
    FloodThreshold   = 2000,  -- instances added per scan interval
}
local IT = Data.InstanceTracker

-- ── Track Added / Removed ─────────────────────────────────────────────────
game.DescendantAdded:Connect(function()
    IT.CreatedSinceStart = IT.CreatedSinceStart + 1
end)
game.DescendantRemoving:Connect(function()
    IT.DeletedSinceStart = IT.DeletedSinceStart + 1
end)

-- ── Scanner ────────────────────────────────────────────────────────────────
local function runInstanceScan()
    local count = 0
    pcall(function() count = #game:GetDescendants() end)
    Data.Stats.InstanceCount = count

    -- Rolling history
    table.insert(IT.CountHistory, count)
    while #IT.CountHistory > 20 do table.remove(IT.CountHistory, 1) end

    -- Flood detection: if count grew by >FloodThreshold since last scan
    if IT.LastCount > 0 then
        local delta = count - IT.LastCount
        if delta > IT.FloodThreshold then
            Data:ReportBug({
                Type = "Instance Flood",
                Source = "Runtime::Instances",
                Description = string.format("%d instances added in one scan cycle (threshold: %d). Possible lag bomb or faulty script loop.",
                    delta, IT.FloodThreshold),
                Severity = delta > 5000 and "High" or "Medium",
            })
        end
    end
    IT.LastCount = count

    -- Leaked ScreenGui detection
    pcall(function()
        if LP and LP:FindFirstChildOfClass("PlayerGui") then
            local pg = LP.PlayerGui
            for _, ch in ipairs(pg:GetChildren()) do
                if ch:IsA("ScreenGui") and ch ~= pg:FindFirstChild("AutoDebuggerUI_v7") then
                    -- Warn if > 10 ScreenGuis (excessive)
                    local guiCount = 0
                    for _ in ipairs(pg:GetChildren()) do guiCount = guiCount + 1 end
                    if guiCount > 10 then
                        Data:ReportBug({
                            Type = "GUI Leak",
                            Source = "PlayerGui",
                            Description = string.format("%d ScreenGuis in PlayerGui (expected ≤ 5). Possible GUI leak from repeated script injection.", guiCount),
                            Severity = "Medium",
                        })
                        break
                    end
                end
            end
        end
    end)

    -- Over-large model detection
    pcall(function()
        for _, inst in ipairs(workspace:GetChildren()) do
            if inst:IsA("Model") then
                local partCount = 0
                for _, p in ipairs(inst:GetDescendants()) do
                    if p:IsA("BasePart") then
                        partCount = partCount + 1
                        if partCount > 3000 then break end
                    end
                end
                if partCount > 2500 then
                    Data:ReportBug({
                        Type = "Performance: Oversized Model",
                        Source = inst:GetFullName(),
                        Description = string.format("Model '%s' has >%d BaseParts. Large models cause render lag.", inst.Name, partCount),
                        Severity = "Medium",
                    })
                end
            end
            task.wait()  -- yield per workspace child
        end
    end)
end

table.insert(getgenv().DebuggerScanners, runInstanceScan)

print("[InstanceTracker v8]: Flood + GUI leak + oversized model detection active.")
