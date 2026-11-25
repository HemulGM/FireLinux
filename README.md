# FMXWayland

A native Wayland platform for Delphi FireMonkey (FMX) on Linux, written in Object Pascal — without Embarcadero's
closed `libfmux.so` and without GTK. FMX programs talk to the Wayland compositor directly (libwayland-client and
libxkbcommon, loaded at run time) and draw into shared-memory buffers with FMX's default Linux canvas (cairo and
Pango, as with libfmux) or, optionally, with its Skia canvas.

When Wayland is unavailable, the same executable falls back to a **native X11 backend** (Xlib, no GTK or libfmux).
See [X11 fallback](#x11-fallback) for selection, dependencies and current limitations.

![The Hello sample on WSLg](docs/screenshots/hello.png)

Phase 1 (this state): an FMX program with the usual controls runs on WSLg, Weston, sway, KWin and GNOME Shell —
windows, popups, mouse, keyboard, clipboard, timers, modal forms, message boxes, file dialogs (the desktop's through
xdg-desktop-portal, FMX's own without one), HiDPI scale (integer and fractional), xdg-activation, server-side or
client-side decorations or a title bar drawn by the program itself
([IFMXWaylandWindowFrame](#ifmxwaylandwindowframe-for-programs-with-their-own-title-bar)), the desktop's font as
FMX's default, on both of FMX's Linux canvases (cairo/Pango and Skia) and on
[FastCanvas](#fastcanvas-vulkan), a GPU canvas that presents to the windows' surfaces through Vulkan
(`VK_KHR_wayland_surface`). See [Dialogs](#dialogs), [Compositors](#compositors), [Status](#status) and
[What does not work](#what-does-not-work-yet).

## How it works

FMX for Linux (`FMX.Platform.Linux`, `FMX.Canvas.Linux`, `FMX.Clipboard.Linux`, `FMX.Skia.Canvas`, ...) calls the
closed library libfmux (a GTK 3 wrapper) through the ~186 function-pointer variables of the unit `FMUX.Api`. The
precompiled FMX units accept another `FMUX.Api` with the same interface section, so FMXWayland generates one at build
time (`tools\gen-fmux-api.ps1`):

- the **interface section** is copied verbatim from the local Delphi installation
  (`$(BDS)\source\fmx\FMUX.Api.pas`). It is Embarcadero's code: the generated file is never committed
  (`.gitignore`);
- the **implementation section** is FMXWayland's: every function pointer first gets a generated stub with the
  declared signature (logs its name once, returns zero/nil/False), then `FMXWayland.Fmux.AssignFmuxApi` assigns the
  implemented functions; the helper routines of the interface (`FmuxStateToShiftState`, `MsgDlgButtonsToButtons`,
  ...) are in `src\FMXWayland.FmuxApi.inc`. There is no libfmux resource and no `dlopen` of libfmux.

The platform logic of `FMX.Platform.Linux` (forms, menus loop, text service, ...) stays Embarcadero's; FMXWayland
implements what libfmux did:

| Unit | What it is |
|---|---|
| `FMXWayland.Fmux` | The FMUX functions: windows (`TFmuxWindow` forwards Wayland events to FMX's callbacks), the paint context, bitmaps, timers, the loop, clipboard, modal loops, message boxes and file dialogs (through the dialog backend), `IFMXWaylandNativeWindow` |
| `FMXWayland.Backend`, `FMXWayland.X11`, `FMXWayland.Xlib` | Startup backend selection and native X11 fallback: dynamically loaded Xlib, XImage presentation, input, eventfd/timers, modal loops and ICCCM clipboard; shares the FMUX canvas, bitmap and dialog implementations |
| `FMXWayland.Cairo`, `FMXWayland.CairoApi` | FMX's default Linux canvas (`FMX.Canvas.Linux`) served by the FMUX canvas, text layout, bitmap codec and font functions on the system's cairo, Pango and gdk-pixbuf (loaded with `dlopen` on first use); contributed by [Hemul GM](https://github.com/HemulGM) |
| `FMXWayland.Platform` | The Wayland side, independent of FMX: connection and globals, outputs, the event loop (display fd + eventfd for wake-ups + timers + watched descriptors, `prepare_read`/`read_events` so other readers such as Vulkan WSI can share the display), `TWlWindow` (xdg_toplevel / xdg_popup, wl_shm double/triple buffering, frame callbacks, damage, scale, client-side decorations, export with xdg-foreign), pointer, keyboard (xkbcommon keymap, key repeat, compose/dead keys), cursors (cursor-shape-v1 or an Xcursor theme through libwayland-cursor), clipboard (wl_data_device) |
| `FMXWayland.Dialogs`, `FMXWayland.DialogTypes`, `FMXWayland.Portal`, `FMXWayland.DBus`, `FMXWayland.FileDialog` | Dialogs behind a replaceable backend: file dialogs through the xdg-desktop-portal FileChooser (over a small D-Bus client in Pascal, no libdbus), FMX's own file dialog form when there is no portal, message dialogs and input queries with FMX's forms (see [Dialogs](#dialogs)); contributed by [Hemul GM](https://github.com/HemulGM) |
| `FMXWayland.Wayland`, `FMXWayland.Xkb`, `FMXWayland.WaylandCursor` | Bindings of libwayland-client, libxkbcommon, libwayland-cursor, loaded with `dlopen`: programs start without link-time dependencies and say what is missing |
| `src\Protocols\FMXWayland.Protocol.*` | Generated from the protocol XML files in `protocols\` by `tools\gen-wayland.ps1`, a small wayland-scanner for Pascal |
| `FMXWayland.Keys` | XKB keysyms / evdev codes -> FMX virtual keys |
| `FMXWayland.Native` | `IFMXWaylandNativeWindow`, the contract for GPU canvases (below) |
| `FMXWayland.FmuxLoad` | Calls `FMUX.Api.LoadLib` from `FMUX.Api`'s implementation uses, before FMX's units that call the FMUX functions initialize, whatever unit a program reaches first (the cycle `FMUX.Api` → `FMXWayland.Fmux` → FMX → `FMX.Platform.Linux` → `FMUX.Api` otherwise let `FMX.Platform.Linux` call `FmuxSetLog` while it was nil) |
| `FMXWayland.Frame` | `IFMXWaylandWindowFrame`, the contract for programs that draw their own title bar (below) |
| `FMXWayland.SystemFont` | FMX's `IFMXSystemFontService`: the default font of `TFont` (GNOME's `font-name` through the settings portal, else fontconfig's `sans-serif`) |

**Painting on Wayland.** Both of FMX's Linux canvases work; the frames go to the compositor as wl_shm buffers, attached with the
damaged rectangle and committed; frame callbacks pace the repaints.

- **FMX's default canvas** (`FMX.Canvas.Linux`, `TLinuxCanvas`: what an FMX program uses unless it sets
  `GlobalUseSkia`) calls the FMUX canvas functions (paths, fills, strokes, gradients, clips, bitmaps), text layouts and
  bitmap codecs. libfmux implemented them with cairo, Pango and gdk-pixbuf; `FMXWayland.Cairo` does the same on the
  system's libraries. The paint context is a cairo context over the window's retained frame: FMX repaints only the
  damaged region, and each wl_shm buffer (they rotate, so a buffer holds an older frame) gets the regions that changed
  since its frame. Text is antialiased in grayscale (a Wayland client does not know the subpixel order of the screen).
- **The Skia raster canvas** (`FMX.Skia`, `GlobalUseSkia := True`, `libsk4d.so` next to the program) gets the frame
  as its context, renders the window into an FMUX bitmap (plain memory) and copies it with `FmuxCanvasDrawBitmap`.
- **A GPU canvas** that presents itself ([FastCanvas](#fastcanvas-vulkan): Vulkan through `VK_KHR_wayland_surface`)
  takes the window's `wl_surface` through [IFMXWaylandNativeWindow](#ifmxwaylandnativewindow-contract-for-gpu-canvases)
  and turns FMXWayland's frames off for it; FMXWayland keeps the window's viewport, geometry and decorations in step
  with the commits of the canvas's presenting thread.

The two draw the same layout; antialiasing, hinting and Pango's line spacing differ a little
(`tests\canvas-check.ps1` puts both side by side, below).

See [Wayland window settings](docs/window-management.md) for border styles, icons, size constraints and decoration negotiation.

## X11 fallback

Initial X11 support; see [scope, known issues and reproducible checks](docs/X11.md).

The backend is chosen at startup, before FMX creates any windows:

| `FMXWAYLAND_BACKEND` | Behaviour |
|---|---|
| unset or `auto` | Prefer a reachable Wayland compositor; fall back to X11 if the transport or required compositor globals are unavailable. |
| `wayland` | Require Wayland; fail rather than fall back. |
| `x11` | Use X11 directly, including XWayland when `DISPLAY` points to it. |

```sh
./Hello                              # automatic selection
FMXWAYLAND_BACKEND=x11 ./Hello       # requires a working DISPLAY
FMXWAYLAND_BACKEND=wayland ./Hello   # Wayland only
```

X11 loads `libX11.so.6` on demand and uses `libxkbcommon.so.0` for Unicode/compose input. Cairo/Pango and Skia
use the existing rendering paths; frames are uploaded with `XPutImage`. There is no dependency on libfmux or GTK,
and a Wayland-only deployment does not need Xlib. Loss of a display connection after startup does not migrate
existing windows to another backend.

The X11 backend supports toplevels and popups, window-manager decorations, movement/resizing, maximize/minimize,
fullscreen requests, mouse/capture/wheel, keyboard shortcuts and compose, timers and main-thread wake-ups,
modal forms, UTF-8 text clipboard (including cross-process INCR transfers), and the existing dialogs. Portal
dialogs receive an `x11:<window-id>` parent. Incoming clipboard transfers are limited to 16 MiB and five seconds.

Transparent forms and popups use an ARGB32 visual with a matching colormap and image depth when a compositor
is present (`libXrender.so.1` validates the alpha format). Without a compositor, the Shape extension
(`libXext.so.6`) clips transparent padding; that fallback has binary transparency rather than soft shadows.

**Current X11 limitations:** scale is 1 and the X screen is reported as one display (no per-monitor RandR/HiDPI);
window rectangles describe the client area; no XIM/IME. Vulkan presentation through `IFMXWaylandNativeWindow`
remains Wayland-only; the supported X11 canvases are Cairo and Skia.

**Custom title bars:** the X11 backend also provides the existing `IFMXWaylandWindowFrame` contract (the name/GUID
is retained for compatibility with FMR Ribbon). It hides/restores WM decorations, reports active/maximized state,
and supports move, resize, minimize and maximize/restore. Modern WMs receive EWMH move/resize/state requests;
legacy WMs such as Xming use pointer-grab-driven move/resize and client-side maximize/restore. The WM menu is
advertised only when `_GTK_SHOW_WINDOW_MENU` is available. FMR Ribbon's Linux frame attaches to this service
automatically: build `Demos/RibbonBasic` against this checkout and run with `/frame=fullnc`.

**Tests:** build Hello with and without `-Define SKIA`, then run
`bash tests/x11-headless.sh <output-directory> <absolute-path-to-Hello>` on Linux with Xvfb, Openbox, xcompmgr, xdotool,
xclip, xrandr, ImageMagick, Python 3 and libXfixes. It checks automatic/forced selection, the Hello self-test, real
mouse/keyboard input, clipboard exchange with xclip, resize and WM close, and saves screenshots.
`tests/x11-modal.sh` also opens and dismisses message boxes and modal forms with mouse clicks, verifies blocked
parent input, and checks cursor visibility and stable cursor identity during movement (`x11-cursor.py`).
`x11-popup.sh` checks that a ComboBox list actually stays visible, including when the WM gives it keyboard focus
(Weston/WSLg), then exercises mouse selection, outside-click dismissal and keyboard selection. Hello's greeting,
renderer description and message box use the selected backend name (`Hello, X11!` / `XPutImage` on X11).
`x11-alpha.py` checks the popup's drawable alpha or non-composited Shape outline. With `xcompmgr` installed,
`X11_START_COMPOSITOR=1` enables the composited path in `x11-modal.sh` (run on a private X display).
`x11-frame.sh` checks the custom-title-bar service: drag, edge resize, maximize/restore, minimize and close;
`X11_LEGACY_WM=1` on a private test display hides `_NET_SUPPORTED` to exercise the legacy-WM fallbacks.
Optionally build
`tests/BackendCheck/BackendCheck.dpr` and pass its executable as the third argument to also test the Xlib LP64 ABI,
early clipboard-unit initialization, large UTF-8 clipboard transfers in both directions, popup override-redirect
at **creation** (as observed by the WM), and live screen/work-area resize. On WSLg, whose
`/tmp/.X11-unix` is read-only, run the tests in a private mount namespace with a writable tmpfs at that path.
The test server uses display numbers 90–189 to avoid intercepting WSLg's `:0` socket. `BackendCheck coordinates`
checks coordinate conversion against X11 after moving a window, reparenting it into nested WM frames and moving
those frames without client configure notifications, and measures 10,000 conversion pairs. Mouse hit-testing
uses the client origin cached from client/ancestor events and input coordinates, without per-control X server
round-trips. Synthetic ICCCM configure positions are authoritative; the tests also cover a compositor screen
position different from the virtual X window tree, including subsequent frame movement and pointer input.
Root geometry changes update the screen bounds instead of retaining Xlib's initial screen size (WSLg may start
at 640x480). Popup windows are created with override-redirect already set, so Weston does not cache them as
managed toplevels before their first map.
The popup test checks its position relative to the combo before and after moving the owner. For WSLg manual
tests, move windows by dragging their title bars: moving only the Windows-side RDP window with `SetWindowPos`
can desynchronize it from the compositor's position.

**Coordinates.** Wayland clients do not know where their windows are. Every window keeps a virtual origin (what FMX
set with `SetWindowRect`); `ClientToScreen`/`ScreenToClient` and the screen positions of mouse events use it, so
FMX's own conversions stay consistent. Popups (combo box lists, popup menus — FMX forms with `FormStyle = Popup`)
become xdg_popups placed relative to their parent (the form of their placement target) and take the position the
compositor gives them.

**Decorations.** With `zxdg_decoration_manager_v1` the compositor draws the title bar (KWin, sway). Without it
(WSLg, Weston, GNOME), or when the compositor answers "client-side" (sway with `border csd`), FMXWayland draws
client-side decorations: a subsurface around the window with the title (rendered by FMX's canvas), minimize/maximize/
close buttons (those the window manager offers in `xdg_toplevel.wm_capabilities`: sway has neither maximize nor
minimize), moving, resizing at the edges and the window menu. FMX's form rectangle includes them, like a frame on
other platforms. `FMXWAYLAND_CSD=0` turns them off; a program can turn off both kinds for a window and draw its own
title bar ([IFMXWaylandWindowFrame](#ifmxwaylandwindowframe-for-programs-with-their-own-title-bar)). A press on the
title starts the compositor's interactive move only when the pointer is dragged past 4 pixels (as GTK does), so a
click or a double click stays the window's.

**Fonts.** FMX's default font (`TFont`, every control whose style names no family) is the desktop's
(`IFMXSystemFontService`; without it FMX falls back to "Tahoma", which Linux systems do not have: Skia then fell back
to "Ubuntu", Pango to fontconfig's default). In a GNOME session (`XDG_CURRENT_DESKTOP` lists GNOME) it is GNOME's
interface font, `org.gnome.desktop.interface font-name` ("Adwaita Sans 11"), read through the settings portal
(`org.freedesktop.portal.Settings`, `ReadOne` or the older `Read`, over the D-Bus client of the dialogs): the family
as fontconfig resolves it (a substitute when that family is not installed), the size converted from points to FMX's
device-independent pixels (11 pt = 14.7, as Windows reports its 9 pt message font as 12). Elsewhere, without a
portal (it is given 1.5 seconds) or with `FMXWAYLAND_PORTAL=0`, it is the desktop's sans-serif font as fontconfig
resolves it at FMX's default size of 12 (libfmux registers no such service: FMX used 12 there too).
`FMXWAYLAND_FONT="family[,size]"` overrides both.

## Dialogs

`TOpenDialog`, `TSaveDialog` and `SelectDirectory` (FMX calls `FmuxFilesDialog`) and FMX's synchronous message
dialogs (`FmuxMessageDialog`) go to a **dialog backend** (`FMXWayland.Dialogs`, `IFMXWaylandDialogBackend` in
`FMXWayland.DialogTypes`). The default one:

- **File dialogs through xdg-desktop-portal** (`org.freedesktop.portal.FileChooser`, the desktop's own dialog: GNOME,
  KDE, GTK), over a private connection to the session bus made by a small D-Bus client in Pascal
  (`FMXWayland.DBus`: Unix socket, SASL EXTERNAL, the wire format; no libdbus). Filters, the chosen filter, the
  initial folder and name, multiple selection, folders (FileChooser version 3) are passed on. The program's window is
  exported with **xdg-foreign** (`zxdg_exporter_v2`) and named as the dialog's parent (`wayland:<handle>`), so the
  compositor keeps the dialog above it (GNOME, KWin, sway have it; without it the parent is ''). While the dialog is
  open the program's loop goes on (painting, timers, threads: the bus socket is one more descriptor of the event
  loop's poll) and its windows take no input, as under a modal form. When the program ends meanwhile, its request is
  closed and the dialog goes away.
- **FMX's own file dialog** (`FMXWayland.FileDialog`, an FMX form: folders and files with the filter, hidden files,
  new folder, the location typed, multiple selection, overwrite question) when there is no portal: no session bus,
  no xdg-desktop-portal, no FileChooser in it, folder selection with FileChooser before version 3, or
  `FMXWAYLAND_PORTAL=0`. The fallback is immediate when the portal is not there (the bus says so); a portal that does
  not answer is given 5 seconds.
- **Message dialogs** with FMX's own dialog form, as before.

Another backend replaces it (for example own forms), and then also serves `TDialogService` (message dialogs and input
queries, synchronous and asynchronous); `nil` restores the default:

```pascal
uses FMXWayland.Dialogs, FMXWayland.DialogTypes;

type
  TMyDialogs = class(TFMXWaylandDialogBackend)
  public
    function FileDialog(const Request: TWaylandFileDialogRequest; out Files: TArray<string>;
      var FilterIndex: Integer): Boolean; override;
  end;

SetWaylandDialogBackend(TMyDialogs.Create);
```

Limits: FMX reads the result of `FmuxFilesDialog` from a buffer of 1024 characters, so a multiple selection keeps
the names that fit (a warning in the log names how many); `GetWaylandDialogBackend.FileDialog` has no such limit. The
portal's dialogs ask before overwriting whatever `ofOverwritePrompt` says (GTK and KDE always do). Under GNOME
50 the portal's file dialog is Nautilus (xdg-desktop-portal-gnome hands it over), which refuses to run as root.

| GNOME Shell 50: the portal's dialog (GTK) as a child of the program's window | KWin 6.6: the portal's dialog (KDE) | FMX's own file dialog (no portal) |
|---|---|---|
| ![GNOME](docs/screenshots/gnome-portal-open.png) | ![KWin](docs/screenshots/kwin-portal-open.png) | ![FMX](docs/screenshots/fmx-file-dialog.png) |

## Requirements

- Delphi 13 (RAD Studio 37.0) with the Linux platform (Enterprise/Architect) and FMX for Linux with its sources:
  in Delphi 13.0 part of the product (`source\fmx\FMUX.Api.pas`, units in `lib\linux64`), in later releases (13.1) a
  GetIt package in the catalog repository. `tools\delphi-env.ps1` finds the `FMUX.Api.dcu` the build uses (the
  Linux64 library path of the IDE, then the catalog repository, then `lib\linux64`) and the `FMUX.Api.pas` next to it:
  the generated interface must be the one those precompiled FMX units were compiled with. `gen-fmux-api.ps1 -Source`
  overrides it.
- A Linux platform SDK to link against: `tools\make-linux-sdk.ps1` makes one from a WSL distribution (or use the
  IDE's SDK manager). The default is Ubuntu 22.04's: programs need glibc 2.35 or later (Ubuntu 22.04+, Debian 12+,
  Fedora 36+, ...; see [Tests](#tests), `tests\glibc-compat.ps1`).
- At run time: a Wayland compositor with `wl_compositor`, `wl_shm` and `xdg_wm_base`; the libraries
  libwayland-client0 and libxkbcommon0 (libwayland-cursor0 for cursors on compositors without cursor-shape-v1); for
  FMX's default canvas cairo, Pango, pangocairo and gdk-pixbuf with fontconfig and fonts (Debian/Ubuntu: `libcairo2
  libpango-1.0-0 libpangocairo-1.0-0 libgdk-pixbuf-2.0-0`, present on any desktop); with the Skia canvas instead,
  `libsk4d.so` (Skia, `$(BDS)\Redist\linux64`) next to the program. Native X11 fallback uses the system libX11. GTK and libfmux are unnecessary. For the desktop's file
  dialogs a session bus with xdg-desktop-portal and a backend with a FileChooser (xdg-desktop-portal-gnome,
  -kde, -gtk; any desktop has one); without them FMX's own file dialog is used.

## Using it in a project

1. Generate `FMUX.Api.pas` (`.\tools\gen-fmux-api.ps1 -Out <dir>\FMUX.Api.pas`) and put `<dir>`, `src` and
   `src\Protocols` **first** on the unit search path (the IDE/`dcclinux64` then compile it instead of linking
   Embarcadero's precompiled `FMUX.Api`).
2. That is all for FMX's default canvas (cairo). For the Skia canvas instead, in the .dpr:

   ```pascal
   uses
     System.StartUpCopy, FMX.Forms, FMX.Types, FMX.Skia, MainForm in 'MainForm.pas';
   begin
     GlobalUseSkia := True;
     Application.Initialize;
     ...
   ```

`samples\Hello\Hello.dproj` runs `tools\prepare-ide-build.ps1` before Linux64 compilation. Use `-FmxLinux` with the command-line builder to select a particular GetIt package.

## 3D: OpenGL

`FMXWayland.OpenGL` provides the native context functions used by the stock
`FMX.Context.Linux` renderer. `TViewport3D` supports FMX meshes, shaders, lit and textured
materials, depth/stencil buffers and multisampling. Rendering uses offscreen FBOs;
FMX reads the BGRA result into its bitmap and Cairo composites it with the 2D controls.
Main and worker contexts share textures and other shareable GL objects. Native resources
are released on shutdown after the program joins its OpenGL worker threads.

This uses the system `libEGL.so.1` and `libGL.so.1`, desktop compatibility OpenGL and `EGL_KHR_surfaceless_context`.
The active backend determines which EGL platform extension is used, `EGL_EXT_platform_wayland` or `EGL_EXT_platform_x11`.
Initialization is deferred until a 3D context is requested.
The demo's **3D / OpenGL** tab (`--tab=3d`) shows a textured rotating cube, a lit sphere,
a camera, and pause/reset controls.

Build `tests\OpenGLChecks.dpr` with `tools\build.ps1 -SearchPath samples\Hello`, then run
it in a Wayland or X11 session. It checks BGRA readback, worker texture sharing, viewport
pixels, rotation, resizing and multisample recreation.

This is the offscreen `TViewport3D` path. Direct presentation for `TForm3D` through
`FmuxFlushBuffer` remains future work. A separate Vulkan context is available below. Native context
creation is isolated from Cairo and the Wayland window implementation so another
renderer can register its own context through FMX's `TContextManager`.

## 3D: Vulkan

`FMXWayland.Vulkan.TVulkanContext` is a native Vulkan 1.0 `TContext3D`. It renders
`TViewport3D` offscreen and composites the BGRA readback with Cairo. It uses the
system `libvulkan.so.1`; it does not create an OpenGL/EGL context or require a
Wayland swapchain. OpenGL remains the default. In the Hello demo select at startup:

```sh
./Hello --tab=3d --3d=vulkan
./Hello --tab=3d --3d=opengl
# Alternative for the demo: FMXWAYLAND_3D_BACKEND=vulkan ./Hello --tab=3d
```

For another application, add `FMXWayland.Vulkan` to uses and call
`RegisterVulkanContext` after `Application.Initialize`, **before** creating forms,
materials, textures or contexts. It replaces only `IFMXContextService`; other
Wayland platform services stay in place. Switching backends while resources exist
is unsupported because FMX shader and texture handles belong to one selected backend.

Implemented: indexed triangles/lines/points (16/32-bit indices), FMX color/texture/light
materials (up to eight directional, point or spot lights), camera/model matrices,
premultiplied blending, depth/stencil, color write masks, face culling, scissor,
nearest/linear filtering and generated mipmaps. Two/four-sample MSAA resolves into
the texture; the actual count is limited by the device and attachment formats.
BGRA textures can be sampled across contexts after `EndScene`; sampling the active
render target raises an error. Texture replacement preserves images referenced by
already recorded draws until their submission fence signals.

`FMXWayland.VulkanDevice` owns the device, coherent staging buffers, images, barriers
and submission fences. The first implementation submits and waits per completed
scene for CPU readback; queue/command-pool operations are serialized. FMX scene and
material manipulation should remain on the UI thread. This is the offscreen
`TViewport3D` path; native-window `TForm3D` presentation is not implemented. Pixel
textures are BGRA/premultiplied, with one texture sampler per material. Other formats
and unsupported shader names fail explicitly instead of falling back to OpenGL.

Built-in SPIR-V is embedded in `src/FMXWayland.VulkanShaders.inc`; a normal Delphi
build needs no Vulkan SDK or shader compiler. The original GLSL is in `shaders/`.
To rebuild it, use `tools/build-vulkan-shaders.ps1` with the `glslangValidator` CLI
and Python 3. Neither tool is shipped with or loaded by the application.
Custom shaders can use `RegisterVulkanShader(Shader, SPIRV)` before initialization;
they must use the vertex layout and descriptor ABI in `shaders/viewport.*` and
`TVulkanUniforms`. The context exposes the standard FMX material uniform names plus
`VulkanParams` for the final parameter vector. Arbitrary GLSL source is not compiled
at runtime. See the custom material in `tests/VulkanChecks.dpr` for an example.

Build and run the checks in an existing Wayland session:

```powershell
.	oolsuild.ps1 -Project tests\VulkanChecks.dpr -SearchPath samples\Hello
```
```sh
# Optional: install/configure the Khronos validation layer, then set
# FMXWAYLAND_VULKAN_VALIDATION=1. Missing requested validation layers are an error.
sh tests/vulkan-checks.sh /path/to/VulkanChecks
```

The tests check actual pixels for depth, stencil, blending, clipping, texture
orientation/filtering/mipmaps, updates during recording, render-to-texture, partial
readback and custom SPIR-V, plus the demo's lit meshes, resize and MSAA recreation.
The wrapper also fails on Vulkan validation errors. Tested on WSLg without DISPLAY,
Mesa lavapipe (LLVM 12.0.0), with Khronos validation enabled. Hardware Vulkan adapters
have not yet been tested in this environment.

The implementation follows the Khronos [render pass](https://docs.vulkan.org/spec/latest/chapters/renderpass.html)
and [synchronization](https://docs.vulkan.org/spec/latest/chapters/synchronization.html) specifications.

## Building

```powershell
.\tools\make-linux-sdk.ps1 -CreateDistro -Install    # once: libc, crt*.o, libgcc, libz of Ubuntu 22.04 (WSL)
.\tools\build.ps1 -Project samples\Hello\Hello.dpr   # Release; -Config Debug
.\tools\build.ps1 -Project samples\Hello\Hello.dpr -Define SKIA -BuildRoot D:\Work\FMXWayland-build\skia
.\tools\build.ps1 -Project samples\Hello\Hello.dpr -Define FASTCANVAS -BuildRoot D:\Work\FMXWayland-build\fastcanvas `
  -SearchPath F:\Projects\FMXFastCanvas\src\Canvas,F:\Projects\FMXFastCanvas\third_party\pasvulkan\src
```

Hello uses Cairo by default. Use `-Define SKIA` for its Skia raster canvas.

The SDK decides the oldest glibc the program runs with. `make-linux-sdk.ps1` copies it out of a WSL distribution
(default `Ubuntu-22.04` into `D:\LinuxSDK\ubuntu-22.04`; `-CreateDistro` installs the distribution first when it is
missing, without the first-run prompt: `wsl --install -d Ubuntu-22.04 --no-launch --web-download --location
D:\WSL\Ubuntu-22.04`; `-Install` installs `libc6-dev`, `libgcc-<n>-dev` and `zlib1g-dev` in it). The optional
`libsk4d.so` also has a glibc requirement determined by the Delphi redistributable. The RAD Studio 37.0 copy used
here requires glibc 2.35. Another SDK stays selectable:
`make-linux-sdk.ps1 -Distro Ubuntu-26.04 -Install` makes `D:\LinuxSDK\ubuntu-26.04` (glibc 2.43), `build.ps1 -Sdk
D:\LinuxSDK\ubuntu-26.04` links against it.

`build.ps1` generates `FMUX.Api.pas` into `<BuildRoot>\gen`, compiles with `dcclinux64` (linking with its lld against
the SDK: `--syslibroot`, `--libpath`), copies `libsk4d.so` next to the program when it links FMX's Skia units (its
map file lists `System.Skia.API`; a program on FMX's default canvas needs none). Everything goes to `-BuildRoot`
(default `D:\Work\FMXWayland-build`: `bin\Linux64\<Config>\`, `dcu\`). It also works around the missing Linux64
`FMX.Filter.res` of Delphi 13. msbuild builds the .dproj too, given the SDK:

```
msbuild samples\Hello\Hello.dproj /p:Config=Release /p:Platform=Linux64 /p:DCC_SysLibRoot=<sdk>
  /p:DCC_LibraryPath=<bds>\lib\linux64\release%3B<sdk>\usr\lib\x86_64-linux-gnu%3B<sdk>\usr\lib\gcc\x86_64-linux-gnu\<n>
```

The protocol units are committed; after adding or updating an XML file in `protocols\` run `.\tools\gen-wayland.ps1`.

## Running

On WSLg (Windows 11, WSL 2):

```sh
export XDG_RUNTIME_DIR=/mnt/wslg/runtime-dir WAYLAND_DISPLAY=wayland-0
unset DISPLAY
./Hello --verbose
```

Environment variables: `FMXWAYLAND_LOG` = 0 errors only, 1 warnings and "not implemented" notes (default), 2 debug,
3 input traces; `FMXWAYLAND_DUMP_DIR=<dir>` writes the latest frame of each window as a BMP (debugging);
`FMXWAYLAND_CSD=0` no client-side decorations; `FMXWAYLAND_APP_ID` the xdg app id (default: the program name);
`FMXWAYLAND_PORTAL=0` FMX's own file dialogs instead of the portal's (and no settings portal for the font);
`FMXWAYLAND_FONT="family[,size]"` FMX's default font (size in device-independent pixels); `XCURSOR_THEME`,
`XCURSOR_SIZE` for cursor themes.

## IME and CJK input

`FMXWayland.TextInput` binds `zwp_text_input_manager_v3` (interface version 1), follows its seat/surface focus,
and enables input when an editable FMX control gains focus. Preedit, committed text and surrounding deletion
are buffered until `done`; control changes discard old responses, while stale serials within one session apply
text without prematurely publishing a new state. The FMUX start/change/commit callbacks update FMX composition.
`TEdit` and `TMemo` supply surrounding text, selection and the actual caret rectangle in logical surface units.
UTF-8 indices are converted to UTF-16 safely, with a 4000-byte surrounding window. State updates reflect text,
caret movement and scrolling. Standard FMX disables IME for password fields; no password surrounding text is sent.
Read-only and disabled-IME controls do not enable the protocol. No new runtime binary library is required.

The session must offer text-input-v3 and have an input method integrated with its compositor. The current WSLg
used for this project advertises `zwp_text_input_manager_v1`, not v3: v3 cannot activate there. Without v3,
keyboard/xkb compose still works. A v1 adapter is not implemented. CJK glyph rendering already uses Pango's font
fallback, independently of IME; the system needs fonts covering the requested characters.

The stock FMUX callbacks carry the preedit string but no cursor/segment attributes. The existing FMX Linux text
service therefore draws its standard composition decoration; exact intra-preedit selection/cursor styling is
not forwarded. See the vendored `protocols/text-input-unstable-v3.xml` for the protocol contract.

`tests\TextInputChecks.dpr` exercises real Wayland messages against a private Python standard-library fixture;
`tests\FMXImeChecks.dpr` routes those messages through real FMX controls. Build the latter with
`-SearchPath samples\Hello`, then run `sh tests/text-input-checks.sh <binary> fmx` (or `memo`, `password`,
`readonly`). Use `core` for TextInputChecks. Tests need no desktop input, IME installation or extra server library.

## Main menus on Wayland

`TMainMenu` is supported through `FMXWayland.Menus`, an `IFMXMenuService` adapter. Core Wayland/xdg-shell has no
API for creating an OS-drawn application menu bar; clients draw the contents of their surfaces. The backend renders
the standard `TMainMenu` tree with a client-side FMX `TMenuBar` and native Wayland `xdg_popup` surfaces for submenus.
Menus use standard FMX drawing. KDE global menus require a separate compositor-specific appmenu/D-Bus integration;
this backend currently draws the bar inside the application's window.

Keep using streamed `TMainMenu` and `TMenuItem` components. The application tree retains its identity and ownership:
the visual projection forwards clicks to the original items, so Action, OnClick and AutoCheck execute once.
Nested menus, separators, Enabled/Visible, checked/radio groups, images and shortcuts are reflected in the view.
Captions/state update live; structural changes made inside an open menu are rebuilt after its popup loop closes.
F10 opens the menu; ampersand mnemonics work with Alt. Arrows, Home/End, Enter/Space, Escape and command shortcuts
work inside the popup. Layout uses a streamed `TFrame` with `Align = MostTop`, reserving a 32-unit row above the
form's other aligned controls. The frame and its menu bar are defined in `FMXWayland.Menus.fmx`.

The service is installed by the standard `Application.Initialize` chain, after the stock platform services and
before forms cache their menu service. `FMXWayland.Fmux` links the unit automatically. `InstallWaylandMenuService`
is also available explicitly for custom application startup. The legacy FMUX menu function pointers remain stubs
and are bypassed by this platform service. Existing `TMenuBar` and `TPopupMenu` controls continue to use FMX.

The Hello demo includes File, View, Options and Help menus in its FMX resource, with an Action, nested tab selection,
radio items and dynamic availability. `tests/MainMenuChecks.dpr` checks commands, shortcuts, state, source lifetime
and mapped nested `xdg_popup` surfaces on WSLg without injecting desktop input. Build with `-SearchPath samples/Hello`.

## Drag and drop

Drag/drop uses `wl_data_device`, with no GTK or additional binary dependency. Receive `text/plain` (UTF-8)
and `text/uri-list` through normal FMX `OnDragOver`, `OnDragDrop`, `OnDragEnter`, `OnDragLeave` events.
An `OnDragOver` handler accepts a target by setting `Operation` to `Copy` or `Move`; otherwise the drop is rejected.
URI lists support multiple local files, percent-encoded Unicode paths and comments. Remote file hosts, NUL,
invalid URI escapes and malformed UTF-8 are rejected. Files are passed as paths; the application performs any
file copy/move itself. `Link` and `Ask` are not offered.

Outgoing drags use the registered `IFMXDragDropService.BeginDragDrop(Form, DragObject, Bitmap)` or FMX automatic
drag mode. This service preserves `Source`, `Files` and `TValue` for drags between this process's controls/windows;
automatic drags also read the source's `Data`. A string `Data` and the file list are exported to other Wayland
applications. Other `TValue` types remain within the process. The optional bitmap is displayed as a drag icon
(up to 512 × 512 pixels). `OnDragEnd` runs once on finish/cancel, unless the source is destroyed.

Start from a live pointer press: Wayland refuses a keyboard serial or a programmatic drag without a grab.
Incoming drags support data-device versions 1–3; outgoing drags require v3 for reliable `dnd_finished` notification.
Pipe reads/writes run asynchronously in the event loop, including transfers larger than the pipe capacity.
Receives are limited to 64 MiB, with a 10-second inactivity timeout. Clipboard and drag sources are separate.
WSLg interoperability with Windows applications depends on its compositor/RDP implementation.

The demo's Drag & Drop tab sends editable text or selected files, and receives either in the highlighted area.
Use `--tab=drag` to open it. Build `tests/DragDropChecks.dpr` with `-SearchPath samples/Hello`, then run
`sh tests/drag-drop-checks.sh <binary> <mode>`: `text`, `files`, `move`, `reject`, `leave`, `legacy`, `internal`,
`outgoing`, `automatic`, `cancel`, `internal-cancel`, `sourcegone`, `bad-utf8`, `no-grab`. The private wire fixture checks FMX events, 1 MiB UTF-8
transfers, URI conversion, action negotiation, finish/leave ordering, cancellation and source lifetime without
touching desktop input.

## Tests

The `samples\Hello` demo has six tabs: controls, animations/images, dialogs, windows/platform, drag/drop, and 3D (OpenGL or Vulkan).
All static controls, timers, animations and dialog components are streamed from `HelloMain.fmx`;
independent and modal windows share `HelloWindow.fmx`. The existing WinUI3 style book is preserved.
Layouts use `Align`, `TLayout`, and scroll boxes. Add future sections as new `TTabItem` children of `DemoTabs`.
The dialog page switches between automatic Portal → FMX selection and the pure FMX backend. PNG/JPEG samples
are embedded in the form; the originals in `samples\Hello\assets` need no deployment entries.
Use `--tab=images|dialogs|platform|drag|3d` to select the initial page, or `--selftest` for the integration checks.
With `--verbose`, the demo logs actual control centers; the real-input test uses these instead of fixed coordinates.
`tests\HelloDemoChecks.dpr` verifies the streamed event bindings, dialog mode routing, image loading and resizing
without user input; build it with `-SearchPath samples\Hello` and pass `samples/Hello/assets/landscape.png` at run time.


The compositor and X11 input scripts run the fixed-layout form with `Hello --backend-probe`. `--selftest` on its own checks the tabbed demo. The headless Weston script covers both.

- `tests\hello-e2e.ps1` — end to end on WSLg with **real input**: it moves the Windows mouse and types (WSLg forwards
  Windows input to its compositor over RDP, so events take the real wl_pointer/wl_keyboard path), takes screenshots
  of the windows and checks the program's log: pointer, button clicks, typing (any keyboard layout), editing keys,
  Ctrl+A/Ctrl+X, mouse wheel, clipboard both ways (WSLg shares it with Windows), combo box popup, check box, second
  form, modal form (the main window must not react meanwhile), close request from the compositor, the close and
  maximize buttons of the client-side title bar, maximize/restore, resize from code, clean exit. Needs an
  interactive desktop nobody else is using (it takes the mouse for about a minute).
- `tests\weston-headless.ps1` — non-interactive: the sample on a private headless Weston 14 at output scale 1 and
  2 (buffer size through `IFMXWaylandNativeWindow`, the self-test steps up to a message box answered by a timer, file
  dialogs without a session bus — FMX's own, driven by timers: the folder listed through the filter without hidden
  files, two files of a multiple selection, save over an existing file with another filter and the overwrite
  question, a folder, cancel —, the program's frame dumps, a compositor screenshot, clean exit), the default font
  (fontconfig's family at 12; `FMXWAYLAND_FONT` with a serif family: the canvas measures the default text in it),
  popups opened before their window is mapped (`Hello --early-popup`, `=paint`, `=create`: the drop-down and the
  window must both be on the screen, counted in the screenshot's pixels) and `Hello --own-titlebar --selftest` (the
  window frame service without input, no FMXWayland title bar in the screenshot). `-BuildRoot <root of a NOSKIA
  build> -Canvas TLinuxCanvas` runs it on FMX's default canvas, `-BuildRoot <root of a FASTCANVAS build> -Canvas
  TFastCanvas` on FastCanvas (the frame dump is then the frame FastCanvas presented: FMXWayland has none of such a
  window). The self-test also hides the second form and shows it again (the window configured twice), and fails on an
  exception the program got (`Application.OnException` writes it to the log).
- `tests\canvas-check.ps1` — builds `tests\CanvasCheck` for both canvases and runs them on headless Weston at scale 1
  and 2: the same drawing (gradients, opacity, dashes and caps, bitmap brushes, scaled and partial bitmaps, the PNG
  codec, text beyond the BMP, wrapping, alignment, trimming, styles, rotation, text as a path, a degenerate matrix),
  checks of what the program measures (positions around a surrogate pair, PtInPath, the PNG round trip) and the two
  frames side by side, Skia left, cairo right.
- `tests\dialog-check.ps1` — builds `tests\DialogCheck` and runs it on headless Weston with a private session bus:
  the D-Bus client against the real dbus-daemon (an address list with a missing socket first, an abstract socket,
  `guid=`, `unix:runtime=yes`, a non-Unix address; SASL EXTERNAL; strings, arrays and a dictionary of variants; an
  error reply's name; a timeout; a subscribed signal; a pump that cancels; no portal: unavailable after 1 ms) and the
  dialog backend with a test backend (what `TOpenDialog`, `TSaveDialog`, `SelectDirectory`, `TDialogService` and
  the FMUX dialog functions hand it and get back; an oversized selection leaves FMX's buffer empty; `nil` restores FMX's
  dialog services) and the default font (Pango font descriptions; GNOME's `font-name` through a settings portal on
  two more private buses, `tests\settings-portal.py`: `ReadOne`, and an old portal with only `Read`; asked only in a
  GNOME session and not with `FMXWAYLAND_PORTAL=0`; a missing key; no portal: fontconfig at once).
- `tests\glibc-compat.ps1` — the glibc symbol versions Hello and `libsk4d.so` need (`objdump -T`, at most 2.35),
  then Hello's self-test on the headless Weston of other distributions in Docker containers (no screen, no GPU;
  images with the run-time libraries, built once as `fmxwayland-compat:<image>`): `ubuntu:22.04` (glibc 2.35,
  Weston 9), `debian:12` (glibc 2.36, Weston 10), `fedora:latest` (Fedora 44, glibc 2.43, Weston 15) by default;
  `-Images` takes others. Needs Docker Desktop (Linux containers). On glibc 2.31 (Debian 11) the loader refuses the
  program (`GLIBC_2.34 not found`).

- `tests\compositors.ps1` — the sample on real compositors started headless in WSL (nothing on the desktop, no
  Windows input): see [Compositors](#compositors).

Evidence of the last runs: all checks of the first two passed (WSLg on Windows 11 with Ubuntu 26.04, Weston 14.0.2
headless), and all of `glibc-compat.ps1` with the program linked against the Ubuntu 22.04 SDK (2026-10-14);
`Hello --selftest` also runs to the end on WSLg (its seat appears only after the RDP client connects, a second or so
after the program starts: the clipboard falls back to a process-local one until then). With the dialogs and the
window frame service merged and GNOME's font: `weston-headless.ps1` passed on both canvases (153 checks each: Skia,
cairo), `dialog-check.ps1` 36, `canvas-check.ps1` 36, `glibc-compat.ps1` 74 (Ubuntu 22.04, Debian 12, Fedora 44);
the end-to-end test on WSLg was not run again (it takes the Windows desktop). With FastCanvas (2026-10-14, after the
changes for it): `weston-headless.ps1` 157 checks on each canvas (Skia, cairo, FastCanvas), `canvas-check.ps1` 36,
`dialog-check.ps1` 36, all passed; `compositors.ps1` with FastCanvas 1028 passed (8 runs, all parts), with Skia 966
(7 runs, all parts; GNOME Shell at 1.5 once more after its shell stayed busy and took no pointer input in the first
run), with cairo 184 (sway, KWin, GNOME Shell at 1.5: self-test, own title bar, popups of unmapped windows), none
failed.

| | |
|---|---|
| ![combo box popup](docs/screenshots/hello-combo-popup.png) | ![message box](docs/screenshots/hello-message-dialog.png) ![modal form](docs/screenshots/hello-modal.png) |

Headless Weston, output scale 2 (2x rendering, client-side decorations, the combo box drop-down as an xdg_popup):

![Weston at scale 2](docs/screenshots/weston-headless-scale2.png)

FMX's default canvas (cairo and Pango, `-Define NOSKIA`) on headless Weston, and `tests\canvas-check.ps1` (Skia
left, cairo right): weston-headless and canvas-check passed with both canvases at scale 1 and 2, and the self-test of
both runs to the end on headless sway 1.11 too (which tiles the window: its size there is sway's, not 700x540)
(2026-10-14).

![Hello on FMX's cairo canvas](docs/screenshots/hello-cairo.png)

![Skia and cairo side by side](docs/screenshots/canvas-check.png)

## Compositors

`tests\compositors.ps1` starts each compositor headless in WSL (Ubuntu 26.04: its own runtime directory, home and
D-Bus session; nothing appears on the desktop and no Windows input is used), runs `samples\Hello` on it and checks
its log, the compositor's view of the windows and screenshots:

1. `Hello --backend-probe --selftest` (the checks of `tests\weston-headless.ps1`: threads, clipboard, the combo box drop-down,
   second form, maximize/restore, modal loop, buffer size at the scale, frame dump) with a compositor screenshot while
   the drop-down is open;
2. where the compositor can be driven from outside, a scenario with input as a user gives it (`tests\wltool.py`, a
   small Wayland client speaking the wire protocol, plus D-Bus): three clicks on a button, typing into `TEdit`,
   Backspace, Home, End, Ctrl+A, Ctrl+X, Shift, the wheel both ways, the clipboard both ways with another application
   (data-control on sway and KWin, `St.Clipboard` on GNOME Shell), the combo box popup (placed where the program asked,
   then an item clicked at its place), the check box, a second form (focused; its "Activate main form" button
   activates the main form with xdg-activation from a click's serial; closed by the compositor), the close button of
   the program's own title bar, a modal form (the main form must not react to a click meanwhile), FMX's own file
   dialogs (the program's session bus has no portal: a double click opens a file, a typed name saves, Escape
   cancels), maximize/restore from the program, from the compositor and from the program's title bar, resize from code
   (the compositor must see the new size), close of the main form by the compositor and a clean exit;
3. `Hello --own-titlebar --selftest` (`IFMXWaylandWindowFrame` without input: decorations off, the listener at once
   and after the configure, nothing started without a press, a drop-down of the undecorated window, maximize/restore
   through the service, decorations on and off again; a screenshot without FMXWayland's title bar) and, where the
   compositor can be driven, `Hello --own-titlebar` with input: no decorations (the compositor's frame equals the
   window geometry and the client area), a drag on the caption moves the window, a drag on the corner grip resizes
   it, the maximize button and a double click maximize and restore it to its size and place, a right click shows the
   compositor's window menu (screenshot), another window takes and gives back the activation (listener), a popup at
   its place, minimize and the compositor showing the window again, the close button;
4. popups opened before their window is mapped (`Hello --early-popup`, `=paint`, `=create`): an xdg_popup of the
   main window once that is mapped, not dismissed, both on the screen (pixels of the screenshot; on compositors that
   activate the new window FMX closes the popup again, see [What does not work](#what-does-not-work-yet)); on GNOME
   Shell these programs run on the session's bus, and their default font must be GNOME's `font-name` read through
   the settings portal;
5. on sway, KWin and GNOME Shell the **portal's file dialog**: xdg-desktop-portal started by D-Bus activation in the
   run's session with the compositor's backend (sway: xdg-desktop-portal-gtk; KWin: -kde; GNOME Shell: -gtk, since
   xdg-desktop-portal-gnome hands file dialogs to Nautilus, which does not run as root): the request, the program's
   window exported with xdg-foreign as the parent and the dialog its child for the compositor (KWin, GNOME Shell
   report it), the program's loop running meanwhile and its main window ignoring the compositor's close, a file chosen
   by typing its path, a name typed into the save dialog, Escape, `Request.Close` from another client refused by the
   portal, the program ending while a folder dialog is open (its request closed, the dialog gone), a clean exit.
   What cannot be automated: a click into the portal's dialog at a known place (its layout is the toolkit's; the
   keyboard answers it), and the program's windows under it (the dialogs cover them on a 1280x800 output).

The self-test and the scenario run on a private session bus without services (no portal: FMX's own file dialogs),
the other parts on the run's session bus. `-Parts` picks some of `selftest, frame-selftest, early, scenario, frame,
portal`.

| | Weston 14 | sway 1.11 | sway 1.11 `border csd` | KWin 6.6 | GNOME Shell 50 (Mutter) |
|---|---|---|---|---|---|
| Headless | `--backend=headless` | `WLR_BACKENDS=headless` | the same | nested in a headless sway (`--virtual` too: self-test only) | `--headless --virtual-monitor` |
| Input, window queries | none (self-test only) | wlr virtual pointer/keyboard, `swaymsg` | the same | `org_kde_kwin_fake_input`, KWin scripts | Clutter virtual devices through `org.gnome.Shell.Eval` |
| Screenshots | `weston-screenshooter` | grim | grim | grim of the host sway | `org.gnome.Shell.Screenshot` |
| Title bar | the program's | sway's (xdg-decoration) | the program's (xdg-decoration "client-side") | KWin's Breeze (xdg-decoration) | the program's |
| Scale 1, 2 | pass, pass | pass, pass | pass, — | pass, pass | pass, pass |
| Fractional 1.5 (wp-fractional-scale-v1) | not offered | pass | pass | pass | pass (`gdctl`, `scale-monitor-framebuffer`) |
| Self-test | pass | pass (maximize n/a) | pass (maximize n/a) | pass | pass |
| Pointer, keyboard, shortcuts, wheel | — | pass | pass | pass | pass |
| Clipboard with another application, both ways | — | pass | pass | pass | pass |
| Popup placed where asked, item clicked | self-test | pass | pass | pass | pass |
| xdg-activation | not offered | pass (`focus_on_window_activation focus`) | pass | pass | pass |
| Second form, close by the compositor | self-test | pass | pass | pass | pass |
| Close button of the program's title bar | — | n/a | pass | n/a | pass |
| Modal form, main form blocked | self-test | pass | pass | pass | pass |
| FMX's own file dialogs (no portal): double click opens, typed name saves, Escape | self-test (no bus) | pass | pass | pass | pass |
| The portal's file dialog (backend) | not run | pass (xdg-desktop-portal-gtk) | pass (-gtk) | pass (-kde) | pass (-gtk: -gnome's Nautilus does not run as root) |
| Its parent: the program's window through xdg-foreign | — | exported (sway does not report the relation) | exported | pass | pass |
| Meanwhile: the program's loop runs, its main window ignores a close | — | pass | pass | pass | pass |
| Keyboard answers (path, name), Escape, the program ending during a dialog | — | pass | pass | pass | pass |
| Maximize/restore: program, compositor, title bar | self-test | n/a (no maximize in sway) | n/a | pass, pass, n/a | pass, pass, pass |
| Resize from code | — | pass | pass | pass | pass |
| Close by the compositor, clean exit | — | pass | pass | pass | pass |
| Default font (fontconfig's sans-serif) | pass | pass | pass | pass | pass |
| Default font in GNOME: `font-name` through the settings portal ("Adwaita Sans 11": fontconfig's family, 14.7) | — | — | — | — | pass |
| Popups opened before the window is mapped (`--early-popup`, `=paint`, `=create`) | pass, both on the screen | pass (FMX closes them at the activation) | pass (likewise) | pass (likewise) | pass (likewise) |
| Own title bar, self-test: no decorations, listener, maximize, decorations on and off | pass | pass (maximize n/a) | pass (maximize n/a) | pass | pass |
| Own title bar with input: move, resize, activation, popup, close button | — | pass | pass | pass | pass |
| Own title bar: maximize/restore by button and double click, back to size and place | — | n/a | n/a | pass | pass |
| Own title bar: the compositor's window menu, minimize | — | n/a | n/a | pass | pass |
| [FastCanvas](#fastcanvas-vulkan) (Vulkan, `VK_KHR_wayland_surface`): all of the above at 1, 2 (Weston), 1.5 | pass (1, 2) | pass (1, 1.5) | not run | pass (1, 1.5) | pass (1, 1.5) |

Last run (2026-10-14, WSL 2 with Ubuntu 26.04, the program linked against the Ubuntu 22.04 SDK, with the dialogs and
the window frame service merged and GNOME's font through the settings portal): 14 runs (Weston 1, 2; sway 1, 2, 1.5;
sway `border csd` 1, 1.5; KWin 1, 2, 1.5; KWin `--virtual` 1; GNOME Shell 1, 2, 1.5) with all parts, 1751 checks
passed, 51 not applicable (maximize, minimize and the window menu on sway; on each run with the portal a click on the
program's window under the portal's dialog, which covers it), none failed (31 minutes). The branches had run 946
(dialogs) and 1366 (window frame) checks before. KWin's `--virtual` backend renders with QPainter, and its
screenshot interface (`org.kde.KWin.ScreenShot2`) needs OpenGL, which WSL cannot give it (no DRM render node): the
test runs KWin nested in a headless sway (KWin's Wayland backend, its window fullscreen there; KWin takes the host
output's scale), and KWin `--virtual` for the self-test alone. GNOME Shell runs with a test extension
(`tests\gnome-test-extension`) that turns on its unsafe mode, which lets the test call `org.gnome.Shell.Eval` and
`org.gnome.Shell.Screenshot`, and hides the overview after the startup animation (it takes the input otherwise).

What the runs found and what was fixed: a window below a modal form that the compositor activated (the user clicked
it) made FMX ask to activate it again, a loop of activation requests that kept the modal form from getting its OK
click (sway, KWin, GNOME); the modal form gets the activation now. Title bar buttons follow
`xdg_toplevel.wm_capabilities` (sway offers neither maximize nor minimize). FMX learns the new window rectangle when
the compositor switches the decoration mode (sway's `border csd`; sway keeps the window's outer size, so the client
area is 692x506 there). FMX resizes its canvas and realigns a form only when its window rectangle changes size, so
when only the client area changes inside a window of the same outer size (decorations switched by the compositor or
by the program), FMXWayland does those steps of `SetBounds` itself (FMX's file dialog had its buttons cut off on
sway with `border csd`; an own title bar turned on and off left the form aligned to the old client area). Popups are
placed where asked on all of them (`popup configure x,y (asked x,y)` in the debug log). With the window frame
service: GNOME Shell put a maximized window that a double click on the program's caption restored at the top left
corner (under its top bar) when the first click had started a move; moves now start on the drag. `SetDecorated`
before the first show reported the window's provisional size to FMX and so replaced the size the program had given
the form (FMR Ribbon's RibbonBasic opened at 632x446 instead of 1180x640); it only records the choice then now. A
popup made before its parent was mapped is made once the parent is (FMR Ribbon saw both windows stay invisible on
Weston that way; in these runs Weston showed both even before the fix, the protocol requires the order). The portal
part found what the portals need in a session without a desktop session manager: `XDG_CURRENT_DESKTOP` and
`XDG_SESSION_TYPE=wayland` (else xdg-desktop-portal-gnome serves settings only), the compositor's display in the
D-Bus activation environment before the compositor starts (GNOME Shell and KWin start the portal at once), Qt's
Wayland shell integration (`qt6-wayland`) for xdg-desktop-portal-kde; xdg-desktop-portal-gtk answers Escape with
response 2, and xdg-desktop-portal 1.21 refuses `Request.Close` from another client.

Running it (in Ubuntu 26.04: `apt install weston sway grim kwin-wayland kwin-common kwin-style-breeze gnome-shell
mutter python3-dbus wayland-utils`, for the portal part `xdg-desktop-portal xdg-desktop-portal-gtk
xdg-desktop-portal-kde xdg-desktop-portal-gnome qt6-wayland`):

```powershell
.\tools\build.ps1 -Project samples\Hello\Hello.dpr
.\tests\compositors.ps1                            # all; -Runs gnome:1.5, kwin:2 for some (<compositor>:<scale>)
```

Results: `D:\Work\FMXWayland-build\shots\compositors\<compositor>-<scale>\` (`results-all.txt`, `steps.log`, the
program's logs, screenshots, frame dumps) and `summary.md` there (the matrix of all checks).

| KWin 6.6 at 1.5 (server-side title bar, combo box popup) | GNOME Shell 50 at 1.5 (the program's title bars, modal form) | sway at 1.5 with `border csd` (only a close button: sway has no maximize) |
|---|---|---|
| ![KWin](docs/screenshots/kwin-scale1.5-combo.png) | ![GNOME Shell](docs/screenshots/gnome-scale1.5-modal.png) | ![sway](docs/screenshots/sway-csd-scale1.5-second-form.png) |
## FastCanvas (Vulkan)

[FastCanvas](https://github.com/Fasday/FMXFastCanvas) (FMX canvas and 3D context on Vulkan, Direct3D 11/12) runs on
FMXWayland natively: its windows present to their `wl_surface`s through `VK_KHR_wayland_surface`, with no GTK, X11,
Skia or libfmux. Neither project depends on the other: FastCanvas declares
[IFMXWaylandNativeWindow](#ifmxwaylandnativewindow-contract-for-gpu-canvases) again and takes the Wayland path when
the service is there (on FMX's GTK platform it presents to X11 windows as before).

- Toplevel windows (forms, modal forms, dialogs, `TForm3D`): a Vulkan surface on the window's `wl_surface`, swap
  chains of the buffer size FMXWayland reports, presented by a thread of FastCanvas (Mesa's WSI reads its own event
  queue there), `MAILBOX` (else `IMMEDIATE`; never Wayland's `FIFO`, which blocks in the present on frame callbacks a
  hidden window never gets). FMXWayland keeps calling FMX's paint; FMX paints when it invalidates.
- Popups (combo box lists, menus) and transparent forms go through FMXWayland's frames: FastCanvas reads them back
  and hands them over with `FmuxCanvasDrawBitmap` (FMXWayland makes a popup's `xdg_popup` again at every show and
  move, which a presenting thread could not follow).
- Before FMXWayland unmaps a window FastCanvas stops presenting to it (it wraps FMX's window service), and the first
  frame of a window shown is presented before FMX's paint returns; FMXWayland applies the window's viewport, geometry
  and decorations before the presenter's next commit (see the contract below).
- Building: `tools\build.ps1 -Define FASTCANVAS -SearchPath
  <FastCanvas>\src\Canvas,<FastCanvas>\third_party\pasvulkan\src` for Hello; FastCanvas's own probes with its `tools\build-linux.ps1 -Wayland <FMXWayland folder>`. Running needs
  `libvulkan1` and a Vulkan driver with `VK_KHR_wayland_surface` (Mesa's; lavapipe on the CPU presents through
  `wl_shm`), and Pango, HarfBuzz, fontconfig, FreeType for FastCanvas's text.
- Tested (2026-10-14, WSL 2 with Ubuntu 26.04, Mesa 26.0.8's lavapipe, the only Vulkan device there): Hello with
  FastCanvas passes `tests\weston-headless.ps1 -Canvas TFastCanvas` (157 checks, Weston 14 at scale 1 and 2: the
  self-test with the combo box drop-down, the second form hidden and shown again, maximize and restore, the modal
  form, the message box, FMX's file dialogs; the default font; the popups of unmapped windows; the own title bar) and
  `tests\compositors.ps1 -Canvas TFastCanvas` on Weston 1 and 2, sway 1 and 1.5, KWin 1 and 1.5, GNOME Shell 1 and
  1.5 with all parts (self-test, scenario with input and the clipboard, own title bar with input, popups of unmapped
  windows, the portal's file dialogs): 1028 checks passed, 22 not applicable, none failed. The Vulkan validation layer
  (with synchronization validation) reports nothing for the self-test on Weston and on sway at 1.5 (23 scale changes),
  for FastCanvas's PortProbe (its scene, the Vulkan 3D context's cube with ray-traced shadows, ambient occlusion and
  reflections, FMX effects; resized from code 42 times at scale 2) and for its Form3DProbe (a `TForm3D` window with
  its own swap chain). What the runs found and fixed is in the commits: the viewport, the configure's state before
  the presenter's commits (Weston's `invalid_surface_state` on maximize), the window mapped after its first paint,
  toplevels hidden and shown again (Weston sent no configure to an unmapped toplevel that kept its role: any canvas),
  the form's canvas made again on scale changes (a new window starts at the output's integer scale), the
  initialization order of `FMUX.Api` (`FMXWayland.FmuxLoad`), and in FastCanvas a click into an empty `TEdit`.
- Frame rate and CPU on the same scene (FastCanvas's PortProbe without its cube, 480x840, headless Weston at scale 1,
  20 s; lavapipe renders on the CPU, so only the relations mean something): repainted at once, FastCanvas 123.5 FPS
  at 2.44 CPU seconds per second (19.8 ms per frame, lavapipe's threads included; 0.3 ms of it recording on the main
  thread), FMX's cairo canvas 39.5 FPS at 0.17 (4.3 ms per frame; FMXWayland's frame callbacks pace it), the Skia
  raster canvas 24.4 FPS at 0.79 (32.5 ms, one thread); with a 16 ms timer 62.0 FPS at 1.28, 39.4 at 0.15, 23.9 at
  0.79.

| KWin 6.6 at 1.5: Hello on FastCanvas (the drop-down read back into FMXWayland's frame) | PortProbe on Weston: shapes, Pango text with emoji, the Vulkan 3D context's cube | Form3DProbe on Weston: a `TForm3D` with ray-traced shadows and ambient occlusion |
|---|---|---|
| ![KWin](docs/screenshots/fastcanvas-kwin-scale1.5-combo.png) | ![PortProbe](docs/screenshots/fastcanvas-portprobe-weston.png) | ![Form3DProbe](docs/screenshots/fastcanvas-form3d-weston.png) |

## IFMXWaylandNativeWindow (contract for GPU canvases)

A GPU canvas (FastCanvas on Vulkan) creates its own `VkSurfaceKHR` for a window with
`vkCreateWaylandSurfaceKHR(wl_display, wl_surface)`. FMXWayland registers, when it connects (in `FmuxInit`, during
the initialization of `FMX.Platform`), an FMX platform service:

```pascal
type
  IFMXWaylandNativeWindow = interface
    ['{B04A2FBC-1322-42BC-98A6-D526A7854F2C}']
    function GetWaylandDisplay: Pointer;                                   // wl_display*
    function GetWaylandSurface(const AHandle: TWindowHandle): Pointer;     // wl_surface*, nil if not an FMXWayland window
    function GetBufferSize(const AHandle: TWindowHandle): TSize;           // buffer pixels = client size x scale
    function GetScale(const AHandle: TWindowHandle): Single;               // buffer pixels per logical pixel
    procedure SetExternalPresentation(const AHandle: TWindowHandle; const AValue: Boolean);
  end;
```

A library that must not depend on FMXWayland declares the same interface (same GUID, same methods in the same order,
same signatures; Delphi's default calling convention) and asks with
`TPlatformServices.Current.SupportsPlatformService(IFMXWaylandNativeWindow, Svc)` (`samples\Hello` does exactly
that). Never change this declaration; extensions get a new interface with a new GUID. The rules:

- The `wl_surface` is the window's content surface: it lives as long as the FMX window handle (also across
  hide/show; popups get new xdg_popup objects at each show, the surface stays). Its size is the client area — the
  client-side decorations are a separate subsurface.
- `GetBufferSize`/`GetScale` change on resize and scale changes; FMX resizes its canvas then (form resize, and
  `TScaleChangedMessage` for scale changes).
- `SetExternalPresentation(Handle, True)`: FMXWayland keeps calling FMX's paint (the canvas renders and presents in
  `EndScene` or later, from a thread of its own), but stops attaching its own wl_shm frames. The surface gets a
  `wp_viewport` (where the compositor has `wp_viewporter`, all tested ones do) whose destination is the window's
  logical size, with buffer scale 1: a buffer of any size the presenter commits is valid and fills the window (a
  frame painted before a resize or a scale change; without the viewport an odd-sized buffer at buffer scale 2 would
  be a protocol error). FMXWayland still owns the viewport, the window geometry and the decoration subsurface; that
  state is double-buffered and takes effect with whichever commit of the presenter (`vkQueuePresentKHR`) comes next.
  So that any such commit is valid for the configure acknowledged before it, FMXWayland sends that state right next
  to the acknowledgement, before FMX hears of the configure (into maximized or fullscreen the new geometry first, out
  of it the acknowledgement first: Weston raises `invalid_surface_state` when a maximized window's geometry is not
  the configured size), and again before every paint. There are no frame callbacks of FMXWayland then: FMX paints
  when it invalidates (its animations and timers), the presenter paces its own frames.
- The window counts as mapped (its popups are made, `CanParentPopups`) once the first paint after it was shown has
  returned: the presenter should have committed that frame by then (FastCanvas waits until its first frame of a
  window is presented).
- Before FMXWayland unmaps a window (FMX hides the form: `FmuxShowWindow(False)`, which attaches no buffer) the
  presenter must have stopped presenting to it, and it must not present again before FMXWayland paints the window
  after the compositor configured it again (a buffer committed to an unmapped xdg_surface is a protocol error).
  FastCanvas wraps FMX's `IFMXWindowService` for this (`HideWindow`, `ReleaseWindow`). FMXWayland itself unmaps
  popups when they move or resize (a new xdg_popup), which no presenter can follow: present popups through
  FMXWayland's frames (FastCanvas reads their frames back into the paint context with `FmuxCanvasDrawBitmap`).
- Everything is on the main thread; FMXWayland dispatches only the default event queue, with the
  `wl_display_prepare_read` protocol, so Vulkan WSI's own queue can coexist (Mesa's WSI reads and dispatches its
  queue on the presenting thread).

## IFMXWaylandWindowFrame (for programs with their own title bar)

A program that draws its own title bar (FMR Ribbon's integrated caption and tab row, a Chrome-like tab strip, ...)
needs the platform to stop decorating its window and to start interactive moves and resizes for it:
`xdg_toplevel.move`/`resize`/`show_window_menu` need the `wl_seat` and the serial of the pressing input event, which
only the platform has. FMXWayland registers this FMX platform service in `FmuxInit`, next to
`IFMXWaylandNativeWindow`. The declaration is FMR Ribbon's (`Source\Frame\FMR.Frame.Wayland.pas`, its
`Docs\LINUX.md`); FMXWayland has it in `FMXWayland.Frame`. A program declares the same interfaces (same GUIDs, the
same methods in the same order, the same signatures, Delphi's default calling convention) and asks with
`TPlatformServices.Current.SupportsPlatformService(IFMXWaylandWindowFrame, Svc)`; neither depends on the other. Never
change it; extensions get a new interface with a new GUID.

```pascal
const
  { Edges of BeginResize: the values of xdg_toplevel.resize_edge. }
  FmxwEdgeNone = 0; FmxwEdgeTop = 1; FmxwEdgeBottom = 2; FmxwEdgeLeft = 4; FmxwEdgeTopLeft = 5;
  FmxwEdgeBottomLeft = 6; FmxwEdgeRight = 8; FmxwEdgeTopRight = 9; FmxwEdgeBottomRight = 10;
  { Bits of GetStates: 1 shl <xdg_toplevel.state> of the last configure. }
  FmxwStateMaximized = 1 shl 1; FmxwStateFullscreen = 1 shl 2; FmxwStateResizing = 1 shl 3;
  FmxwStateActivated = 1 shl 4; FmxwStateTiledLeft = 1 shl 5; FmxwStateTiledRight = 1 shl 6;
  FmxwStateTiledTop = 1 shl 7; FmxwStateTiledBottom = 1 shl 8; FmxwStateSuspended = 1 shl 9;
  { Bits of GetCapabilities: 1 shl <xdg_toplevel.wm_capabilities>; FmxwCapsUnknown before xdg_wm_base 5. }
  FmxwCapWindowMenu = 1 shl 1; FmxwCapMaximize = 1 shl 2; FmxwCapFullscreen = 1 shl 3; FmxwCapMinimize = 1 shl 4;
  FmxwCapsUnknown = Cardinal($FFFFFFFF);

type
  IFMXWaylandWindowFrameListener = interface
    ['{785C5760-E413-4153-82DF-E857D1AA70AC}']
    procedure WindowFrameChanged(const AHandle: TWindowHandle; const AStates, ACapabilities: Cardinal);
  end;

  IFMXWaylandWindowFrame = interface
    ['{547B5786-5639-43A4-A598-1A03B465783A}']
    procedure SetDecorated(const AHandle: TWindowHandle; const AValue: Boolean);
    function GetDecorated(const AHandle: TWindowHandle): Boolean;
    function BeginMove(const AHandle: TWindowHandle): Boolean;
    function BeginResize(const AHandle: TWindowHandle; const AEdges: Cardinal): Boolean;
    function ShowWindowMenu(const AHandle: TWindowHandle; const AClientPoint: TPointF): Boolean;
    procedure Minimize(const AHandle: TWindowHandle);
    procedure SetMaximized(const AHandle: TWindowHandle; const AValue: Boolean);
    function GetStates(const AHandle: TWindowHandle): Cardinal;
    function GetCapabilities(const AHandle: TWindowHandle): Cardinal;
    procedure SetFrameListener(const AHandle: TWindowHandle; const AListener: IFMXWaylandWindowFrameListener);
  end;
```

`AHandle` is the form's `Handle`. Handles that are not toplevels of FMXWayland (popups, foreign handles): the methods
do nothing and return False/0. Main thread only.

| Method | What FMXWayland does |
|---|---|
| `SetDecorated(H, False)` | No decorations at all: the client-side title bar (subsurface) goes, and where the compositor has xdg-decoration it is asked for `client_side` (KWin and sway draw none then). Kept for the window: configures, the compositor's decoration answers and hide/show do not bring them back. The window geometry is the surface (`set_window_geometry(0, 0, w, h)`), `DecorationInsets` are 0, FMX's window rectangle is the client rectangle. **Before the window's first show** (a form's constructor, `FormCreate`, FMR's frame attaching to a new form) only the choice is recorded: nothing is reported to FMX and the window's size is not touched, so the `Width`/`Height` the program gave the form (before or after the call) stay and become the client area when the form is shown (FMX keeps a form's size to itself until its first show and sets it then). **Once the window has been shown** it keeps its outer size and place (the client area takes the room of the decorations; a maximized window must keep the configured size) and FMX gets the new bounds and realigns; a hidden window keeps its client size. `True`: the platform's choice again (`server_side` asked, or its own title bar), with the same rules. |
| `GetDecorated(H)` | True while the window has FMXWayland's title bar, or the compositor's (asked for and not refused). |
| `BeginMove(H)` | True when the latest pointer button press on any surface of the window (its content or its title bar) is still held. The move itself (`xdg_toplevel.move` with that press's serial) starts when the pointer has been dragged 4 pixels with the button held, as GTK does: a click or a double click on the caption stays a click (no button release lost to the compositor; GNOME Shell put a maximized window restored right after a move that started at the first click of a double click to the top left corner). False without a held press, for popups. |
| `BeginResize(H, Edges)` | `xdg_toplevel.resize` with the held press's serial at once; False without one or for an edge value that is not one of xdg-shell's (a protocol error otherwise). |
| `ShowWindowMenu(H, P)` | `xdg_toplevel.show_window_menu` at `P` (client = surface coordinates) with the held press's serial; False without one or without the `window_menu` capability. |
| `Minimize(H)` | `xdg_toplevel.set_minimized` where the window manager can minimize (not sway); FMX's `WindowState` becomes `wsMinimized` (Wayland does not tell; the next activation brings `wsNormal` back), as the minimize button of FMXWayland's title bar does. |
| `SetMaximized(H, V)` | `set_maximized` / `unset_maximized`; the state follows with the configure (`WindowState`, the listener). |
| `GetStates(H)` | Bits `1 shl state` of the last configure (0 before the first). |
| `GetCapabilities(H)` | Bits `1 shl capability` of `xdg_toplevel.wm_capabilities`; `$FFFFFFFF` when the compositor never sent them (before the first configure too). |
| `SetFrameListener(H, L)` | Keeps a reference (nil removes it; released with the window) and calls `L.WindowFrameChanged(H, States, Caps)` at once, then on the main thread after every configure that changed the states or brought new capabilities (activation changes come as states). |

Also for programs with their own title bar: a pointer that leaves a window while a button is held (the compositor
took it for a move, a resize or its window menu) gives FMX the release, so the control that took the press lets the
mouse capture go.

`samples\Hello --own-titlebar` uses the service through its own copy of the declaration (`HelloTitleBar.pas`): a
blue caption that moves the window, maximizes and restores it on a double click and shows the window menu on a right
click, minimize/maximize/close buttons (those the window manager offers), 5 pixel resize grips at the edges and the
states from the listener. Like a program, it sets the form's `Width`/`Height` in its constructor (720x460,
`--size=WxH`; `--size-after=WxH` sets it again after the frame is attached) and turns the decorations off before the
first show; the tests check that the window opens at that size (FMX's form, the client area, the buffer at the
scale) and follows sizes set from code later. What the compositors do with it ([Compositors](#compositors), `tests\compositors.ps1`):

| | Weston 14 | sway 1.11 | KWin 6.6 | GNOME Shell 50 |
|---|---|---|---|---|
| No decorations (window geometry = client area, no title bar of the compositor) | pass (self-test) | pass (sway draws none for `client_side`) | pass | pass |
| Move by dragging the caption | — (no input) | pass (floating window) | pass | pass |
| Resize by the corner grip | — | pass | pass | pass |
| Maximize/restore: button, double click; back to size and place | self-test (`SetMaximized`) | n/a (no maximize) | pass | pass |
| Window menu (right click) | n/a (no `window_menu`) | n/a (no `window_menu`) | pass (KWin's menu) | pass (GNOME Shell's menu) |
| Activation in the listener (another window focused and closed) | — (no focus headless) | pass | pass | pass |
| Minimize, shown again by the compositor | — | n/a (no minimize) | pass | pass |
| Decorations back (`SetDecorated(True)`) and off again | pass: FMXWayland's title bar, same outer size | pass: sway's; sway keeps the outer size of the floating window, the client area stays smaller by its title bar | pass: Breeze; likewise | pass: FMXWayland's |

| GNOME Shell 50: the program's title bar, GNOME Shell's window menu after a right click on it | KWin 6.6: likewise, KWin's window menu |
|---|---|
| ![GNOME Shell](docs/screenshots/gnome-own-titlebar-menu.png) | ![KWin](docs/screenshots/kwin-own-titlebar-menu.png) |

## Status

Tested on WSLg (Weston-based, RDP; xdg_wm_base 1, no xdg-decoration, no cursor-shape, no fractional-scale), and
headless on Weston 9, 10, 14, 15, sway 1.11, KWin 6.6 and GNOME Shell 50 (see [Compositors](#compositors)); the cairo
canvas on Weston 14 and sway 1.11. 108 of 186 FMUX functions are assigned; the full list:
[docs/FMUX-STATUS.md](docs/FMUX-STATUS.md).

| Area | FMUX functions | Status |
|---|---|---|
| Application, loop, threads | FmuxInit, FmuxRun, FmuxHandleMessage, FmuxTerminate, FmuxWakeMainThread, FmuxGetKeyState, FmuxGet/SetVersionInfo | implemented |
| Timers | FmuxCreateTimer, FmuxDestroyTimer | implemented |
| Windows | FmuxCreateWindow, FmuxDestroyWindow, FmuxShowWindow, FmuxSetWindowState, FmuxSetWindowTitle, FmuxGet/SetClientSize, FmuxGetWindowRect, FmuxInvalidateRect, FmuxProcessUpdates, FmuxClientToScreen, FmuxScreenToClient, FmuxGetWindowScale, FmuxGet/SetWindowFullScreen, FmuxShowModal, FmuxSetMainWindow | implemented |
| Windows (Wayland limits) | FmuxSetWindowRect (position virtual), FmuxSetWindowIcon (xdg-toplevel-icon-v1), FmuxActivateWindow/FmuxWindowBringToFront (xdg-activation request), FmuxWindowSendToBack (no-op), FmuxSetCapture/ReleaseCapture (implicit grab), FmuxGetWindowNativeHandle/DrawingHandle (wl_surface) | partial |
| Popups | through FmuxCreateWindow (Popup) / FmuxShowWindow | implemented (xdg_popup, no grab; made once the parent window is mapped) |
| Screens | FmuxGetScreenSize, FmuxGetScreenScale, FmuxGetDisplayFromWindow, FmuxGetDisplayFromPoint; FmuxGetDisplayInfo (work area = output) | implemented / partial |
| Mouse, cursor | FmuxGetMousePos (partial: last position over an own window), FmuxSetCursor | implemented |
| Keyboard | (FmuxKey callback): xkbcommon, repeat, compose, layout-independent shortcuts | implemented |
| Painting, bitmaps (both canvases) | FmuxBitmapCreate, FmuxBitmapDestroy, FmuxGetBitmapInfo, FmuxCanvasDrawBitmap | implemented |
| FMX's default canvas (cairo, Pango, gdk-pixbuf) | FmuxCreateContext, FmuxDestroyContext, FmuxSave/Restore, FmuxSetClipRects, FmuxIntersect/ExcludeClipRect, FmuxCanvas* (paths, fills, strokes, dashes, gradients, bitmap brushes, matrix, quality, clear, PtInPath), FmuxCreateTextLayout ... FmuxLayoutToPath, FmuxBitmapLoad, FmuxBitmapSave | implemented |
| Clipboard | FmuxClipboardHas/Get/SetText | implemented |
| Clipboard, other formats | FmuxClipboardHas/GetImage, FmuxClipboardHas/GetCustom (report "none"); FmuxClipboardSetImage/SetCustom/SetArray | partial / stub |
| Dialogs | FmuxFilesDialog (portal's file dialog, FMX's own without a portal) | implemented |
| Dialogs | FmuxMessageDialog (FMX's own dialog form, or the backend's), FmuxInputQuery (the backend's; FMX uses its own input query anyway) | partial |
| IME | FmuxImeEnterControl/ExitControl/SetCaretPos | text-input-v3; stock FMUX preedit attribute limit |
| Tooltips, gestures | FmuxAddTooltip/RemoveTooltip, FmuxAdd/RemoveGestureRecognizer (no-ops) | partial |
| OpenGL contexts | FmuxCreateSharedContext, FmuxCreateThreadContext, FmuxMakeCurrentContext | EGL; shared desktop GL contexts for TViewport3D |
| PDF canvas | FmuxCreatePDFContext | stub |
| Fonts | FmuxGetFontCount, FmuxGetFontName (the system's families); FmuxAddCustomFont, FmuxAddCustomFontFromData; FMX's IFMXSystemFontService (default font: GNOME's font-name through the settings portal, else fontconfig's sans-serif) | partial / stub; service implemented |
| Main menu | IFMXMenuService / FMXWayland.Menus | TMainMenu rendered inside the window; xdg_popup submenus; legacy FMUX menu slots bypassed |
| Printing, PDF | FmuxEnumPrinters ... FmuxSetAlwaysAskOutputFile | stub |
| Web view, media, video capture | FmuxCreateWebView..., FmuxCreateMedia..., FmuxCaptureDeviceEnum... | stub |
| Shell | FmuxOpenFile, FmuxOpenUrl, FmuxGetFileIcon, FmuxGetFileType | stub |
| Drag and drop | FmuxBeginDragDrop / IFMXDragDropService | text, files, internal FMX data over wl_data_device |
| Synthetic events, screenshots | FmuxGen*, FmuxTakeScreenshot, FmuxGetCursor... | stub |

## What does not work yet

- FMX's default canvas: custom fonts (`TFontManager` / `FmuxAddCustomFont`: fontconfig application fonts are not
  wired yet), printing and PDF (`FmuxCreatePDFContext`). Pango spaces wrapped lines by the font's
  metrics, a little wider than Skia for some fonts (Ubuntu); FMX's own dialogs size themselves to it.
- External presentation (FastCanvas): no frame callbacks drive FMX's paints of such a window (FMX paints when it
  invalidates; with `MAILBOX` the presenter may draw more frames than the output shows); the acknowledgement of a
  configure is sent next to the new size's state, not in the presenter's commit, so a commit of the presenter's
  thread can still fall between the two (a window going from one maximized size to another: not seen in the tests);
  popups and transparent forms of a GPU canvas go through FMXWayland's frames (FastCanvas reads them back); tested on
  lavapipe only (WSL has no GPU driver with Wayland presentation).
- Clipboard images and custom formats, touch and gestures, tooltips, printing, web browser, media player.
- X11 currently omits Wayland-specific drag and drop, text-input-v3 and the xdg-toplevel-icon protocol.
- File dialogs: a selection that exceeds the FMUX filename buffer is rejected without returning a partial list; the portal's
  dialogs always ask before overwriting; `TSaveDialog.DefaultExt` is not passed by FMX. FMX's own file dialog has
  no places/bookmarks, icons or previews.
- Window positions are not under the program's control (Wayland); `Position = poScreenCenter` and the like have no
  effect. Popups do not grab the pointer (xdg_popup.grab): they close like other FMX popups (a click elsewhere in
  the program, or the form losing activation when another application is clicked).
- Scale changes after start (moving a window to a monitor with another scale) are reported to FMX with
  `TScaleChangedMessage`; tested only in the form of new windows getting the fractional scale after the output's
  integer one (fractional scaling itself is tested on sway, KWin and GNOME Shell at 1.5).
- `FmuxActivateWindow`/`FmuxWindowBringToFront` ask for activation with an xdg-activation token tied to the last
  input event; the compositor decides (sway only marks the window urgent unless `focus_on_window_activation focus`;
  KWin and GNOME Shell focus it). Without an input event yet (no serial) compositors may refuse.
- On compositors without maximize (sway: `wm_capabilities` lists only fullscreen) `WindowState := wsMaximized` is
  ignored by the compositor while FMX keeps `wsMaximized`.
- `IFMXWaylandWindowFrame`: no touch (FMXWayland has no `wl_touch` yet; only pointer presses start moves and
  resizes); no window geometry insets for shadows and invisible resize borders outside the window (a later interface).
  A move starts on the drag, not at the press (see the table): a program that waits for the compositor's grab at the
  press itself sees it a few pixels later.
- The default font follows the desktop's only in GNOME (its `font-name`, read once at start: a change later is not
  followed; `text-scaling-factor` is not applied). Elsewhere (KDE, sway, ...) the size is FMX's 12
  device-independent pixels, not the desktop's (fontconfig's match carries none).
- A popup opened before its window is on the screen (from a timer, `FormCreate`) waits for the window; compositors
  that activate the new window then (sway, KWin, GNOME Shell) make FMX close it again: FMX closes the popups of a form
  whenever its activation changes (FMX.Platform.Linux, as with libfmux).
- FMX frees a form's controls after its window handle: a form freed while a combo box's drop-down is open (closed by
  code, not by the user, whose close goes through FMX's popup handling first) ends in an access violation in FMX
  (`TCustomForm.DoRemoveObject` asks the gone window for its client size; on Windows the same program hangs at
  exit, so it is FMX's, not FMXWayland's to fix). Close the drop-downs of a form before freeing it from code, e.g.:

  ```pascal
  procedure CloseDropDowns(const ARoot: TFmxObject); // uses FMX.ListBox, FMX.ComboEdit
  var
    I: Integer;
  begin
    if (ARoot is TCustomComboBox) and TCustomComboBox(ARoot).DroppedDown then
      TCustomComboBox(ARoot).DropDown // toggles: closes the open list
    else if (ARoot is TCustomComboEdit) and TCustomComboEdit(ARoot).DroppedDown then
      TCustomComboEdit(ARoot).CloseDropDown;
    for I := 0 to ARoot.ChildrenCount - 1 do
      CloseDropDowns(ARoot.Children[I]);
  end;
  ```

  FMR Ribbon does this for its forms (`FmrCloseDropDowns` in `FMR.Ribbon.Editors`).

## Next steps

1. **External presentation**: pacing by the compositor (an `IFMXWaylandNativeWindow2` through which the presenter
   tells FMXWayland that it committed a frame, so that frame callbacks drive FMX's paints as with wl_shm frames;
   now FMX paints at the pace of its invalidations), and the acknowledgement of a configure in the presenter's own
   commit (now FMXWayland sends it next to the new size's state: a commit of the presenter's thread can fall in
   between).
2. **IME**: text-input-v1 for older WSLg, and an extension for precise preedit cursor and segment styling.
3. **Decorations**: polish the client-side ones (shadows, theme colors, `prefers-color-scheme` through the portal).
   xdg-decoration where offered, the tests on KWin, sway and GNOME Shell and `IFMXWaylandWindowFrame` for programs
   with their own title bar are done; next for it: window geometry insets (shadows, resize borders outside the
   window), the desktop's dark/light preference (settings portal; GNOME's font is read through it already).
4. **Clipboard and drag and drop**: image and custom clipboard formats, primary selection and more drag MIME types.
5. `FmuxOpenUrl`/`FmuxOpenFile` through the OpenURI portal (the D-Bus client is there) or `xdg-open`; the dark style
   preference through the Settings portal.
6. **Menus**: optional desktop global-menu export and accessibility integration.
7. Popup grabs, popup repositioning and touch events.
8. **X11**: extend screen support with RandR and add XIM.
9. Packaging: a design-time/package setup so the IDE builds Linux FMX projects with FMXWayland without copying paths.

## Contributors

- **[Hemul GM](https://github.com/HemulGM)** — FMX's default Linux canvas on cairo, Pango and gdk-pixbuf
  (`FMXWayland.Cairo`, `FMXWayland.CairoApi`): ordinary FMX programs draw on FMXWayland without Skia; dialogs
  (`FMXWayland.DBus`, `FMXWayland.Portal`, `FMXWayland.Dialogs`, `FMXWayland.DialogTypes`, `FMXWayland.FileDialog`):
  a D-Bus client in Pascal, the xdg-desktop-portal file dialogs, FMX's own file dialog and the replaceable dialog
  backend.

Thank you!

## License

MIT, see [LICENSE](LICENSE). Third-party notices: [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
