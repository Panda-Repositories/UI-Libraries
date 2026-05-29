--[[
============================================================================
  PandaUI  —  macOS-inspired UI Library for Roblox (Luau)
============================================================================

  A clean, modular, object-oriented UI library with a built-in key system.

  Design language: modern macOS.
    • Rounded corners (UICorner ~6-10px), subtle borders (UIStroke),
      drop shadow, traffic-light window controls, Gotham typography.
    • Dynamic Light / Dark theme engine that tweens every themed property
      via TweenService when toggled.

  Key system / authentication:
    • Config.KeySystem (boolean) gates the whole UI behind a key screen.
    • Authentication tries **V4.3-Cookies** first (the full encrypted /
      Ed25519-pinned HTTP protocol — the lib is fetched and reused).
    • If V4.3-Cookies fails or is unreachable, it falls back to **V2**
      (POST /v2_validation) — but ONLY when Config.Legacy_Compatible == true.
    • Config.Legacy_Compatible defaults to true.

----------------------------------------------------------------------------
  USAGE
----------------------------------------------------------------------------

    local PandaUI = loadstring(game:HttpGet("http://localhost:4022/ui/lib"))()

    local Window = PandaUI:CreateWindow({
        Title    = "Panda Hub",
        SubTitle = "v1.0",
        Theme    = "Dark",                 -- "Dark" | "Light"

        -- Key system --------------------------------------------------------
        KeySystem         = true,
        Legacy_Compatible = true,          -- default true → enables V2 fallback
        ServiceId         = "pandadevkit",

        -- Endpoints (defaults shown are production; override for local tests) -
        CookiesLibUrl  = "http://localhost:4022/cv4/lib",
        CookiesBaseUrl = "http://localhost:4022",   -- nil in prod
        CookiesHost    = "localhost",               -- nil in prod
        V2Url          = "http://localhost:3000/v2_validation",

        OnAuthSuccess = function(info) print("Authed via", info.source) end,
        OnAuthFail    = function(info) warn("Auth failed:", info.error) end,
    })

    local main = Window:CreateTab("Main")
    main:CreateLabel("Welcome to Panda Hub")
    main:CreateButton({ Text = "Click Me", Callback = function() print("hi") end })
    main:CreateInput({ Placeholder = "Type here", Callback = function(txt) print(txt) end })

    local settings = Window:CreateTab("Settings")
    settings:CreateButton({ Text = "Toggle Theme", Callback = function() Window:ToggleTheme() end })

============================================================================
]]

--======================================================================--
--  SERVICES
--======================================================================--

local Players          = game:GetService("Players")
local TweenService     = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local HttpService      = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer

--======================================================================--
--  THEME DEFINITIONS
--  Every UI element registers the theme keys it cares about; toggling the
--  theme tweens all of them at once (see Window:_register / :_applyTheme).
--======================================================================--

local Themes = {
	Dark = {
		Accent       = Color3.fromRGB(10, 132, 255),   -- macOS system blue
		Background   = Color3.fromRGB(28, 28, 30),     -- window body
		Sidebar      = Color3.fromRGB(22, 22, 24),     -- tab rail
		Element      = Color3.fromRGB(44, 44, 46),     -- buttons / inputs
		ElementHover = Color3.fromRGB(58, 58, 60),
		Input        = Color3.fromRGB(38, 38, 41),
		Stroke       = Color3.fromRGB(64, 64, 68),
		Text         = Color3.fromRGB(245, 245, 247),
		SubText      = Color3.fromRGB(150, 150, 157),
		Placeholder  = Color3.fromRGB(118, 118, 124),
	},
	Light = {
		Accent       = Color3.fromRGB(0, 122, 255),
		Background   = Color3.fromRGB(243, 243, 245),   -- window body + content
		Sidebar      = Color3.fromRGB(229, 229, 234),   -- two-tone macOS sidebar
		Element      = Color3.fromRGB(255, 255, 255),
		ElementHover = Color3.fromRGB(237, 237, 242),
		Input        = Color3.fromRGB(255, 255, 255),
		Stroke       = Color3.fromRGB(206, 206, 212),
		Text         = Color3.fromRGB(28, 28, 30),
		SubText      = Color3.fromRGB(116, 116, 124),
		Placeholder  = Color3.fromRGB(166, 166, 174),
	},
}

local TWEEN_TIME  = 0.22                       -- theme transition duration
local TWEEN_STYLE = Enum.EasingStyle.Quad
local TWEEN_DIR   = Enum.EasingDirection.Out
local WHITE       = Color3.fromRGB(255, 255, 255)

--======================================================================--
--  LOW-LEVEL HELPERS
--======================================================================--

-- Instance factory. Sets Parent last so property writes never trigger
-- premature replication / layout passes.
local function create(className, props)
	local inst = Instance.new(className)
	local parent = nil
	if props then
		for k, v in pairs(props) do
			if k == "Parent" then
				parent = v
			else
				inst[k] = v
			end
		end
	end
	if parent then inst.Parent = parent end
	return inst
end

local function corner(inst, radius)
	return create("UICorner", { Parent = inst, CornerRadius = UDim.new(0, radius or 8) })
end

local function stroke(inst, thickness, transparency)
	return create("UIStroke", {
		Parent           = inst,
		Thickness        = thickness or 1,
		Transparency     = transparency or 0,
		ApplyStrokeMode  = Enum.ApplyStrokeMode.Border,
	})
