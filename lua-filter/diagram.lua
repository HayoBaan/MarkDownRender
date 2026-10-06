--[[
diagram.lua — Pandoc Lua filter that turns diagrams into images.

Supported diagram types:
  - Mermaid: ```mermaid code blocks, rendered with mmdc (Mermaid CLI).
  - Graphviz: ```dot or ```graphviz code blocks, rendered with dot.
  - draw.io: images that refer to a .drawio file, exported with the draw.io
    desktop app, e.g. ![Release flow](flow.drawio).

Each diagram is replaced by an image with the class `diagram`, so a stylesheet
can style diagrams, e.g. give them a light background on a dark page. HTML and
EPUB output get SVG, every other output format gets PNG. Rendered images are cached by content hash, so
unchanged diagrams are not rendered again. Rendering a diagram can take a
second or two, because mmdc and draw.io start a browser engine.

Usage:
  pandoc -L diagram.lua input.md -o output.html

Combine with --embed-resources to inline the images into a single HTML file.
Without it, the HTML references the cached image files by absolute path.

The metadata field `diagram-format` overrides the image type: `svg` or `png`.
For example, WeasyPrint turns HTML into PDF, but cannot show the labels that
Mermaid and draw.io put in SVG as HTML (foreignObject). Use
`-M diagram-format=png` there.

Optional attributes on a code block:
  ```{.mermaid caption="Text" width="80%"}
  - caption: used as the image's alt text and caption
  - width:   passed on as the image width
  - engine:  Graphviz only, the layout engine, e.g. neato or circo

Optional attributes on a draw.io image:
  ![Caption](flow.drawio){page=2 width="80%"}
  - page:  the page to export, by number (from 1) or by name. Default: the
           first page.
  - width: kept as the image width

PNG images are rendered at twice their natural resolution, to stay sharp in
Word and PDF. Without a width attribute they get an explicit width: their
natural size, scaled down when needed to fit the metadata fields
`diagram-max-width` and `diagram-max-height`. For example,
`-M diagram-max-width=170mm -M diagram-max-height=237mm` fits the text area of
an A4 page with 2cm margins, with room for a caption. That keeps wide and tall
diagrams on the page, also in ODT, whose writer does not scale images down by
itself.

Environment variables:
  DIAGRAM_CACHE_DIR  cache location (default: $XDG_CACHE_HOME/pandoc-diagram,
                     or ~/.cache/pandoc-diagram)
  DIAGRAM_MMDC       mmdc executable (default: mmdc)
  DIAGRAM_DOT        dot executable (default: dot)
  DIAGRAM_DRAWIO     draw.io executable (default: drawio)

If rendering fails, for instance because the tool is not installed, the filter
prints a warning. A code block then stays as is. An image is replaced by its
description, as pandoc does for a missing image.
]]

--- Resolution factor for PNG output.
local PNG_SCALE = 2

--- Inches per supported length unit, for `diagram-max-width` and `diagram-max-height`.
local INCHES_PER_UNIT = { ["in"] = 1, cm = 1 / 2.54, mm = 1 / 25.4, pt = 1 / 72 }

--- Returns the 1-based index of a draw.io page given by number or by name, or
--- nil plus an error message. Page names are read from the file's XML.
local function drawio_page_index(path, page)
  if page:match("^%d+$") then
    return page
  end
  local f = io.open(path, "rb")
  if not f then
    return nil, "cannot read " .. path
  end
  local xml = f:read("a")
  f:close()
  local index = 0
  for name in xml:gmatch('<diagram[^>]-%sname="([^"]*)"') do
    index = index + 1
    if name == page then
      return tostring(index)
    end
  end
  return nil, "no page named '" .. page .. "' in " .. path
end

--- The diagram types written as code blocks, by name. For each type:
---   - classes: the code block classes that select it.
---   - command: the program that renders it.
---   - input_ext: the extension of the temporary input file.
---   - options: the block attributes that change the result.
---   - args(input, output, ext, attributes): the arguments for the command.
local CODE_TYPES = {
  mermaid = {
    classes = { "mermaid" },
    command = os.getenv("DIAGRAM_MMDC") or "mmdc",
    input_ext = "mmd",
    options = {},
    args = function(input, output, ext)
      local args = { "--quiet", "-i", input, "-o", output, "-e", ext }
      if ext == "png" then
        table.insert(args, "-s")
        table.insert(args, tostring(PNG_SCALE))
      end
      return args
    end,
  },
  graphviz = {
    classes = { "dot", "graphviz" },
    command = os.getenv("DIAGRAM_DOT") or "dot",
    input_ext = "dot",
    options = { "engine" },
    args = function(input, output, ext, attributes)
      local args = { "-T" .. ext, "-o", output }
      if ext == "png" then
        -- Graphviz draws at 96 dpi by default.
        table.insert(args, "-Gdpi=" .. tostring(96 * PNG_SCALE))
      end
      if attributes.engine then
        table.insert(args, "-K" .. attributes.engine)
      end
      table.insert(args, input)
      return args
    end,
  },
}

