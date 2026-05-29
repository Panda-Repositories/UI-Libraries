--[[
============================================================================
  LiquidUI  —  Liquid-Glass UI Library for Roblox (Luau)
============================================================================

  A professional, organized, frosted-glass UI library inspired by Apple's
  "Liquid Glass" design language.

  Highlights
    • Frosted glass panels (translucent, rim-lit, rounded) over a real
      blurred 3D background (Lighting BlurEffect).
    • Drifting "liquid" bubbles behind the glass for subtle motion.
    • Fully resizable window (bottom-right grip) with a min size.
    • Hotkey to show/hide (default RightControl; configurable, e.g. Escape).
    • Persistent config saved to disk (theme, position, size, visibility,
      and toggle flags) — restored on next launch.
    • Dynamic Light / Dark theme with TweenService cross-fades.
    • Built-in key system: V4.3-Cookies first, automatic V2 fallback.

----------------------------------------------------------------------------
  USAGE
----------------------------------------------------------------------------

    local LiquidUI = loadstring(game:HttpGet("http://localhost:4022/ui/liquid"))()

    local Window = LiquidUI:CreateWindow({
        Title     = "Liquid Hub",
        SubTitle  = "v1.0",
        Theme     = "Dark",                 -- "Dark" | "Light"
        Size      = UDim2.fromOffset(600, 420),
        ToggleKey = Enum.KeyCode.RightControl,

        -- Key system (identical to PandaUI) ---------------------------------
        KeySystem         = true,
        Legacy_Compatible = true,           -- default true → V2 fallback
        ServiceId         = "pandadevkit",

        -- Endpoints (override only for local testing) -----------------------
        CookiesLibUrl  = "http://localhost:4022/cv4/lib",
        CookiesBaseUrl = "http://localhost:4022",
        CookiesHost    = "localhost",
        V2Url          = "http://localhost:3000/v2_validation",

        OnAuthSuccess = function(info) print("authed via", info.source) end,
    })

    local main = Window:CreateTab("Main")
    main:CreateSection("General")
    main:CreateLabel("Welcome to the liquid side.")
    main:CreateButton({ Text = "Click", Callback = function() print("hi") end })
    main:CreateToggle({ Text = "Auto Farm", Flag = "autofarm", Callback = function(v) print(v) end })
    main:CreateInput({ Placeholder = "Search...", Callback = function(t) print(t) end })

============================================================================
]]

--======================================================================--
--  SERVICES
--======================================================================--

local Players          = game:GetService("Players")
local TweenService     = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local HttpService      = game:GetService("HttpService")
local Lighting         = game:GetService("Lighting")

local LocalPlayer = Players.LocalPlayer

--======================================================================--
--  THEME  (glass tints — panels are translucent, so colors read as tint)
--======================================================================--

local Themes = {
	Dark = {
		Accent     = Color3.fromRGB(122, 172, 255),   -- liquid blue
		Glass      = Color3.fromRGB(18, 20, 26),       -- main panel tint
		GlassLight = Color3.fromRGB(48, 52, 64),       -- elements
		GlassHover = Color3.fromRGB(64, 70, 86),
		Text       = Color3.fromRGB(244, 246, 251),
		SubText    = Color3.fromRGB(168, 174, 190),
		Bubble     = Color3.fromRGB(122, 172, 255),
	},
	Light = {
		Accent     = Color3.fromRGB(0, 122, 255),
		Glass      = Color3.fromRGB(236, 240, 248),
		GlassLight = Color3.fromRGB(255, 255, 255),
		GlassHover = Color3.fromRGB(240, 243, 250),
		Text       = Color3.fromRGB(22, 24, 30),
		SubText    = Color3.fromRGB(92, 98, 114),
		Bubble     = Color3.fromRGB(0, 122, 255),
	},
}

local TWEEN_TIME  = 0.25
local TWEEN_STYLE = Enum.EasingStyle.Quad
local TWEEN_DIR   = Enum.EasingDirection.Out
local WHITE       = Color3.fromRGB(255, 255, 255)

-- Glass translucency (same across themes; blur behind does the rest).
local MAIN_TRANSPARENCY    = 0.10
local SIDEBAR_TRANSPARENCY = 0.30
local ELEMENT_TRANSPARENCY = 0.20
local RIM_TRANSPARENCY     = 0.55

--======================================================================--
--  LOW-LEVEL HELPERS
--======================================================================--

local function create(className, props)
	local inst = Instance.new(className)
	local parent
	if props then
		for k, v in pairs(props) do
			if k == "Parent" then parent = v else inst[k] = v end
		end
	end
	if parent then inst.Parent = parent end
	return inst
end

local function corner(inst, radius)
	return create("UICorner", { Parent = inst, CornerRadius = UDim.new(0, radius or 12) })
end

