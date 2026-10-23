-- Dia focus helpers: give keyboard focus to the page so Vimium j/k work.
-- Ctrl+;            focus the page (Dia only; Ctrl+; elsewhere, e.g. nvim's
--                   <C-;>, passes through untouched)
-- Ctrl+(Shift+)Tab  Dia switches tabs natively (its switcher overlay stays
--                   up while Ctrl is held); on Ctrl release we focus the page
-- Enter             in the command bar: once it closes, focus the new page
local M = {}

local DIA_BUNDLE = "company.thebrowser.dia"
local SWITCH_DELAY = 0.15  -- after Ctrl release; raise if heavy pages are not ready
local COMMAND_BAR_TIMEOUT = 2  -- seconds to wait for the bar to close
local VERIFY_DELAY = 0.15  -- wait before checking the AX focus took effect
local AX_TRIES = 3  -- AX focus attempts before falling back to a click

local keys = hs.keycodes.map
local types = hs.eventtap.event.types

-- The page's web area. Picks the largest AXWebArea so Dia's chat sidebar
-- (also a web view) is never the target; iframes are not descended.
local function pageArea(win)
  local root = hs.axuielement.windowElement(win)
  if not root then return nil end
  local best, bestArea = nil, 0
  local function walk(e, depth)
    if depth > 30 then return end
    if e:attributeValue("AXRole") == "AXWebArea" then
      local f = e:attributeValue("AXFrame")
      if f and f.w * f.h > bestArea then best, bestArea = e, f.w * f.h end
      return
    end
    for _, c in ipairs(e:attributeValue("AXChildren") or {}) do walk(c, depth + 1) end
  end
  walk(root, 0)
  return best
end

-- Dia's keyboard-focused element, and whether it sits inside a page.
local function focusedElement(app)
  return hs.axuielement.applicationElement(app):attributeValue("AXFocusedUIElement")
end

local function inPage(el)
  for _ = 1, 60 do
    if not el then return false end
    if el:attributeValue("AXRole") == "AXWebArea" then return true end
    el = el:attributeValue("AXParent")
  end
  return false
end

-- Fallback: click the page's left margin at mid-height (usually blank
-- padding; corners tend to hold chat inputs and widgets), then restore the
-- mouse. Flags are cleared so a held Ctrl doesn't make it a Ctrl-click,
-- which macOS turns into a context menu.
local function clickPage(f)
  local pt = { x = f.x + 5, y = f.y + f.h / 2 }
  local orig = hs.mouse.absolutePosition()
  hs.eventtap.event.newMouseEvent(types.leftMouseDown, pt):setFlags({}):post()
  hs.eventtap.event.newMouseEvent(types.leftMouseUp, pt):setFlags({}):post()
  hs.mouse.absolutePosition(orig)
end

-- Focus the page's web area via Accessibility (no mouse, so nothing on the
-- page gets clicked). A page still loading can ignore it, so retry a few
-- times, then fall back to a click.
function M.focusPage()
  local app = hs.application.frontmostApplication()
  if not app or app:bundleID() ~= DIA_BUNDLE then return end
  local win = app:focusedWindow()
  if not win then return end
  local area = pageArea(win)
  if not area then clickPage(win:frame()); return end
  local tries = 0
  local function attempt()
    area:setAttributeValue("AXFocused", true)
    tries = tries + 1
    M.verify = hs.timer.doAfter(VERIFY_DELAY, function()
      local el = focusedElement(app)
      if el and el:attributeValue("AXRole") == "AXWebArea" then return end
      if tries < AX_TRIES then return attempt() end
      local f = area:attributeValue("AXFrame")
      if f then clickPage(f) end
    end)
  end
  attempt()
end

local function schedule(delay)
  if M.timer then M.timer:stop() end
  M.timer = hs.timer.doAfter(delay, M.focusPage)
end

-- After Enter in the command bar: poll until the bar has closed (focus left
-- the text field), then focus the page. Stops early if the page already has
-- focus; focuses anyway on timeout.
local function focusAfterCommandBar()
  if M.timer then M.timer:stop() end
  local deadline = hs.timer.secondsSinceEpoch() + COMMAND_BAR_TIMEOUT
  M.timer = hs.timer.doEvery(0.1, function()
    local app = hs.application.frontmostApplication()
    if not app or app:bundleID() ~= DIA_BUNDLE then M.timer:stop(); return end
    local el = focusedElement(app)
    if inPage(el) then M.timer:stop(); return end
    local role = el and el:attributeValue("AXRole")
    local typing = role == "AXTextField" or role == "AXTextArea" or role == "AXComboBox"
    if typing and hs.timer.secondsSinceEpoch() < deadline then return end
    M.timer:stop()
    M.focusPage()
  end)
end

-- One tap instead of hotkeys: hotkeys would swallow Ctrl+; in every app, and
-- re-sending Ctrl+Tab needs a disable/keyStroke/enable dance.
function M.start()
  M.tap = hs.eventtap.new({ types.keyDown, types.flagsChanged }, function(e)
    local code, flags = e:getKeyCode(), e:getFlags()
    if e:getType() == types.flagsChanged then
      -- Focusing while Ctrl is held would dismiss Dia's tab switcher.
      if M.tabPending and not flags.ctrl then
        M.tabPending = false
        schedule(SWITCH_DELAY)
      end
      return false
    end
    local isTab = code == keys.tab
      and (flags:containExactly({ "ctrl" }) or flags:containExactly({ "ctrl", "shift" }))
    local isFocus = code == keys[";"] and flags:containExactly({ "ctrl" })
    local isEnter = code == keys["return"] and not (flags.ctrl or flags.alt)
    if not (isTab or isFocus or isEnter) then return false end

    local app = hs.application.frontmostApplication()
    if not app or app:bundleID() ~= DIA_BUNDLE then return false end

    if isEnter then
      -- Only Enter in Dia's own UI (command bar); Enter in a page is left alone.
      if not inPage(focusedElement(app)) then focusAfterCommandBar() end
      return false
    end
    if isTab then
      if M.timer then M.timer:stop() end
      M.tabPending = true  -- focus on Ctrl release (flagsChanged above)
      return false  -- let Dia switch the tab itself
    end
    schedule(0)  -- focus outside the tap callback
    return true
  end):start()
end

return M
