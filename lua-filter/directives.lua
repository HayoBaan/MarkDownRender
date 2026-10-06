--[[
directives.lua — Pandoc Lua filter for directives written in the Markdown itself.

Directives are HTML comments on a line of their own, so GitHub, GitLab and other
Markdown viewers do not show them:

  <!-- lang: nl -->
      The document language, as a language code such as nl or en-GB. Used only
      when the metadata has no lang yet, so YAML metadata (lang: nl) and pandoc's
      --metadata lang=... take precedence. The first lang directive counts.

  <!-- newpage -->
      A page break. \newpage on a line of its own works too, but Markdown viewers
      show it as text.

A page break becomes the right raw code for each writer:
  - LaTeX:       \newpage
  - Typst:       #pagebreak()
  - HTML:        an empty div with break-before: page, for printing and WeasyPrint
  - DOCX:        a paragraph with a page break
  - ODT:         an empty paragraph in the style Pagebreak. Pandoc's default
                 reference document has no such style, so the reference document
                 must define it, with a page break before.
Other writers get nothing.

Usage:
  pandoc -L directives.lua input.md -o output.pdf
]]

--- Raw page break code by writer, as format and text of a raw block.
local PAGE_BREAKS = {
  latex = { "latex", "\\newpage" },
  beamer = { "latex", "\\newpage" },
  typst = { "typst", "#pagebreak()" },
  html = { "html", '<div style="break-before: page"></div>' },
  html4 = { "html", '<div style="break-before: page"></div>' },
  html5 = { "html", '<div style="break-before: page"></div>' },
  docx = { "openxml", '<w:p><w:r><w:br w:type="page"/></w:r></w:p>' },
  odt = { "opendocument", '<text:p text:style-name="Pagebreak"/>' },
}

--- Returns the text of a comment block (without <!-- and -->), or nil.
local function comment_text(block)
  if block.format ~= "html" then
    return nil
  end
  return block.text:match("^%s*<!%-%-%s*(.-)%s*%-%->%s*$")
end

--- Returns the language code of a lang directive, or nil.
local function lang_directive(block)
  local text = comment_text(block)
  return text and text:match("^lang:%s*([%w%-]+)$")
end

--- Succeeds for a page break: a newpage comment or a \newpage raw TeX block.
local function is_page_break(block)
  if block.format == "tex" or block.format == "latex" then
    return block.text:match("^%s*\\newpage%s*$") ~= nil
  end
  return comment_text(block) == "newpage"
end

--- Returns the page break for the current writer: a raw block, or an empty list.
local function page_break()
  local code = PAGE_BREAKS[FORMAT]
  if not code then
    return {}
  end
  return pandoc.RawBlock(code[1], code[2])
end

function Pandoc(doc)
  local lang = nil
  doc = doc:walk({
    RawBlock = function(block)
      local code = lang_directive(block)
      if code then
        lang = lang or code
        return {}
      end
      if is_page_break(block) then
        return page_break()
      end
      return nil
    end,
  })
  if lang and doc.meta.lang == nil then
    doc.meta.lang = pandoc.MetaString(lang)
  end
  return doc
end
