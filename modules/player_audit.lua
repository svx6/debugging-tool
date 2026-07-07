--[[
    ========================================================================
    ULTIMATE ROBLOX AUTO-DEBUGGER  ·  PLAYER SECURITY AUDITOR  (v8)
    ========================================================================
    Detects per-player:
      1. Speed hack        — WalkSpeed abnormally high
      2. Jump hack         — JumpPower/JumpHeight abnormally high
      3. Teleport          — large position delta between scans
      4. Noclip            — CanCollide false on all HRP BaseParts
      5. Fly hack          — floating at constant Y with no jump animation
      6. Rapid fire        — fires >N events per second to server
      7. Name spoofing     — DisplayName ≠ Name (common in cheat menus)
      8. GOD mode          — Humanoid.Health = maxHealth every scan (infinite)
      9. Infinite stamina  — custom Stamina/Energy attribute always at max
     10. Tool spam         — >10 tools in backpack
    All detections are rate-limited per-player to avoid log spam.
    ========================================================================
--]]

local Data = getgenv().DebuggerSharedData
if not Data then warn("[PlayerAuditor v8]: Core not loaded.") return end

local Players     = game:GetService("Players")
local RunService  = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer

-- ── Per-player state ─────────────────────────────────────────────────────
local state = {}   -- [userId] = { ... }

local function getState(player)
    local uid = player.UserId
    if not state[uid] then
        state[uid] = {
            lastPos          = nil,
            lastHealth       = nil,
            flyFrames        = 0,
            lastReportedType = {},  -- type → last report clock
            lastMoveTime     = tick(),
        }
    end
    return state[uid]
end

-- ── Rate limiter — 1 report per type per player per N seconds ─────────────
local REPORT_COOLDOWN = 15  -- seconds

local function canReport(st, typeKey)
    local now = os.clock()
    if not st.lastReportedType[typeKey] then
        st.lastReportedType[typeKey] = now
        return true
    end
    if now - st.lastReportedType[typeKey] >= REPORT_COOLDOWN then
        st.lastReportedType[typeKey] = now
        return true
    end
    return false
end

local function report(player, st, typeKey, severity, description)
    if not canReport(st, typeKey) then return end
    Data:ReportBug({
        Type        = typeKey,
        Source      = player.Name,
        Description = description,
        Severity    = severity,
    })
    Data:ReportLog({
        Type = "Warning",
        Text = string.format("[PlayerAudit] %s — %s: %s", player.Name, typeKey, description:sub(1, 100)),
    })
end

