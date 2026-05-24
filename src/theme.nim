import std/[os, strutils, algorithm]
import rawk_luigi

type Palette* = object
  bg*, fg*, accent*, muted*, urgent*: uint32
  borderLight*, borderDark*, separator*: uint32
  codeKeyword*, codeString*, codeComment*, codeNumber*, codeOperator*: uint32
  codeType*, codeReturnType*: uint32
  clInject*: uint32

var currentPalette*: Palette

const gruvboxMaterialDark* = Palette(
  bg:             0x292828'u32,
  fg:             0xd4be98'u32,
  accent:         0x9253be'u32,
  muted:          0x928374'u32,
  urgent:         0xea6962'u32,
  borderLight:    0x504945'u32,
  borderDark:     0x32302f'u32,
  separator:      0x45403d'u32,
  codeKeyword:    0xd3869b'u32,
  codeString:     0xd8a657'u32,
  codeComment:    0x928374'u32,
  codeNumber:     0xd3869b'u32,
  codeOperator:   0xe78a4e'u32,
  codeType:       0xa9b665'u32,
  codeReturnType: 0x89b482'u32,
  clInject:       0xff0000'u32,
)

const globalThemeName* = "global"
  ## Sentinel passed via `--theme global` (the default). Tells Drawk to
  ## adopt whatever palette Thrawk last wrote to ~/.config/unrawk/active.theme.

var
  # Themes ship as themes/gruvbox.theme and themes/zenburn.theme. If neither
  # is found at runtime, `loadInitialTheme` falls back to the hardcoded
  # `gruvboxMaterialDark` palette above.
  activeTheme*: string = globalThemeName
  discoveredThemes: seq[string]

proc themeDirs(): seq[string] =
  ## Search paths: per-user first, then alongside the binary. First hit wins.
  @[getConfigDir() / "Drawk" / "themes", getAppDir() / "themes"]

proc discoverThemes*() =
  discoveredThemes.setLen(0)
  for dir in themeDirs():
    if not dirExists(dir): continue
    for kind, path in walkDir(dir, relative = true):
      if kind != pcFile: continue
      let (_, name, ext) = splitFile(path)
      if ext == ".theme" and name.len > 0 and name notin discoveredThemes:
        discoveredThemes.add(name)
  sort(discoveredThemes, system.cmp)

proc themePath(name: string): string =
  for dir in themeDirs():
    let p = dir / (name & ".theme")
    if fileExists(p): return p
  ""

proc parseHex(s: string): uint32 =
  let t = s.strip().strip(chars = {'#'})
  if t.len == 6:
    result = uint32(parseHexInt(t))

proc parsePalette*(content: string, p: var Palette): bool =
  ## Accepts every key the shared rawk theme files use; Drawk only consumes
  ## a subset in apply() but parses the rest as no-ops so default.theme /
  ## zenburn.theme from sibling rawk apps load without errors.
  if content.len == 0: return false
  for rawLine in content.splitLines():
    let line = rawLine.strip()
    if line.len == 0 or line.startsWith('#'): continue
    let colon = line.find(':')
    if colon <= 0: continue
    let key = line[0 ..< colon].strip()
    let val = parseHex(line[colon+1 .. ^1])
    case key
    of "bg":               p.bg = val
    of "fg":               p.fg = val
    of "accent":           p.accent = val
    of "muted":            p.muted = val
    of "urgent":           p.urgent = val
    of "border_light":     p.borderLight = val
    of "border_dark":      p.borderDark = val
    of "separator":        p.separator = val
    of "code_keyword":     p.codeKeyword = val
    of "code_string":      p.codeString = val
    of "code_comment":     p.codeComment = val
    of "code_number":      p.codeNumber = val
    of "code_operator":    p.codeOperator = val
    of "code_type":        p.codeType = val
    of "code_return_type": p.codeReturnType = val
    of "cl_inject":        p.clInject = val
    else: discard
  return true

proc apply(p: Palette) =
  ui.theme.panel1           = p.bg
  ui.theme.panel2           = p.borderLight
  ui.theme.selected         = p.accent
  ui.theme.border           = p.borderDark
  ui.theme.text             = p.fg
  ui.theme.textDisabled     = p.muted
  ui.theme.textSelected     = p.bg
  ui.theme.buttonNormal     = p.borderLight
  ui.theme.buttonHovered    = p.separator
  ui.theme.buttonPressed    = p.accent
  ui.theme.buttonDisabled   = p.borderDark
  ui.theme.textboxNormal    = p.borderLight
  ui.theme.textboxFocused   = p.separator
  currentPalette = p

proc themeNames*(): seq[string] =
  discoverThemes()
  result = discoveredThemes

proc loadThemeByName*(name: string): bool =
  let path = themePath(name)
  if path.len == 0: return false
  var body: string
  try: body = readFile(path)
  except IOError: return false
  var p = gruvboxMaterialDark
  discard parsePalette(body, p)
  apply(p)
  activeTheme = name
  return true

proc globalThemePath*(): string =
  ## Path Thrawk writes via `Thrawk --emit-active <name>`. Verbatim theme
  ## body in the same key:value format parsePalette consumes.
  getHomeDir() / ".config" / "unrawk" / "active.theme"

proc loadGlobalTheme*(): bool =
  let path = globalThemePath()
  if not fileExists(path): return false
  var body: string
  try: body = readFile(path)
  except IOError: return false
  var p = gruvboxMaterialDark
  if not parsePalette(body, p): return false
  apply(p)
  activeTheme = globalThemeName
  return true

proc loadInitialTheme*(name: string = globalThemeName) =
  ## `name` comes from the `--theme` CLI flag. "global" reads Thrawk's
  ## active.theme; any other string is looked up in the local themes dirs.
  ## Always succeeds — falls back to the baked-in gruvbox palette.
  discoverThemes()
  if name == globalThemeName:
    if loadGlobalTheme(): return
  elif loadThemeByName(name):
    return
  apply(gruvboxMaterialDark)
  activeTheme = "gruvbox"
