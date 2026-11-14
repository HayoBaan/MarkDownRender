--[=[
toc.lua — Pandoc Lua filter for table of contents markers, as GitLab and IntelliJ IDEA write them.

A paragraph that holds only a marker becomes a table of contents:

  [[_TOC_]]
  [TOC]

Letter case doesn't matter. A marker inside a sentence, a list, or a code block stays as it is. Only
a top-level paragraph counts, as in GitLab. In a document without headings, the marker disappears.

A list between two <!-- TOC --> lines, as IntelliJ IDEA writes it, is replaced by a fresh table of
contents. So an outdated list in the document can't end up in the output, nor a link to a missing
anchor. When the entries differ, the filter prints a warning. An entry is its nesting level, its
text, and its link, so a change in layout or whitespace alone gives no warning. The document file
itself stays as it is. A single <!-- TOC --> line, without a second one, is left alone.

The table of contents covers every heading level, and leaves out a heading with the class unlisted.
Each writer gets its own kind, so formats with pages show page numbers:
  - Typst: #outline(), without a title.
  - LaTeX: the contents list of \tableofcontents, without its heading. An unlisted heading also gets
    the class unnumbered, as LaTeX only leaves an unnumbered heading out.
  - DOCX: a TOC field that Word fills in when it updates the fields.
  - ODT: a table of contents index that LibreOffice fills in when it updates the indexes.
  - HTML: a nested list of links in a div with the class toc. CSS can add page numbers for
    WeasyPrint.
  - Others: a nested list of links.
DOCX and ODT can't leave out an unlisted heading: their table of contents lists every heading.

The DOCX field and the ODT index are empty in pandoc's output. mdrender fills them in with
LibreOffice, see toc_update.py.

With the metadata field toc-skip-title set, level-1 headings are left out. mdrender sets it when it
makes a sole level-1 heading the document title with --shift-heading-level-by=-1. Filters run before
that shift, so the title is still a heading here. As the title, it gets no anchor to link to.

Usage:
  pandoc -L toc.lua input.md -o output.html
  pandoc -L toc.lua -M toc-skip-title=true --shift-heading-level-by=-1 input.md -o output.pdf
]=]

--- The deepest heading level in the table of contents: all of them, as in GitLab.
local TOC_DEPTH = 6

--- The contents list of \tableofcontents, without the heading that \tableofcontents adds. Level 5
--- is \subparagraph, the deepest level LaTeX lists.
local LATEX_TOC = "\\setcounter{tocdepth}{5}\n\\makeatletter\\@starttoc{toc}\\makeatother"

--- A Word TOC field for heading levels 1 to 6, as pandoc writes it for --toc. Its switches: \h
--- links the entries, \z hides page numbers in web view, and \u also lists paragraphs with an
--- outline level. The field is marked dirty, so Word offers to update it when it opens the
--- document. Its end is in a paragraph of its own: LibreOffice ignores a field whose end directly
--- follows its separator.
local DOCX_TOC = '<w:sdt><w:sdtPr><w:docPartObj><w:docPartGallery w:val="Table of Contents"/>'
    .. '</w:docPartObj></w:sdtPr><w:sdtContent><w:p><w:r>'
    .. '<w:fldChar w:fldCharType="begin" w:dirty="true"/>'
    .. '<w:instrText xml:space="preserve">TOC \\o "1-' .. TOC_DEPTH .. '" \\h \\z \\u</w:instrText>'
    .. '<w:fldChar w:fldCharType="separate"/></w:r></w:p>'
    .. '<w:p><w:r><w:fldChar w:fldCharType="end"/></w:r></w:p></w:sdtContent></w:sdt>'

--- Returns an ODT table of contents index for heading levels 1 to 6, as pandoc writes it for --toc,
--- without a title. Each entry links its text and page number to the heading. The links have
--- LibreOffice's Index Link style, as in its own table of contents. Pandoc uses Internet Link,
--- which makes the entries blue and underlined, unlike in DOCX and PDF.
local function odt_toc()
  local templates = {}
  for level = 1, TOC_DEPTH do
    templates[#templates + 1] = string.format(
      '<text:table-of-content-entry-template text:outline-level="%d" text:style-name="Contents_20_%d">'
        .. '<text:index-entry-link-start text:style-name="Index_20_Link"/>'
        .. '<text:index-entry-chapter/><text:index-entry-text/><text:index-entry-link-end/>'
        .. '<text:index-entry-tab-stop style:type="right" style:leader-char="."/>'
        .. '<text:index-entry-link-start text:style-name="Index_20_Link"/>'
        .. '<text:index-entry-page-number/><text:index-entry-link-end/>'
        .. '</text:table-of-content-entry-template>', level, level)
  end
  -- An empty title template: without it, LibreOffice adds its own title.
  return '<text:table-of-content><text:table-of-content-source text:outline-level="' .. TOC_DEPTH
      .. '"><text:index-title-template text:style-name="Contents_20_Heading"/>'
      .. table.concat(templates) .. '</text:table-of-content-source>'
      .. '<text:index-body/></text:table-of-content>'
end

