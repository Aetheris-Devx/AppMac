# AppMac

A minimal macOS Liquid Glass UI library for Roblox (Luau).

- Frosted glass window with a sheen, rim light and soft shadow
- macOS traffic lights, a draggable top bar, double-click the bar to zoom
- Minimizes into a Dynamic Island at the top of the screen, and grows back out of it
- Title and icon in the top-right corner, like a macOS toolbar
- Sidebar tabs with a sliding selection pill, and a button that collapses the sidebar down to tab icons
- A subtitle under the window title, and an optional subtitle under every page title
- A user chip at the bottom of the sidebar with the avatar and nickname of whoever runs the script
- Section, Label, Paragraph, Button, Toggle, Slider, Dropdown, Input and Keybind
- Notifications with a progress line
- Dark and Light themes, any accent color, optional background blur
- Spring animations that can be interrupted mid-motion without jumping
- Icons from about 1,800 bundled Lucide icons (by name) or any `rbxassetid://` image
- Touch friendly, fits any screen

## Install

Paste this into a LocalScript. Nothing else is needed.

```lua
local AppMac = loadstring(game:HttpGet("https://raw.githubusercontent.com/Aetheris-Devx/AppMac/main/src/AppMac.lua"))()
```

Using Roblox Studio instead? Put `src/AppMac.lua` in a ModuleScript named `AppMac` in ReplicatedStorage and require it:

```lua
local AppMac = require(game:GetService("ReplicatedStorage"):WaitForChild("AppMac"))
```

## Quick start

```lua
local AppMac = loadstring(game:HttpGet("https://raw.githubusercontent.com/Aetheris-Devx/AppMac/main/src/AppMac.lua"))()

local Window = AppMac:CreateWindow({
	Title = "My App",
	Theme = "Dark",
	Accent = Color3.fromRGB(10, 132, 255),
	ToggleKey = Enum.KeyCode.RightShift,
	Blur = true,
	Size = {560, 430},
	OrbIcon = "gamepad-2",
})

local Main = Window:CreateTab("Main")

Main:Button({
	Name = "Say hello",
	Callback = function()
		Window:Notify({ Title = "Hello", Content = "It works.", Type = "Success" })
	end,
})
```

## All elements

Every element goes inside a tab. The blocks below continue from Quick start, so `Window` already exists.

### Tab

A page in the sidebar. `Icon` takes a Lucide icon name or an `rbxassetid://` image.

```lua
local Tab = Window:CreateTab({
	Name = "Settings",
	Icon = "settings", -- Lucide icon name (lucide.dev)
	Subtitle = "Everything you can tweak", -- optional, shown under the page title
})

-- the same with an image
local Shop = Window:CreateTab({
	Name = "Shop",
	Icon = "rbxassetid://6031280882",
})
```

### Section

A heading that groups the elements below it.

```lua
Tab:Section("Settings")
```

### Label

A line of text you can change later.

```lua
local Label = Tab:Label("Plain label")

Label:Set("Updated text")
```

### Paragraph

A title with longer text underneath.

```lua
local Info = Tab:Paragraph({
	Title = "About",
	Content = "A longer piece of text that wraps over several lines.",
})

Info:Set("New title", "New content")
```

### Button

Runs a function when pressed.

```lua
Tab:Button({
	Name = "Click me",
	Description = "Optional description",
	Callback = function()
		print("clicked")
	end,
})
```

### Toggle

An on/off switch.

```lua
local Feature = Tab:Toggle({
	Name = "Enable feature",
	Default = false,
	Color = Color3.fromRGB(48, 209, 88), -- optional
	Callback = function(value)
		print("Toggle:", value)
	end,
})

Feature:Set(true)
```

### Slider

Pick a number in a range.

```lua
local Volume = Tab:Slider({
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

Volume:Set(75)
```

### Dropdown

Choose one option from a list.

```lua
local Quality = Tab:Dropdown({
	Name = "Quality",
	Options = {"Low", "Medium", "High", "Ultra"},
	Default = "Medium",
	Placeholder = "Select...",
	Callback = function(value)
		print("Selected:", value)
	end,
})

Quality:Set("High")
Quality:Refresh({"Low", "High"}) -- replace the options
```

### Input

A text field.

```lua
local Nickname = Tab:Input({
	Name = "Nickname",
	Placeholder = "Enter name",
	Default = "",
	ClearOnFocus = false,
	Callback = function(text, enterPressed)
		print(text, enterPressed)
	end,
})

print(Nickname:Get())
```

### Keybind

Lets the player pick a key. While it listens, Escape cancels and Backspace clears the key.

```lua
Tab:Keybind({
	Name = "Action key",
	Default = Enum.KeyCode.E,
	Callback = function()
		print("key pressed")
	end,
	Changed = function(keyCode)
		print("rebound to", keyCode)
	end,
})
```

## Notifications

```lua
Window:Notify({ Title = "Saved", Content = "Settings updated.", Type = "Success", Duration = 4 })
Window:Notify({ Title = "Heads up", Content = "Low health.", Type = "Warning" })
Window:Notify({ Title = "Failed", Content = "Could not connect.", Type = "Error" })
Window:Notify({ Title = "Tip", Content = "Press RightShift to hide.", Type = "Info" })
```

