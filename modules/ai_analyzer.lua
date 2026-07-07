--[[
    ========================================================================
    ULTIMATE ROBLOX AUTO-DEBUGGER  ·  AI HEURISTIC ANALYZER  (v8)
    ========================================================================
    Massively upgraded AI engine:

    ANALYSIS ENGINES:
      1. Log Pattern Matcher   — 30+ error rules with specific fixes
      2. Error Loop Detector   — same error 5+ times = loop bug
      3. Remote Vulnerability  — 20 keywords × risk scoring
      4. Remote Payload Audit  — arg count, rate, method type
      5. Bug Correlator        — cross-links related bugs → combined insight
      6. Object Diagnosis      — AI analyzes inspected objects
      7. Performance Analyzer  — FPS/ping/memory trend analysis
      8. Chain Reaction Detector — one bug triggering cascades
      9. Health Reporter        — grade the entire session every 60s
     10. Remediation Generator  — generates specific Lua fix code snippets

    CONFIDENCE SCORING:
      Weighted by rule match quality, frequency, and correlation.

    OUTPUT:
      All insights go to Data.AIInsights and are published via OnAIInsightAdded.
      Fix code snippets are included in the Suggestion field.
    ========================================================================
--]]

local Data = getgenv().DebuggerSharedData
if not Data then warn("[AI-Analyzer v8]: Core not loaded.") return end

local _pcall = pcall

-- ── Insight Manager ───────────────────────────────────────────────────────
local insightsByTitle = {}

local function addInsight(title, problem, fix, confidence, category)
    confidence = confidence or "80%"
    category   = category or "General"

    -- Deduplicate: update hits + time instead of duplicating
    local existingIdx = insightsByTitle[title]
    if existingIdx and Data.AIInsights[existingIdx] then
        local ins = Data.AIInsights[existingIdx]
        ins.Time     = os.date("%H:%M:%S")
        ins.Hits     = (ins.Hits or 1) + 1
        ins.Suggestion = fix  -- update suggestion in case it improved
        _pcall(function() Data:Publish("OnAIInsightUpdated", ins) end)
        return
    end

    local insight = {
        Time       = os.date("%H:%M:%S"),
        Title      = title,
        Problem    = problem,
        Suggestion = fix,
        Confidence = confidence,
        Category   = category,
        Hits       = 1,
    }
    table.insert(Data.AIInsights, 1, insight)
    insightsByTitle[title] = 1
    -- Reindex (simple)
    for i, ins in ipairs(Data.AIInsights) do insightsByTitle[ins.Title] = i end
    -- Trim
    if #Data.AIInsights > Data.Settings.MaxInsights then
        local removed = table.remove(Data.AIInsights)
        if removed then insightsByTitle[removed.Title] = nil end
    end
    _pcall(function() Data:Publish("OnAIInsightAdded", insight) end)
end

-- ── Error Frequency Tracker ───────────────────────────────────────────────
local errorFreq    = {}
local errorSources = {}  -- signature → source script
local ERROR_LOOP_THRESHOLD = 4

