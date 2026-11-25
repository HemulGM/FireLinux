# Delphi window settings on Wayland

FMXWayland selects behavior from advertised Wayland protocols and per-window
`xdg_toplevel.wm_capabilities`, rather than guessing from the desktop name. This
works with older xdg-shell versions as well: without a capabilities event the
standard window actions remain available.

| Delphi setting | Behavior |
|---|---|
| `BorderStyle.None` | No client title bar or border; requests client decoration mode to suppress server decorations. |
| `BorderStyle.Single` | Fixed size, title and configured buttons; equal minimum/maximum geometry hints. |
| `BorderStyle.Sizeable` | Resizable regular window. |
| `BorderStyle.ToolWindow` | Fixed size, compact title, no minimize/maximize buttons. |
| `BorderStyle.SizeToolWin` | Resizable tool window, compact title, no minimize/maximize buttons. |
| `BorderIcons` | `biSystemMenu` controls close and the system menu; `biMinimize`/`biMaximize` control the corresponding buttons. Maximizing from the title bar uses the same policy. |
| `Caption` | Unicode title, including runtime updates, sent to xdg-shell and rendered in client decorations. |
| Application `MAINICON` / `FmuxSetWindowIcon` | Encoded images decoded by the existing FMX codec; displayed in the client title and sent through `xdg-toplevel-icon-v1` when advertised. Non-square images retain their aspect ratio inside a transparent square. Nil/empty input resets the icon. |
| `Constraints` | Initial and runtime min/max sizes, forwarded through `IFMXWindowConstraintsService`; zero means unconstrained. FMX sizes include client decorations; protocol hints include window geometry. |
| `WindowState` | Normal, minimized and maximized requests, subject to compositor capabilities and policy. A minimized window can request activation to restore. |
| `FullScreen` | xdg-shell fullscreen request; CSD is hidden while fullscreen. |
| `FormStyle.Popup` | xdg_popup relative to its parent, with compositor placement. |
| Modal forms | Transient parent and application modal event loop. |
| `FormStyle.StayOnTop` | Transient relationship to the main window when available. This keeps a dependent window above its parent according to compositor policy; it cannot promise global topmost status. |
| `Transparency` | Existing ARGB surface path. |
| Bounds / `Position` | Size requests are supported; top-level screen position remains virtual. |

FMX recreates the native handle for regular form `BorderStyle`/`BorderIcons`
changes. The new window receives the current settings. Resize edges and title-bar
double-click actions follow the same policy as the buttons. Capabilities can
remove unsupported minimize/maximize buttons without leaving clickable areas.

## Decoration negotiation

Without `zxdg_decoration_manager_v1` (for example, a compositor offering only
client decorations), FMXWayland draws its own frame. With the protocol, a regular
fully decorated sizeable window requests server decorations. Fixed/tool windows
and custom button sets request client decorations, because xdg-decoration has no
request for an individual server-side button. The compositor's negotiated mode
always wins; if it forces server decorations, its theme and button policy win too.

`FMXWAYLAND_DECORATIONS=client` requests client decorations for every decorated
window. `FMXWAYLAND_CSD=0` disables drawing client decorations, including on
compositors without server decorations.

The icon protocol is optional. Without it the shell can resolve the application
icon from the `.desktop` file matching its app ID; the per-window image is still
available to client decorations. The shell decides where to display icons.

Global topmost/bottom stacking, forced focus, exact top-level coordinates and
Windows-specific nonclient settings have no portable xdg-shell equivalent.
`biHelp` likewise has no standard xdg-shell title-bar action and is not exported
by Delphi's Linux FMUX window-creation API.
Activation is an optional xdg-activation request tied to user input. Size hints
are requests: tiling compositors may override them, and fullscreen/maximized
geometry is chosen by the compositor.

## Validation

`tests/WindowChecks.dpr`, `tests/window-checks.sh` and `tests/window-server.py`
exercise all five styles and four button combinations against five private wire
fixtures: CSD only, negotiated SSD, forced SSD, forced CSD, and xdg-shell v1 without the icon
protocol. Checks cover initial/updated min/max hints, icon pixels and destruction
order, Unicode titles, remapping, button policy and resize hit areas.

`tests/FMXWindowChecks.dpr` exercises the FMX bridge: form creation, runtime
caption, constraints, handle recreation after changing BorderIcons, encoded
image decoding and hide/show. It can be run in a real Wayland session.
To run it against the fixtures, build it with `tools/build.ps1`, then run
`FMX_TEST_FMX=1 sh tests/window-checks.sh <absolute-path-to-FMXWindowChecks>` in Linux.

Protocol reference: [upstream xdg-toplevel-icon XML](https://gitlab.freedesktop.org/wayland/wayland-protocols/-/blob/main/staging/xdg-toplevel-icon/xdg-toplevel-icon-v1.xml).
