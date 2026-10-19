--[[
table-widths.lua — Pandoc Lua filter that widens LaTeX table columns to fit
their longest word.

For a pipe table with a line wider than 72 characters, pandoc sets each
column's width from the length of its dash line. LaTeX keeps those widths, so
a narrow column can be too narrow for a word in it. That word then runs into
the next column. This filter estimates the width of the longest word in each
column. A column that is too narrow gets that width, taken from the columns
with room to spare.

When the longest words of all columns together don't fit, the filter first
sets the table in a smaller font: `\small`, then `\footnotesize`. When even
that doesn't fit, it prints a warning. The column widths then follow the
longest words, so any overlap is spread over all columns.

The width of a word is estimated from its characters, since a filter cannot
measure text. Inline code counts as monospace. A word may break at a space,
after a hyphen, and at a LaTeX `\allowbreak`, which `code-breaks.lua` adds.
Run this filter after that one.

It needs the text width as metadata, e.g. 170mm for A4 with 2cm margins:
  pandoc -L code-breaks.lua -L table-widths.lua -M table-text-width=170mm input.md -o output.pdf

The filter only changes LaTeX output, and only tables with relative column
widths. Without `table-text-width` it does nothing.
]]

--- Estimated character widths in em for Latin Modern, LaTeX's default font.
local UPPER_EM = 0.72
local LOWER_EM = 0.5
local OTHER_EM = 0.4
local MONO_EM = 0.53

--- LaTeX's default space between columns, on each side of a column, in pt.
local TABCOLSEP_PT = 6

--- Extra room on top of the estimated word width, for estimation errors.
local SAFETY = 1.05

--- The smaller fonts to try, with their size relative to the normal font.
local SMALLER_FONTS = {
  { command = "\\small", scale = 0.9 },
  { command = "\\footnotesize", scale = 0.8 },
}

--- Points per unit of length.
local PT_PER_UNIT = { pt = 1, mm = 72 / 25.4, cm = 720 / 25.4, ["in"] = 72 }

--- Returns a length such as `170mm` in pt, or nil when it is not a length.
local function to_pt(length)
  local number, unit = length:match("^%s*([%d.]+)%s*(%a+)%s*$")
  if not number or not PT_PER_UNIT[unit] then
    return nil
  end
  return tonumber(number) * PT_PER_UNIT[unit]
end

--- Returns the estimated width of text in em.
local function text_em(text, mono)
  local em = 0
  for _, code in utf8.codes(text) do
    local char = utf8.char(code)
    if mono then
      em = em + MONO_EM
    elseif char:match("%u") then
      em = em + UPPER_EM
    elseif char:match("[%l%d]") then
      em = em + LOWER_EM
    else
      em = em + OTHER_EM
    end
  end
  return em
end

--- Returns the estimated width in em of the longest unbreakable word in a cell.
local function longest_word_em(cell)
  local longest, current = 0, 0
  local function finish_word()
    longest = math.max(longest, current)
    current = 0
  end
  local function add_text(text, mono)
    -- A hyphen in normal text is a break opportunity after it. A hyphen
    -- between digits, as in a date, counts as part of the word, so the column
    -- gets wide enough to keep such a number whole.
    local parts = { text }
    if not mono then
      parts = {}
      local start = 1
      for position in text:gmatch("()%-") do
        local between_digits = text:sub(position - 1, position - 1):match("%d")
          and text:sub(position + 1, position + 1):match("%d")
        if not between_digits then
          table.insert(parts, text:sub(start, position))
          start = position + 1
        end
      end
      table.insert(parts, text:sub(start))
    end
    for i, part in ipairs(parts) do
      if i > 1 then
        finish_word()
      end
      current = current + text_em(part, mono)
    end
  end
  pandoc.Blocks(cell.contents):walk({
    traverse = "topdown",
    Str = function(str)
      add_text(str.text, false)
    end,
    Code = function(code)
      add_text(code.text, true)
    end,
    Space = finish_word,
    SoftBreak = finish_word,
    LineBreak = finish_word,
    RawInline = function(raw)
      if raw.format == "latex" and raw.text:match("\\allowbreak") then
        finish_word()
      end
    end,
    Block = function()
      finish_word()
    end,
  })
  finish_word()
  return longest
end

