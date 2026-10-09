--[[
	AppMac  -  v1.0.0
	Minimal Apple / macOS "Liquid Glass" UI library for Roblox.

	Place this file as a ModuleScript (e.g. ReplicatedStorage.AppMac) and
	require it from a LocalScript. See README.md and examples/Example.client.lua.

	Elements:  Section, Label, Paragraph, Button, Toggle, Slider,
	           Dropdown, Input, Keybind, Notify
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")

local LocalPlayer = Players.LocalPlayer

local AppMac = {}
AppMac.Version = "1.0.0"

local Window = {}
Window.__index = Window

local Tab = {}
Tab.__index = Tab

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local WINDOW_RADIUS = 18
local SIDEBAR_WIDTH = 170
local TOPBAR_HEIGHT = 52
local TAB_HEIGHT = 34
local TAB_GAP = 4
local TAB_STRIDE = TAB_HEIGHT + TAB_GAP

--------------------------------------------------------------------------------
-- Animation presets
--------------------------------------------------------------------------------

local T = {
	Fast = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	Smooth = TweenInfo.new(0.38, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
	Spring = TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	In = TweenInfo.new(0.24, Enum.EasingStyle.Quint, Enum.EasingDirection.In),
	Drag = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
}

--------------------------------------------------------------------------------
-- Themes
--------------------------------------------------------------------------------

local Palettes = {
	Dark = {
		Base = Color3.fromRGB(28, 28, 32),
		BaseTransparency = 0.14,
		Sidebar = Color3.fromRGB(0, 0, 0),
		SidebarTransparency = 0.8,
		Element = Color3.fromRGB(255, 255, 255),
		ElementTransparency = 0.94,
		ElementHover = 0.89,
		Text = Color3.fromRGB(245, 245, 247),
		SubText = Color3.fromRGB(150, 150, 160),
		Off = Color3.fromRGB(120, 120, 128),
		OffTransparency = 0.6,
		Sheen = { 0.9, 0.97, 0.985 },
		ShadowTransparency = 0.955,
	},
	Light = {
		Base = Color3.fromRGB(242, 242, 247),
		BaseTransparency = 0.1,
		Sidebar = Color3.fromRGB(200, 200, 210),
		SidebarTransparency = 0.72,
		Element = Color3.fromRGB(0, 0, 0),
		ElementTransparency = 0.95,
		ElementHover = 0.9,
		Text = Color3.fromRGB(28, 28, 30),
		SubText = Color3.fromRGB(110, 110, 118),
		Off = Color3.fromRGB(120, 120, 128),
		OffTransparency = 0.6,
		Sheen = { 0.7, 0.9, 0.95 },
		ShadowTransparency = 0.975,
	},
}

AppMac.Palettes = Palettes

local function makePalette(theme, accent)
	local source = Palettes[theme] or Palettes.Dark
	local pal = {}
	for key, value in pairs(source) do
		pal[key] = value
	end
	pal.Accent = accent or Color3.fromRGB(10, 132, 255)
	pal.Green = Color3.fromRGB(48, 209, 88)
	pal.Red = Color3.fromRGB(255, 69, 58)
	pal.Yellow = Color3.fromRGB(255, 214, 10)
	return pal
end

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function create(class, props, children)
	local inst = Instance.new(class)
	local parent
	if props then
		for key, value in pairs(props) do
			if key == "Parent" then
				parent = value
			else
				inst[key] = value
			end
		end
	end
	if children then
		for _, child in ipairs(children) do
			child.Parent = inst
		end
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

local function apply(obj, props)
	for key, value in pairs(props) do
		obj[key] = value
	end
end

-- play(obj, nil, props) applies instantly, otherwise tweens.
local function play(obj, info, props)
	if not info then
		apply(obj, props)
		return nil
	end
	local tween = TweenService:Create(obj, info, props)
	tween:Play()
	return tween
end

local function safe(fn, ...)
	if type(fn) ~= "function" then
		return
	end
	local ok, err = pcall(fn, ...)
	if not ok then
		warn("[AppMac] callback error: " .. tostring(err))
	end
end

local function font(weight)
	return Font.new("rbxasset://fonts/families/GothamSSm.json", weight or Enum.FontWeight.Medium, Enum.FontStyle.Normal)
end

local function decimals(n)
	local s = tostring(n)
	local dot = string.find(s, "%.")
	if dot then
		return #s - dot
	end
	return 0
end

local function bind(window, signal, fn)
	local connection = signal:Connect(fn)
	table.insert(window.Connections, connection)
	return connection
end

local function isPointer(input)
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end

local function isMove(input)
	return input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch
end

-- Glass surface: soft diagonal sheen + a thin gradient rim light.
-- Must be used on a CanvasGroup (the rim is inset by 1px so it is never clipped).
local function addGlass(frame, pal, radius)
	create("Frame", {
		Name = "Sheen",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ZIndex = 0,
		Parent = frame,
	}, {
		create("UIGradient", {
			Rotation = 62,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, pal.Sheen[1]),
				NumberSequenceKeypoint.new(0.45, pal.Sheen[2]),
				NumberSequenceKeypoint.new(1, pal.Sheen[3]),
			}),
		}),
	})

	create("Frame", {
		Name = "Rim",
		Position = UDim2.fromOffset(1, 1),
		Size = UDim2.new(1, -2, 1, -2),
		BackgroundTransparency = 1,
		ZIndex = 50,
		Parent = frame,
	}, {
		create("UICorner", { CornerRadius = UDim.new(0, radius - 1) }),
		create("UIStroke", {
			Color = Color3.new(1, 1, 1),
			Thickness = 1,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}, {
			create("UIGradient", {
				Rotation = 45,
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0.3),
					NumberSequenceKeypoint.new(0.3, 0.84),
					NumberSequenceKeypoint.new(0.7, 0.86),
					NumberSequenceKeypoint.new(1, 0.45),
				}),
			}),
		}),
	})
end

-- Soft shadow built from a few stacked translucent rounded frames.
local function addShadow(holder, radius)
	local layers = {}
	for i, grow in ipairs({ 6, 14, 24, 36, 50 }) do
		local layer = create("Frame", {
			Name = "Shadow" .. i,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, 10),
			Size = UDim2.new(1, grow, 1, grow),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = 0,
			Parent = holder,
		}, {
			create("UICorner", { CornerRadius = UDim.new(0, radius + grow / 2) }),
		})
		table.insert(layers, layer)
	end
	return layers
