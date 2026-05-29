# LiquidUI — Liquid-Glass UI Library

A professional, organized Roblox (Luau) UI library with an Apple-inspired
**Liquid Glass** aesthetic: frosted translucent panels over a real blurred 3D
background, rim-lit edges, rounded corners, and drifting "liquid" bubbles.

Same built-in key system as PandaUI — **V4.3-Cookies first, automatic V2
fallback** — plus resizing, a show/hide hotkey, and a config that persists to
disk between sessions.

---

## Package contents

```
UI Libraries/Liquid_Glass_UILib/
├── LiquidUI.lua       ← the UI library (ModuleScript source)
├── Sample.lua         ← a runnable sample / loader script
└── Documentation.md   ← this file
```

Hosted for testing at `GET /ui/liquid` on the WebSocket Authentication HTTP
server (port `4022`).

---

## Feature checklist

- **Liquid-glass design** — translucent frosted panels, rim-light strokes,
  large rounded corners, glass top sheen.
- **Blurred background** — a `Lighting.BlurEffect` blurs the 3D world while the
  UI is open, and animates away when hidden/closed.
- **Liquid bubbles** — soft circular bubbles drift upward behind the glass for
  subtle living motion.
- **Resizable** — drag the bottom-right grip (`◢`); clamped to a min size.
- **Hotkey toggle** — show/hide with a configurable key (default Right Ctrl;
  Escape also possible).
- **Persistent config** — theme, position, size, visibility, and toggle flags
  saved to disk and restored next launch.
- **Light / Dark themes** — cross-faded with TweenService.
- **Key system** — V4.3-Cookies → V2 fallback (`Legacy_Compatible`, default true).
- **Components** — Section, Label, Button, Toggle, Input. Tabs in a sidebar.
- **Relaunch-safe** — re-running replaces the window (and its blur).

---

## Loading

```lua
-- Production
local LiquidUI = loadstring(game:HttpGet("https://secure.pandauth.com/ui/liquid"))()
-- Local testing
local LiquidUI = loadstring(game:HttpGet("http://localhost:4022/ui/liquid"))()
```

> **Executor requirements:** an HTTP request function or `game:HttpGet`,
> `loadstring`, a GUI container (`gethui`/`CoreGui`/`PlayerGui`), and — for
> config persistence — `writefile`/`readfile`/`isfile`. Blur needs write access
> to `Lighting` (wrapped in `pcall`; degrades gracefully if blocked).

---

## Quick start

```lua
local Window = LiquidUI:CreateWindow({   -- colon ( : ) + config TABLE
    Title     = "Liquid Hub",
    Theme     = "Dark",
    ToggleKey = Enum.KeyCode.RightControl,
    KeySystem = false,
})

local main = Window:CreateTab("Main")
main:CreateSection("General")
main:CreateLabel("Welcome.")
main:CreateButton({ Text = "Click", Callback = function() print("hi") end })
main:CreateToggle({ Text = "Auto Farm", Flag = "autofarm", Callback = function(v) print(v) end })
main:CreateInput({ Placeholder = "Search...", Callback = function(t) print(t) end })
```

---

## Configuration reference

`LiquidUI:CreateWindow(config)`:

### General

| Key          | Type        | Default                       | Description |
|--------------|-------------|-------------------------------|-------------|
| `Title`      | string      | `"LiquidUI"`                  | Title-bar text. |
| `SubTitle`   | string      | `nil`                         | Secondary line. |
| `Theme`      | string      | `"Dark"`                      | Initial theme (overridden by saved config). |
| `Size`       | UDim2       | `UDim2.fromOffset(600,420)`   | Initial size (overridden by saved config). |
| `MinSize`    | Vector2     | `Vector2.new(440,300)`        | Minimum resize size. |
| `Name`       | string      | `"LiquidUI"`                  | ScreenGui name + relaunch key + blur name. |
| `ConfigName` | string      | `Name .. "_" .. ServiceId`    | Save-file key (`LiquidUI_<ConfigName>.json`). |
| `ToggleKey`  | KeyCode     | `Enum.KeyCode.RightControl`   | Show/hide hotkey. |
| `StealthBlur`| boolean     | `true`                        | `true` = **no** post-processing effect at all (stealth). Set `false` to opt into a real blur (random-named, Camera-parented, cleaned up). |
| `BlurSize`   | number      | `18`                          | Max blur strength (only used when `StealthBlur = false`). |

### Key system

| Key                 | Type    | Default             | Description |
|---------------------|---------|---------------------|-------------|
| `KeySystem`         | boolean | `false`             | Gate the UI behind a key panel. |
| `Legacy_Compatible` | boolean | **`true`**          | Enable V2 fallback when Cookies fails. |
| `ServiceId`         | string  | `"YOUR_SERVICE_ID"` | Your Panda service identifier. |
| `Debug`             | boolean | `false`             | Verbose Cookies logging. |
| `ValidationTimeout` | number  | `600`               | Forwarded to the Cookies lib. |

### Endpoints (override only for local testing)

| Key              | Default (prod)                              |
|------------------|---------------------------------------------|
| `CookiesLibUrl`  | `https://secure.pandauth.com/cv4/lib`       |
| `CookiesBaseUrl` | `nil`                                       |
| `CookiesHost`    | `nil`                                       |
| `V2Url`          | `https://secure.pandauth.com/v2_validation` |
| `GetKeyBase`     | `https://ads.pandauth.com/getkey`           |

### Callbacks

| Key             | Description |
|-----------------|-------------|
| `OnAuthSuccess` | `function(result)` on success. |
| `OnAuthFail`    | `function(result)` per failed attempt. |