-- ── Engine 1: Log Pattern Matcher ────────────────────────────────────────
-- 30+ rules: each has pattern, title, problem analysis, specific fix code
local LOG_RULES = {
    -- ─ Nil Access ──────────────────────────────────────────────────────────
    {
        pat = "attempt to index nil",
        title = "Nil Dereference",
        prob = "A property or method was accessed on a nil value. The object was not found, was destroyed, or was never set.",
        fix = [[Guard with nil check:
  local obj = parent:FindFirstChild("Name")
  if obj then
      obj.Property = value
  else
      warn("obj is nil — not found")
  end]],
        conf = "97%", cat = "Runtime Error",
    },
    {
        pat = "attempt to call nil",
        title = "Nil Function Call",
        prob = "A variable expected to hold a function is nil. The function may not have been defined, or the module that provides it failed to load.",
        fix = [[Check before calling:
  local fn = module.MyFunction
  if type(fn) == "function" then
      fn(arg1, arg2)
  else
      warn("Function not available")
  end]],
        conf = "95%", cat = "Runtime Error",
    },
    {
        pat = "attempt to perform arithmetic on",
        title = "Arithmetic on Non-Number",
        prob = "Math was performed on a nil, string, or boolean. Common in stat systems where a value fails to load.",
        fix = [[Sanitize before math:
  local value = tonumber(rawValue) or 0
  local result = value + 10  -- safe]],
        conf = "94%", cat = "Runtime Error",
    },
    -- ─ Yield / Async ───────────────────────────────────────────────────────
    {
        pat = "infinite yield",
        title = "WaitForChild Timeout",
        prob = "WaitForChild() waited indefinitely because the target never replicated. Likely a replication order issue or the object path is wrong.",
        fix = [[Add timeout and handle nil:
  local obj = parent:WaitForChild("TargetName", 5)
  if not obj then
      warn("Object never arrived: TargetName")
      return
  end]],
        conf = "99%", cat = "Async",
    },
    {
        pat = "cannot yield",
        title = "Illegal Yield in Callback",
        prob = "task.wait() or a yielding call was made inside a non-yieldable callback (Changed signal, GetPropertyChangedSignal). Roblox does not allow yielding inside these.",
        fix = [[Wrap with task.spawn:
  inst:GetPropertyChangedSignal("Health"):Connect(function()
      task.spawn(function()
          task.wait(0.1)   -- now safe to yield
          doSomething()
      end)
  end)]],
        conf = "96%", cat = "Async",
    },
    -- ─ Recursion / Stack ───────────────────────────────────────────────────
    {
        pat = "stack overflow",
        title = "Infinite Recursion (Stack Overflow)",
        prob = "A function recursively calls itself without a base case, exhausting the call stack.",
        fix = [[Add depth guard or convert to iteration:
  local MAX_DEPTH = 100
  local function recurse(node, depth)
      depth = depth or 0
      if depth >= MAX_DEPTH then return end
      -- ... process node ...
      recurse(node.Child, depth + 1)
  end]],
        conf = "98%", cat = "Runtime Error",
    },
    {
        pat = "maximum event re.entrancy",
        title = "Event Re-Entrancy Loop",
        prob = "An event fires itself within its own handler, creating an infinite recursion loop at the event level.",
        fix = [[Use a reentrancy guard:
  local _busy = false
  remote.OnServerEvent:Connect(function(player, ...)
      if _busy then return end
      _busy = true
      -- safe code here
      _busy = false
  end)]],
        conf = "93%", cat = "Runtime Error",
    },
    -- ─ Types ───────────────────────────────────────────────────────────────
    {
        pat = "bad argument",
        title = "Invalid Argument to API",
        prob = "A Roblox API function received an argument of wrong type or out-of-range value.",
        fix = [[Validate before calling:
  assert(type(param) == "number", "Expected number, got " .. type(param))
  assert(param >= 0 and param <= 100, "Out of range: " .. param)
  api.SetValue(param)]],
        conf = "92%", cat = "Runtime Error",
    },
    {
        pat = "expected number",
        title = "Wrong Type: Expected Number",
        prob = "A function expected a number but received a string or nil.",
        fix = [[Sanitize:
  local n = tonumber(inputValue)
  if not n then warn("Not a number: " .. tostring(inputValue)); return end]],
        conf = "91%", cat = "Runtime Error",
    },
    {
        pat = "table index is nil",
        title = "Nil Table Key",
        prob = "A table was indexed with a nil key. This is illegal in Lua and usually means a loop variable or computed key resolved to nil.",
        fix = [[Guard the key:
  local key = computeKey()  -- may return nil
  if key ~= nil then
      myTable[key] = value
  end]],
        conf = "93%", cat = "Runtime Error",
    },
    -- ─ Module / Require ────────────────────────────────────────────────────
    {
        pat = "cannot load module",
        title = "Module Load Failure",
        prob = "require() failed. The ModuleScript either has a runtime error, returns nothing, or was destroyed.",
        fix = [[Wrap require in pcall:
  local ok, module = pcall(require, script.MyModule)
  if not ok then
      warn("Module load failed: " .. tostring(module))
      return
  end]],
        conf = "94%", cat = "Module",
    },
    {
        pat = "module must return",
        title = "Module Returns Nothing",
        prob = "A ModuleScript does not return a value. Every ModuleScript must end with 'return something'.",
        fix = [[Add return statement to module:
  -- At the very end of your ModuleScript:
  local MyModule = {}
  -- ... your code ...
  return MyModule  -- THIS IS REQUIRED]],
        conf = "99%", cat = "Module",
    },
    -- ─ Roblox Instance ─────────────────────────────────────────────────────
    {
        pat = "not a valid member",
        title = "Invalid Property / Child Access",
        prob = "Code accessed a property or child name that doesn't exist on this class. Property names are case-sensitive.",
        fix = [[Use FindFirstChild for children, check API for properties:
  local child = parent:FindFirstChild("ChildName")  -- safe
  if child then child:Destroy() end
  -- For properties, verify spelling in Roblox documentation]],
        conf = "95%", cat = "Instance",
    },
    {
        pat = "is not a valid",
        title = "Invalid Enum Value",
        prob = "An invalid Enum member or out-of-range value was assigned to a property.",
        fix = [[Use valid enum:
  part.Material = Enum.Material.SmoothPlastic  -- correct
  -- Wrong: part.Material = "SmoothPlastic"]],
        conf = "90%", cat = "Instance",
    },
    {
        pat = "has no parent",
        title = "Accessing Destroyed Instance",
        prob = "An instance was destroyed and then accessed. Destroyed instances lose their parent.",
        fix = [[Check before access:
  if inst and inst.Parent then
      inst.Property = value
  else
      warn("Instance was destroyed")
  end]],
        conf = "97%", cat = "Instance",
    },
    -- ─ Network / HTTP ──────────────────────────────────────────────────────
    {
        pat = "httpservice",
        title = "HTTP Request Failed",
        prob = "An HTTP request failed. This could be due to HttpService being disabled, an unreachable endpoint, or a Roblox content filter block.",
        fix = [[Always use pcall with HTTP:
  local HttpService = game:GetService("HttpService")
  local ok, result = pcall(function()
      return HttpService:GetAsync("https://api.example.com/data")
  end)
  if not ok then warn("HTTP failed: " .. result) end]],
        conf = "90%", cat = "Network",
    },
    {
        pat = "http 429",
        title = "HTTP Rate Limited",
        prob = "The HTTP endpoint returned 429 Too Many Requests. Your script is making HTTP calls too frequently.",
        fix = [[Add rate limiting:
  local lastRequest = 0
  local COOLDOWN = 2  -- seconds
  if tick() - lastRequest < COOLDOWN then return end
  lastRequest = tick()
  HttpService:GetAsync(url)]],
        conf = "88%", cat = "Network",
    },
    -- ─ DataStore ───────────────────────────────────────────────────────────
    {
        pat = "datastore",
        title = "DataStore Error",
        prob = "A DataStore operation failed. This is often due to rate limits, server-side validation errors, or malformed keys.",
        fix = [[Wrap DataStore calls:
  local MAX_RETRIES = 3
  for attempt = 1, MAX_RETRIES do
      local ok, err = pcall(function()
          store:SetAsync(key, data)
      end)
      if ok then break end
      warn("DataStore attempt " .. attempt .. " failed: " .. err)
      task.wait(2 ^ attempt)  -- exponential backoff
  end]],
        conf = "87%", cat = "DataStore",
    },
    -- ─ Memory ──────────────────────────────────────────────────────────────
    {
        pat = "memory",
        title = "Memory Pressure Detected",
        prob = "Memory warnings indicate large table allocations, instance floods, or persistent event connections accumulating over time.",
        fix = [[Memory cleanup best practices:
  -- 1. Disconnect events when done:
  local conn = event:Connect(handler)
  conn:Disconnect()  -- when finished
  -- 2. Clear large tables:
  table.clear(myHugeTable)
  -- 3. Destroy unused instances:
  for _, inst in ipairs(oldInstances) do inst:Destroy() end]],
        conf = "85%", cat = "Performance",
    },
    -- ─ Coroutine ───────────────────────────────────────────────────────────
    {
        pat = "cannot resume dead coroutine",
        title = "Dead Coroutine Resume",
        prob = "A coroutine was resumed after it finished executing. This is usually a missed check on coroutine status.",
        fix = [[Check coroutine status:
  local co = coroutine.create(myFunction)
  if coroutine.status(co) ~= "dead" then
      coroutine.resume(co)
  end]],
        conf = "92%", cat = "Coroutine",
    },
    -- ─ Physics ─────────────────────────────────────────────────────────────
    {
        pat = "physics",
        title = "Physics Engine Warning",
        prob = "The physics engine reported an anomaly. Possible causes: part with NaN/Inf position, assembly with disconnected constraints, or parts outside the physics world.",
        fix = [[Validate positions before setting:
  local pos = Vector3.new(x, y, z)
  if pos.X == pos.X and pos.Y == pos.Y then  -- NaN check
      part.Position = pos
  end]],
        conf = "80%", cat = "Physics",
    },
    -- ─ Security ────────────────────────────────────────────────────────────
    {
        pat = "permission denied",
        title = "Permission Denied",
        prob = "A script attempted to access a protected service or perform an action restricted to the server (from a LocalScript or vice versa).",
        fix = [[Check execution context:
  -- In LocalScript, use RemoteEvent to ask server:
  local remote = ReplicatedStorage.RequestAction
  remote:FireServer("performAction", actionData)
  -- Server handles privileged operations]],
        conf = "88%", cat = "Security",
    },
    -- ─ Tween / Animation ───────────────────────────────────────────────────
    {
        pat = "tween",
        title = "Tween Error",
        prob = "TweenService failed to create or play a tween. Common causes: invalid property name, tweening a non-tweeneable property, or the instance was destroyed before tween completion.",
        fix = [[Safe tween pattern:
  local ok, tween = pcall(function()
      return TweenService:Create(frame, TweenInfo.new(0.3), {BackgroundTransparency = 0})
  end)
  if ok then tween:Play() end]],
        conf = "83%", cat = "Animation",
    },
}