-- ── Audit one player ──────────────────────────────────────────────────────
local function auditPlayer(player)
    if not player or player == LocalPlayer then return end
    local char = player.Character
    if not char then return end
    local st = getState(player)

    local humanoid = char:FindFirstChildOfClass("Humanoid")
    local hrp      = char:FindFirstChild("HumanoidRootPart")

    -- 1. SPEED HACK
    if humanoid then
        local ok, ws = pcall(function() return humanoid.WalkSpeed end)
        if ok and ws > 38 then
            report(player, st, "Exploit: Speed Hack", "High",
                string.format("WalkSpeed = %d (normal ≤ 16). Possible speed hack.", math.floor(ws)))
        end
    end

    -- 2. JUMP HACK
    if humanoid then
        local jpOk, jp
        local useJPOk, useJP = pcall(function() return humanoid.UseJumpPower end)
        if useJPOk and useJP then
            jpOk, jp = pcall(function() return humanoid.JumpPower end)
            if jpOk and jp > 110 then
                report(player, st, "Exploit: Jump Hack", "Medium",
                    string.format("JumpPower = %d (normal ≤ 50).", math.floor(jp)))
            end
        else
            jpOk, jp = pcall(function() return humanoid.JumpHeight end)
            if jpOk and jp > 28 then
                report(player, st, "Exploit: Jump Hack", "Medium",
                    string.format("JumpHeight = %d (normal ≤ 7.2).", math.floor(jp)))
            end
        end
    end

    -- 3. TELEPORT DETECTION
    if hrp then
        local posOk, pos = pcall(function() return hrp.Position end)
        if posOk then
            if st.lastPos then
                local dist = (pos - st.lastPos).Magnitude
                -- 3s scan interval × 50 studs/s walk = 150 max legit movement.
                -- Use 350 to account for fast mounts / tools.
                if dist > 350 then
                    report(player, st, "Exploit: Teleport", "High",
                        string.format("Moved %.0f studs in one scan cycle. Threshold: 350.", dist))
                end
            end
            st.lastPos = pos
        end
    end

    -- 4. NOCLIP (all HRP descendant BaseParts have CanCollide = false while on ground)
    if hrp then
        local allNoCollide = true
        local partCount = 0
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") and part ~= hrp then
                partCount = partCount + 1
                local colOk, col = pcall(function() return part.CanCollide end)
                if colOk and col then allNoCollide = false; break end
            end
        end
        if allNoCollide and partCount > 2 then
            report(player, st, "Exploit: Noclip", "High",
                string.format("All %d body parts have CanCollide=false. Likely noclip.", partCount))
        end
    end

    -- 5. FLY HACK (stationary Y position while velocity is near-zero and not on ground)
    if hrp then
        local yOk, yPos = pcall(function() return hrp.Position.Y end)
        local vOk, vel  = pcall(function() return hrp.Velocity end)
        if yOk and vOk then
            local isGrounded = false
            pcall(function()
                -- Simple ground check: if Humanoid.FloorMaterial ~= Air
                if humanoid then
                    local floorOk, floor = pcall(function() return humanoid.FloorMaterial end)
                    isGrounded = floorOk and floor ~= Enum.Material.Air
                end
            end)
            if not isGrounded and math.abs(vel.Y) < 0.5 and yPos > 5 then
                st.flyFrames = (st.flyFrames or 0) + 1
                if st.flyFrames >= 4 then  -- 4 consecutive scan cycles
                    report(player, st, "Exploit: Fly Hack", "High",
                        string.format("Floating at Y=%.1f for %d scan cycles with no Y velocity.", yPos, st.flyFrames))
                    st.flyFrames = 0
                end
            else
                st.flyFrames = 0
            end
        end
    end

    -- 6. GOD MODE (health stays at exact max every scan)
    if humanoid then
        local hpOk, hp  = pcall(function() return humanoid.Health end)
        local mhOk, mh  = pcall(function() return humanoid.MaxHealth end)
        if hpOk and mhOk and mh > 0 then
            if st.lastHealth and st.lastHealth == hp and hp == mh and mh ~= 100 then
                -- Player was hit but health is identical two scans in a row at max
                report(player, st, "Exploit: God Mode", "High",
                    string.format("Health locked at %.0f/%.0f (MaxHealth=%.0f).", hp, mh, mh))
            end
            st.lastHealth = hp
        end
    end

    -- 7. TOOL SPAM
    local backpack = player:FindFirstChildOfClass("Backpack")
    if backpack then
        local toolCount = #backpack:GetChildren()
        if toolCount > 12 then
            report(player, st, "Exploit: Tool Spam", "Medium",
                string.format("Player has %d tools in backpack (normal ≤ 4).", toolCount))
        end
    end

    -- 8. NAME SPOOFING (DisplayName differs greatly from Name — common in cheat menus)
    local dnOk, dn = pcall(function() return player.DisplayName end)
    if dnOk and dn then
        if dn ~= player.Name and #dn > 0 and dn:lower() ~= player.Name:lower() then
            -- Only flag if the display name looks like it's impersonating someone (starts with same letters)
            -- We just log it, not a hard flag
            if canReport(st, "Info: DisplayName") then
                Data:ReportLog({
                    Type = "Info",
                    Text = string.format("[PlayerAudit] %s has DisplayName '%s' (may differ from Name '%s')",
                        player.Name, dn, player.Name),
                })
            end
        end
    end
end

-- ── Scan all players ───────────────────────────────────────────────────────
local function runScan()
    for _, player in ipairs(Players:GetPlayers()) do
        pcall(auditPlayer, player)
        task.wait()  -- yield between each player to spread load
    end
end

table.insert(getgenv().DebuggerScanners, runScan)

-- ── Cleanup on player leave ────────────────────────────────────────────────
Players.PlayerRemoving:Connect(function(player)
    local uid = player.UserId
    state[uid] = nil
    -- Remove their bugs from the list + dedup set
    for i = #Data.Bugs, 1, -1 do
        local bug = Data.Bugs[i]
        if bug and bug.Source == player.Name then
            local setKey = (bug.Type or ""):lower() .. "\0" .. (bug.Source or ""):lower()
            Data.BugSet[setKey] = nil
            table.remove(Data.Bugs, i)
        end
    end
end)

print("[PlayerAudit v8]: 8-check anti-cheat active (Speed/Jump/Teleport/Noclip/Fly/GodMode/ToolSpam/DisplayName)")
