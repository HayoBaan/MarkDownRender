--[=[
toc_test.lua — tests of toc.lua.

Covered:
  - markers: [[_TOC_]] and [TOC], in any letter case, become a nested list of links to the headings.
  - markers that don't count: inside a sentence, in a list, in a code block, and [[TOC]] without the
    emphasis.
  - levels: every level is listed, and an unlisted heading is left out.
  - title: with toc-skip-title, level-1 headings are left out. Without it, they are listed.
  - several markers each get the list, and without headings a marker disappears.
  - <!-- TOC --> pairs: the list between them is replaced, with or without blank lines, and an empty
    pair is filled. An outdated list gives a warning, a change in layout alone doesn't. A single
    comment, or a pair around something else than a list, stays.
  - writers: Typst gets #outline() and LaTeX the list of \tableofcontents. DOCX gets a dirty TOC
    field, and ODT an empty index for every level. HTML gets the list in a div with the class toc,
    and other writers the plain list. Without headings, none of them gets anything.
  - LaTeX: an unlisted heading also gets the class unnumbered.
  The list tests use the markdown writer, which gets the plain list.

Usage:
  pandoc lua tests/lua/toc_test.lua
]=]

package.path = pandoc.path.directory(arg[0]) .. "/?.lua;" .. package.path
local t = require("testing")

--- Returns the Markdown with the toc filter applied, and what the filter wrote to stderr. The
--- format is markdown when left out, which gets the plain list of links.
local function toc(markdown, format)
  local io_stand_in, stderr = t.capture_stderr()
  return t.apply("toc.lua", t.read(markdown), format or "markdown", { io = io_stand_in }), stderr()
end

--- Returns the document's blocks written as Markdown, to compare a list with its nesting and links.
local function markdown(doc)
  return pandoc.write(pandoc.Pandoc(doc.blocks), "markdown"):gsub("{#toc%-[%w%-]+}", "")
end

local HEADINGS = "## Part one\n\n### Detail\n\n## Part two\n"
local LIST = "- [Part one](#part-one)\n  - [Detail](#detail)\n- [Part two](#part-two)\n"

t.test("[[_TOC_]] becomes a list of links to the headings", function()
  t.eq(markdown(toc("[[_TOC_]]\n\n" .. HEADINGS)), LIST .. "\n" .. HEADINGS, "the document")
end)

t.test("[TOC] becomes a list of links to the headings", function()
  t.eq(markdown(toc("[TOC]\n\n" .. HEADINGS)), LIST .. "\n" .. HEADINGS, "the document")
end)

t.test("letter case doesn't matter", function()
  for _, marker in ipairs({ "[[_toc_]]", "[toc]", "[Toc]" }) do
    t.eq(t.blocks(toc(marker .. "\n\n## A\n")), "BulletList A | Header 2 A", "the blocks for " .. marker)
  end
end)

t.test("a marker that isn't a paragraph of its own stays", function()
  local cases = {
    ["Text [TOC] here\n\n## A\n"] = "Para Text [TOC] here | Header 2 A",
    ["- [TOC]\n\n## A\n"] = "BulletList [TOC] | Header 2 A",
    ["[[TOC]]\n\n## A\n"] = "Para [[TOC]] | Header 2 A",
  }
  for input, expected in pairs(cases) do
    t.eq(t.blocks(toc(input)), expected, "the blocks for " .. input)
  end
  -- stringify gives no text for a code block, so its text is checked on its own.
  local code = toc("```\n[TOC]\n```\n\n## A\n").blocks[1]
  t.eq(code.t .. " " .. code.text, "CodeBlock [TOC]", "the code block")
end)

t.test("every heading level is listed", function()
  local doc = toc("[TOC]\n\n## A\n\n### B\n\n#### C\n\n##### D\n\n###### E\n")
  t.eq(markdown(doc):match("^(.-)\n\n"),
    "- [A](#a)\n  - [B](#b)\n    - [C](#c)\n      - [D](#d)\n        - [E](#e)", "the list")
end)