end

local function setShadow(layers, pal, visible, info)
	for _, layer in ipairs(layers) do
		play(layer, info, { BackgroundTransparency = visible and pal.ShadowTransparency or 1 })
	end
end

-- Optional full-screen blur behind open windows (shared between windows).
local blurUsers = {}

local function refreshBlur()
	local blur = Lighting:FindFirstChild("AppMac_Blur")
	if next(blurUsers) ~= nil then
		if not blur then
			blur = create("BlurEffect", { Name = "AppMac_Blur", Size = 0, Parent = Lighting })
		end
		play(blur, T.Smooth, { Size = 14 })
	elseif blur then
		play(blur, T.Smooth, { Size = 0 })
		task.delay(0.5, function()
			if next(blurUsers) == nil and blur.Parent then
				blur:Destroy()
			end
		end)
	end
end

--------------------------------------------------------------------------------
-- Notifications
--------------------------------------------------------------------------------

local notifyGui, notifyHolder
local notifyCount = 0

local function ensureNotifyHolder()
	if notifyGui and notifyGui.Parent then
		return notifyHolder
	end
	notifyGui = create("ScreenGui", {
		Name = "AppMac_Notifications",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		IgnoreGuiInset = true,
		DisplayOrder = 1001,
		Parent = LocalPlayer:WaitForChild("PlayerGui"),
	})
	notifyHolder = create("Frame", {
		Name = "Holder",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 16),
		Size = UDim2.fromOffset(300, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = notifyGui,
	}, {
		create("UIListLayout", {
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
		}),
	})
	return notifyHolder
end

-- config: { Title, Content, Duration = 4, Type = "Info" | "Success" | "Warning" | "Error" }
function AppMac:Notify(config, palette)
	assert(LocalPlayer, "[AppMac] Notify must run on the client.")
	if type(config) == "string" then
		config = { Title = config }
	end
	config = config or {}

	local pal = palette or AppMac._palette or makePalette("Dark")
	local holder = ensureNotifyHolder()
	local duration = config.Duration or 4
	local colors = { Info = pal.Accent, Success = pal.Green, Warning = pal.Yellow, Error = pal.Red }
	local color = colors[config.Type or "Info"] or pal.Accent

	notifyCount = notifyCount + 1

	local wrapper = create("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = -notifyCount, -- newest on top
		Parent = holder,
	})

	local card = create("CanvasGroup", {
		Position = UDim2.new(0, 340, 0, 0),
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = pal.Base,
		BackgroundTransparency = pal.BaseTransparency,
		GroupTransparency = 1,
		BorderSizePixel = 0,
		Parent = wrapper,
	}, {
		create("UICorner", { CornerRadius = UDim.new(0, 14) }),
	})
	addGlass(card, pal, 14)

	local body = create("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = card,
	}, {
		create("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }),
		create("UIPadding", {
			PaddingTop = UDim.new(0, 12),
			PaddingBottom = UDim.new(0, 14),
			PaddingLeft = UDim.new(0, 32),
			PaddingRight = UDim.new(0, 14),
		}),
	})

	create("TextLabel", {
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Text = config.Title or "Notification",
		FontFace = font(Enum.FontWeight.SemiBold),
		TextSize = 14,
		TextColor3 = pal.Text,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = body,
	})

	if config.Content and config.Content ~= "" then
		create("TextLabel", {
			LayoutOrder = 2,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			Text = config.Content,
			FontFace = font(Enum.FontWeight.Regular),
			TextSize = 13,
			TextColor3 = pal.SubText,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			Parent = body,
		})
	end

	create("Frame", {
		Name = "Dot",
		Position = UDim2.fromOffset(14, 17),
		Size = UDim2.fromOffset(8, 8),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		ZIndex = 3,
		Parent = card,
	}, {
		create("UICorner", { CornerRadius = UDim.new(1, 0) }),
	})

	local bar = create("Frame", {
		Name = "Progress",
		Position = UDim2.new(0, 0, 1, -2),
		Size = UDim2.new(1, 0, 0, 2),
		BackgroundColor3 = color,
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		ZIndex = 40,
		Parent = card,
	})

	local closed = false
	local function close()
		if closed then
			return
		end
		closed = true
		play(card, T.In, { Position = UDim2.new(0, 340, 0, 0), GroupTransparency = 1 })
		task.delay(0.26, function()
			if not wrapper.Parent then
				return
			end
			local height = wrapper.AbsoluteSize.Y
			wrapper.AutomaticSize = Enum.AutomaticSize.None
			wrapper.Size = UDim2.new(1, 0, 0, height)
			play(wrapper, T.Smooth, { Size = UDim2.new(1, 0, 0, 0) })
			task.delay(0.4, function()
				if wrapper.Parent then
					wrapper:Destroy()
				end
			end)
		end)
	end

	-- click to dismiss
	local dismiss = create("TextButton", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
		ZIndex = 60,
		Parent = card,
	})
	dismiss.MouseButton1Click:Connect(close)

	play(card, T.Smooth, { Position = UDim2.new(0, 0, 0, 0), GroupTransparency = 0 })
	play(bar, TweenInfo.new(duration, Enum.EasingStyle.Linear), { Size = UDim2.new(0, 0, 0, 2) })
	task.delay(duration, close)

	return { Close = close }
end

--------------------------------------------------------------------------------
-- Window
--------------------------------------------------------------------------------