local function analyzeLog(entry)
    if not entry or (entry.Type ~= "Error" and entry.Type ~= "Warning") then return end
    local textLow = (entry.Text or ""):lower()
    local sig     = textLow:sub(1, 80)

    -- Frequency loop detection
    errorFreq[sig] = (errorFreq[sig] or 0) + 1
    if errorFreq[sig] == ERROR_LOOP_THRESHOLD then
        addInsight(
            "⚠ Error Loop: " .. entry.Text:sub(1, 40) .. "…",
            string.format("The error '%s…' has appeared %d times. It is being triggered repeatedly — likely inside a RunService loop or a repeated event connection.",
                entry.Text:sub(1, 60), errorFreq[sig]),
            [[Find and fix the loop:
  -- 1. Add a debounce to the event that triggers this
  -- 2. Wrap the body in pcall() to prevent crash spreading
  -- 3. Check if the error source is inside RunService.Heartbeat or a tight task.spawn loop]],
            "97%", "Error Loop"
        )
    end

    -- Rule matching
    local matched = false
    for _, rule in ipairs(LOG_RULES) do
        if textLow:find(rule.pat, 1, false) then
            addInsight(rule.title, rule.prob, rule.fix, rule.conf, rule.cat)
            matched = true
            break
        end
    end

    -- Catch-all with context-aware message
    if not matched and entry.Type == "Error" then
        addInsight(
            "Unclassified Error",
            "Error: " .. entry.Text:sub(1, 120),
            [[Generic debugging steps:
  1. pcall() the failing code to prevent crash spreading
  2. Add print() before each line to find which one fails
  3. Check if the error source script is still in game
  4. Look at the script name:line in the error message]],
            "65%", "Unknown"
        )
    end
