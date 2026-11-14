"""Tests of toc_update.py: copying LibreOffice's tables of contents into pandoc's DOCX and ODT.

Covered, without LibreOffice, on XML in the shape pandoc and LibreOffice write it:

- bookmarks: LibreOffice's heading bookmarks map to the original ones, and links follow them.
- DOCX: the empty field is replaced by the filled one, which links to the original bookmarks and
  stays dirty. Missing styles are added, with the styles they are based on. Missing TOC styles get
  Word's definition instead of LibreOffice's, and TOC styles of the reference document stay. Other
  fields and the rest of the document stay as they are.
- ODT: the empty index body is filled, without a title, and links to the original bookmarks. Its
  automatic styles are copied under new names, also into an empty automatic styles element, and
  missing common styles are added with their parents.
- zip files: the copy keeps the order and compression of every member, ODT's mimetype included, and
  a document is spliced as a whole.

Usage:
    python3 -m unittest discover -s tests/python
"""

import os
import sys
import tempfile
import unittest
import zipfile

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "libreoffice"))

import toc_update  # noqa: E402

# DOCX as pandoc writes it with toc.lua: an empty field, with its end in a paragraph of its own
DOCX = ('<w:body><w:p><w:r><w:t>Intro</w:t></w:r></w:p>'
        '<w:sdt><w:sdtContent><w:p><w:r><w:fldChar w:fldCharType="begin" w:dirty="true"/>'
        '<w:instrText xml:space="preserve">TOC \\o "1-6" \\h \\z \\u</w:instrText>'
        '<w:fldChar w:fldCharType="separate"/></w:r></w:p>'
        '<w:p><w:r><w:fldChar w:fldCharType="end"/></w:r></w:p></w:sdtContent></w:sdt>'
        '<w:p><w:pPr><w:pStyle w:val="Heading1"/></w:pPr><w:bookmarkStart w:id="1" w:name="_part"/>'
        '<w:r><w:t>Part</w:t></w:r><w:bookmarkEnd w:id="1"/></w:p>'
        '<w:p><w:r><w:fldChar w:fldCharType="begin"/><w:instrText>PAGE</w:instrText>'
        '<w:fldChar w:fldCharType="end"/></w:r></w:p></w:body>')

# LibreOffice's copy: the field filled in, with links to its own bookmarks
FILLED_DOCX = ('<w:body><w:p><w:r><w:t>Intro</w:t></w:r></w:p>'
               '<w:sdt><w:sdtContent><w:p><w:pPr><w:pStyle w:val="TOC1"/></w:pPr>'
               '<w:r><w:fldChar w:fldCharType="begin"></w:fldChar></w:r>'
               '<w:r><w:instrText xml:space="preserve"> TOC \\z \\o "1-6" \\u \\h</w:instrText></w:r>'
               '<w:r><w:fldChar w:fldCharType="separate"/></w:r>'
               '<w:hyperlink w:anchor="__RefHeading___Toc13_1"><w:r><w:rPr><w:rStyle w:val="IndexLink"/>'
               '</w:rPr><w:t>Part</w:t><w:tab/><w:t>1</w:t></w:r></w:hyperlink>'
               '<w:r><w:fldChar w:fldCharType="end"/></w:r></w:p></w:sdtContent></w:sdt>'
               '<w:p><w:pPr><w:pStyle w:val="Heading1"/></w:pPr>'
               '<w:bookmarkStart w:id="0" w:name="__RefHeading___Toc13_1"/>'
               '<w:bookmarkStart w:id="1" w:name="_part"/><w:r><w:t>Part</w:t></w:r></w:p></w:body>')

DOCX_STYLES = ('<w:styles><w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="heading 1"/>'
               '</w:style></w:styles>')
FILLED_DOCX_STYLES = ('<w:styles><w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="LO"/>'
                      '</w:style><w:style w:type="paragraph" w:styleId="Index"><w:name w:val="Index"/>'
                      '</w:style><w:style w:type="paragraph" w:styleId="TOC1"><w:name w:val="toc 1"/>'
                      '<w:basedOn w:val="Index"/></w:style><w:style w:type="character" '
                      'w:styleId="IndexLink"><w:name w:val="Index Link"/></w:style></w:styles>')

# ODT as pandoc writes it with toc.lua: an empty index body
ODT = ('<office:document-content><office:automatic-styles><style:style style:name="P1" '
       'style:family="paragraph"/></office:automatic-styles><office:body><office:text>'
       '<text:table-of-content><text:table-of-content-source text:outline-level="6"/>'
       '<text:index-body/></text:table-of-content>'
       '<text:h text:outline-level="1"><text:bookmark-start text:name="part" />Part'
       '<text:bookmark-end text:name="part" /></text:h></office:text></office:body>'
       '</office:document-content>')

