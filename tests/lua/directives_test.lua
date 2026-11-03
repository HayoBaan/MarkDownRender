--[[
directives_test.lua — tests of directives.lua.

Covered:
  - lang directive: sets the document language and disappears; the first one
    counts; YAML metadata wins over it.
  - page break: the newpage directive and a \newpage line, as the raw code of
    each writer, and nothing for a writer without page breaks.
  - other comments: left alone, except that comments before the first level-1
    heading move to just after it, in their order. Not when other text, or a
    lower-level heading, comes first.

Usage:
  pandoc lua tests/lua/directives_test.lua
]]

package.path = pandoc.path.directory(arg[0]) .. "/?.lua;" .. package.path
local t = require("testing")

--- Returns the Markdown with the directives filter applied for the format.
local function directives(markdown, format)
  return t.apply("directives.lua", t.read(markdown), format)
end

t.test("a lang directive sets the language and disappears", function()
  local doc = directives("<!-- lang: nl -->\n\nTekst\n")
  t.eq(pandoc.utils.stringify(doc.meta.lang), "nl", "the language")
  t.eq(t.blocks(doc), "Para Tekst", "the blocks")
end)

t.test("the first lang directive counts", function()
  local doc = directives("<!-- lang: de -->\n\nText\n\n<!-- lang: fr -->\n")
  t.eq(pandoc.utils.stringify(doc.meta.lang), "de", "the language")
  t.eq(t.blocks(doc), "Para Text", "both directives disappear")
end)

t.test("YAML metadata wins over a lang directive", function()
  local doc = directives("---\nlang: en-GB\n---\n\n<!-- lang: nl -->\n\nText\n")
  t.eq(pandoc.utils.stringify(doc.meta.lang), "en-GB", "the language")
end)

t.test("a page break becomes the raw code of each writer", function()
  local expected = {
    html = "RawBlock html <div style=\"break-before: page\"></div>",
    latex = "RawBlock latex \\newpage",
    typst = "RawBlock typst #pagebreak()",
    docx = "RawBlock openxml <w:p><w:r><w:br w:type=\"page\"/></w:r></w:p>",
    odt = "RawBlock opendocument <text:p text:style-name=\"Pagebreak\"/>",
  }
  for format, block in pairs(expected) do
    t.eq(t.blocks(directives("<!-- newpage -->\n", format)), block, "the directive for " .. format)
    t.eq(t.blocks(directives("\\newpage\n", format)), block, "\\newpage for " .. format)
  end
end)

t.test("a page break disappears for a writer without page breaks", function()
  t.eq(t.blocks(directives("A\n\n<!-- newpage -->\n\nB\n", "markdown")), "Para A | Para B", "the blocks")
end)

t.test("another comment is left alone", function()
  local doc = directives("Text\n\n<!-- a note -->\n\nMore\n")
  t.eq(t.blocks(doc), "Para Text | RawBlock html <!-- a note --> | Para More", "the blocks")
end)

t.test("comments before the first level-1 heading move to just after it", function()
  local doc = directives("<!-- lang: nl -->\n<!-- one -->\n\n<!-- two -->\n\n# Title\n\nText\n\n# Other\n")
  t.eq(t.blocks(doc),
    "Header 1 Title | RawBlock html <!-- one --> | RawBlock html <!-- two --> | Para Text | Header 1 Other",
    "the blocks")
end)

t.test("comments stay when other text comes before the heading", function()
  local doc = directives("<!-- note -->\n\nIntro\n\n# Title\n")
  t.eq(t.blocks(doc), "RawBlock html <!-- note --> | Para Intro | Header 1 Title", "the blocks")
end)

t.test("comments stay before a lower-level heading", function()
  local doc = directives("<!-- note -->\n\n## Part\n\n# Title\n")
  t.eq(t.blocks(doc), "RawBlock html <!-- note --> | Header 2 Part | Header 1 Title", "the blocks")
end)

t.done()