--- The diagram types stored in their own file, by file extension. For each
--- type, the fields are those of CODE_TYPES, except classes and input_ext.
--- The args function also gets the path of the diagram file as its input, and
--- returns nil plus an error message when the attributes are wrong.
local FILE_TYPES = {
  drawio = {
    command = os.getenv("DIAGRAM_DRAWIO") or "drawio",
    options = { "page" },
    args = function(input, output, ext, attributes)
      local args = { "--export", "--format", ext, "--output", output }
      if ext == "png" then
        table.insert(args, "--scale")
        table.insert(args, tostring(PNG_SCALE))
      end
      if attributes.page then
        local index, err = drawio_page_index(input, attributes.page)
        if not index then
          return nil, err
        end
        table.insert(args, "--page-index")
        table.insert(args, index)
      end
      table.insert(args, input)
      return args
    end,
  },
}

--- Prints a warning on stderr.
local function warn(message)
  io.stderr:write("[diagram.lua] WARNING: " .. message .. "\n")
end

--- Returns the cache directory, creating it when needed.
local function cache_dir()
  local dir = os.getenv("DIAGRAM_CACHE_DIR")
  if not dir then
    local base = os.getenv("XDG_CACHE_HOME") or (os.getenv("HOME") .. "/.cache")
    dir = pandoc.path.join({ base, "pandoc-diagram" })
  end
  pandoc.system.make_directory(dir, true)
  return dir
end

--- Returns true when a file exists and is readable.
local function file_exists(path)
  local f = io.open(path, "rb")
  if f then
    f:close()
    return true
  end
  return false
end

--- Returns the contents of a file, or nil when it cannot be read.
local function read_file(path)
  local f = io.open(path, "rb")
  if not f then
    return nil
  end
  local data = f:read("a")
  f:close()
  return data
end

--- Returns the image type to render: the override when given, or else the
--- type that suits the current output format.
local function image_type(override)
  if override then
    return override
  end
  if FORMAT:match("^html") or FORMAT == "revealjs" or FORMAT:match("^epub") then
    return "svg"
  end
  return "png"
end

--- Returns a length such as "170mm" in inches, or nil when it cannot be parsed.
local function to_inches(length)
  local number, unit = tostring(length):match("^%s*([%d%.]+)%s*(%a+)%s*$")
  local factor = unit and INCHES_PER_UNIT[unit]
  if not number or not factor then
    return nil
  end
  return tonumber(number) * factor
end

--- Returns the cache key for a diagram: its type, image type, options and contents.
local function cache_key(name, spec, ext, attributes, content)
  local parts = { name, ext }
  for _, option in ipairs(spec.options) do
    table.insert(parts, option .. "=" .. (attributes[option] or ""))
  end
  table.insert(parts, content)
  return pandoc.utils.sha1(table.concat(parts, "\0"))
end

--- Renders one diagram, returning the image path, or nil plus an error message.
--- Arguments: the type name and spec, the image type, the attributes, the
--- diagram text or file contents, and for a file type the file's path.
local function render(name, spec, ext, attributes, content, source)
  local out = pandoc.path.join({ cache_dir(), cache_key(name, spec, ext, attributes, content) .. "." .. ext })
  if file_exists(out) then
    return out
  end

  local ok, err = pcall(function()
    pandoc.system.with_temporary_directory("pandoc-diagram", function(tmp)
      local input = source
      if not input then
        input = pandoc.path.join({ tmp, "diagram." .. spec.input_ext })
        local f = assert(io.open(input, "w"))
        f:write(content)
        f:close()
      end
      local args, args_err = spec.args(input, out, ext, attributes)
      if not args then
        error(args_err, 0)
      end
      pandoc.pipe(spec.command, args, "")
    end)
  end)
  if not ok or not file_exists(out) then
    return nil, tostring(err)
  end
  return out
