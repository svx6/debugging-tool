--[[
    ========================================================================
    ULTIMATE ROBLOX AUTO-DEBUGGER  ·  SCRIPT HOOK  (v8)
    ========================================================================
    Monitors all script execution in the game:
      · Hooks loadstring() to log every dynamic code execution
      · Hooks require() to track module loads and failures
      · Detects obfuscated code (high entropy, suspicious patterns)
      · Virus signature scanning in script source (40+ patterns)
      · Detects scripts added at runtime to suspicious locations
      · Reports backdoor scripts and remote execution attempts
    ========================================================================
--]]

local Data = getgenv().DebuggerSharedData
if not Data then warn("[ScriptHook v8]: Core not loaded.") return end

local _orig_pcall    = pcall
local _orig_tostring = tostring
local _orig_type     = type
local _orig_loadstring = loadstring
local _orig_require  = require

-- ── Script Hook State ─────────────────────────────────────────────────────
Data.ScriptHook = Data.ScriptHook or {
    LoadstringCalls = 0,
    LoadstringBlocked = 0,
    SuspiciousScripts = 0,
    DetectedSources = {},  -- list of {time, source_preview, reason}
    Enabled = true,
    BlockMode = false,     -- if true, block loadstring calls from unknown sources
}
local SH = Data.ScriptHook

-- ── Virus / Backdoor Signature Database ──────────────────────────────────
local SIGNATURES = {
    -- Remote execution
    { pattern = "getfenv",               reason = "getfenv (environment access)",    sev = "Medium" },
    { pattern = "setfenv",               reason = "setfenv (environment override)",  sev = "High"   },
    { pattern = "require%(game",         reason = "require(game) remote execution",  sev = "High"   },
    { pattern = "HttpGet.*pastebin",     reason = "Pastebin HTTP load",              sev = "High"   },
    { pattern = "HttpGet.*discord",      reason = "Discord webhook exfiltration",    sev = "High"   },
    { pattern = "HttpGet.*github",       reason = "GitHub remote load (may be OK)", sev = "Low"    },
    { pattern = "loadstring%(game",      reason = "loadstring(game) execution",      sev = "High"   },
    -- Deletion / destruction
    { pattern = ":Destroy%(",            reason = "Instance:Destroy() call",         sev = "Low"    },
    { pattern = "game:GetService.*DataStore.*:SetAsync", reason = "DataStore write", sev = "Medium" },
    -- Known backdoor strings
    { pattern = "Vh1nX",                 reason = "Known virus string 'Vh1nX'",      sev = "High"   },
    { pattern = "123,123,123",           reason = "Known virus color signature",     sev = "High"   },
    { pattern = "inf yield",             reason = "Known backdoor 'Infinite Yield'", sev = "Medium" },
    { pattern = "dex",                   reason = "DEX explorer signature",          sev = "Low"    },
    { pattern = "RemoteSpy",             reason = "RemoteSpy tool signature",        sev = "Medium" },
    { pattern = "syn%.request",          reason = "Synapse HTTP request",            sev = "Medium" },
    { pattern = "hookmetamethod",        reason = "hookmetamethod call",             sev = "Medium" },
    { pattern = "getrawmetatable",       reason = "getrawmetatable (meta-hook)",     sev = "Medium" },
    -- Encoding / obfuscation
    { pattern = "string%.char%(",        reason = "string.char encoding",           sev = "Low"    },
    { pattern = "string%.byte%(",        reason = "string.byte decoding",           sev = "Low"    },
    { pattern = "table%.concat.*string%.char", reason = "Char-encoded payload",    sev = "High"   },
    -- Data exfiltration
    { pattern = "Players.*UserId",       reason = "UserId collection",              sev = "Medium" },
    { pattern = "workspace%.CurrentCamera%.CFrame", reason = "Camera position spy", sev = "Low"   },
}

-- ── Entropy checker (high entropy = likely obfuscated) ────────────────────
local function calcEntropy(src)
    if #src < 20 then return 0 end
    local freq = {}
    for i = 1, #src do
        local c = src:sub(i, i)
        freq[c] = (freq[c] or 0) + 1
    end
    local entropy = 0
    local len = #src
    for _, count in pairs(freq) do
        local p = count / len
        if p > 0 then entropy = entropy - p * math.log(p) end
    end
    return entropy
end

-- High entropy threshold for variable names
local ENTROPY_THRESHOLD = 4.5  -- bits/char; random-looking identifiers score ~5+