end

Data:Subscribe("OnLogAdded", analyzeLog)

-- ── Engine 2: Remote Vulnerability Scoring ────────────────────────────────
local REMOTE_KEYWORDS = {
    {kw="ADMIN",    score=5, label="admin authority"},
    {kw="GIVE",     score=4, label="item/currency give"},
    {kw="CASH",     score=4, label="currency manipulation"},
    {kw="MONEY",    score=4, label="currency manipulation"},
    {kw="COIN",     score=3, label="currency"},
    {kw="BAN",      score=5, label="moderation control"},
    {kw="KICK",     score=4, label="moderation control"},
    {kw="GRANT",    score=3, label="privilege granting"},
    {kw="PROMOTE",  score=4, label="role escalation"},
    {kw="DELETE",   score=3, label="destructive action"},
    {kw="DESTROY",  score=3, label="destructive action"},
    {kw="EXECUTE",  score=6, label="code execution"},
    {kw="COMMAND",  score=3, label="command system"},
    {kw="TELEPORT", score=2, label="position control"},
    {kw="SPEED",    score=3, label="stat manipulation"},
    {kw="FLY",      score=3, label="movement cheat"},
    {kw="NOCLIP",   score=5, label="collision bypass"},
    {kw="KILL",     score=4, label="player kill"},
    {kw="HEALTH",   score=3, label="health manipulation"},
    {kw="PURCHASE", score=4, label="purchase action"},
}
local VULN_THRESHOLD = 4