---

## Window API

| Method                   | Description |
|--------------------------|-------------|
| `Window:CreateTab(name)` | Adds a sidebar tab; returns a [Tab](#tab-api). |
| `Window:Toggle([bool])`  | Show/hide (no arg = flip). Animates the panel + blur. Also bound to the hotkey. |
| `Window:Show()` / `Window:Hide()` | Convenience wrappers. |
| `Window:ToggleTheme()`   | Switch Light/Dark (saves config). |
| `Window:SetTheme(name)`  | Set `"Dark"` or `"Light"` (saves config). |
| `Window:Destroy()`       | Animate out, remove blur + UI, disconnect input hooks. |

---

## Tab API

| Method | Options | Returns |
|--------|---------|---------|
| `Tab:CreateSection(text)` | — | `{ Set(text) }` |
| `Tab:CreateLabel(text or {Text,Muted,TextSize})` | — | `{ Set(text), Get() }` |
| `Tab:CreateButton({Text,Callback})` | — | `{ SetText(text) }` |
| `Tab:CreateToggle({Text,Default,Flag,Callback})` | `Flag` persists the value to the saved config | `{ Get(), Set(v) }` |
| `Tab:CreateInput({Placeholder,Default,ClearOnFocus,Callback})` | `Callback(text, enterPressed)` on focus-lost | `{ Get(), Set(text) }` |

**Persistent toggles:** give a toggle a `Flag` string. Its value is written to
the config on change and restored on the next launch (the `Callback` is fired on
restore so your game state matches the UI).

---

## Persistent config

Saved to `LiquidUI_<ConfigName>.json` (default `LiquidUI_<ServiceId>.json`) via
`writefile`. It stores:

```json
{
  "theme":   "Dark",
  "visible": true,
  "pos":     [0.5, -40, 0.5, 12],
  "size":    [600, 420],
  "flags":   { "autofarm": true }
}
```

Written automatically on drag-end, resize-end, theme change, visibility toggle,
and flagged-toggle change. Restored at `CreateWindow`. If `writefile`/`readfile`
are unavailable, the UI still works — it just won't persist.

---

## Authentication

Identical to PandaUI. When `KeySystem = true` a glass key panel gates the UI:

1. **V4.3-Cookies** — fetch lib from `CookiesLibUrl`, `configure` + `validate`.
2. **V2 fallback** — only if `Legacy_Compatible == true`. `POST V2Url` with
   `{ serviceid, hwid, key }`; success when `Status == "Authenticate"`.

`OnAuthSuccess` receives:

```lua
-- Cookies: { success=true, source="V4.3-Cookies", isPremium, expiresAt, sessionId, getKeyUrl }
-- V2:      { success=true, source="V2", isPremium, expiresAt, note }
```

The **Get Key** button copies the Get-Key URL; saved keys pre-fill the box.

---

## Hosting

```
GET http://localhost:4022/ui/liquid        (local)
GET https://secure.pandauth.com/ui/liquid  (prod, needs nginx location block)
```

- **Server:** the V4.3-Cookies HTTP server in the WebSocket Authentication
  service (`COOKIES_HTTP_PORT`, default `4022`).
- **Handler:** `handleLiquidLibDelivery` in
  `Websocket_Authentication/src/handlers/cookiesHttp.js`.
- **Route:** `cookiesHttpServer.js` (`matchRoute` → `uilib_liquid`).
- **Source candidates:** `Websocket_Authentication/lua/LiquidUI.lua`, then
  `UI Libraries/Liquid_Glass_UILib/LiquidUI.lua`.

Read fresh from disk per request (`Cache-Control: no-store`).

> The V2 fallback endpoint (`/v2_validation`) lives on the **backend** service
> (local port `3000`), not the WS-auth server.

---

## Animations & transitions

| Trigger        | Effect |
|----------------|--------|
| Open / show    | Scale pop-in (Back easing) + blur fade-in. |
| Hide / close   | Scale-down + blur fade-out. |
| Tab switch     | Page slides up into place. |
| Theme toggle   | All themed properties + bubbles cross-fade. |
| Button hover/press, input focus | Color / size / stroke transitions. |
| Background     | Liquid bubbles continuously drift upward. |

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
- **Blur off by default** — effects can't be hidden in a protected container, so
  `StealthBlur` defaults to `true` (zero post-processing footprint). Opt in with
  `StealthBlur = false`; even then the effect is random-named and parented to the
  Camera (less commonly scanned than Lighting) and removed on hide/close.
- **Full cleanup** — `Destroy()` / relaunch disconnect all input hooks and
  remove the GUI + any blur.

**This is not a guarantee of being undetectable.** A determined game anti-cheat
can still find a Camera effect, and — most importantly — none of this hides the
*cheat behavior* in the script itself, which is the usual ban driver.

## Notes & limitations

- Built for **executor** environments. With `KeySystem = false` the UI runs
  standalone (no auth servers needed).
- `Escape` as a `ToggleKey` works but may also trigger the Roblox menu in some
  games; Right Ctrl / Insert are safer defaults.
- Blur affects the whole screen (Roblox cannot blur only behind one frame); if a
  game restricts `Lighting`, the panel still renders, just without backdrop blur.
- V4.3-Cookies is lite mode (one-shot validation; no live revoke). Use
  V4.5-Wilkins for live sessions.

---

## Changelog

**1.0.0** — Initial release: liquid-glass Window/Tabs/Section/Label/Button/
Toggle/Input, blurred background, resizable, hotkey toggle, persistent config
(incl. toggle flags), liquid bubbles, key system (Cookies → V2), hosted at
`/ui/liquid`.
