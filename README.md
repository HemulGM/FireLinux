# FMXWayland

A native Wayland platform for Delphi FireMonkey (FMX) on Linux, written in Object Pascal — without Embarcadero's
closed `libfmux.so` and without GTK. FMX programs talk to the Wayland compositor directly (libwayland-client and
libxkbcommon, loaded at run time) and draw with the standard FMX Cairo canvas into shared-memory buffers.

![The Hello sample on WSLg](docs/screenshots/hello.png)

Phase 1 (this state): an FMX program with the usual controls runs on WSLg and on Weston — windows, popups, mouse,
keyboard, clipboard, timers, modal forms, message boxes, HiDPI (integer) scale, client-side decorations. See
[Status](#status) and [What does not work](#what-does-not-work-yet).

## How it works

FMX for Linux (`FMX.Platform.Linux`, `FMX.Clipboard.Linux`, `FMX.Dialogs.Linux`, `FMX.Skia.Canvas`, ...) calls the
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
| `FMXWayland.Fmux` | The FMUX functions: windows (`TFmuxWindow` forwards Wayland events to FMX's callbacks), the paint context, bitmaps, timers, the loop, clipboard, modal loops, message boxes, `IFMXWaylandNativeWindow` |
| `FMXWayland.Platform` | The Wayland side, independent of FMX: connection and globals, outputs, the event loop (display fd + eventfd for wake-ups + timers, `prepare_read`/`read_events` so other readers such as Vulkan WSI can share the display), `TWlWindow` (xdg_toplevel / xdg_popup, wl_shm double/triple buffering, frame callbacks, damage, scale, client-side decorations), pointer, keyboard (xkbcommon keymap, key repeat, compose/dead keys), cursors (cursor-shape-v1 or an Xcursor theme through libwayland-cursor), clipboard (wl_data_device) |
| `FMXWayland.Wayland`, `FMXWayland.Xkb`, `FMXWayland.WaylandCursor` | Bindings of libwayland-client, libxkbcommon, libwayland-cursor, loaded with `dlopen`: programs start without link-time dependencies and say what is missing |
| `src\Protocols\FMXWayland.Protocol.*` | Generated from the protocol XML files in `protocols\` by `tools\gen-wayland.ps1`, a small wayland-scanner for Pascal |
| `FMXWayland.Cairo`, `FMXWayland.CairoApi` | Cairo canvas, Pango text layout and GdkPixbuf codecs; system libraries loaded with `dlopen` |
| `FMXWayland.Vulkan`, `FMXWayland.VulkanDevice`, `FMXWayland.VulkanApi` | Offscreen Vulkan 3D context, GPU resources and system Vulkan ABI |
| `FMXWayland.Keys` | XKB keysyms / evdev codes -> FMX virtual keys |
| `FMXWayland.Native` | `IFMXWaylandNativeWindow`, the contract for GPU canvases (below) |

**Painting.** The default canvas is `FMX.Canvas.Linux`. FMXWayland implements its FMUX drawing functions with
system Cairo: paths, transforms, clipping, gradients, opacity, strokes and bitmap drawing. Pango handles UTF-8
text shaping, font fallback, wrapping, text outlines and cursor/selection coordinates (converted to Delphi UTF-16
indexes). GdkPixbuf handles bitmap decoding and encoding, including PNG and JPEG. Cairo draws directly into
premultiplied BGRA `wl_shm` buffers. Each window retains the last frame, so rotating buffers preserve pixels
outside a partial repaint. The same canvas draws offscreen bitmaps and client-side window titles.

Skia is optional: projects that explicitly use `FMX.Skia` and enable `GlobalUseSkia` can retain the raster bitmap
presentation path. Only those projects need `libsk4d.so` and the build script's `-Skia` flag. The default sample
has no Skia dependency and runs on Ubuntu 20.04 with its system graphics libraries. Delphi 13's bundled Skia
requires GLIBC 2.35, so it cannot load on Ubuntu 20.04's GLIBC 2.31.

**Coordinates.** Wayland clients do not know where their windows are. Every window keeps a virtual origin (what FMX
set with `SetWindowRect`); `ClientToScreen`/`ScreenToClient` and the screen positions of mouse events use it, so
FMX's own conversions stay consistent. Popups (combo box lists, popup menus — FMX forms with `FormStyle = Popup`)
become xdg_popups placed relative to their parent (the form of their placement target) and take the position the
compositor gives them.

**Decorations and window settings.** FMXWayland negotiates server/client decorations, implements all five
Delphi border styles, the configured BorderIcons, Unicode captions, application/per-window icons and initial/runtime
size constraints. Unsupported actions are hidden according to xdg-shell capabilities. Custom button sets and tool/fixed
windows request client decorations; the compositor can override the requested mode. See the
[window settings matrix and Wayland limits](docs/window-management.md). `FMXWAYLAND_DECORATIONS=client` requests
client decorations for all decorated windows; `FMXWAYLAND_CSD=0` disables client decorations.

## Requirements

- Delphi 13 (RAD Studio 37.0) with the Linux platform (Enterprise/Architect), FMX Linux sources installed
  (`source\fmx\FMUX.Api.pas`, or the FMX Linux GetIt package's `source\FMUX.Api.pas`).
- A Linux platform SDK to link against: `tools\make-linux-sdk.ps1` makes one from a WSL distribution (or use the
  IDE's SDK manager).
- At run time: a Wayland compositor with `wl_compositor`, `wl_shm` and `xdg_wm_base`; the libraries
  libwayland-client0 and libxkbcommon0 (libwayland-cursor0 for cursors on compositors without cursor-shape-v1);
  system Cairo, Pango/PangoCairo and GdkPixbuf. The default sample needs no `libsk4d.so`, GTK, X11 or libfmux.

## Using it in a project

1. Generate `FMUX.Api.pas` (`.\tools\gen-fmux-api.ps1 -Out <dir>\FMUX.Api.pas`) and put `<dir>`, `src` and
   `src\Protocols` **first** on the unit search path (the IDE/`dcclinux64` then compile it instead of linking
   Embarcadero's precompiled `FMUX.Api`).
2. Use the standard FMX canvas — in the .dpr:

   ```pascal
   uses
     System.StartUpCopy, FMX.Forms, FMX.Types, MainForm in 'MainForm.pas';
   begin
     Application.Initialize;
     ...
   ```

Nothing else changes in the program. `samples\Hello\Hello.dproj` generates the replacement next to its .dpr
with `tools\prepare-ide-build.ps1` before the Linux64 build. Its search path includes `src` and `src\Protocols`.

## 3D: OpenGL

`FMXWayland.OpenGL` provides the native context functions used by the stock
`FMX.Context.Linux` renderer. `TViewport3D` supports FMX meshes, shaders, lit and textured
materials, depth/stencil buffers and multisampling. Rendering uses offscreen FBOs;
FMX reads the BGRA result into its bitmap and Cairo composites it with the 2D controls.
Main and worker contexts share textures and other shareable GL objects. Native resources
are released before the Wayland connection closes; worker threads must be joined first.

This uses the system `libEGL.so.1` and `libGL.so.1`, desktop compatibility OpenGL,
`EGL_EXT_platform_wayland` and `EGL_KHR_surfaceless_context`. It needs neither X11 nor
`libwayland-egl`, and initialization stays lazy for programs that only use 2D controls.
The demo's **3D / OpenGL** tab (`--tab=3d`) shows a textured rotating cube, a lit sphere,
a camera, and pause/reset controls.

Build `tests\OpenGLChecks.dpr` with `tools\build.ps1 -SearchPath samples\Hello`, then run
it in a Wayland session. It checks BGRA readback, worker texture sharing, actual viewport
pixels, rotation, resizing, and multisample recreation. Tested on WSLg with DISPLAY unset,
Mesa 21.2.6 desktop OpenGL 3.1.

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

## Dialog backends

The default backend uses XDG Desktop Portal for `TOpenDialog`/`TSaveDialog`, automatically falling back to FMX
when the service is unavailable or does not support the requested mode. Messages and input use FMX forms.
The application communicates with D-Bus using Object Pascal and Delphi RTL; it does not load GTK,
Qt or libdbus. The desktop's portal provider draws the native file chooser in a separate process.
Both synchronous and asynchronous FMX dialog services use the selected backend.

```pascal
uses FMXWayland.Dialogs, FMXWayland.DialogTypes;

// TMyDialogs implements IFMXWaylandDialogBackend, or derives from TFMXWaylandDialogBackend.
SetWaylandDialogBackend(TMyDialogs.Create);
// All subsequent TOpenDialog/TSaveDialog, MessageDlg and InputQuery calls use it.
SetWaylandDialogBackend(TFMXWaylandDialogBackend.Create); // Force pure FMX for all dialogs.
SetWaylandDialogBackend(nil); // Restore Portal with automatic FMX fallback.
```

`TFMXWaylandDialogBackend` supplies a complete FMX file browser, messages and input. Its file browser supports
folder navigation, typed paths, filters, hidden files, multi-selection, folder selection, creating folders,
and overwrite confirmation. The static layout in `src\FMXWayland.FileDialog.fmx` uses `Align` and `TLayout`.
Override `FileDialog`, `MessageDialog` or `InputQuery` when you need your own forms.
The file request contains open/save/folder mode, title, initial path, filters, one-based filter
index, multiple selection and overwrite confirmation. Return `False` on cancellation. The backend is held by
an interface reference, including for queued asynchronous requests; change it on the UI thread.

Runtime requirements for native files: a session D-Bus, `xdg-desktop-portal`, and an installed FileChooser
provider (GNOME/GTK, KDE, etc.). The session address is read from `DBUS_SESSION_BUS_ADDRESS`, the user bus
socket, or the cached X11 bus address used by WSL without systemd. PAServer must run in the same user session.
See [the FileChooser specification](https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.portal.FileChooser.html).

Limits: directory selection requires FileChooser version 3; Ubuntu 20.04's version 2 supports files only,
so `SelectDirectory` automatically uses the FMX folder picker there.
The FMX Linux ABI has a 1024-character file-list buffer; too-long selections raise an exception instead of
silently truncating paths. Portal save dialogs always handle overwrite confirmation; `ConfirmOverwrite` is
available to custom backends. FMX's ABI does not forward `DefaultExt` or every `TOpenOption` to the backend.
Without an exported Wayland parent identifier, the portal window is standalone; input to application forms
is blocked while it is open, but event processing and painting continue. Portal errors are reported as
`EDBusError`. Cancellation never opens another dialog, and malformed responses or errors in an already opened
portal request do not trigger fallback. Missing services/interfaces, unavailable D-Bus, a capability-probe
timeout, and unsupported versions use FMX; the FMX backend needs no portal packages.

Tests: build `tests\DialogChecks.dpr` with `tools\build.ps1`, then run
`dbus-run-session -- sh tests/dialog-checks.sh <binary>` in WSL. The isolated Python fixture needs `python3-dbus`
and `python3-gi` only for testing. `DialogChecks --real-portal` opens the actual file chooser and cancels it
automatically. The tests cover backend switching, queued calls, Unicode, filters, multi-selection, save,
cancel/error responses, early signals, bounds, request cleanup, and FMX message/input forms.
`tests\FMXFileDialogChecks.dpr` covers actual FMX file forms. Run it directly for the pure backend, or pass it
through the same shell fixture with `FMX_TEST_PORTAL_MODE=version2` / `missing` and `--fallback-version2` /
`--fallback-missing`. `--fallback-no-bus` tests an unavailable bus. The tests create and remove their own
temporary directory.

## Building

```powershell
.\tools\make-linux-sdk.ps1 -Sdk D:\LinuxSDK\ubuntu-26.04 -Install   # once: libc, crt*.o, libgcc of the WSL distribution
.\tools\build.ps1 -Project samples\Hello\Hello.dpr                   # Release; -Config Debug
```

`build.ps1` generates `FMUX.Api.pas` into `<BuildRoot>\gen`, compiles with `dcclinux64` (linking with its lld against
the SDK: `--syslibroot`, `--libpath`). With `-Skia` it also copies `libsk4d.so` next to the program. Everything goes to `-BuildRoot`
(default `D:\Work\FMXWayland-build`: `bin\Linux64\<Config>\`, `dcu\`). It also works around the missing Linux64
`FMX.Filter.res` of Delphi 13. Use `-Bds` for a non-default Delphi installation and `-FmxLinux` for a GetIt
installation. The sample .dproj uses the SDK selected in the IDE (avoid specifying a second sysroot when
the SDK profile already supplies one):

```
msbuild samples\Hello\Hello.dproj /t:Build /p:Config=Release /p:Platform=Linux64
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
`XCURSOR_THEME`, `XCURSOR_SIZE` for cursor themes.

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

The `samples\Hello` demo has six tabs: controls, animations/images, dialogs, windows/platform, drag/drop, and 3D/OpenGL.
All static controls, timers, animations and dialog components are streamed from `HelloMain.fmx`;
independent and modal windows share `HelloWindow.fmx`. The existing WinUI3 style book is preserved.
Layouts use `Align`, `TLayout`, and scroll boxes. Add future sections as new `TTabItem` children of `DemoTabs`.
The dialog page switches between automatic Portal → FMX selection and the pure FMX backend. PNG/JPEG samples
are embedded in the form; the originals in `samples\Hello\assets` need no deployment entries.
Use `--tab=images|dialogs|platform|drag` to select the initial page, or `--selftest` for the integration checks.
With `--verbose`, the demo logs actual control centers; the real-input test uses these instead of fixed coordinates.
`tests\HelloDemoChecks.dpr` verifies the streamed event bindings, dialog mode routing, image loading and resizing
without user input; build it with `-SearchPath samples\Hello` and pass `samples/Hello/assets/landscape.png` at run time.

- `tests\hello-e2e.ps1` — end to end on WSLg with **real input**: it moves the Windows mouse and types (WSLg forwards
  Windows input to its compositor over RDP, so events take the real wl_pointer/wl_keyboard path), takes screenshots
  of the windows and checks the program's log: pointer, button clicks, typing (any keyboard layout), editing keys,
  Ctrl+A/Ctrl+X, mouse wheel, clipboard both ways (WSLg shares it with Windows), combo box popup, check box, second
  form, modal form (the main window must not react meanwhile), close request from the compositor, the close and
  maximize buttons of the client-side title bar, maximize/restore, resize from code, clean exit. Needs an
  interactive desktop nobody else is using (it takes the mouse for about a minute).
- `tests\weston-headless.ps1` — non-interactive: the sample on a private headless Weston 14 at output scale 1 and
  2 (buffer size through `IFMXWaylandNativeWindow`, the program's frame dump, a compositor screenshot, clean exit).

Evidence of the last runs: all checks of both passed (WSLg on Windows 11 with Ubuntu 26.04, Weston 14.0.2 headless);
`Hello --selftest` also runs to the end on WSLg (its seat appears only after the RDP client connects, a second or so
after the program starts: the clipboard falls back to a process-local one until then).

| | |
|---|---|
| ![combo box popup](docs/screenshots/hello-combo-popup.png) | ![message box](docs/screenshots/hello-message-dialog.png) ![modal form](docs/screenshots/hello-modal.png) |

Headless Weston, output scale 2 (2x rendering, client-side decorations, the combo box drop-down as an xdg_popup):

![Weston at scale 2](docs/screenshots/weston-headless-scale2.png)

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
  `EndScene`), but stops attaching its own wl_shm frames. FMXWayland still sets the surface's buffer scale (or the
  viewport destination with fractional scaling) and the decoration subsurface; that state is double-buffered and
  takes effect with the presenter's next commit (`vkQueuePresentKHR`).
- Everything is on the main thread; FMXWayland dispatches only the default event queue, with the
  `wl_display_prepare_read` protocol, so Vulkan WSI's own queue can coexist.

## Status

Tested on WSLg (Weston-based, RDP; xdg_wm_base 1, no xdg-decoration, no cursor-shape, no fractional-scale) and
Weston 14 headless (scale 1 and 2). 105 of 186 FMUX functions are assigned (84 fully, 21 partly); the full list:
[docs/FMUX-STATUS.md](docs/FMUX-STATUS.md).

| Area | FMUX functions | Status |
|---|---|---|
| Application, loop, threads | FmuxInit, FmuxRun, FmuxHandleMessage, FmuxTerminate, FmuxWakeMainThread, FmuxGetKeyState, FmuxGet/SetVersionInfo | implemented |
| Timers | FmuxCreateTimer, FmuxDestroyTimer | implemented |
| Windows | FmuxCreateWindow, FmuxDestroyWindow, FmuxShowWindow, FmuxSetWindowState, FmuxSetWindowTitle, FmuxGet/SetClientSize, FmuxGetWindowRect, FmuxInvalidateRect, FmuxProcessUpdates, FmuxClientToScreen, FmuxScreenToClient, FmuxGetWindowScale, FmuxGet/SetWindowFullScreen, FmuxShowModal, FmuxSetMainWindow | implemented |
| Windows (Wayland limits) | FmuxSetWindowRect (position virtual), FmuxActivateWindow/FmuxWindowBringToFront (xdg-activation request), FmuxWindowSendToBack (no-op), FmuxSetWindowIcon (shell icon requires xdg-toplevel-icon-v1), FmuxSetCapture/ReleaseCapture (implicit grab), FmuxGetWindowNativeHandle/DrawingHandle (wl_surface) | partial |
| Popups | through FmuxCreateWindow (Popup) / FmuxShowWindow | implemented (xdg_popup, no grab) |
| Screens | FmuxGetScreenSize, FmuxGetScreenScale, FmuxGetDisplayFromWindow, FmuxGetDisplayFromPoint; FmuxGetDisplayInfo (work area = output) | implemented / partial |
| Mouse, cursor | FmuxGetMousePos (partial: last position over an own window), FmuxSetCursor | implemented |
| Keyboard | (FmuxKey callback): xkbcommon, repeat, compose, layout-independent shortcuts | implemented |
| Painting (Cairo and optional Skia raster canvas) | FmuxBitmapCreate, FmuxBitmapDestroy, FmuxGetBitmapInfo, FmuxCanvasDrawBitmap | implemented |
| Clipboard | FmuxClipboardHas/Get/SetText | implemented |
| Clipboard, other formats | FmuxClipboardHas/GetImage, FmuxClipboardHas/GetCustom (report "none"); FmuxClipboardSetImage/SetCustom/SetArray | partial / stub |
| Dialogs | FmuxFilesDialog (XDG Portal), FmuxMessageDialog, FmuxInputQuery (FMX forms) | implemented; replaceable backend |
| IME | FmuxImeEnterControl/ExitControl/SetCaretPos | text-input-v3; stock FMUX preedit attribute limit |
| Tooltips, gestures | FmuxAddTooltip/RemoveTooltip, FmuxAdd/RemoveGestureRecognizer (no-ops) | partial |
| Cairo canvas, text layouts | FmuxCanvas*, FmuxCreateContext, FmuxCreateTextLayout... | implemented (Cairo/Pango) |
| OpenGL contexts | FmuxCreateSharedContext, FmuxCreateThreadContext, FmuxMakeCurrentContext | EGL/Wayland; shared desktop GL contexts for TViewport3D |
| Fonts | FmuxAddCustomFont..., FmuxGetFontName | stub |
| Main menu | IFMXMenuService / FMXWayland.Menus | TMainMenu rendered inside the window; xdg_popup submenus; legacy FMUX menu slots bypassed |
| Printing, PDF | FmuxEnumPrinters ... FmuxSetAlwaysAskOutputFile | stub |
| Web view, media, video capture | FmuxCreateWebView..., FmuxCreateMedia..., FmuxCaptureDeviceEnum... | stub |
| Shell | FmuxOpenFile, FmuxOpenUrl, FmuxGetFileIcon, FmuxGetFileType | stub |
| Drag and drop | FmuxBeginDragDrop / IFMXDragDropService | text, files, internal FMX data over wl_data_device |
| Synthetic events, screenshots | FmuxGen*, FmuxTakeScreenshot, FmuxGetCursor... | stub |

## What does not work yet

- Clipboard images and custom formats,
  touch and gestures, tooltips, printing, web browser, media player.
- Window positions are not under the program's control (Wayland); `Position = poScreenCenter` and the like have no
  effect. Popups do not grab the pointer (xdg_popup.grab): they close like other FMX popups (a click elsewhere in
  the program, or the form losing activation when another application is clicked).
- Fractional scaling (wp_fractional_scale_v1 + wp_viewporter) is implemented but untested (neither WSLg nor Weston 14
  offer it); scale changes after start (moving a window to a monitor with another scale) are reported to FMX with
  `TScaleChangedMessage` but not tested.
- `FmuxActivateWindow`/`FmuxWindowBringToFront` ask for activation with an xdg-activation token (the compositor
  decides); untested, neither WSLg nor Weston 14 offer xdg_activation_v1.

## Next steps

1. **FastCanvas (Vulkan)**: FastCanvas declares `IFMXWaylandNativeWindow` (contract above), creates its
   `VkSurfaceKHR` on Wayland and calls `SetExternalPresentation`; test both canvases side by side.
2. **IME**: a text-input-v1 adapter for older WSLg, and a text-service extension for precise preedit cursor/segment styling.
3. **Decorations**: polish the client-side ones (shadows, theme colors, `prefers-color-scheme` through the portal);
   use xdg-decoration where offered (done) and test on KDE/sway and GNOME.
4. **Clipboard** images and custom formats, primary selection; additional drag MIME formats.
5. **OpenURI**: `FmuxOpenUrl`/`FmuxOpenFile` through the OpenURI portal or `xdg-open`.
6. **Menus**: optional desktop global-menu export through KDE appmenu + D-Bus; additional accessibility integration.
7. Popup grabs (`xdg_popup.grab` for menus), `xdg_popup.reposition` (version 3),
   touch (wl_touch -> FMX touch/gesture callbacks).
8. **X11 fallback backend** sharing the FMX adapter (`FMXWayland.Fmux` talks to the Wayland core through
   `TWlWindow`'s events; an X11 core with the same shape would plug in).
9. Packaging: a design-time/package setup so the IDE builds Linux FMX projects with FMXWayland without copying paths.

## License

MIT, see [LICENSE](LICENSE). Third-party notices: [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