-- Rim-light stroke (white, semi-transparent) — the glass edge highlight.
local function stroke(inst, thickness, transparency, color)
	return create("UIStroke", {
		Parent          = inst,
		Thickness       = thickness or 1,
		Transparency    = transparency or RIM_TRANSPARENCY,
		Color           = color or WHITE,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

local function padding(inst, all)
	local d = UDim.new(0, all or 12)
	return create("UIPadding", {
		Parent = inst, PaddingLeft = d, PaddingRight = d, PaddingTop = d, PaddingBottom = d,
	})
end

local function tween(inst, props, time, style, dir)
	local info = TweenInfo.new(time or TWEEN_TIME, style or TWEEN_STYLE, dir or TWEEN_DIR)
	local t = TweenService:Create(inst, info, props)
	t:Play()
	return t
end

--======================================================================--
--  CONFIG PERSISTENCE  (writefile/readfile — executor only, graceful)
--======================================================================--

local function configPath(name)
	return "LiquidUI_" .. tostring(name) .. ".json"
end

local function loadConfig(name)
	if not (isfile and readfile) then return {} end
	local ok, exists = pcall(isfile, configPath(name))
	if not (ok and exists) then return {} end
	local rOk, content = pcall(readfile, configPath(name))
	if not (rOk and content and content ~= "") then return {} end
	local dOk, data = pcall(function() return HttpService:JSONDecode(content) end)
	if dOk and type(data) == "table" then return data end
	return {}
end

local function saveConfig(name, data)
	if not writefile then return end
	pcall(writefile, configPath(name), HttpService:JSONEncode(data))
end

--======================================================================--
--  STEALTH HELPERS  (shrink the client-side anti-cheat scan surface)
--
--  Game anti-cheats are LocalScripts that scan the client DataModel for
--  foreign instances. We (1) give the ScreenGui a random per-session name,
--  (2) parent it into a protected/hidden container so CoreGui scans miss it,
--  and (3) keep the relaunch handle in the executor global env (getgenv),
--  which game scripts cannot read — so nothing scannable is left behind.
--  The optional blur is the one thing that must live in Lighting/Camera
--  (effects can't be hidden), so it is OFF by default — see StealthBlur.
--======================================================================--

local _genv = (getgenv and getgenv()) or _G
local REG_KEY = "_lui_active"

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
	local hui = gethui and gethui()
	if hui and pcall(function() gui.Parent = hui end) and gui.Parent then return end
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
--  HWID  (for V2 fallback)
--======================================================================--

local _cachedHWID
local function getHWID()
	if _cachedHWID then return _cachedHWID end
	local hwid
	if gethwid then
		local ok, r = pcall(gethwid); if ok and r and r ~= "" then hwid = r end
	end
	if not hwid and LocalPlayer then
		local exec = ""
		if identifyexecutor then local ok, r = pcall(identifyexecutor); if ok and r then exec = r end end
		hwid = "P_" .. tostring(LocalPlayer.UserId) .. "_" .. (exec ~= "" and exec or "unknown")
	end
	if not hwid then
		local ok, r = pcall(function() return game:GetService("RbxAnalyticsService"):GetClientId() end)
		if ok and r then hwid = r end
	end
	if not hwid and LocalPlayer then hwid = "PANDA_" .. tostring(LocalPlayer.UserId) end
	_cachedHWID = hwid or "unknown_hwid"
	return _cachedHWID
end

--======================================================================--
--  HTTP
--======================================================================--

local function resolveRequest()
	return (syn and syn.request) or (http and http.request) or (fluxus and fluxus.request)
		or request or http_request or httprequest
end

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

local function httpPostJson(url, tbl)
	local bodyStr = HttpService:JSONEncode(tbl)
	local req = resolveRequest()
	if req then
		local ok, resp = pcall(req, {
			Url = url, Method = "POST",
			Headers = { ["Content-Type"] = "application/json" }, Body = bodyStr,
		})
		if ok and resp then
			return { Body = resp.Body or resp.body or "", StatusCode = resp.StatusCode or resp.statusCode or 0 }
		end
	end
	local ok, resp = pcall(function()
		return HttpService:RequestAsync({
			Url = url, Method = "POST",
			Headers = { ["Content-Type"] = "application/json" }, Body = bodyStr,
		})
	end)
	if ok and resp then return { Body = resp.Body, StatusCode = resp.StatusCode } end
	return nil
end

--======================================================================--
--  AUTH MODULE  (identical contract to PandaUI: Cookies → V2 fallback)
--======================================================================--

local Auth = {}

function Auth.fetchCookies(url)
	local body = httpGet(url)
	if not body or #body < 100 then return nil end
	local loader = loadstring(body)
	if not loader then return nil end
	local ok, mod = pcall(loader)
	if not ok or type(mod) ~= "table" or type(mod.configure) ~= "function" then return nil end
	return mod
end

function Auth.ensureCookies(cfg, state)
	if state.cookies then return state.cookies end
	local mod = Auth.fetchCookies(cfg.CookiesLibUrl)
	if not mod then return nil, "Cookies library unreachable" end
	local okCfg = pcall(function()
		mod.configure({
			serviceId         = cfg.ServiceId,
			debug             = cfg.Debug == true,
			kickOnDetect      = false,
			openDashboard     = false,
			validationTimeout = cfg.ValidationTimeout or 600,
			baseUrl           = cfg.CookiesBaseUrl,
			canonicalHost     = cfg.CookiesHost,
		})
	end)
	if not okCfg then return nil, "Cookies configure failed" end
	state.cookies = mod
	return mod
end

function Auth.viaCookies(cfg, key, state)
	local mod, err = Auth.ensureCookies(cfg, state)
	if not mod then return { success = false, error = err } end
	local ok, res = pcall(function() return mod.validate(key) end)
	if not ok then return { success = false, error = "Cookies validation error" } end
	if res and res.success then
		return {
			success = true, source = "V4.3-Cookies",
			isPremium = res.isPremium, expiresAt = res.expiresAt,
			sessionId = res.sessionId, getKeyUrl = res.getKeyUrl,
		}
	end
	return { success = false, error = (res and res.error) or "Invalid key" }
end

function Auth.viaV2(cfg, key, hwid)
	if not cfg.V2Url or cfg.V2Url == "" then return { success = false, error = "V2 endpoint not configured" } end
	local resp = httpPostJson(cfg.V2Url, { serviceid = cfg.ServiceId, hwid = hwid, key = key })
	if not resp then return { success = false, error = "V2 endpoint unreachable" } end
	local ok, data = pcall(function() return HttpService:JSONDecode(resp.Body) end)
	if not ok or type(data) ~= "table" then return { success = false, error = "V2 malformed response" } end
	if data.Status == "Authenticate" then
		return { success = true, source = "V2", isPremium = data.Is_Premium == true, expiresAt = data.Expired_At, note = data.Note }
	end
	return { success = false, error = data.Note or "Invalid key" }
end

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
		return { success = false, error = string.format("Cookies: %s | V2: %s", primary.error or "?", fallback.error or "?") }
	end
	return primary
end

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
--======================================================================--

local Tab = {}
Tab.__index = Tab

function Tab:CreateSection(text)
	local w = self._window
	local lbl = create("TextLabel", {
		Parent = self._page, BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 20),
		Font = Enum.Font.GothamBold, TextSize = 12,
		Text = string.upper(tostring(text or "")),
		TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Bottom,
	})
	w:_register(lbl, "TextColor3", "SubText")
	return { Set = function(_, t) lbl.Text = string.upper(tostring(t)) end }
end

function Tab:CreateLabel(opts)
	if type(opts) == "string" then opts = { Text = opts } end
	opts = opts or {}
	local w = self._window
	local lbl = create("TextLabel", {
		Parent = self._page, BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
		Font = Enum.Font.Gotham, TextSize = opts.TextSize or 14,
		Text = opts.Text or "", TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
	})
	w:_register(lbl, "TextColor3", opts.Muted and "SubText" or "Text")
	return { Set = function(_, t) lbl.Text = t end, Get = function() return lbl.Text end }
end

function Tab:CreateButton(opts)
	opts = opts or {}
	local w = self._window
	local btn = create("TextButton", {
		Parent = self._page, Size = UDim2.new(1, 0, 0, 38),
		AutoButtonColor = false, BorderSizePixel = 0,
		BackgroundTransparency = ELEMENT_TRANSPARENCY,
		Font = Enum.Font.GothamMedium, TextSize = 14, Text = opts.Text or "Button",
	})
	corner(btn, 10); local st = stroke(btn)
	w:_register(btn, "BackgroundColor3", "GlassLight")
	w:_register(btn, "TextColor3", "Text")
	btn.MouseEnter:Connect(function() tween(btn, { BackgroundColor3 = w._theme.GlassHover }, 0.15) end)
	btn.MouseLeave:Connect(function() tween(btn, { BackgroundColor3 = w._theme.GlassLight }, 0.15) end)
	btn.MouseButton1Click:Connect(function()
		tween(btn, { Size = UDim2.new(1, -8, 0, 36) }, 0.08)
		task.delay(0.08, function() tween(btn, { Size = UDim2.new(1, 0, 0, 38) }, 0.1) end)
		if opts.Callback then task.spawn(opts.Callback) end
	end)
	return { SetText = function(_, t) btn.Text = t end }
end

function Tab:CreateToggle(opts)
	opts = opts or {}
	local w = self._window
	local flags = w._flags

	local value = false
	if opts.Flag ~= nil and flags[opts.Flag] ~= nil then value = flags[opts.Flag] == true
	elseif opts.Default ~= nil then value = opts.Default == true end

	local holder = create("Frame", {
		Parent = self._page, Size = UDim2.new(1, 0, 0, 40),
		BackgroundTransparency = ELEMENT_TRANSPARENCY, BorderSizePixel = 0,
	})
	corner(holder, 10); local st = stroke(holder)
	w:_register(holder, "BackgroundColor3", "GlassLight")

	local lbl = create("TextLabel", {
		Parent = holder, BackgroundTransparency = 1,
		Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -76, 1, 0),
		Font = Enum.Font.GothamMedium, TextSize = 14, Text = opts.Text or "Toggle",
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	w:_register(lbl, "TextColor3", "Text")

	local sw = create("Frame", {
		Parent = holder, AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(46, 24),
		BorderSizePixel = 0, BackgroundColor3 = Color3.fromRGB(110, 116, 130),
	})
	corner(sw, 12)
	local knob = create("Frame", {
		Parent = sw, AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 3, 0.5, 0), Size = UDim2.fromOffset(18, 18),
		BackgroundColor3 = WHITE, BorderSizePixel = 0,
	})
	corner(knob, 9)

	local function apply(animated)
		local t = animated and 0.18 or 0
		tween(sw, { BackgroundColor3 = value and w._theme.Accent or Color3.fromRGB(110, 116, 130) }, t)
		tween(knob, { Position = value and UDim2.new(1, -21, 0.5, 0) or UDim2.new(0, 3, 0.5, 0) }, t)
	end
	apply(false)

	local hit = create("TextButton", { Parent = holder, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Text = "" })
	local function set(v, fireCb)
		value = v == true
		apply(true)
		if opts.Flag ~= nil then flags[opts.Flag] = value; w:_saveState() end
		if fireCb and opts.Callback then task.spawn(opts.Callback, value) end
	end
	hit.MouseButton1Click:Connect(function() set(not value, true) end)

	-- Restore-on-load should fire the callback so game state matches the UI.
	if value and opts.Flag ~= nil and opts.Callback then task.spawn(opts.Callback, true) end

	return { Get = function() return value end, Set = function(_, v) set(v, true) end }
end

function Tab:CreateInput(opts)
	opts = opts or {}
	local w = self._window
	local box = create("TextBox", {
		Parent = self._page, Size = UDim2.new(1, 0, 0, 38),
		BackgroundTransparency = ELEMENT_TRANSPARENCY, BorderSizePixel = 0,
		Font = Enum.Font.Gotham, TextSize = 14,
		Text = opts.Default or "", PlaceholderText = opts.Placeholder or "",
		ClearTextOnFocus = opts.ClearOnFocus == true,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	corner(box, 10); padding(box, 10); local st = stroke(box)
	w:_register(box, "BackgroundColor3", "GlassLight")
	w:_register(box, "TextColor3", "Text")
	w:_register(box, "PlaceholderColor3", "SubText")
	box.Focused:Connect(function() tween(st, { Color = w._theme.Accent, Transparency = 0, Thickness = 1.6 }, 0.15) end)
	box.FocusLost:Connect(function(enter)
		tween(st, { Color = WHITE, Transparency = RIM_TRANSPARENCY, Thickness = 1 }, 0.15)
		if opts.Callback then task.spawn(opts.Callback, box.Text, enter) end
	end)
	return { Get = function() return box.Text end, Set = function(_, t) box.Text = t end }
end

--======================================================================--
--  WINDOW CLASS
--======================================================================--

local Window = {}
Window.__index = Window

function Window:_register(inst, prop, themeKey)
	table.insert(self._themeItems, { inst = inst, prop = prop, key = themeKey })
	inst[prop] = self._theme[themeKey]
end

function Window:_applyTheme()
	for _, item in ipairs(self._themeItems) do
		if item.inst and item.inst.Parent then
			tween(item.inst, { [item.prop] = self._theme[item.key] })
		end
	end
	if self._active then self:_selectTab(self._active) end
end

function Window:SetTheme(name)
	if name ~= "Dark" and name ~= "Light" then return end
	self._themeName = name
	self._theme = Themes[name]
	self:_applyTheme()
	self:_saveState()
end

function Window:ToggleTheme()
	self:SetTheme(self._themeName == "Dark" and "Light" or "Dark")
end

function Window:_selectTab(tab)
	for _, t in ipairs(self._tabs) do
		local selected = (t == tab)
		if selected then
			t._page.Visible = true
			t._page.Position = UDim2.fromOffset(0, 12)
			tween(t._page, { Position = UDim2.fromOffset(0, 0) }, 0.2)
		else
			t._page.Visible = false
		end
		tween(t._button, {
			BackgroundTransparency = selected and ELEMENT_TRANSPARENCY or 1,
			BackgroundColor3       = self._theme.Accent,
			TextColor3             = selected and WHITE or self._theme.SubText,
		}, 0.15)
	end
	self._active = tab
end

function Window:CreateTab(name)
	local btn = create("TextButton", {
		Parent = self._sidebar, Size = UDim2.new(1, 0, 0, 34),
		AutoButtonColor = false, BackgroundTransparency = 1, BorderSizePixel = 0,
		Font = Enum.Font.GothamMedium, TextSize = 14, Text = "  " .. tostring(name),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	corner(btn, 8)
	self:_register(btn, "TextColor3", "SubText")

	local page = create("ScrollingFrame", {
		Parent = self._content, Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1, BorderSizePixel = 0, Visible = false,
		CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 4, ScrollBarImageTransparency = 0.4,
	})
	create("UIListLayout", { Parent = page, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder })
	padding(page, 12)

	local tab = setmetatable({ _window = self, _button = btn, _page = page }, Tab)
	btn.MouseButton1Click:Connect(function() self:_selectTab(tab) end)
	btn.MouseEnter:Connect(function()
		if self._active ~= tab then tween(btn, { BackgroundTransparency = 0.85 }, 0.12) end
	end)
	btn.MouseLeave:Connect(function()
		if self._active ~= tab then tween(btn, { BackgroundTransparency = 1 }, 0.12) end
	end)
	table.insert(self._tabs, tab)
	if #self._tabs == 1 then self:_selectTab(tab) end
	return tab
end

-- Connection tracking so relaunch / Destroy doesn't leak global input hooks.
function Window:_bind(conn)
	table.insert(self._conns, conn)
	return conn
end

function Window:_setBlur(on)
	if not self._blur then return end
	tween(self._blur, { Size = on and self._blurAmount or 0 }, 0.3)
end

function Window:Show() self:Toggle(true) end
function Window:Hide() self:Toggle(false) end

function Window:Toggle(force)
	local show = force
	if show == nil then show = not self._visible end
	if show == self._visible and self._didFirstToggle then return end
	self._didFirstToggle = true
	self._visible = show

	if show then
		self._main.Visible = true
		local sc = self._main:FindFirstChildOfClass("UIScale") or create("UIScale", { Parent = self._main, Scale = 0.94 })
		sc.Scale = 0.94
		tween(sc, { Scale = 1 }, 0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		self:_setBlur(true)
	else
		self:_setBlur(false)
		local sc = self._main:FindFirstChildOfClass("UIScale") or create("UIScale", { Parent = self._main, Scale = 1 })
		tween(sc, { Scale = 0.94 }, 0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		task.delay(0.2, function()
			if not self._visible then self._main.Visible = false end
		end)
	end
	self:_saveState()
end

function Window:_saveState()
	if self._loading then return end
	local m = self._main
	saveConfig(self._cfgName, {
		theme   = self._themeName,
		visible = self._visible,
		pos     = { m.Position.X.Scale, m.Position.X.Offset, m.Position.Y.Scale, m.Position.Y.Offset },
		size    = { m.Size.X.Offset, m.Size.Y.Offset },
		flags   = self._flags,
	})
end

function Window:Destroy()
	if self._destroying then return end
	self._destroying = true
	if _genv[REG_KEY] == self._hardDestroy then _genv[REG_KEY] = nil end
	for _, c in ipairs(self._conns) do pcall(function() c:Disconnect() end) end
	self:_setBlur(false)
	if self._main then
		local sc = self._main:FindFirstChildOfClass("UIScale") or create("UIScale", { Parent = self._main, Scale = 1 })
		tween(sc, { Scale = 0.92 }, 0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		tween(self._main, { BackgroundTransparency = 1 }, 0.2)
	end
	task.delay(0.25, function()
		if self._blur then pcall(function() self._blur:Destroy() end) end
		if self._gui then pcall(function() self._gui:Destroy() end) end
	end)
end

-- Smooth dragging via InputBegan / InputChanged.
function Window:_enableDrag(handle, target)
	local dragging, dragInput, dragStart, startPos = false, nil, nil, nil
	self:_bind(handle.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging, dragStart, startPos = true, input.Position, target.Position
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
					self:_saveState()
				end
			end)
		end
	end))
	self:_bind(handle.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
			dragInput = input
		end
	end))
	self:_bind(UserInputService.InputChanged:Connect(function(input)
		if dragging and input == dragInput then
			local delta = input.Position - dragStart
			target.Position = UDim2.new(
				startPos.X.Scale, startPos.X.Offset + delta.X,
				startPos.Y.Scale, startPos.Y.Offset + delta.Y)
		end
	end))
end

-- Bottom-right resize grip.
function Window:_enableResize(grip, target)
	local resizing, startPos, startSize = false, nil, nil
	self:_bind(grip.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			resizing, startPos, startSize = true, input.Position, target.AbsoluteSize
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					resizing = false
					self:_saveState()
				end
			end)
		end
	end))
	self:_bind(UserInputService.InputChanged:Connect(function(input)
		if resizing and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			local delta = input.Position - startPos
			local nx = math.max(self._minSize.X, startSize.X + delta.X)
			local ny = math.max(self._minSize.Y, startSize.Y + delta.Y)
			target.Size = UDim2.fromOffset(nx, ny)
		end
	end))
end

-- Liquid bubbles drifting upward behind the glass.
function Window:_startBubbles(layer)
	local function animate(b, size)
		local startX = math.random()
		b.Position = UDim2.new(startX, 0, 1, size)
		b.BackgroundTransparency = 0.92
		local dur = math.random(45, 95) / 10
		local t = tween(b, {
			Position = UDim2.new(math.clamp(startX + math.random(-12, 12) / 100, 0, 1), 0, 0, -size),
			BackgroundTransparency = 0.82,
		}, dur, Enum.EasingStyle.Linear)
		t.Completed:Connect(function()
			if b and b.Parent then animate(b, size) end
		end)
	end
	for i = 1, 7 do
		local size = math.random(20, 52)
		local b = create("Frame", {
			Parent = layer, Size = UDim2.fromOffset(size, size),
			BackgroundColor3 = self._theme.Bubble, BackgroundTransparency = 0.9,
			BorderSizePixel = 0, ZIndex = 0,
		})
		corner(b, math.floor(size / 2))
		table.insert(self._bubbles, b)
		task.delay(math.random(0, 40) / 10, function()
			if b.Parent then animate(b, size) end
		end)
	end
end

function Window:_refreshBubbleColors()
	for _, b in ipairs(self._bubbles) do
		if b and b.Parent then tween(b, { BackgroundColor3 = self._theme.Bubble }) end
	end
end

--======================================================================--
--  KEY SYSTEM SCREEN  (glass styled)
--======================================================================--

function Window:_buildKeyPanel(cfg)
	local panel = create("Frame", {
		Parent = self._body, Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = self._theme.Glass, BackgroundTransparency = 0.05,
		BorderSizePixel = 0, ZIndex = 50,
	})
	self:_register(panel, "BackgroundColor3", "Glass")

	local card = create("Frame", {
		Parent = panel, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(370, 230), BackgroundTransparency = ELEMENT_TRANSPARENCY,
		BorderSizePixel = 0, ZIndex = 51,
	})
	corner(card, 14); stroke(card)
	self:_register(card, "BackgroundColor3", "GlassLight")
	padding(card, 20)
	create("UIListLayout", { Parent = card, Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder })

	local title = create("TextLabel", {
		Parent = card, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 24), ZIndex = 52,
		Font = Enum.Font.GothamBold, TextSize = 18, Text = "Key Required",
		TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 1,
	})
	self:_register(title, "TextColor3", "Text")

	local sub = create("TextLabel", {
		Parent = card, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 30), ZIndex = 52,
		Font = Enum.Font.Gotham, TextSize = 12,
		Text = "Paste your key to continue, or press Get Key to copy the URL.",
		TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top, LayoutOrder = 2,
	})
	self:_register(sub, "TextColor3", "SubText")

	local input = create("TextBox", {
		Parent = card, Size = UDim2.new(1, 0, 0, 38), BackgroundTransparency = ELEMENT_TRANSPARENCY,
		BorderSizePixel = 0, Font = Enum.Font.Code, TextSize = 15, Text = "",
		PlaceholderText = "PANDA-XXXX-XXXX-XXXX", ClearTextOnFocus = false,
		TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 52, LayoutOrder = 3,
	})
	corner(input, 10); padding(input, 10); local ist = stroke(input)
	self:_register(input, "BackgroundColor3", "GlassHover")
	self:_register(input, "TextColor3", "Text")
	self:_register(input, "PlaceholderColor3", "SubText")
	input.Focused:Connect(function() tween(ist, { Color = self._theme.Accent, Transparency = 0, Thickness = 1.6 }, 0.15) end)
	input.FocusLost:Connect(function() tween(ist, { Color = WHITE, Transparency = RIM_TRANSPARENCY, Thickness = 1 }, 0.15) end)

	task.spawn(function()
		local mod = Auth.ensureCookies(cfg, self._authState)
		if mod and mod.loadSavedKey then
			local ok, saved = pcall(mod.loadSavedKey)
			if ok and saved and saved ~= "" then input.Text = saved end
		end
	end)

	local row = create("Frame", {
		Parent = card, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 40), ZIndex = 52, LayoutOrder = 4,
	})
	create("UIListLayout", { Parent = row, FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder })

	local getKey = create("TextButton", {
		Parent = row, Size = UDim2.new(0.5, -5, 1, 0), AutoButtonColor = false, BorderSizePixel = 0,
		BackgroundTransparency = ELEMENT_TRANSPARENCY, Font = Enum.Font.GothamMedium, TextSize = 14,
		Text = "Get Key", ZIndex = 52, LayoutOrder = 1,
	})
	corner(getKey, 10); stroke(getKey)
	self:_register(getKey, "BackgroundColor3", "GlassHover")
	self:_register(getKey, "TextColor3", "Text")

	local submit = create("TextButton", {
		Parent = row, Size = UDim2.new(0.5, -5, 1, 0), AutoButtonColor = false, BorderSizePixel = 0,
		BackgroundColor3 = self._theme.Accent, BackgroundTransparency = 0.05, TextColor3 = WHITE,
		Font = Enum.Font.GothamBold, TextSize = 14, Text = "Authenticate", ZIndex = 52, LayoutOrder = 2,
	})
	corner(submit, 10)

	local status = create("TextLabel", {
		Parent = card, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 18), ZIndex = 52,
		Font = Enum.Font.Gotham, TextSize = 12, Text = "", TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 5,
	})
	self:_register(status, "TextColor3", "SubText")

	getKey.MouseButton1Click:Connect(function()
		status.Text = "Fetching Get Key URL..."
		task.spawn(function()
			local url = Auth.copyGetKeyUrl(cfg, self._authState)
			status.Text = url and "Get Key URL copied to clipboard." or "Could not build Get Key URL."
		end)
	end)

	submit.MouseButton1Click:Connect(function()
		if self._authBusy then return end
		self._authBusy = true
		local key = (input.Text or ""):gsub("%s", "")
		if key == "" then status.Text = "Please enter a key."; self._authBusy = false; return end
		status.Text = "Authenticating..."
		task.spawn(function()
			local result = Auth.run(cfg, key, self._authState)
			if result.success then
				status.Text = "Authenticated via " .. result.source .. " — welcome!"
				task.wait(0.45)
				tween(panel, { BackgroundTransparency = 1 }, 0.3)
				tween(card, { Size = UDim2.fromOffset(370, 0) }, 0.3)
				task.wait(0.32)
				panel:Destroy()
				self._authed = true
				if cfg.OnAuthSuccess then task.spawn(cfg.OnAuthSuccess, result) end
			else
				status.Text = "Failed: " .. (result.error or "unknown")
				self._authBusy = false
				if cfg.OnAuthFail then task.spawn(cfg.OnAuthFail, result) end
			end
		end)
	end)
