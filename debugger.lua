--[[
    ========================================================================
    ULTIMATE ROBLOX AUTO-DEBUGGER - REDIRECTOR
    ========================================================================
    Author: Antigravity
    Description: Redirects executions of legacy debugger.lua to main.lua
                 orchestrator.
    ========================================================================
--]]

warn("[Debugger]: debugger.lua has been modularized and is deprecated. Loading main.lua orchestrator...")

local function runMain()
    if loadfile then
        local ok, func = pcall(loadfile, "main.lua")
        if ok and func then
            return func()
        end
    end
    
    if readfile and loadstring then
        local ok, content = pcall(readfile, "main.lua")
        if ok and content then
            local func, err = loadstring(content)
            if func then
                return func()
            end
        end
    end
    
    warn("[Debugger - Redirector]: Failed to load main.lua bootstrapper.")
end

runMain()
