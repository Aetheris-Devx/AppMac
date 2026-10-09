# AppMac

Minimal Apple / macOS **Liquid Glass** UI library for Roblox (Luau).

- Frosted glass window: translucent surface, diagonal sheen, gradient rim light, soft shadow
- macOS traffic lights (close / minimize / zoom), draggable, minimizes to a small orb
- Minimal sidebar tabs with a sliding selection pill and animated page transitions
- Elements: Section, Label, Paragraph, Button, Toggle, Slider, Dropdown, Input, Keybind
- Notifications that slide in with a progress line
- Dark and Light themes, custom accent color, optional screen blur, mobile friendly

> Roblox cannot blur only the area behind a UI frame, so the "glass" is built from transparency,
> gradients and strokes. `Blur = true` adds a full-screen `BlurEffect` while the window is open.

## Install

**Rojo**

```bash
rojo serve   # uses default.project.json
```

**Manual (Studio)**

1. Create a `ModuleScript` in `ReplicatedStorage` named `AppMac` and paste `src/AppMac.lua`.
2. Create a `LocalScript` in `StarterPlayer > StarterPlayerScripts` and paste `examples/Example.client.lua`.
3. Press Play.

## Quick start

```lua
local AppMac = require(game:GetService("ReplicatedStorage"):WaitForChild("AppMac"))

local Window = AppMac:CreateWindow({
	Title = "AppMac",
	Theme = "Dark",
	Accent = Color3.fromRGB(10, 132, 255),
})

local Tab = Window:CreateTab("Home")
Tab:Section("Hello")
Tab:Toggle({ Name = "Enable", Default = true, Callback = function(v) print(v) end })
```

## API

### `AppMac:CreateWindow(config)`

| Option      | Type             | Default                | Notes                              |
| ----------- | ---------------- | ---------------------- | ---------------------------------- |
| `Title`     | string           | `"AppMac"`              | Shown in the sidebar               |
| `Size`      | UDim2 (offset)   | `640 x 420`            | Clamped to the viewport            |
| `Theme`     | `"Dark"`/`"Light"` | `"Dark"`             |                                    |
| `Accent`    | Color3           | Apple blue             |                                    |
| `ToggleKey` | Enum.KeyCode     | `RightShift`           | Show / hide                        |
| `Blur`      | boolean          | `true`                 | Screen blur while open             |
| `Parent`    | Instance         | `PlayerGui`            |                                    |

Window methods: `:CreateTab(nameOrConfig)`, `:SelectTab(tab)`, `:Show()`, `:Hide()`, `:Toggle()`,
`:ToggleZoom()`, `:SetToggleKey(keyCode)`, `:Notify(config)`, `:Destroy()`.

`CreateTab` accepts a string or `{ Name = "Tab", Icon = "rbxassetid://..." }` (icon optional).

### Elements

| Call | Config | Returns |
| ---- | ------ | ------- |
| `Tab:Section(name)` | | |
| `Tab:Label(text)` | | `:Set(text)` |
| `Tab:Paragraph(cfg)` | `Title`, `Content` | `:Set(title, content)` |
| `Tab:Button(cfg)` | `Name`, `Description?`, `Callback()` | `:SetName(text)` |
| `Tab:Toggle(cfg)` | `Name`, `Default`, `Color?`, `Callback(value)` | `.Value`, `:Set(value, silent?)` |
| `Tab:Slider(cfg)` | `Name`, `Min`, `Max`, `Default`, `Increment`, `Suffix`, `Callback(value)` | `.Value`, `:Set(value, silent?)` |
| `Tab:Dropdown(cfg)` | `Name`, `Options`, `Default`, `Placeholder`, `Callback(option)` | `.Value`, `:Set(option, silent?)`, `:Refresh(options, keepValue?)` |
| `Tab:Input(cfg)` | `Name`, `Placeholder`, `Default`, `ClearOnFocus`, `Callback(text, enter)` | `:Set(text)`, `:Get()` |
| `Tab:Keybind(cfg)` | `Name`, `Default`, `Callback()`, `Changed(keyCode)` | `.Value`, `:Set(keyCode, silent?)` |

Callbacks only fire on changes made by the user (or `:Set` without `silent = true`).

### Notifications

```lua
Window:Notify({ Title = "Saved", Content = "Settings applied.", Type = "Success", Duration = 4 })
-- Type: "Info" | "Success" | "Warning" | "Error"   (click a notification to dismiss it)
```

### Tweaking the look

Colors live in `AppMac.Palettes` (`Dark` / `Light`) at the top of `src/AppMac.lua`.
Animation presets are in the `T` table (`Fast`, `Smooth`, `Spring`, `In`, `Drag`).

## Publish to GitHub

```bash
cd AppMac
git init
git add .
git commit -m "Initial commit: AppMac"
git branch -M main
git remote add origin https://github.com/<your-username>/AppMac.git
git push -u origin main
```

## License

MIT