end

local function padding(inst, all)
	local d = UDim.new(0, all or 10)
	return create("UIPadding", {
		Parent        = inst,
		PaddingLeft   = d,
		PaddingRight  = d,
		PaddingTop    = d,
		PaddingBottom = d,
	})
end

local function tween(inst, props, time, style, dir)
	local info = TweenInfo.new(time or TWEEN_TIME, style or TWEEN_STYLE, dir or TWEEN_DIR)
	local t = TweenService:Create(inst, info, props)
	t:Play()
	return t
end

--======================================================================--
--  STEALTH HELPERS  (shrink the client-side anti-cheat scan surface)
--
--  Game anti-cheats are LocalScripts that scan the client DataModel for
--  foreign instances. We (1) give the ScreenGui a random per-session name,
--  (2) parent it into a protected/hidden container so CoreGui scans miss it,
--  and (3) keep the relaunch handle in the executor global env (getgenv),
--  which game scripts cannot read — so nothing scannable is left behind.
--======================================================================--

local _genv = (getgenv and getgenv()) or _G
local REG_KEY = "_pui_active"

local function randomName(len)
	local chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
	local t = {}
	for i = 1, (len or 8) do
		local n = math.random(1, #chars)
		t[i] = string.sub(chars, n, n)
	end
	return table.concat(t)
end

local function mountProtected(gui)
	-- gethui() returns a hidden, scan-resistant container in most executors.
	local hui = gethui and gethui()
	if hui and pcall(function() gui.Parent = hui end) and gui.Parent then return end
	-- Synapse-style: parent to CoreGui then protect it from scans.
	local cg = game:GetService("CoreGui")
	if pcall(function() gui.Parent = cg end) and gui.Parent then
		if syn and syn.protect_gui then pcall(syn.protect_gui, gui) end
		if protect_gui then pcall(protect_gui, gui) end
		if protectgui  then pcall(protectgui, gui) end
		return
	end
	local pg = LocalPlayer and LocalPlayer:FindFirstChild("PlayerGui")
	if pg then gui.Parent = pg end
end

--======================================================================--
--  HWID  (used for the V2 fallback when the Cookies lib never loaded)
--  Mirrors the Cookies / V2 client derivation chain.
--======================================================================--

local _cachedHWID
local function getHWID()
	if _cachedHWID then return _cachedHWID end

	local hwid
	if gethwid then
		local ok, r = pcall(gethwid)
		if ok and r and r ~= "" then hwid = r end
	end
	if not hwid and LocalPlayer then
		local exec = ""
		if identifyexecutor then
			local ok, r = pcall(identifyexecutor)
			if ok and r then exec = r end
		end
		hwid = "P_" .. tostring(LocalPlayer.UserId) .. "_" .. (exec ~= "" and exec or "unknown")
	end
	if not hwid then
		local ok, r = pcall(function()
			return game:GetService("RbxAnalyticsService"):GetClientId()
		end)
		if ok and r then hwid = r end
	end
	if not hwid and LocalPlayer then
		hwid = "PANDA_" .. tostring(LocalPlayer.UserId)
	end

	_cachedHWID = hwid or "unknown_hwid"
	return _cachedHWID
end

--======================================================================--
--  HTTP  (executor request-function with HttpService fallbacks)
--======================================================================--

local function resolveRequest()
	return (syn and syn.request)
		or (http and http.request)
		or (fluxus and fluxus.request)
		or request
		or http_request
		or httprequest
end

-- GET that returns a raw body string (used to fetch the Cookies lib source).
local function httpGet(url)
	local req = resolveRequest()
	if req then
		local ok, resp = pcall(req, { Url = url, Method = "GET", Headers = { ["Accept"] = "text/plain" } })
		if ok and resp then
			local body = resp.Body or resp.body
			if body and #body > 0 then return body end
		end
	end
	local ok, body = pcall(function() return game:HttpGet(url) end)
	if ok and body and #body > 0 then return body end
	return nil
end

-- POST JSON, returns { Body = string, StatusCode = number } or nil.
local function httpPostJson(url, tbl)
	local bodyStr = HttpService:JSONEncode(tbl)
	local req = resolveRequest()
	if req then
		local ok, resp = pcall(req, {
			Url     = url,
			Method  = "POST",
			Headers = { ["Content-Type"] = "application/json" },
			Body    = bodyStr,
		})
		if ok and resp then
			return {
				Body       = resp.Body       or resp.body       or "",
				StatusCode = resp.StatusCode or resp.statusCode or 0,
			}
		end
	end
	local ok, resp = pcall(function()
		return HttpService:RequestAsync({
			Url     = url,
			Method  = "POST",
			Headers = { ["Content-Type"] = "application/json" },
			Body    = bodyStr,
		})
	end)
	if ok and resp then
		return { Body = resp.Body, StatusCode = resp.StatusCode }
	end
	return nil
end

--======================================================================--
--  AUTH MODULE
--  Orchestrates: V4.3-Cookies (primary) → V2 (fallback, if legacy on).
--  `state` is a per-window scratch table so a loaded Cookies module and
--  its one-time configure() are reused across retries.
--======================================================================--

local Auth = {}

-- Fetch + load the V4.3-Cookies Lua library from its delivery URL.
function Auth.fetchCookies(url)
	local body = httpGet(url)
	if not body or #body < 100 then return nil end
	local loader = loadstring(body)
	if not loader then return nil end
	local ok, mod = pcall(loader)
	if not ok or type(mod) ~= "table" or type(mod.configure) ~= "function" then
		return nil
	end
	return mod
end

-- Ensure the Cookies module is loaded and configured exactly once.
function Auth.ensureCookies(cfg, state)
	if state.cookies then return state.cookies end
	local mod = Auth.fetchCookies(cfg.CookiesLibUrl)
	if not mod then return nil, "Cookies library unreachable" end
	local okCfg = pcall(function()
		mod.configure({
			serviceId     = cfg.ServiceId,
			debug         = cfg.Debug == true,
			kickOnDetect  = false,
			openDashboard = false,
			validationTimeout = cfg.ValidationTimeout or 600,
			baseUrl       = cfg.CookiesBaseUrl,   -- nil → prod default inside lib
			canonicalHost = cfg.CookiesHost,      -- nil → prod default inside lib
		})
	end)
	if not okCfg then return nil, "Cookies configure failed" end
	state.cookies = mod
	return mod
end

-- Primary path. Returns a normalized result table.
function Auth.viaCookies(cfg, key, state)
	local mod, err = Auth.ensureCookies(cfg, state)
	if not mod then
		return { success = false, error = err, reachable = false }
	end
	local ok, res = pcall(function() return mod.validate(key) end)
	if not ok then
		return { success = false, error = "Cookies validation error", reachable = false }
	end
	if res and res.success then
		return {
			success   = true,
			source    = "V4.3-Cookies",
			isPremium = res.isPremium,
			expiresAt = res.expiresAt,
			sessionId = res.sessionId,
			getKeyUrl = res.getKeyUrl,
		}
	end
	return { success = false, error = (res and res.error) or "Invalid key", reachable = true }
end

-- Fallback path. POST /v2_validation → { Status, Is_Premium, Expired_At, Note }.
function Auth.viaV2(cfg, key, hwid)
	if not cfg.V2Url or cfg.V2Url == "" then
		return { success = false, error = "V2 endpoint not configured" }
	end
	local resp = httpPostJson(cfg.V2Url, {
		serviceid = cfg.ServiceId,
		hwid      = hwid,
		key       = key,
	})
	if not resp then
		return { success = false, error = "V2 endpoint unreachable" }
	end
	local ok, data = pcall(function() return HttpService:JSONDecode(resp.Body) end)
	if not ok or type(data) ~= "table" then
		return { success = false, error = "V2 returned malformed response" }
	end
	if data.Status == "Authenticate" then
		return {
			success   = true,
			source    = "V2",
			isPremium = data.Is_Premium == true,
			expiresAt = data.Expired_At,
			note      = data.Note,
		}
	end
	return { success = false, error = data.Note or "Invalid key" }
end

-- The orchestrator the UI calls. Cookies first; V2 only when legacy enabled.
function Auth.run(cfg, key, state)
	local primary = Auth.viaCookies(cfg, key, state)
	if primary.success then return primary end

	if cfg.Legacy_Compatible then
		local hwid = getHWID()
		if state.cookies and state.cookies.getHWIDInfo then
			local okH, info = pcall(state.cookies.getHWIDInfo)
			if okH and info and info.hwid then hwid = info.hwid end
		end
		local fallback = Auth.viaV2(cfg, key, hwid)
		if fallback.success then return fallback end
		return {
			success = false,
			error   = string.format("Cookies: %s | V2: %s",
				primary.error or "?", fallback.error or "?"),
		}
	end

	return primary
end

-- Best-effort GetKey URL (and copy to clipboard). Tries the Cookies lib
-- first (HWID-accurate), then a constructed fallback.
function Auth.copyGetKeyUrl(cfg, state)
	local url
	local mod = Auth.ensureCookies(cfg, state)
	if mod and mod.copyGetKeyUrl then
		local ok, info = pcall(mod.copyGetKeyUrl)
		if ok and info and info.url then url = info.url end
	end
	if not url then
		local base = cfg.GetKeyBase or "https://ads.pandauth.com/getkey"
		url = string.format("%s/%s?hwid=%s", base, tostring(cfg.ServiceId), getHWID())
		local clip = setclipboard or toclipboard
		if clip then pcall(clip, url) end
	end
	return url
end

--======================================================================--
--  TAB CLASS
--  A Tab owns a sidebar button and a scrolling content page. Components
--  (Label / Button / Input) are appended to the page via a UIListLayout.
--======================================================================--

local Tab = {}
Tab.__index = Tab

function Tab:CreateLabel(opts)
	if type(opts) == "string" then opts = { Text = opts } end
	opts = opts or {}
	local w = self._window

	local label = create("TextLabel", {
		Parent                 = self._page,
		BackgroundTransparency = 1,
		Size                   = UDim2.new(1, 0, 0, 0),
		AutomaticSize          = Enum.AutomaticSize.Y,   -- grows to fit wrapped text
		Font                   = Enum.Font.Gotham,
		TextSize               = opts.TextSize or 14,
		Text                   = opts.Text or "",
		TextWrapped            = true,
		TextXAlignment         = Enum.TextXAlignment.Left,
		TextYAlignment         = Enum.TextYAlignment.Top,
	})
	w:_register(label, "TextColor3", opts.Muted and "SubText" or "Text")

	local api = {}
	function api:Set(text) label.Text = text end
	function api:Get() return label.Text end
	return api
end

function Tab:CreateButton(opts)
	opts = opts or {}
	local w = self._window

	local btn = create("TextButton", {
		Parent          = self._page,
		Size            = UDim2.new(1, 0, 0, 38),
		AutoButtonColor = false,
		BorderSizePixel = 0,
		Font            = Enum.Font.GothamMedium,
		TextSize        = 14,
		Text            = opts.Text or "Button",
	})
	corner(btn, 8)
	local st = stroke(btn)
	w:_register(btn, "BackgroundColor3", "Element")
	w:_register(btn, "TextColor3", "Text")
	w:_register(st,  "Color", "Stroke")

	-- Hover: subtle color shift.
	btn.MouseEnter:Connect(function()
		tween(btn, { BackgroundColor3 = w._theme.ElementHover }, 0.15)
	end)
	btn.MouseLeave:Connect(function()
		tween(btn, { BackgroundColor3 = w._theme.Element }, 0.15)
	end)

	-- Click: quick "press" bounce, then run the callback off-thread.
	btn.MouseButton1Click:Connect(function()
		tween(btn, { Size = UDim2.new(1, -8, 0, 36) }, 0.08)
		task.delay(0.08, function()
			tween(btn, { Size = UDim2.new(1, 0, 0, 38) }, 0.10)
		end)
		if opts.Callback then task.spawn(opts.Callback) end
	end)

	local api = {}
	function api:SetText(t) btn.Text = t end
	return api
end

function Tab:CreateInput(opts)
	opts = opts or {}
	local w = self._window

	local box = create("TextBox", {
		Parent           = self._page,
		Size             = UDim2.new(1, 0, 0, 38),
		BorderSizePixel  = 0,
		Font             = Enum.Font.Gotham,
		TextSize         = 14,
		Text             = opts.Default or "",
		PlaceholderText  = opts.Placeholder or "",
		ClearTextOnFocus = opts.ClearOnFocus == true,
		TextXAlignment   = Enum.TextXAlignment.Left,
		TextYAlignment   = Enum.TextYAlignment.Center,
		TextTruncate     = Enum.TextTruncate.AtEnd,
	})
	corner(box, 8)
	padding(box, 10)              -- left/right text inset
	local st = stroke(box)
	w:_register(box, "BackgroundColor3", "Input")
	w:_register(box, "TextColor3", "Text")
	w:_register(box, "PlaceholderColor3", "Placeholder")
	w:_register(st,  "Color", "Stroke")

	-- Focus visuals: accent-colored, thicker border.
	box.Focused:Connect(function()
		tween(st, { Color = w._theme.Accent, Thickness = 1.6 }, 0.15)
	end)
	box.FocusLost:Connect(function(enterPressed)
		tween(st, { Color = w._theme.Stroke, Thickness = 1 }, 0.15)
		if opts.Callback then task.spawn(opts.Callback, box.Text, enterPressed) end
	end)

	local api = {}
	function api:Get() return box.Text end
	function api:Set(t) box.Text = t end
	return api
end

--======================================================================--
--  WINDOW CLASS
--======================================================================--

local Window = {}
Window.__index = Window

-- Register an instance property against a theme key. Applies the current
-- color immediately and remembers it so :ToggleTheme can tween it later.
function Window:_register(inst, prop, themeKey)
	table.insert(self._themeItems, { inst = inst, prop = prop, key = themeKey })
	inst[prop] = self._theme[themeKey]
end

function Window:_applyTheme()
	for _, item in ipairs(self._themeItems) do
		tween(item.inst, { [item.prop] = self._theme[item.key] })
	end
	-- Re-assert the active tab highlight (its colors are set imperatively,
	-- not through the registry, so a plain theme tween would wash them out).
	if self._active then self:_selectTab(self._active) end
end

function Window:SetTheme(name)
	if name ~= "Dark" and name ~= "Light" then return end
	self._themeName = name
	self._theme = Themes[name]
	self:_applyTheme()
end

function Window:ToggleTheme()
	self:SetTheme(self._themeName == "Dark" and "Light" or "Dark")
end

function Window:_selectTab(tab)
	for _, t in ipairs(self._tabs) do
		local selected = (t == tab)
		if selected then
			-- Slide the incoming page up into place for a soft transition.
			t._page.Visible  = true
			t._page.Position = UDim2.fromOffset(0, 12)
			tween(t._page, { Position = UDim2.fromOffset(0, 0) }, 0.2)
		else
			t._page.Visible = false
		end
		tween(t._button, {
			BackgroundColor3       = self._theme.Accent,
			BackgroundTransparency = selected and 0 or 1,
			TextColor3             = selected and WHITE or self._theme.SubText,
		}, 0.15)
	end
	self._active = tab
end

-- Pop-in open animation (scale + shadow fade).
function Window:_playOpen()
	local sMain   = create("UIScale", { Parent = self._main,   Scale = 0.92 })
	local sShadow = create("UIScale", { Parent = self._shadow, Scale = 0.92 })
	self._shadow.ImageTransparency = 1
	tween(sMain,   { Scale = 1 }, 0.34, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	tween(sShadow, { Scale = 1 }, 0.34, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	tween(self._shadow, { ImageTransparency = 0.55 }, 0.34)
end

function Window:CreateTab(name)
	-- Sidebar button.
	local btn = create("TextButton", {
		Parent                 = self._sidebar,
		Size                   = UDim2.new(1, 0, 0, 34),
		AutoButtonColor        = false,
		BackgroundTransparency = 1,
		BorderSizePixel        = 0,
		Font                   = Enum.Font.GothamMedium,
		TextSize               = 14,
		Text                   = "  " .. tostring(name),
		TextXAlignment         = Enum.TextXAlignment.Left,
	})
	corner(btn, 6)
	self:_register(btn, "TextColor3", "SubText")

	-- Content page (one scrolling frame per tab).
	local page = create("ScrollingFrame", {
		Parent                 = self._content,
		Size                   = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel        = 0,
		Visible                = false,
		CanvasSize             = UDim2.new(),
		AutomaticCanvasSize    = Enum.AutomaticSize.Y,
		ScrollBarThickness     = 4,
		ScrollBarImageTransparency = 0.4,
	})
	create("UIListLayout", {
		Parent   = page,
		Padding  = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
	padding(page, 12)

	local tab = setmetatable({ _window = self, _button = btn, _page = page }, Tab)

	btn.MouseButton1Click:Connect(function() self:_selectTab(tab) end)
	btn.MouseEnter:Connect(function()
		if self._active ~= tab then tween(btn, { BackgroundTransparency = 0.88 }, 0.12) end
	end)
	btn.MouseLeave:Connect(function()
		if self._active ~= tab then tween(btn, { BackgroundTransparency = 1 }, 0.12) end
	end)

	table.insert(self._tabs, tab)
	if #self._tabs == 1 then self:_selectTab(tab) end
	return tab
end

function Window:Destroy()
	if self._destroying then return end
	self._destroying = true
	if not self._gui then return end

	for _, c in ipairs(self._conns) do pcall(function() c:Disconnect() end) end
	if _genv[REG_KEY] == self._hardDestroy then _genv[REG_KEY] = nil end

	-- Scale + fade out, then remove.
	local sMain = self._main:FindFirstChildOfClass("UIScale") or create("UIScale", { Parent = self._main, Scale = 1 })
	tween(sMain, { Scale = 0.9 }, 0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	if self._shadow then
		local sShadow = self._shadow:FindFirstChildOfClass("UIScale") or create("UIScale", { Parent = self._shadow, Scale = 1 })
		tween(sShadow, { Scale = 0.9 }, 0.2)
		tween(self._shadow, { ImageTransparency = 1 }, 0.2)
	end
	tween(self._main, { BackgroundTransparency = 1 }, 0.2)

	task.delay(0.22, function()
		if self._gui then self._gui:Destroy() end
	end)
end

-- Track connections so relaunch / Destroy doesn't leak global input hooks.
function Window:_bind(conn)
	table.insert(self._conns, conn)
	return conn
end

-- Smooth dragging via InputBegan/InputChanged (mouse + touch).
function Window:_enableDrag(handle, target)
	local dragging, dragInput, dragStart, startPos = false, nil, nil, nil

	self:_bind(handle.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging  = true
			dragStart = input.Position
			startPos  = target.Position
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then dragging = false end
			end)
		end
	end))

	self:_bind(handle.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch then
			dragInput = input
		end
	end))

	self:_bind(UserInputService.InputChanged:Connect(function(input)
		if dragging and input == dragInput then
			local delta = input.Position - dragStart
			target.Position = UDim2.new(
				startPos.X.Scale, startPos.X.Offset + delta.X,
				startPos.Y.Scale, startPos.Y.Offset + delta.Y
			)
		end
	end))
end

-- macOS traffic-light controls (close / minimize / decorative).
function Window:_buildTrafficLights(parent)
	local holder = create("Frame", {
		Parent                 = parent,
		BackgroundTransparency = 1,
		Position               = UDim2.fromOffset(14, 0),
		Size                   = UDim2.new(0, 60, 1, 0),
	})
	create("UIListLayout", {
		Parent           = holder,
		FillDirection    = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding          = UDim.new(0, 8),
		SortOrder        = Enum.SortOrder.LayoutOrder,
	})

	local function dot(color, order)
		local d = create("TextButton", {
			Parent           = holder,
			Size             = UDim2.fromOffset(12, 12),
			BackgroundColor3 = color,
			AutoButtonColor  = false,
			BorderSizePixel  = 0,
			Text             = "",
			LayoutOrder      = order,
		})
		corner(d, 6)
		return d
	end

	local closeDot = dot(Color3.fromRGB(255, 95, 86), 1)
	local minDot   = dot(Color3.fromRGB(255, 189, 46), 2)
	dot(Color3.fromRGB(39, 201, 63), 3)   -- green: decorative

	closeDot.MouseButton1Click:Connect(function() self:Destroy() end)
	minDot.MouseButton1Click:Connect(function() self:_toggleMinimize() end)
end

function Window:_toggleMinimize()
	self._minimized = not self._minimized
	self._body.Visible = not self._minimized
	tween(self._main, {
		Size = self._minimized
			and UDim2.fromOffset(self._size.X.Offset, 40)
			or  self._size,
	}, 0.2)
end

--======================================================================--
--  KEY SYSTEM SCREEN
--  Overlays the window body until authentication succeeds, then fades out.
--======================================================================--

function Window:_buildKeyPanel(cfg)
	local panel = create("Frame", {
		Parent          = self._body,
		Size            = UDim2.fromScale(1, 1),
		BorderSizePixel = 0,
		ZIndex          = 50,
	})
	self:_register(panel, "BackgroundColor3", "Background")

	local card = create("Frame", {
		Parent          = panel,
		AnchorPoint     = Vector2.new(0.5, 0.5),
		Position        = UDim2.fromScale(0.5, 0.5),
		Size            = UDim2.fromOffset(360, 226),
		BorderSizePixel = 0,
		ZIndex          = 51,
	})
	corner(card, 10)
	local cst = stroke(card)
	self:_register(card, "BackgroundColor3", "Element")
	self:_register(cst,  "Color", "Stroke")
	padding(card, 18)
	create("UIListLayout", {
		Parent    = card,
		Padding   = UDim.new(0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
	})

	local title = create("TextLabel", {
		Parent                 = card,
		BackgroundTransparency = 1,
		Size                   = UDim2.new(1, 0, 0, 22),
		Font                   = Enum.Font.GothamBold,
		TextSize               = 17,
		Text                   = "Key Required",
		TextXAlignment         = Enum.TextXAlignment.Left,
		ZIndex                 = 52,
		LayoutOrder            = 1,
	})
	self:_register(title, "TextColor3", "Text")

	local sub = create("TextLabel", {
		Parent                 = card,
		BackgroundTransparency = 1,
		Size                   = UDim2.new(1, 0, 0, 30),
		Font                   = Enum.Font.Gotham,
		TextSize               = 12,
		Text                   = "Paste your key to continue, or press Get Key to copy the URL.",
		TextWrapped            = true,
		TextXAlignment         = Enum.TextXAlignment.Left,
		TextYAlignment         = Enum.TextYAlignment.Top,
		ZIndex                 = 52,
		LayoutOrder            = 2,
	})
	self:_register(sub, "TextColor3", "SubText")

	local input = create("TextBox", {
		Parent           = card,
		Size             = UDim2.new(1, 0, 0, 38),
		BorderSizePixel  = 0,
		Font             = Enum.Font.Code,
		TextSize         = 15,
		Text             = "",
		PlaceholderText  = "PANDA-XXXX-XXXX-XXXX",
		ClearTextOnFocus = false,
		TextXAlignment   = Enum.TextXAlignment.Left,
		ZIndex           = 52,
		LayoutOrder      = 3,
	})
	corner(input, 8)
	padding(input, 10)
	local ist = stroke(input)
	self:_register(input, "BackgroundColor3", "Input")
	self:_register(input, "TextColor3", "Text")
	self:_register(input, "PlaceholderColor3", "Placeholder")
	self:_register(ist,   "Color", "Stroke")
	input.Focused:Connect(function()
		tween(ist, { Color = self._theme.Accent, Thickness = 1.6 }, 0.15)
	end)
	input.FocusLost:Connect(function()
		tween(ist, { Color = self._theme.Stroke, Thickness = 1 }, 0.15)
	end)

	-- Prefill a previously saved key (Cookies persists keys to disk).
	task.spawn(function()
		local mod = Auth.ensureCookies(cfg, self._authState)
		if mod and mod.loadSavedKey then
			local ok, saved = pcall(mod.loadSavedKey)
			if ok and saved and saved ~= "" then input.Text = saved end
		end
	end)

	-- Button row.
	local row = create("Frame", {
		Parent                 = card,
		BackgroundTransparency = 1,
		Size                   = UDim2.new(1, 0, 0, 40),
		ZIndex                 = 52,
		LayoutOrder            = 4,
	})
	create("UIListLayout", {
		Parent        = row,
		FillDirection = Enum.FillDirection.Horizontal,
		Padding       = UDim.new(0, 10),
		SortOrder     = Enum.SortOrder.LayoutOrder,
	})

	local getKey = create("TextButton", {
		Parent          = row,
		Size            = UDim2.new(0.5, -5, 1, 0),
		AutoButtonColor = false,
		BorderSizePixel = 0,
		Font            = Enum.Font.GothamMedium,
		TextSize        = 14,
		Text            = "Get Key",
		ZIndex          = 52,
		LayoutOrder     = 1,
	})
	corner(getKey, 8)
	local gst = stroke(getKey)
	self:_register(getKey, "BackgroundColor3", "Element")
	self:_register(getKey, "TextColor3", "Text")
	self:_register(gst,    "Color", "Stroke")
	getKey.MouseEnter:Connect(function() tween(getKey, { BackgroundColor3 = self._theme.ElementHover }, 0.15) end)
	getKey.MouseLeave:Connect(function() tween(getKey, { BackgroundColor3 = self._theme.Element }, 0.15) end)

	local submit = create("TextButton", {
		Parent           = row,
		Size             = UDim2.new(0.5, -5, 1, 0),
		AutoButtonColor  = false,
		BorderSizePixel  = 0,
		BackgroundColor3 = self._theme.Accent,
		TextColor3       = WHITE,
		Font             = Enum.Font.GothamBold,
		TextSize         = 14,
		Text             = "Authenticate",
		ZIndex           = 52,
		LayoutOrder      = 2,
	})
	corner(submit, 8)

	local status = create("TextLabel", {
		Parent                 = card,
		BackgroundTransparency = 1,
		Size                   = UDim2.new(1, 0, 0, 18),
		Font                   = Enum.Font.Gotham,
		TextSize               = 12,
		Text                   = "",
		TextXAlignment         = Enum.TextXAlignment.Left,
		ZIndex                 = 52,
		LayoutOrder            = 5,
	})
	self:_register(status, "TextColor3", "SubText")

	-- Get Key → copy URL to clipboard.
	getKey.MouseButton1Click:Connect(function()
		status.Text = "Fetching Get Key URL..."
		task.spawn(function()
			local url = Auth.copyGetKeyUrl(cfg, self._authState)
			status.Text = url and "Get Key URL copied to clipboard." or "Could not build Get Key URL."
		end)
	end)

	-- Authenticate → Cookies first, V2 fallback, then reveal the UI.
	submit.MouseButton1Click:Connect(function()
		if self._authBusy then return end
		self._authBusy = true

		local key = (input.Text or ""):gsub("%s", "")
		if key == "" then
			status.Text = "Please enter a key."
			self._authBusy = false
			return
		end

		status.Text = "Authenticating..."
		tween(submit, { BackgroundColor3 = self._theme.ElementHover }, 0.1)

		task.spawn(function()
			local result = Auth.run(cfg, key, self._authState)

			if result.success then
				status.Text = "Authenticated via " .. result.source .. " — welcome!"
				task.wait(0.45)
				-- Fade the gate away to reveal the tab system underneath.
				tween(panel, { BackgroundTransparency = 1 }, 0.3)
				tween(card,  { Size = UDim2.fromOffset(360, 0) }, 0.3)
				task.wait(0.32)
				panel:Destroy()
				self._authed = true
				if cfg.OnAuthSuccess then task.spawn(cfg.OnAuthSuccess, result) end
			else
				status.Text = "Failed: " .. (result.error or "unknown")
				tween(submit, { BackgroundColor3 = self._theme.Accent }, 0.15)
				self._authBusy = false
				if cfg.OnAuthFail then task.spawn(cfg.OnAuthFail, result) end
			end
		end)
	end)
end

--======================================================================--
--  PUBLIC ENTRY POINT
--======================================================================--

local PandaUI = {}
PandaUI.__index = PandaUI
PandaUI.Version = "1.0.0"

function PandaUI:CreateWindow(cfg)
	cfg = cfg or {}

	-- Legacy_Compatible defaults to true (controls the V2 fallback routing).
	if cfg.Legacy_Compatible == nil then cfg.Legacy_Compatible = true end
	cfg.ServiceId     = cfg.ServiceId     or "YOUR_SERVICE_ID"
	cfg.CookiesLibUrl = cfg.CookiesLibUrl or "https://secure.pandauth.com/cv4/lib"
	cfg.V2Url         = cfg.V2Url         or "https://secure.pandauth.com/v2_validation"

	local self = setmetatable({}, Window)
	self._themeName  = (cfg.Theme == "Light") and "Light" or "Dark"
	self._theme      = Themes[self._themeName]
	self._themeItems = {}
	self._tabs       = {}
	self._conns      = {}
	self._authState  = {}
	self._authed     = not (cfg.KeySystem == true)   -- no gate → already "authed"
	self._cfg        = cfg
	self._size       = cfg.Size or UDim2.fromOffset(560, 380)

	---------------------------------------------------------------- ScreenGui
	-- Relaunch: tear down any previous instance. The handle lives in the
	-- executor global env (getgenv) — invisible to game scripts, so no
	-- scannable name/tag is left in the DataModel.
	local prevCleanup = _genv[REG_KEY]
	if type(prevCleanup) == "function" then pcall(prevCleanup) end

	local gui = create("ScreenGui", {
		Name            = cfg.Name or randomName(8),
		ResetOnSpawn    = false,
		IgnoreGuiInset  = true,
		ZIndexBehavior  = Enum.ZIndexBehavior.Sibling,
		DisplayOrder    = 9999,
	})
	mountProtected(gui)
	self._gui = gui

	-- Hard (immediate) teardown used by relaunch; Destroy() is the animated one.
	self._hardDestroy = function()
		self._destroying = true
		for _, c in ipairs(self._conns) do pcall(function() c:Disconnect() end) end
		if self._gui then pcall(function() self._gui:Destroy() end) end
	end
	_genv[REG_KEY] = self._hardDestroy

	-------------------------------------------------------------- Main window
	-- Soft drop shadow. It is a SIBLING placed *behind* the window (not a child)
	-- so its semi-transparent black never bleeds up through the window's
	-- transparent interior — that bleed is what muddied Light mode. It tracks
	-- the window as it is dragged / minimized.
	local shadow = create("ImageLabel", {
		Parent                 = gui,
		BackgroundTransparency = 1,
		AnchorPoint            = Vector2.new(0.5, 0.5),
		Position               = UDim2.fromScale(0.5, 0.5),
		Size                   = UDim2.new(0, self._size.X.Offset + 48, 0, self._size.Y.Offset + 48),
		ZIndex                 = 0,
		Image                  = "rbxassetid://6014261993",
		ImageColor3            = Color3.fromRGB(0, 0, 0),
		ImageTransparency      = 0.55,
		ScaleType              = Enum.ScaleType.Slice,
		SliceCenter            = Rect.new(49, 49, 450, 450),
	})
	self._shadow = shadow

	local main = create("Frame", {
		Parent           = gui,
		AnchorPoint      = Vector2.new(0.5, 0.5),
		Position         = UDim2.fromScale(0.5, 0.5),
		Size             = self._size,
		BorderSizePixel  = 0,
		ZIndex           = 1,
		ClipsDescendants = true,   -- square interior children clip to the rounded rect
	})
	corner(main, 10)
	local mstroke = stroke(main, 1, 0.2)
	self:_register(main, "BackgroundColor3", "Background")
	self:_register(mstroke, "Color", "Stroke")
	self._main = main

	-- Glue the shadow to the window.
	main:GetPropertyChangedSignal("Position"):Connect(function()
		shadow.Position = main.Position
	end)
	main:GetPropertyChangedSignal("Size"):Connect(function()
		shadow.Size = UDim2.new(0, main.AbsoluteSize.X + 48, 0, main.AbsoluteSize.Y + 48)
	end)

	------------------------------------------------------------------ Title bar
	local titleBar = create("Frame", {
		Parent                 = main,
		BackgroundTransparency = 1,        -- macOS "unified" title bar
		Size                   = UDim2.new(1, 0, 0, 40),
		ZIndex                 = 2,
	})
	self:_buildTrafficLights(titleBar)
	self:_enableDrag(titleBar, main)

	local title = create("TextLabel", {
		Parent                 = titleBar,
		BackgroundTransparency = 1,
		Position               = UDim2.fromOffset(86, 0),
		Size                   = UDim2.new(1, -180, 1, 0),
		Font                   = Enum.Font.GothamBold,
		TextSize               = 14,
		Text                   = cfg.Title or "PandaUI",
		TextXAlignment         = Enum.TextXAlignment.Left,
		ZIndex                 = 2,
	})
	self:_register(title, "TextColor3", "Text")

	if cfg.SubTitle then
		local subTitle = create("TextLabel", {
			Parent                 = titleBar,
			BackgroundTransparency = 1,
			Position               = UDim2.fromOffset(86, 18),
			Size                   = UDim2.new(1, -180, 0, 14),
			Font                   = Enum.Font.Gotham,
			TextSize               = 11,
			Text                   = cfg.SubTitle,
			TextXAlignment         = Enum.TextXAlignment.Left,
			ZIndex                 = 2,
		})
		self:_register(subTitle, "TextColor3", "SubText")
		title.Position = UDim2.fromOffset(86, 4)
		title.Size = UDim2.new(1, -180, 0, 16)
		title.TextYAlignment = Enum.TextYAlignment.Bottom
	end

	-- Theme toggle (top-right of the title bar).
	local themeBtn = create("TextButton", {
		Parent           = titleBar,
		AnchorPoint      = Vector2.new(1, 0.5),
		Position         = UDim2.new(1, -12, 0.5, 0),
		Size             = UDim2.fromOffset(56, 26),
		AutoButtonColor  = false,
		BorderSizePixel  = 0,
		Font             = Enum.Font.GothamMedium,
		TextSize         = 12,
		Text             = self._themeName,
		ZIndex           = 2,
	})
	corner(themeBtn, 6)
	local tbst = stroke(themeBtn)
	self:_register(themeBtn, "BackgroundColor3", "Element")
	self:_register(themeBtn, "TextColor3", "SubText")
	self:_register(tbst,     "Color", "Stroke")
	themeBtn.MouseButton1Click:Connect(function()
		self:ToggleTheme()
		themeBtn.Text = self._themeName
	end)

	-- Title bar bottom separator.
	local sep = create("Frame", {
		Parent          = main,
		Position        = UDim2.fromOffset(0, 40),
		Size            = UDim2.new(1, 0, 0, 1),
		BorderSizePixel = 0,
		ZIndex          = 2,
	})
	self:_register(sep, "BackgroundColor3", "Stroke")

	----------------------------------------------------------------------- Body
	local body = create("Frame", {
		Parent                 = main,
		BackgroundTransparency = 1,
		Position               = UDim2.fromOffset(0, 41),
		Size                   = UDim2.new(1, 0, 1, -41),
		ClipsDescendants       = true,
		ZIndex                 = 1,
	})
	self._body = body

	-- Sidebar (tab rail).
	local sidebar = create("Frame", {
		Parent          = body,
		Size            = UDim2.new(0, 150, 1, 0),
		BorderSizePixel = 0,
		ZIndex          = 1,
	})
	-- round only the bottom-left visually via corner on the whole sidebar
	corner(sidebar, 0)
	self:_register(sidebar, "BackgroundColor3", "Sidebar")
	padding(sidebar, 10)
	create("UIListLayout", {
		Parent    = sidebar,
		Padding   = UDim.new(0, 4),
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
	self._sidebar = sidebar

	-- Sidebar / content separator.
	local vsep = create("Frame", {
		Parent          = body,
		Position        = UDim2.fromOffset(150, 0),
		Size            = UDim2.new(0, 1, 1, 0),
		BorderSizePixel = 0,
		ZIndex          = 1,
	})
	self:_register(vsep, "BackgroundColor3", "Stroke")

	-- Content area.
	local content = create("Frame", {
		Parent                 = body,
		BackgroundTransparency = 1,
		Position               = UDim2.fromOffset(151, 0),
		Size                   = UDim2.new(1, -151, 1, 0),
		ClipsDescendants       = true,   -- contain the tab slide transition
		ZIndex                 = 1,
	})
	self._content = content

	------------------------------------------------------------- Key gate (opt)
	if cfg.KeySystem == true then
		self:_buildKeyPanel(cfg)
	end

	self:_playOpen()   -- pop-in animation
	return self
end

return PandaUI
