--[[
	AppMac  -  v1.3.1
	Minimal Apple / macOS "Liquid Glass" UI library for Roblox.

	Load it from a LocalScript:
		local AppMac = loadstring(game:HttpGet("https://raw.githubusercontent.com/Aetheris-Devx/AppMac/main/src/AppMac.lua"))()
	or place this file as a ModuleScript (e.g. ReplicatedStorage.AppMac) and require it.
	See README.md and examples/Example.client.lua.

	Elements:  Section, Label, Paragraph, Button, Toggle, Slider,
	           Dropdown, Input, Keybind, Notify
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer

local AppMac = {}
AppMac.Version = "1.3.1"

local Window = {}
Window.__index = Window

local Tab = {}
Tab.__index = Tab

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local WINDOW_RADIUS = 18
local SIDEBAR_WIDTH = 170
local SIDEBAR_COLLAPSED = 80 -- icons only
local TOPBAR_HEIGHT = 52
local TAB_HEIGHT = 34
local TAB_GAP = 4
local TAB_STRIDE = TAB_HEIGHT + TAB_GAP

--------------------------------------------------------------------------------
-- Animation presets
--------------------------------------------------------------------------------

local T = {
	Fast = TweenInfo.new(0.15, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
	Smooth = TweenInfo.new(0.4, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out),
	Spring = TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	In = TweenInfo.new(0.22, Enum.EasingStyle.Quart, Enum.EasingDirection.In),
	Drag = TweenInfo.new(0.06, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
}

-- Springs (macOS-style motion). w = speed (angular frequency), z = damping (1 = no overshoot).
local Sp = {
	Window = { Spring = true, w = 17, z = 0.86 }, -- open, un-minimize
	Smooth = { Spring = true, w = 15, z = 1 }, -- resize, zoom, dropdowns
	Close = { Spring = true, w = 20, z = 1 }, -- minimize, dismiss
	Fade = { Spring = true, w = 24, z = 1 }, -- opacity
	Snappy = { Spring = true, w = 34, z = 0.88 }, -- toggles, press states
	Soft = { Spring = true, w = 26, z = 0.8 }, -- sliding tab pill
	Pop = { Spring = true, w = 24, z = 0.56 }, -- the orb
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

local function safe(fn, ...)
	if type(fn) ~= "function" then
		return
	end
	local ok, err = pcall(fn, ...)
	if not ok then
		warn("[AppMac] callback error: " .. tostring(err))
	end
end

--------------------------------------------------------------------------------
-- Spring engine
-- Interruptible, velocity-preserving motion. A new spring on a property that is
-- already moving keeps its current velocity, so reversing a window mid-animation
-- never jumps or stutters (this is what makes macOS feel fluid).
--------------------------------------------------------------------------------

local springs = {} -- [instance] = { [property] = record }
local tweenRegistry = setmetatable({}, { __mode = "k" }) -- [instance] = { [property] = tween }
local frameConnection

local function toArray(value)
	local kind = typeof(value)
	if kind == "number" then
		return { value }, 1
	elseif kind == "UDim2" then
		return { value.X.Scale, value.X.Offset, value.Y.Scale, value.Y.Offset }, 2
	elseif kind == "Vector2" then
		return { value.X, value.Y }, 3
	elseif kind == "Color3" then
		return { value.R, value.G, value.B }, 4
	end
	return nil, 0
end

local function fromArray(a, kind, clamp)
	if kind == 1 then
		return clamp and math.clamp(a[1], 0, 1) or a[1]
	elseif kind == 2 then
		return UDim2.new(a[1], a[2], a[3], a[4])
	elseif kind == 3 then
		return Vector2.new(a[1], a[2])
	end
	return Color3.new(math.clamp(a[1], 0, 1), math.clamp(a[2], 0, 1), math.clamp(a[3], 0, 1))
end

local EPSILON = {
	{ 0.0008 },
	{ 0.0004, 0.04, 0.0004, 0.04 },
	{ 0.04, 0.04 },
	{ 0.002, 0.002, 0.002 },
}

-- exact solution of a damped harmonic oscillator over dt (stable at any frame rate)
local function stepComponent(x, v, target, w, z, dt)
	local d = x - target
	if z >= 0.9999 then
		local e = math.exp(-w * dt)
		local b = v + w * d
		return target + e * (d + b * dt), e * (v - w * b * dt)
	end
	local c = z * w
	local wd = w * math.sqrt(1 - z * z)
	local e = math.exp(-c * dt)
	local cs, sn = math.cos(wd * dt), math.sin(wd * dt)
	return target + e * (d * cs + ((v + c * d) / wd) * sn), e * (v * cs - ((v * c + d * w * w) / wd) * sn)
end

local function onFrame(dt)
	if dt > 0.05 then
		dt = 0.05
	end
	local finished
	for obj, set in pairs(springs) do
		if not obj:IsDescendantOf(game) then
			springs[obj] = nil
		else
			for prop, rec in pairs(set) do
				local x, v, t, eps = rec.x, rec.v, rec.t, EPSILON[rec.kind]
				local settled = true
				for i = 1, #x do
					x[i], v[i] = stepComponent(x[i], v[i], t[i], rec.w, rec.z, dt)
					if math.abs(x[i] - t[i]) > eps[i] or math.abs(v[i]) > eps[i] * 25 then
						settled = false
					end
				end
				if settled then
					obj[prop] = fromArray(t, rec.kind, rec.clamp)
					set[prop] = nil
					local group = rec.group
					group.left = group.left - 1
					if group.left == 0 and group.done then
						finished = finished or {}
						table.insert(finished, group.done)
					end
				else
					obj[prop] = fromArray(x, rec.kind, rec.clamp)
				end
			end
			if next(set) == nil then
				springs[obj] = nil
			end
		end
	end
	-- completion callbacks run after the loop (they may start new springs)
	if finished then
		for _, fn in ipairs(finished) do
			safe(fn)
		end
	end
	if next(springs) == nil and frameConnection then
		frameConnection:Disconnect()
		frameConnection = nil
	end
end

local function springTo(obj, info, props, done)
	local set = springs[obj]
	if not set then
		set = {}
		springs[obj] = set
	end
	local registry = tweenRegistry[obj]
	local group = { left = 0, done = done }
	for prop, target in pairs(props) do
		if registry and registry[prop] then
			registry[prop]:Cancel()
			registry[prop] = nil
		end
		local t, kind = toArray(target)
		if not t then
			obj[prop] = target
			set[prop] = nil
		else
			local old = set[prop]
			local x, v
			if old then
				x, v = old.x, old.v
			else
				x = toArray(obj[prop])
				v = table.create(#x, 0)
			end
			set[prop] = {
				kind = kind,
				x = x,
				v = v,
				t = t,
				w = info.w,
				z = info.z,
				group = group,
				clamp = string.find(prop, "Transparency", 1, true) ~= nil,
			}
			group.left = group.left + 1
		end
	end
	if group.left == 0 then
		if next(set) == nil then
			springs[obj] = nil
		end
		if done then
			task.spawn(safe, done)
		end
	elseif not frameConnection then
		local signal = RunService:IsClient() and RunService.RenderStepped or RunService.Heartbeat
		frameConnection = signal:Connect(onFrame)
	end
end

-- stop any running spring / tween on one property (used when the user grabs something)
local function halt(obj, prop)
	local set = springs[obj]
	if set then
		set[prop] = nil
	end
	local registry = tweenRegistry[obj]
	if registry and registry[prop] then
		registry[prop]:Cancel()
		registry[prop] = nil
	end
end

local function apply(obj, props)
	for key, value in pairs(props) do
		halt(obj, key)
		obj[key] = value
	end
end

-- play(obj, nil, props)   applies instantly
-- play(obj, T.x, props)   tweens
-- play(obj, Sp.x, props)  springs. Optional done() fires when everything settled
--                         (it never fires if the motion gets interrupted).
local function play(obj, info, props, done)
	if not info then
		apply(obj, props)
		if done then
			task.spawn(safe, done)
		end
		return nil
	end
	if type(info) == "table" then -- spring preset (TweenInfo is userdata)
		springTo(obj, info, props, done)
		return nil
	end
	local set = springs[obj]
	if set then
		for key in pairs(props) do
			set[key] = nil
		end
	end
	local tween = TweenService:Create(obj, info, props)
	local registry = tweenRegistry[obj]
	if not registry then
		registry = {}
		tweenRegistry[obj] = registry
	end
	for key in pairs(props) do
		registry[key] = tween
	end
	if done then
		tween.Completed:Once(function(state)
			if state == Enum.PlaybackState.Completed then
				done()
			end
		end)
	end
	tween:Play()
	return tween
end

local function font(weight)
	return Font.new("rbxasset://fonts/families/GothamSSm.json", weight or Enum.FontWeight.Medium, Enum.FontStyle.Normal)
end

--------------------------------------------------------------------------------
-- Icons
-- Anywhere an icon is accepted you can pass either
--   "settings", "gamepad-2", "lucide-home"     a Lucide icon name (lucide.dev)
--   "rbxassetid://123", 123, "rbxthumb://..."  an image
-- Lucide sprites are fetched the first time a name is used. That needs an executor
-- (HttpGet + loadstring). Point AppMac.LucideSource at your own pinned copy, or call
-- AppMac:SetIconProvider(fn) to supply icons yourself.
--------------------------------------------------------------------------------

AppMac.LucideSource = "https://raw.githubusercontent.com/deividcomsono/lucide-roblox-direct/refs/heads/main/source.lua"

local LUCIDE_ALIASES = { home = "house", gear = "settings" }
local iconProvider, lucideLib
local lucideFailed, lucideLoading = false, false
local iconRequests = setmetatable({}, { __mode = "k" }) -- [ImageLabel] = icon that was last requested

local function isImageId(icon)
	if type(icon) == "number" then
		return true
	end
	return type(icon) == "string"
		and (
			string.sub(icon, 1, 13) == "rbxassetid://"
			or string.sub(icon, 1, 9) == "rbxasset:"
			or string.sub(icon, 1, 11) == "rbxthumb://"
			or string.sub(icon, 1, 4) == "http"
		)
end

-- normalized Lucide name for strings that look like one, otherwise nil
local function lucideName(icon)
	if type(icon) ~= "string" or isImageId(icon) then
		return nil
	end
	local name = string.lower(icon)
	name = string.gsub(name, "^lucide[%-:_]", "")
	name = string.gsub(name, "[%s_]+", "-")
	-- a single character, an emoji or ALL-CAPS initials are text, not an icon name
	if #name < 2 or not string.match(name, "^[a-z][a-z0-9%-]*$") or not string.find(icon, "[a-z%-_ :]") then
		return nil
	end
	return LUCIDE_ALIASES[name] or name
end

local function iconKind(icon)
	if isImageId(icon) then
		return "image"
	elseif lucideName(icon) then
		return "lucide"
	end
	return "text"
end

local function lookupAsset(name)
	if iconProvider then
		local ok, asset = pcall(iconProvider, name)
		return ok and type(asset) == "table" and asset or nil
	end
	if not lucideLib and not lucideFailed then
		if lucideLoading then
			while lucideLoading do
				task.wait()
			end
		else
			lucideLoading = true
			local ok, result = pcall(function()
				return loadstring(game:HttpGet(AppMac.LucideSource))()
			end)
			lucideLoading = false
			if ok and type(result) == "table" and type(result.GetAsset) == "function" then
				lucideLib = result
			else
				lucideFailed = true
				warn(
					"[AppMac] Lucide icons could not be loaded (they need an executor with HttpGet and loadstring). "
						.. "Use an rbxassetid:// icon instead, or call AppMac:SetIconProvider(fn). "
						.. tostring(result)
				)
			end
		end
	end
	if not lucideLib then
		return nil
	end
	local ok, asset = pcall(lucideLib.GetAsset, name)
	return ok and type(asset) == "table" and asset or nil
end

-- Puts an icon on an ImageLabel. Lucide names resolve in the background.
-- done(found) runs once the icon is known (it is skipped if the label was reused meanwhile).
local function loadIcon(label, icon, done)
	iconRequests[label] = icon
	local kind = iconKind(icon)
	if kind == "image" then
		label.Image = type(icon) == "number" and ("rbxassetid://" .. icon) or icon
		label.ImageRectOffset = Vector2.zero
		label.ImageRectSize = Vector2.zero
		if done then
			done(true)
		end
	elseif kind == "lucide" then
		local name = lucideName(icon)
		task.spawn(function()
			local asset = lookupAsset(name)
			if iconRequests[label] ~= icon or not label.Parent then
				return
			end
			if asset and asset.Url then
				label.Image = asset.Url
				label.ImageRectOffset = asset.ImageRectOffset or Vector2.zero
				label.ImageRectSize = asset.ImageRectSize or Vector2.zero
				if done then
					done(true)
				end
			else
				if not lucideFailed then
					warn('[AppMac] unknown icon "' .. tostring(icon) .. '"')
				end
				if done then
					done(false)
				end
			end
		end)
	else
		label.Image = ""
		if done then
			done(false)
		end
	end
end

-- provider: function(name) -> { Url, ImageRectSize?, ImageRectOffset? } | nil
-- (a table with a GetAsset(name) function, like the Lucide module, also works)
function AppMac:SetIconProvider(provider)
	if type(provider) == "table" and type(provider.GetAsset) == "function" then
		local source = provider
		provider = function(name)
			return source.GetAsset(name)
		end
	end
	iconProvider = provider
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
		play(card, Sp.Close, { Position = UDim2.new(0, 340, 0, 0) })
		play(card, Sp.Fade, { GroupTransparency = 1 })
		task.delay(0.2, function()
			if not wrapper.Parent then
				return
			end
			local height = wrapper.AbsoluteSize.Y
			wrapper.AutomaticSize = Enum.AutomaticSize.None
			wrapper.Size = UDim2.new(1, 0, 0, height)
			play(wrapper, Sp.Smooth, { Size = UDim2.new(1, 0, 0, 0) }, function()
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

	play(card, Sp.Window, { Position = UDim2.new(0, 0, 0, 0) })
	play(card, Sp.Fade, { GroupTransparency = 0 })
	play(bar, TweenInfo.new(duration, Enum.EasingStyle.Linear), { Size = UDim2.new(0, 0, 0, 2) })
	task.delay(duration, close)

	return { Close = close }
end

--------------------------------------------------------------------------------
-- Window
--------------------------------------------------------------------------------

-- config:
--   Title     string
--   Size      {w, h} | Vector2 | UDim2   default {560, 430}
--   Theme     "Dark" | "Light"          default "Dark"
--   Accent    Color3                    default Apple blue
--   ToggleKey Enum.KeyCode              default RightShift
--   Blur      boolean                   default true
--   OrbIcon   string                    Lucide name ("settings"), image id, text/emoji, or nil (first letter of Title)
--   Icon      string                    optional window icon, same formats (defaults to OrbIcon)
--   Subtitle  string                    small description under the title
--   Collapsible boolean                 show the sidebar toggle button, default true
--   Collapsed boolean                   start with the sidebar collapsed to icons, default false
--   CollapseIcon string                 optional icon for the toggle button (Lucide name or image id)
--   CollapseIconSize number             size of that icon in pixels, default 15
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
	self.Subtitle = config.Subtitle or ""
	self.Collapsible = config.Collapsible ~= false
	self.Collapsed = config.Collapsed == true
	AppMac._palette = self.Palette

	local pal = self.Palette

	-- sizing: the viewport can report 1x1 right when the script starts, so fall back to a sane size
	-- accept {w, h}, Vector2, or UDim2 for Size (offset values are used)
	local function toSize(s)
		if typeof(s) == "UDim2" then
			return s
		elseif typeof(s) == "Vector2" then
			return UDim2.fromOffset(s.X, s.Y)
		elseif type(s) == "table" then
			local w = s.X or s[1] or s.Width or 560
			local h = s.Y or s[2] or s.Height or 430
			return UDim2.fromOffset(w, h)
		end
		return UDim2.fromOffset(560, 430)
	end
	local requested = toSize(config.Size)
	local function computeSizes()
		local camera = workspace.CurrentCamera
		local vp = camera and camera.ViewportSize or Vector2.new(0, 0)
		if vp.X < 200 or vp.Y < 200 then
			vp = Vector2.new(1280, 720)
		end
		local rw = requested.X.Offset + requested.X.Scale * vp.X
		local rh = requested.Y.Offset + requested.Y.Scale * vp.Y
		local w = math.max(280, math.min(rw, vp.X - 24))
		local h = math.max(240, math.min(rh, vp.Y - 24))
		local zoom = UDim2.fromOffset(
			math.max(w, math.min(vp.X * 0.88, 1000)),
			math.max(h, math.min(vp.Y * 0.88, 700))
		)
		return UDim2.fromOffset(w, h), zoom
	end
	self.BaseSize, self.ZoomSize = computeSizes()

	local startWidth = self.Collapsed and SIDEBAR_COLLAPSED or SIDEBAR_WIDTH

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
		Size = UDim2.new(0, startWidth, 1, 0),
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

	self.Sidebar = sidebar

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

	-- tab list + sliding selection pill
	local tabScroll = create("ScrollingFrame", {
		Name = "Tabs",
		Position = UDim2.new(0, 10, 0, 54),
		Size = UDim2.new(1, -20, 1, -64),
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
		Visible = false,
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
		Position = UDim2.fromOffset(startWidth, 0),
		Size = UDim2.new(1, -startWidth, 1, 0),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = canvas,
	})
	self.Content = content
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
	-- title + icon, top right (macOS toolbar style). The subtitle sits under the title.
	local titleGroup = create("Frame", {
		Name = "TitleGroup",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -18, 0, TOPBAR_HEIGHT / 2),
		Size = UDim2.fromOffset(0, 34),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		ZIndex = 3,
		Parent = content,
	}, {
		create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	local titleStack = create("Frame", {
		Name = "Text",
		LayoutOrder = 1,
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		BackgroundTransparency = 1,
		ZIndex = 3,
		Parent = titleGroup,
	}, {
		create("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 1),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	self.TitleLabel = create("TextLabel", {
		Name = "Title",
		LayoutOrder = 1,
		Size = UDim2.fromOffset(0, 16),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		Text = self.Title,
		FontFace = font(Enum.FontWeight.SemiBold),
		TextSize = 13,
		TextColor3 = pal.Text,
		TextTransparency = 0.2,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 3,
		Parent = titleStack,
	}, {
		create("UISizeConstraint", { MaxSize = Vector2.new(190, 16) }),
	})
	self.SubtitleLabel = create("TextLabel", {
		Name = "Subtitle",
		LayoutOrder = 2,
		Size = UDim2.fromOffset(0, 13),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		Text = self.Subtitle,
		FontFace = font(Enum.FontWeight.Regular),
		TextSize = 11,
		TextColor3 = pal.SubText,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Visible = self.Subtitle ~= "",
		ZIndex = 3,
		Parent = titleStack,
	}, {
		create("UISizeConstraint", { MaxSize = Vector2.new(190, 13) }),
	})
	self.IconTile = create("Frame", {
		Name = "Icon",
		LayoutOrder = 2,
		Size = UDim2.fromOffset(22, 22),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ClipsDescendants = true,
		ZIndex = 3,
		Parent = titleGroup,
	}, {
		create("UICorner", { CornerRadius = UDim.new(0, 6) }),
	})
	self.IconGradient = create("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(pal.Accent:Lerp(Color3.new(1, 1, 1), 0.3), pal.Accent),
		Parent = self.IconTile,
	})
	self.IconStroke = create("UIStroke", {
		Color = Color3.new(1, 1, 1),
		Transparency = 0.82,
		Thickness = 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = self.IconTile,
	})
	self.IconText = create("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
		FontFace = font(Enum.FontWeight.Bold),
		TextSize = 13,
		TextColor3 = Color3.new(1, 1, 1),
		ZIndex = 4,
		Parent = self.IconTile,
	})
	self.IconImage = create("ImageLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Image = "",
		ScaleType = Enum.ScaleType.Fit,
		Visible = false,
		ZIndex = 4,
		Parent = self.IconTile,
	})
	-- the tab name on the left shrinks instead of running under the title
	self.Header.TextTruncate = Enum.TextTruncate.AtEnd
	local headerX = self.Collapsible and 52 or 24
	self._headerX = headerX
	self.Header.Position = UDim2.fromOffset(headerX, 14)
	self.HeaderSub = create("TextLabel", {
		Name = "HeaderSubtitle",
		Position = UDim2.fromOffset(headerX, 33),
		Size = UDim2.fromOffset(200, 14),
		BackgroundTransparency = 1,
		Text = "",
		FontFace = font(Enum.FontWeight.Regular),
		TextSize = 12,
		TextColor3 = pal.SubText,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextTransparency = 1,
		Parent = content,
	})

	-- sidebar toggle: collapses the tab list down to icons
	local collapseButton = create("TextButton", {
		Name = "Collapse",
		Position = UDim2.fromOffset(14, TOPBAR_HEIGHT / 2 - 14),
		Size = UDim2.fromOffset(28, 28),
		BackgroundColor3 = pal.Element,
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "",
		Visible = self.Collapsible,
		ZIndex = 3,
		Parent = content,
	}, {
		create("UICorner", { CornerRadius = UDim.new(0, 8) }),
	})
	local collapseScale = create("UIScale", { Parent = collapseButton })
	self.CollapseButton = collapseButton
	-- built-in glyph (a panel with a sidebar), used unless CollapseIcon is set
	self.CollapseGlyph = create("Frame", {
		Name = "Glyph",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(14, 11),
		BackgroundTransparency = 1,
		ZIndex = 4,
		Parent = collapseButton,
	}, {
		create("UICorner", { CornerRadius = UDim.new(0, 4) }),
		create("UIStroke", {
			Color = pal.Text,
			Transparency = 0.35,
			Thickness = 1.5,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
		create("Frame", {
			Name = "Divider",
			Position = UDim2.fromOffset(4, 0),
			Size = UDim2.new(0, 2, 1, 0),
			BackgroundColor3 = pal.Text,
			BackgroundTransparency = 0.45,
			BorderSizePixel = 0,
			ZIndex = 4,
		}),
	})
	local iconPx = math.clamp(tonumber(config.CollapseIconSize) or 15, 8, 24)
	self.CollapseImage = create("ImageLabel", {
		Name = "Icon",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(iconPx, iconPx),
		BackgroundTransparency = 1,
		ImageColor3 = pal.Text,
		ImageTransparency = 0.2,
		ScaleType = Enum.ScaleType.Fit,
		Visible = false,
		ZIndex = 4,
		Parent = collapseButton,
	})
	collapseButton.MouseEnter:Connect(function()
		play(collapseButton, T.Fast, { BackgroundTransparency = 0.9 })
	end)
	collapseButton.MouseLeave:Connect(function()
		play(collapseButton, T.Fast, { BackgroundTransparency = 1 })
		play(collapseScale, Sp.Snappy, { Scale = 1 })
	end)
	collapseButton.MouseButton1Down:Connect(function()
		play(collapseScale, Sp.Snappy, { Scale = 0.88 })
	end)
	collapseButton.MouseButton1Up:Connect(function()
		play(collapseScale, Sp.Snappy, { Scale = 1 })
	end)
	collapseButton.MouseButton1Click:Connect(function()
		self:SetCollapsed(not self.Collapsed)
	end)
	if config.CollapseIcon ~= nil then
		self:SetCollapseIcon(config.CollapseIcon)
	end

	local function fitHeader()
		local scale = math.max(self.Scale.Scale, 0.05)
		local contentWidth = holder.Size.X.Offset + content.Size.X.Offset
		local free = contentWidth - (headerX + titleGroup.AbsoluteSize.X / scale + 40)
		local width = math.max(60, free)
		self.Header.Size = UDim2.fromOffset(width, 28)
		self.HeaderSub.Size = UDim2.fromOffset(width, 14)
	end
	titleGroup:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitHeader)
	holder:GetPropertyChangedSignal("Size"):Connect(fitHeader)
	content:GetPropertyChangedSignal("Size"):Connect(fitHeader)
	fitHeader()

	self.Pages = create("Frame", {
		Name = "Pages",
		Position = UDim2.fromOffset(0, TOPBAR_HEIGHT),
		Size = UDim2.new(1, 0, 1, -TOPBAR_HEIGHT),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Parent = content,
	})

	-- minimized "orb" (tap to restore, drag to move)
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
	local orbIcon = create("ImageLabel", {
		Name = "Icon",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(22, 22),
		BackgroundTransparency = 1,
		ImageColor3 = pal.Text,
		Visible = false,
		Parent = orb,
	})
	self.Orb = orb
	self.OrbIcon = orbIcon
	self.OrbScale = create("UIScale", { Scale = 0, Parent = orb })
	self:SetOrbIcon(config.OrbIcon)
	if config.Icon ~= nil then
		self:SetIcon(config.Icon)
	end

	-- orb: tap restores the window, drag moves the orb (it never leaves the screen)
	local orbPressing, orbMoved = false, false
	local orbPressPos, orbStartPosition
	orb.InputBegan:Connect(function(input)
		if isPointer(input) then
			orbPressing = true
			orbMoved = false
			orbPressPos = input.Position
			orbStartPosition = orb.Position
			play(self.OrbScale, Sp.Snappy, { Scale = 0.9 })
		end
	end)
	bind(self, UserInputService.InputChanged, function(input)
		if orbPressing and isMove(input) then
			local delta = input.Position - orbPressPos
			if not orbMoved and delta.Magnitude < 6 then
				return
			end
			orbMoved = true
			local vp = gui.AbsoluteSize
			local cx = orbStartPosition.X.Scale * vp.X + orbStartPosition.X.Offset + delta.X
			local cy = orbStartPosition.Y.Scale * vp.Y + orbStartPosition.Y.Offset + delta.Y
			orb.Position = UDim2.fromOffset(
				math.clamp(cx, 22, math.max(22, vp.X - 22)),
				math.clamp(cy, 22, math.max(22, vp.Y - 22))
			)
		end
	end)
	bind(self, UserInputService.InputEnded, function(input)
		if orbPressing and isPointer(input) then
			orbPressing = false
			if not orbMoved and not self.Visible then
				self:Show()
			else
				play(self.OrbScale, Sp.Pop, { Scale = self.Visible and 0 or 1 })
			end
		end
	end)

	-- window drag: 1:1 with the pointer, always keeps the title bar reachable,
	-- double-click the bar to zoom (like macOS)
	local dragging = false
	local dragStart, startPosition
	local lastClick, lastClickPos = 0, Vector3.zero
	dragBar.InputBegan:Connect(function(input)
		if not isPointer(input) then
			return
		end
		local now = os.clock()
		if now - lastClick < 0.35 and (input.Position - lastClickPos).Magnitude < 10 then
			lastClick = 0
			dragging = false
			self:ToggleZoom()
			return
		end
		lastClick = now
		lastClickPos = input.Position
		dragging = true
		dragStart = input.Position
		startPosition = holder.Position
		halt(holder, "Position")
	end)
	bind(self, UserInputService.InputChanged, function(input)
		if dragging and isMove(input) then
			local delta = input.Position - dragStart
			local vp = gui.AbsoluteSize
			local size = holder.AbsoluteSize
			local cx = startPosition.X.Scale * vp.X + startPosition.X.Offset + delta.X
			local cy = startPosition.Y.Scale * vp.Y + startPosition.Y.Offset + delta.Y
			cx = math.clamp(cx, 80 - size.X / 2, math.max(80 - size.X / 2, vp.X - 80 + size.X / 2))
			cy = math.clamp(cy, size.Y / 2, math.max(size.Y / 2, vp.Y - 56 + size.Y / 2))
			holder.Position = UDim2.fromOffset(cx, cy)
		end
	end)
	bind(self, UserInputService.InputEnded, function(input)
		if dragging and isPointer(input) then
			dragging = false
		end
	end)

	-- toggle key
	bind(self, UserInputService.InputBegan, function(input, processed)
		-- gameProcessed is true for keys the game itself binds (RightShift is Roblox's Shift Lock),
		-- so only typing in a TextBox blocks the hotkey
		if input.KeyCode == self.ToggleKey and not self._capturing and not UserInputService:GetFocusedTextBox() then
			self:Toggle()
		end
	end)

	local function refit()
		if self.Destroyed then
			return
		end
		self.BaseSize, self.ZoomSize = computeSizes()
		play(holder, Sp.Smooth, { Size = self.Zoomed and self.ZoomSize or self.BaseSize })
	end
	local cameraConnection
	local function watchCamera()
		if cameraConnection then
			cameraConnection:Disconnect()
		end
		local cam = workspace.CurrentCamera
		if cam then
			cameraConnection = cam:GetPropertyChangedSignal("ViewportSize"):Connect(refit)
			table.insert(self.Connections, cameraConnection)
		end
		refit()
	end
	bind(self, workspace:GetPropertyChangedSignal("CurrentCamera"), watchCamera)
	watchCamera()

	-- mount + open animation
	canvas.GroupTransparency = 1
	gui.Parent = config.Parent or LocalPlayer:WaitForChild("PlayerGui")
	play(self.Scale, Sp.Window, { Scale = 1 })
	play(canvas, Sp.Fade, { GroupTransparency = 0 })
	setShadow(self.Shadow, pal, true, Sp.Fade)
	-- safety net: never leave the window invisible
	task.delay(1.2, function()
		if not self.Destroyed and self.Visible and canvas.Parent then
			canvas.GroupTransparency = 0
		end
	end)
	if self.UseBlur then
		blurUsers[self] = true
		refreshBlur()
	end

	return self
end

-- repaints the icon tile in the top-right corner of the window
function Window:_refreshIcon()
	local icon = self._customIcon and self.IconValue or self.OrbIconValue
	local kind = iconKind(icon)
	local letter = string.upper(string.sub(self.Title, 1, 1))
	local tile, image = self.IconTile, self.IconImage

	local function showText(text)
		iconRequests[image] = nil
		image.Visible = false
		image.Image = ""
		self.IconText.Visible = true
		self.IconText.Text = text
		tile.BackgroundTransparency = 0
		self.IconGradient.Enabled = true
		self.IconStroke.Transparency = 0.82
	end

	if kind == "image" then
		-- a full image replaces the tile
		self.IconText.Visible = false
		image.Visible = true
		image.AnchorPoint = Vector2.zero
		image.Position = UDim2.new()
		image.Size = UDim2.fromScale(1, 1)
		image.ImageColor3 = Color3.new(1, 1, 1)
		tile.BackgroundTransparency = 1
		self.IconGradient.Enabled = false
		self.IconStroke.Transparency = 1
		loadIcon(image, icon)
	elseif kind == "lucide" then
		-- a white glyph on the accent tile; the letter shows until the icon is ready
		showText(letter)
		loadIcon(image, icon, function(found)
			if self.Destroyed or (self._customIcon and self.IconValue or self.OrbIconValue) ~= icon then
				return
			end
			if found then
				self.IconText.Visible = false
				image.Visible = true
				image.AnchorPoint = Vector2.new(0.5, 0.5)
				image.Position = UDim2.fromScale(0.5, 0.5)
				image.Size = UDim2.fromOffset(14, 14)
				image.ImageColor3 = Color3.new(1, 1, 1)
			end
		end)
	else
		showText((type(icon) == "string" and icon ~= "") and icon or letter)
	end
end

-- icon of the minimized orb (and of the window, unless SetIcon was used):
--   a Lucide icon name, an image id ("rbxassetid://..."), a letter / emoji, or nil (first letter of the title)
function Window:SetOrbIcon(icon)
	self.OrbIconValue = icon
	local letter = string.upper(string.sub(self.Title, 1, 1))
	local kind = iconKind(icon)
	if kind == "image" then
		self.Orb.Text = ""
		self.OrbIcon.Visible = true
		loadIcon(self.OrbIcon, icon)
	elseif kind == "lucide" then
		-- the first letter shows until the icon is ready (or if it cannot be found)
		self.Orb.Text = letter
		self.OrbIcon.Visible = false
		loadIcon(self.OrbIcon, icon, function(found)
			if self.Destroyed or self.OrbIconValue ~= icon then
				return
			end
			self.OrbIcon.Visible = found
			self.Orb.Text = found and "" or letter
		end)
	else
		iconRequests[self.OrbIcon] = nil
		self.OrbIcon.Visible = false
		self.OrbIcon.Image = ""
		self.Orb.Text = (type(icon) == "string" and icon ~= "") and icon or letter
	end
	self:_refreshIcon()
end

-- icon in the top-right corner of the window only (nil = follow OrbIcon)
function Window:SetIcon(icon)
	self.IconValue = icon
	self._customIcon = icon ~= nil
	self:_refreshIcon()
end

function Window:SetTitle(text)
	self.Title = tostring(text or "")
	self.TitleLabel.Text = self.Title
	self:SetOrbIcon(self.OrbIconValue)
end

function Window:SetSubtitle(text)
	self.Subtitle = tostring(text or "")
	self.SubtitleLabel.Text = self.Subtitle
	self.SubtitleLabel.Visible = self.Subtitle ~= ""
end

-- re-lays one tab out for the current sidebar state (icons only when collapsed)
function Window:_layoutTab(tab, info)
	local collapsed = self.Collapsed
	local base = self.ActiveTab == tab and 0 or 0.4
	local iconShown = tab._icon ~= nil and tab._icon.Visible
	play(tab._label, info, { TextTransparency = collapsed and 1 or base })
	if tab._icon then
		play(tab._icon, info, {
			ImageTransparency = base,
			Position = UDim2.new(0, collapsed and 22 or 11, 0.5, 0),
		})
	end
	-- tabs without an icon show their first letter while collapsed
	play(tab._glyph, info, { TextTransparency = (collapsed and not iconShown) and base or 1 })
end

-- collapse the sidebar to a column of tab icons (true) or expand it again (false)
function Window:SetCollapsed(state, instant)
	if self.Destroyed then
		return
	end
	state = state == true
	if state == self.Collapsed and not instant then
		return
	end
	self.Collapsed = state
	local width = state and SIDEBAR_COLLAPSED or SIDEBAR_WIDTH
	local info = (not instant) and Sp.Smooth or nil
	play(self.Sidebar, info, { Size = UDim2.new(0, width, 1, 0) })
	play(self.Content, info, {
		Position = UDim2.fromOffset(width, 0),
		Size = UDim2.new(1, -width, 1, 0),
	})
	for _, tab in ipairs(self.Tabs) do
		self:_layoutTab(tab, (not instant) and Sp.Fade or nil)
	end
	self:_hideTip()
end

function Window:ToggleSidebar()
	self:SetCollapsed(not self.Collapsed)
end

-- icon of the sidebar toggle button: a Lucide name or an image id (nil = built-in glyph)
function Window:SetCollapseIcon(icon)
	self.CollapseIconValue = icon
	if iconKind(icon) == "text" then
		iconRequests[self.CollapseImage] = nil
		self.CollapseImage.Visible = false
		self.CollapseGlyph.Visible = true
		return
	end
	loadIcon(self.CollapseImage, icon, function(found)
		if self.Destroyed or self.CollapseIconValue ~= icon then
			return
		end
		self.CollapseImage.Visible = found
		self.CollapseGlyph.Visible = not found
	end)
end

-- tab name tooltip, shown next to an icon while the sidebar is collapsed
function Window:_ensureTip()
	if self.Tip then
		return
	end
	local pal = self.Palette
	self.Tip = create("Frame", {
		Name = "Tip",
		AnchorPoint = Vector2.new(0, 0.5),
		Size = UDim2.fromOffset(0, 28),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = pal.Base,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 100,
		Parent = self.Gui,
	}, {
		create("UICorner", { CornerRadius = UDim.new(0, 8) }),
		create("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }),
	})
	self.TipStroke = create("UIStroke", {
		Color = pal.Element,
		Transparency = 1,
		Thickness = 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = self.Tip,
	})
	self.TipLabel = create("TextLabel", {
		Size = UDim2.fromOffset(0, 28),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		Text = "",
		FontFace = font(Enum.FontWeight.Medium),
		TextSize = 13,
		TextColor3 = pal.Text,
		TextTransparency = 1,
		ZIndex = 101,
		Parent = self.Tip,
	})
end

function Window:_showTip(tab)
	if self.Destroyed or not self.Visible then
		return
	end
	self:_ensureTip()
	local button = tab._button
	local pos, size = button.AbsolutePosition, button.AbsoluteSize
	self.TipLabel.Text = tab.Name
	self.Tip.Position = UDim2.fromOffset(pos.X + size.X + 12, pos.Y + size.Y / 2)
	self.Tip.Visible = true
	play(self.Tip, Sp.Fade, { BackgroundTransparency = 0.04 })
	play(self.TipLabel, Sp.Fade, { TextTransparency = 0 })
	play(self.TipStroke, Sp.Fade, { Transparency = 0.86 })
end

function Window:_hideTip()
	if not self.Tip then
		return
	end
	local tip = self.Tip
	play(tip, Sp.Fade, { BackgroundTransparency = 1 }, function()
		if tip.Parent and tip.BackgroundTransparency >= 0.99 then
			tip.Visible = false
		end
	end)
	play(self.TipLabel, Sp.Fade, { TextTransparency = 1 })
	play(self.TipStroke, Sp.Fade, { Transparency = 1 })
end

-- un-minimize: the window grows back out of the orb
function Window:Show()
	if self.Visible or self.Destroyed then
		return
	end
	self.Visible = true
	local holder = self.Holder
	if not holder.Visible then
		apply(holder, { Position = self.Orb.Position, Visible = true })
		apply(self.Scale, { Scale = 0.14 })
		apply(self.Canvas, { GroupTransparency = 1 })
	end
	play(holder, Sp.Window, { Position = self._restPosition or UDim2.fromScale(0.5, 0.5) })
	play(self.Scale, Sp.Window, { Scale = 1 })
	play(self.Canvas, Sp.Fade, { GroupTransparency = 0 })
	setShadow(self.Shadow, self.Palette, true, Sp.Fade)
	play(self.OrbScale, Sp.Close, { Scale = 0 }, function()
		if self.Visible and self.Orb.Parent then
			self.Orb.Visible = false
		end
	end)
	if self.UseBlur then
		blurUsers[self] = true
		refreshBlur()
	end
end

-- minimize: the window shrinks into the orb
function Window:Hide()
	if not self.Visible or self.Destroyed then
		return
	end
	self.Visible = false
	local holder = self.Holder
	self:_hideTip()
	if self.Scale.Scale > 0.9 then
		self._restPosition = holder.Position
	end
	self.Orb.Visible = true
	play(holder, Sp.Close, { Position = self.Orb.Position })
	play(self.Scale, Sp.Close, { Scale = 0.14 })
	setShadow(self.Shadow, self.Palette, false, Sp.Fade)
	play(self.Canvas, Sp.Fade, { GroupTransparency = 1 }, function()
		if not self.Visible and not self.Destroyed then
			holder.Visible = false
		end
	end)
	task.delay(0.09, function()
		if not self.Visible and not self.Destroyed then
			play(self.OrbScale, Sp.Pop, { Scale = 1 })
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
	if self.Destroyed or not self.Visible then
		return
	end
	self.Zoomed = not self.Zoomed
	if self.Zoomed then
		self.PreviousPosition = self.Holder.Position
		play(self.Holder, Sp.Smooth, { Size = self.ZoomSize, Position = UDim2.fromScale(0.5, 0.5) })
	else
		play(self.Holder, Sp.Smooth, {
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
	local wasVisible = self.Visible
	self.Visible = false
	blurUsers[self] = nil
	refreshBlur()
	for _, connection in ipairs(self.Connections) do
		connection:Disconnect()
	end
	self.Connections = {}
	if wasVisible then
		play(self.Scale, Sp.Close, { Scale = 0.92 })
		play(self.Canvas, Sp.Fade, { GroupTransparency = 1 })
		setShadow(self.Shadow, self.Palette, false, Sp.Fade)
		task.delay(0.28, function()
			self.Gui:Destroy()
		end)
	else
		self.Gui:Destroy()
	end
end

--------------------------------------------------------------------------------
-- Tabs
--------------------------------------------------------------------------------

-- config: "Name"  or  { Name = "Name", Icon = "settings" | "rbxassetid://..." (optional), Subtitle = "..." (optional) }
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
	tab._glyph = create("TextLabel", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 22, 0.5, 0),
		Size = UDim2.fromOffset(16, 16),
		BackgroundTransparency = 1,
		Text = string.upper(string.sub(tab.Name, 1, 1)),
		FontFace = font(Enum.FontWeight.Bold),
		TextSize = 14,
		TextColor3 = pal.Text,
		TextTransparency = 1,
		Parent = tab._button,
	})
	tab.Subtitle = config.Subtitle

	if config.Icon then
		tab._icon = create("ImageLabel", {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 11, 0.5, 0),
			Size = UDim2.fromOffset(16, 16),
			BackgroundTransparency = 1,
			Image = "",
			ImageColor3 = pal.Text,
			ImageTransparency = 0.4,
			Parent = tab._button,
		})
		loadIcon(tab._icon, config.Icon, function(found)
			if not found and tab._icon.Parent then
				-- unknown icon: give the space back to the label
				tab._icon.Visible = false
				tab._label.Position = UDim2.fromOffset(12, 0)
				tab._label.Size = UDim2.new(1, -20, 1, 0)
				self:_layoutTab(tab, nil)
			end
		end)
	end

	tab._button.MouseEnter:Connect(function()
		if self.Collapsed then
			self:_showTip(tab)
		end
		if self.ActiveTab ~= tab then
			if not self.Collapsed then
				play(tab._label, T.Fast, { TextTransparency = 0.15 })
			end
			if tab._icon then
				play(tab._icon, T.Fast, { ImageTransparency = 0.15 })
			end
			if tab._glyph.TextTransparency < 1 then
				play(tab._glyph, T.Fast, { TextTransparency = 0.15 })
			end
		end
	end)
	tab._button.MouseLeave:Connect(function()
		self:_hideTip()
		if self.ActiveTab ~= tab then
			self:_layoutTab(tab, T.Fast)
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

	self:_layoutTab(tab, nil)

	return tab
end

function Window:SelectTab(tab, instant)
	if self.Destroyed or tab == self.ActiveTab then
		return
	end

	local previous = self.ActiveTab
	self.ActiveTab = tab

	for _, other in ipairs(self.Tabs) do
		self:_layoutTab(other, T.Fast)
	end

	-- sliding pill
	local y = (tab.Index - 1) * TAB_STRIDE
	self.Pill.Visible = true
	play(self.Pill, (not instant) and Sp.Soft or nil, { Position = UDim2.fromOffset(0, y) })

	-- header
	self.Header.Text = tab.Name
	local hasSub = tab.Subtitle ~= nil and tab.Subtitle ~= ""
	self.HeaderSub.Text = tab.Subtitle or ""
	play(self.Header, (not instant) and Sp.Smooth or nil, { Position = UDim2.fromOffset(self._headerX, hasSub and 8 or 14) })
	play(self.HeaderSub, (not instant) and T.Smooth or nil, { TextTransparency = hasSub and 0 or 1 })
	if not instant then
		self.Header.TextTransparency = 1
		play(self.Header, T.Smooth, { TextTransparency = 0 })
	end

	-- pages
	if previous then
		local old = previous._page
		play(old, Sp.Fade, { GroupTransparency = 1, Position = UDim2.fromOffset(0, -8) }, function()
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
		play(page, Sp.Smooth, { GroupTransparency = 0, Position = UDim2.fromOffset(0, 0) })
	end
end

--------------------------------------------------------------------------------
-- Element building blocks
--------------------------------------------------------------------------------

-- change (or clear) the description under the page title
function Tab:SetSubtitle(text)
	self.Subtitle = text
	local window = self.Window
	if window.ActiveTab == self then
		local hasSub = text ~= nil and text ~= ""
		window.HeaderSub.Text = text or ""
		play(window.Header, Sp.Smooth, { Position = UDim2.fromOffset(window._headerX, hasSub and 8 or 14) })
		play(window.HeaderSub, T.Smooth, { TextTransparency = hasSub and 0 or 1 })
	end
end

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
			play(scale, Sp.Snappy, { Scale = 0.985 })
		end)
		card.MouseButton1Up:Connect(function()
			play(scale, Sp.Snappy, { Scale = 1 })
		end)
		card.MouseLeave:Connect(function()
			play(scale, Sp.Snappy, { Scale = 1 })
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
		play(knob, animate and Sp.Snappy or nil, knobProps)
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
		commit(value, Sp.Smooth, silent)
	end

	local dragging = false
	local function fromPointer(x)
		local width = math.max(track.AbsoluteSize.X, 1)
		local rel = math.clamp((x - track.AbsolutePosition.X) / width, 0, 1)
		commit(min + (max - min) * rel, nil, false)
	end

	hit.InputBegan:Connect(function(input)
		if isPointer(input) then
			dragging = true
			self._scroll.ScrollingEnabled = false
			play(knob, Sp.Snappy, { Size = UDim2.fromOffset(20, 20) })
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
			play(knob, Sp.Snappy, { Size = UDim2.fromOffset(16, 16) })
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
		play(card, Sp.Smooth, { Size = UDim2.new(1, 0, 0, target) })
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
		play(arrow, Sp.Smooth, { Rotation = state and 90 or 0 })
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
		window._capturing = true
		render()
	end)

	bind(window, UserInputService.InputBegan, function(input, processed)
		if listening then
			if input.UserInputType == Enum.UserInputType.Keyboard then
				listening = false
				task.defer(function()
					window._capturing = false
				end)
				if input.KeyCode == Enum.KeyCode.Escape then
					render()
				elseif input.KeyCode == Enum.KeyCode.Backspace then
					keybind:Set(nil)
				else
					keybind:Set(input.KeyCode)
				end
			end
			return
		end
		if not window._capturing and keybind.Value and input.KeyCode == keybind.Value and not UserInputService:GetFocusedTextBox() then
			task.spawn(safe, config.Callback)
		end
	end)

	return keybind
end

return AppMac
