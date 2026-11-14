"""Fills in the table of contents of a DOCX or ODT document with LibreOffice, for mdrender.

Pandoc writes a table of contents for DOCX as a Word field, and for ODT as an index. Both are empty
until a word processor updates them. LibreOffice doesn't update them when it converts a document on
the command line. This LibreOffice Python macro does:

- In mode `pdf`, it updates the indexes of a document and exports it as PDF.
- In mode `fill`, it updates the indexes and saves a copy in the same format. Then it copies only
  the tables of contents from that copy into the original document. The rest of the document stays
  as pandoc wrote it. LibreOffice would otherwise add direct formatting, such as fonts and spacing,
  which overrides the styles of the reference document.

The entries in the copy link to bookmarks that LibreOffice adds to the headings. Each heading also
keeps the bookmark of the original, so the links are pointed at that one. The styles the entries use
are copied along when the original lacks them. For DOCX, the TOC styles are the exception: they get
the definition of Word's built-in ones instead, as LibreOffice's spread the entries out. In DOCX,
the field stays marked dirty, so Word updates the page numbers to its own layout when it opens the
document.

mdrender copies this file into the Scripts/python folder of a temporary LibreOffice profile. It
passes the mode and files in environment variables, because a macro URL has no arguments:

- `MDRENDER_TOC_MODE`: `pdf` or `fill`
- `MDRENDER_TOC_INPUT`: the document
- `MDRENDER_TOC_OUTPUT`: the PDF, or the filled document

Usage:

    soffice --headless 'vnd.sun.star.script:toc_update.py$update?language=Python&location=user'

The functions that copy the tables of contents work on XML text, without LibreOffice, so plain
Python can test them.
"""

import os
import re
import shutil
import tempfile
import zipfile

# LibreOffice's export filter for each file extension
FILTERS = {".docx": "MS Word 2007 XML", ".odt": "writer8", ".pdf": "writer_pdf_Export"}

# The prefix of the bookmarks LibreOffice adds to headings for its table of contents
REF_HEADING = "__RefHeading"

# The prefix for the automatic styles copied into an ODT, so they can't clash with its own
ODT_STYLE_PREFIX = "mdrender_toc_"

DOCX_PARAGRAPH = re.compile(r"<w:p[ >].*?</w:p>", re.S)
DOCX_BOOKMARK = re.compile(r'<w:bookmarkStart\b[^>]*\bw:name="([^"]+)"')
DOCX_TOC_STYLE = re.compile(r"^TOC[1-9]$")
DOCX_FIELD_BEGIN = re.compile(r'<w:fldChar w:fldCharType="begin"[^>]*?(/>|>\s*</w:fldChar>)')
ODT_HEADING = re.compile(r"<text:h\b.*?</text:h>", re.S)
ODT_BOOKMARK = re.compile(r'<text:bookmark-start\b[^>]*\btext:name="([^"]+)"')
ODT_TOC = re.compile(r"<text:table-of-content\b.*?</text:table-of-content>", re.S)
ODT_INDEX_BODY = re.compile(r"<text:index-body\s*/>|<text:index-body>.*?</text:index-body>", re.S)
ODT_INDEX_TITLE = re.compile(r"<text:index-title\b.*?</text:index-title>", re.S)


def heading_bookmarks(paragraphs, bookmark):
    """Maps the bookmarks LibreOffice added to headings to the bookmarks they already had.

    Args:
        paragraphs: the XML text of each paragraph or heading of LibreOffice's copy.
        bookmark: the pattern that finds the name of each bookmark in a paragraph.

    Returns:
        For each paragraph with both kinds of bookmark, LibreOffice's name mapped to the other one.
    """
    mapping = {}
    for paragraph in paragraphs:
        names = bookmark.findall(paragraph)
        own = [name for name in names if not name.startswith(REF_HEADING)]
        for name in names:
            if name.startswith(REF_HEADING) and own:
                mapping[name] = own[0]
    return mapping


def relink(xml, attribute, mapping):
    """Returns the XML with each link to a bookmark in the mapping pointed at its replacement.

    Args:
        xml: the XML text.
        attribute: the attribute that holds the link, with a # before the name or not.
        mapping: the bookmark names to replace, and their replacements.
    """
    def replace(match):
        hash_mark, name = match.group(2), match.group(3)
        return match.group(1) + hash_mark + mapping.get(name, name) + '"'

    return re.sub(r'(\b%s=")(#?)([^"]+)"' % re.escape(attribute), replace, xml)


def docx_fields(document):
    """Returns the position of each table of contents field: from the start of its first paragraph
    to the end of the paragraph with the end of the field.

    Args:
        document: the text of word/document.xml.
    """
    fields = []
    for instruction in re.finditer(r"<w:instrText\b[^>]*>\s*TOC\b", document):
        start = max(document.rfind("<w:p>", 0, instruction.start()),
                    document.rfind("<w:p ", 0, instruction.start()))
        end_mark = document.find('w:fldCharType="end"', instruction.end())
        if start < 0 or end_mark < 0:
            continue
        fields.append((start, document.find("</w:p>", end_mark) + len("</w:p>")))
    return fields