end

--- Returns the width to give a PNG diagram: its natural width, scaled down when
--- needed so that both its width and its height fit the limits that are given.
local function png_width(path, limits)
  local data = read_file(path)
  if not data then
    return nil
  end
  local ok, size = pcall(pandoc.image.size, data)
  if not ok or not size or not size.width or not size.height then
    return nil
  end
  local inches = size.width / (96 * PNG_SCALE)
  if limits.width and inches > limits.width then
    inches = limits.width
  end
  local height = inches * size.height / size.width
  if limits.height and height > limits.height then
    inches = limits.height * size.width / size.height
  end
  return string.format("%.2fin", inches)
end

--- Returns the name and spec of the code block type with one of the given classes, or nil.
local function code_type(classes)
  for name, spec in pairs(CODE_TYPES) do
    for _, class in ipairs(spec.classes) do
      if classes:includes(class) then
        return name, spec
      end
    end
  end
  return nil
end

--- Returns the path of an image file, looked up in pandoc's resource path as
--- pandoc does for other images, or nil.
local function find_file(src)
  if pandoc.path.is_absolute(src) then
    return file_exists(src) and src or nil
  end
  for _, dir in ipairs(PANDOC_STATE.resource_path) do
    local path = pandoc.path.join({ dir, src })
    if file_exists(path) then
      return path
    end
  end
  return nil
end

--- Returns a function that replaces diagram code blocks by images.
local function code_block_handler(limits, ext)
  return function(block)
    local name, spec = code_type(block.classes)
    if not name then
      return nil
    end

    local path, err = render(name, spec, ext, block.attributes, block.text)
    if not path then
      warn(name .. " rendering failed, keeping code block: " .. err)
      return nil
    end

    local attr = pandoc.Attr("", { "diagram" }, {})
    if block.attributes.width then
      attr.attributes.width = block.attributes.width
    elseif ext == "png" then
      attr.attributes.width = png_width(path, limits)
    end

    local caption = block.attributes.caption
    local alt = caption and { pandoc.Str(caption) } or {}
    local image = pandoc.Image(alt, path, "", attr)
    if caption then
      return pandoc.Figure(pandoc.Plain({ image }), { pandoc.Plain({ pandoc.Str(caption) }) })
    end
    return pandoc.Para({ image })
  end
end

--- Returns a function that replaces images of diagram files by rendered images.
local function image_handler(limits, ext)
  return function(image)
    local file_ext = image.src:match("%.([%w]+)$")
    local name = file_ext and file_ext:lower()
    local spec = name and FILE_TYPES[name]
    if not spec then
      return nil
    end

    -- Without a rendered image, the description replaces the image, as pandoc
    -- does for a missing image. Most writers cannot use the diagram file itself.
    local source = find_file(image.src)
    local content = source and read_file(source)
    if not content then
      warn(name .. " file not found, using its description: " .. image.src)
      return image.caption
    end

    local path, err = render(name, spec, ext, image.attributes, content, source)
    if not path then
      warn(name .. " export of " .. image.src .. " failed, using its description: " .. err)
      return image.caption
    end

    image.src = path
    if not image.classes:includes("diagram") then
      image.classes:insert("diagram")
    end
    for _, option in ipairs(spec.options) do
      image.attributes[option] = nil
    end
    if not image.attributes.width and ext == "png" then
      image.attributes.width = png_width(path, limits)
    end
    return image
  end
end

--- Returns the size limits from the metadata, in inches: a table with the
--- optional fields width and height.
local function size_limits(meta)
  local limits = {}
  for _, dimension in ipairs({ "width", "height" }) do
    local field = "diagram-max-" .. dimension
    if meta[field] ~= nil then
      limits[dimension] = to_inches(pandoc.utils.stringify(meta[field]))
      if not limits[dimension] then
        warn("ignoring " .. field .. ", use e.g. 170mm, 17cm or 6.7in")
      end
    end
  end
  return limits
end

function Pandoc(doc)
  local limits = size_limits(doc.meta)
  local override = nil
  local format = doc.meta["diagram-format"]
  if format ~= nil then
    override = pandoc.utils.stringify(format)
    if override ~= "svg" and override ~= "png" then
      warn("ignoring diagram-format, use svg or png")
      override = nil
    end
  end
  local ext = image_type(override)
  return doc:walk({
    CodeBlock = code_block_handler(limits, ext),
    Image = image_handler(limits, ext),
  })
end
