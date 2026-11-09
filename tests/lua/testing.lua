--[[
testing.lua — a minimal test helper for the filter tests, run with pandoc lua.

A test file loads it, declares its tests with test(), and ends with done(), which exits with status
1 when a test failed:

  local t = require("testing")
  t.test("does something", function()
    t.eq(1 + 1, 2, "the sum")
  end)
  t.done()

Each test prints "ok" or "not ok" with its name, as in TAP. A failing check stops its test and
prints what it expected and what it got.
]]

local M = {}

--- Number of tests run, and number of tests failed.
local run, failed = 0, 0

--- Path of the repository's lua-filter folder, found from the test file that pandoc lua runs
--- (arg[0]), which is in tests/lua.
M.filter_dir = pandoc.path.join({
  pandoc.path.directory(pandoc.path.directory(pandoc.path.directory(arg[0]))),
  "lua-filter",
})

--- Runs one test, and reports whether all its checks passed.
function M.test(name, fn)
  run = run + 1
  local ok, err = pcall(fn)
  if ok then
    print("ok " .. run .. " - " .. name)
  else
    failed = failed + 1
    print("not ok " .. run .. " - " .. name)
    print("# " .. tostring(err):gsub("\n", "\n# "))
  end
end

--- Fails the current test when actual differs from expected.
function M.eq(actual, expected, what)
  if actual ~= expected then
    error(string.format("%s: expected %q, got %q", what, tostring(expected), tostring(actual)), 2)
  end
end

--- Returns the Markdown text read as a pandoc document.
function M.read(markdown)
  return pandoc.read(markdown, "markdown+gfm_auto_identifiers")
end

--- Returns the document with the named filter from lua-filter applied, as pandoc runs it for the
--- given output format (html when left out).
function M.apply(filter, doc, format)
  local env = setmetatable({ FORMAT = format or "html" }, { __index = _G })
  return pandoc.utils.run_lua_filter(doc, pandoc.path.join({ M.filter_dir, filter }), env)
end

--- Returns a short description of each block, such as "Header 1 Title" or "RawBlock html <!-- x
--- -->", to compare block lists in one check.
function M.blocks(doc)
  local descriptions = {}
  for _, block in ipairs(doc.blocks) do
    local text
    if block.t == "RawBlock" then
      text = "RawBlock " .. block.format .. " " .. block.text
    elseif block.t == "Header" then
      text = "Header " .. block.level .. " " .. pandoc.utils.stringify(block)
    else
      text = block.t .. " " .. pandoc.utils.stringify(block)
    end
    descriptions[#descriptions + 1] = text
  end
  return table.concat(descriptions, " | ")
end

--- Prints the totals, and exits with status 1 when a test failed.
function M.done()
  print("1.." .. run)
  if failed > 0 then
    print("# " .. failed .. " of " .. run .. " tests failed")
    os.exit(1)
  end
end

return M
