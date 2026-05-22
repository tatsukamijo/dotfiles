require("clipimg")

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