-- config:
--   Title     string
--   Size      UDim2 (offset)           default 640 x 420
--   Theme     "Dark" | "Light"          default "Dark"
--   Accent    Color3                    default Apple blue
--   ToggleKey Enum.KeyCode              default RightShift
--   Blur      boolean                   default true
--   Parent    Instance                  default PlayerGui
function AppMac:CreateWindow(config)
	config = config or {}
	assert(LocalPlayer, "[AppMac] CreateWindow must run on the client (LocalScript).")

	local self = setmetatable({}, Window)
	self.Title = config.Title or "AppMac"
	self.Palette = makePalette(config.Theme, config.Accent)
	self.Tabs = {}
	self.Connections = {}
	self.Visible = true
	self.Zoomed = false
	self.ToggleKey = config.ToggleKey or Enum.KeyCode.RightShift
	self.UseBlur = config.Blur ~= false
	AppMac._palette = self.Palette

	local pal = self.Palette

	-- sizing: the viewport can report 1x1 right when the script starts, so fall back to a sane size
	local requested = config.Size or UDim2.fromOffset(640, 420)
	local function computeSizes()
		local camera = workspace.CurrentCamera
		local vp = camera and camera.ViewportSize or Vector2.new(0, 0)
		if vp.X < 200 or vp.Y < 200 then
			vp = Vector2.new(1280, 720)
		end
		local w = math.max(280, math.min(requested.X.Offset, vp.X - 24))
		local h = math.max(240, math.min(requested.Y.Offset, vp.Y - 24))
		local zoom = UDim2.fromOffset(
			math.max(w, math.min(vp.X * 0.88, 1000)),
			math.max(h, math.min(vp.Y * 0.88, 700))
		)
		return UDim2.fromOffset(w, h), zoom
	end
	self.BaseSize, self.ZoomSize = computeSizes()

	local gui = create("ScreenGui", {
		Name = "AppMac",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		IgnoreGuiInset = true,
		DisplayOrder = 1000,
	})
	self.Gui = gui

	local holder = create("Frame", {
		Name = "Window",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = self.BaseSize,
		BackgroundTransparency = 1,
		Parent = gui,
	})
	self.Holder = holder
	self.Scale = create("UIScale", { Scale = 0.92, Parent = holder })
	self.Shadow = addShadow(holder, WINDOW_RADIUS)

	local canvas = create("CanvasGroup", {
		Name = "Glass",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = pal.Base,
		BackgroundTransparency = pal.BaseTransparency,
		BorderSizePixel = 0,
		GroupTransparency = 0,
		ZIndex = 1,
		Parent = holder,
	}, {
		create("UICorner", { CornerRadius = UDim.new(0, WINDOW_RADIUS) }),
	})
	self.Canvas = canvas
	addGlass(canvas, pal, WINDOW_RADIUS)

	-- drag area (sits below everything so buttons keep their input)
	local dragBar = create("Frame", {
		Name = "DragBar",
		Size = UDim2.new(1, 0, 0, TOPBAR_HEIGHT),
		BackgroundTransparency = 1,
		ZIndex = 1,
		Parent = canvas,
	})

	-- sidebar
	local sidebar = create("Frame", {
		Name = "Sidebar",
		Size = UDim2.new(0, SIDEBAR_WIDTH, 1, 0),
		BackgroundColor3 = pal.Sidebar,
		BackgroundTransparency = pal.SidebarTransparency,
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = canvas,
	}, {
		create("Frame", {
			Name = "Divider",
			Position = UDim2.new(1, -1, 0, 0),
			Size = UDim2.new(0, 1, 1, 0),
			BackgroundColor3 = pal.Element,
			BackgroundTransparency = 0.92,
			BorderSizePixel = 0,
		}),
	})

	-- traffic lights
	local lights = create("Frame", {
		Name = "Controls",
		Position = UDim2.fromOffset(16, 16),
		Size = UDim2.fromOffset(56, 12),
		BackgroundTransparency = 1,
		Parent = sidebar,
	})
	local glyphs = {}
	local function light(x, color, glyph, onClick)
		local button = create("TextButton", {
			Position = UDim2.fromOffset(x, 0),
			Size = UDim2.fromOffset(12, 12),
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Text = "",
			Parent = lights,
		}, {
			create("UICorner", { CornerRadius = UDim.new(1, 0) }),
		})
		local label = create("TextLabel", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Text = glyph,
			FontFace = font(Enum.FontWeight.Bold),
			TextSize = 11,
			TextColor3 = Color3.fromRGB(0, 0, 0),
			TextTransparency = 1,
			Parent = button,
		})
		table.insert(glyphs, label)
		button.MouseButton1Click:Connect(onClick)
	end
	light(0, Color3.fromRGB(255, 95, 87), "\u{00D7}", function()
		self:Destroy()
	end)
	light(22, Color3.fromRGB(254, 188, 46), "\u{2013}", function()
		self:Hide()
	end)
	light(44, Color3.fromRGB(40, 200, 64), "+", function()
		self:ToggleZoom()
	end)
	lights.MouseEnter:Connect(function()
		for _, glyph in ipairs(glyphs) do
			play(glyph, T.Fast, { TextTransparency = 0.45 })
		end
	end)
	lights.MouseLeave:Connect(function()
		for _, glyph in ipairs(glyphs) do
			play(glyph, T.Fast, { TextTransparency = 1 })
		end
	end)

	-- title
	create("TextLabel", {
		Position = UDim2.fromOffset(18, 44),
		Size = UDim2.new(1, -36, 0, 16),
		BackgroundTransparency = 1,
		Text = string.upper(self.Title),
		FontFace = font(Enum.FontWeight.SemiBold),
		TextSize = 11,
		TextColor3 = pal.SubText,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = sidebar,
	})

	-- tab list + sliding selection pill
	local tabScroll = create("ScrollingFrame", {
		Name = "Tabs",
		Position = UDim2.new(0, 10, 0, 68),
		Size = UDim2.new(1, -20, 1, -80),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 0,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = sidebar,
	})
	self.Pill = create("Frame", {
		Name = "Pill",
		Size = UDim2.new(1, 0, 0, TAB_HEIGHT),
		BackgroundColor3 = pal.Element,
		BackgroundTransparency = 0.88,
		BorderSizePixel = 0,
		ZIndex = 1,
		Parent = tabScroll,
	}, {
		create("UICorner", { CornerRadius = UDim.new(0, 9) }),
	})
	self.TabList = create("Frame", {
		Name = "List",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = tabScroll,
	}, {
		create("UIListLayout", { Padding = UDim.new(0, TAB_GAP), SortOrder = Enum.SortOrder.LayoutOrder }),
	})

	-- content area
	local content = create("Frame", {
		Name = "Content",
		Position = UDim2.fromOffset(SIDEBAR_WIDTH, 0),
		Size = UDim2.new(1, -SIDEBAR_WIDTH, 1, 0),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = canvas,
	})
	self.Header = create("TextLabel", {
		Name = "Header",
		Position = UDim2.fromOffset(24, 14),
		Size = UDim2.new(1, -48, 0, 28),
		BackgroundTransparency = 1,
		Text = "",
		FontFace = font(Enum.FontWeight.Bold),
		TextSize = 20,
		TextColor3 = pal.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = content,
	})
	self.Pages = create("Frame", {
		Name = "Pages",
		Position = UDim2.fromOffset(0, TOPBAR_HEIGHT),
		Size = UDim2.new(1, 0, 1, -TOPBAR_HEIGHT),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Parent = content,
	})

	-- minimized "orb" (click to restore)
	local orb = create("TextButton", {
		Name = "Orb",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 1, -44),
		Size = UDim2.fromOffset(44, 44),
		BackgroundColor3 = pal.Base,
		BackgroundTransparency = pal.BaseTransparency,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = string.upper(string.sub(self.Title, 1, 1)),
		FontFace = font(Enum.FontWeight.Bold),
		TextSize = 18,
		TextColor3 = pal.Text,
		Visible = false,
		Parent = gui,
	}, {
		create("UICorner", { CornerRadius = UDim.new(1, 0) }),
		create("UIStroke", {
			Color = Color3.new(1, 1, 1),
			Transparency = 0.8,
			Thickness = 1,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
	})
	self.Orb = orb
	self.OrbScale = create("UIScale", { Scale = 0, Parent = orb })
	orb.MouseButton1Click:Connect(function()
		self:Show()
	end)

	-- dragging
	local dragging = false
	local dragStart, startPosition
	dragBar.InputBegan:Connect(function(input)
		if isPointer(input) then
			dragging = true
			dragStart = input.Position
			startPosition = holder.Position
			play(self.Scale, T.Fast, { Scale = 0.992 })
		end
	end)
	bind(self, UserInputService.InputChanged, function(input)
		if dragging and isMove(input) then
			local delta = input.Position - dragStart
			play(holder, T.Drag, {
				Position = UDim2.new(
					startPosition.X.Scale,
					startPosition.X.Offset + delta.X,
					startPosition.Y.Scale,
					startPosition.Y.Offset + delta.Y
				),
			})
		end
	end)
	bind(self, UserInputService.InputEnded, function(input)
		if dragging and isPointer(input) then
			dragging = false
			play(self.Scale, T.Spring, { Scale = 1 })
		end
	end)

	-- toggle key
	bind(self, UserInputService.InputBegan, function(input, processed)
		if not processed and input.KeyCode == self.ToggleKey then
			self:Toggle()
		end
	end)

	local function refit()
		if self.Destroyed or self.Zoomed then
			return
		end
		self.BaseSize, self.ZoomSize = computeSizes()
		play(holder, T.Smooth, { Size = self.BaseSize })
	end
	local cam = workspace.CurrentCamera
	if cam then
		bind(self, cam:GetPropertyChangedSignal("ViewportSize"), refit)
	end

	-- mount + open animation
	gui.Parent = config.Parent or LocalPlayer:WaitForChild("PlayerGui")
	play(self.Scale, T.Smooth, { Scale = 1 })
	play(canvas, T.Smooth, { GroupTransparency = 0 })
	setShadow(self.Shadow, pal, true, T.Smooth)
	if self.UseBlur then
		blurUsers[self] = true
		refreshBlur()
	end

	return self
end

function Window:Show()
	if self.Visible or self.Destroyed then
		return
	end
	self.Visible = true
	self.Holder.Visible = true
	play(self.Scale, T.Smooth, { Scale = 1 })
	play(self.Canvas, T.Smooth, { GroupTransparency = 0 })
	setShadow(self.Shadow, self.Palette, true, T.Smooth)
	play(self.OrbScale, T.In, { Scale = 0 })
	task.delay(0.26, function()
		if self.Visible and self.Orb.Parent then
			self.Orb.Visible = false
		end
	end)
	if self.UseBlur then
		blurUsers[self] = true
		refreshBlur()
	end
end

function Window:Hide()
	if not self.Visible or self.Destroyed then
		return
	end
	self.Visible = false
	play(self.Scale, T.In, { Scale = 0.94 })
	play(self.Canvas, T.In, { GroupTransparency = 1 })
	setShadow(self.Shadow, self.Palette, false, T.In)
	self.Orb.Visible = true
	play(self.OrbScale, T.Spring, { Scale = 1 })
	task.delay(0.26, function()
		if not self.Visible and not self.Destroyed then
			self.Holder.Visible = false
		end
	end)
	blurUsers[self] = nil
	refreshBlur()
end

function Window:Toggle()
	if self.Visible then
		self:Hide()
	else
		self:Show()
	end
end

function Window:ToggleZoom()
	if self.Destroyed then
		return
	end
	self.Zoomed = not self.Zoomed
	if self.Zoomed then
		self.PreviousPosition = self.Holder.Position
		play(self.Holder, T.Smooth, { Size = self.ZoomSize, Position = UDim2.fromScale(0.5, 0.5) })
	else
		play(self.Holder, T.Smooth, {
			Size = self.BaseSize,
			Position = self.PreviousPosition or UDim2.fromScale(0.5, 0.5),
		})
	end
end

function Window:SetToggleKey(keyCode)
	self.ToggleKey = keyCode
end

function Window:Notify(config)
	return AppMac:Notify(config, self.Palette)
end

function Window:Destroy()
	if self.Destroyed then
		return
	end
	self.Destroyed = true
	self.Visible = false
	blurUsers[self] = nil
	refreshBlur()
	for _, connection in ipairs(self.Connections) do
		connection:Disconnect()
	end
	self.Connections = {}
	play(self.Scale, T.In, { Scale = 0.9 })
	play(self.Canvas, T.In, { GroupTransparency = 1 })
	setShadow(self.Shadow, self.Palette, false, T.In)
	task.delay(0.3, function()
		self.Gui:Destroy()
	end)
end

--------------------------------------------------------------------------------
-- Tabs
--------------------------------------------------------------------------------

-- config: "Name"  or  { Name = "Name", Icon = "rbxassetid://..." (optional) }
function Window:CreateTab(config)
	if type(config) == "string" then
		config = { Name = config }
	end
	config = config or {}

	local pal = self.Palette
	local tab = setmetatable({}, Tab)
	tab.Window = self
	tab.Name = config.Name or ("Tab " .. (#self.Tabs + 1))
	tab.Index = #self.Tabs + 1
	tab._order = 0

	local textOffset = config.Icon and 36 or 12

	tab._button = create("TextButton", {
		Name = tab.Name,
		Size = UDim2.new(1, 0, 0, TAB_HEIGHT),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = tab.Index,
		Parent = self.TabList,
	})
	tab._label = create("TextLabel", {
		Position = UDim2.fromOffset(textOffset, 0),
		Size = UDim2.new(1, -(textOffset + 8), 1, 0),
		BackgroundTransparency = 1,
		Text = tab.Name,
		FontFace = font(Enum.FontWeight.Medium),
		TextSize = 14,
		TextColor3 = pal.Text,
		TextTransparency = 0.4,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = tab._button,
	})
	if config.Icon then
		tab._icon = create("ImageLabel", {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 11, 0.5, 0),
			Size = UDim2.fromOffset(16, 16),
			BackgroundTransparency = 1,
			Image = config.Icon,
			ImageColor3 = pal.Text,
			ImageTransparency = 0.4,
			Parent = tab._button,
		})
	end

	tab._button.MouseEnter:Connect(function()
		if self.ActiveTab ~= tab then
			play(tab._label, T.Fast, { TextTransparency = 0.15 })
			if tab._icon then
				play(tab._icon, T.Fast, { ImageTransparency = 0.15 })
			end
		end
	end)
	tab._button.MouseLeave:Connect(function()
		if self.ActiveTab ~= tab then
			play(tab._label, T.Fast, { TextTransparency = 0.4 })
			if tab._icon then
				play(tab._icon, T.Fast, { ImageTransparency = 0.4 })
			end
		end
	end)
	tab._button.MouseButton1Click:Connect(function()
		self:SelectTab(tab)
	end)

	tab._page = create("CanvasGroup", {
		Name = tab.Name,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		GroupTransparency = 1,
		Visible = false,
		Parent = self.Pages,
	})
	tab._scroll = create("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = pal.Element,
		ScrollBarImageTransparency = 0.6,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = tab._page,
	}, {
		create("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
		create("UIPadding", {
			PaddingLeft = UDim.new(0, 20),
			PaddingRight = UDim.new(0, 20),
			PaddingTop = UDim.new(0, 4),
			PaddingBottom = UDim.new(0, 20),
		}),
	})

	table.insert(self.Tabs, tab)

	if #self.Tabs == 1 then
		self:SelectTab(tab, true)
	end

	return tab
end

function Window:SelectTab(tab, instant)
	if self.Destroyed or tab == self.ActiveTab then
		return
	end

	local previous = self.ActiveTab
	self.ActiveTab = tab

	for _, other in ipairs(self.Tabs) do
		local active = other == tab
		local transparency = active and 0 or 0.4
		play(other._label, T.Fast, { TextTransparency = transparency })
		if other._icon then
			play(other._icon, T.Fast, { ImageTransparency = transparency })
		end
	end

	-- sliding pill
	local y = (tab.Index - 1) * TAB_STRIDE
	play(self.Pill, (not instant) and T.Smooth or nil, { Position = UDim2.fromOffset(0, y) })

	-- header
	self.Header.Text = tab.Name
	if not instant then
		self.Header.TextTransparency = 1
		play(self.Header, T.Smooth, { TextTransparency = 0 })
	end

	-- pages
	if previous then
		local old = previous._page
		play(old, T.Fast, { GroupTransparency = 1, Position = UDim2.fromOffset(0, -8) })
		task.delay(0.18, function()
			if self.ActiveTab ~= previous then
				old.Visible = false
			end
		end)
	end

	local page = tab._page
	page.Visible = true
	if instant then
		apply(page, { GroupTransparency = 0, Position = UDim2.fromOffset(0, 0) })
	else
		apply(page, { GroupTransparency = 1, Position = UDim2.fromOffset(0, 14) })
		play(page, T.Smooth, { GroupTransparency = 0, Position = UDim2.fromOffset(0, 0) })
	end
end

--------------------------------------------------------------------------------
-- Element building blocks
--------------------------------------------------------------------------------

local function nextOrder(tab)
	tab._order = tab._order + 1
	return tab._order
end

local function newCard(tab, height, class)
	local pal = tab.Window.Palette
	local card = create(class or "Frame", {
		Size = UDim2.new(1, 0, 0, height),
		BackgroundColor3 = pal.Element,
		BackgroundTransparency = pal.ElementTransparency,
		BorderSizePixel = 0,
		LayoutOrder = nextOrder(tab),
		Parent = tab._scroll,
	}, {
		create("UICorner", { CornerRadius = UDim.new(0, 10) }),
		create("UIStroke", {
			Color = pal.Element,
			Transparency = 0.94,
			Thickness = 1,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
	})
	if class == "TextButton" then
		card.Text = ""
		card.AutoButtonColor = false
	end
	return card
end

local function hoverable(card, pal, pressable)
	card.MouseEnter:Connect(function()
		play(card, T.Fast, { BackgroundTransparency = pal.ElementHover })
	end)
	card.MouseLeave:Connect(function()
		play(card, T.Fast, { BackgroundTransparency = pal.ElementTransparency })
	end)
	if pressable then
		local scale = create("UIScale", { Parent = card })
		card.MouseButton1Down:Connect(function()
			play(scale, T.Fast, { Scale = 0.985 })
		end)
		card.MouseButton1Up:Connect(function()
			play(scale, T.Spring, { Scale = 1 })
		end)
		card.MouseLeave:Connect(function()
			play(scale, T.Fast, { Scale = 1 })
		end)
	end
end

local function textLabel(parent, props)
	local pal = props.Palette
	return create("TextLabel", {
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		Size = props.Size,
		BackgroundTransparency = 1,
		Text = props.Text or "",
		FontFace = font(props.Weight or Enum.FontWeight.Medium),
		TextSize = props.TextSize or 14,
		TextColor3 = props.Color or pal.Text,
		TextXAlignment = props.AlignX or Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = parent,
	})
end

local function chevron(parent, pal)
	return create("TextLabel", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -14, 0.5, 0),
		Size = UDim2.fromOffset(14, 14),
		BackgroundTransparency = 1,
		Text = "\u{203A}",
		FontFace = font(Enum.FontWeight.Bold),
		TextSize = 20,
		TextColor3 = pal.SubText,
		Parent = parent,
	})
end

--------------------------------------------------------------------------------
-- Elements: text
--------------------------------------------------------------------------------

function Tab:Section(name)
	local pal = self.Window.Palette
	create("TextLabel", {
		Size = UDim2.new(1, 0, 0, 28),
		BackgroundTransparency = 1,
		Text = string.upper(name or "Section"),
		FontFace = font(Enum.FontWeight.SemiBold),
		TextSize = 12,
		TextColor3 = pal.SubText,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Bottom,
		LayoutOrder = nextOrder(self),
		Parent = self._scroll,
	}, {
		create("UIPadding", { PaddingLeft = UDim.new(0, 4), PaddingBottom = UDim.new(0, 2) }),
	})
end

function Tab:Label(text)
	local pal = self.Window.Palette
	local label = create("TextLabel", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Text = text or "",
		FontFace = font(Enum.FontWeight.Regular),
		TextSize = 13,
		TextColor3 = pal.SubText,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		LayoutOrder = nextOrder(self),
		Parent = self._scroll,
	}, {
		create("UIPadding", { PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4) }),
	})
	local object = { Instance = label }
	function object:Set(newText)
		label.Text = newText
	end
	return object