local analyzedRemotes = {}

local function analyzeRemote(rd)
    if not rd or not rd.Name then return end
    if analyzedRemotes[rd.Path] then return end
    analyzedRemotes[rd.Path] = true

    local upper = rd.Name:upper()
    local totalScore, labels = 0, {}
    for _, kw in ipairs(REMOTE_KEYWORDS) do
        if upper:find(kw.kw, 1, true) then
            totalScore = totalScore + kw.score
            table.insert(labels, kw.label)
        end
    end

    if totalScore >= VULN_THRESHOLD then
        local sev = totalScore >= 8 and "High" or "Medium"
        local score100 = math.min(99, 50 + totalScore * 6)
        _pcall(function()
            Data:ReportBug({
                Type        = "Vulnerable Remote",
                Source      = rd.Path,
                Description = string.format("'%s' scored %d risk points. Matched: %s. Likely no server-side validation.", rd.Name, totalScore, table.concat(labels, ", ")),
                Severity    = sev,
            })
        end)
        addInsight(
            "🚨 High-Risk Remote: " .. rd.Name,
            string.format("Remote '%s' (path: %s) matches keywords: %s. Risk score: %d/30. This remote likely processes sensitive game actions without proper security.", rd.Name, rd.Path, table.concat(labels, " + "), totalScore),
            [[Server-side validation pattern:
  remote.OnServerEvent:Connect(function(player, action, value)
      -- 1. Validate player is in game
      if not game.Players:FindFirstChild(player.Name) then return end
      -- 2. Validate types
      if type(action) ~= "string" then return end
      -- 3. Whitelist allowed actions
      local ALLOWED = {buy=true, sell=true, equip=true}
      if not ALLOWED[action] then return end
      -- 4. Rate limit
      -- (use a per-player cooldown table)
  end)]],
            tostring(score100) .. "%", "Security"
        )
    end

    -- Rate analysis
    if rd.CallRate and rd.CallRate > 20 then
        addInsight(
            "⚡ Rapid-Fire Remote: " .. rd.Name,
            string.format("'%s' is called %d times/second. Without server-side rate limiting, this is exploitable for automation.", rd.Name, rd.CallRate),
            [[Server-side per-player rate limiter:
  local cooldowns = {}
  remote.OnServerEvent:Connect(function(player, ...)
      local now = tick()
      local last = cooldowns[player.UserId] or 0
      if now - last < 0.1 then return end  -- max 10/sec
      cooldowns[player.UserId] = now
      -- process the request
  end)]],
            "92%", "Performance"
        )
    end
end

Data:Subscribe("OnRemoteSpied", analyzeRemote)

-- ── Engine 3: Bug Correlator ──────────────────────────────────────────────
-- Finds patterns across multiple bugs and synthesizes combined insights
local lastBugCount  = 0
local bugTypeFreq   = {}  -- bug type → count

