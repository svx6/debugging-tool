--[[
    ========================================================================
    ULTIMATE ROBLOX AUTO-DEBUGGER  ·  AUTO REMOTE MANAGER  (v6)
    ========================================================================
    Author   : Antigravity
    Features :
      · Auto-discovers ALL RemoteEvents + RemoteFunctions the instant they exist
      · Real-time call logger with argument inspection
      · One-click "Fire Remote" from GUI with custom args
      · Block/allow individual remotes
      · Remote speed graph data (calls per second per remote)
      · Detects server→client OnClientEvent fires too
      · Auto-hooks NEW remotes as they're added dynamically
    ========================================================================
--]]

local Data = getgenv().DebuggerSharedData
if not Data then warn("[AutoRemote v6]: Core not loaded.") return end

-- ── Extension Data ────────────────────────────────────────────────────────
Data.AutoRemotes = Data.AutoRemotes or {}    -- path → RemoteRecord
Data.BlockedRemotes = Data.BlockedRemotes or {}  -- path → true

local AR = Data.AutoRemotes
local BR = Data.BlockedRemotes

-- ── Utilities ─────────────────────────────────────────────────────────────
local function safeName(inst)
    local ok, n = pcall(function() return inst.Name end) 
    return ok and n or "?"
end

local function safePath(inst)
    local ok, p = pcall(function() return inst:GetFullName() end)
    return ok and p or tostring(inst)
end

local function serializeArg(v, depth)
    depth = depth or 0
    if depth > 4 then return "..." end
    local t = typeof(v)
    if t == "nil"     then return "nil" end
    if t == "boolean" then return tostring(v) end
    if t == "number"  then return tostring(math.floor(v * 1000 + 0.5) / 1000) end
    if t == "string"  then return string.format("%q", v:sub(1, 80)) end
    if t == "Vector3" then return string.format("V3(%.2f,%.2f,%.2f)", v.X, v.Y, v.Z) end
    if t == "CFrame"  then
        local p = v.Position
        return string.format("CF(%.1f,%.1f,%.1f)", p.X, p.Y, p.Z)
    end
    if t == "Instance" then return "[" .. v.ClassName .. "] " .. safePath(v) end
    if t == "table"   then
        local parts = {}
        local n = 0
        for k, val in pairs(v) do
            n = n + 1
            if n > 6 then table.insert(parts, "...") break end
            table.insert(parts, tostring(k) .. "=" .. serializeArg(val, depth + 1))
        end
        return "{" .. table.concat(parts, ", ") .. "}"
    end
    return t .. ":" .. tostring(v):sub(1, 40)
end

local function serializeArgs(args)
    local parts = {}
    for i, v in ipairs(args) do
        parts[i] = serializeArg(v)
    end
    return parts
end

-- ── Remote Record Management ───────────────────────────────────────────────
local callTimestamps = {}  -- path → {timestamps}

local function safeClass(inst)
    local ok, c = pcall(function() return inst.ClassName end)
    return ok and c or "?"
end

local function getOrCreateRecord(remote, method)
    local path = safePath(remote)
    if not AR[path] then
        AR[path] = {
            Name       = safeName(remote),
            Path       = path,
            Class      = safeClass(remote),
            Method     = method,
            Calls      = 0,
            Blocked    = false,
            CallRate   = 0,
            LastArgs   = {},
            History    = {},  -- last 20 calls
            FirstSeen  = os.date("%H:%M:%S"),
            LastFired  = os.date("%H:%M:%S"),
            Remote     = remote,  -- live reference
        }
        Data.Stats.RemotesHooked = Data.Stats.RemotesHooked + 1
        Data:Publish("OnAutoRemoteAdded", AR[path])
    end
    return AR[path]
end