end

-- config: { Title, Content }
function Tab:Paragraph(config)
	config = config or {}
	local pal = self.Window.Palette
	local card = newCard(self, 0)
	card.AutomaticSize = Enum.AutomaticSize.Y
	create("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder, Parent = card })
	create("UIPadding", {
		PaddingTop = UDim.new(0, 12),
		PaddingBottom = UDim.new(0, 12),
		PaddingLeft = UDim.new(0, 14),
		PaddingRight = UDim.new(0, 14),
		Parent = card,
	})

	local title = create("TextLabel", {
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Text = config.Title or "",
		FontFace = font(Enum.FontWeight.SemiBold),
		TextSize = 14,
		TextColor3 = pal.Text,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = card,
	})
	local body = create("TextLabel", {
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Text = config.Content or "",
		FontFace = font(Enum.FontWeight.Regular),
		TextSize = 13,
		TextColor3 = pal.SubText,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = card,
	})

	local object = { Frame = card }
	function object:Set(newTitle, newContent)
		if newTitle ~= nil then
			title.Text = newTitle
		end
		if newContent ~= nil then
			body.Text = newContent
		end
	end
	return object
end

--------------------------------------------------------------------------------
-- Elements: Button
--------------------------------------------------------------------------------

-- config: { Name, Description (optional), Callback }
function Tab:Button(config)
	config = config or {}
	local pal = self.Window.Palette
	local hasDescription = config.Description ~= nil and config.Description ~= ""
	local card = newCard(self, hasDescription and 56 or 44, "TextButton")
	hoverable(card, pal, true)

	local title
	if hasDescription then
		title = textLabel(card, {
			Palette = pal,
			Position = UDim2.fromOffset(14, 8),
			Size = UDim2.new(1, -44, 0, 20),
			Text = config.Name or "Button",
		})
		textLabel(card, {
			Palette = pal,
			Position = UDim2.fromOffset(14, 29),
			Size = UDim2.new(1, -44, 0, 18),
			Text = config.Description,
			TextSize = 12,
			Color = pal.SubText,
			Weight = Enum.FontWeight.Regular,
		})
	else
		title = textLabel(card, {
			Palette = pal,
			Position = UDim2.fromOffset(14, 0),
			Size = UDim2.new(1, -44, 1, 0),
			Text = config.Name or "Button",
		})
	end
	chevron(card, pal)

	card.MouseButton1Click:Connect(function()
		-- soft flash on click
		card.BackgroundTransparency = pal.ElementHover - 0.06
		play(card, T.Smooth, { BackgroundTransparency = pal.ElementHover })
		task.spawn(safe, config.Callback)
	end)

	local object = { Frame = card }
	function object:SetName(text)
		title.Text = text
	end
	return object
end

--------------------------------------------------------------------------------
-- Elements: Toggle
--------------------------------------------------------------------------------

-- config: { Name, Default = false, Color (optional), Callback(value) }
function Tab:Toggle(config)
	config = config or {}
	local pal = self.Window.Palette
	local onColor = config.Color or pal.Green
	local card = newCard(self, 44, "TextButton")
	hoverable(card, pal, true)
	textLabel(card, {
		Palette = pal,
		Position = UDim2.fromOffset(14, 0),
		Size = UDim2.new(1, -80, 1, 0),
		Text = config.Name or "Toggle",
	})

	local TRACK_W, TRACK_H, KNOB = 44, 26, 22
	local track = create("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -14, 0.5, 0),
		Size = UDim2.fromOffset(TRACK_W, TRACK_H),
		BackgroundColor3 = pal.Off,
		BackgroundTransparency = pal.OffTransparency,
		BorderSizePixel = 0,
		Parent = card,
	}, {
		create("UICorner", { CornerRadius = UDim.new(1, 0) }),
	})
	local knob = create("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 2, 0.5, 0),
		Size = UDim2.fromOffset(KNOB, KNOB),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Parent = track,
	}, {
		create("UICorner", { CornerRadius = UDim.new(1, 0) }),
	})

	local toggle = { Value = config.Default == true, Frame = card }
	local pressed = false

	local function render(animate)
		local knobWidth = pressed and (KNOB + 6) or KNOB
		local knobProps = {
			Size = UDim2.fromOffset(knobWidth, KNOB),
			Position = toggle.Value and UDim2.new(1, -(knobWidth + 2), 0.5, 0) or UDim2.new(0, 2, 0.5, 0),
		}
		local trackProps = {
			BackgroundColor3 = toggle.Value and onColor or pal.Off,
			BackgroundTransparency = toggle.Value and 0 or pal.OffTransparency,
		}
		play(knob, animate and T.Spring or nil, knobProps)
		play(track, animate and T.Smooth or nil, trackProps)
	end
	render(false)

	function toggle:Set(value, silent)
		self.Value = value == true
		render(true)
		if not silent then
			task.spawn(safe, config.Callback, self.Value)
		end
	end

	card.MouseButton1Down:Connect(function()
		pressed = true
		render(true)
	end)
	card.MouseButton1Up:Connect(function()
		pressed = false
		render(true)
	end)
	card.MouseLeave:Connect(function()
		if pressed then
			pressed = false
			render(true)
		end
	end)
	card.MouseButton1Click:Connect(function()
		toggle:Set(not toggle.Value)
	end)

	return toggle