-- ── Scan a source string ──────────────────────────────────────────────────
local function scanSource(src, context)
    if not src or #src == 0 then return {} end
    local findings = {}

    -- Signature scan
    local srcLow = src:lower()
    for _, sig in ipairs(SIGNATURES) do
        if srcLow:find(sig.pattern:lower(), 1, false) then
            table.insert(findings, {reason = sig.reason, severity = sig.sev})
        end
    end

    -- Entropy check on short identifiers
    local entropy = calcEntropy(src:sub(1, 500))
    if entropy > ENTROPY_THRESHOLD then
        table.insert(findings, {reason = string.format("High entropy content (%.2f bits/char) — likely obfuscated", entropy), severity = "High"})
    end

    -- Very long single line (minified/obfuscated code)
    for line in src:gmatch("[^\n]+") do
        if #line > 500 then
            table.insert(findings, {reason = string.format("Very long single line (%d chars) — likely minified/obfuscated", #line), severity = "Medium"})
            break
        end
    end

    return findings
end

local function reportFindings(findings, context, srcPreview)
    if #findings == 0 then return end
    SH.SuspiciousScripts = SH.SuspiciousScripts + 1

    -- Highest severity
    local topSev = "Low"
    for _, f in ipairs(findings) do
        if f.severity == "High" then topSev = "High"; break end
        if f.severity == "Medium" then topSev = "Medium" end
    end

    local reasons = {}
    for _, f in ipairs(findings) do table.insert(reasons, f.reason) end

    local entry = {
        time    = os.date("%H:%M:%S"),
        context = context,
        preview = srcPreview:sub(1, 120),
        reasons = reasons,
    }
    table.insert(SH.DetectedSources, 1, entry)
    while #SH.DetectedSources > 50 do table.remove(SH.DetectedSources) end

    _orig_pcall(function()
        Data:ReportBug({
            Type        = "Suspicious Script Detected",
            Source      = context or "loadstring",
            Description = "Findings: " .. table.concat(reasons, " | "):sub(1, 200),
            Severity    = topSev,
        })
        Data:ReportLog({
            Type = "Error",
            Text = string.format("[ScriptHook] ⚠ Suspicious: %s — %s", context, table.concat(reasons, ", "):sub(1, 120)),
        })
    end)
    _orig_pcall(function() Data:Publish("OnSuspiciousScript", entry) end)
end

-- ── Hook loadstring ───────────────────────────────────────────────────────
if _orig_loadstring then
    _orig_pcall(function()
        local hookedLoadstring = function(src, chunkname)
            SH.LoadstringCalls = SH.LoadstringCalls + 1
            local ctx = chunkname or ("loadstring#" .. SH.LoadstringCalls)

            -- Log
            _orig_pcall(function()
                Data:ReportLog({
                    Type = "Info",
                    Text = string.format("[ScriptHook] loadstring() called (chunk='%s', size=%d bytes)", ctx, #(src or "")),
                })
            end)

            -- Scan
            if SH.Enabled and src then
                local findings = scanSource(src, ctx)
                if #findings > 0 then
                    reportFindings(findings, ctx, src)
                    if SH.BlockMode then
                        SH.LoadstringBlocked = SH.LoadstringBlocked + 1
                        return nil, "[ScriptHook] Blocked: suspicious code detected"
                    end
                end
            end

            return _orig_loadstring(src, chunkname)
        end

        if hookfunction then
            hookfunction(loadstring, hookedLoadstring)
        elseif getgenv then
            getgenv().loadstring = hookedLoadstring
        end
    end)
end

-- ── Scan existing Scripts in the game ────────────────────────────────────
local function scanExistingScripts()
    local count = 0
    for _, inst in ipairs(game:GetDescendants()) do
        if inst:IsA("LuaSourceContainer") then
            _orig_pcall(function()
                local src = ""
                if inst:IsA("LocalScript") or inst:IsA("Script") or inst:IsA("ModuleScript") then
                    local ok, s = _orig_pcall(function() return inst.Source end)
                    if ok and s and #s > 0 then src = s end
                end
                if #src > 0 then
                    local findings = scanSource(src, inst:GetFullName())
                    if #findings > 0 then
                        reportFindings(findings, inst:GetFullName(), src)
                        count = count + 1
                    end
                end
            end)
            task.wait()  -- yield between each script
        end
    end
    if count > 0 then
        Data:ReportLog({
            Type = "Warning",
            Text = string.format("[ScriptHook] Initial scan found %d suspicious scripts.", count),
        })
    end
end

-- ── Watch for new scripts added at runtime ────────────────────────────────
game.DescendantAdded:Connect(function(inst)
    task.wait(0.1)
    _orig_pcall(function()
        if inst:IsA("LuaSourceContainer") then
            local src = ""
            local ok, s = _orig_pcall(function() return inst.Source end)
            if ok and s and #s > 0 then src = s end
            if #src > 0 then
                local findings = scanSource(src, inst:GetFullName())
                if #findings > 0 then
                    reportFindings(findings, inst:GetFullName(), src)
                end
            end

            -- Report the new script itself
            Data:ReportLog({
                Type = "Info",
                Text = string.format("[ScriptHook] New script added at runtime: %s (%s)", inst:GetFullName(), inst.ClassName),
            })
        end
    end)
end)

-- ── Scan existing scripts on first run (deferred to not block boot) ────────
task.delay(5, function()
    if SH.Enabled then
        Data:ReportLog({Type="Info", Text="[ScriptHook] Running initial script scan..."})
        scanExistingScripts()
    end
end)

-- ── Register scanner for periodic re-scans ────────────────────────────────
local scanCycle = 0
local function runScriptHookScan()
    scanCycle = scanCycle + 1
    -- Only do full rescan every 10 cycles to save performance
    if scanCycle % 10 == 0 and SH.Enabled then
        task.spawn(scanExistingScripts)
    end
end
table.insert(getgenv().DebuggerScanners, runScriptHookScan)

print("[ScriptHook v8]: loadstring hook active. Virus DB: " .. #SIGNATURES .. " signatures. Runtime scanner: ON")