end

--======================================================================--
--  PUBLIC ENTRY POINT
--======================================================================--

local LiquidUI = {}
LiquidUI.__index = LiquidUI
LiquidUI.Version = "1.0.0"

function LiquidUI:CreateWindow(cfg)
	cfg = cfg or {}
	if cfg.Legacy_Compatible == nil then cfg.Legacy_Compatible = true end
	cfg.ServiceId     = cfg.ServiceId     or "YOUR_SERVICE_ID"
	cfg.CookiesLibUrl = cfg.CookiesLibUrl or "https://secure.pandauth.com/cv4/lib"
	cfg.V2Url         = cfg.V2Url         or "https://secure.pandauth.com/v2_validation"

	local self = setmetatable({}, Window)
	-- Config filename is stable (it lives on the executor disk, not in the
	-- DataModel, so it is not a game-scannable artifact and must persist).
	self._cfgName    = cfg.ConfigName or ("LiquidUI_" .. tostring(cfg.ServiceId))
	self._themeItems = {}
	self._tabs       = {}
	self._bubbles    = {}
	self._conns      = {}
	self._authState  = {}
	self._loading    = true
	self._minSize    = cfg.MinSize or Vector2.new(440, 300)
	self._blurAmount = cfg.BlurSize or 18
	self._toggleKey  = cfg.ToggleKey or Enum.KeyCode.RightControl

	-- Load any saved config and merge over the defaults.
	local saved = loadConfig(self._cfgName)
	self._flags     = saved.flags or {}
	self._themeName = saved.theme or ((cfg.Theme == "Light") and "Light" or "Dark")
	self._theme     = Themes[self._themeName]
	self._visible   = (saved.visible == nil) and true or (saved.visible == true)
	local size      = cfg.Size or UDim2.fromOffset(600, 420)
	if saved.size then size = UDim2.fromOffset(saved.size[1], saved.size[2]) end

	------------------------------------------------------------- relaunch clean
	-- Handle stored in the executor global env (getgenv) — invisible to game
	-- scripts, so no scannable name/tag is left in the DataModel.
	local prevCleanup = _genv[REG_KEY]
	if type(prevCleanup) == "function" then pcall(prevCleanup) end

	------------------------------------------------------------------ ScreenGui
	local gui = create("ScreenGui", {
		Name = cfg.Name or randomName(8), ResetOnSpawn = false, IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 9999,
	})
	mountProtected(gui)
	self._gui = gui

	--------------------------------------------------------------------- Blur
	-- Stealth default: NO post-processing effect exists at all (zero footprint
	-- in Lighting/Camera). Opt in with StealthBlur=false → a randomly-named
	-- BlurEffect parented to the Camera (less commonly scanned than Lighting),
	-- removed on hide/close.
	if cfg.StealthBlur == false then
		pcall(function()
			local blur = Instance.new("BlurEffect")
			blur.Name = randomName(6)
			blur.Size = 0
			blur.Parent = workspace.CurrentCamera or Lighting
			self._blur = blur
		end)
	end

	-- Hard (immediate) teardown used by relaunch; Destroy() is the animated one.
	self._hardDestroy = function()
		self._destroying = true
		for _, c in ipairs(self._conns) do pcall(function() c:Disconnect() end) end
		if self._blur then pcall(function() self._blur:Destroy() end) end
		if self._gui then pcall(function() self._gui:Destroy() end) end
	end
	_genv[REG_KEY] = self._hardDestroy

	--------------------------------------------------------------- Main panel
	local main = create("Frame", {
		Parent = gui, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5), Size = size,
		BackgroundColor3 = self._theme.Glass, BackgroundTransparency = MAIN_TRANSPARENCY,
		BorderSizePixel = 0, ClipsDescendants = true, ZIndex = 1,
	})
	corner(main, 16)
	stroke(main, 1.5, RIM_TRANSPARENCY)
	self:_register(main, "BackgroundColor3", "Glass")
	self._main = main
	if saved.pos then main.Position = UDim2.new(saved.pos[1], saved.pos[2], saved.pos[3], saved.pos[4]) end

	-- Liquid bubble layer (behind everything inside the panel).
	local bubbleLayer = create("Frame", {
		Parent = main, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
		BorderSizePixel = 0, ClipsDescendants = true, ZIndex = 0,
	})
	self:_startBubbles(bubbleLayer)

	-- Glass top sheen.
	local sheen = create("Frame", {
		Parent = main, Size = UDim2.new(1, 0, 0.55, 0), BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.9, BorderSizePixel = 0, ZIndex = 1,
	})
	corner(sheen, 16)
	create("UIGradient", {
		Parent = sheen, Rotation = 90,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.86),
			NumberSequenceKeypoint.new(1, 1),
		}),
	})

	------------------------------------------------------------------ Title bar
	local titleBar = create("Frame", {
		Parent = main, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 44), ZIndex = 3,
	})
	self:_enableDrag(titleBar, main)

	local title = create("TextLabel", {
		Parent = titleBar, BackgroundTransparency = 1, Position = UDim2.fromOffset(18, 0),
		Size = UDim2.new(1, -150, 1, 0), Font = Enum.Font.GothamBold, TextSize = 15,
		Text = cfg.Title or "LiquidUI", TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 3,
	})
	self:_register(title, "TextColor3", "Text")
	if cfg.SubTitle then
		title.Position = UDim2.fromOffset(18, 5); title.Size = UDim2.new(1, -150, 0, 17)
		title.TextYAlignment = Enum.TextYAlignment.Bottom
		local subTitle = create("TextLabel", {
			Parent = titleBar, BackgroundTransparency = 1, Position = UDim2.fromOffset(18, 22),
			Size = UDim2.new(1, -150, 0, 14), Font = Enum.Font.Gotham, TextSize = 11,
			Text = cfg.SubTitle, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 3,
		})
		self:_register(subTitle, "TextColor3", "SubText")
	end

	-- Theme toggle + close, top-right.
	local themeBtn = create("TextButton", {
		Parent = titleBar, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -52, 0.5, 0),
		Size = UDim2.fromOffset(58, 26), AutoButtonColor = false, BorderSizePixel = 0,
		BackgroundTransparency = ELEMENT_TRANSPARENCY, Font = Enum.Font.GothamMedium, TextSize = 12,
		Text = self._themeName, ZIndex = 3,
	})
	corner(themeBtn, 8); stroke(themeBtn)
	self:_register(themeBtn, "BackgroundColor3", "GlassLight")
	self:_register(themeBtn, "TextColor3", "SubText")
	themeBtn.MouseButton1Click:Connect(function()
		self:ToggleTheme(); self:_refreshBubbleColors(); themeBtn.Text = self._themeName
	end)

	local closeBtn = create("TextButton", {
		Parent = titleBar, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -16, 0.5, 0),
		Size = UDim2.fromOffset(26, 26), AutoButtonColor = false, BorderSizePixel = 0,
		BackgroundTransparency = ELEMENT_TRANSPARENCY, Font = Enum.Font.GothamBold, TextSize = 14,
		Text = "✕", ZIndex = 3,
	})
	corner(closeBtn, 8); stroke(closeBtn)
	self:_register(closeBtn, "BackgroundColor3", "GlassLight")
	self:_register(closeBtn, "TextColor3", "Text")
	closeBtn.MouseButton1Click:Connect(function() self:Destroy() end)

	local sep = create("Frame", {
		Parent = main, Position = UDim2.fromOffset(0, 44), Size = UDim2.new(1, 0, 0, 1),
		BackgroundColor3 = WHITE, BackgroundTransparency = 0.8, BorderSizePixel = 0, ZIndex = 3,
	})

	----------------------------------------------------------------------- Body
	local body = create("Frame", {
		Parent = main, BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 45),
		Size = UDim2.new(1, 0, 1, -45), ClipsDescendants = true, ZIndex = 2,
	})
	self._body = body

	local sidebar = create("Frame", {
		Parent = body, Size = UDim2.new(0, 156, 1, 0), BackgroundTransparency = SIDEBAR_TRANSPARENCY,
		BorderSizePixel = 0, ZIndex = 2,
	})
	self:_register(sidebar, "BackgroundColor3", "GlassLight")
	padding(sidebar, 12)
	create("UIListLayout", { Parent = sidebar, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder })
	self._sidebar = sidebar

	local vsep = create("Frame", {
		Parent = body, Position = UDim2.fromOffset(156, 0), Size = UDim2.new(0, 1, 1, 0),
		BackgroundColor3 = WHITE, BackgroundTransparency = 0.85, BorderSizePixel = 0, ZIndex = 2,
	})

	local content = create("Frame", {
		Parent = body, BackgroundTransparency = 1, Position = UDim2.fromOffset(157, 0),
		Size = UDim2.new(1, -157, 1, 0), ClipsDescendants = true, ZIndex = 2,
	})
	self._content = content

	------------------------------------------------------------------ Resize grip
	local grip = create("TextButton", {
		Parent = main, AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -3, 1, -3),
		Size = UDim2.fromOffset(20, 20), BackgroundTransparency = 1, Text = "◢",
		Font = Enum.Font.GothamBold, TextSize = 14, ZIndex = 6,
		TextXAlignment = Enum.TextXAlignment.Right, TextYAlignment = Enum.TextYAlignment.Bottom,
	})
	self:_register(grip, "TextColor3", "SubText")
	self:_enableResize(grip, main)

	------------------------------------------------------------- Hotkey toggle
	self:_bind(UserInputService.InputBegan:Connect(function(input, gpe)
		if gpe or self._destroying then return end
		if input.KeyCode == self._toggleKey then self:Toggle() end
	end))

	------------------------------------------------------------- Key gate (opt)
	if cfg.KeySystem == true then self:_buildKeyPanel(cfg) end

	-------------------------------------------------------------- Initial state
	self._loading = false
	if self._visible then
		self._main.Visible = true
		local sc = create("UIScale", { Parent = main, Scale = 0.94 })
		tween(sc, { Scale = 1 }, 0.34, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		self:_setBlur(true)
	else
		self._main.Visible = false
	end

	return self
end

return LiquidUI