end

--------------------------------------------------------------------------------
-- Elements: Slider
--------------------------------------------------------------------------------

-- config: { Name, Min = 0, Max = 100, Default, Increment = 1, Suffix = "", Callback(value) }
function Tab:Slider(config)
	config = config or {}
	local window = self.Window
	local pal = window.Palette
	local min = config.Min or 0
	local max = config.Max or 100
	local increment = config.Increment or 1
	local places = decimals(increment)
	local suffix = config.Suffix or ""

	local slider = { Value = math.clamp(config.Default or min, min, max) }

	local card = newCard(self, 58)
	hoverable(card, pal)
	textLabel(card, {
		Palette = pal,
		Position = UDim2.fromOffset(14, 8),
		Size = UDim2.new(1, -110, 0, 20),
		Text = config.Name or "Slider",
	})
	local valueLabel = textLabel(card, {
		Palette = pal,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 8),
		Size = UDim2.fromOffset(90, 20),
		Text = "",
		TextSize = 13,
		Color = pal.SubText,
		AlignX = Enum.TextXAlignment.Right,
	})

	local track = create("Frame", {
		Position = UDim2.new(0, 14, 0, 40),
		Size = UDim2.new(1, -28, 0, 6),
		BackgroundColor3 = pal.Element,
		BackgroundTransparency = 0.85,
		BorderSizePixel = 0,
		Parent = card,
	}, {
		create("UICorner", { CornerRadius = UDim.new(1, 0) }),
	})
	local fill = create("Frame", {
		Size = UDim2.new(0, 0, 1, 0),
		BackgroundColor3 = pal.Accent,
		BorderSizePixel = 0,
		Parent = track,
	}, {
		create("UICorner", { CornerRadius = UDim.new(1, 0) }),
	})
	local knob = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, 0, 0.5, 0),
		Size = UDim2.fromOffset(16, 16),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Parent = track,
	}, {
		create("UICorner", { CornerRadius = UDim.new(1, 0) }),
		create("UIStroke", {
			Color = Color3.new(0, 0, 0),
			Transparency = 0.85,
			Thickness = 1,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
	})
	local hit = create("TextButton", {
		Position = UDim2.new(0, 14, 0, 28),
		Size = UDim2.new(1, -28, 0, 26),
		BackgroundTransparency = 1,
		Text = "",
		Parent = card,
	})

	local function ratio()
		if max == min then
			return 0
		end
		return (slider.Value - min) / (max - min)
	end

	local function render(info)
		local r = ratio()
		valueLabel.Text = string.format("%." .. places .. "f", slider.Value) .. suffix
		play(fill, info, { Size = UDim2.new(r, 0, 1, 0) })
		play(knob, info, { Position = UDim2.new(r, 0, 0.5, 0) })
	end
	render(nil)

	local function commit(value, info, silent)
		value = math.clamp(value, min, max)
		value = min + math.floor((value - min) / increment + 0.5) * increment
		value = math.clamp(value, min, max)
		value = tonumber(string.format("%." .. places .. "f", value))
		if value ~= slider.Value then
			slider.Value = value
			render(info)
			if not silent then
				task.spawn(safe, config.Callback, value)
			end
		end
	end

	function slider:Set(value, silent)
		commit(value, T.Smooth, silent)
	end

	local dragging = false
	local function fromPointer(x)
		local width = math.max(track.AbsoluteSize.X, 1)
		local rel = math.clamp((x - track.AbsolutePosition.X) / width, 0, 1)
		commit(min + (max - min) * rel, T.Drag, false)
	end

	hit.InputBegan:Connect(function(input)
		if isPointer(input) then
			dragging = true
			self._scroll.ScrollingEnabled = false
			play(knob, T.Fast, { Size = UDim2.fromOffset(20, 20) })
			fromPointer(input.Position.X)
		end
	end)
	bind(window, UserInputService.InputChanged, function(input)
		if dragging and isMove(input) then
			fromPointer(input.Position.X)
		end
	end)
	bind(window, UserInputService.InputEnded, function(input)
		if dragging and isPointer(input) then
			dragging = false
			self._scroll.ScrollingEnabled = true
			play(knob, T.Spring, { Size = UDim2.fromOffset(16, 16) })
		end
	end)

	slider.Frame = card
	return slider
end

--------------------------------------------------------------------------------
-- Elements: Dropdown
--------------------------------------------------------------------------------

-- config: { Name, Options = {...}, Default, Placeholder, Callback(option) }
function Tab:Dropdown(config)
	config = config or {}
	local pal = self.Window.Palette
	local HEADER, ITEM, MAX_VISIBLE = 44, 30, 5

	local dropdown = { Value = config.Default, Options = config.Options or {}, Open = false }

	local card = newCard(self, HEADER)
	card.ClipsDescendants = true
	hoverable(card, pal)

	local header = create("TextButton", {
		Size = UDim2.new(1, 0, 0, HEADER),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		Parent = card,
	})
	textLabel(header, {
		Palette = pal,
		Position = UDim2.fromOffset(14, 0),
		Size = UDim2.new(1, -190, 1, 0),
		Text = config.Name or "Dropdown",
	})
	local valueLabel = textLabel(header, {
		Palette = pal,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -36, 0, 0),
		Size = UDim2.new(0, 150, 1, 0),
		Text = "",
		TextSize = 13,
		Color = pal.SubText,
		AlignX = Enum.TextXAlignment.Right,
	})
	local arrow = chevron(header, pal)

	local list = create("ScrollingFrame", {
		Position = UDim2.fromOffset(6, HEADER),
		Size = UDim2.new(1, -12, 0, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 2,
		ScrollBarImageColor3 = pal.Element,
		ScrollBarImageTransparency = 0.6,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Parent = card,
	}, {
		create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }),
	})

	local entries = {}

	local function listHeight()
		return math.min(#dropdown.Options, MAX_VISIBLE) * ITEM
	end

	local function resize()
		list.Size = UDim2.new(1, -12, 0, listHeight())
		local target = dropdown.Open and (HEADER + listHeight() + 8) or HEADER
		play(card, T.Smooth, { Size = UDim2.new(1, 0, 0, target) })
	end

	local function paint()
		if dropdown.Value ~= nil then
			valueLabel.Text = tostring(dropdown.Value)
		else
			valueLabel.Text = config.Placeholder or "Select"
		end
		for _, entry in ipairs(entries) do
			local selected = entry.Option == dropdown.Value
			play(entry.Label, T.Fast, { TextColor3 = selected and pal.Text or pal.SubText })
			play(entry.Dot, T.Fast, { BackgroundTransparency = selected and 0 or 1 })
		end
	end

	local function setOpen(state)
		dropdown.Open = state
		play(arrow, T.Smooth, { Rotation = state and 90 or 0 })
		resize()
	end

	function dropdown:Set(option, silent)
		self.Value = option
		paint()
		if not silent then
			task.spawn(safe, config.Callback, option)
		end
	end

	local function rebuild()
		for _, entry in ipairs(entries) do
			entry.Button:Destroy()
		end
		entries = {}
		for index, option in ipairs(dropdown.Options) do
			local button = create("TextButton", {
				Size = UDim2.new(1, 0, 0, ITEM),
				BackgroundColor3 = pal.Element,
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				AutoButtonColor = false,
				Text = "",
				LayoutOrder = index,
				Parent = list,
			}, {
				create("UICorner", { CornerRadius = UDim.new(0, 8) }),
			})
			local label = textLabel(button, {
				Palette = pal,
				Position = UDim2.fromOffset(10, 0),
				Size = UDim2.new(1, -34, 1, 0),
				Text = tostring(option),
				TextSize = 13,
				Color = pal.SubText,
			})
			local dot = create("Frame", {
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -12, 0.5, 0),
				Size = UDim2.fromOffset(6, 6),
				BackgroundColor3 = pal.Accent,
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Parent = button,
			}, {
				create("UICorner", { CornerRadius = UDim.new(1, 0) }),
			})
			button.MouseEnter:Connect(function()
				play(button, T.Fast, { BackgroundTransparency = 0.92 })
			end)
			button.MouseLeave:Connect(function()
				play(button, T.Fast, { BackgroundTransparency = 1 })
			end)
			button.MouseButton1Click:Connect(function()
				dropdown:Set(option)
				setOpen(false)
			end)
			table.insert(entries, { Option = option, Button = button, Label = label, Dot = dot })
		end
		paint()
		resize()
	end

	function dropdown:Refresh(options, keepValue)
		self.Options = options or {}
		if not keepValue then
			self.Value = nil
		end
		rebuild()
	end

	header.MouseButton1Click:Connect(function()
		setOpen(not dropdown.Open)
	end)

	rebuild()
	dropdown.Frame = card
	return dropdown
