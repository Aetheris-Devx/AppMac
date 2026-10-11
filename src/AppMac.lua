--[[
	AppMac  -  v1.5.0
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
local TextService = game:GetService("TextService")

local LocalPlayer = Players.LocalPlayer

local AppMac = {}
AppMac.Version = "1.5.0"

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
	Pop = { Spring = true, w = 24, z = 0.56 }, -- bouncy pops
	Island = { Spring = true, w = 20, z = 0.66 }, -- the Dynamic Island morphing
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
-- About 1700 Lucide icons are bundled (two sprite sheets), so names work everywhere,
-- including Roblox Studio. A name that is not bundled falls back to a remote copy of the
-- Lucide set, which needs an executor
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

-- Bundled Lucide sprites (name:sheet:x:y), parsed the first time an icon name is used
local LUCIDE_SHEETS = { "rbxassetid://136111683851629", "rbxassetid://135883070486325" }
local LUCIDE_DATA = [==[align-vertical-distribute-center:1:175:0,chevron-down:1:625:25,list-restart:1:750:350,table-cells-split:2:25:125,gavel:1:200:750,dna-off:1:575:250,refresh-ccw-dot:1:475:900,venus:2:25:425,bean:1:25:375,circle-question-mark:1:650:50,folder-code:1:450:475,bolt:1:25:425,heater:1:25:975,feather:1:775:100,align-horizontal-distribute-center:1:50:75,grip-vertical:1:125:850,pill-bottle:1:950:375,person-standing:1:750:550,badge-swiss-franc:1:300:75,between-horizontal-end:1:75:350,file-braces-corner:1:600:275,rotate-cw:1:850:575,house-plus:1:675:350,bus-front:1:400:150,shield-ellipsis:1:525:975,between-vertical-end:1:25:400,globe-lock:1:500:475,tags:2:150:50,concierge-bell:1:0:750,bookmark-minus:1:275:225,plant-pot:1:725:600,file-down:1:250:625,picture-in-picture:1:400:900,messages-square:1:850:325,scissors:1:925:550,file-check-corner:1:450:425,phone-call:1:675:625,anchor:1:100:100,hand-helping:1:850:150,text-wrap:2:0:250,birdhouse:1:300:150,wifi-off:2:375:150,cloud-alert:1:150:575,message-square:1:900:275,cloud-download:1:50:675,folder-plus:1:50:875,cctv-off:1:200:400,notebook-dot:1:425:800,mirror-round:1:400:775,user-round:2:25:400,pointer:1:400:925,between-horizontal-start:1:50:375,chevrons-up-down:1:300:350,brush:1:25:500,message-circle-more:1:675:475,parentheses:1:500:775,book-up-2:1:425:75,flame:1:850:75,chevrons-up:1:275:375,square-dashed:1:950:750,square-mouse-pointer:1:925:800,superscript:2:75:50,signal:1:625:925,wifi-cog:2:450:75,hexagon:1:950:75,navigation-2-off:1:650:575,eye-off:1:200:650,arrows-up-from-line:1:225:100,file-code-corner:1:375:500,square-centerline-dashed-horizontal:1:800:850,panels-right-bottom:1:625:650,scaling:1:750:700,hash:1:600:400,arrow-left-from-line:1:75:200,ship:1:675:850,ticket-percent:2:50:225,calendar-clock:1:75:475,x:2:450:100,non-binary:1:450:775,voicemail:2:300:175,presentation:1:900:450,tree-palm:2:200:150,badge:1:225:150,captions-off:1:25:550,align-vertical-justify-center:1:100:75,download:1:225:600,mouse-right:1:425:775,text-align-justify-start:2:200:50,lens-convex:1:675:400,shrimp-off:1:875:675,focus:1:650:275,diamond-percent:1:125:675,arrow-big-up:1:125:125,volume-x:2:175:300,mouse-pointer-click:1:475:725,face-slightly-smiling-plus:1:25:825,hard-drive:1:650:350,grid-2x2-x:1:250:725,package-minus:1:675:575,cloud:1:450:300,pipette:1:850:475,corner-left-down:1:325:450,badge-cent:1:225:125,cloud-lightning:1:725:25,user-round-pen:2:125:300,arrow-left-to-line:1:25:250,book-open-text:1:50:425,monitor-cloud:1:350:825,parking-meter:1:450:825,cat:1:225:375,heart-handshake:1:200:800,dam:1:550:250,trees:2:150:200,ham:1:25:950,circle-pause:1:100:575,chess-king:1:75:550,bean-off:1:50:350,clef-alto:1:325:375,separator-horizontal:1:525:950,ambulance:1:200:0,globe-code:1:525:450,citrus:1:375:325,phone-missed:1:600:700,calendar-off:1:500:75,chart-column:1:525:100,battery-medium:1:175:225,square-minus:1:950:775,star-check:1:975:875,decimals-arrow-left:1:275:525,folder-output:1:100:825,menu:1:850:300,bangladeshi-taka:1:75:300,image-down:1:475:550,terminal:2:125:100,building-complex-plus:1:475:75,circle-dot-dashed:1:400:275,medal:1:950:200,cake-slice:1:300:250,git-graph:1:825:150,armchair:1:75:150,tickets:2:225:75,qr-code:1:675:675,copy:1:450:325,goal:1:400:575,book-bookmark:1:350:125,trending-down:2:125:225,creative-commons:1:150:625,layers-arrow-down:1:225:825,ev-charger:1:325:525,user-star:2:425:25,road:1:650:750,nfc:1:475:750,align-center-horizontal:1:0:100,text-align-justify-end:2:225:25,car:1:525:75,notebook-tabs:1:375:850,ear:1:800:50,videotape:2:400:75,sun-moon:2:50:50,chart-scatter:1:275:350,podium:1:450:875,toolbox:2:0:300,calendar:1:300:275,calendar-cog:1:50:500,gallery-horizontal:1:450:500,clipboard-x:1:0:700,list-sort-ascending:1:725:375,book-open:1:25:450,circle-pile:1:50:625,rectangle-ellipsis:1:675:700,badge-plus:1:0:350,badge-info:1:100:250,file-headphone:1:200:675,bow-arrow:1:25:475,clipboard-pen-line:1:100:600,user-round-key:2:175:250,folder-search:1:950:0,utensils-crossed:2:300:150,arrow-up:1:250:75,arrow-up-from-dot:1:100:200,align-vertical-justify-start:1:50:125,layers-minus:1:175:875,pause:1:400:875,shrub:1:800:750,flag:1:900:25,biceps-flexed:1:450:0,align-horizontal-distribute-end:1:25:100,donut:1:425:400,calendar-plus-2:1:475:100,move-vertical:1:800:425,file-pen-line:1:875:25,badge-russian-ruble:1:325:50,radius:1:425:925,pilcrow:1:975:350,corner-left-up:1:300:475,georgian-lari:1:150:800,cable:1:325:225,book-user:1:375:125,square-arrow-down:1:825:800,circle-plus:1:0:675,view:2:375:100,cctv:1:175:425,circle-arrow-left:1:125:525,square-off:1:900:825,octagon-alert:1:950:300,panel-bottom-dashed:1:350:900,book-a:1:425:50,align-end-vertical:1:75:50,thumbs-up:2:150:125,globe:1:425:550,rabbit:1:625:725,layers-plus:1:150:900,door-stairwell:1:275:550,banknote-arrow-down:1:50:325,message-square-off:1:275:875,dice-4:1:825:0,message-circle-x:1:525:625,folder-x:1:825:125,message-circle-warning:1:550:600,map:1:250:875,move:1:775:450,zoom-out:2:450:125,zoom-in:2:475:100,arrow-up-left:1:50:250,award:1:0:325,zodiac-virgo:2:75:475,layout-panel-top:1:825:250,file-check:1:425:450,list-music:1:825:275,arrow-down-wide-narrow:1:150:125,unfold-horizontal:2:275:125,lens-concave:1:700:375,zodiac-pisces:2:175:375,stone:2:50:0,motorbike:1:675:525,music-4:1:700:525,wind-arrow-up:2:225:300,shield-x:1:775:750,file-volume:1:350:550,disc-3:1:675:150,file-signal:1:650:250,columns-4:1:150:600,archive-x:1:125:100,zodiac-libra:2:225:325,square-dashed-kanban:1:825:850,mouse-pointer-2:1:525:675,clock-arrow-up:1:300:425,clock-fading:1:250:475,pencil-sparkles:1:850:450,zodiac-leo:2:250:300,vegan:2:100:350,star-plus:1:875:975,zodiac-gemini:2:275:275,clef-bass:1:300:400,message-circle-plus:1:625:525,popsicle:1:350:975,credit-card-plus:1:75:700,square-chevron-left:1:975:700,fast-forward:1:825:50,user-pen:2:325:100,chess-knight:1:50:575,wifi-pen:2:350:175,files:1:250:650,send-to-back:1:575:900,alarm-clock:1:50:50,zodiac-aries:2:350:200,zodiac-aquarius:2:375:175,receipt:1:725:650,wifi:2:275:250,shopping-basket:1:600:925,send:1:550:925,x-line-top:2:475:75,solar-panel:1:975:625,shelving-unit:1:675:825,worm:2:100:425,workflow:2:125:400,wine-off:2:175:350,germ-off:1:125:825,brush-cleaning:1:50:475,skip-back:1:925:650,wine:2:150:375,book-audio:1:375:100,wind-arrow-down:2:250:275,file-scan:1:725:175,cupcake:1:625:175,midi-port:1:600:575,message-square-dashed:1:425:725,tic-tac-toe:2:125:150,euro:1:350:500,chevrons-left:1:375:275,wifi-sync:2:325:200,umbrella:2:400:0,skip-forward:1:900:675,clipboard-copy:1:200:500,map-pin-off:1:500:625,arrow-up-from-line:1:75:225,circle-chevron-up:1:525:150,magnet:1:150:950,wifi-high:2:425:100,circle-small:1:575:125,align-vertical-space-between:1:0:175,lamp-desk:1:625:425,circle-arrow-up:1:675:0,zap:2:400:150,beaker:1:75:325,sun-dim:2:100:0,whistle:2:25:475,wheat-off:2:75:425,paintbrush:1:450:800,wheat:2:50:450,broccoli:1:125:400,weight-tilde:2:125:375,weight:2:100:400,chevron-up:1:500:150,send-horizontal:1:600:875,flask-conical-off:1:775:150,pen-tool:1:975:325,database-check:1:450:350,webcam-off:2:225:275,form:1:700:250,pencil-ruler:1:875:425,dna:1:550:275,arrow-big-down-dash:1:25:200,chart-area:1:150:450,bug-off:1:550:0,webcam:2:200:300,waypoints:2:250:250,card-sim:1:475:125,waves-vertical:2:275:225,waves-ladder:2:300:200,map-pin-search:1:400:725,waves-horizontal:2:325:175,eye-dashed:1:225:625,save:1:825:625,ellipse:1:600:250,spell-check:1:750:850,waves-arrow-down:2:375:125,watch:2:400:100,popcorn:1:375:950,blocks:1:175:275,washing-machine:2:425:75,layer-arrow-up:1:275:775,microchip:1:675:500,heart:1:50:950,badge-minus:1:50:300,cloud-sun:1:525:225,circle:1:425:275,shield-alert:1:650:850,wand-sparkles:2:0:475,utensils:2:275:175,map-minus:1:650:475,wallpaper:2:25:450,wallet-minimal:2:75:400,separator-vertical:1:500:975,wallet-cards:2:100:375,wallet:2:50:425,scan-square:1:525:925,ampersands:1:150:50,vote:2:125:350,user-search:2:0:425,volume-off:2:200:275,fence:1:750:125,rows-3:1:725:700,square-user-round:1:950:850,volume-1:2:250:225,volume:2:150:325,sunrise:2:125:0,strikethrough:2:50:25,calendar-days:1:25:525,folder-bookmark:1:550:375,volleyball:2:275:200,banknote-arrow-up:1:25:350,layout-arrow-right:1:75:975,clock-arrow-right:1:325:400,dollar-sign:1:475:350,message-square-quote:1:225:925,virus:2:325:150,tag:2:175:25,video:2:425:50,list-minus:1:850:250,cloud-hail:1:750:0,package-plus:1:625:625,eye-closed:1:250:600,app-window-mac:1:225:0,vibrate:2:475:0,ellipsis:1:550:300,copy-check:1:575:200,venus-and-mars:2:50:400,satellite:1:450:975,bookmark-plus:1:225:275,pentagon:1:800:500,folder-key:1:225:700,coffee:1:300:450,circle-power:1:675:25,logs:1:225:875,hourglass:1:775:250,tickets-plane:2:250:50,folder-git:1:325:600,vector-polygon:2:150:300,bomb:1:0:450,layers-2:1:250:800,battery-full:1:225:175,vault:2:175:275,line-dot-bottom-vertical:1:450:625,chart-gantt:1:500:125,folder-tree:1:875:75,command:1:100:650,badge-dollar-sign:1:175:175,align-start-vertical:1:0:150,briefcase-conveyor-belt:1:250:275,message-circle-question-mark:1:600:550,badge-x:1:250:125,bluetooth-off:1:125:325,van:2:225:225,square-square:1:900:875,cannabis:1:50:525,equal-approximately-not:1:500:350,book:1:325:175,grip-horizontal:1:150:825,circle-minus:1:200:475,audio-waveform:1:25:300,moon-star:1:800:400,arrow-down-narrow-wide:1:275:0,maximize-2:1:150:975,database-backup:1:475:325,wand:2:475:25,receipt-turkish-lira:1:750:625,users-round:2:350:100,calendar-minus-2:1:550:25,copy-minus:1:550:225,users:2:325:125,folder-input:1:275:650,book-image:1:175:300,user-x:2:400:50,mouse-left:1:600:600,tag-plus:2:0:175,shirt:1:650:875,percent:1:775:525,server-off:1:925:575,move-up:1:825:400,user-round-x:2:50:375,user-round-search:2:75:350,plug-2:1:575:750,crosshair:1:725:75,chess-rook:1:650:0,brackets:1:475:50,calendar-heart:1:575:0,list-ordered:1:800:300,image-plus:1:375:650,star-x:1:975:900,mic-off:1:775:400,user-round-group:2:200:225,arrow-big-left:1:225:25,square-split-horizontal:1:950:825,user-round-cog:2:225:200,user-round-check:2:250:175,clover:1:400:350,sun-snow:2:25:75,sofa:1:600:975,user-round-arrow-left:2:275:150,computer:1:25:725,funnel-x:1:550:400,user-minus:2:350:75,clock-2:1:600:125,calendar-fold:1:0:550,fish-off:1:150:750,baby:1:300:50,database-x:1:350:450,fold-vertical:1:600:325,user-lock:2:375:50,hop:1:875:150,face-angry:1:150:700,user-key:2:400:25,cigarette:1:200:450,calendar-chevrons-right:1:100:450,user-group:2:425:0,user-cog:2:0:400,diamond-plus:1:100:700,server-cog:1:975:525,file-chart-column:1:525:350,triangle-dashed:2:25:325,git-pull-request-closed:1:725:250,badge-check:1:200:150,user:2:375:75,usb-c-port:2:75:325,layers-arrow-up:1:200:850,plug-zap:1:550:775,heading-4:1:400:600,chess-queen:1:0:625,graduation-cap:1:350:625,grid-3x2:1:200:775,zodiac-sagittarius:2:150:400,square-dashed-x-corner:1:700:975,square-dashed-bottom-code:1:875:800,clock-7:1:475:250,ethernet-port:1:375:475,scan-text:1:500:950,upload:2:100:300,shower-head:1:925:625,equal-not:1:450:400,unplug:2:125:275,move-down:1:975:250,clock-arrow-down:1:375:350,ticket-slash:2:0:275,ruler:1:600:825,locate:1:400:700,unlink:2:150:250,circle-user-round:1:500:200,university:2:200:200,ungroup:2:225:175,list-filter:1:925:175,map-pin-check:1:600:525,egg-off:1:675:175,unfold-vertical:2:250:150,cog:1:275:475,dog:1:500:325,ice-cream-bowl:1:575:450,swords:2:125:25,spotlight:1:975:650,panel-right-dashed:1:850:425,undo-2:2:350:50,paper-bag:1:575:700,truck-electric:2:275:100,undo:2:300:100,check-line:1:200:425,underline:2:375:25,bubbles:1:0:525,bot:1:75:425,chart-bar-increasing:1:75:525,umbrella-off:2:0:375,playing-card:1:650:675,air-vent:1:75:0,type-outline:2:50:325,dot:1:250:575,flask-round:1:725:200,mouth:1:350:850,armenian-dram:1:50:175,clipboard-paste:1:125:575,chevron-last:1:575:75,book-heart:1:200:275,paperclip:1:550:725,circle-parking:1:125:550,globe-check:1:550:425,cloud-check:1:100:625,panel-left:1:900:375,circle-chevron-right:1:550:125,case-lower:1:375:225,fan:1:850:25,squares-unite:1:950:875,arrow-down-up:1:175:100,git-fork:1:850:125,forward:1:675:275,brain-circuit:1:450:75,between-vertical-start:1:0:425,database:1:300:500,panel-right:1:800:475,fingerprint-pattern:1:200:700,turntable:2:175:200,turkish-lira:2:200:175,log-out:1:250:850,git-branch-plus:1:0:950,clipboard-minus:1:150:550,file-text:1:500:400,tube-lotion:2:225:150,truck:2:250:125,trophy:2:300:75,table-rows-split:2:125:50,milk-off:1:550:625,tv-minimal:2:100:275,cloud-upload:1:475:275,banknote:1:375:25,triangles-centerline-dashed-horizontal:2:350:25,message-circle-dashed-check:1:750:400,drumstick:1:0:825,folder-closed:1:475:450,calendar-search:1:400:175,triangle-alert:2:50:300,line-dot-top-vertical:1:375:700,bell-ring:1:125:300,circle-chevron-left:1:575:100,triangle:2:375:0,arrow-down:1:100:175,arrow-up-down:1:125:175,folder-dot:1:400:525,tree-deciduous:2:225:125,trending-up:2:75:275,whole-word:2:475:50,monitor:1:825:375,disc-2:1:700:125,trending-up-down:2:100:250,square-asterisk:1:875:775,user-shield:2:450:0,transgender:2:300:50,tv-minimal-play:2:125:250,circle-stop:1:525:175,align-vertical-space-around:1:25:150,chess-bishop:1:100:525,train-front-tunnel:2:25:300,train-front:2:0:325,arrow-big-down:1:0:225,circle-parking-off:1:150:525,calendar-x-2:1:350:225,user-plus:2:300:125,move-diagonal-2:1:300:900,bandage:1:100:275,gallery-horizontal-end:1:475:475,panel-top-dashed:1:725:550,traffic-cone:2:75:250,tractor:2:100:225,tram-front:2:325:25,tower-control:2:150:175,plug:1:525:800,touchpad-off:2:225:100,audio-lines:1:50:275,touchpad:2:200:125,torus:2:250:75,tornado:2:275:50,toothbrush-sparkles:2:325:0,rocket:1:575:825,toothbrush:2:300:25,ear-off:1:825:25,tool-case:2:25:275,save-check:1:925:525,toilet:2:50:250,squares-exclude:1:850:950,printer:1:800:550,megaphone-off:1:925:225,toggle-left:2:100:200,arrow-big-right:1:175:75,section:1:625:850,file-clock:1:400:475,timer-reset:2:150:150,toy-brick:2:125:200,square-chevron-down:1:675:975,dice-1:1:50:750,drill:1:150:675,app-window:1:200:25,robot-vacuum:1:600:800,hand-metal:1:825:175,timer:2:125:175,spell-check-2:1:775:825,timeline:2:200:100,ticket-x:2:300:0,list-plus:1:775:325,sport-shoe:1:625:975,rotate-ccw-key:1:425:975,ticket-minus:2:75:200,chart-pie:1:300:325,replace:1:775:625,message-circle-off:1:650:500,copy-slash:1:500:275,wind:2:200:325,move-down-left:1:250:950,layout-panel-left:1:850:225,thermometer-sun:2:225:50,circle-percent:1:75:600,thermometer-snowflake:2:250:25,circle-arrow-out-down-right:1:75:575,square-x:1:900:900,italic:1:100:925,chart-column-increasing:1:575:50,thermometer:2:200:75,step-forward:1:900:975,theater:2:275:0,a-arrow-down:1:0:0,broom-sparkles:1:100:425,sticker:1:950:950,lock-keyhole-open:1:375:725,text-quote:2:50:200,newspaper:1:500:725,text-cursor-input:2:125:125,text-cursor:2:100:150,heart-pulse:1:100:900,import:1:250:775,badge-turkish-lira:1:275:100,square-terminal:1:800:975,file-music:1:0:875,text-align-justify-center:2:250:0,beef:1:350:75,faucet:1:800:75,file-user:1:400:500,text-align-justify:2:175:75,square-radical:1:875:875,text-align-end:2:0:225,image-upscale:1:325:700,book-type:1:450:50,text-align-center:2:25:200,signpost-big:1:575:975,test-tubes:2:50:175,cloudy:1:425:325,test-tube-diagonal:2:100:125,rugby-ball:1:650:775,brick-wall-fire:1:375:150,navigation-off:1:600:625,arrow-left:1:0:275,car-taxi-front:1:550:50,square-scissors:1:825:925,mouth-off:1:375:825,chevrons-right-left:1:350:300,tent:2:150:75,telescope:2:200:25,house-wifi:1:650:375,tangent:2:0:200,saudi-riyal:1:975:475,leaf:1:775:300,square-dimensions:1:925:775,face-slightly-smiling:1:0:850,align-end-horizontal:1:100:25,layer-arrow-down:1:300:750,equal:1:425:425,megaphone:1:900:250,calendar-x:1:325:250,tally-3:2:75:125,table-of-contents:2:175:0,egg:1:650:200,tally-1:2:125:75,rotate-cw-clock:1:925:500,ship-cargo:1:725:800,circle-pound-sterling:1:700:0,video-off:2:450:25,japanese-yen:1:950:100,tablets:2:25:150,tablet-smartphone:2:75:100,refresh-cw-off:1:425:950,library:1:600:475,file-terminal:1:525:375,circle-chevron-down:1:600:75,accessibility:1:50:0,table-properties:2:150:25,square-library:1:750:950,amphora:1:125:75,hourglass-cog:1:800:225,tally-2:2:100:100,table-columns-split:2:0:150,table-cells-merge:2:50:100,building-complex:1:450:100,table-2:2:75:75,sheet:1:725:775,circle-check-big:1:650:25,table:2:100:75,syringe:2:100:50,map-pinned:1:300:825,corner-down-left:1:375:400,circuit-board:1:400:300,power-off:1:950:400,switch-camera:2:0:125,swiss-franc:2:25:100,shield-lock:1:925:600,folder-open-dot:1:150:775,book-dashed:1:275:200,sunset:2:100:25,sun-medium:2:75:25,bluetooth:1:75:375,tree-pine:2:175:175,receipt-indian-rupee:1:900:475,rotate-ccw-clock:1:450:950,mic-audio-lines:1:800:375,subscript:2:25:50,stretch-vertical:2:75:0,stretch-horizontal:2:0:50,can-soda:1:200:375,flask-conical:1:750:175,hotel:1:825:200,funnel:1:525:425,square-star:1:850:925,folder-sync:1:900:50,monitor-pc:1:200:975,zodiac-ophiuchus:2:200:350,headset:1:250:750,sticky-note-x:2:0:0,arrow-up-narrow-wide:1:25:275,fishing-hook:1:75:825,chart-no-axes-column-increasing:1:400:225,equal-approximately:1:475:375,gap-horizontal:1:275:675,frame:1:650:300,calendar-arrow-down:1:200:350,clock-12:1:625:100,star-minus:1:925:925,sticky-note-check:1:925:975,sticky-note:2:25:0,images:1:275:750,lollipop:1:200:900,book-text:1:475:25,stethoscope:1:975:925,lamp-floor:1:600:450,file-plus-corner:1:800:100,image:1:300:725,step-back:1:925:950,badge-euro:1:150:200,bike:1:425:25,angle:1:75:125,star-off:1:900:950,refrigerator:1:975:425,star:1:950:925,stamp:1:850:975,squirrel:1:875:950,file-video-camera:1:375:525,option:1:800:450,banknote-check:1:0:375,scroll-text:1:825:650,server-plus:1:900:600,squircle:1:900:925,search-alert:1:775:700,repeat:1:825:575,toggle-right:2:75:225,square-user:1:925:875,ferris-wheel:1:725:150,camera-off:1:250:325,square-text:1:975:825,case-sensitive:1:350:250,square-stack:1:875:900,square-split-vertical:1:925:850,soap-dispenser-droplet:1:625:950,group:1:75:900,square-slash:1:775:975,battery:1:100:300,rewind:1:700:700,tent-tree:2:175:50,square-round-corner:1:850:900,rectangle-horizontal:1:625:750,iv-bag:1:975:75,square-plus:1:925:825,square-play:1:950:800,bitcoin:1:275:175,square-pilcrow:1:975:775,battery-plus:1:150:250,database-search:1:375:425,square-pi:1:750:975,file-diff:1:300:575,square-percent:1:775:950,message-square-lock:1:325:825,square-pause:1:825:900,spline-pointer:1:725:875,ligature:1:550:525,axis-3d:1:325:25,square-parking:1:850:875,piano:1:475:825,binoculars:1:375:75,square-m:1:725:975,square-kanban:1:775:925,square-function:1:800:900,rose:1:500:900,land-plot:1:500:550,mail-minus:1:925:200,square-equal:1:850:850,square-dot:1:875:825,square-divide:1:900:800,nut-off:1:250:975,clipboard-pen:1:75:625,bottle-wine:1:50:450,alarm-clock-off:1:100:0,shield-question-mark:1:825:700,list:1:550:550,monitor-pause:1:225:950,square-arrow-right:1:975:675,dome:1:450:375,badge-pound-sterling:1:375:0,bookmark-check:1:300:200,sliders-horizontal:1:800:775,wrench-off:2:75:450,square-dashed-bottom:1:850:825,a-arrow-up:1:25:0,clock-check:1:275:450,square-code:1:900:775,square-chevron-up:1:925:750,vibrate-off:2:0:450,face-grinning:1:100:750,zodiac-cancer:2:325:225,ratio:1:975:400,file-code:1:350:525,sliders-vertical:1:775:800,carton-off:1:425:175,credit-card-reader:1:50:725,square-chart-gantt:1:750:900,cassette-tape:1:300:300,battery-low:1:200:200,square-centerline-dashed-vertical:1:775:875,square-bottom-dashed-scissors:1:825:825,signpost:1:975:600,square-bookmark:1:850:800,calendar-arrow-up:1:175:375,landmark:1:475:575,fish-symbol:1:125:775,trash-off:2:275:75,loader:1:475:625,bold:1:50:400,dice-2:1:25:775,file-type:1:450:450,clipboard-clock:1:225:475,beer:1:300:125,lectern:1:725:350,square-arrow-up-right:1:925:725,router:1:775:650,phone-incoming:1:625:675,binary:1:400:50,move-diagonal:1:275:925,square-arrow-right-exit:1:650:975,door-closed:1:325:500,square-arrow-right-enter:1:675:950,layout-template:1:800:275,square-arrow-out-up-right:1:700:925,square-arrow-out-up-left:1:725:900,monitor-off:1:250:925,bookmark-off:1:250:250,hand-heart:1:875:125,square-arrow-out-down-left:1:775:850,scan-qr-code:1:575:875,message-square-check:1:475:675,search-x:1:675:800,square-arrow-down-right:1:850:775,gamepad-directional:1:325:625,brain:1:400:125,monitor-up:1:875:325,square:1:875:925,sprout:1:925:700,key:1:775:275,clock-11:1:650:75,spray-can:1:950:675,ticket-plus:2:25:250,arrow-up-0-1:1:200:100,bell-electric:1:225:200,shield-keyhole:1:950:575,heading:1:325:675,book-open-check:1:75:400,panel-top-close:1:750:525,lasso-select:1:350:700,screen-share-off:1:875:600,caravan:1:500:100,speech:1:800:800,speaker:1:825:775,bus:1:375:175,sparkles:1:850:750,audio-lines-x:1:75:250,chart-no-axes-gantt:1:325:300,file-spreadsheet:1:600:300,sparkle:1:875:725,clipboard-list:1:175:525,spade:1:900:700,contact-round:1:725:50,file-play:1:825:75,keyboard-off:1:725:325,soup:1:950:650,file-badge:1:650:225,battery-warning:1:125:275,mail-question-mark:1:825:300,arrow-down-from-line:1:25:225,briefcase:1:175:350,biohazard:1:350:100,rectangle-circle:1:700:675,braces:1:500:25,scale-3d:1:800:650,panel-top-bottom-dashed:1:775:500,mail-x:1:750:375,square-dashed-mouse-pointer:1:800:875,square-sparkles:1:975:800,lock-open:1:325:775,snowflake:1:650:925,pizza:1:825:500,list-indent-decrease:1:900:200,arrow-up-wide-narrow:1:300:25,snail:1:675:900,clock-5:1:525:200,smartphone-nfc:1:725:850,rotate-ccw:1:950:475,align-horizontal-justify-center:1:150:0,chevrons-down:1:450:200,antenna:1:50:150,memory-stick:1:875:275,scan-eye:1:675:775,smartphone:1:700:875,square-check:1:700:950,heart-plus:1:125:875,door-closed-cog:1:400:425,map-pin-minus-inside:1:550:575,git-merge:1:775:200,gallery-vertical-end:1:400:550,square-dashed-plus:1:775:900,hand-coins:1:950:50,zodiac-capricorn:2:300:250,wifi-low:2:400:125,skull:1:875:700,clock:1:200:525,file-pen:1:850:50,git-compare-arrows:1:900:75,cloud-sun-rain:1:550:200,align-horizontal-justify-start:1:100:50,siren:1:950:625,signature:1:600:950,signal-zero:1:650:900,calendar-plus:1:450:125,signal-medium:1:675:875,arrow-down-z-a:1:125:150,bath:1:275:125,signal-low:1:700:850,unlink-2:2:175:225,sigma:1:750:800,shopping-cart-minus:1:575:950,folder-check:1:525:400,shuffle:1:775:775,book-key:1:150:325,ribbon:1:675:725,microwave:1:625:550,shrink:1:825:725,gallery-vertical:1:375:575,shrimp:1:850:700,hard-drive-download:1:700:300,square-dashed-text:1:750:925,map-pin-pen:1:475:650,move-up-left:1:875:350,shopping-cart-plus:1:550:975,folder-heart:1:300:625,orbit:1:775:475,shopping-bag:1:625:900,ship-wheel:1:700:825,arrow-up-a-z:1:150:150,shield-user:1:800:725,square-dashed-top-solid:1:725:950,shield-plus:1:850:675,shield-off:1:875:650,git-pull-request-create:1:675:300,swatch-book:2:50:75,receipt-cent:1:950:425,spool:1:650:950,folder-archive:1:575:350,folder-symlink:1:925:25,can:1:175:400,ban:1:150:225,message-square-x:1:925:250,paint-roller:1:500:750,shield-half:1:975:550,archive:1:100:125,shield-cog-corner:1:575:925,shield-cog:1:550:950,shield-check:1:600:900,circle-slash-2:1:625:75,shield-ban:1:625:875,cake:1:275:275,cloud-rain:1:600:150,chart-bar:1:25:575,shield:1:750:775,wrench:2:50:475,shell:1:700:800,gamepad:1:300:650,share:1:750:750,flag-triangle-right:1:925:0,shapes:1:800:700,settings-2:1:850:650,bell:1:100:325,settings:1:825:675,server-crash:1:950:550,music-3:1:725:500,chart-bar-big:1:125:475,user-check:2:25:375,proportions:1:750:600,server:1:875:625,plane:1:750:575,webhook-off:2:175:325,carrot:1:450:150,square-arrow-left:1:800:825,file-cog:1:325:550,circle-dashed:1:475:200,search-slash:1:700:775,search-code:1:725:750,dices:1:750:75,germ:1:100:850,squares-subtract:1:975:850,search:1:650:825,scroll:1:800:675,split:1:675:925,list-sort-descending:1:700:400,screen-share:1:850:625,forklift:1:725:225,lightbulb:1:500:575,alarm-clock-minus:1:0:75,heart-x:1:75:925,eraser:1:400:450,square-sigma:1:800:950,school:1:975:500,bluetooth-connected:1:150:300,rotate-ccw-square:1:975:450,chart-no-axes-column:1:375:250,cannabis-off:1:75:500,folder-kanban:1:250:675,scan-search:1:550:900,mars-stroke:1:225:900,phone-off:1:575:725,messages-circle:1:875:300,scan-face:1:650:800,file-box:1:625:250,scan-box:1:700:750,paint-bucket:1:525:725,glass-water:1:600:375,scan-barcode:1:725:725,glasses:1:575:400,piggy-bank:1:375:925,scan:1:475:975,cuboid:1:675:125,cloud-off:1:650:100,check-check:1:225:400,activity:1:25:25,axe:1:350:0,plane-takeoff:1:775:550,pin-off:1:900:425,cloud-rain-wind:1:625:125,save-plus:1:850:600,gem:1:175:775,copy-x:1:475:300,file-axis-3d:1:675:200,radical:1:550:800,chart-column-decreasing:1:600:25,save-off:1:900:550,bug-play:1:525:25,align-vertical-distribute-start:1:125:50,file-braces:1:575:300,waves-arrow-up:2:350:150,tally-5:2:25:175,satellite-dish:1:475:950,sandwich:1:500:925,salad:1:525:900,circle-divide:1:450:225,sailboat:1:550:875,rows-2:1:750:675,ruler-dimension-line:1:625:800,life-buoy:1:575:500,external-link:1:275:575,rows-4:1:700:725,volume-2:2:225:250,battery-charging:1:250:150,russian-ruble:1:575:850,square-arrow-up-left:1:950:700,brick-wall-shield:1:350:175,footprints:1:750:200,route-off:1:825:600,building:1:425:125,route:1:800:625,fire-extinguisher:1:175:725,rotate-cw-fading-clock:1:900:525,tag-x:2:200:0,book-alert:1:400:75,link-2:1:275:800,astroid:1:175:150,bell-minus:1:200:225,image-up:1:350:675,closed-caption:1:175:550,drum:1:25:800,arrow-up-z-a:1:275:50,sun:2:0:100,rotate-3d:1:475:925,roller-coaster:1:525:875,file-key:1:100:775,database-arrow-down:1:525:275,robot-arm:1:625:775,scissors-line-dashed:1:950:525,layers:1:125:925,reply:1:725:675,replace-all:1:800:600,ticket-check:2:100:175,combine:1:125:625,repeat-off:1:850:550,repeat-2:1:875:525,mountain:1:625:575,mars:1:200:925,picture-in-picture-2:1:425:875,radio-off:1:525:825,flower-2:1:700:225,repeat-1:1:900:500,squares-intersect:1:825:975,remove-formatting:1:925:475,regex:1:950:450,keyboard-music:1:750:300,star-half:1:950:900,playing-cards-fan:1:625:700,code-xml:1:350:400,pencil-line:1:925:375,mails:1:675:450,brain-cog:1:425:100,tablet:2:50:125,refresh-cw:1:400:975,pi:1:500:800,trash:2:250:100,book-down:1:250:225,hdmi-port:1:500:500,trailer:2:50:275,case-upper:1:325:275,circle-fading-arrow-up:1:275:400,pilcrow-left:1:350:950,croissant:1:800:0,redo:1:500:875,circle-arrow-right:1:0:650,barcode:1:350:50,rectangle-vertical:1:600:775,rectangle-goggles:1:650:725,bed:1:400:25,git-merge-conflict:1:800:175,divide:1:600:225,grape:1:325:650,receipt-swiss-franc:1:800:575,party-popper:1:425:850,file-chart-pie:1:475:400,receipt-russian-ruble:1:825:550,list-indent-increase:1:875:225,dice-6:1:775:50,receipt-japanese-yen:1:875:500,blender:1:225:225,receipt-euro:1:925:450,zap-off:2:425:125,square-check-big:1:725:925,rat:1:375:975,rainbow:1:400:950,octagon-pause:1:900:350,laptop-minimal:1:400:650,radio-receiver:1:500:850,radio:1:450:900,map-pin-minus:1:525:600,radiation:1:575:775,chart-spline:1:250:375,message-square-more:1:300:850,radar:1:600:750,chart-candlestick:1:0:600,quote:1:650:700,arrow-down-a-z:1:50:200,pyramid:1:700:650,puzzle:1:725:625,move-horizontal:1:950:275,file-sliders:1:625:275,projector:1:775:575,square-exclamation-point:1:825:875,cup-soda:1:650:150,printer-check:1:850:500,map-pin-plus:1:425:700,sword:2:150:0,power:1:925:425,pound-sterling:1:975:375,earth:1:750:100,slice:1:825:750,dice-3:1:0:800,milk:1:525:650,mouse-pointer-ban:1:500:700,crown:1:700:100,circle-slash:1:600:100,circle-star:1:550:150,rotate-cw-square:1:875:550,atom:1:125:200,package-x:1:575:675,bed-double:1:0:400,layout-dashboard:1:975:100,circle-dot:1:375:300,file-exclamation-point:1:225:650,hand-fist:1:925:75,message-circle-code:1:775:375,folder-git-2:1:350:575,message-square-code:1:450:700,plus:1:500:825,towel-rack:2:175:150,playing-cards:1:600:725,arrow-big-left-dash:1:250:0,play-off:1:700:625,dumbbell:1:850:0,play:1:675:650,plane-landing:1:800:525,houses:1:600:425,scale:1:775:675,pin:1:875:450,flashlight:1:800:125,panel-top-open:1:700:575,pill:1:925:400,mailbox:1:700:425,notebook:1:325:900,redo-2:1:550:825,pickaxe:1:450:850,square-menu:1:975:750,chevrons-left-right:1:400:250,monitor-smartphone:1:950:250,laptop:1:375:675,scan-line:1:600:850,clock-4:1:550:175,square-arrow-up:1:900:750,book-minus:1:100:375,file-question-mark:1:750:150,phone-forwarded:1:650:650,phone:1:525:775,save-pen:1:875:575,arrow-down-to-line:1:200:75,phi:1:725:575,refresh-ccw:1:450:925,venetian-mask:2:75:375,calendar-check-2:1:150:400,pencil-off:1:900:400,spline:1:700:900,banknote-x:1:400:0,git-pull-request-create-arrow:1:700:275,pen-off:1:300:975,circle-check:1:625:50,pen-line:1:325:950,hand:1:775:225,pc-case:1:350:925,paw-print:1:375:900,bed-single:1:425:0,parasol:1:525:750,timer-off:2:175:125,arrow-big-right-dash:1:200:50,calendar-minus:1:525:50,panels-left-bottom:1:650:625,panel-top:1:675:600,backpack:1:275:75,panel-right-open:1:825:450,panel-right-close:1:875:400,panel-left-right-dashed:1:925:350,panel-left-open:1:950:325,mic-signal:1:750:425,arrow-down-right:1:250:25,panel-left-dashed:1:975:300,letters:1:650:425,wifi-zero:2:300:225,eject:1:625:225,panel-bottom-close:1:375:875,panel-bottom:1:300:950,layout-grid-circles:1:925:150,image-off:1:425:600,panda:1:400:850,move-right:1:900:325,paintbrush-vertical:1:475:775,package-search:1:600:650,square-chevron-right:1:950:725,mail-search:1:800:325,package-open:1:650:600,bone-fracture:1:475:0,crop:1:775:25,package-2:1:725:525,package:1:550:700,origami:1:750:500,lambda:1:675:375,ampersand:1:175:25,ad:1:0:50,shopping-cart:1:975:575,align-vertical-justify-end:1:75:100,omega:1:825:425,alarm-smoke:1:25:75,dock:1:525:300,file-input:1:125:750,clock-8:1:450:275,hand-grab:1:900:100,cloud-cog:1:75:650,blend:1:250:200,hd:1:525:475,radio-tower:1:475:875,list-tree:1:625:475,droplet:1:75:750,octagon-minus:1:925:325,eye:1:175:675,cloud-sync:1:500:250,square-dashed-x:1:975:725,banana:1:125:250,gpu:1:375:600,nut:1:975:275,notepad-text-dashed:1:300:925,circle-equal:1:325:350,face-slightly-frowning:1:50:800,notepad-text:1:275:950,library-big:1:625:450,file-chart-column-increasing:1:550:325,text-initial:2:75:175,arrow-up-right:1:0:300,network:1:525:700,leafy-green:1:750:325,message-square-dot:1:375:775,file-chart-line:1:500:375,columns-3-cog:1:200:550,nepali-rupee:1:550:675,navigation-2:1:625:600,minimize-2:1:500:675,navigation:1:575:650,music-2:1:750:475,cone:1:775:0,engine:1:525:325,file-image:1:150:725,move-up-right:1:850:375,palette:1:425:825,barrel:1:325:75,gallery-thumbnails:1:425:525,move-left:1:925:300,cpu:1:175:600,move-down-right:1:225:975,thumbs-down:2:175:100,merge:1:825:325,hamburger:1:0:975,move-3d:1:325:875,hat-glasses:1:575:425,code:1:325:425,mail:1:725:400,mouse-pointer:1:450:750,mouse-off:1:575:625,list-clock:1:125:950,carton:1:400:200,circle-arrow-out-down-left:1:100:550,kanban:1:900:150,bone:1:450:25,apple:1:175:50,rocking-chair:1:550:850,bot-off:1:100:400,flower:1:675:250,mop:1:725:475,moon:1:775:425,circle-arrow-out-up-left:1:50:600,message-square-plus:1:250:900,cable-car:1:350:200,arrow-down-left:1:0:250,square-activity:1:900:725,monitor-stop:1:900:300,cigarette-off:1:225:425,monitor-speaker:1:925:275,message-circle:1:500:650,circle-arrow-out-up-right:1:25:625,car-battery:1:600:0,monitor-play:1:975:225,fold-horizontal:1:625:300,shovel:1:950:600,calendar-1:1:225:325,cloud-moon:1:675:75,square-arrow-out-down-right:1:750:875,lock-keyhole:1:350:750,clock-plus:1:225:500,circle-euro:1:300:375,cloud-snow:1:575:175,anvil:1:25:175,arrow-big-up-dash:1:150:100,monitor-dot:1:300:875,monitor-cog:1:325:850,monitor-check:1:375:800,link-2-off:1:300:775,minus:1:450:725,list-chevrons-up-down:1:150:925,chevrons-down-up:1:475:175,clipboard-plus:1:50:650,circle-x:1:450:250,list-end:1:975:125,milestone:1:575:600,microscope:1:650:525,chevrons-right:1:325:325,audio-lines-off:1:100:225,message-square-reply:1:200:950,corner-down-right:1:350:425,mic-vocal:1:725:450,summary:2:0:75,lamp-wall-down:1:575:475,mic:1:700:475,layout-arrow-down:1:100:950,ellipsis-vertical:1:575:275,globe-off:1:475:500,square-stop:1:825:950,arrow-up-1-0:1:175:125,align-horizontal-justify-end:1:125:25,scan-heart:1:625:825,align-vertical-distribute-end:1:150:25,heart-crack:1:225:775,airplay:1:50:25,message-square-warning:1:950:225,message-square-text:1:975:200,message-square-share:1:175:975,monitor-x:1:850:350,bell-check:1:275:150,database-minus:1:425:375,square-pen:1:800:925,message-square-heart:1:350:800,message-square-diff:1:400:750,dice-5:1:800:25,octagon:1:850:400,ticket:2:275:25,message-circle-heart:1:700:450,message-circle-dashed:1:725:425,briefcase-plus:1:200:325,bookmark:1:175:325,message-circle-check:1:800:350,utility-pole:2:250:200,maximize:1:975:175,chart-bar-decreasing:1:100:500,database-plus:1:400:400,calendar-sync:1:375:200,funnel-plus:1:575:375,store:2:25:25,circle-arrow-down:1:150:500,notebook-pen:1:400:825,egg-fried:1:700:150,map-pin-x-inside:1:375:750,map-pin-x:1:350:775,corner-right-up:1:250:525,hand-platter:1:800:200,printer-3d:1:875:475,user-round-plus:2:100:325,panel-left-close:1:275:975,map-pin:1:325:800,pilcrow-right:1:325:975,user-round-minus:2:150:275,bell-off:1:175:250,mail-pen:1:875:250,mail-plus:1:850:275,mail-clock:1:950:175,mail-check:1:975:150,mail-badge:1:125:975,mouse-pointer-2-off:1:550:650,drone:1:125:700,slash:1:850:725,credit-card-x:1:25:750,aperture:1:0:200,arrow-right-left:1:275:25,circle-alert:1:175:475,vector-square:2:125:325,circle-gauge:1:225:450,log-in:1:275:825,check:1:175:450,text-search:2:25:225,arrow-down-to-dot:1:225:50,monitor-down:1:275:900,lock:1:300:800,chef-hat:1:150:475,calculator:1:250:300,locate-fixed:1:450:650,file-archive:1:700:175,signal-high:1:725:825,inbox:1:225:800,loader-pinwheel:1:500:600,loader-circle:1:525:575,image-play:1:400:625,align-horizontal-space-between:1:50:100,corner-right-down:1:275:500,calendar-check:1:125:425,database-zap:1:325:475,droplets:1:50:775,list-video:1:600:500,broom:1:75:450,bird:1:325:125,layout-list:1:875:200,file-search:1:675:225,lamp-ceiling:1:650:400,alarm-clock-plus:1:75:25,circle-dollar-sign:1:425:250,usb:2:50:350,house:1:625:400,receipt-pound-sterling:1:850:525,house-plug:1:700:325,list-collapse:1:100:975,id-card:1:500:525,mouse:1:400:800,minimize:1:475:700,list-chevrons-down-up:1:175:900,list-checks:1:200:875,galaxy:1:500:450,list-check:1:225:850,book-x:1:350:150,mirror-rectangular:1:425:750,link:1:250:825,line-style:1:325:750,line-squiggle:1:350:725,headphone-off:1:300:700,asterisk:1:200:125,line-dot-right-horizontal:1:400:675,octagon-x:1:875:375,languages:1:450:600,lighthouse:1:475:600,alarm-clock-check:1:25:50,guitar:1:50:925,calendar-range:1:425:150,beer-off:1:325:100,scooter:1:900:575,square-parking-off:1:875:850,notebook-text:1:350:875,arrow-right-to-line:1:250:50,clef-treble:1:275:425,tally-4:2:50:150,zodiac-taurus:2:100:450,layout-grid:1:900:175,door-open:1:300:525,flag-triangle-left:1:0:900,grid-3x3:1:175:800,file:1:275:625,layout-freeform:1:950:125,pocket-knife:1:475:850,book-copy:1:300:175,castle:1:250:350,car-front:1:575:25,clock-alert:1:400:325,reply-all:1:750:650,cloud-moon-rain:1:700:50,clipboard-type:1:25:675,lasso:1:325:725,list-todo:1:650:450,printer-x:1:825:525,lamp-wall-up:1:550:500,list-start:1:675:425,lamp:1:525:525,a-large-small:1:0:25,keyboard:1:700:350,key-square:1:800:250,map-plus:1:275:850,kazakh-tenge:1:850:200,kayak:1:875:175,joystick:1:925:125,database-arrow-up:1:500:300,arrow-right-from-line:1:300:0,flame-kindling:1:875:50,square-power:1:900:850,iteration-cw:1:50:975,bring-to-front:1:150:375,iteration-ccw:1:75:950,inspection-panel:1:125:900,bell-plus:1:150:275,info:1:150:875,infinity:1:175:850,indian-rupee:1:200:825,folders:1:775:175,mail-warning:1:775:350,image-minus:1:450:575,id-card-lanyard:1:525:500,ice-cream-cone:1:550:475,bridge:1:300:225,chart-line:1:475:150,file-lock:1:75:800,cast:1:275:325,circle-fading-plus:1:250:425,clock-10:1:675:50,undo-dot:2:325:75,target:2:225:0,list-filter-plus:1:950:150,house-heart:1:725:300,drama:1:175:650,compass:1:75:675,baseline:1:300:100,martini:1:175:950,contrast:1:650:125,hospital:1:850:175,candy-off:1:125:450,heart-minus:1:175:825,book-check:1:325:150,highlighter:1:925:100,book-lock:1:125:350,helicopter:1:975:50,briefcase-medical:1:225:300,calendars:1:275:300,text-align-start:2:150:100,heart-off:1:150:850,hop-off:1:900:125,warehouse:2:450:50,sticky-notes:2:0:25,drafting-compass:1:200:625,save-all:1:950:500,heading-6:1:350:650,heading-5:1:375:625,heading-3:1:425:575,heading-2:1:450:550,heading-1:1:475:525,fishing-rod:1:50:850,book-headphones:1:225:250,credit-card:1:0:775,haze:1:550:450,hard-hat:1:625:375,hard-drive-upload:1:675:325,shredder:1:900:650,panel-bottom-open:1:325:925,door-closed-package:1:350:475,handbag:1:750:250,credit-card-check:1:125:650,balloon:1:175:200,map-pin-plus-inside:1:450:675,bookmark-x:1:200:300,badge-question-mark:1:350:25,pen:1:950:350,hammer:1:975:25,candy-cane:1:150:425,grip:1:100:875,file-symlink:1:550:350,gamepad-2:1:350:600,grid-2x2-check:1:300:675,grid-2x2:1:225:750,globe-x:1:450:525,git-pull-request-draft:1:650:325,shield-minus:1:900:625,circle-off:1:175:500,dessert:1:200:600,eclipse:1:725:125,church:1:250:400,columns-3:1:175:575,cylinder:1:575:225,badge-japanese-yen:1:75:275,file-x:1:300:600,receipt-text:1:775:600,git-compare:1:875:100,git-commit-vertical:1:925:50,git-commit-horizontal:1:950:25,circle-ellipsis:1:350:325,file-output:1:900:0,disc-album:1:650:175,git-branch:1:975:0,arrow-down-0-1:1:100:150,captions:1:0:575,gift:1:50:900,ghost:1:75:875,philippine-peso:1:700:600,badge-alert:1:250:100,gauge:1:225:725,folder-pen:1:75:850,cross:1:750:50,gap-vertical:1:250:700,chevron-right:1:525:125,sticky-note-minus:1:975:950,square-arrow-down-left:1:875:750,share-2:1:775:725,fullscreen:1:600:350,fuel:1:625:325,folder-up:1:850:100,folder-search-2:1:0:925,folder-root:1:25:900,folder-open:1:125:800,chess-pawn:1:25:600,folder-minus:1:175:750,briefcase-business:1:275:250,folder-lock:1:200:725,message-circle-reply:1:575:575,folder-cog:1:425:500,triangle-right:2:0:350,folder-clock:1:500:425,folder:1:800:150,mop-sparkles:1:750:450,type:2:25:350,webhook:2:150:350,flashlight-off:1:825:100,align-horizontal-distribute-start:1:0:125,flag-off:1:25:875,fish:1:100:800,pointer-off:1:425:900,turtle:2:150:225,camera:1:225:350,film:1:225:675,file-x-corner:1:325:575,git-pull-request:1:625:350,bluetooth-searching:1:100:350,arrow-up-to-line:1:325:0,squircle-dashed:1:925:900,clock-3:1:575:150,badge-percent:1:25:325,face-expressionless:1:125:725,file-up:1:425:475,file-type-corner:1:475:425,grid-2x2-plus:1:275:700,file-stack:1:575:325,box:1:0:500,file-search-corner:1:700:200,clock-1:1:700:25,file-heart:1:175:700,house-cog:1:750:275,space:1:925:675,file-minus-corner:1:50:825,file-minus:1:25:850,file-digit:1:275:600,corner-up-left:1:225:550,clock-6:1:500:225,zodiac-scorpio:2:125:425,key-round:1:825:225,headphones:1:275:725,tv:2:75:300,factory:1:875:0,face-neutral:1:75:775,rss:1:675:750,expand:1:300:550,at-sign:1:150:175,map-pin-check-inside:1:625:500,sticky-note-off:1:950:975,music:1:675:550,handshake:1:725:275,earth-lock:1:775:75,circle-user:1:475:225,copy-plus:1:525:250,droplet-off:1:100:725,virus-off:2:350:125,line-dot-left-horizontal:1:425:650,disc:1:625:200,diff:1:725:100,search-check:1:750:725,clipboard-check:1:250:450,columns-2:1:225:525,diamond-minus:1:150:650,clipboard:1:725:0,align-center-vertical:1:125:0,diameter:1:175:625,delete:1:225:575,club:1:375:375,cloud-fog:1:0:725,mosque:1:700:500,currency:1:600:200,map-pin-house:1:575:550,package-check:1:700:550,chevron-first:1:600:50,pencil:1:825:475,boxes:1:525:0,list-x:1:575:525,copyright:1:400:375,copyleft:1:425:350,corner-up-right:1:200:575,cookie:1:625:150,clock-arrow-left:1:350:375,container:1:675:100,contact:1:700:75,badge-indian-rupee:1:125:225,construction:1:750:25,redo-dot:1:525:850,component:1:50:700,align-start-horizontal:1:25:125,chart-column-stacked:1:550:75,file-plus:1:775:125,git-pull-request-arrow:1:750:225,coins:1:250:500,decimals-arrow-right:1:250:550,bell-dot:1:250:175,folder-down:1:375:550,cloud-drizzle:1:25:700,cloud-backup:1:125:600,align-horizontal-space-around:1:75:75,door-closed-locked:1:375:450,clock-9:1:425:300,diamond:1:75:725,blinds:1:200:250,clapperboard:1:350:350,circle-play:1:25:650,book-search:1:500:0,git-branch-minus:1:25:925,circle-dashed-check:1:500:175,recycle:1:575:800,mountain-snow:1:650:550,luggage:1:175:925,chevrons-left-right-ellipsis:1:425:225,bot-message-square:1:125:375,phone-outgoing:1:550:750,smartphone-charging:1:750:825,chevron-left:1:550:100,train-track:2:350:0,cherry:1:125:500,chart-bar-stacked:1:50:550,sticky-note-plus:1:975:975,chart-no-axes-column-decreasing:1:425:200,chart-network:1:450:175,chart-column-big:1:625:0,chart-no-axes-combined:1:350:275,metronome:1:825:350,triangles-centerline-dashed-vertical:2:325:50,arrow-down-1-0:1:75:175,credit-card-minus:1:100:675,candy:1:100:475,arrow-left-right:1:50:225,lightbulb-off:1:525:550,panels-top-left:1:600:675,beef-off:1:375:50,locate-off:1:425:675,bug:1:500:50,test-tube:2:75:150,brick-wall:1:325:200,cooking-pot:1:600:175,boom-box:1:150:350,book-up:1:400:100,book-plus:1:0:475,laptop-minimal-check:1:425:625,mail-open:1:900:225,park:1:475:800,baggage-claim:1:200:175,variable:2:200:250,arrow-right:1:225:75,archive-restore:1:150:75]==]
local lucideSprites

local function bundledAsset(name)
	if not lucideSprites then
		lucideSprites = {}
		for n, sheet, x, y in string.gmatch(LUCIDE_DATA, "([%w%-]+):(%d):(%d+):(%d+)") do
			lucideSprites[n] = { tonumber(sheet), tonumber(x), tonumber(y) }
		end
	end
	local sprite = lucideSprites[name]
	if sprite then
		return {
			Url = LUCIDE_SHEETS[sprite[1]],
			ImageRectSize = Vector2.new(24, 24),
			ImageRectOffset = Vector2.new(sprite[2], sprite[3]),
		}
	end
	return nil
end

local function lookupAsset(name)
	if iconProvider then
		local ok, asset = pcall(iconProvider, name)
		return ok and type(asset) == "table" and asset or nil
	end
	local bundled = bundledAsset(name)
	if bundled then
		return bundled
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

	-- minimized state: a Dynamic Island at the top of the screen.
	-- Compact = icon + title. Hover (or the moment you minimize) = open with the subtitle.
	-- Tap it to restore the window, drag it to move it.
	local orb = create("CanvasGroup", {
		Name = "Island",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 14),
		Size = UDim2.fromOffset(26, 26),
		BackgroundColor3 = Color3.fromRGB(8, 8, 10),
		BorderSizePixel = 0,
		Active = true,
		Visible = false,
		ZIndex = 50,
		Parent = gui,
	}, {
		create("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
		create("Frame", {
			Name = "Edge",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ZIndex = 60,
		}, {
			create("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
			create("UIStroke", {
				Color = Color3.new(1, 1, 1),
				Transparency = 0.9,
				Thickness = 2,
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			}),
		}),
	})
	self.Orb = orb
	self.OrbScale = create("UIScale", { Scale = 1, Parent = orb })
	self.OrbGlyph = create("TextLabel", {
		Name = "Glyph",
		Position = UDim2.fromOffset(10, 8),
		Size = UDim2.fromOffset(22, 22),
		BackgroundTransparency = 1,
		Text = "",
		FontFace = font(Enum.FontWeight.Bold),
		TextSize = 16,
		TextColor3 = Color3.new(1, 1, 1),
		TextTransparency = 1,
		Parent = orb,
	})
	self.OrbIcon = create("ImageLabel", {
		Name = "Icon",
		Position = UDim2.fromOffset(10, 8),
		Size = UDim2.fromOffset(22, 22),
		BackgroundTransparency = 1,
		ImageColor3 = Color3.new(1, 1, 1),
		ImageTransparency = 1,
		Visible = false,
		Parent = orb,
	})
	self.OrbTitle = create("TextLabel", {
		Name = "Title",
		Position = UDim2.fromOffset(40, 11),
		Size = UDim2.fromOffset(0, 16),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		Text = self.Title,
		FontFace = font(Enum.FontWeight.SemiBold),
		TextSize = 13,
		TextColor3 = Color3.new(1, 1, 1),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTransparency = 1,
		Parent = orb,
	})
	self.OrbSub = create("TextLabel", {
		Name = "Subtitle",
		Position = UDim2.fromOffset(40, 31),
		Size = UDim2.fromOffset(0, 14),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		Text = self.Subtitle ~= "" and self.Subtitle or "Tap to open",
		FontFace = font(Enum.FontWeight.Regular),
		TextSize = 11,
		TextColor3 = Color3.fromRGB(165, 165, 172),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTransparency = 1,
		Parent = orb,
	})
	self.OrbArrow = create("ImageLabel", {
		Name = "Arrow",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 11),
		Size = UDim2.fromOffset(16, 16),
		BackgroundTransparency = 1,
		ImageColor3 = Color3.new(1, 1, 1),
		ImageTransparency = 1,
		Parent = orb,
	})
	loadIcon(self.OrbArrow, "arrow-up-right")
	self:SetOrbIcon(config.OrbIcon)
	if config.Icon ~= nil then
		self:SetIcon(config.Icon)
	end

	-- tap restores the window, drag moves the island (it never leaves the screen)
	local islandPressing, islandMoved = false, false
	local islandPressPos, islandStartPosition
	orb.InputBegan:Connect(function(input)
		if isPointer(input) then
			islandPressing = true
			islandMoved = false
			islandPressPos = input.Position
			islandStartPosition = orb.Position
			play(self.OrbScale, Sp.Snappy, { Scale = 0.95 })
		end
	end)
	orb.MouseEnter:Connect(function()
		self._hover = true
		if not self.Visible and self._islandState == "compact" then
			self:_setIsland("open")
		end
	end)
	orb.MouseLeave:Connect(function()
		self._hover = false
		if not self.Visible and self._islandState == "open" then
			self:_setIsland("compact")
		end
	end)
	bind(self, UserInputService.InputChanged, function(input)
		if islandPressing and isMove(input) then
			local delta = input.Position - islandPressPos
			if not islandMoved and delta.Magnitude < 6 then
				return
			end
			islandMoved = true
			local vp = gui.AbsoluteSize
			local size = orb.AbsoluteSize
			local cx = islandStartPosition.X.Scale * vp.X + islandStartPosition.X.Offset + delta.X
			local cy = islandStartPosition.Y.Scale * vp.Y + islandStartPosition.Y.Offset + delta.Y
			cx = math.clamp(cx, size.X / 2 + 4, math.max(size.X / 2 + 4, vp.X - size.X / 2 - 4))
			cy = math.clamp(cy, 4, math.max(4, vp.Y - size.Y - 4))
			orb.Position = UDim2.fromOffset(cx, cy)
		end
	end)
	bind(self, UserInputService.InputEnded, function(input)
		if islandPressing and isPointer(input) then
			islandPressing = false
			if not islandMoved and not self.Visible then
				self:Show()
			else
				play(self.OrbScale, Sp.Snappy, { Scale = 1 })
			end
		end
	end)

	-- -- window drag: 1:1 with the pointer, always keeps the title bar reachable,
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

-- icon of the minimized Dynamic Island (and of the window, unless SetIcon was used):
--   a Lucide icon name, an image id ("rbxassetid://..."), a letter / emoji, or nil (first letter of the title)
function Window:SetOrbIcon(icon)
	self.OrbIconValue = icon
	local letter = string.upper(string.sub(self.Title, 1, 1))
	local kind = iconKind(icon)
	if kind == "image" then
		self.OrbGlyph.Text = ""
		self.OrbIcon.Visible = true
		loadIcon(self.OrbIcon, icon)
	elseif kind == "lucide" then
		-- the first letter shows until the icon is ready (or if it cannot be found)
		self.OrbGlyph.Text = letter
		self.OrbIcon.Visible = false
		loadIcon(self.OrbIcon, icon, function(found)
			if self.Destroyed or self.OrbIconValue ~= icon then
				return
			end
			self.OrbIcon.Visible = found
			self.OrbGlyph.Text = found and "" or letter
		end)
	else
		iconRequests[self.OrbIcon] = nil
		self.OrbIcon.Visible = false
		self.OrbIcon.Image = ""
		self.OrbGlyph.Text = (type(icon) == "string" and icon ~= "") and icon or letter
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
	self:_islandRefresh()
end

function Window:SetSubtitle(text)
	self.Subtitle = tostring(text or "")
	self.SubtitleLabel.Text = self.Subtitle
	self.SubtitleLabel.Visible = self.Subtitle ~= ""
	self:_islandRefresh()
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

local ISLAND_H, ISLAND_H_OPEN = 38, 58

local measureCache = {}
local function measure(text, size, weight)
	local key = text .. "|" .. size .. "|" .. tostring(weight)
	if measureCache[key] then
		return measureCache[key]
	end
	local width
	pcall(function()
		local params = Instance.new("GetTextBoundsParams")
		params.Text = text
		params.Font = font(weight)
		params.Size = size
		params.Width = 1000
		width = TextService:GetTextBoundsAsync(params).X
		params:Destroy()
	end)
	width = width or (#text * size * 0.58)
	measureCache[key] = width
	return width
end

-- widths of the island when compact (icon + title) and open (+ subtitle)
function Window:_islandMetrics()
	local titleW = measure(self.Title, 13, Enum.FontWeight.SemiBold)
	local subW = measure(self.OrbSub.Text, 11, Enum.FontWeight.Regular)
	local compact = math.clamp(math.ceil(10 + 22 + 8 + titleW + 18), 100, 260)
	local open = math.clamp(math.ceil(10 + 22 + 8 + math.max(titleW, subW) + 18 + 28), compact + 40, 360)
	return compact, open
end

-- where the window shrinks to / grows from: the middle of the compact island
function Window:_islandTarget()
	local p = self.Orb.Position
	return UDim2.new(p.X.Scale, p.X.Offset, p.Y.Scale, p.Y.Offset + ISLAND_H / 2)
end

-- the island starts as a small dot and morphs into the pill
function Window:_islandAppear()
	if self._islandState == nil or self._islandState == "dot" then
		apply(self.Orb, { Size = UDim2.fromOffset(26, 26), Visible = true })
		apply(self.OrbGlyph, { TextTransparency = 1 })
		apply(self.OrbIcon, { ImageTransparency = 1 })
		apply(self.OrbTitle, { TextTransparency = 1 })
		apply(self.OrbSub, { TextTransparency = 1 })
		apply(self.OrbArrow, { ImageTransparency = 1 })
		self._islandState = "dot"
	end
end

-- "dot" (hidden), "compact" or "open"
function Window:_setIsland(state)
	if self.Destroyed then
		return
	end
	local orb = self.Orb
	local compactW, openW = self:_islandMetrics()
	self._islandState = state
	local hiddenAll = state == "dot" and 1 or 0
	local hiddenOpen = state == "open" and 0 or 1
	play(self.OrbGlyph, Sp.Fade, { TextTransparency = hiddenAll })
	play(self.OrbIcon, Sp.Fade, { ImageTransparency = hiddenAll })
	play(self.OrbTitle, Sp.Fade, { TextTransparency = hiddenAll })
	play(self.OrbSub, Sp.Fade, { TextTransparency = hiddenOpen })
	play(self.OrbArrow, Sp.Fade, { ImageTransparency = hiddenOpen == 0 and 0.15 or 1 })
	if state == "dot" then
		play(orb, Sp.Close, { Size = UDim2.fromOffset(26, 26) }, function()
			if self._islandState == "dot" then
				orb.Visible = false
			end
		end)
	elseif state == "compact" then
		orb.Visible = true
		play(orb, Sp.Island, { Size = UDim2.fromOffset(compactW, ISLAND_H) })
	else
		orb.Visible = true
		play(orb, Sp.Island, { Size = UDim2.fromOffset(openW, ISLAND_H_OPEN) })
	end
end

-- keeps the island's texts and size in sync with Title / Subtitle
function Window:_islandRefresh()
	self.OrbTitle.Text = self.Title
	self.OrbSub.Text = self.Subtitle ~= "" and self.Subtitle or "Tap to open"
	if self._islandState and self._islandState ~= "dot" then
		self:_setIsland(self._islandState)
	end
end

-- un-minimize: the window grows back out of the island
function Window:Show()
	if self.Visible or self.Destroyed then
		return
	end
	self.Visible = true
	local holder = self.Holder
	if not holder.Visible then
		apply(holder, { Position = self:_islandTarget(), Visible = true })
		apply(self.Scale, { Scale = 0.14 })
		apply(self.Canvas, { GroupTransparency = 1 })
	end
	play(holder, Sp.Window, { Position = self._restPosition or UDim2.fromScale(0.5, 0.5) })
	play(self.Scale, Sp.Window, { Scale = 1 })
	play(self.Canvas, Sp.Fade, { GroupTransparency = 0 })
	setShadow(self.Shadow, self.Palette, true, Sp.Fade)
	self._hover = false
	self:_setIsland("dot")
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
	self:_islandAppear()
	play(holder, Sp.Close, { Position = self:_islandTarget() })
	play(self.Scale, Sp.Close, { Scale = 0.14 })
	setShadow(self.Shadow, self.Palette, false, Sp.Fade)
	play(self.Canvas, Sp.Fade, { GroupTransparency = 1 }, function()
		if not self.Visible and not self.Destroyed then
			holder.Visible = false
		end
	end)
	task.delay(0.09, function()
		if not self.Visible and not self.Destroyed then
			self:_setIsland("open")
			task.delay(1.6, function()
				if not self.Visible and not self.Destroyed and self._islandState == "open" and not self._hover then
					self:_setIsland("compact")
				end
			end)
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