def docx_style(styles, style_id):
    """Returns the definition of a style in word/styles.xml, or None."""
    match = re.search(r'<w:style\b[^>]*\bw:styleId="%s".*?</w:style>' % re.escape(style_id),
                      styles, re.S)
    return match.group(0) if match else None


def missing_styles(names, source, target, find, parent):
    """Returns the definitions of the styles that the target lacks, with the styles they are based on.

    Args:
        names: the names of the styles in use.
        source: the styles text to copy definitions from.
        target: the styles text to copy them to.
        find: returns the definition of a named style in a styles text, or None.
        parent: the pattern that finds the name of the style a definition is based on.

    Returns:
        The definitions to add, each style once.
    """
    added, definitions = set(), []
    pending = list(names)
    while pending:
        name = pending.pop(0)
        if name in added or find(target, name) is not None:
            continue
        definition = find(source, name)
        if definition is None:
            continue
        added.add(name)
        definitions.append(definition)
        pending.extend(parent.findall(definition))
    return definitions


def word_toc_style(level):
    """Returns the paragraph style for one level of a Word table of contents, as Word defines it.

    Like Word's built-in style, it is based on Normal, with 5 pt after, and 12 pt more indent per
    level.

    LibreOffice's own styles inherit the spacing after every paragraph that pandoc's reference
    document sets, 10 pt, which spreads the entries out. Word keeps a style the document defines
    when it updates the table of contents, so it would keep that spacing too.

    Args:
        level: the level, from 1 to 9.
    """
    indent = "" if level == 1 else '<w:ind w:left="%d"/>' % (240 * (level - 1))
    return ('<w:style w:type="paragraph" w:styleId="TOC%d"><w:name w:val="toc %d"/>'
            '<w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:autoRedefine/>'
            '<w:uiPriority w:val="39"/><w:unhideWhenUsed/>'
            '<w:pPr><w:spacing w:after="100"/>%s</w:pPr></w:style>') % (level, level, indent)


def splice_docx(document, styles, filled_document, filled_styles):
    """Copies the tables of contents of LibreOffice's copy of a DOCX into the original.

    Args:
        document: word/document.xml of the original.
        styles: word/styles.xml of the original.
        filled_document: word/document.xml of LibreOffice's copy.
        filled_styles: word/styles.xml of LibreOffice's copy.

    Returns:
        The new document.xml and styles.xml of the original.
    """
    mapping = heading_bookmarks(DOCX_PARAGRAPH.findall(filled_document), DOCX_BOOKMARK)
    filled = [filled_document[start:end] for start, end in docx_fields(filled_document)]
    used = set()
    result, position = [], 0
    for (start, end), toc in zip(docx_fields(document), filled):
        toc = relink(toc, "w:anchor", mapping)
        # Word updates a dirty field when it opens the document, with its own page numbers.
        toc = DOCX_FIELD_BEGIN.sub('<w:fldChar w:fldCharType="begin" w:dirty="true"/>', toc, count=1)
        used.update(re.findall(r'w:(?:pStyle|rStyle) w:val="([^"]+)"', toc))
        result.extend([document[position:start], toc])
        position = end
    result.append(document[position:])
    toc_levels = [name for name in sorted(used) if DOCX_TOC_STYLE.match(name)]
    added = [word_toc_style(int(name[3:])) for name in toc_levels if docx_style(styles, name) is None]
    added += missing_styles([name for name in sorted(used) if name not in toc_levels], filled_styles,
                            styles, docx_style, re.compile(r'<w:basedOn w:val="([^"]+)"'))
    if added:
        styles = styles.replace("</w:styles>", "".join(added) + "</w:styles>")
    return "".join(result), styles


def odt_style(styles, name):
    """Returns the definition of a style in an ODT styles text, or None."""
    match = re.search(r'<style:style\b[^>]*\bstyle:name="%s"[^>]*?(?:/>|>.*?</style:style>)'
                      % re.escape(name), styles, re.S)
    return match.group(0) if match else None


