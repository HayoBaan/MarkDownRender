--[[
table_widths_test.lua — tests of table-widths.lua, for DOCX and ODT.

Covered, for tables read without column widths, as mdrender reads them with --columns=10000:
  - a table that fits on one line gets the width of its lines, so it is narrower than the page.
  - a wider table fills the page. Each column is at least as wide as its longest word, and the room
    that is left goes to the columns with longer lines.
  - a table whose longest words don't fit gets a warning, and columns in proportion to those words.
  - a date counts as one word.
  - a table with column widths keeps them, and without table-text-width, or for HTML, nothing
    changes.
  - the font size comes from fontsize, which changes the widths.

Usage:
  pandoc lua tests/lua/table_widths_test.lua
]]

package.path = pandoc.path.directory(arg[0]) .. "/?.lua;" .. package.path
local t = require("testing")

--- The metadata mdrender passes: the text width of A4 with 2cm margins.
local META = "---\ntable-text-width: 170mm\n---\n\n"

--- Returns the column widths after the filter ran for the format, as numbers or "default", and what
--- the filter wrote to stderr. The Markdown is read without a line limit, as mdrender does.
local function widths(markdown, format)
  local io_stand_in, stderr = t.capture_stderr()
  local doc = pandoc.read(markdown, "markdown", { columns = 10000 })
  doc = t.apply("table-widths.lua", doc, format or "docx", { io = io_stand_in })
  local result = {}
  for _, block in ipairs(doc.blocks) do
    if block.t == "Table" then
      for i, colspec in ipairs(block.colspecs) do
        result[i] = type(colspec[2]) == "number" and colspec[2] or "default"
      end
    end
  end
  return result, stderr()
end

--- Returns the sum of the widths.
local function sum(list)
  local total = 0
  for _, width in ipairs(list) do
    total = total + width
  end
  return total
end

local NARROW = "| Datum | Auteur | Betreft |\n|---|---|---|\n| 2026-11-13 | Hayo Baan | Advies (concept) |\n"

local WIDE = "| Key | Description |\n|---|---|\n| a | " .. string.rep("word ", 60) .. "|\n| b | short |\n"

t.test("a table that fits gets the width of its lines", function()
  local result, stderr = widths(META .. NARROW)
  t.eq(#result, 3, "the columns")
  t.eq(sum(result) < 1, true, "a table narrower than the page")
  t.eq(result[3] > result[1] and result[1] > 0.08, true, "the longest column widest, a date whole")
  t.eq(stderr, "", "the warnings")
end)

t.test("a wider table fills the page, with each column at least its longest word", function()
  local result = widths(META .. WIDE)
  t.eq(math.abs(sum(result) - 1) < 1e-9, true, "the table as wide as the page")
  t.eq(result[1] > 0.03 and result[1] < 0.1, true, "the key column as wide as its word")
  t.eq(result[2] > 0.9, true, "the rest for the description")
end)

t.test("a table whose longest words don't fit gets a warning", function()
  local long_word = string.rep("x", 120)
  local result, stderr = widths(META .. "| A | B |\n|---|---|\n| " .. long_word .. " | " .. long_word .. " |\n")
  t.eq(math.abs(sum(result) - 1) < 1e-9, true, "the table as wide as the page")
  t.eq(math.abs(result[1] - result[2]) < 1e-9, true, "columns in proportion to their words")
  t.eq(stderr, "[table-widths.lua] WARNING: table 'A | B' is too wide for the page, words in its"
    .. " columns may break\n", "the warning")
end)

t.test("ODT gets the same widths as DOCX", function()
  local docx, odt = widths(META .. NARROW, "docx"), widths(META .. NARROW, "odt")
  for i = 1, 3 do
    t.eq(odt[i], docx[i], "the width of column " .. i)
  end
end)

t.test("a larger font gives wider columns", function()
  local normal = widths(META .. NARROW)
  local large = widths("---\ntable-text-width: 170mm\nfontsize: 16pt\n---\n\n" .. NARROW)
  t.eq(large[3] > normal[3], true, "the widest column")
end)

t.test("a table with column widths keeps them", function()
  local grid = "+-----+------------+\n| A   | B          |\n+=====+============+\n| a   | b          |\n+-----+------------+\n"
  local before = widths(grid, "html")
  local after = widths(META .. grid)
  t.eq(type(before[1]), "number", "the grid table has widths")
  t.eq(after[1], before[1], "the first width")
  t.eq(after[2], before[2], "the second width")
end)

t.test("without table-text-width, or for HTML, nothing changes", function()
  t.eq(widths(NARROW)[1], "default", "without table-text-width")
  t.eq(widths(META .. NARROW, "html")[1], "default", "for HTML")
end)

t.done()
