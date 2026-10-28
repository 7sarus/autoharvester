local _G = rawget(_G, "GLOBAL") or _G
local print = _G.print or print
local tostring = _G.tostring or tostring
local string = _G.string or string
local debug = _G.debug or debug
local type = _G.type or type
local xpcall = _G.xpcall or xpcall

local Logger = {
    LEVELS = { DEBUG = 1, INFO = 2, WARN = 3, ERROR = 4 },
    current_level = 1,
    prefix = "[WX_HARVESTER]",
}

local LEVEL_NAMES = { [1] = "DEBUG", [2] = "INFO", [3] = "WARN", [4] = "ERROR" }

function Logger.SetLevel(level)
    if type(level) == "string" then
        level = Logger.LEVELS[level:upper()]
    end
    Logger.current_level = tonumber(level) or 2
end

function Logger.Log(level_num, tag, fmt, ...)
    if level_num < Logger.current_level then return end
    local msg = (select("#", ...) > 0) and string.format(fmt, ...) or tostring(fmt)
    print(string.format("%s [%s] [%s] %s", Logger.prefix, LEVEL_NAMES[level_num] or "LOG", tag or "CORE", msg))
end

function Logger.Debug(tag, fmt, ...) Logger.Log(1, tag, fmt, ...) end
function Logger.Info(tag, fmt, ...) Logger.Log(2, tag, fmt, ...) end
function Logger.Warn(tag, fmt, ...) Logger.Log(3, tag, fmt, ...) end
function Logger.Error(tag, fmt, ...)
    Logger.Log(4, tag, fmt, ...)
    if debug and debug.traceback then print(debug.traceback()) end
end

function Logger.SafeCall(tag, fn, ...)
    local args = { ... }
    return xpcall(function() return fn(unpack(args)) end, function(err)
        Logger.Error(tag, "Exception: %s", tostring(err))
        return err
    end)
end

return Logger
