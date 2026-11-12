-- Infrastructure first, so these stay live even if a require() below errors.

-- Local message port for the `hs` CLI (`hs -c 'hs.reload()'`). Any process
-- running as this user can send Lua through it — that is how the CLI works.
require("hs.ipc")

-- Auto-reload on config changes: clipimg.lua reads the local-only
-- clipimg-hosts.lua once at load time, so editing the host map needs a reload.
-- Global on purpose — a local watcher is garbage-collected when this chunk
-- finishes and silently stops firing.
configWatcher = hs.pathwatcher.new(os.getenv("HOME") .. "/.hammerspoon/", function(files)
	for _, file in ipairs(files) do
		-- Skip Spoons (can write .lua → reload loop) and editor temp dotfiles.
		if file:match("%.lua$") and not file:match("/Spoons/") and not file:match("/%.[^/]*$") then
			hs.reload()
			return
		end
	end
end):start()

require("clipimg")
require("dia_focus").start()

local kittyWasActive = false

hs.window.filter.default:subscribe(hs.window.filter.windowFocused, function(window)
	if window then
		local app = window:application()
		if app then
			local name = app:name()
			if name == "kitty" then
				kittyWasActive = true
			elseif name ~= "Preview" and name ~= "mpv" and name ~= "qlmanage" and name ~= "QuickTime Player" then
				kittyWasActive = false
			end
		end
	end
end)

local function focusKittyIfNeeded()
	if kittyWasActive then
		local kitty = hs.application.get("kitty")
		if kitty then
			kitty:activate()
		end
	end
end

local apps = { "Preview", "mpv", "qlmanage", "QuickTime Player" }
for _, app in ipairs(apps) do
	hs.window.filter.new(app):subscribe(hs.window.filter.windowDestroyed, focusKittyIfNeeded)
end
