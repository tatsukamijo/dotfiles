-- Dia focus helpers: give keyboard focus to the page so Vimium j/k work.
-- Ctrl+;            click inside the page (Dia only; Ctrl+; elsewhere, e.g.
--                   nvim's <C-;>, passes through untouched)
-- Ctrl+(Shift+)Tab  Dia switches tabs natively, then we focus the page
local M = {}

local DIA_BUNDLE = "company.thebrowser.dia"
local SWITCH_DELAY = 0.15  -- raise to 0.25 if heavy pages are not ready

local keys = hs.keycodes.map
local types = hs.eventtap.event.types

-- Frame of the page's web area. Picks the largest AXWebArea so Dia's chat
-- sidebar (also a web view) is never the target; iframes are not descended.
local function pageFrame(win)
  local root = hs.axuielement.windowElement(win)
  if not root then return nil end
  local best, bestArea = nil, 0
  local function walk(e, depth)
    if depth > 30 then return end
    if e:attributeValue("AXRole") == "AXWebArea" then
      local f = e:attributeValue("AXFrame")
      if f and f.w * f.h > bestArea then best, bestArea = f, f.w * f.h end
      return
    end
    for _, c in ipairs(e:attributeValue("AXChildren") or {}) do walk(c, depth + 1) end
  end
  walk(root, 0)
  return best
end

-- Click near the bottom-right of the page, then restore the mouse. Flags are
-- cleared so a still-held Ctrl (Ctrl+;, Ctrl+Tab) doesn't make it a
-- Ctrl-click, which macOS turns into a context menu.
-- Adjust offsets if the click hits a link or button on some site.
function M.focusPage()
  local app = hs.application.frontmostApplication()
  if not app or app:bundleID() ~= DIA_BUNDLE then return end
  local win = app:focusedWindow()
  if not win then return end
  local f = pageFrame(win) or win:frame()
  local pt = { x = f.x + f.w - 40, y = f.y + f.h - 15 }
  local orig = hs.mouse.absolutePosition()
  hs.eventtap.event.newMouseEvent(types.leftMouseDown, pt):setFlags({}):post()
  hs.eventtap.event.newMouseEvent(types.leftMouseUp, pt):setFlags({}):post()
  hs.mouse.absolutePosition(orig)
end

local function schedule(delay)
  if M.timer then M.timer:stop() end
  M.timer = hs.timer.doAfter(delay, M.focusPage)
end

-- One keyDown tap instead of hotkeys: hotkeys would swallow Ctrl+; in every
-- app, and re-sending Ctrl+Tab needs a disable/keyStroke/enable dance.
function M.start()
  M.tap = hs.eventtap.new({ types.keyDown }, function(e)
    local code, flags = e:getKeyCode(), e:getFlags()
    local isTab = code == keys.tab
      and (flags:containExactly({ "ctrl" }) or flags:containExactly({ "ctrl", "shift" }))
    local isFocus = code == keys[";"] and flags:containExactly({ "ctrl" })
    if not (isTab or isFocus) then return false end

    local app = hs.application.frontmostApplication()
    if not app or app:bundleID() ~= DIA_BUNDLE then return false end

    if isTab then
      schedule(SWITCH_DELAY)
      return false  -- let Dia switch the tab itself
    end
    schedule(0)  -- click outside the tap callback
    return true
  end):start()
end

return M