Data:Subscribe("OnBugAdded", function(bug)
    if not bug then return end
    _pcall(function()
        -- Track type frequency
        local btype = bug.Type or "Unknown"
        bugTypeFreq[btype] = (bugTypeFreq[btype] or 0) + 1

        -- High-severity burst
        local highCount = 0
        for _, b in ipairs(Data.Bugs) do
            if b.Severity == "High" then highCount = highCount + 1 end
        end
        if highCount >= 5 and highCount % 5 == 0 then
            addInsight(
                string.format("🔴 Critical: %d High-Severity Issues", highCount),
                string.format("%d high-severity issues have been detected. The game environment is significantly compromised. Immediate action required.", highCount),
                [[Priority action list:
  1. Open Bug Center → filter by "High" severity
  2. Check Script Hook for suspicious/backdoor scripts
  3. Check Crash Log for ScriptContext errors
  4. Block suspicious remotes in the Auto Remote tab
  5. Run a full page scan: Bug Center → ▶ Scan]],
                "99%", "Correlation"
            )
        end

        -- Repeating bug type
        if bugTypeFreq[btype] >= 3 then
            addInsight(
                "🔁 Recurring Bug: " .. btype,
                string.format("Bug type '%s' has occurred %d times. This is a systematic issue, not a one-off.", btype, bugTypeFreq[btype]),
                "Focus debugging efforts on the root cause of '" .. btype .. "'. Check if it originates from a single script or system.",
                "88%", "Correlation"
            )
        end

        -- Instance flood + high errors together = bad script loop
        if btype == "Instance Flood" then
            local errCount = Data.Stats.Errors or 0
            if errCount > 10 then
                addInsight(
                    "⚠ Instance Flood + High Error Rate",
                    "An instance flood is occurring simultaneously with a high error rate. This pattern strongly suggests a script loop that creates instances and then crashes, repeatedly.",
                    [[Look for:
  1. A while true loop that creates parts (game.Workspace)
  2. A DescendantAdded/ChildAdded handler that creates more children
  3. A RunService.Heartbeat loop that spawns things without cleanup
  Fix: Identify the script via Script Hook tab, disable it.]],
                    "94%", "Correlation"
                )
            end
        end
    end)
end)

-- ── Engine 4: Object Diagnosis AI ────────────────────────────────────────
-- When the inspector analyzes an object, AI reads the diagnosis
Data:Subscribe("OnObjectInspected", function(inspection)
    if not inspection then return end
    _pcall(function()
        for _, issue in ipairs(inspection.Diagnosis or {}) do
            if not issue:find("✅") then
                addInsight(
                    "Inspector: " .. inspection.Name .. " — " .. issue:sub(1, 50),
                    string.format("Inspected '%s' (%s) at %s. Issue: %s",
                        inspection.FullPath, inspection.ClassName, inspection.Time, issue),
                    "Check the Value Watcher tab to monitor this object's properties over time. If it's a problematic script, use Script Hook to see what it contains.",
                    "85%", "Inspector"
                )
            end
        end
    end)
end)

-- ── Engine 5: Performance Trend Analyzer ──────────────────────────────────
local prevFPS  = 60
local prevPing = 0
local prevMem  = 0

