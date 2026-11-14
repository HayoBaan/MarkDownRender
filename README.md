# MarkDownRender

Render Markdown to HTML, DOCX, ODT, or PDF in one command, diagrams included.

`mdrender` is a small wrapper around [pandoc](https://pandoc.org). It adds six Lua filters and
sensible defaults:

- Diagrams become images: Mermaid and Graphviz code blocks, and draw.io files. HTML gets SVG, DOCX,
  ODT, and PDF get PNG.
- Links to other Markdown files can be rewritten to the output format, e.g. `other.md` becomes
  `other.html`.
- Directives in the document, as invisible HTML comments: the document language, and page breaks.
- A table of contents where the document says `[[_TOC_]]` or `[TOC]`, as in GitLab. A list between
  two `<!-- TOC -->` lines, as IntelliJ IDEA writes it, is brought up to date in the output. DOCX,
  ODT, and PDF get a real table of contents, with page numbers.
- Long inline code, such as a path or `Class.method`, can break across lines in PDF. It stays within
  its table column and on the page.
- With LaTeX, a table column that is too narrow for its longest word gets wider. In DOCX and ODT,
  table columns get their widths from their content.
- HTML fills the window, with a small margin. It is light by default, or dark, or follows the
  system.
- DOCX, ODT, and PDF use A4 portrait with 2 cm margins, instead of pandoc's US Letter.
- DOCX and ODT look like the PDF: a serif font, black and bold headings, centered tables, and a line
  under a table's header row.
- PDF uses the best PDF engine that is installed: Typst, LaTeX, WeasyPrint, or LibreOffice.
- A single level-1 heading becomes the document title.

The Lua filters are installed in pandoc's filters folder. `mdrender` uses them from there, and so
can any other pandoc command.

## Contents

```text
MarkDownRender/
├── bin/
│   └── mdrender          the command-line script
├── lua-filter/
│   ├── code-breaks.lua   lets long inline code break across lines
│   ├── diagram.lua       turns Mermaid, Graphviz and draw.io diagrams into images
│   ├── directives.lua    handles directives (document language, page breaks), keeps the title first
│   ├── md-links.lua      rewrites links to .md files
│   ├── table-widths.lua  fits table columns to their content for LaTeX, DOCX, and ODT
│   └── toc.lua           makes a table of contents for [[_TOC_]], [TOC], and <!-- TOC --> lists
├── libreoffice/
│   └── toc_update.py     LibreOffice macro that fills in the DOCX and ODT table of contents
├── install.manifest      what to install, and where
├── install.sh            installs the files listed in install.manifest
├── tests/
│   ├── lua/              tests of the filters, run with pandoc lua
│   ├── python/           tests of toc_update.py, run with python3
│   ├── mdrender.bats     tests of mdrender, run with Bats
│   └── run               runs all tests
├── LICENSE               the MIT License
└── README.md
```

## Requirements

- [pandoc](https://pandoc.org) 3 or later, with Lua support (`brew install pandoc`).
- For diagrams, the tool for each type you use:
  - [Mermaid CLI](https://github.com/mermaid-js/mermaid-cli) (`mmdc`): `npm install -g
    @mermaid-js/mermaid-cli`.
  - [Graphviz](https://graphviz.org) (`dot`): `brew install graphviz`.
  - [draw.io desktop](https://www.drawio.com) (`drawio`): `brew install --cask drawio`.
- `python3`, for the DOCX/ODT page setup.
- For PDF: one of the PDF engines, see [PDF engines](#pdf-engines).
- For a filled-in table of contents in DOCX and ODT: [LibreOffice](https://www.libreoffice.org)
  (`soffice`): `brew install --cask libreoffice`. See [Table of contents](#table-of-contents).

## Installation

`install.manifest` lists what to install, and where:

```text
# source          destination
bin/              $TARGET/bin/
lua-filter/*.lua  ${XDG_DATA_HOME:-~/.local/share}/pandoc/filters/
libreoffice/*.py  ${XDG_DATA_HOME:-~/.local/share}/pandoc/mdrender/
```

- `mdrender` goes to `bin` in the target root, your home directory by default. That folder must be
  on your `PATH`.
- The Lua filters go to pandoc's filters folder.
- The LibreOffice macro goes to the `mdrender` folder in pandoc's user data directory.

Install with:

```sh
./install.sh
```

The files are copied. With `--symlink` they are linked instead, so later changes in this repository
take effect without reinstalling. Running it again with or without `--symlink` switches between
links and copies. Other files with the same name are only replaced with `--force`. Use `--target`
for another target root, and `--dry-run` to only see what would happen. Run `./install.sh --help`
for all options.

The filters folder in the manifest assumes pandoc's default user data directory. Check yours with
`pandoc --version`. If it is another folder, such as `~/.pandoc`, install the filters and the macro
there by hand.

## Usage

```text
mdrender --help|-h
mdrender --version
mdrender [option...] [file.md ...] [-- extra pandoc options]

  --format|-f FORMAT    Output format: html (default), docx, odt or pdf.
  --pdf|-p              Short for --format pdf.
  --pdf-engine ENGINE   PDF engine: auto (default), typst, latex, weasyprint or
                        libreoffice. Also settable with MDRENDER_PDF_ENGINE.
  --output|-o FILE      Output file, for a single input only. "-" means stdout.
  --temp|-t             Write the output to a new temporary folder.
  --open|-O             Open each output file. For stdin input, implies --temp.
  --link-ext|-l         Rewrite relative .md links to the output extension (not for pdf).
  --no-shift            Keep heading levels as they are.
  --lang CODE           Document language, e.g. nl or en-GB.
  --nl, --de, --fr, --es, --gb
                        Short for --lang nl, de, fr, es or en-GB.
  --margin LENGTH       HTML page margin on all sides (default: 2em).
  --max-width LENGTH    HTML content width limit (default: none, full width).
  --theme THEME         HTML theme: light (default), dark or system.
  --dark                Short for --theme dark.
  --paper SIZE          docx/odt/pdf paper size: a3, a4 (default), a5, letter, legal.
  --landscape           docx/odt/pdf landscape orientation.
  --page-margin LENGTH  docx/odt/pdf page margin on all sides (default: 2cm).
  --reference-doc FILE  Style template for docx/odt, and for pdf via libreoffice.
```

Short options can be combined: `-tp` is `-t -p`. An argument can be attached: `-fodt` is `-f odt`.

Input and output:

- A file `foo.md` is written next to it as `foo.html`, `foo.docx`, `foo.odt`, or `foo.pdf`.
- Without a file, or with `-`, the input is read from stdin and written to stdout.
- `--output` sets another output location, for a single input.
- `--temp` writes the output to a new folder in `$TMPDIR` (or `/tmp`), with the same file name. Use
  it to view a document without leaving files next to it. The folder is kept, so the files can still
  be opened after `mdrender` exits.
- `--open` opens each output file in its default application: `open` on macOS, `xdg-open` elsewhere.
  Input from stdin then goes to a temporary file, as with `--temp`.
- Anything after `--` is passed to pandoc unchanged.

Examples:

```sh
# Two documents that link to each other, both to HTML.
mdrender --link-ext advice.md plan.md

# ODT on A4, and DOCX on A3 landscape.
mdrender -f odt advice.md
mdrender -f docx --paper a3 --landscape overview.md

# PDF with the best engine available, and with WeasyPrint.
mdrender -f pdf advice.md
mdrender -f pdf --pdf-engine weasyprint advice.md

# A Dutch document as PDF, with Dutch hyphenation.
mdrender -p --nl advies.md

# HTML with a dark page.
mdrender --dark notes.md

# A quick look at the PDF, without writing it next to the document.
mdrender --pdf --temp --open advice.md

# From stdin to stdout, and from stdin to a browser.
cat notes.md | mdrender > notes.html
cat notes.md | mdrender --open
```

## How it works

### Headings and title

When a document has exactly one level-1 heading, that heading becomes the document title. All other
headings move up one level. This is pandoc's `--shift-heading-level-by=-1`. The title then shows up
as the HTML `<title>`, or as the Title style in Word.

Pandoc only makes the heading the title when it's the first block. HTML comments may come before it,
such as a directive or a "generated by" notice. `directives.lua` moves them to just after the
heading. That doesn't change the output, since comments don't show. Any other text before the
heading turns it into a plain paragraph.

With zero or several level-1 headings, `mdrender` does not shift. Pandoc would otherwise turn the
extra level-1 headings into plain paragraphs. In that case `mdrender` prints a warning. Headings
inside fenced code blocks are not counted. Use `--no-shift` to never shift.

When the YAML metadata sets a `title`, that is the title, and the headings keep their levels. A
level-1 heading then stays a level-1 heading, without a warning.

Without a title, the HTML page title is the file name.

### HTML layout

The HTML is a single file, with all images embedded (`--embed-resources`). It uses pandoc's default
template, with the width limit removed and a fixed margin. Use `--max-width` and `--margin` to
change that.

`--theme` chooses the colors of the page:

- `light`, the default: dark text on a light page.
- `dark`: light text on a dark page. `--dark` is short for this.
- `system`: follows the light or dark theme of the system, and switches along with it.

Pandoc's default template (pandoc 3.12 or later) defines both color sets. `mdrender` chooses between
them with the CSS property `color-scheme`. Printed pages are always light.

Diagrams are drawn for a light background, and are hard to read on a dark page. So every diagram
sits on a light panel with rounded corners. On a light page, that panel is invisible.

### DOCX and ODT page setup

Pandoc takes the page size and margins from a *reference document*. `mdrender` generates one on the
fly with the requested paper size, orientation, and margins. It starts from:

1. `reference.docx` or `reference.odt` in pandoc's user data directory, if present, or
2. pandoc's built-in default.

So you can keep your own fonts and styles in such a reference document, and still choose the paper
size per run.

With `--reference-doc`, that document is used as is. Page options given together with it are applied
on top of it.

With pandoc's built-in default, `mdrender` also sets the styles, so that DOCX and ODT look like the
PDF:

- **Font:** a serif font for body text and headings.
  - DOCX: Cambria, which comes with Word. LibreOffice shows it as Caladea, which has the same
    character widths. So a DOCX wraps the same way in both. LibreOffice's font box does list Cambria
    as missing.
  - ODT: Caladea, which comes with LibreOffice.
- **Headings:** black and bold. The title is 18 pt, level 1 17 pt, level 2 14 pt, and deeper levels
  12 pt, the size of the text.
- **Tables:** centered. LibreOffice doesn't center the tables of a DOCX, Word does.
- **Word:** opens a DOCX as a current document, not in compatibility mode.

Your own reference document keeps its own fonts and styles.

Every ODT table also gets a line under its header row, as in DOCX and PDF. That also holds with your
own reference document.

### PDF engines

Pandoc needs a separate program to create a PDF. `mdrender` supports four of them:

| Engine        | Output looks like       | macOS (Homebrew)                  | Elsewhere                                                                                  |
| ------------- | ----------------------- | --------------------------------- | ------------------------------------------------------------------------------------------ |
| `typst`       | Neatly typeset document | `brew install typst`              | [typst releases](https://github.com/typst/typst/releases)                                  |
| `latex`       | Classic LaTeX article   | `brew install tectonic`           | [TeX Live](https://tug.org/texlive/) or [Tectonic](https://tectonic-typesetting.github.io) |
| `weasyprint`  | The HTML output         | `brew install weasyprint`         | `pip install weasyprint`, see [WeasyPrint](https://weasyprint.org)                         |
| `libreoffice` | The ODT output          | `brew install --cask libreoffice` | [LibreOffice](https://www.libreoffice.org/download/)                                       |

With `--pdf-engine auto`, the default, `mdrender` uses the first one installed, in the order of the
table. Set `MDRENDER_PDF_ENGINE`, e.g. in your shell profile, to prefer another engine on a machine.

Pros and cons, as found while testing on macOS:

| Engine      | Pros                                                                                        | Cons                                                                                                                |
| ----------- | ------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------- |
| Typst       | Small single program. Fast, about a second. Good typesetting and hyphenation. Page numbers. | Looks different from the HTML. Changing the style takes Typst knowledge.                                            |
| LaTeX       | The finest typesetting. Mature, with a huge set of packages.                                | Large install, except Tectonic. Tectonic's first run downloads packages. Wide tables and code can run off the page. |
| WeasyPrint  | Looks like the HTML output. Styled with CSS. Fast.                                          | No page numbers. Diagrams are PNG instead of SVG.                                                                   |
| LibreOffice | Comes with many Linux desktops. Uses the fonts and styles of a reference document.          | Slowest, because LibreOffice has to start. Plain tables. A large install otherwise.                                 |

Some notes per engine:

- **Typst** is the best choice when nothing is installed yet. `mdrender` adds a few rules for
  tables:
  - Cells start on the left, and their text is not justified.
  - The header row is bold.
  - Column widths fit the content.
  - A long table continues on the next page, with its header row repeated.

  It also shows the checkboxes of task lists (`- [ ]` and `- [x]`) as the math symbols `□` and `⊠`,
  as LaTeX does. Typst's default font has no checkbox characters. In a list of only task items,
  the checkbox replaces the bullet, as in the HTML.
- **LaTeX** uses `xelatex`, `lualatex`, `tectonic`, or `pdflatex`, whichever is found first.
  Tectonic is the smallest LaTeX to install. It downloads the packages it needs on first use. A full
  TeX Live, or MacTeX on macOS, also works, but is several gigabytes. BasicTeX
  (`brew install --cask basictex`) is smaller, but needs extra packages before pandoc can use it.
  See [Creating a PDF](https://pandoc.org/MANUAL.html#creating-a-pdf) in pandoc's manual.

  With `--lang`, pandoc loads the LaTeX package `babel` for that language. Babel then needs the
  language and hyphenation files for it. Tectonic downloads these on first use, and a full TeX
  Live has them. With BasicTeX, install them with `tlmgr`, e.g. for Dutch:
  `sudo tlmgr install babel-dutch hyphen-dutch`.
- **WeasyPrint** turns the HTML into PDF. Diagrams become PNG here, because WeasyPrint cannot show
  the labels that Mermaid and draw.io put in their SVG. `mdrender` also keeps the checkboxes of task
  lists on the line of their item, as in the HTML.
- **LibreOffice** converts the ODT output, so `--reference-doc` applies. `mdrender` runs it as
  `soffice`, which must be on your `PATH`. Linux packages install it there. On macOS, the app keeps
  it inside its bundle, so link it into a folder on your `PATH`, e.g.: `ln -s
  /Applications/LibreOffice.app/Contents/MacOS/soffice ~/bin/soffice`.

Links behave the same with every engine:

| Link                                                 | In the PDF                      |
| ---------------------------------------------------- | ------------------------------- |
| Web link, e.g. `https://…` or `mailto:…`             | Clickable                       |
| Within the document, e.g. `#section`                 | Clickable                       |
| To another local file, e.g. `plan.md` or `data.xlsx` | Plain text, see [Links](#links) |

Only the look of links differs. Typst and LaTeX show them in blue, which `mdrender` sets.
LibreOffice shows them blue and underlined. WeasyPrint follows the HTML style.

The page options `--paper`, `--landscape`, and `--page-margin` work with every engine.

### Language

The document language is a language code such as `nl` or `en-GB`. There are three ways to set it:

1. On the command line, with `--lang`. `--nl`, `--de`, `--fr`, `--es`, and `--gb` are short for
   Dutch, German, French, Spanish, and British English.
2. In the YAML metadata of the document, pandoc's standard way:

   ```markdown
   ---
   lang: nl
   ---
   ```

3. With a directive in the document: `<!-- lang: nl -->` on a line of its own. See
   [Directives](#directives).

The first one that is set wins, in this order. So `--lang` overrides the document, and the YAML
metadata overrides the directive.

YAML metadata is pandoc's standard, but GitHub and GitLab show it as a table at the top of the page.
The directive is an HTML comment, which they don't show.

The language affects:

- **PDF:** hyphenation with Typst and LaTeX. Their default is English.
- **DOCX and ODT:** the language for spell checking and hyphenation in Word and LibreOffice.
- **HTML:** the `lang` attribute, which browsers use for hyphenation and screen readers for
  pronunciation.

### Directives

`directives.lua` handles directives in the document. A directive is an HTML comment on a line of its
own, so GitHub, GitLab, and other Markdown viewers don't show it:

| Directive           | Effect                                                                 |
| ------------------- | ---------------------------------------------------------------------- |
| `<!-- lang: nl -->` | The document language, unless set otherwise, see [Language](#language) |
| `<!-- newpage -->`  | A page break                                                           |

A page break works in every output format with pages:

| Output                    | Page break as                                      |
| ------------------------- | -------------------------------------------------- |
| PDF with Typst            | `#pagebreak()`                                     |
| PDF with LaTeX            | `\newpage`                                         |
| PDF with WeasyPrint       | an element with `break-before: page`               |
| PDF with LibreOffice, ODT | an empty paragraph in the style `Pagebreak`        |
| DOCX                      | a paragraph with a page break                      |
| HTML                      | an element with `break-before: page`, for printing |

`\newpage` on a line of its own is a page break too. Pandoc users know it from LaTeX. But GitHub and
GitLab show it as text, so the directive is usually the better choice.

For ODT, the reference document needs a paragraph style `Pagebreak`, with a page break before it.
`mdrender` adds that style to the reference document it generates. Your own document from
`--reference-doc`, without page options, is used as is. Add the style to it yourself, or the page
break is missing.

Example:

```markdown
<!-- lang: nl -->

# Managementsamenvatting

Twee pagina's samenvatting.

<!-- newpage -->

## Meer lezen
```

### Table of contents

`toc.lua` turns a paragraph that is only `[[_TOC_]]` or `[TOC]` into a table of contents. GitLab
uses the same markers, so the document looks the same there. Letter case doesn't matter. A marker
inside a sentence, a list, or a code block stays as it is.

The table of contents lists the headings at every level. A heading with the class `unlisted`
(`## Notes {.unlisted}`) is left out, except in DOCX and ODT. In a document without headings, the
marker just disappears.

The document title isn't in the list. When `mdrender` makes a sole level-1 heading the title, that
heading has no anchor to link to. With `--no-shift`, or with several level-1 headings, every heading
is listed.

Each output format gets its own kind of table of contents. In all of them, the entries link to the
headings. Formats with pages show page numbers:

| Output               | Table of contents                                                |
| -------------------- | ---------------------------------------------------------------- |
| HTML                 | a nested list of links                                           |
| PDF with Typst       | Typst's `#outline()`, with dot leaders and page numbers          |
| PDF with LaTeX       | the list of `\tableofcontents`, without its "Contents" heading   |
| PDF with WeasyPrint  | the list of links, with dot leaders and page numbers from CSS    |
| PDF with LibreOffice | LibreOffice's table of contents, filled in during the conversion |
| DOCX                 | a Word table of contents field, filled in by LibreOffice         |
| ODT                  | a LibreOffice table of contents, filled in by LibreOffice        |

#### DOCX and ODT

Only a word processor can work out the page numbers of a DOCX or ODT. `mdrender` fills in the table
of contents with LibreOffice, when it's installed:

1. `toc_update.py`, a LibreOffice macro, opens the document and updates its tables of contents.
2. It copies only the filled-in tables of contents back into the document. The rest of the document
   stays exactly as it was, styles included.

In DOCX, the entries have the TOC styles of Word itself: 5 pt after each entry, and more indent per
level. A reference document with its own TOC styles keeps those.

After an update, Word ends the table of contents with an empty paragraph, which holds the end of the
field. A table of contents that Word inserts itself has it too.

LibreOffice runs headless, with a private profile, so it can run while LibreOffice is open. It adds
a few seconds, and only for a document with a table of contents.

Word works out its own page layout, which can differ a little from LibreOffice's. So the DOCX field
stays marked for updating: Word offers to update the fields when it opens the document. Then it uses
its own page numbers.

Without LibreOffice, the table of contents stays empty, and `mdrender` prints a warning. Word still
fills in the DOCX field when it updates the fields. In LibreOffice, update an ODT with **Tools →
Update → Update All**.

A table of contents can also be a list between two `<!-- TOC -->` lines. IntelliJ IDEA writes it
that way, and other tools can keep it up to date in the file. GitHub shows such a list too, since
it's ordinary Markdown. GitHub doesn't know the `[[_TOC_]]` and `[TOC]` markers.

`toc.lua` replaces that list with a fresh one in the output. An outdated list can then never end up
in the output, nor a link to a missing heading. The file itself stays as it is. When the list was
out of date, `toc.lua` prints a warning:

```text
[toc.lua] WARNING: advice.md: the table of contents between the <!-- TOC --> lines is out of date, the output uses an updated one
```

Only the entries count: their level, their text, and their link. A different bullet, indentation, or
other whitespace gives no warning. A single `<!-- TOC -->` line, without a second one, is left
alone.

### Content for one output format

Pandoc can pass content unchanged to one output format, with a *raw block*. The block is marked with
the format, e.g. `{=typst}`. Other formats leave it out. Use it for anything that Markdown cannot
express, such as a layout detail that only matters in one format.

The format is the pandoc *writer*, not the format you ask `mdrender` for. A PDF can come from four
writers, depending on the PDF engine:

| `mdrender` output    | Raw block format                      |
| -------------------- | ------------------------------------- |
| HTML                 | `{=html}`                             |
| DOCX                 | `{=openxml}`                          |
| ODT                  | `{=opendocument}`                     |
| PDF with Typst       | `{=typst}`                            |
| PDF with LaTeX       | `{=latex}`                            |
| PDF with WeasyPrint  | `{=html}`, so also in the HTML        |
| PDF with LibreOffice | `{=opendocument}`, so also in the ODT |

Some examples:

````markdown
```{=typst}
#set text(size: 10pt)
```

```{=latex}
\small
```

```{=html}
<p style="text-align: center">Only in HTML, and in PDF via WeasyPrint.</p>
```

```{=openxml}
<w:p><w:r><w:t>Only in DOCX.</w:t></w:r></w:p>
```
````

A raw block of one format is shown as a code block on GitHub and GitLab. For a page break, use the
`<!-- newpage -->` directive instead. It also works with every writer.

Pandoc's manual describes raw blocks under [Extension:
raw_attribute](https://pandoc.org/MANUAL.html#extension-raw_attribute).

### Diagrams

`diagram.lua` turns three kinds of diagrams into images:

| Type     | Written as                                           | Rendered with             |
| -------- | ---------------------------------------------------- | ------------------------- |
| Mermaid  | a ` ```mermaid ` code block                          | `mmdc`                    |
| Graphviz | a ` ```dot ` or ` ```graphviz ` code block           | `dot`                     |
| draw.io  | an image of a `.drawio` file: `![Flow](flow.drawio)` | `drawio`, the desktop app |

The image type depends on the output format:

- HTML and EPUB get SVG.
- Other formats get PNG, at twice the normal resolution so it stays sharp.
- The metadata field `diagram-format` overrides that: `svg` or `png`. `mdrender` uses it for PDF via
  WeasyPrint.

PNG diagrams get an explicit width: their natural size, scaled down when needed to fit the text area
of the page. A little room is left for a caption. `mdrender` passes the text area to the filter.
Without it, a wide or tall diagram can run off the page, in ODT even more so, because pandoc's ODT
writer does not scale images down.

Rendering takes a second or two per diagram, so the images are cached by content. The cache lives in
`~/.cache/pandoc-diagram`, or in `$XDG_CACHE_HOME/pandoc-diagram`. Unchanged diagrams are not
rendered again.

A code block can set a caption and width. A Graphviz block can also choose a layout engine:

````markdown
```{.mermaid caption="Release flow" width="80%"}
flowchart LR
  A --> B
```

```{.dot engine=circo}
digraph { a -> b -> c -> a }
```
````

A draw.io image is found like any other image, relative to the document. Its description becomes the
caption. It can choose a page, by number (from 1) or by name, and set a width:

```markdown
![Release flow](diagrams/flow.drawio){page="Hotfix" width="80%"}
```

When rendering fails, the filter prints a warning. A code block then stays as is. A draw.io image is
replaced by its description, as pandoc does for a missing image.

Other images, such as PNG, JPEG, GIF, and SVG, need no filter. Pandoc handles them itself.

### Links

With `--link-ext`, `md-links.lua` rewrites relative links to `.md` and `.markdown` files. The new
extension is that of the output format. A `#fragment` is kept, and absolute URLs are left alone.

PDF is different. Most PDF viewers refuse to open another file from a link. Preview on macOS, for
example, is not allowed to by its sandbox, and Firefox ignores such links. So in a PDF, links to
other local files become plain text, also without `--link-ext`. Web links and links within the
document stay links. With Typst and LaTeX, `mdrender` also colors links blue, because both engines
show them as plain text by default.

### Long inline code

Typst, LaTeX, and WeasyPrint don't break inline code by themselves. A long name such as
`OrderService.calculateShippingCosts` then runs into the next table column, or off the page.
`code-breaks.lua` adds a break opportunity after each `.`, `/`, `_`, `,`, `|`, `:` and `-` in inline
code:

| Engine      | Where      | How                                                   |
| ----------- | ---------- | ----------------------------------------------------- |
| Typst       | In tables  | A zero-width space, which copied text leaves out      |
| LaTeX       | Everywhere | `\allowbreak`, except in headings                     |
| WeasyPrint  | In tables  | `<wbr>`                                               |
| LibreOffice | Not needed | LibreOffice breaks a long word by itself where needed |

Outside tables, Typst moves long code to a new line by itself. LaTeX doesn't, so there the filter
works everywhere. With LaTeX, normal text also gets a break opportunity after a `/`, so e.g.
`client/server` can break. Typst already breaks there, and WeasyPrint widens the column instead.

With LaTeX, `mdrender` also uses `\sloppy`. LaTeX then accepts a loosely spaced line rather than one
that runs past the margin. HTML output gets the same `<wbr>` in tables as WeasyPrint.

### Table column widths

`table-widths.lua` fits the columns of a table to their content, for DOCX, ODT, and LaTeX. Typst and
WeasyPrint do that themselves.

#### DOCX and ODT

Each column gets its width from its content:

- When all cells fit on one line, each column gets the width of its longest cell. The table is then
  narrower than the page.
- Otherwise each column gets at least the width of its longest word, so a word doesn't break. The
  room that is left goes to the columns with longer cells.
- When even the longest words don't fit, `mdrender` prints a warning that names the table by its
  header row. Word and LibreOffice then break words.

This also covers PDF with LibreOffice. A table with its own column widths, such as a grid table,
keeps them. The estimate assumes 12 pt text.

#### LaTeX

For a pipe table with a line wider than 72 characters, pandoc sets each column's width from the
length of its dash line. A narrow column can then be too narrow for a word in it, which runs into
the next column.

So `table-widths.lua` estimates the width of the longest word in each column. A word can break at a
space, after a hyphen, and where `code-breaks.lua` allows it. A hyphen between digits, as in a date,
counts as part of the word. A column that is too narrow gets wider. The extra width comes from the
columns with room to spare.

When the longest words don't fit the line together, the table gets a smaller font: first `\small`,
then `\footnotesize`. When even that is too wide, `mdrender` prints a warning that names the table
by its header row. The columns may then overlap a little.

The estimate counts characters, because a filter can't measure text. It assumes Latin Modern,
LaTeX's default font. With another font set in the document, the widths can be a little off.

## Using the filters directly

Pandoc finds the installed filters by name:

```sh
pandoc -s --embed-resources -L diagram.lua input.md -o output.html
pandoc -L md-links.lua -M md-link-ext=html input.md -o output.html
pandoc -L directives.lua input.md -o output.pdf
pandoc -L toc.lua -M toc-skip-title=true --shift-heading-level-by=-1 input.md -o output.pdf
pandoc -L toc.lua input.md -o output.docx
pandoc -L code-breaks.lua input.md -o output.pdf
pandoc -L code-breaks.lua -L table-widths.lua -M table-text-width=170mm input.md -o output.pdf
pandoc --columns=10000 -L table-widths.lua -M table-text-width=170mm input.md -o output.docx
```

Settings:

| Setting                         | Filter             | Purpose                                        |
| ------------------------------- | ------------------ | ---------------------------------------------- |
| metadata `md-link-ext`          | `md-links.lua`     | New link extension, e.g. `html`                |
| metadata `md-link-unlink`       | `md-links.lua`     | `true`: links to local files become plain text |
| metadata `diagram-max-width`    | `diagram.lua`      | Maximum PNG width, e.g. `170mm`                |
| metadata `diagram-max-height`   | `diagram.lua`      | Maximum PNG height, e.g. `237mm`               |
| metadata `diagram-format`       | `diagram.lua`      | Image type: `svg` or `png`                     |
| metadata `table-text-width`     | `table-widths.lua` | Text width for tables, e.g. `170mm`            |
| metadata `toc-skip-title`       | `toc.lua`          | `true`: leave level-1 headings out of the list |
| environment `DIAGRAM_CACHE_DIR` | `diagram.lua`      | Cache location                                 |
| environment `DIAGRAM_MMDC`      | `diagram.lua`      | `mmdc` executable                              |
| environment `DIAGRAM_DOT`       | `diagram.lua`      | `dot` executable                               |
| environment `DIAGRAM_DRAWIO`    | `diagram.lua`      | draw.io executable                             |

## Emacs

[markdown-mode](https://jblevins.org/projects/markdown-mode/) sends the buffer to `markdown-command`
on stdin, and reads HTML from stdout. That is exactly what `mdrender` does by default:

```elisp
(setq markdown-command "mdrender")
```

Use `"mdrender --link-ext"` to also rewrite links to other Markdown files.

## Tests

`tests/run` runs all tests. They need pandoc and `python3`, and
[Bats](https://github.com/bats-core/bats-core) for the tests of `mdrender` (`brew install bats-core`
on macOS). Installing `mdrender` doesn't need Bats.

- The filter tests in `tests/lua` run each filter on small documents, with `pandoc lua`, and check
  the resulting document. A single file runs with `pandoc lua tests/lua/directives_test.lua`.
- The tests in `tests/python` check how `toc_update.py` copies a table of contents into a DOCX or
  ODT. They run without LibreOffice: `python3 -m unittest discover -s tests/python`.
- The tests in `tests/mdrender.bats` run `mdrender` itself, mostly with HTML output: options, the
  title, the language, the table of contents, and links. They install this repository with
  `install.sh --symlink` into a temporary folder. That way they test the files here, not the
  installed ones. Run them alone with `bats tests`.
- The tests of a table of contents in DOCX, ODT, and PDF skip themselves when LibreOffice or a PDF
  engine they need is missing.

The Bats tests run in parallel with `TEST_JOBS` set to more than 1, e.g. `TEST_JOBS=8 tests/run`.
That takes [GNU parallel](https://www.gnu.org/software/parallel/) (`brew install parallel`).
Without it, they run one at a time.

`tests/run` exits with status 0 when all tests pass, and 1 when a test fails. When pandoc,
`python3`, or Bats is missing, it runs the tests it can and exits with status 77, which means
"skipped".

## Known limitations

- **Heading detection is a heuristic.** It counts `#` and `===` headings outside fenced code blocks.
  Unusual constructs, such as headings inside HTML blocks, can confuse it. Use `--no-shift` when in
  doubt.
- **Own reference document without page options.** The page setup is then unknown to `mdrender`.
  Diagrams keep their natural size, and can be too wide in ODT.
- **ODT links start with `../`.** ODT stores relative links relative to the document package.
  LibreOffice resolves them correctly.
- **No DOCX, ODT, or PDF on a terminal.** `mdrender` refuses to write binary output to a terminal.
  Use `--output`, `--temp`, or `--open`, or redirect stdout.
- **PDF hyphenation is English by default.** Typst and LaTeX hyphenate by the document language. Set
  it with `--lang` or a shortcut such as `--nl`, or in the document, see [Language](#language).
- **Own ODT reference document without page options.** It needs a paragraph style `Pagebreak` for
  page breaks, see [Directives](#directives).
- **LaTeX doesn't wrap code blocks.** A line in a fenced code block that is wider than the page runs
  off it. `code-breaks.lua` only handles inline code.
- **A very wide table can still overlap with LaTeX.** When a table's longest words don't fit the
  line even in `\footnotesize`, its columns overlap, see
  [Table column widths](#table-column-widths). Shorten or split the table, or use landscape.
- **An unlisted heading is listed in DOCX and ODT.** Word and LibreOffice build their table of
  contents from the headings themselves. They can't leave out one heading.
- **A DOCX or ODT table of contents needs LibreOffice.** Without it, the table of contents stays
  empty until Word or LibreOffice updates it, see [Table of contents](#table-of-contents).
- **`mmdc` errors are verbose.** When a diagram is invalid, `mmdc` prints a stack trace to stderr.

## Alternatives

[pandoc-ext/diagram](https://github.com/pandoc-ext/diagram) supports more diagram types written as
code blocks: PlantUML, D2, TikZ, and others. It does not size PNG diagrams for DOCX/ODT, though. It
also renders Mermaid PNGs at normal resolution only, its cache is off by default, and it has no
draw.io support. `diagram.lua` exists for those reasons.

## License

MarkDownRender is released under the MIT License. See [LICENSE](LICENSE).