def splice_odt(content, styles, filled_content, filled_styles):
    """Copies the tables of contents of LibreOffice's copy of an ODT into the original.

    Args:
        content: content.xml of the original.
        styles: styles.xml of the original.
        filled_content: content.xml of LibreOffice's copy.
        filled_styles: styles.xml of LibreOffice's copy.

    Returns:
        The new content.xml and styles.xml of the original.
    """
    mapping = heading_bookmarks(ODT_HEADING.findall(filled_content), ODT_BOOKMARK)
    bodies = []
    for toc in ODT_TOC.findall(filled_content):
        body = ODT_INDEX_BODY.search(toc)
        inner = ""
        if body and not body.group(0).endswith("/>"):
            inner = body.group(0)[len("<text:index-body>"):-len("</text:index-body>")]
        bodies.append(ODT_INDEX_TITLE.sub("", relink(inner, "xlink:href", mapping)))

    automatic, renamed, common = [], set(), set()

    def rename(match):
        name = match.group(2)
        definition = odt_style(filled_content, name)
        if definition is None:
            common.add(name)
            return match.group(0)
        new_name = ODT_STYLE_PREFIX + name
        if name not in renamed:
            renamed.add(name)
            automatic.append(definition.replace('style:name="%s"' % name,
                                                'style:name="%s"' % new_name, 1))
            common.update(re.findall(r'style:parent-style-name="([^"]+)"', definition))
        return match.group(1) + new_name + '"'

    result, position, index = [], 0, 0
    for toc in ODT_TOC.finditer(content):
        if index >= len(bodies):
            break
        body = re.sub(r'(\btext:(?:visited-)?style-name=")([^"]+)"', rename, bodies[index])
        index += 1
        new_toc = ODT_INDEX_BODY.sub(lambda _: "<text:index-body>" + body + "</text:index-body>",
                                     toc.group(0), count=1)
        result.extend([content[position:toc.start()], new_toc])
        position = toc.end()
    result.append(content[position:])
    content = "".join(result)

    if automatic:
        if "<office:automatic-styles/>" in content:
            content = content.replace("<office:automatic-styles/>",
                                      "<office:automatic-styles></office:automatic-styles>", 1)
        content = content.replace("</office:automatic-styles>",
                                  "".join(automatic) + "</office:automatic-styles>", 1)
    added = missing_styles(sorted(common), filled_styles, styles, odt_style,
                           re.compile(r'style:parent-style-name="([^"]+)"'))
    if added:
        styles = styles.replace("</office:styles>", "".join(added) + "</office:styles>", 1)
    return content, styles


def replace_members(source_path, target_path, replacements):
    """Writes a copy of a zip file with some members replaced, keeping the order and compression of
    all. ODT needs its mimetype member first and uncompressed, so nothing else about the file
    changes. The copy appears at once, complete, so a failure leaves no partial file behind.

    Args:
        source_path: the zip file.
        target_path: the copy to write. It may be the zip file itself.
        replacements: the new text of each member to replace, by name.
    """
    handle, temporary = tempfile.mkstemp(suffix=os.path.splitext(target_path)[1],
                                         dir=os.path.dirname(os.path.abspath(target_path)))
    os.close(handle)
    try:
        with zipfile.ZipFile(source_path) as source, zipfile.ZipFile(temporary, "w") as target:
            for info in source.infolist():
                data = source.read(info)
                if info.filename in replacements:
                    data = replacements[info.filename].encode("utf-8")
                target.writestr(info, data)
        shutil.move(temporary, target_path)
    finally:
        if os.path.exists(temporary):
            os.remove(temporary)


def splice(original, filled, output):
    """Writes the original document with the tables of contents of LibreOffice's filled copy.

    Args:
        original: the document as pandoc wrote it.
        filled: LibreOffice's copy, with its tables of contents filled in.
        output: the document to write. It may be the original itself.
    """
    if os.path.splitext(original)[1].lower() == ".docx":
        names, splicer = ("word/document.xml", "word/styles.xml"), splice_docx
    else:
        names, splicer = ("content.xml", "styles.xml"), splice_odt
    with zipfile.ZipFile(original) as source, zipfile.ZipFile(filled) as copy:
        texts = [source.read(name).decode("utf-8") for name in names]
        texts += [copy.read(name).decode("utf-8") for name in names]
    main, styles = splicer(*texts)
    replace_members(original, output, {names[0]: main, names[1]: styles})


def _property(name, value):
    """Returns a UNO PropertyValue."""
    from com.sun.star.beans import PropertyValue  # pylint: disable=import-error,import-outside-toplevel

    prop = PropertyValue()
    prop.Name, prop.Value = name, value
    return prop


def _store(doc, path):
    """Stores a LibreOffice document in the format its file extension names."""
    import uno  # pylint: disable=import-error,import-outside-toplevel

    extension = os.path.splitext(path)[1].lower()
    doc.storeToURL(uno.systemPathToFileUrl(os.path.abspath(path)),
                   (_property("FilterName", FILTERS[extension]),))


def update(*_args):
    """The macro: updates the indexes of the input, and writes the output for the mode."""
    import uno  # pylint: disable=import-error,import-outside-toplevel

    mode = os.environ["MDRENDER_TOC_MODE"]
    source = os.environ["MDRENDER_TOC_INPUT"]
    output = os.environ["MDRENDER_TOC_OUTPUT"]
    desktop = XSCRIPTCONTEXT.getDesktop()  # noqa: F821 — LibreOffice provides it to a macro
    doc = desktop.loadComponentFromURL(uno.systemPathToFileUrl(os.path.abspath(source)), "_blank", 0,
                                       (_property("Hidden", True),))
    try:
        indexes = doc.getDocumentIndexes()
        for i in range(indexes.getCount()):
            indexes.getByIndex(i).update()
        if mode == "pdf":
            _store(doc, output)
            return
        directory = tempfile.mkdtemp()
        filled = os.path.join(directory, "filled" + os.path.splitext(source)[1])
        _store(doc, filled)
    finally:
        doc.close(True)
    try:
        splice(source, filled, output)
    finally:
        shutil.rmtree(directory, ignore_errors=True)


# Only the macro can be run from LibreOffice.
g_exportedScripts = (update,)
