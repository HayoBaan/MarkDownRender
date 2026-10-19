--[[
code-breaks.lua — Pandoc Lua filter that lets inline code break across lines.

Typst, LaTeX and WeasyPrint never break inline code by themselves. A long
name such as `Class.method` or a path then runs into the next table column,
or past the page margin. This filter adds a break opportunity after each
separator in inline code: `.`, `/`, `_`, `,`, `|`, `:` and `-`. It does so in
the way of the output format:

  - LaTeX: `\allowbreak`, in all inline code except in headings. Raw LaTeX in
    a heading would also end up in the PDF bookmarks. LaTeX lets long inline
    code run off the page, also in paragraphs. In normal text, LaTeX gets a
    break opportunity after a `/` too, so e.g. `client/server` can break. Typst
    already breaks there, and WeasyPrint widens the table column instead.
  - HTML, e.g. for WeasyPrint: `<wbr>`, only in tables.
  - Typst: a zero-width space between the parts, only in tables. Typst leaves
    it out of the PDF's text, so copied text has no trace of it. Outside
    tables, Typst moves long code to a new line, which is enough there.

Other formats are left alone. LibreOffice and Word break a long word by
themselves where needed.

  pandoc -L code-breaks.lua input.md -o output.pdf
]]

--- Characters after which inline code may break, as a Lua pattern set.
local SEPARATORS = "%./_,|:%-"

--- Returns the inline that marks a break opportunity in the output format,
--- or nil for a format that needs none.
local function break_inline()
  if FORMAT:match("latex") then
    return pandoc.RawInline("latex", "\\allowbreak{}")
  elseif FORMAT:match("html") then
    return pandoc.RawInline("html", "<wbr>")
  elseif FORMAT:match("typst") then
    return pandoc.Str("\u{200B}")
  end
  return nil
end

--- Returns inline code split after each separator, with a break opportunity
--- between the parts, or nil when there is nothing to split.
--- A separator at the very end gets no break, since nothing follows it.
local function split_code(code, mark)
  local parts = {}
  for part in code.text:gmatch("[^" .. SEPARATORS .. "]*[" .. SEPARATORS .. "]?") do
    if part ~= "" then
      table.insert(parts, part)
    end
  end
  if #parts < 2 then
    return nil
  end
  -- Only the first part keeps the identifier, which must stay unique.
  local rest_attr = code.attr:clone()
  rest_attr.identifier = ""
  local inlines = pandoc.Inlines({})
  for i, part in ipairs(parts) do
    if i > 1 then
      inlines:insert(mark:clone())
    end
    inlines:insert(pandoc.Code(part, i == 1 and code.attr or rest_attr))
  end
  return inlines
end

--- Returns text split after each run of slashes, with a LaTeX break
--- opportunity between the parts, or nil when there is nothing to split.
local function split_slashes(str, mark)
  local parts = {}
  for part in str.text:gmatch("[^/]*/*") do
    if part ~= "" then
      table.insert(parts, part)
    end
  end
  if #parts < 2 then
    return nil
  end
  local inlines = pandoc.Inlines({})
  for i, part in ipairs(parts) do
    if i > 1 then
      inlines:insert(mark:clone())
    end
    inlines:insert(pandoc.Str(part))
  end
  return inlines
end

function Pandoc(doc)
  local mark = break_inline()
  if not mark then
    return nil
  end
  local code_filter = {
    Code = function(code)
      return split_code(code, mark)
    end,
  }
  if FORMAT:match("latex") then
    return doc:walk({
      traverse = "topdown",
      Header = function(header)
        return header, false
      end,
      Code = code_filter.Code,
      Str = function(str)
        return split_slashes(str, mark)
      end,
    })
  end
  return doc:walk({
    Table = function(tbl)
      return tbl:walk(code_filter)
    end,
  })
end
