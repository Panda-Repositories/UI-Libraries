# PandaUI — macOS-Style UI Library

A clean, modular, object-oriented Roblox (Luau) UI library with a built-in key
system. Modern macOS design language: rounded corners, subtle `UIStroke`
borders, a soft drop shadow, traffic-light window controls, Gotham typography,
and a dynamic Light / Dark theme engine that tweens between themes.

The key system authenticates against the real Panda auth stack:
**V4.3-Cookies first, with an automatic V2 fallback.**

---

## Package contents

```
UI Libraries/MacOS_Style_UILib/
├── PandaUI.lua        ← the UI library (ModuleScript source)
├── Sample.lua         ← a runnable sample / loader script
└── Documentation.md   ← this file
```

> The library is also **hosted** for testing at `GET /ui/lib` on the WebSocket
> Authentication HTTP server (port `4022`). See [Hosting](#hosting).

---

## Features

- **Window** — title bar with macOS traffic-light controls (close / minimize),
  smooth `InputBegan`/`InputChanged` dragging (mouse + touch), soft drop shadow.
- **Tabs** — sidebar navigation; one scrolling content page per tab with a
  slide-in transition.
- **Components** — Button (hover + press animation), Input (placeholder +
  accent focus stroke), Label (auto-wrapping, auto-sizing).
- **Theme engine** — Light / Dark, every themed property cross-fades via
  `TweenService` on toggle.
- **Animations** — window pop-in on open, scale + fade on close, tab slide,
  component hover/press, input focus, theme cross-fade.
- **Key system** — optional key gate; V4.3-Cookies → V2 fallback.
- **Relaunch-safe** — re-running the script destroys the previous window
  instead of stacking duplicates.

---

## Installation / loading

The library is a single ModuleScript. Load it with `loadstring`:

```lua
-- Production
local PandaUI = loadstring(game:HttpGet("https://secure.pandauth.com/ui/lib"))()

-- Local testing (WS-auth server on port 4022)
local PandaUI = loadstring(game:HttpGet("http://localhost:4022/ui/lib"))()
```

> **Executor requirements:** an HTTP request function (`request` /
> `http_request` / `syn.request` / `fluxus.request`) **or** `game:HttpGet`,
> `loadstring`, and a GUI container (`gethui()`, `CoreGui`, or `PlayerGui`).

If you prefer to ship the source yourself, paste the contents of `PandaUI.lua`
into a ModuleScript and `require()` it.

---

## Quick start

```lua
local PandaUI = loadstring(game:HttpGet("http://localhost:4022/ui/lib"))()

local Window = PandaUI:CreateWindow({   -- NOTE: colon ( : ) and a config TABLE
    Title    = "Panda Hub",
    SubTitle = "v1.0",
    Theme    = "Dark",
    KeySystem = false,
})

local main = Window:CreateTab("Main")
main:CreateLabel("Welcome to Panda Hub.")
main:CreateButton({ Text = "Click Me", Callback = function() print("clicked") end })
main:CreateInput({ Placeholder = "Type here", Callback = function(txt) print(txt) end })

local settings = Window:CreateTab("Settings")
settings:CreateButton({ Text = "Toggle Theme", Callback = function() Window:ToggleTheme() end })
```

> **Common mistake:** `PandaUI.CreateWindow("My Title")` (dot + string) will
> error. It is a **method** taking a **table**: `PandaUI:CreateWindow({ Title = "My Title" })`.

---

## Configuration reference

`PandaUI:CreateWindow(config)` accepts the following keys. All are optional
unless your use case requires them.

### General

| Key        | Type     | Default                   | Description |
|------------|----------|---------------------------|-------------|
| `Title`    | string   | `"PandaUI"`               | Title-bar text. |
| `SubTitle` | string   | `nil`                     | Smaller secondary line under the title. |
| `Theme`    | string   | `"Dark"`                  | Initial theme: `"Dark"` or `"Light"`. |
| `Size`     | UDim2    | `UDim2.fromOffset(560,380)` | Window size. |
| `Name`     | string   | `"PandaUI"`               | ScreenGui name (also the relaunch key). |

### Key system

| Key                 | Type    | Default              | Description |
|---------------------|---------|----------------------|-------------|
| `KeySystem`         | boolean | `false`              | If `true`, a key panel gates the UI until authentication succeeds. |
| `Legacy_Compatible` | boolean | **`true`**           | When `true`, falls back to **V2** if V4.3-Cookies fails/unreachable. When `false`, only Cookies is used. |
| `ServiceId`         | string  | `"YOUR_SERVICE_ID"`  | Your Panda service identifier. |
| `Debug`             | boolean | `false`              | Forwarded to the Cookies lib for verbose logging. |
| `ValidationTimeout` | number  | `600`                | Forwarded to the Cookies lib (seconds). |

### Endpoints

Leave the override fields `nil` in production (the library uses the pinned
production hosts). Override them only for local testing.

| Key              | Type   | Default (prod)                              | Description |
|------------------|--------|---------------------------------------------|-------------|
| `CookiesLibUrl`  | string | `https://secure.pandauth.com/cv4/lib`       | Where the V4.3-Cookies lib is fetched from. |
| `CookiesBaseUrl` | string | `nil` (prod default inside Cookies lib)     | Override base URL for the Cookies HTTP protocol (e.g. `http://localhost:4022`). |
| `CookiesHost`    | string | `nil` (prod default inside Cookies lib)     | Override canonical host for Ed25519 identity (e.g. `localhost`). |
| `V2Url`          | string | `https://secure.pandauth.com/v2_validation` | V2 fallback endpoint. |
| `GetKeyBase`     | string | `https://ads.pandauth.com/getkey`           | Base for the constructed Get-Key URL fallback. |

### Callbacks

| Key             | Type     | Description |
|-----------------|----------|-------------|
| `OnAuthSuccess` | function | Called with the [result table](#authentication) on success. |
| `OnAuthFail`    | function | Called with `{ success = false, error = "..." }` on each failed attempt. |

---

## Window API

| Method                  | Description |
|-------------------------|-------------|
| `Window:CreateTab(name)`| Adds a sidebar tab and returns a [Tab](#tab-api). First tab auto-selects. |
| `Window:ToggleTheme()`  | Switches between Light and Dark (cross-fades all themed properties). |
| `Window:SetTheme(name)` | Sets theme explicitly: `"Dark"` or `"Light"`. |
| `Window:Destroy()`      | Plays the close animation, then removes the UI. (Also bound to the red traffic light.) |

The **yellow** traffic light minimizes/restores the window; the **green** one is
decorative.

---

## Tab API

### `Tab:CreateLabel(optsOrString)`

```lua
tab:CreateLabel("Plain text")
tab:CreateLabel({ Text = "Muted caption", Muted = true, TextSize = 13 })
```

| Option     | Type    | Default | Description |
|------------|---------|---------|-------------|
| `Text`     | string  | `""`    | Label text (wraps + auto-sizes height). |
| `Muted`    | boolean | `false` | Uses the `SubText` color instead of `Text`. |
| `TextSize` | number  | `14`    | Font size. |

**Returns:** `{ Set(text), Get() }`

### `Tab:CreateButton(opts)`

```lua
tab:CreateButton({ Text = "Run", Callback = function() print("run") end })
```

| Option     | Type     | Default    | Description |
|------------|----------|------------|-------------|
| `Text`     | string   | `"Button"` | Button label. |
| `Callback` | function | `nil`      | Called (off-thread) on click. |

**Returns:** `{ SetText(text) }`

### `Tab:CreateInput(opts)`

```lua
tab:CreateInput({
    Placeholder = "Search...",
    Callback = function(text, enterPressed) print(text, enterPressed) end,
})
```

| Option        | Type     | Default | Description |
|---------------|----------|---------|-------------|
| `Placeholder` | string   | `""`    | Placeholder text. |
| `Default`     | string   | `""`    | Initial text. |
| `ClearOnFocus`| boolean  | `false` | Clear the text box on focus. |
| `Callback`    | function | `nil`   | Called on focus-lost with `(text, enterPressed)`. |

**Returns:** `{ Get(), Set(text) }`

---

## Theming

Each theme is a flat table of colors. `Window:_register(inst, prop, key)` binds
an instance property to a theme key; on `ToggleTheme`/`SetTheme` every registered
property is tweened to the new theme's value.

| Theme key      | Used for |
|----------------|----------|
| `Accent`       | Selection highlight, focus stroke, primary button. |
| `Background`   | Window body + content area. |
| `Sidebar`      | Tab rail. |
| `Element`      | Buttons. |
| `ElementHover` | Button hover. |
| `Input`        | Text boxes. |
| `Stroke`       | Borders / separators. |
| `Text`         | Primary text. |
| `SubText`      | Secondary / muted text. |
| `Placeholder`  | Input placeholder text. |

---

## Authentication

When `KeySystem = true`, the user must pass a key before the tabs are revealed.

**Order of attempts:**

1. **V4.3-Cookies (primary).** The library fetches the Cookies lib from
   `CookiesLibUrl`, calls `configure` once, then `validate(key)`. This reuses the
   full encrypted, Ed25519-pinned HTTP protocol (path-rotating slug, HMAC-signed
   `__pcs` cookie, AES+HMAC envelope).
2. **V2 (fallback).** Only if `Legacy_Compatible == true`. `POST V2Url` with
   `{ serviceid, hwid, key }`; success when the response `Status == "Authenticate"`.

If both fail, `OnAuthFail` fires and the status line shows
`Cookies: <reason> | V2: <reason>`.

**Result table** passed to `OnAuthSuccess`:

```lua
-- via Cookies
{ success = true, source = "V4.3-Cookies", isPremium = <bool>,
  expiresAt = <iso|nil>, sessionId = <string>, getKeyUrl = <string> }

-- via V2
{ success = true, source = "V2", isPremium = <bool>,
  expiresAt = <string|nil>, note = <string> }
```

The **Get Key** button copies a Get-Key URL to the clipboard (HWID-accurate via
the Cookies lib when available; otherwise constructed from `GetKeyBase`).
Previously saved keys (persisted by the Cookies lib) are pre-filled
automatically.

> **HWID** for the V2 fallback is derived the same way as the Cookies/V2 clients:
> `gethwid()` → `player + executor` → `RbxAnalyticsService:GetClientId()` →
> `player id`.

---

## Hosting

For testing, the library is served raw at:

```
GET http://localhost:4022/ui/lib        (local)
GET https://secure.pandauth.com/ui/lib  (prod, requires nginx location block)
```

- **Server:** the V4.3-Cookies HTTP server inside the WebSocket Authentication
  service (`COOKIES_HTTP_PORT`, default `4022`) — the same server that hosts
  `/cv4/lib`.
- **Handler:** `handleUiLibDelivery` in
  `Websocket_Authentication/src/handlers/cookiesHttp.js`.
- **Route:** wired in `Websocket_Authentication/src/cookiesHttpServer.js`
  (`matchRoute` → `uilib`).
- **Source resolution (candidate paths):**
  1. `Websocket_Authentication/lua/PandaUI.lua` (deploy copy)
  2. `UI Libraries/MacOS_Style_UILib/PandaUI.lua` (repo source)

The file is read fresh from disk on every request (`Cache-Control: no-store`),
so edits are picked up without restarting — except changes to the candidate path
list itself, which require a server reload.

> **Production note:** the V2 fallback endpoint (`/v2_validation`) lives on the
> **backend** service (local port `3000`), not the WS-auth server. For
> `secure.pandauth.com/ui/lib` to work in prod, an nginx `location /ui/` block
> proxying to port `4022` must be added (not configured by default).

---

## Animations & transitions

| Trigger          | Effect |
|------------------|--------|
| Window open      | Scale pop-in (0.92 → 1, Back easing) + shadow fade. |
| Window close     | Scale-down + fade, then destroy. |
| Tab switch       | Incoming page slides up into place. |
| Theme toggle     | All themed properties cross-fade. |
| Button hover     | Background color shift. |
| Button press     | Quick size "press" bounce. |
| Input focus      | Stroke turns Accent + thickens. |
| Key success      | Key panel fades / collapses to reveal tabs. |

---

## Stealth / anti-detection

These libraries don't expose you to **Byfron/Hyperion** (that targets the
executor, not your Lua GUI) and the **server never sees** client-created GUIs
(client instances aren't replicated). The realistic risk is **game-specific
client-side anti-cheats** (LocalScripts) that scan the DataModel for foreign
objects. Built-in mitigations:

- **Randomized names** — the ScreenGui gets a fresh random name each session, so
  name/blocklist scans miss it. (Pass `Name` to force a static name — not
  recommended.)
- **Protected container** — parented via `gethui()` (hidden, scan-resistant),
  falling back to `protect_gui`/`syn.protect_gui` + CoreGui, then PlayerGui.
- **No DataModel breadcrumbs** — the relaunch handle lives in the executor's
  `getgenv()`, which game scripts cannot read. No tag/name is left behind.
- **Full cleanup** — `Destroy()` / relaunch disconnect all input hooks and
  remove the GUI.

**This is not a guarantee of being undetectable**, and none of it hides the
*cheat behavior* in the script itself, which is the usual ban driver.

## Notes & limitations

- Designed for **executor** environments (`loadstring`, HTTP request functions,
  `gethui`). In vanilla Roblox, `loadstring` must be enabled and external HTTP
  allowed.
- The key system needs the auth servers reachable and a valid key; with
  `KeySystem = false` the UI renders standalone (no servers required).
- V4.3-Cookies is **lite mode** — one-shot validation, no live heartbeat or
  mid-session revoke. Use V4.5-Wilkins (WebSocket) if you need those.
- Some executors don't support viewport screenshots via `CaptureService`.

---

## Changelog

**1.0.0**
- Initial release: Window / Tabs / Button / Input / Label, Light-Dark theme
  engine, key system (V4.3-Cookies → V2 fallback, `Legacy_Compatible`),
  open/close/tab animations, relaunch-safe, hosted at `/ui/lib`.