end

--------------------------------------------------------------------------------
-- Elements: Input
--------------------------------------------------------------------------------

-- config: { Name, Placeholder, Default, ClearOnFocus = false, Callback(text, enterPressed) }
function Tab:Input(config)
	config = config or {}
	local pal = self.Window.Palette
	local card = newCard(self, 44)
	hoverable(card, pal)
	textLabel(card, {
		Palette = pal,
		Position = UDim2.fromOffset(14, 0),
		Size = UDim2.new(1, -190, 1, 0),
		Text = config.Name or "Input",
	})

	local box = create("TextBox", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.5, 0),
		Size = UDim2.fromOffset(160, 28),
		BackgroundColor3 = pal.Element,
		BackgroundTransparency = 0.9,
		BorderSizePixel = 0,
		Text = config.Default or "",
		PlaceholderText = config.Placeholder or "Type here...",
		PlaceholderColor3 = pal.SubText,
		FontFace = font(Enum.FontWeight.Medium),
		TextSize = 13,
		TextColor3 = pal.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ClearTextOnFocus = config.ClearOnFocus == true,
		Parent = card,
	}, {
		create("UICorner", { CornerRadius = UDim.new(0, 8) }),
		create("UIPadding", { PaddingLeft = UDim.new(0, 9), PaddingRight = UDim.new(0, 9) }),
	})
	local stroke = create("UIStroke", {
		Color = pal.Accent,
		Thickness = 1.5,
		Transparency = 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = box,
	})

	box.Focused:Connect(function()
		play(stroke, T.Fast, { Transparency = 0.1 })
		play(box, T.Fast, { BackgroundTransparency = 0.85 })
	end)
	box.FocusLost:Connect(function(enterPressed)
		play(stroke, T.Smooth, { Transparency = 1 })
		play(box, T.Smooth, { BackgroundTransparency = 0.9 })
		task.spawn(safe, config.Callback, box.Text, enterPressed)
	end)

	local object = { Frame = card, Box = box }
	function object:Set(text)
		box.Text = text
	end
	function object:Get()
		return box.Text
	end
	return object
