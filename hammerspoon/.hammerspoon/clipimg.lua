-- Cmd+Ctrl+V: send Mac clipboard image to focused remote SSH terminal.
-- Detects target host from frontmost terminal window title (set by remote
-- bashrc / tmux to `hostname -s`).
local M = {}

-- Host map: short hostname → ~/.ssh/config Host alias.
-- Kept out of the repo (potentially sensitive). Define it in a local-only file:
--   ~/.hammerspoon/clipimg-hosts.lua
-- which returns a table like:
--   return { ["robot-dev7"] = "robot_dev7", ["airoa-dev-5070-01"] = "airoa01" }
-- See `clipimg-hosts.lua.example` in this directory for a template.
M.hosts = {}
do
  local path = os.getenv("HOME") .. "/.hammerspoon/clipimg-hosts.lua"
  local chunk = loadfile(path)
  if chunk then
    local ok, loaded = pcall(chunk)
    if ok and type(loaded) == "table" then M.hosts = loaded end
  end
end

M.terminals = { Ghostty=true, iTerm2=true, Alacritty=true, WezTerm=true,
                kitty=true, Terminal=true }

-- Apple Silicon path; change to /usr/local/bin/pngpaste on Intel.
local PNGPASTE = "/opt/homebrew/bin/pngpaste"

local function notify(t, s)
  hs.alert.show("clipimg: "..t..(s and s ~= "" and " — "..s or ""), 2)
end

local function frontHost()
  local app = hs.application.frontmostApplication()
  if not app or not M.terminals[app:name()] then
    return nil, "front app not a known terminal: "..(app and app:name() or "nil")
  end
  local win = app:focusedWindow()
  if not win then return nil, "no focused window" end
  local title = win:title() or ""
  for short, _ in pairs(M.hosts) do
    if title:find(short, 1, true) then return short end
  end
  return nil, "no known host in title: "..title
end

function M.paste()
  hs.alert.show("clipimg: ⌘⌃V", 1)
  local host, err = frontHost()
  if not host then notify("skip", err); return end
  local alias = M.hosts[host]
  local script = string.format(
    [[set -o pipefail; %s - | ssh -o BatchMode=yes -o ConnectTimeout=5 -o ServerAliveInterval=5 -o ForwardX11=no -o ForwardX11Trusted=no -o ControlMaster=auto -o ControlPath=$HOME/.ssh/cm-clipimg-%%r@%%h:%%p -o ControlPersist=60 %s 'PATH=$HOME/.pixi/bin:$HOME/.local/bin:$PATH $HOME/.local/bin/clipimg-recv']],
    PNGPASTE, alias
  )
  local task = hs.task.new("/bin/bash", function(exitCode, stdOut, stdErr)
    if exitCode == 0 then
      notify("→ "..host)
    else
      local msg = (stdErr ~= nil and stdErr ~= "") and stdErr or stdOut
      notify("fail rc="..tostring(exitCode), msg)
    end
  end, { "-lc", script })
  task:start()
end

hs.hotkey.bind({"cmd","ctrl"}, "v", M.paste)

return M
