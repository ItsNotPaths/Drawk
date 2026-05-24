## Drawk — wayluigi-backed dmenu replacement.
##
## Reads newline-separated items from stdin, opens a centered floating
## window with a search field and filtered list, prints the chosen item
## to stdout on Enter (exit 0) or exits 1 on Escape / empty stdin.
##
## Designed for Sway. Requires a `for_window [title="^Drawk$"]` rule
## (see README) so the window comes up floating + centered at map time,
## with no tile-then-float flash. Title-match is used instead of app_id
## because wayluigi sets title unconditionally before the first commit.

import std/[os, osproc, strutils]
import rawk_luigi, theme

const
  fontSize:     uint32 = 12
  windowW:      cint   = 480
  windowH:      cint   = 304    # 19 list rows + 1 prompt row at rowH=16 (FreeType height for size 12 with mono leading); change in lockstep with sway rule
  rowPadding:   cint   = 0
  blinkPeriod:  int    = 25     # ~500ms at luigi's ~50Hz animate tick

# ---------- font helper (inlined from rawk-bufferlib's font.nim) ----------

proc systemMonoPath(): string =
  let override = getEnv("RAWK_FONT")
  if override.len > 0 and fileExists(override):
    return override
  try:
    let (output, code) = execCmdEx("fc-match --format=%{file} monospace:mono")
    if code == 0:
      let p = output.strip()
      if p.len > 0 and fileExists(p):
        return p
  except CatchableError:
    discard
  return ""

proc loadFont() =
  let path = systemMonoPath()
  if path.len == 0: return
  let f = fontCreate(path.cstring, fontSize)
  if f != nil:
    discard fontActivate(f)

# ---------- state ----------

type Drawk = object
  e*:            Element    # must be first; cast ptr Element <-> ptr Drawk
  items*:        seq[string]
  filtered*:     seq[int]
  query*:        string
  selected*:     int
  scroll*:       int
  caretVisible*: bool
  blinkTicks*:   int

proc rowHeight(): cint =
  let gh = if ui.activeFont != nil: ui.activeFont.glyphHeight else: 16.cint
  gh + rowPadding

proc recomputeFilter(d: ptr Drawk) =
  d.filtered.setLen(0)
  let q = d.query.toLowerAscii
  for i, it in d.items:
    if q.len == 0 or q in it.toLowerAscii:
      d.filtered.add(i)
  d.selected = 0
  d.scroll = 0

# ---------- painting ----------

proc paint(d: ptr Drawk, p: ptr Painter) =
  let b = d.e.bounds
  let rowH = rowHeight()

  # 1. Background.
  drawBlock(p, b, ui.theme.panel1)

  # 2. Prompt row at top with blinking caret. Monospace font: " " and "|"
  # are the same advance width, so swapping them keeps the centered text
  # from jittering as the caret blinks.
  let promptRect = Rectangle(l: b.l, r: b.r, t: b.t, b: b.t + rowH)
  drawBlock(p, promptRect, ui.theme.textboxFocused)
  let caretChar = if d.caretVisible: "|" else: " "
  let promptText = d.query & caretChar
  drawString(p, promptRect, promptText.cstring, promptText.len,
             ui.theme.text, ALIGN_CENTER)

  # 3. Visible filtered rows.
  if d.filtered.len == 0: return
  let listTop = b.t + rowH
  let listH   = b.b - listTop
  if listH <= 0: return
  let visibleRows = max(1, listH div rowH)

  # Clamp scroll so selected stays in view.
  if d.selected < d.scroll: d.scroll = d.selected
  elif d.selected >= d.scroll + visibleRows:
    d.scroll = d.selected - visibleRows + 1
  if d.scroll < 0: d.scroll = 0
  let lastVisible = min(d.filtered.len, d.scroll + visibleRows)

  for i in d.scroll ..< lastVisible:
    let row = i - d.scroll
    let rTop = listTop + cint(row) * rowH
    let rect = Rectangle(l: b.l, r: b.r, t: rTop, b: rTop + rowH)
    let isSelected = (i == d.selected)
    if isSelected:
      drawBlock(p, rect, ui.theme.selected)
    let s = d.items[d.filtered[i]]
    let color = if isSelected: ui.theme.textSelected else: ui.theme.text
    drawString(p, rect, s.cstring, s.len, color, ALIGN_CENTER)

