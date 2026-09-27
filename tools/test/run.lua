-- run.lua
-- Runs every LoadoutPlanner test. From the repository root:
--     lua tools/test/run.lua
-- (Any Lua 5.1 or newer works: lua5.1, lua5.4, ... WoW itself uses 5.1.)
--
-- Each test runs in its own Lua process, so one test's fake globals can't
-- leak into the next. Exit code 0 = everything passed.

local lua = arg[-1] or "lua" -- the interpreter running this script

if not io.open("LoadoutPlanner.toc") then
    print("Run this from the repository root (the folder with LoadoutPlanner.toc).")
    os.exit(2)
end

-- os.execute returns a number in Lua 5.1 and (true/nil, "exit", code) in 5.2+.
local function run(command)
    io.stdout:flush() -- print our lines before the child process prints its own
    local a, _, c = os.execute(command)
    if type(a) == "number" then return a == 0 end
    return a == true and (c == nil or c == 0)
end

-- 1. Every Lua file in the addon compiles (catches typos first).
package.path = "tools/test/?.lua;" .. package.path
local wow = require("wow")
local files = wow.tocFiles()
local syntaxOK = true
for _, file in ipairs(files) do
    local chunk, err = loadfile(file)
    if not chunk then
        print("SYNTAX ERROR: " .. err)
        syntaxOK = false
    end
end
print((syntaxOK and "ok  " or "FAIL") .. "  syntax of " .. #files .. " files")

-- 2. The test files.
local tests = {
    "tools/test/test_load.lua modern",
    "tools/test/test_load.lua fallback",
    "tools/test/test_load.lua missing",
    "tools/test/test_topbuilds.lua",
}
local failed = syntaxOK and 0 or 1
for _, test in ipairs(tests) do
    print("")
    if not run(('"%s" %s'):format(lua, test)) then
        failed = failed + 1
        print("FAILED: " .. test)
    end
end

print("")
print(failed == 0 and "All tests passed." or (failed .. " test run(s) failed."))
os.exit(failed == 0 and 0 or 1)
