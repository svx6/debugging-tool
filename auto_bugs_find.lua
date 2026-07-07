--[[
    ========================================================================
    ANTIGRAVITY AUTO-DEBUGGER  ·  ENTRY POINT (v7)
    ========================================================================
    Run this file in your executor to launch the full debugger suite.
    This file auto-detects the correct loader and delegates to main.lua.
    ========================================================================
--]]

local function tryLoad(name)
    if loadfile then
        local ok, fn = pcall(loadfile, name)
        if ok and type(fn) == "function" then
            local runOk, err = pcall(fn)
            if runOk then return true end
            warn("[Debugger] Error in main.lua: " .. tostring(err))
            return false
        end
    end
    if readfile and loadstring then
        local ok, src = pcall(readfile, name)
        if ok and type(src) == "string" and #src > 0 then
            local fn, err = loadstring(src, "@main.lua")
            if fn then
                local runOk, runErr = pcall(fn)
                if runOk then return true end
                warn("[Debugger] Error in main.lua: " .. tostring(runErr))
                return false
            end
            warn("[Debugger] Compile error: " .. tostring(err))
            return false
        end
    end
    if dofile then
        local ok, err = pcall(dofile, name)
        if ok then return true end
        warn("[Debugger] dofile error: " .. tostring(err))
    end
    return false
end

warn("[Debugger]: Launching via entry point → main.lua")
tryLoad("main.lua")
