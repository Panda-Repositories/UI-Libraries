--[[
    PandaUI — Sample loader

    Fetches the hosted UI library, builds a macOS-style window gated behind
    the key system (V4.3-Cookies primary, V2 fallback), and populates a few
    tabs once the user authenticates.

    Flip LOCAL_TEST to false to point everything at production.
]]

local LOCAL_TEST = true
local SERVICE_ID = "pandadevkit"

local UI_LIB_URL = LOCAL_TEST
    and "http://localhost:4022/ui/lib"
    or  "https://secure.pandauth.com/ui/lib"

-- Load the library (works with executor request fns or game:HttpGet).
local function fetchUiLib()
    local req = (syn and syn.request) or (http and http.request)
        or request or http_request or httprequest
    local body
    if req then
        local ok, resp = pcall(req, { Url = UI_LIB_URL, Method = "GET" })
        if ok and resp then body = resp.Body or resp.body end
    end
    if not body or #body < 100 then
        local ok, res = pcall(function() return game:HttpGet(UI_LIB_URL) end)
        if ok then body = res end
    end
    if not body or #body < 100 then return nil end
    local loader = loadstring(body)
    return loader and loader() or nil
end

local PandaUI = fetchUiLib()
if not PandaUI then
    warn("[Sample] Failed to load PandaUI from " .. UI_LIB_URL)
    return
end

local Window = PandaUI:CreateWindow({
    Title    = "Panda Hub",
    SubTitle = "PandaUI v" .. PandaUI.Version,
    Theme    = "Dark",
    Size     = UDim2.fromOffset(560, 380),

    -- Key system -----------------------------------------------------------
    KeySystem         = true,
    Legacy_Compatible = true,          -- default true → V2 fallback enabled
    ServiceId         = SERVICE_ID,
    Debug             = LOCAL_TEST,

    -- Endpoints (omit the *BaseUrl/Host/V2Url overrides in production) ------
    CookiesLibUrl  = LOCAL_TEST and "http://localhost:4022/cv4/lib" or nil,
    CookiesBaseUrl = LOCAL_TEST and "http://localhost:4022" or nil,
    CookiesHost    = LOCAL_TEST and "localhost" or nil,
    V2Url          = LOCAL_TEST and "http://localhost:3000/v2_validation" or nil,

    OnAuthSuccess = function(info)
        print("[Sample] Authenticated via", info.source,
              "| premium:", info.isPremium,
              "| expires:", info.expiresAt or "never")
    end,
    OnAuthFail = function(info)
        warn("[Sample] Auth failed:", info.error)
    end,
})

-- These tabs are built immediately but stay hidden behind the key gate
-- until authentication succeeds.
local main = Window:CreateTab("Main")
main:CreateLabel("Welcome to Panda Hub. This text wraps automatically and scales cleanly with the macOS-inspired theme.")
main:CreateButton({
    Text = "Say Hello",
    Callback = function() print("[Sample] Hello from the Main tab!") end,
})
main:CreateInput({
    Placeholder = "Type something and press Enter",
    Callback = function(text, enterPressed)
        if enterPressed then print("[Sample] You typed:", text) end
    end,
})

local settings = Window:CreateTab("Settings")
settings:CreateLabel({ Text = "Appearance", Muted = true })
settings:CreateButton({
    Text = "Toggle Light / Dark",
    Callback = function() Window:ToggleTheme() end,
})
settings:CreateButton({
    Text = "Close UI",
    Callback = function() Window:Destroy() end,
})

local about = Window:CreateTab("About")
about:CreateLabel("PandaUI is a modular, OOP UI library with a built-in key system.")
about:CreateLabel({ Text = "Auth order: V4.3-Cookies → V2 (when Legacy_Compatible).", Muted = true })
