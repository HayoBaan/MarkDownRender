--[[
md-links.lua — Pandoc Lua filter that rewrites links to Markdown files.

Relative links to `.md` or `.markdown` files get a different extension, so
links between documents keep working after rendering them all, e.g. to HTML.
Any `#fragment` is kept. Absolute URLs (anything with a scheme, such as
`https:` or `mailto:`) and pure `#fragment` links are left alone.

The new extension comes from the metadata field `md-link-ext`:
  pandoc -L md-links.lua -M md-link-ext=html input.md -o output.html

With the metadata field `md-link-unlink` set to true, links to other local
files are replaced by their plain link text instead. This suits PDF: most PDF
viewers refuse to open another file from a link, e.g. macOS Preview because of
its sandbox. Absolute URLs and pure `#fragment` links stay links.
  pandoc -L md-links.lua -M md-link-unlink=true input.md -o output.pdf

Without either field the filter does nothing.
]]

--- Returns true when a link target is a relative link to another file: not
--- empty, without a scheme such as `https:`, and not a pure `#fragment`.
local function is_local_file(target)
  return target ~= "" and not target:match("^%a[%w+.-]*:") and not target:match("^#")
end

--- Returns the target with its Markdown extension replaced, or nil if it is not a local Markdown link.
local function rewrite(target, ext)
  if not is_local_file(target) then
    return nil
  end
  local path, fragment = target:match("^([^#]*)(#.*)$")
  if not path then
    path, fragment = target, ""
  end
  local base = path:match("^(.*)%.md$") or path:match("^(.*)%.markdown$")
  if not base then
    return nil
  end
  return base .. "." .. ext .. fragment
end

function Pandoc(doc)
  local ext = nil
  local value = doc.meta["md-link-ext"]
  if value ~= nil then
    ext = pandoc.utils.stringify(value):gsub("^%.", "")
    if ext == "" then
      ext = nil
    end
  end
  local unlink = doc.meta["md-link-unlink"] == true
    or pandoc.utils.stringify(doc.meta["md-link-unlink"] or "") == "true"
  if not ext and not unlink then
    return nil
  end
  return doc:walk({
    Link = function(link)
      if unlink and is_local_file(link.target) then
        return link.content
      end
      local target = ext and rewrite(link.target, ext)
      if target then
        link.target = target
        return link
      end
    end,
  })
end