local function recordCall(remote, method, args)
    local path = safePath(remote)
    if BR[path] then return false end  -- blocked

    local rec = getOrCreateRecord(remote, method)
    rec.Calls = rec.Calls + 1
    rec.Method = method
    rec.LastFired = os.date("%H:%M:%S")
    rec.LastArgs = serializeArgs(args)

    -- Rolling call history
    table.insert(rec.History, 1, {
        Time   = os.date("%H:%M:%S"),
        Method = method,
        Args   = serializeArgs(args),
    })
    while #rec.History > 20 do table.remove(rec.History) end

    -- Call rate (calls per second over 5-sec window)
    if not callTimestamps[path] then callTimestamps[path] = {} end
    local hist = callTimestamps[path]
    local now = os.clock()
    table.insert(hist, now)
    local i = 1
    while i <= #hist do
        if now - hist[i] > 5 then table.remove(hist, i)
        else i = i + 1 end
    end
    rec.CallRate = math.floor(#hist / 5 + 0.5)

    Data:Publish("OnAutoRemoteFired", rec)
    return true
end

-- ── Hook Strategy 1: hookmetamethod ──────────────────────────────────────
local hookedViaMetamethod = false
if hookmetamethod and getnamecallmethod then
    pcall(function()
        local oldNC
        oldNC = hookmetamethod(game, "__namecall", function(self, ...)
            local method = getnamecallmethod()
            -- Client→Server calls
            if method == "FireServer" and typeof(self) == "Instance" and self:IsA("RemoteEvent") then
                task.spawn(recordCall, self, "FireServer", {...})
            elseif method == "InvokeServer" and typeof(self) == "Instance" and self:IsA("RemoteFunction") then
                task.spawn(recordCall, self, "InvokeServer", {...})
            end
            return oldNC(self, ...)
        end)
        hookedViaMetamethod = true
    end)
end

-- ── Hook Strategy 2: Wrap individual FireServer/InvokeServer ──────────────
local function hookRemoteInstance(inst)
    if not inst then return end
    local hasParent = pcall(function() return inst.Parent end)
    if not hasParent then return end
    pcall(function()
        local path = safePath(inst)
        if AR[path] and AR[path]._wrapped then return end  -- already wrapped

        -- Ensure the record exists immediately
        local cls = safeClass(inst)
        getOrCreateRecord(inst, cls == "RemoteEvent" and "FireServer" or "InvokeServer")
        if AR[path] then AR[path]._wrapped = true end

        if not hookedViaMetamethod then
            if inst:IsA("RemoteEvent") then
                local orig = inst.FireServer
                inst.FireServer = function(self, ...)
                    recordCall(self, "FireServer", {...})
                    return orig(self, ...)
                end
            elseif inst:IsA("RemoteFunction") then
                local orig = inst.InvokeServer
                inst.InvokeServer = function(self, ...)
                    recordCall(self, "InvokeServer", {...})
                    return orig(self, ...)
                end
            end
        end

        -- Also hook OnClientEvent (server → client) if accessible
        if inst:IsA("RemoteEvent") then
            pcall(function()
                inst.OnClientEvent:Connect(function(...)
                    local path2 = safePath(inst)
                    local rec = AR[path2]
                    if rec then
                        table.insert(rec.History, 1, {
                            Time   = os.date("%H:%M:%S"),
                            Method = "OnClientEvent",
                            Args   = serializeArgs({...}),
                        })
                        while #rec.History > 20 do table.remove(rec.History) end
                        Data:Publish("OnAutoRemoteFired", rec)
                    end
                end)
            end)
        end
    end)
end

-- ── Auto-Discover All Current Remotes ────────────────────────────────────
local function discoverAll()
    for _, inst in ipairs(game:GetDescendants()) do
        pcall(function()
            if inst:IsA("RemoteEvent") or inst:IsA("RemoteFunction") then
                hookRemoteInstance(inst)
            end
        end)
    end
end

task.spawn(discoverAll)

-- ── Watch for NEW remotes ──────────────────────────────────────────────────
game.DescendantAdded:Connect(function(inst)
    task.wait(0.05)  -- let it fully replicate
    pcall(function()
        -- Verify inst is still valid (could be destroyed during wait)
        if not inst or not inst.Parent then return end
        if inst:IsA("RemoteEvent") or inst:IsA("RemoteFunction") then
            hookRemoteInstance(inst)
        end
    end)
end)

-- ── Block / Unblock API (callable from GUI) ───────────────────────────────
Data.BlockRemote = function(path)
    BR[path] = true
    if AR[path] then AR[path].Blocked = true end
    Data:Publish("OnRemoteBlocked", path)
end

Data.UnblockRemote = function(path)
    BR[path] = nil
    if AR[path] then AR[path].Blocked = false end
    Data:Publish("OnRemoteUnblocked", path)
end

-- ── Fire Remote API (callable from GUI) ───────────────────────────────────
-- GUI can call: Data.FireRemote(path, args_table)
Data.FireRemote = function(path, argsTable)
    local rec = AR[path]
    if not rec or not rec.Remote then
        warn("[AutoRemote] No live reference for path:", path)
        return false
    end
    local remote = rec.Remote
    local ok, err = pcall(function()
        if typeof(remote) ~= "Instance" or not remote.Parent then
            error("Remote no longer exists")
        end
        if remote:IsA("RemoteEvent") then
            remote:FireServer(table.unpack(argsTable or {}))
        elseif remote:IsA("RemoteFunction") then
            return remote:InvokeServer(table.unpack(argsTable or {}))
        end
    end)
    if not ok then
        Data:ReportLog({
            Type = "Warning",
            Text = "[AutoRemote] FireRemote failed for " .. path .. ": " .. tostring(err),
        })
        return false
    end
    return true
end

-- ── Scanner registration ──────────────────────────────────────────────────
local function autoRemoteScan()
    -- Re-discover periodically in case new containers loaded
    discoverAll()
    Data:Publish("OnAutoRemoteUpdate", AR)
end

table.insert(getgenv().DebuggerScanners, autoRemoteScan)
print(string.format("[AutoRemote v6]: Active. hookmetamethod=%s. Monitoring all remotes.", tostring(hookedViaMetamethod)))
