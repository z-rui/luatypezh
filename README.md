# luatypezh

This is a handy script that helps me typeset Chinese w/ LuaTeX for my personal projects.

It does:

- Line breaking
- Punctuation compression
- Proper monospace font spacing (`\wd{中}` = `\wd{En}`)
- Rudimentary LaTeX support

It does not:

- Allow dynamic configuration in plain TeX.  (Edit the source if you need differenct typefaces)

# Usage

Before loading this script, you need a font loader that is capable of loading Chinese fonts (actually this script has one, but it is not bullet-proof and never works except on my Windows system).  Luaotfload is a great one:
```
\input luaotfload.sty
```
Or, in LaTeX,
```
\usepackage{luaotfload}
```
Then, just `\input luatypezh`. Don't bother with `\usepackage` because I really don't know how to write packages for LaTeX.

Then everything works.  If not:

- Check the font names in `luatypezh.tex`.  Change them to what you have/want.
- Happy debugging!