end

--------------------------------------------------------------------------------
-- Elements: Keybind
--------------------------------------------------------------------------------

-- config: { Name, Default = Enum.KeyCode.X, Callback(), Changed(keyCode) }
function Tab:Keybind(config)
	config = config or {}
	local window = self.Window
	local pal = window.Palette
	local card = newCard(self, 44)
	hoverable(card, pal)
	textLabel(card, {
		Palette = pal,
		Position = UDim2.fromOffset(14, 0),
		Size = UDim2.new(1, -140, 1, 0),
		Text = config.Name or "Keybind",
	})

	local keybind = { Value = config.Default, Frame = card }
	local listening = false

	local button = create("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.5, 0),
		Size = UDim2.fromOffset(0, 28),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = pal.Element,
		BackgroundTransparency = 0.9,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		Parent = card,
	}, {
		create("UICorner", { CornerRadius = UDim.new(0, 8) }),
		create("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }),
	})
	local label = create("TextLabel", {
		Size = UDim2.new(0, 0, 1, 0),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		Text = "",
		FontFace = font(Enum.FontWeight.SemiBold),
		TextSize = 12,
		TextColor3 = pal.Text,
		Parent = button,
	})

	local function render()
		if listening then
			label.Text = "..."
		elseif keybind.Value then
			label.Text = keybind.Value.Name
		else
			label.Text = "None"
		end
		play(button, T.Fast, { BackgroundTransparency = listening and 0.8 or 0.9 })
		play(label, T.Fast, { TextColor3 = listening and pal.Accent or pal.Text })
	end
	render()

	function keybind:Set(keyCode, silent)
		self.Value = keyCode
		render()
		if not silent then
			task.spawn(safe, config.Changed, keyCode)
		end
	end

	button.MouseButton1Click:Connect(function()
		listening = true
		render()
	end)

	bind(window, UserInputService.InputBegan, function(input, processed)
		if listening then
			if input.UserInputType == Enum.UserInputType.Keyboard then
				listening = false
				if input.KeyCode == Enum.KeyCode.Escape then
					render()
				else
					keybind:Set(input.KeyCode)
				end
			end
			return
		end
		if not processed and keybind.Value and input.KeyCode == keybind.Value then
			task.spawn(safe, config.Callback)
		end
	end)

	return keybind
end

return AppMac
