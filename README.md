# MarkDownRender

Render Markdown to HTML, DOCX, ODT or PDF in one command, diagrams included.

`mdrender` is a small wrapper around [pandoc](https://pandoc.org). It adds three Lua filters and
sensible defaults:

- Diagrams become images: Mermaid and Graphviz code blocks, and draw.io files. HTML gets SVG,
  DOCX, ODT and PDF get PNG.
- Links to other Markdown files can be rewritten to the output format, e.g. `other.md` becomes
  `other.html`.
- Directives in the document, as invisible HTML comments: the document language, and page breaks.
- HTML fills the window, with a small margin. It is light by default, or dark, or follows the
  system.
- DOCX, ODT and PDF use A4 portrait with 2 cm margins, instead of pandoc's US Letter.
- PDF uses the best PDF engine that is installed: Typst, LaTeX, WeasyPrint or LibreOffice.
- A single level-1 heading becomes the document title.

The Lua filters are installed in pandoc's filters folder. `mdrender` uses them from there, and so
can any other pandoc command.

## Contents

```text
MarkDownRender/
├── bin/
│   └── mdrender          the command-line script
├── lua-filter/
│   ├── diagram.lua       turns Mermaid, Graphviz and draw.io diagrams into images
│   ├── directives.lua    handles directives: document language and page breaks
│   └── md-links.lua      rewrites links to .md files
├── install.manifest      what to install, and where
├── install.sh            installs the files listed in install.manifest
├── LICENSE               the MIT License
└── README.md
```

## Requirements

- [pandoc](https://pandoc.org) 3 or later, with Lua support (`brew install pandoc`).
- For diagrams, the tool for each type you use:
  - [Mermaid CLI](https://github.com/mermaid-js/mermaid-cli) (`mmdc`):
    `npm install -g @mermaid-js/mermaid-cli`.
  - [Graphviz](https://graphviz.org) (`dot`): `brew install graphviz`.
  - [draw.io desktop](https://www.drawio.com) (`drawio`): `brew install --cask drawio`.
- `python3`, for the DOCX/ODT page setup.
- For PDF: one of the PDF engines, see [PDF engines](#pdf-engines).

## Installation

`install.manifest` lists what to install, and where:

```text
# source          destination
bin/              $TARGET/bin/
lua-filter/*.lua  ${XDG_DATA_HOME:-~/.local/share}/pandoc/filters/
```

- `mdrender` goes to `bin` in the target root, your home directory by default. That folder must
  be on your `PATH`.
- The Lua filters go to pandoc's filters folder.

Install with:

```sh
./install.sh
```

The files are copied. With `--symlink` they are linked instead, so later changes in this
repository take effect without reinstalling. Running it again with or without `--symlink` switches
between links and copies. Other files with the same name are only replaced with `--force`. Use
`--target` for another target root, and `--dry-run` to only see what would happen. Run
`./install.sh --help` for all options.

The filters folder in the manifest assumes pandoc's default user data directory. Check yours with
`pandoc --version`. If it is another folder, such as `~/.pandoc`, install the filters there by
hand.

## Usage

```text
mdrender --help|-h
mdrender --version
mdrender [option...] [file.md ...] [-- extra pandoc options]

  --to|-t FORMAT        Output format: html (default), docx, odt or pdf.
  --pdf-engine ENGINE   PDF engine: auto (default), typst, latex, weasyprint or
                        libreoffice. Also settable with MDRENDER_PDF_ENGINE.
  --output|-o FILE      Output file, for a single input only. "-" means stdout.
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

Input and output:

- A file `foo.md` is written next to it as `foo.html`, `foo.docx`, `foo.odt` or `foo.pdf`.
- Without a file, or with `-`, the input is read from stdin and written to stdout.
- `--output` sets another output location, for a single input.
- Anything after `--` is passed to pandoc unchanged.

Examples:

```sh
# Two documents that link to each other, both to HTML.
mdrender --link-ext advice.md plan.md

# ODT on A4, and DOCX on A3 landscape.
mdrender -t odt advice.md
mdrender -t docx --paper a3 --landscape overview.md

# PDF with the best engine available, and with WeasyPrint.
mdrender -t pdf advice.md
mdrender -t pdf --pdf-engine weasyprint advice.md

# A Dutch document as PDF, with Dutch hyphenation.
mdrender -t pdf --nl advies.md

# HTML with a dark page.
mdrender --dark notes.md

# From stdin to stdout.
cat notes.md | mdrender > notes.html
```

## How it works

### Headings and title

When a document has exactly one level-1 heading, that heading becomes the document title. All other
headings move up one level. This is pandoc's `--shift-heading-level-by=-1`. The title then shows up
as the HTML `<title>`, or as the Title style in Word.

With zero or several level-1 headings, `mdrender` does not shift. Pandoc would otherwise turn the
extra level-1 headings into plain paragraphs. In that case `mdrender` prints a warning. Headings
inside fenced code blocks are not counted. Use `--no-shift` to never shift.

Without a title, the HTML page title is the file name.

### HTML layout

The HTML is a single file, with all images embedded (`--embed-resources`). It uses pandoc's
default template, with the width limit removed and a fixed margin. Use `--max-width` and
`--margin` to change that.

`--theme` chooses the colors of the page:

- `light`, the default: dark text on a light page.
- `dark`: light text on a dark page. `--dark` is short for this.
- `system`: follows the light or dark theme of the system, and switches along with it.

Pandoc's default template (pandoc 3.12 or later) defines both color sets. `mdrender` chooses
between them with the CSS property `color-scheme`. Printed pages are always light.

Diagrams are drawn for a light background, and are hard to read on a dark page. So every diagram
sits on a light panel with rounded corners. On a light page, that panel is invisible.

### DOCX and ODT page setup

Pandoc takes the page size and margins from a *reference document*. `mdrender` generates one on
the fly with the requested paper size, orientation and margins. It starts from:

1. `reference.docx` or `reference.odt` in pandoc's user data directory, if present, or
2. pandoc's built-in default.

So you can keep your own fonts and styles in such a reference document, and still choose the
paper size per run.

With `--reference-doc`, that document is used as is. Page options given together with it are
applied on top of it.

### PDF engines

Pandoc needs a separate program to create a PDF. `mdrender` supports four of them:

| Engine        | Output looks like       | macOS (Homebrew)                  | Elsewhere                                                                                  |
| ------------- | ----------------------- | --------------------------------- | ------------------------------------------------------------------------------------------ |
| `typst`       | Neatly typeset document | `brew install typst`              | [typst releases](https://github.com/typst/typst/releases)                                  |
| `latex`       | Classic LaTeX article   | `brew install tectonic`           | [TeX Live](https://tug.org/texlive/) or [Tectonic](https://tectonic-typesetting.github.io) |
| `weasyprint`  | The HTML output         | `brew install weasyprint`         | `pip install weasyprint`, see [WeasyPrint](https://weasyprint.org)                         |
| `libreoffice` | The ODT output          | `brew install --cask libreoffice` | [LibreOffice](https://www.libreoffice.org/download/)                                       |

With `--pdf-engine auto`, the default, `mdrender` uses the first one installed, in the order of the
table. Set `MDRENDER_PDF_ENGINE`, e.g. in your shell profile, to prefer another engine on a
machine.

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
- **LaTeX** uses `xelatex`, `lualatex`, `tectonic` or `pdflatex`, whichever is found first.
  Tectonic is the smallest LaTeX to install. It downloads the packages it needs on first use. A
  full TeX Live, or MacTeX on macOS, also works, but is several gigabytes. BasicTeX (`brew install
  --cask basictex`) is smaller, but needs extra packages before pandoc can use it. See [Creating a
  PDF](https://pandoc.org/MANUAL.html#creating-a-pdf) in pandoc's manual.

  With `--lang`, pandoc loads the LaTeX package `babel` for that language. Babel then needs the
  language and hyphenation files for it. Tectonic downloads these on first use, and a full TeX
  Live has them. With BasicTeX, install them with `tlmgr`, e.g. for Dutch:
  `sudo tlmgr install babel-dutch hyphen-dutch`.
- **WeasyPrint** turns the HTML into PDF. Diagrams become PNG here, because WeasyPrint cannot
  show the labels that Mermaid and draw.io put in their SVG.
- **LibreOffice** converts the ODT output, so `--reference-doc` applies. `mdrender` runs it as
  `soffice`, which must be on your `PATH`. Linux packages install it there. On macOS, the app
  keeps it inside its bundle, so link it into a folder on your `PATH`, e.g.:
  `ln -s /Applications/LibreOffice.app/Contents/MacOS/soffice ~/bin/soffice`.

Links behave the same with every engine:

| Link                                                 | In the PDF                      |
| ---------------------------------------------------- | ------------------------------- |
| Web link, e.g. `https://…` or `mailto:…`             | Clickable                       |
| Within the document, e.g. `#section`                 | Clickable                       |
| To another local file, e.g. `plan.md` or `data.xlsx` | Plain text, see [Links](#links) |

Only the look of links differs. Typst and LaTeX show them in blue, which `mdrender` sets.
LibreOffice shows them blue and underlined. WeasyPrint follows the HTML style.

The page options `--paper`, `--landscape` and `--page-margin` work with every engine.

### Language

The document language is a language code such as `nl` or `en-GB`. There are three ways to set it:

1. On the command line, with `--lang`. `--nl`, `--de`, `--fr`, `--es` and `--gb` are short for
   Dutch, German, French, Spanish and British English.
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

YAML metadata is pandoc's standard, but GitHub and GitLab show it as a table at the top of the
page. The directive is an HTML comment, which they don't show.

The language affects:

- **PDF:** hyphenation with Typst and LaTeX. Their default is English.
- **DOCX and ODT:** the language for spell checking and hyphenation in Word and LibreOffice.
- **HTML:** the `lang` attribute, which browsers use for hyphenation and screen readers for
  pronunciation.

### Directives

`directives.lua` handles directives in the document. A directive is an HTML comment on a line of its
own, so GitHub, GitLab and other Markdown viewers don't show it:

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

`\newpage` on a line of its own is a page break too. Pandoc users know it from LaTeX. But GitHub
and GitLab show it as text, so the directive is usually the better choice.

For ODT, the reference document needs a paragraph style `Pagebreak`, with a page break before it.
`mdrender` adds that style to the reference document it generates. Your own document from
`--reference-doc`, without page options, is used as is. Add the style to it yourself, or the page
break is missing.

Example:

```markdown
<!-- lang: nl -->

# Managementsamenvatting

Two pages of summary.

<!-- newpage -->

## Meer lezen
```

### Content for one output format

Pandoc can pass content unchanged to one output format, with a *raw block*. The block is
marked with the format, e.g. `{=typst}`. Other formats leave it out. Use it for anything that
Markdown cannot express, such as a layout detail that only matters in one format.

The format is the pandoc *writer*, not the format you ask `mdrender` for. A PDF can come from
four writers, depending on the PDF engine:

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

A raw block of one format is shown as a code block on GitHub and GitLab. For a page break, use
the `<!-- newpage -->` directive instead. It also works with every writer.

Pandoc's manual describes raw blocks under
[Extension: raw_attribute](https://pandoc.org/MANUAL.html#extension-raw_attribute).

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
- The metadata field `diagram-format` overrides that: `svg` or `png`. `mdrender` uses it for PDF
  via WeasyPrint.

PNG diagrams get an explicit width: their natural size, scaled down when needed to fit the text
area of the page. A little room is left for a caption. `mdrender` passes the text area to the
filter. Without it, a wide or tall diagram can run off the page, in ODT even more so, because
pandoc's ODT writer does not scale images down.

Rendering takes a second or two per diagram, so the images are cached by content. The cache lives
in `~/.cache/pandoc-diagram`, or in `$XDG_CACHE_HOME/pandoc-diagram`. Unchanged diagrams are not
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

A draw.io image is found like any other image, relative to the document. Its description becomes
the caption. It can choose a page, by number (from 1) or by name, and set a width:

```markdown
![Release flow](diagrams/flow.drawio){page="Hotfix" width="80%"}
```

When rendering fails, the filter prints a warning. A code block then stays as is. A draw.io image
is replaced by its description, as pandoc does for a missing image.

Other images, such as PNG, JPEG, GIF and SVG, need no filter. Pandoc handles them itself.

### Links

With `--link-ext`, `md-links.lua` rewrites relative links to `.md` and `.markdown` files. The new
extension is that of the output format. A `#fragment` is kept, and absolute URLs are left alone.

PDF is different. Most PDF viewers refuse to open another file from a link. Preview on macOS, for
example, is not allowed to by its sandbox, and Firefox ignores such links. So in a PDF, links to
other local files become plain text, also without `--link-ext`. Web links and links within the
document stay links. With Typst and LaTeX, `mdrender` also colors links blue, because both
engines show them as plain text by default.

## Using the filters directly

Pandoc finds the installed filters by name:

```sh
pandoc -s --embed-resources -L diagram.lua input.md -o output.html
pandoc -L md-links.lua -M md-link-ext=html input.md -o output.html
pandoc -L directives.lua input.md -o output.pdf
```

Settings:

| Setting                         | Filter         | Purpose                                        |
| ------------------------------- | -------------- | ---------------------------------------------- |
| metadata `md-link-ext`          | `md-links.lua` | New link extension, e.g. `html`                |
| metadata `md-link-unlink`       | `md-links.lua` | `true`: links to local files become plain text |
| metadata `diagram-max-width`    | `diagram.lua`  | Maximum PNG width, e.g. `170mm`                |
| metadata `diagram-max-height`   | `diagram.lua`  | Maximum PNG height, e.g. `237mm`               |
| metadata `diagram-format`       | `diagram.lua`  | Image type: `svg` or `png`                     |
| environment `DIAGRAM_CACHE_DIR` | `diagram.lua`  | Cache location                                 |
| environment `DIAGRAM_MMDC`      | `diagram.lua`  | `mmdc` executable                              |
| environment `DIAGRAM_DOT`       | `diagram.lua`  | `dot` executable                               |
| environment `DIAGRAM_DRAWIO`    | `diagram.lua`  | draw.io executable                             |

## Emacs

[markdown-mode](https://jblevins.org/projects/markdown-mode/) sends the buffer to
`markdown-command` on stdin, and reads HTML from stdout. That is exactly what `mdrender` does by
default:

```elisp
(setq markdown-command "mdrender")
```

Use `"mdrender --link-ext"` to also rewrite links to other Markdown files.

## Known limitations

- **Heading detection is a heuristic.** It counts `#` and `===` headings outside fenced code
  blocks. Unusual constructs, such as headings inside HTML blocks, can confuse it. Use
  `--no-shift` when in doubt.
- **Own reference document without page options.** The page setup is then unknown to `mdrender`.
  Diagrams keep their natural size, and can be too wide in ODT.
- **ODT links start with `../`.** ODT stores relative links relative to the document package.
  LibreOffice resolves them correctly.
- **No DOCX, ODT or PDF on a terminal.** `mdrender` refuses to write binary output to a terminal.
  Use `--output` or redirect stdout.
- **PDF hyphenation is English by default.** Typst and LaTeX hyphenate by the document language.
  Set it with `--lang` or a shortcut such as `--nl`, or in the document, see [Language](#language).
- **Own ODT reference document without page options.** It needs a paragraph style `Pagebreak` for
  page breaks, see [Directives](#directives).
- **`mmdc` errors are verbose.** When a diagram is invalid, `mmdc` prints a stack trace to stderr.

## Alternatives

[pandoc-ext/diagram](https://github.com/pandoc-ext/diagram) supports more diagram types written as
code blocks: PlantUML, D2, TikZ and others. It does not size PNG diagrams for DOCX/ODT, though. It
also renders Mermaid PNGs at normal resolution only, its cache is off by default, and it has no
draw.io support. `diagram.lua` exists for those reasons.

## License

MarkDownRender is released under the MIT License. See [LICENSE](LICENSE).