t.test("an unlisted heading is left out", function()
  local doc = toc("[TOC]\n\n## A\n\n## B {.unlisted}\n")
  t.eq(markdown(doc):match("^(.-)\n\n"), "- [A](#a)", "the list")
end)

t.test("with toc-skip-title, the level-1 heading is left out", function()
  local doc = toc("---\ntoc-skip-title: true\n---\n\n# Title\n\n[TOC]\n\n" .. HEADINGS)
  t.eq(markdown(doc), "# Title\n\n" .. LIST .. "\n" .. HEADINGS, "the document")
end)

t.test("without toc-skip-title, the level-1 heading is listed", function()
  local doc = toc("# Title\n\n[TOC]\n\n## A\n")
  t.eq(markdown(doc):match("%[TOC%]") == nil and markdown(doc):match("\n\n(.-)\n\n"),
    "- [Title](#title)\n  - [A](#a)", "the list")
end)

t.test("each marker gets the list", function()
  t.eq(t.blocks(toc("[TOC]\n\n## A\n\n[[_TOC_]]\n")), "BulletList A | Header 2 A | BulletList A", "the blocks")
end)

t.test("without headings, the marker disappears", function()
  t.eq(t.blocks(toc("Text\n\n[TOC]\n")), "Para Text", "the blocks")
end)

--- An up-to-date list between <!-- TOC --> lines, as IntelliJ IDEA writes it: without blank lines,
--- so pandoc reads the closing comment as part of the last item.
local INTELLIJ = "<!-- TOC -->\n* [Part one](#part-one)\n  * [Detail](#detail)\n* [Part two](#part-two)\n"
    .. "<!-- TOC -->\n\n"

t.test("an up-to-date <!-- TOC --> list is replaced, without a warning", function()
  local doc, stderr = toc(INTELLIJ .. HEADINGS)
  t.eq(markdown(doc), LIST .. "\n" .. HEADINGS, "the document")
  t.eq(stderr, "", "the warnings")
end)

t.test("a <!-- TOC --> list with blank lines is replaced too", function()
  local doc, stderr = toc("<!-- TOC -->\n\n- [Part one](#part-one)\n  - [Detail](#detail)\n"
    .. "- [Part two](#part-two)\n\n<!-- TOC -->\n\n" .. HEADINGS)
  t.eq(markdown(doc), LIST .. "\n" .. HEADINGS, "the document")
  t.eq(stderr, "", "the warnings")
end)

t.test("a change in layout or whitespace alone gives no warning", function()
  local _, stderr = toc("<!-- TOC -->\n+   [Part   one](#part-one)\n\n    - [Detail](#detail)\n\n"
    .. "+ [Part two](#part-two)\n<!-- TOC -->\n\n" .. HEADINGS)
  t.eq(stderr, "", "the warnings")
end)

t.test("an outdated <!-- TOC --> list is replaced, with a warning", function()
  local cases = {
    "a changed text", "<!-- TOC -->\n* [Part 1](#part-one)\n  * [Detail](#detail)\n* [Part two](#part-two)\n",
    "a wrong link", "<!-- TOC -->\n* [Part one](#part-1)\n  * [Detail](#detail)\n* [Part two](#part-two)\n",
    "a missing entry", "<!-- TOC -->\n* [Part one](#part-one)\n* [Part two](#part-two)\n",
    "a wrong level", "<!-- TOC -->\n* [Part one](#part-one)\n* [Detail](#detail)\n* [Part two](#part-two)\n",
  }
  for i = 1, #cases, 2 do
    local doc, stderr = toc(cases[i + 1] .. "<!-- TOC -->\n\n" .. HEADINGS)
    t.eq(markdown(doc), LIST .. "\n" .. HEADINGS, "the document with " .. cases[i])
    t.eq(stderr, "[toc.lua] WARNING: stdin: the table of contents between the <!-- TOC --> lines is"
      .. " out of date, the output uses an updated one\n", "the warning for " .. cases[i])
  end
end)