# LibreOffice's copy: the index body filled in, with a title and links to its own bookmarks
FILLED_ODT = ('<office:document-content><office:automatic-styles>'
              '<style:style style:name="P1" style:family="paragraph" '
              'style:parent-style-name="Contents_20_1"><style:tab-stops/></style:style>'
              '<style:style style:name="P10" style:family="paragraph" '
              'style:parent-style-name="Contents_20_2"><style:tab-stops/></style:style>'
              '</office:automatic-styles><office:body><office:text>'
              '<text:table-of-content text:name="Table of Contents1">'
              '<text:table-of-content-source text:outline-level="6"/><text:index-body>'
              '<text:index-title text:name="Head"><text:p>Table of Contents</text:p></text:index-title>'
              '<text:p text:style-name="P1"><text:a xlink:href="#__RefHeading___Toc29_1" '
              'text:style-name="Internet_20_link">Part</text:a><text:tab/>1</text:p>'
              '<text:p text:style-name="P10"><text:a xlink:href="#__RefHeading___Toc31_1" '
              'text:style-name="Internet_20_link">Detail</text:a><text:tab/>1</text:p>'
              '</text:index-body></text:table-of-content>'
              '<text:h text:outline-level="1"><text:bookmark-start text:name="part"/>'
              '<text:bookmark-start text:name="__RefHeading___Toc29_1"/>Part</text:h>'
              '<text:h text:outline-level="2"><text:bookmark-start text:name="detail"/>'
              '<text:bookmark-start text:name="__RefHeading___Toc31_1"/>Detail</text:h>'
              '</office:text></office:body></office:document-content>')

ODT_STYLES = ('<office:styles><style:style style:name="Index" style:family="paragraph"/>'
              '<style:style style:name="Internet_20_link" style:family="text"/></office:styles>')
FILLED_ODT_STYLES = ('<office:styles><style:style style:name="Index" style:family="paragraph" '
                     'style:class="lo"/><style:style style:name="Contents_20_1" style:family="paragraph" '
                     'style:parent-style-name="Index"><style:tab-stops/></style:style>'
                     '<style:style style:name="Contents_20_2" style:family="paragraph" '
                     'style:parent-style-name="Contents_20_1"/></office:styles>')


class BookmarkTest(unittest.TestCase):
    """LibreOffice's heading bookmarks, and the links to them."""

    def test_maps_libreoffice_bookmarks_to_the_original_ones(self):
        paragraphs = toc_update.DOCX_PARAGRAPH.findall(FILLED_DOCX)
        self.assertEqual(toc_update.heading_bookmarks(paragraphs, toc_update.DOCX_BOOKMARK),
                         {"__RefHeading___Toc13_1": "_part"})

    def test_relinks_with_and_without_hash(self):
        mapping = {"a": "b"}
        self.assertEqual(toc_update.relink('<x w:anchor="a"/><x w:anchor="c"/>', "w:anchor", mapping),
                         '<x w:anchor="b"/><x w:anchor="c"/>')
        self.assertEqual(toc_update.relink('<x xlink:href="#a"/>', "xlink:href", mapping), '<x xlink:href="#b"/>')


class DocxTest(unittest.TestCase):
    """Copying the table of contents field of a DOCX."""

    def setUp(self):
        self.document, self.styles = toc_update.splice_docx(DOCX, DOCX_STYLES, FILLED_DOCX, FILLED_DOCX_STYLES)

    def test_finds_only_table_of_contents_fields(self):
        (start, end), = toc_update.docx_fields(DOCX)
        self.assertTrue(DOCX[start:end].startswith("<w:p><w:r><w:fldChar"))
        self.assertTrue(DOCX[start:end].endswith('<w:fldChar w:fldCharType="end"/></w:r></w:p>'))

    def test_fills_the_field_with_links_to_the_original_bookmarks(self):
        self.assertIn('<w:hyperlink w:anchor="_part">', self.document)
        self.assertNotIn("__RefHeading", self.document)
        self.assertIn("<w:t>Part</w:t><w:tab/><w:t>1</w:t>", self.document)

    def test_keeps_the_field_dirty(self):
        self.assertIn('<w:fldChar w:fldCharType="begin" w:dirty="true"/><', self.document)
        self.assertNotIn("</w:fldChar>", self.document)

    def test_leaves_the_rest_of_the_document_alone(self):
        self.assertTrue(self.document.startswith("<w:body><w:p><w:r><w:t>Intro</w:t></w:r></w:p><w:sdt>"))
        self.assertIn('<w:bookmarkStart w:id="1" w:name="_part"/>', self.document)
        self.assertIn("<w:instrText>PAGE</w:instrText>", self.document)

    def test_adds_missing_styles_with_their_base_styles(self):
        self.assertEqual(self.styles.count('w:styleId="Heading1"'), 1)
        self.assertIn('<w:name w:val="heading 1"/>', self.styles)
        self.assertIn('w:styleId="IndexLink"', self.styles)
        self.assertTrue(self.styles.endswith("</w:style></w:styles>"))

    def test_adds_word_toc_styles_instead_of_libreoffice_ones(self):
        """LibreOffice's TOC styles inherit pandoc's 10 pt after each paragraph, Word's set 5 pt."""
        toc1 = toc_update.docx_style(self.styles, "TOC1")
        self.assertIn('<w:basedOn w:val="Normal"/>', toc1)
        self.assertIn('<w:spacing w:after="100"/>', toc1)
        self.assertNotIn('w:styleId="Index"', self.styles)

    def test_indents_each_deeper_toc_level(self):
        self.assertNotIn("<w:ind ", toc_update.word_toc_style(1))
        self.assertIn('<w:ind w:left="240"/>', toc_update.word_toc_style(2))
        self.assertIn('<w:ind w:left="480"/>', toc_update.word_toc_style(3))

    def test_keeps_toc_styles_of_the_reference_document(self):
        own = '<w:style w:type="paragraph" w:styleId="TOC1"><w:name w:val="toc 1"/><w:pPr/></w:style>'
        _, styles = toc_update.splice_docx(DOCX, DOCX_STYLES.replace("</w:styles>", own + "</w:styles>"),
                                           FILLED_DOCX, FILLED_DOCX_STYLES)
        self.assertEqual(styles.count('w:styleId="TOC1"'), 1)
        self.assertIn(own, styles)