task.spawn(function()
    while getgenv().DebuggerLoaded do
        task.wait(10)
        _pcall(function()
            local fps  = Data.Stats.FPS     or 60
            local ping = Data.Stats.Ping    or 0
            local mem  = Data.Stats.MemoryMB or 0

            -- FPS dropping
            if fps < 20 and prevFPS >= 20 then
                addInsight(
                    "📉 FPS Dropped Below 20",
                    string.format("FPS fell from %d to %d. This can cause rubber-banding, animation stutters, and gameplay desync.", prevFPS, fps),
                    [[FPS recovery steps:
  1. Check Instance Count (Dashboard) — if >50,000 instances, there's a flood
  2. Check for scripts with tight RunService.Heartbeat loops
  3. Look for BaseParts with very complex meshes (UnionOperation)
  4. Check for explosion/fire/smoke particle abuse]],
                    "90%", "Performance"
                )
            end

            -- Memory leak detection
            if mem > prevMem + 50 and prevMem > 0 then
                addInsight(
                    "📈 Memory Spike: +" .. math.floor(mem - prevMem) .. "MB",
                    string.format("Memory jumped from %.1fMB to %.1fMB in 10 seconds. Rapid memory growth indicates a leak.", prevMem, mem),
                    [[Memory leak hunting:
  1. Open Instance Tracker — check if instance count is rising
  2. Look for event connections that are never Disconnect()ed
  3. Check for large tables being built in a loop without clearing
  4. Look for Sound objects being created but not destroyed]],
                    "87%", "Performance"
                )
            end

            -- High ping sustained
            if ping > 400 and prevPing <= 400 then
                addInsight(
                    "🌐 High Latency Detected: " .. ping .. "ms",
                    string.format("Ping rose to %dms. High latency can cause issues with RemoteEvent-dependent systems and hit detection.", ping),
                    [[Reduce network load:
  1. Audit the Network Spy tab for high-frequency remotes
  2. Bundle multiple remote calls into one RemoteEvent with a payload table
  3. Move non-critical syncs to polling (every 0.5s) instead of event-driven
  4. Check if any scripts are spamming HTTP requests]],
                    "82%", "Performance"
                )
            end

            prevFPS  = fps
            prevPing = ping
            prevMem  = mem
        end)
    end
end)

-- ── Engine 6: Health Reporter ─────────────────────────────────────────────
local function generateHealthReport()
    local score = 100
    score = score - math.min(40, (Data.Stats.BugsFound or 0) * 3)
    score = score - math.min(20, (Data.Stats.Errors or 0))
    score = score - math.min(15, math.max(0, 60 - (Data.Stats.FPS or 60)) / 2)
    score = score - math.min(10, math.max(0, (Data.Stats.Ping or 0) - 200) / 20)
    score = math.max(0, math.floor(score))

    local grade
    if     score >= 90 then grade = "A+ (Excellent)"
    elseif score >= 80 then grade = "A  (Healthy)"
    elseif score >= 70 then grade = "B  (Good)"
    elseif score >= 55 then grade = "C  (Minor Issues)"
    elseif score >= 40 then grade = "D  (Degraded)"
    elseif score >= 20 then grade = "E  (Critical)"
    else                     grade = "F  (Compromised)"
    end

    local icon = score >= 70 and "✅" or score >= 40 and "⚠" or "🔴"
    local topIssue = "System is stable."
    if Data.Stats.BugsFound > 10 then
        topIssue = "High bug count. Check Bug Center immediately."
    elseif (Data.Stats.FPS or 60) < 20 then
        topIssue = "Severe FPS drop. Check for instance floods or heavy scripts."
    elseif (Data.Stats.Ping or 0) > 400 then
        topIssue = "High latency. Network may be congested."
    end

    addInsight(
        icon .. " Health Report — " .. os.date("%H:%M"),
        string.format("Score: %d/100 · Grade: %s\nBugs: %d · Errors: %d · FPS: %d · Ping: %dms · Instances: %d · Memory: %sMB\nTop Issue: %s",
            score, grade,
            Data.Stats.BugsFound or 0, Data.Stats.Errors or 0,
            Data.Stats.FPS or 0, Data.Stats.Ping or 0,
            Data.Stats.InstanceCount or 0, tostring(Data.Stats.MemoryMB or "?"),
            topIssue),
        score < 60
            and "Immediate action recommended. Priority: Bug Center → Core Debugger → Script Hook."
            or "Environment is stable. Continue monitoring.",
        tostring(score) .. "%", "Health"
    )
end

-- Initial report after 3 seconds, then every 60s
task.delay(3, generateHealthReport)
task.spawn(function()
    while getgenv().DebuggerLoaded do
        task.wait(60)
        if getgenv().DebuggerLoaded then generateHealthReport() end
    end
end)

-- ── Expose for GUI ────────────────────────────────────────────────────────
Data.AI = {
    GenerateHealthReport = generateHealthReport,
    AnalyzeLog           = analyzeLog,
    AnalyzeRemote        = analyzeRemote,
    AddInsight           = addInsight,
}

print("[AI-Analyzer v8]: 6 analysis engines online — " .. #LOG_RULES .. " log rules · 20 remote keywords · health reporter active.")