--- Returns all cells of a table, grouped per column.
local function cells_per_column(tbl)
  local columns = {}
  for i = 1, #tbl.colspecs do
    columns[i] = {}
  end
  local function add_rows(rows)
    for _, row in ipairs(rows) do
      local column = 1
      for _, cell in ipairs(row.cells) do
        -- A cell that spans columns counts for none of them.
        if cell.col_span == 1 and columns[column] then
          table.insert(columns[column], cell)
        end
        column = column + cell.col_span
      end
    end
  end
  add_rows(tbl.head.rows)
  for _, body in ipairs(tbl.bodies) do
    add_rows(body.head)
    add_rows(body.body)
  end
  add_rows(tbl.foot.rows)
  return columns
end

--- Returns the column widths that give each column at least its minimum width,
--- taking the difference from the columns with room to spare.
--- Returns nil when the minimum widths together exceed the line.
local function fit_widths(widths, minimums)
  local total_minimum, deficit, slack = 0, 0, 0
  for i, width in ipairs(widths) do
    total_minimum = total_minimum + minimums[i]
    if width < minimums[i] then
      deficit = deficit + minimums[i] - width
    else
      slack = slack + width - minimums[i]
    end
  end
  if total_minimum > 1 then
    return nil
  end
  local fitted = {}
  for i, width in ipairs(widths) do
    if width < minimums[i] then
      fitted[i] = minimums[i]
    elseif slack > 0 then
      fitted[i] = width - deficit * (width - minimums[i]) / slack
    else
      fitted[i] = width
    end
  end
  return fitted
end

--- Returns a table's header row as text, to name the table in a warning.
local function table_name(tbl)
  local row = tbl.head.rows[1]
  if not row then
    return "without a header"
  end
  local names = {}
  for _, cell in ipairs(row.cells) do
    table.insert(names, pandoc.utils.stringify(cell.contents))
  end
  return "'" .. table.concat(names, " | ") .. "'"
end

--- Returns the column widths of a table as a list, or nil when a column
--- has no relative width.
local function relative_widths(tbl)
  local widths = {}
  for i, colspec in ipairs(tbl.colspecs) do
    local width = colspec[2]
    if type(width) ~= "number" then
      return nil
    end
    widths[i] = width
  end
  return widths
end

--- Returns the table with its column widths set, wrapped in a smaller font
--- when needed.
local function fit_table(tbl, text_width_pt, font_pt)
  local widths = relative_widths(tbl)
  if not widths then
    return nil
  end
  -- The same space pandoc subtracts from the line before applying the widths.
  local available_pt = text_width_pt - 2 * (#widths - 1) * TABCOLSEP_PT
  local word_pt = {}
  for i, cells in ipairs(cells_per_column(tbl)) do
    local em = 0
    for _, cell in ipairs(cells) do
      em = math.max(em, longest_word_em(cell))
    end
    word_pt[i] = em * font_pt * SAFETY
  end

  local function minimums_at(scale)
    local minimums = {}
    for i, pt in ipairs(word_pt) do
      minimums[i] = pt * scale / available_pt
    end
    return minimums
  end

  local function with_widths(fitted, font_command)
    for i, width in ipairs(fitted) do
      tbl.colspecs[i][2] = width
    end
    if not font_command then
      return tbl
    end
    return {
      pandoc.RawBlock("latex", "\\begingroup" .. font_command),
      tbl,
      pandoc.RawBlock("latex", "\\endgroup"),
    }
  end

  local fitted = fit_widths(widths, minimums_at(1))
  if fitted then
    return with_widths(fitted, nil)
  end
  for _, font in ipairs(SMALLER_FONTS) do
    fitted = fit_widths(widths, minimums_at(font.scale))
    if fitted then
      return with_widths(fitted, font.command)
    end
  end

  local smallest = SMALLER_FONTS[#SMALLER_FONTS]
  local minimums = minimums_at(smallest.scale)
  local total = 0
  for _, minimum in ipairs(minimums) do
    total = total + minimum
  end
  for i, minimum in ipairs(minimums) do
    minimums[i] = minimum / total
  end
  io.stderr:write("[table-widths.lua] WARNING: table " .. table_name(tbl)
    .. " is too wide for the page, its columns may overlap\n")
  return with_widths(minimums, smallest.command)
end

function Pandoc(doc)
  if not FORMAT:match("latex") then
    return nil
  end
  local text_width = doc.meta["table-text-width"]
  local text_width_pt = text_width and to_pt(pandoc.utils.stringify(text_width))
  if not text_width_pt then
    return nil
  end
  local font_size = doc.meta["fontsize"]
  local font_pt = font_size and to_pt(pandoc.utils.stringify(font_size)) or 10
  return doc:walk({
    Table = function(tbl)
      return fit_table(tbl, text_width_pt, font_pt)
    end,
  })
end
