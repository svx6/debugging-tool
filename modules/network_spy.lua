--[[
    ========================================================================
    ULTIMATE ROBLOX AUTO-DEBUGGER  ·  NETWORK SPY  (v8)
    ========================================================================
    Intercepts ALL RemoteEvent / RemoteFunction traffic:
      · Primary method: hookmetamethod on __namecall (Synapse X, KRNL, Wave)
      · Fallback: per-instance FireServer / InvokeServer hook
      · Records: call count, last args, call rate, direction
      · Detects rapid-fire (>20 calls/sec) to a single remote
      · Shows full argument list with type info
      · Works on every major executor
    ========================================================================
--]]

local Data = getgenv().DebuggerSharedData
if not Data then warn("[NetworkSpy v8]: Core not loaded.") return end

local _orig_pcall    = pcall
local _orig_tostring = tostring

-- ── Helpers ───────────────────────────────────────────────────────────────
local function safePath(inst)
    local ok, p = _orig_pcall(function() return inst:GetFullName() end)
    return ok and p or _orig_tostring(inst)
end
local function safeName(inst)
    local ok, n = _orig_pcall(function() return inst.Name end)
    return ok and n or "?"
end
local function safeClass(inst)
    local ok, c = _orig_pcall(function() return inst.ClassName end)
    return ok and c or "?"
end

local function argsToStr(args)
    local parts = {}
    for i, v in ipairs(args) do
        local t = typeof(v)
        local s
        if t == "string"  then s = '"' .. v:sub(1, 30) .. '"'
        elseif t == "number" then s = tostring(v)
        elseif t == "boolean" then s = tostring(v)
        elseif t == "nil"    then s = "nil"
        elseif t == "Instance" then
            local ok2, fn = _orig_pcall(function() return v:GetFullName() end)
            s = (ok2 and fn or t)
        else s = t end
        table.insert(parts, s)
    end
    return parts
end

-- ── Remote record management ──────────────────────────────────────────────
local callTimestamps = {}  -- path → list of os.clock() timestamps (for rate calc)

local function getOrCreate(inst, method)
    local path = safePath(inst)
    if not Data.Remotes[path] then
        Data.Remotes[path] = {
            Name      = safeName(inst),
            Path      = path,
            Class     = safeClass(inst),
            Method    = method,
            Calls     = 0,
            CallRate  = 0,
            Args      = {},
            LastArgs  = {},
            Blocked   = false,
        }
        Data.Stats.RemotesHooked = Data.Stats.RemotesHooked + 1
        _orig_pcall(function() Data:Publish("OnRemoteSpied", Data.Remotes[path]) end)
    end
    return Data.Remotes[path], path
end

local function recordCall(inst, method, args)
    local rec, path = getOrCreate(inst, method)
    rec.Calls    = rec.Calls + 1
    rec.Args     = argsToStr(args)
    rec.LastArgs = rec.Args
    rec.Method   = method

    -- Rate calculation
    local ts = callTimestamps[path] or {}
    local now = os.clock()
    table.insert(ts, now)
    while #ts > 0 and now - ts[1] > 5 do table.remove(ts, 1) end
    callTimestamps[path] = ts
    rec.CallRate = math.floor(#ts / 5 + 0.5)

    -- Rapid-fire alert (>20/sec sustained)
    if rec.CallRate > 20 then
        _orig_pcall(function()
            Data:ReportBug({
                Type = "Network: Rapid Fire Remote",
                Source = path,
                Description = string.format("'%s' fired %d times/sec. Possible exploit or tight loop.", rec.Name, rec.CallRate),
                Severity = "High",
            })
        end)
    end

    -- Blocked check
    if rec.Blocked then return true end  -- signal to suppress
    _orig_pcall(function() Data:Publish("OnRemoteSpied", rec) end)
    return false
end

-- ── Method 1: hookmetamethod (__namecall) — best coverage ─────────────────
local hookedViaMeta = false
_orig_pcall(function()
    if not hookmetamethod or not getrawmetatable then return end
    local meta = getrawmetatable(game)
    if not meta then return end

    local origNC = meta.__namecall
    hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
        local method = getnamecallmethod and getnamecallmethod() or ""
        if (method == "FireServer" or method == "InvokeServer"
            or method == "FireAllClients" or method == "FireClient") then
            local ok, isRemote = _orig_pcall(function()
                return self:IsA("RemoteEvent") or self:IsA("RemoteFunction")
            end)
            if ok and isRemote then
                local blocked = recordCall(self, method, {...})
                if blocked then return end
            end
        end
        return origNC(self, ...)
    end))
    hookedViaMeta = true
end)

-- ── Method 2: per-instance wrapping (fallback) ────────────────────────────
local wrapped = {}

local function hookInstance(inst)
    if not inst then return end
    local ok, _ = _orig_pcall(function() return inst.Parent end)
    if not ok then return end
    local path = safePath(inst)
    if wrapped[path] then return end
    wrapped[path] = true

    _orig_pcall(function()
        local cls = safeClass(inst)
        if cls == "RemoteEvent" then
            local origFire = inst.FireServer
            if origFire and hookfunction then
                hookfunction(inst.FireServer, function(s, ...)
                    local blocked = recordCall(inst, "FireServer", {...})
                    if not blocked then return origFire(s, ...) end
                end)
            end
        elseif cls == "RemoteFunction" then
            local origInvoke = inst.InvokeServer
            if origInvoke and hookfunction then
                hookfunction(inst.InvokeServer, function(s, ...)
                    local blocked = recordCall(inst, "InvokeServer", {...})
                    if not blocked then return origInvoke(s, ...) end
                end)
            end
        end
    end)
end

-- Scan existing remotes
if not hookedViaMeta then
    task.spawn(function()
        for _, desc in ipairs(game:GetDescendants()) do
            if desc:IsA("RemoteEvent") or desc:IsA("RemoteFunction") then
                hookInstance(desc)
            end
            task.wait()
        end
    end)
end

-- Watch for new remotes
game.DescendantAdded:Connect(function(inst)
    task.wait(0.05)
    _orig_pcall(function()
        if not inst or not inst.Parent then return end
        if inst:IsA("RemoteEvent") or inst:IsA("RemoteFunction") then
            if not hookedViaMeta then hookInstance(inst) end
            getOrCreate(inst, inst.ClassName == "RemoteEvent" and "FireServer" or "InvokeServer")
        end
    end)
end)

-- ── Block / Unblock API ───────────────────────────────────────────────────
Data.BlockRemote = function(path)
    if Data.Remotes[path] then Data.Remotes[path].Blocked = true end
end
Data.UnblockRemote = function(path)
    if Data.Remotes[path] then Data.Remotes[path].Blocked = false end
end

-- ── Fire a remote by path with args ──────────────────────────────────────
Data.FireRemote = function(path, args)
    args = args or {}
    _orig_pcall(function()
        local rec = Data.Remotes[path]
        if not rec then return end
        -- Try to find the live instance
        local inst = game
        for part in path:gmatch("[^%.]+") do
            inst = inst:FindFirstChild(part) or inst[part]
            if not inst then return end
        end
        local cls = safeClass(inst)
        if cls == "RemoteEvent" then
            inst:FireServer(table.unpack(args))
        elseif cls == "RemoteFunction" then
            inst:InvokeServer(table.unpack(args))
        end
    end)
end

print(string.format("[NetworkSpy v8]: Method=%s. Monitoring all RemoteEvent/Function traffic.",
    hookedViaMeta and "hookmetamethod(__namecall)" or "per-instance hooks"))
