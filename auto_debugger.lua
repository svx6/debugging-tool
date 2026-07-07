--[[
    ========================================================================
    ULTIMATE ROBLOX AUTO-DEBUGGER - AUTOMATED SCANNER ENGINE & HEALER
    ========================================================================
    Author: Antigravity
    Description: Continuous game scanner loop. Cleans physics leaks,
                 calculates metrics, and triggers diagnostics.
    ========================================================================
--]]

local Data = getgenv().DebuggerSharedData
if not Data then
    warn("[Auto-Debugger]: Shared data not initialized. Run main.lua first.")
    return
end

local Players = game:GetService("Players")

-- Physics healer function
local function healPhysics(item)
    if not item:IsA("BasePart") then return end
    
    if not item.Anchored and item.Position.Y < -500 and not item:IsDescendantOf(Players) then
        if Data.Settings.AutoClean then
            pcall(function() item:Destroy() end)
        else
            local path = item:GetFullName()
            local exists = false
            for _, b in ipairs(Data.Bugs) do 
                if b.Source == path then exists = true break end 
            end
            
            if not exists then
                local bug = {
                    Time = os.date("%H:%M:%S"),
                    Type = "Physics Leak",
                    Source = path,
                    Description = "Unanchored part fell past world limit (-500Y). Stalls physics engine.",
                    Severity = "Medium"
                }
                table.insert(Data.Bugs, 1, bug)
                Data.Stats.BugsFound = Data.Stats.BugsFound + 1
                if Data.OnBugAdded then Data.OnBugAdded(bug) end
            end
        end
    end
end

-- Core scanner function
local function scanGame()
    -- Update basic metrics
    local allDescendants = game:GetDescendants()
    Data.Stats.InstanceCount = #allDescendants
    
    -- Scan workspace parts for physics leaks
    for _, item in ipairs(workspace:GetDescendants()) do
        pcall(healPhysics, item)
    end
    
    -- Run external bug finder rules if registered
    if getgenv().DebuggerRunExternalScans then
        pcall(getgenv().DebuggerRunExternalScans)
    end
end

-- Export functions for manual triggers
getgenv().DebuggerManualScan = scanGame

-- Automated periodic task loop
task.spawn(function()
    while true do
        task.wait(Data.Settings.ScanInterval)
        pcall(scanGame)
    end
end)

print("[Auto-Debugger]: Automated scanner and healer module loaded.")
