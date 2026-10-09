-- Example LocalScript. With Rojo it is mounted at StarterPlayerScripts.
-- Without Rojo: put AppMac.lua in ReplicatedStorage as a ModuleScript named "AppMac"
-- and paste this into a LocalScript under StarterPlayer > StarterPlayerScripts.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AppMac = require(ReplicatedStorage:WaitForChild("AppMac"))

local Window = AppMac:CreateWindow({
	Title = "AppMac",
	Theme = "Dark", -- "Dark" | "Light"
	Accent = Color3.fromRGB(10, 132, 255),
	ToggleKey = Enum.KeyCode.RightShift,
	Blur = true,
})

-- Home -------------------------------------------------------------------------
local Home = Window:CreateTab("Home")

Home:Section("Welcome")
Home:Paragraph({
	Title = "AppMac",
	Content = "A minimal Liquid Glass UI library. Drag the top bar, press RightShift to hide, or use the traffic lights.",
})
Home:Button({
	Name = "Show notification",
	Description = "Slides in from the right with a progress line",
	Callback = function()
		Window:Notify({ Title = "Hello", Content = "This is a minimal glass notification.", Type = "Success", Duration = 4 })
	end,
})

-- Controls ---------------------------------------------------------------------
local Controls = Window:CreateTab("Controls")

Controls:Section("Toggles & sliders")
Controls:Toggle({
	Name = "Enable feature",
	Default = true,
	Callback = function(value)
		print("Toggle:", value)
	end,
})
Controls:Slider({
	Name = "Volume",
	Min = 0,
	Max = 100,
	Default = 60,
	Increment = 1,
	Suffix = "%",
	Callback = function(value)
		print("Volume:", value)
	end,
})
Controls:Slider({
	Name = "Speed",
	Min = 0.5,
	Max = 3,
	Default = 1,
	Increment = 0.1,
	Suffix = "x",
	Callback = function(value)
		print("Speed:", value)
	end,
})

Controls:Section("Choices")
Controls:Dropdown({
	Name = "Quality",
	Options = { "Low", "Medium", "High", "Ultra" },
	Default = "High",
	Callback = function(option)
		print("Quality:", option)
	end,
})
Controls:Input({
	Name = "Nickname",
	Placeholder = "Enter name",
	Callback = function(text, enterPressed)
		print("Nickname:", text, enterPressed)
	end,
})
Controls:Keybind({
	Name = "Quick action",
	Default = Enum.KeyCode.F,
	Callback = function()
		Window:Notify({ Title = "Keybind pressed", Type = "Info", Duration = 2 })
	end,
})

-- Settings ---------------------------------------------------------------------
local Settings = Window:CreateTab("Settings")

Settings:Section("Window")
Settings:Keybind({
	Name = "Toggle window",
	Default = Enum.KeyCode.RightShift,
	Changed = function(keyCode)
		Window:SetToggleKey(keyCode)
	end,
})
Settings:Label("Tip: the yellow button minimizes to a small orb, the green one zooms the window.")