--- Returns the table of contents for the current writer, given the list of links that pandoc made.
local function native_toc(list)
  if FORMAT == "typst" then
    return pandoc.RawBlock("typst", "#outline(title: none, depth: " .. TOC_DEPTH .. ")")
  elseif FORMAT == "latex" then
    return pandoc.RawBlock("latex", LATEX_TOC)
  elseif FORMAT == "docx" then
    return pandoc.RawBlock("openxml", DOCX_TOC)
  elseif FORMAT == "odt" then
    return pandoc.RawBlock("opendocument", odt_toc())
  elseif FORMAT:match("^html") then
    return pandoc.Div({ list }, pandoc.Attr("", { "toc" }))
  end
  return list
end

--- Succeeds for a paragraph that holds only a marker. Pandoc reads [[_TOC_]] as "[[", the word TOC
--- in emphasis, and "]]", and [TOC] as a single string.
local function is_marker(para)
  local content = para.content
  if #content == 1 and content[1].t == "Str" then
    return content[1].text:upper() == "[TOC]"
  end
  return #content == 3
      and content[1].t == "Str" and content[1].text == "[["
      and content[2].t == "Emph" and pandoc.utils.stringify(content[2]):upper() == "TOC"
      and content[3].t == "Str" and content[3].text == "]]"
end

--- Succeeds for a <!-- TOC --> comment, as a raw block or a raw inline.
local function is_comment_marker(raw)
  return raw.format == "html" and raw.text:match("^%s*<!%-%- TOC %-%->%s*$") ~= nil
end

--- Succeeds for a list that holds the closing <!-- TOC --> comment. Without a blank line between
--- them, pandoc reads that comment as part of the list's last item.
local function holds_comment_marker(list)
  local found = false
  list:walk({
    RawInline = function(raw)
      found = found or is_comment_marker(raw)
    end,
  })
  return found
end

--- Returns the entries of a table of contents as text, one line per entry: its nesting level, its
--- text with whitespace collapsed, and its link. Returns an empty string for no list.
local function entries(list)
  local lines = {}
  local function add(bullets, level)
    for _, item in ipairs(bullets.content) do
      for _, block in ipairs(item) do
        if block.t == "BulletList" then
          add(block, level + 1)
        elseif block.t == "Plain" or block.t == "Para" then
          for _, inline in ipairs(block.content) do
            if inline.t == "Link" then
              local text = pandoc.utils.stringify(inline):gsub("%s+", " ")
              lines[#lines + 1] = level .. " " .. text .. " " .. inline.target
              break
            end
          end
        end
      end
    end
  end
  if list then
    add(list, 1)
  end
  return table.concat(lines, "\n")
end

--- Returns the name of the input, for a warning.
local function input_name()
  local files = PANDOC_STATE and PANDOC_STATE.input_files or {}
  return files[1] or "stdin"
end

--- Returns how many blocks a <!-- TOC --> pair at position i takes up, and the list between the
--- comments, or nil. Returns 0 when the comment at i doesn't start a pair.
local function comment_pair(blocks, i)
  local next_block, after = blocks[i + 1], blocks[i + 2]
  if next_block and next_block.t == "RawBlock" and is_comment_marker(next_block) then
    return 2, nil
  end
  if next_block and next_block.t == "BulletList" then
    if after and after.t == "RawBlock" and is_comment_marker(after) then
      return 3, next_block
    end
    if holds_comment_marker(next_block) then
      return 2, next_block
    end
  end
  return 0, nil
end

--- Returns an unlisted heading with the class unnumbered added, or nil for another heading. LaTeX
--- only leaves a heading out of its table of contents when it is unnumbered as well.
local function unnumber_unlisted(header)
  if header.classes:includes("unlisted") and not header.classes:includes("unnumbered") then
    header.classes:insert("unnumbered")
    return header
  end
  return nil
end

--- Returns the headings the table of contents lists. Without level-1 headings when the title is
--- skipped.
local function listed_blocks(doc)
  if not doc.meta["toc-skip-title"] then
    return doc.blocks
  end
  return doc.blocks:filter(function(block)
    return not (block.t == "Header" and block.level == 1)
  end)
end

function Pandoc(doc)
  local toc = pandoc.structure.table_of_contents(listed_blocks(doc), { toc_depth = TOC_DEPTH })
  local blocks = pandoc.Blocks({})
  local i = 1
  while i <= #doc.blocks do
    local block = doc.blocks[i]
    -- The number of blocks the table of contents replaces, 0 for none.
    local taken = 0
    if block.t == "Para" and is_marker(block) then
      taken = 1
    elseif block.t == "RawBlock" and is_comment_marker(block) then
      local old
      taken, old = comment_pair(doc.blocks, i)
      if taken > 0 and entries(old) ~= entries(toc) then
        io.stderr:write("[toc.lua] WARNING: " .. input_name()
          .. ": the table of contents between the <!-- TOC --> lines is out of date,"
          .. " the output uses an updated one\n")
      end
    end
    if taken == 0 then
      blocks:insert(block)
      i = i + 1
    else
      -- Without headings, the table of contents is empty, and the marker just disappears.
      if #toc.content > 0 then
        blocks:insert(native_toc(toc:clone()))
      end
      i = i + taken
    end
  end
  doc.blocks = blocks
  if FORMAT == "latex" then
    doc.blocks = doc.blocks:walk({ Header = unnumber_unlisted })
  end
  return doc
end