Click a notification to dismiss it. `Notify` returns `{ Close = function }`.

## Window and Dynamic Island

```lua
-- Dynamic Island icon: Lucide name, image, text or emoji
Window:SetOrbIcon("gamepad-2") -- Lucide icon name
Window:SetOrbIcon("rbxassetid://6031280882") -- image
Window:SetOrbIcon("🎮") -- emoji
Window:SetOrbIcon(nil) -- first letter of Title

-- window icon and title (top-right corner)
Window:SetIcon("rbxassetid://6031280882") -- window icon only, nil follows OrbIcon
Window:SetTitle("New title")
Window:SetSubtitle("Control panel") -- small description under the title

-- window control
Window:Hide()
Window:Show()
Window:Toggle()
Window:ToggleZoom()
Window:SetToggleKey(Enum.KeyCode.F4)
Window:Destroy()
```

## Sidebar and subtitles

The window has a toggle button at the top left of the content area. It collapses the sidebar down to a column of tab icons and expands it again. A tab without an icon shows its first letter, and hovering an icon shows the tab name.

```lua
local Window = AppMac:CreateWindow({
	Title = "My App",
	Subtitle = "Control panel", -- small description under the title
	Collapsed = false, -- start with the sidebar collapsed
	CollapseIcon = "rbxassetid://6031280882", -- optional, the default is a built-in panel glyph
})

Window:SetCollapsed(true)
Window:ToggleSidebar()
Window:SetSubtitle("New description")
Window:SetCollapseIcon("rbxassetid://6031280882") -- a Lucide name works too, nil restores the default

local Home = Window:CreateTab({ Name = "Home", Icon = "house", Subtitle = "Everything at a glance" })
Home:SetSubtitle("Changed later")
```

Set `Collapsible = false` to remove the toggle button.

## User chip

A chip at the bottom of the sidebar shows the avatar and nickname (display name) of the player running the script, with `@username` underneath. When the sidebar collapses it shrinks to just the avatar, and hovering it shows the name.

```lua
local Window = AppMac:CreateWindow({
	Title = "My App",
	User = true, -- the local player (this is the default)
})

-- custom text, still with the player's own avatar
Window:SetUser({ Name = "Nickname", Subtitle = "Premium" })

-- your own picture (an image id, or a Lucide name), or another player's avatar
Window:SetUser({ Name = "Guest", Image = "rbxassetid://6031280882" })
Window:SetUser({ UserId = 1 }) -- the name is looked up for you

Window:SetUser(false) -- hide the chip
```

| Field | Default | What it does |
| --- | --- | --- |
| `Name` | the player's display name | Main text |
| `Subtitle` | `"@username"` | Text under the name. An empty string hides it |
| `Image` | the player's headshot | Image id, `rbxthumb://` link or Lucide name for the avatar |
| `UserId` | the local player | Shows another player's avatar and name |

If the picture cannot be found, the first letter of the name is shown instead.

## Icons

Every icon option accepts the same formats:

| You pass | You get |
| --- | --- |
| `"settings"`, `"gamepad-2"`, `"lucide-home"` | a Lucide icon (names from [lucide.dev](https://lucide.dev); `"home"` also works) |
| `"rbxassetid://123"`, `123`, `"rbxthumb://..."` | an image |
| `"A"`, `"★"`, `"AB"` | text or emoji (island and window icon only) |

About 1,800 Lucide icons are bundled in two sprite sheets, so names work everywhere, including Roblox Studio, with no `HttpGet` needed. Browse the names at [lucide.dev](https://lucide.dev). A name that is not bundled falls back to a remote copy of the Lucide set, which needs an executor with `HttpGet` and `loadstring`.

If a name cannot be found, a tab icon is hidden, and the island and window icon show the first letter of the title.

The sprite sheets are Roblox images uploaded by the maintainers of lucide-roblox-direct, and the remote fallback loads code from that repository. To control either, fork it and point AppMac at your copy, or supply icons yourself:

```lua
AppMac.LucideSource = "https://raw.githubusercontent.com/you/your-fork/main/source.lua"

AppMac:SetIconProvider(function(name)
	if name == "settings" then
		return {
			Url = "rbxassetid://6031280882",
			ImageRectSize = Vector2.new(0, 0),   -- optional, for sprite sheets
			ImageRectOffset = Vector2.new(0, 0), -- optional, for sprite sheets
		}
	end
	return nil -- unknown name
end)
```

## Controls

- **RightShift** (or your `ToggleKey`) shows or hides the window, except while you are typing in a text box
- **Drag the top bar** to move the window. It always stays on screen. **Double-click** the bar to zoom
- **Red** closes the window, **yellow** minimizes it into the Dynamic Island, **green** zooms
- **Hover the island** to peek at the subtitle, **tap it** to bring the window back, **drag it** to move it
- **Toggle button** (top left of the content area) collapses the sidebar to tab icons. Hover an icon to see the tab name

## API reference

### AppMac:CreateWindow(options)

| Option | Type | Default | What it does |
| --- | --- | --- | --- |
| `Title` | string | `"AppMac"` | Title in the top-right corner |
| `Theme` | `"Dark"` or `"Light"` | `"Dark"` | Color theme |
| `Accent` | Color3 | Apple blue | Accent color |
| `ToggleKey` | Enum.KeyCode | `RightShift` | Shows or hides the window. Works even when the game uses the key (RightShift is Roblox Shift Lock), but not while typing in a text box |
| `Blur` | boolean | `true` | Blurs the scene behind the window |
| `Size` | `{w, h}`, Vector2 or UDim2 | `{560, 430}` | Window size, fitted to the screen |
| `OrbIcon` | string or number | first letter of Title | Dynamic Island icon, and the window icon unless `Icon` is set |
| `Icon` | string or number | `OrbIcon` | Window icon in the top-right corner |
| `Subtitle` | string | none | Small description under the title, also shown when the Dynamic Island opens |
| `User` | boolean or table | `true` | Avatar and nickname chip at the bottom of the sidebar |
| `Collapsible` | boolean | `true` | Shows the sidebar toggle button |
| `Collapsed` | boolean | `false` | Starts with the sidebar collapsed to icons |
| `CollapseIcon` | string or number | built-in glyph | Icon of the toggle button (Lucide name or image) |
| `CollapseIconSize` | number | `15` | Size of that icon in pixels |
| `Parent` | Instance | PlayerGui | Where the ScreenGui goes |

### Window

| Method | What it does |
| --- | --- |
| `Window:CreateTab(name)` | Adds a tab. Pass a string or `{ Name, Icon, Subtitle }` |
| `Window:SelectTab(tab)` | Switches to a tab |
| `Window:Notify({ Title, Content, Type, Duration })` | Shows a notification. `Type` is Info, Success, Warning or Error. `Duration` defaults to 4 |
| `Window:Show()` `Hide()` `Toggle()` | Shows, minimizes into the Dynamic Island, or switches |
| `Window:ToggleZoom()` | Expands or restores the window |
| `Window:SetToggleKey(keyCode)` | Changes the toggle key |
| `Window:SetOrbIcon(icon)` | Changes the Dynamic Island icon (and the window icon unless `SetIcon` was used) |
| `Window:SetIcon(icon)` | Changes the window icon only. `nil` follows the island icon |
| `Window:SetTitle(text)` | Changes the title |
| `Window:SetSubtitle(text)` | Changes the description under the title. An empty string hides it |
| `Window:SetCollapsed(state)` | Collapses the sidebar to icons (`true`) or expands it (`false`) |
| `Window:ToggleSidebar()` | Switches between collapsed and expanded |
| `Window:SetCollapseIcon(icon)` | Changes the toggle button icon. `nil` restores the built-in glyph |
| `Window:SetUser(option)` | Changes the user chip. `true` shows the local player, `false` hides it, or pass a table |
| `Window:Destroy()` | Removes the window |

### Module

| Member | What it does |
| --- | --- |
| `AppMac:Notify(config)` | Same as `Window:Notify`, without a window |
| `AppMac:SetIconProvider(fn)` | Supplies icons yourself. `fn(name)` returns `{ Url, ImageRectSize?, ImageRectOffset? }` or nil |
| `AppMac.LucideSource` | URL the Lucide icon set is loaded from |
| `AppMac.Version` | Library version |
| `AppMac.Palettes` | The Dark and Light palettes |

### Tab elements

| Element | Options | Methods |
| --- | --- | --- |
| `Tab:Section(name)` | | |
| `Tab:Label(text)` | | `:Set(text)` |
| `Tab:Paragraph(options)` | `Title`, `Content` | `:Set(title, content)` |
| `Tab:Button(options)` | `Name`, `Description`, `Callback()` | `:SetName(text)` |
| `Tab:Toggle(options)` | `Name`, `Default`, `Color`, `Callback(value)` | `:Set(value, silent)` |
| `Tab:Slider(options)` | `Name`, `Min`, `Max`, `Default`, `Increment`, `Suffix`, `Callback(value)` | `:Set(value, silent)` |
| `Tab:Dropdown(options)` | `Name`, `Options`, `Default`, `Placeholder`, `Callback(option)` | `:Set(option, silent)`, `:Refresh(options, keepValue)` |
| `Tab:Input(options)` | `Name`, `Placeholder`, `Default`, `ClearOnFocus`, `Callback(text, enterPressed)` | `:Set(text)`, `:Get()` |
| `Tab:Keybind(options)` | `Name`, `Default`, `Callback()`, `Changed(keyCode)` | `:Set(keyCode, silent)` |

Pass `silent = true` to a `Set` method to change the value without firing the callback.

A tab object also has `Tab:SetSubtitle(text)`, which changes the description under its page title.

## Project layout

```
src/AppMac.lua                  the library
examples/Example.client.lua     example LocalScript
default.project.json            Rojo project
```

## License

MIT
