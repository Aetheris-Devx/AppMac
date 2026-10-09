# AppMac

A minimal Apple / macOS Liquid Glass UI library for Roblox (Luau).

## Features

- **Frosted glass window**: Translucent surface with diagonal sheen, gradient rim light, and soft shadow
- **macOS traffic lights**: Close, minimize, and zoom buttons with full functionality
- **Draggable top bar**: Move windows around easily
- **Minimizes to orb**: Compact button for minimized state
- **Sidebar tabs**: Minimal tab list with smooth animated transitions
- **Rich elements**: Sections, labels, buttons, toggles, sliders, dropdowns, inputs, keybinds
- **Notifications**: Slide in from the right with progress bar, click to dismiss
- **Themes**: Dark and Light modes with custom accent color
- **BlurEffect support**: Optional background blur
- **Mobile-friendly**: Responsive design for all screen sizes

## Quick Start

### Installation

```lua
local AppMac = loadstring(game:HttpGet("https://raw.githubusercontent.com/Aetheris-Devx/AppMac/main/src/AppMac.lua"))()
```

That's it! No need to install anything to ReplicatedStorage.

### Basic Usage

```lua
local AppMac = loadstring(game:HttpGet("https://raw.githubusercontent.com/Aetheris-Devx/AppMac/main/src/AppMac.lua"))()

local Window = AppMac:CreateWindow({
	Title = "My App",
	Theme = "Dark",
	ToggleKey = Enum.KeyCode.RightShift,
	Blur = false, -- Optional background blur
})

-- Create a tab
local Main = Window:CreateTab("Main")

-- Add a button
Main:Button({
	Name = "Click me",
	Description = "Optional description",
	Callback = function()
		Window:Notify({
			Title = "Hello",
			Content = "Button clicked!",
			Type = "Success", -- Info, Success, Warning, Error
			Duration = 5,
		})
	end,
})

-- Add a toggle
Main:Toggle({
	Name = "Feature",
	Default = false,
	Color = Color3.fromRGB(52, 168, 83), -- Optional
	Callback = function(value)
		print("Toggle:", value)
	end,
})

-- Add a slider
Main:Slider({
	Name = "Volume",
	Min = 0,
	Max = 100,
	Default = 50,
	Increment = 1,
	Suffix = "%",
	Callback = function(value)
		print("Volume:", value)
	end,
})
```

## API Reference

### Window

```lua
local Window = AppMac:CreateWindow(options)

-- Options
{
	Title = "Window Title",           -- string
	Theme = "Dark",                  -- "Dark" or "Light"
	Accent = Color3.fromRGB(...),    -- Color3 (optional)
	ToggleKey = Enum.KeyCode...,     -- Toggle visibility key
	Blur = true,                     -- boolean, adds background blur
	Size = {width, height},          -- {number, number}, default auto
	Parent = ScreenGui,              -- Instance (optional)
}

-- Methods
Window:CreateTab(name)               -- Create a new tab (string or {name, icon})
Window:Show()                        -- Show window
Window:Hide()                        -- Hide window
Window:Toggle()                      -- Toggle visibility
Window:ToggleZoom()                  -- Toggle maximize/normal
Window:Destroy()                     -- Remove window
Window:SetToggleKey(keyCode)         -- Change toggle key
Window:Notify(options)               -- Show notification
```

### Tab

```lua
local Tab = Window:CreateTab("TabName")

-- Methods
Tab:Section(name)                    -- Create a section header
Tab:Label(text)                      -- Simple text label (returns {Set(text)})
Tab:Paragraph(options)               -- Multi-line text
Tab:Button(options)                  -- Interactive button
Tab:Toggle(options)                  -- On/off toggle switch
Tab:Slider(options)                  -- Numeric slider
Tab:Dropdown(options)                -- Select from list
Tab:Input(options)                   -- Text input field
Tab:Keybind(options)                 -- Key binding selector
```

### Elements

#### Section
```lua
Tab:Section("Settings")
```

#### Label
```lua
local Label = Tab:Label("Hello World")
Label:Set("New text")
```

#### Paragraph
```lua
Tab:Paragraph({
	Title = "Info",
	Content = "This is a paragraph with more text.",
})
```

#### Button
```lua
Tab:Button({
	Name = "Click",
	Description = "Optional description",
	Callback = function()
		print("Button pressed")
	end,
})
```

#### Toggle
```lua
Tab:Toggle({
	Name = "Enable feature",
	Default = false,
	Color = Color3.fromRGB(52, 168, 83), -- Optional, green by default
	Callback = function(value)
		print("Toggle state:", value)
	end,
})
```

#### Slider
```lua
Tab:Slider({
	Name = "Volume",
	Min = 0,
	Max = 100,
	Default = 50,
	Increment = 5,
	Suffix = "%",
	Callback = function(value)
		print("Slider value:", value)
	end,
})
```

#### Dropdown
```lua
Tab:Dropdown({
	Name = "Quality",
	Options = {"Low", "Medium", "High", "Ultra"},
	Default = "Medium",
	Placeholder = "Select...",
	Callback = function(value)
		print("Selected:", value)
	end,
})
```

#### Input
```lua
Tab:Input({
	Name = "Name",
	Placeholder = "Enter your name",
	Default = "Player",
	ClearOnFocus = false,
	Callback = function(text, enterPressed)
		if enterPressed then
			print("Submitted:", text)
		else
			print("Text changed:", text)
		end
	end,
})
```

#### Keybind
```lua
Tab:Keybind({
	Name = "Bind action",
	Default = Enum.KeyCode.E,
	Callback = function()
		print("Key pressed!")
	end,
	Changed = function(keyCode)
		print("Keybind changed to:", keyCode)
	end,
})
```

### Notifications

```lua
Window:Notify({
	Title = "Alert",
	Content = "Something happened",
	Type = "Info",        -- Info, Success, Warning, Error
	Duration = 5,         -- seconds (optional, default 5)
})
```

## Examples

### Full Example

```lua
local AppMac = loadstring(game:HttpGet("https://raw.githubusercontent.com/Aetheris-Devx/AppMac/main/src/AppMac.lua"))()

local Window = AppMac:CreateWindow({
	Title = "AppMac Demo",
	Theme = "Dark",
	Accent = Color3.fromRGB(0, 122, 255),
})

-- Home Tab
local Home = Window:CreateTab("Home")
Home:Section("Welcome")
Home:Paragraph({
	Title = "AppMac",
	Content = "A minimal macOS Liquid Glass UI library for Roblox. Drag the top bar, press RightShift to toggle.",
})
Home:Button({
	Name = "Show notification",
	Callback = function()
		Window:Notify({
			Title = "Demo",
			Content = "This is a notification!",
			Type = "Success",
		})
	end,
})

-- Settings Tab
local Settings = Window:CreateTab("Settings")
Settings:Section("Theme")
Settings:Toggle({
	Name = "Dark mode",
	Default = true,
	Callback = function(value)
		print("Dark mode:", value)
	end,
})

Settings:Section("Audio")
Settings:Slider({
	Name = "Volume",
	Min = 0,
	Max = 100,
	Default = 50,
	Increment = 1,
	Suffix = "%",
})
```

## Controls

- **Toggle**: Press `RightShift` (default) to show/hide window
- **Drag**: Click and drag the top bar to move
- **Close**: Click the red traffic light button
- **Minimize**: Click the yellow traffic light button (becomes an orb)
- **Maximize**: Click the green traffic light button

## License

MIT License - See LICENSE file for details

## GitHub

https://github.com/Aetheris-Devx/AppMac

## Support

For issues, feature requests, or questions, please open an issue on GitHub.
