--[[
    LiquidUI — Sample loader

    Loads the hosted liquid-glass library, builds a resizable frosted window
    behind a blurred background, gated by the key system (V4.3-Cookies → V2).
    Press the toggle key (default Right Ctrl) to show/hide. The window's
    theme, position, size, visibility and toggle flags are saved to disk and
    restored on the next run.

    Flip LOCAL_TEST to false to use production.
]]

local LOCAL_TEST = true
local SERVICE_ID = "pandadevkit"

local LIB_URL = LOCAL_TEST
    and "http://localhost:4022/ui/liquid"
    or  "https://secure.pandauth.com/ui/liquid"

local function fetchLib()
    local req = (syn and syn.request) or (http and http.request)
        or request or http_request or httprequest
    local body
    if req then
        local ok, resp = pcall(req, { Url = LIB_URL, Method = "GET" })
        if ok and resp then body = resp.Body or resp.body end
    end
    if not body or #body < 100 then
        local ok, res = pcall(function() return game:HttpGet(LIB_URL) end)
        if ok then body = res end
    end
    if not body or #body < 100 then return nil end
    local loader = loadstring(body)
    return loader and loader() or nil
end

local LiquidUI = fetchLib()
if not LiquidUI then
    warn("[Sample] Failed to load LiquidUI from " .. LIB_URL)
    return
end

local Window = LiquidUI:CreateWindow({
    Title     = "Liquid Hub",
    SubTitle  = "LiquidUI v" .. LiquidUI.Version,
    Theme     = "Dark",
    Size      = UDim2.fromOffset(600, 420),
    ToggleKey = Enum.KeyCode.RightControl,   -- try Enum.KeyCode.Escape if you prefer
    BlurSize  = 18,
    StealthBlur = false,                     -- blur is OFF by default (stealth);
                                             -- set false to opt in (random-named,
                                             -- Camera-parented, cleaned up)

    -- Key system ----------------------------------------------------------
    KeySystem         = true,
    Legacy_Compatible = true,
    ServiceId         = SERVICE_ID,
    Debug             = LOCAL_TEST,

    -- Endpoints (omit in production) --------------------------------------
    CookiesLibUrl  = LOCAL_TEST and "http://localhost:4022/cv4/lib" or nil,
    CookiesBaseUrl = LOCAL_TEST and "http://localhost:4022" or nil,
    CookiesHost    = LOCAL_TEST and "localhost" or nil,
    V2Url          = LOCAL_TEST and "http://localhost:3000/v2_validation" or nil,

    OnAuthSuccess = function(info)
        print("[Sample] Authed via", info.source, "| premium:", info.isPremium)
    end,
    OnAuthFail = function(info) warn("[Sample] Auth failed:", info.error) end,
})

local main = Window:CreateTab("Main")
main:CreateSection("General")
main:CreateLabel("Welcome to the liquid side. Drag the title bar, resize from the bottom-right, and press Right Ctrl to hide.")
main:CreateButton({ Text = "Say Hello", Callback = function() print("[Sample] hello") end })
main:CreateToggle({
    Text = "Auto Farm",
    Flag = "autofarm",                       -- persisted in the saved config
    Callback = function(v) print("[Sample] autofarm =", v) end,
})
main:CreateInput({
    Placeholder = "Type and press Enter",
    Callback = function(text, enter) if enter then print("[Sample] input:", text) end end,
})

local settings = Window:CreateTab("Settings")
settings:CreateSection("Appearance")
settings:CreateButton({ Text = "Toggle Light / Dark", Callback = function() Window:ToggleTheme() end })
settings:CreateToggle({ Text = "Remember This Setting", Flag = "remember_demo" })
settings:CreateButton({ Text = "Close (and save)", Callback = function() Window:Destroy() end })

local about = Window:CreateTab("About")
about:CreateSection("About")
about:CreateLabel("LiquidUI — frosted glass, blurred background, resizable, hotkey-toggle, config-saving.")
about:CreateLabel({ Text = "Auth: V4.3-Cookies → V2 (when Legacy_Compatible).", Muted = true })
