local callback_register

if luatexbase then
  callback_register = luatexbase.add_to_callback
else
  callback_register = callback.register
end

local zh = {
  specials = {},
  fontsubst = {},
  adjust = {},
  defaultadj = {
    gluefactor = 0.05,
    kernfactor = 0.5,
    [0x3002] = 1.05, -- 。
    [0xff0c] = 1.2, -- ，
    [0xff0e] = 1.2, -- ，
    [0x2018] = 1.2, -- ‘
    [0x2019] = 1.2, -- ’
  },
  nfsssubst = {},
}

function zh.setup(f, zhf, is_tt)
  zh.fontsubst[f] = zhf
  --print("zh setup:", f, zhf, is_tt)
  if is_tt then
    local scratchbox = tex.box[0]
    local tt_width = scratchbox.width*2
    zh.adjust[f] = {tt = tt_width}
  else
    zh.adjust[zhf] = zh.defaultadj
  end
end

function zh.nfss(f, zhf, is_tt)
  local subst = zh.nfsssubst
  --print("new nfss rule:", f, zhf, is_tt)
  subst[#subst+1] = {f, zhf, is_tt}
end

local dumbloader -- used here, defined in the end
function zh.nfsshook(fname)
  while fname:sub(-1) == ' ' do
    fname = fname:sub(1, -2)
  end
  local id = font.id(fname)
  if id == -1 then return -1 end -- nullfont?
  local subst = zh.fontsubst
  local zid = subst[id]
  --print("what to do with "..fname.."?")
  if zid then
    --print("hmm...I've seen that one")
    return zid
  end

  local subst = zh.nfsssubst
  for i = #subst, 1, -1 do
    local v = subst[i]
    local from, to, is_tt = v[1], v[2], v[3]
    local pat = from .. '(.*)'
    local size = fname:match(pat)
    if size then
      size = tonumber(size)
      --print("maybe map to "..to.." at size "..size.."?", is_tt)
      local zhft = dumbloader(to, 65536*size)
      zid = font.define(zhft)
      zh.setup(id, zid, is_tt)
      --print("ok, map "..id.." to "..zid)
      break
    end
  end
  return zid
end

function zh.mathhook(t, s, ss)
  local nfsshook = zh.nfsshook
  local definefont = tex.definefont
  t = nfsshook(t)
  s = nfsshook(s)
  ss = nfsshook(ss)
  -- can't directly define \textfont\zhfam, etc
  definefont(true, "zh@textfont", t)
  definefont(true, "zh@scriptfont", s)
  definefont(true, "zh@scriptscriptfont", ss)
end

function zh.setkind(codepoint, class)
  if class == 0 or class == nil then
    class = nil
  end
  zh.specials[codepoint] = class
end

function zh.getkind(cp)
  local kind = zh.specials[cp]
  if kind ~= nil then
    return kind
  end
  -- the following is hard-coded, and possibly wrong
  if 0x3000 <= cp and cp <= 0xd7A7 or 0xff00 <= cp and cp < 0xffe0 then
    return 3 -- cjk
  elseif 0x20000 <= cp and cp <= 0x2ebef then
    return 3 -- cjk-ext
  elseif 0xf900 <= cp and cp <= 0xfaff then
    return 3 -- cjk-compat
  end
end

local function zhglue(t, adj)
  local n = node.new "glue"
  local gf = 0
  if adj and not adj.tt then
    gf = adj.gluefactor
  end
--[[
  if gf==nil then
    for k,v in pairs(adj) do print(k,v) end
  end
--]]
  node.setglue(n,
    0, -- width
    gf * t.width, -- stretch
    0, -- stretch_order
    0, -- shrink
    0) -- shrink_order
  return n
end

local function negkern(t, adj)
  --print("negkern for", t.char)
  local n = node.new "kern"
  n.subtype = 0 -- font kern; won't be discarded at linebreak
  local kf = 0
  if adj then
    kf = (adj[t.char] or 1) * adj.kernfactor
  end
  n.kern = -kf * t.width
  return n
end

local function ttkern(t, adj_tt)
  --print("negkern for", t.char)
  local n = node.new "kern"
  n.subtype = 0 -- font kern; won't be discarded at linebreak
  n.kern = (adj_tt - t.width) / 2
  return n
end

local function zh_filter(head, groupcode)
  local node = node
  local ID_GLYPH = node.id "glyph"
  local adjust = zh.adjust
  for t in node.traverse(head) do
    if t.id == ID_GLYPH then
      local kind = zh.getkind(t.char)
      --print(t.char, kind)
      if kind then
        -- font substitution
        local zid = zh.fontsubst[t.font]
        local adj
        if zid ~= nil then
          adj = adjust[t.font]
          t.font = zid
        end
        if not adj then
          adj = adjust[t.font]
        end
        local adj_tt
        if adj then adj_tt = adj.tt end
        local maybeglue = false
        local tt = t
        if adj_tt then
          node.insert_before(head, t, ttkern(t, adj_tt))
        end
        --print(t.char, kind, adj_tt)
        if kind == 3 then
          maybeglue = true
        elseif kind == 1 then
          if not adj_tt then
            node.insert_before(head, t, negkern(t, adj))
          end
        elseif kind == 2 then
          maybeglue = true
          if not adj_tt then
            node.insert_after(head, t, negkern(t, adj))
            tt = tt.next
          end
        end
        if adj_tt then
          node.insert_after(head, tt, ttkern(t, adj_tt))
          tt = tt.next
        end
        if maybeglue then -- see if we need to insert a glue here
          local n = tt.next
          local nKind
          if n ~= nil and n.id == ID_GLYPH then
            nKind = zh.getkind(n.char)
          end
          if nKind == 1 or nKind == 3 then
            -- (c,l) or (c,c) or (r,l) or (r,c)
            node.insert_after(head, tt, zhglue(t, adj))
          end
        end
      end
    end
  end
  return true
end

callback_register('pre_linebreak_filter', zh_filter, 'zh_filter')
callback_register('hpack_filter', zh_filter, 'zh_filter')

-- 下面的 dumbloader 仅在我的 Windows 环境中有效。
local TEXMFVAR = kpse.expand_var('$TEXMFSYSVAR')
local CACHE_DIR = TEXMFVAR.."/luatex-cache/generic/fonts/otl"
local _cache = setmetatable({}, {__mode="v"})

function dumbloader(name, size)
  local f = _cache[name]
  if not f then
    -- don't bother with font names
    -- just use filenames
    local filepath = CACHE_DIR .. "/" .. name .. (jit and ".lub" or ".luc")
    -- .lua can also work,
    -- but don't bother compiling & caching them
    local ok
    ok, f = pcall(dofile, filepath)
    if not ok then
      return font.read_tfm(name, size)
    end
    texio.write("("..name..")")
    _cache[name] = f
  end

  if size < 0 then
    size = -655.36 * size
  end
  local mag = size / f.metadata.units

  local tfm =  {
    name = f.metadata.fontname,
    fullname = f.metadata.fontname,
    size = size,
    parameters = {
      slant = 0,
      space = size * 0.25,
      space_stretch = 0.3 * size,
      space_shrink = 0.1 * size,
      x_height = 0.4 * size,
      quad = 1.0 * size,
      extra_space = 0,
      no_math = true,
    },
    characters = {},
    filename = f.resources.filename,
    embedding = "subset",
    type = "real",
    format = f.format,
    cidinfo = f.resources.cidinfo,
  }
  local tables = f.tables
  local characters = tfm.characters
  local type = type -- used in a loop
  for k, v in pairs(f.descriptions) do
    local ch = { index=v.index }
    characters[k] = ch
    local wd = v.width
    if wd then
      wd = wd * mag
    end
    local bb = v.boundingbox
    if type(bb) == 'number' then
      bb = tables[bb]
    end
    if type(bb) == 'table' then
      ch.height = bb[4] * mag
      ch.depth = -bb[2] * mag
      if not wd then
        wd = (bb[3] - bb[1]) * mag
      end
    end
    ch.width = wd
  end
  -- no ligatures, math, fancy stuff, etc.
  -- I don't use them at all.
  return tfm
end

if not luaotfload then
callback_register('define_font', dumbloader, 'dumb font loader')
else
dumbloader = callback.find('define_font')
end -- not luaotfload

texio.write "(luatypezh.lua)"
return zh
-- vim: sw=2:ts=2:et