class OdtTest(unittest.TestCase):
    """Copying the table of contents index of an ODT."""

    def setUp(self):
        self.content, self.styles = toc_update.splice_odt(ODT, ODT_STYLES, FILLED_ODT, FILLED_ODT_STYLES)

    def test_fills_the_index_body_without_a_title(self):
        self.assertIn("<text:index-body><text:p ", self.content)
        self.assertNotIn("Table of Contents", self.content)
        self.assertNotIn("<text:index-body/>", self.content)

    def test_links_to_the_original_bookmarks(self):
        self.assertIn('xlink:href="#part"', self.content)
        self.assertIn('xlink:href="#detail"', self.content)
        self.assertNotIn("__RefHeading", self.content)

    def test_copies_automatic_styles_under_new_names(self):
        self.assertIn('<style:style style:name="P1" style:family="paragraph"/>', self.content)
        self.assertIn('<text:p text:style-name="mdrender_toc_P1">', self.content)
        self.assertIn('<text:p text:style-name="mdrender_toc_P10">', self.content)
        self.assertEqual(self.content.count('style:name="mdrender_toc_P1"'), 1)
        self.assertEqual(self.content.count('style:name="mdrender_toc_P10"'), 1)

    def test_copies_into_an_empty_automatic_styles_element(self):
        content, _ = toc_update.splice_odt(
            ODT.replace('<office:automatic-styles><style:style style:name="P1" style:family="paragraph"/>'
                        '</office:automatic-styles>', "<office:automatic-styles/>"),
            ODT_STYLES, FILLED_ODT, FILLED_ODT_STYLES)
        self.assertIn('<office:automatic-styles><style:style style:name="mdrender_toc_P1"', content)

    def test_adds_missing_common_styles_with_their_parents(self):
        self.assertIn('style:name="Contents_20_1"', self.styles)
        self.assertIn('style:name="Contents_20_2"', self.styles)
        self.assertEqual(self.styles.count('style:name="Index"'), 1)
        self.assertNotIn('style:class="lo"', self.styles)


class ZipTest(unittest.TestCase):
    """Rewriting the zip files of documents."""

    def write(self, path, members):
        with zipfile.ZipFile(path, "w") as archive:
            for name, data, compression in members:
                archive.writestr(zipfile.ZipInfo(name), data, compress_type=compression)

    def test_keeps_order_and_compression(self):
        with tempfile.TemporaryDirectory() as directory:
            source, target = os.path.join(directory, "a.odt"), os.path.join(directory, "b.odt")
            self.write(source, [("mimetype", "application/vnd.oasis.opendocument.text", zipfile.ZIP_STORED),
                                ("content.xml", "old", zipfile.ZIP_DEFLATED)])
            toc_update.replace_members(source, target, {"content.xml": "new"})
            with zipfile.ZipFile(target) as archive:
                self.assertEqual([(i.filename, i.compress_type) for i in archive.infolist()],
                                 [("mimetype", zipfile.ZIP_STORED), ("content.xml", zipfile.ZIP_DEFLATED)])
                self.assertEqual(archive.read("content.xml"), b"new")
            with zipfile.ZipFile(source) as archive:
                self.assertEqual(archive.read("content.xml"), b"old")
            self.assertEqual(sorted(os.listdir(directory)), ["a.odt", "b.odt"])

    def test_splices_a_docx(self):
        with tempfile.TemporaryDirectory() as directory:
            original, filled = os.path.join(directory, "a.docx"), os.path.join(directory, "b.docx")
            self.write(original, [("word/document.xml", DOCX, zipfile.ZIP_DEFLATED),
                                  ("word/styles.xml", DOCX_STYLES, zipfile.ZIP_DEFLATED)])
            self.write(filled, [("word/document.xml", FILLED_DOCX, zipfile.ZIP_DEFLATED),
                                ("word/styles.xml", FILLED_DOCX_STYLES, zipfile.ZIP_DEFLATED)])
            toc_update.splice(original, filled, original)
            with zipfile.ZipFile(original) as archive:
                self.assertIn('w:anchor="_part"', archive.read("word/document.xml").decode())
                self.assertIn('w:styleId="TOC1"', archive.read("word/styles.xml").decode())


if __name__ == "__main__":
    unittest.main()