t.test("an empty <!-- TOC --> pair is filled, with a warning", function()
  local doc, stderr = toc("<!-- TOC -->\n<!-- TOC -->\n\n" .. HEADINGS)
  t.eq(markdown(doc), LIST .. "\n" .. HEADINGS, "the document")
  t.eq(stderr ~= "", true, "a warning")
end)

t.test("a single <!-- TOC --> comment stays", function()
  local doc, stderr = toc("<!-- TOC -->\n\n## A\n")
  t.eq(t.blocks(doc), "RawBlock html <!-- TOC --> | Header 2 A", "the blocks")
  t.eq(stderr, "", "the warnings")
end)

t.test("each writer gets its own kind of table of contents", function()
  local expected = {
    typst = "RawBlock typst #outline(title: none, depth: 6)",
    latex = "RawBlock latex \\setcounter{tocdepth}{5}\n\\makeatletter\\@starttoc{toc}\\makeatother",
    html = "Div A",
    html5 = "Div A",
    gfm = "BulletList A",
  }
  for format, block in pairs(expected) do
    t.eq(t.blocks(toc("[TOC]\n\n## A\n", format)), block .. " | Header 2 A", "the blocks for " .. format)
  end
  local div = toc("[TOC]\n\n## A\n", "html").blocks[1]
  t.eq(table.concat(div.classes, " "), "toc", "the class of the HTML div")
end)

t.test("DOCX gets a TOC field for every level, marked dirty", function()
  local raw = toc("[TOC]\n\n## A\n", "docx").blocks[1]
  t.eq(raw.format, "openxml", "the raw format")
  t.eq(raw.text:find('TOC \\o "1-6" \\h \\z \\u', 1, true) ~= nil, true, "the field instruction")
  t.eq(raw.text:find('w:fldCharType="begin" w:dirty="true"', 1, true) ~= nil, true, "the dirty mark")
end)

t.test("ODT gets an empty index with a template for every level", function()
  local raw = toc("[TOC]\n\n## A\n", "odt").blocks[1]
  t.eq(raw.format, "opendocument", "the raw format")
  local _, templates = raw.text:gsub("<text:table%-of%-content%-entry%-template ", "")
  t.eq(templates, 6, "the entry templates")
  t.eq(raw.text:find("Internet_20_link", 1, true), nil, "no Internet Link style, which underlines")
  local _, links = raw.text:gsub('text:style%-name="Index_20_Link"', "")
  t.eq(links, 12, "the Index Link style for the text and page number of each level")
  t.eq(raw.text:find("<text:index-body/>", 1, true) ~= nil, true, "the empty index body")
end)

t.test("without headings, no writer gets a table of contents", function()
  for _, format in ipairs({ "typst", "latex", "docx", "odt", "html" }) do
    t.eq(t.blocks(toc("Text\n\n[TOC]\n", format)), "Para Text", "the blocks for " .. format)
  end
end)

t.test("for LaTeX, an unlisted heading becomes unnumbered too", function()
  local doc = toc("## A {.unlisted}\n\n## B\n\n## C {.unlisted .unnumbered}\n", "latex")
  t.eq(table.concat(doc.blocks[1].classes, " "), "unlisted unnumbered", "the unlisted heading")
  t.eq(#doc.blocks[2].classes, 0, "the other heading")
  t.eq(table.concat(doc.blocks[3].classes, " "), "unlisted unnumbered", "the heading that has both")
  local html = toc("## A {.unlisted}\n", "html")
  t.eq(table.concat(html.blocks[1].classes, " "), "unlisted", "the heading for another writer")
end)

t.test("a <!-- TOC --> pair around something else than a list stays", function()
  local doc = toc("<!-- TOC -->\n\nText\n\n<!-- TOC -->\n\n## A\n")
  t.eq(t.blocks(doc), "RawBlock html <!-- TOC --> | Para Text | RawBlock html <!-- TOC --> | Header 2 A",
    "the blocks")
end)

t.done()