# ---------- key handling ----------

proc handleKey(d: ptr Drawk, k: ptr KeyTyped): cint =
  let win = d.e.window
  if k.code == int(KEYCODE_ESCAPE):
    quit(1)
  elif k.code == int(KEYCODE_ENTER):
    if d.filtered.len > 0:
      stdout.writeLine(d.items[d.filtered[d.selected]])
      stdout.flushFile()
      quit(0)
    return 1
  elif k.code == int(KEYCODE_UP):
    if d.selected > 0: dec d.selected
  elif k.code == int(KEYCODE_DOWN):
    if d.selected < d.filtered.len - 1: inc d.selected
  elif k.code == int(KEYCODE_BACKSPACE):
    if d.query.len > 0:
      # ASCII-only backspace. UTF-8-aware boundary walking = TODO.
      d.query.setLen(d.query.len - 1)
      recomputeFilter(d)
  elif k.code == int(KEYCODE_TAB):
    discard  # consume so wayluigi doesn't cycle focus / insert literal tab
  elif win.ctrl and k.code == int(KEYCODE_LETTER('P')):
    if d.selected > 0: dec d.selected
  elif win.ctrl and k.code == int(KEYCODE_LETTER('N')):
    if d.selected < d.filtered.len - 1: inc d.selected
  elif k.text != nil and k.textBytes > 0:
    # Accept UTF-8; only strip ASCII control bytes.
    for i in 0 ..< int(k.textBytes):
      let b = byte(cast[ptr UncheckedArray[byte]](k.text)[i])
      if b >= 0x20'u8 and b != 0x7F'u8:
        d.query.add(char(b))
    recomputeFilter(d)
  else:
    return 0
  elementRepaint(addr d.e, nil)
  return 1

# ---------- message dispatch ----------

proc drawkMessage(element: ptr Element, m: Message, di: cint,
                  dp: pointer): cint {.cdecl.} =
  let d = cast[ptr Drawk](element)
  case m
  of msgPaint:
    paint(d, cast[ptr Painter](dp))
    return 1
  of msgKeyTyped:
    # Any keystroke restarts the blink cycle from "on" so the cursor
    # visibly tracks the user's edits instead of disappearing mid-key.
    d.caretVisible = true
    d.blinkTicks = 0
    return handleKey(d, cast[ptr KeyTyped](dp))
  of msgAnimate:
    inc d.blinkTicks
    if d.blinkTicks >= blinkPeriod:
      d.blinkTicks = 0
      d.caretVisible = not d.caretVisible
      elementRepaint(element, nil)
    return 0
  of msgDestroy:
    `=destroy`(d[])
    return 0
  else:
    return 0

# ---------- main ----------

var stdinItems: seq[string] = @[]
for line in stdin.lines:
  stdinItems.add(line)
if stdinItems.len == 0:
  quit(1)

initialise()
loadInitialTheme()
loadFont()

let win = windowCreate(nil, 0, "Drawk", windowW, windowH)

let elemPtr = elementCreate(csize_t(sizeof(Drawk)), addr win.e,
                            ELEMENT_TAB_STOP or ELEMENT_V_FILL or ELEMENT_H_FILL,
                            drawkMessage, "Drawk")
let d = cast[ptr Drawk](elemPtr)
# elementCreate zero-initialised the bytes; rebuild Nim-managed fields in place.
d.items        = stdinItems
d.filtered     = @[]
d.query        = ""
d.selected     = 0
d.scroll       = 0
d.caretVisible = true
d.blinkTicks   = 0
recomputeFilter(d)

elementFocus(elemPtr)
discard elementAnimate(elemPtr, false)  # start the blink ticker
quit messageLoop()
