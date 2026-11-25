{ FireLinux FMUX compatibility unit for FMX Linux 1.82 on RAD Studio 37.0. }

unit FMUX.Api;

interface

{$SCOPEDENUMS ON}
{$MINENUMSIZE 4}

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.IOUtils,
  FMX.Types, FMX.Graphics;

const
  FMUX_INIT_NOWAYLAND = 1;

type
  TFmuxWakeMainThreadProc = procedure(); cdecl;

  TFmuxIdleProc = procedure(); cdecl;

var
  FmuxInit: procedure(Flags: Integer); cdecl;
  FmuxRun: procedure(IdleProc: TFmuxIdleProc); cdecl;
  FmuxTerminate: procedure; cdecl;
  FmuxHandleMessage: function: Boolean; cdecl;
  FmuxWakeMainThread: procedure(Proc: TFmuxWakeMainThreadProc); cdecl;

const
  FMUX_STATE_Shift = 1;
  FMUX_STATE_Alt = 2;
  FMUX_STATE_CTRL = 4;
  FMUX_STATE_LEFT = 8;
  FMUX_STATE_RIGHT = 16;
  FMUX_STATE_MIDDLE = 32;
  FMUX_STATE_DOUBLE = 64;
  FMUX_STATE_SUPER = 128;

type
  PRectFArray = ^TRectFArray;

  TRectFArray = array[0..0] of TRectF;

  TFmuxWindowState = (Normal, Minimized, Maximized);

  TFmuxMotionKind = (Move, Down, Up, Drag, Scroll);

  TFmuxKeyKind = (Down, Up);

  TFmuxDragAction = (Over, Drop, Cancel);

  TFmuxDragOperation = (None, Move, Copy, Link);

  TFmuxGestureKind = (Zoom, Pan, Rotate, TwoFingerTap, PressAndTap, LongTap, DoubleTap);

  TFmuxGestureState = (Start, Inertia, Finish);

  TFmuxGestureData = record
    Angle, AngleDelta: Single;
    Direction: Integer;
    Offset: Single;
  end;

  TFmuxTouchKind = (TouchBegin, TouchUpdate, TouchEnd);

  TFmuxDragData = record
    Internal: Boolean;
    Files: PPChar;
    Text: PChar;
  end;

  TFmuxPaintCallback = procedure(Data: Pointer; Ctx: Pointer; Rects: PRectFArray; Count: Integer); cdecl;

  TFmuxStateChanged = procedure(Data: Pointer; State: TFmuxWindowState); cdecl;

  TFmuxBoundsChanged = procedure(Data: Pointer; NewBounds: TRectF); cdecl;

  TFmuxWindowActivate = procedure(Data: Pointer; Active: Boolean); cdecl;

  TFmuxClose = procedure(Data: Pointer); cdecl;

  TFmuxMotion = procedure(Data: Pointer; Kind: TFmuxMotionKind; X, Y: Single; State: Integer); cdecl;

  TFmuxKey = procedure(Data: Pointer; Kind: TFmuxKeyKind; Key: Word; KeyChar: Char; State: Integer); cdecl;

  TFmuxDrag = procedure(Data: Pointer; DragData: TFmuxDragData; X, Y: Single; Action: TFmuxDragAction; var Operation: TFmuxDragOperation); cdecl;

  TFmuxClosePopups = procedure(Data: Pointer); cdecl;

  TFmuxMenuAdded = procedure(Data: Pointer); cdecl;

  TFmuxGesture = procedure(Data: Pointer; Kind: TFmuxGestureKind; State: TFmuxGestureState; var Value: TFmuxGestureData); cdecl;

  TFmuxTouch = procedure(Data: Pointer; Kind: TFmuxTouchKind; X, Y: Single; Seq: NativeInt); cdecl;

  TFmuxBorderStyle = (None, Single, Sizeable, ToolWindow, SizeToolWin);

  TFmuxCreateStruct = record
    OpenGL: Boolean;
    X, Y, Width, Height: Single;
    BorderStyle: TFmuxBorderStyle;
    Transparent: Boolean;
    Popup: Boolean;
    StayOnTop: Boolean;
    Title: PChar;
    Data: Pointer;
    PaintCallback: TFmuxPaintCallback;
    BoundsChanged: TFmuxBoundsChanged;
    StateChanged: TFmuxStateChanged;
    Close: TFmuxClose;
    Motion: TFmuxMotion;
    Key: TFmuxKey;
    Activate: TFmuxWindowActivate;
    Drag: TFmuxDrag;
    SystemMenuIcon, MinimizeIcon, MaximizeIcon: Boolean;
    ClosePopups: TFmuxClosePopups;
    MenuAdded: TFmuxMenuAdded;
    Gesture: TFmuxGesture;
    Touch: TFmuxTouch;
  end;

var
  FmuxCreateWindow: function(var CreateStruct: TFmuxCreateStruct): Pointer; cdecl;
  FmuxDestroyWindow: procedure(Wnd: Pointer); cdecl;
  FmuxSetMainWindow: procedure(Wnd: Pointer); cdecl;
  FmuxSetWindowState: procedure(Wnd: Pointer; AState: TFmuxWindowState); cdecl;
  FmuxSetWindowTitle: procedure(Wnd: Pointer; Title: PChar); cdecl;
  FmuxSetWindowIcon: procedure(Wnd: Pointer; Data: Pointer; Size: Integer); cdecl;
  FmuxShowWindow: procedure(Wnd: Pointer; Show: Boolean); cdecl;
  FmuxActivateWindow: procedure(Wnd: Pointer); cdecl;
  FmuxWindowBringToFront: procedure(Wnd: Pointer); cdecl;
  FmuxWindowSendToBack: procedure(Wnd: Pointer); cdecl;
  FmuxGetClientSize: procedure(Wnd: Pointer; var R: TPointF); cdecl;
  FmuxSetClientSize: procedure(Wnd: Pointer; R: TPointF); cdecl;
  FmuxGetWindowRect: procedure(Wnd: Pointer; var R: TRectF); cdecl;
  FmuxSetWindowRect: procedure(Wnd: Pointer; R: TRectF); cdecl;
  FmuxInvalidateRect: procedure(Wnd: Pointer; R: TRectF); cdecl;
  FmuxProcessUpdates: procedure(Wnd: Pointer); cdecl;
  FmuxClientToScreen: function(Wnd: Pointer; Point: TPointF): TPointF; cdecl;
  FmuxScreenToClient: function(Wnd: Pointer; Point: TPointF): TPointF; cdecl;
  FmuxGetScreenSize: function: TPointF; cdecl;
  FmuxGetScreenScale: function: Single; cdecl;
  FmuxGetWindowScale: function(Wnd: Pointer): Single; cdecl;
  FmuxGetWindowFullScreen: function(Wnd: Pointer): Boolean; cdecl;
  FmuxSetWindowFullScreen: procedure(Wnd: Pointer; AValue: Boolean); cdecl;
  FmuxSetCapture: procedure(Wnd: Pointer); cdecl;
  FmuxReleaseCapture: procedure(Wnd: Pointer); cdecl;

  // Return GTK+ handle of window
  FmuxGetWindowNativeHandle: function(Wnd: Pointer): Pointer; cdecl;
  // Return GTK+ drawingare handle of window
  FmuxGetWindowNativeDrawingHandle: function(Wnd: Pointer): Pointer; cdecl;
  FmuxAddTooltip: procedure(Wnd: Pointer; Text: PChar); cdecl;
  FmuxRemoveTooltip: procedure(Wnd: Pointer); cdecl;
  FmuxAddGestureRecognizer: procedure(Wnd: Pointer; ARec: Integer); cdecl;
  FmuxRemoveGestureRecognizer: procedure(Wnd: Pointer; ARec: Integer); cdecl;

type
  TFmuxModal = procedure(Data: Pointer; var Result: Integer); cdecl;

var
  FmuxShowModal: function(Wnd: Pointer; Proc: TFmuxModal): Integer; cdecl;

type
  TFmuxTimerProc = procedure(Data, Code: Pointer); cdecl;

  TFmuxPathPointKind = (MoveTo, LineTo, CurveTo, Close);

  PFmuxPathPoint = ^TFmuxPathPoint;

  TFmuxPathPoint = record
    Kind: TFmuxPathPointKind;
    Point: TPointF;
  end;

  PFmuxPathPointArray = ^TFmuxPathPointArray;

  TFmuxPathPointArray = array[0..0] of TFmuxPathPoint;

  PFmuxGradient = ^TFmuxGradient;

  TFmuxGradient = record
    Offset: Single;
    Color: TAlphaColor;
  end;

  PFmuxGradientArray = ^TFmuxGradientArray;

  TFmuxGradientArray = array[0..0] of TFmuxGradient;

const
  FmuxCanvasQualityDefault = 0;
  FmuxCanvasQualityHighPerformance = 1;
  FmuxCanvasQualityHighQuality = 2;

var
  FmuxGetKeyState: function: Integer; cdecl;
  FmuxCreateTimer: function(Interval: Integer; TimerFunc: TFmuxTimerProc; Data, Code: Pointer): NativeInt; cdecl;
  FmuxDestroyTimer: function(Timer: NativeInt): Boolean; cdecl;
  FmuxSetClipRects: procedure(Ctx: Pointer; const ARects: PRectF; const Count: Integer); cdecl;
  FmuxIntersectClipRect: procedure(Ctx: Pointer; const ARect: TRectF); cdecl;
  FmuxExcludeClipRect: procedure(Ctx: Pointer; const ARect: TRectF); cdecl;
  FmuxSave: procedure(Ctx: Pointer); cdecl;
  FmuxRestore: procedure(Ctx: Pointer); cdecl;
  FmuxCanvasSetQuality: procedure(Ctx: Pointer; Quality: Integer); cdecl;
  FmuxCanvasClear: procedure(Ctx: Pointer; C: TAlphaColor); cdecl;
  FmuxCanvasClearRect: procedure(Ctx: Pointer; R: TRectF; C: TAlphaColor); cdecl;
  FmuxCanvasSetMatrix: procedure(Ctx: Pointer; m11, m12, m21, m22, m31, m32: Single); cdecl;
  FmuxCanvasSetFillColor: procedure(Ctx: Pointer; C: TAlphaColor); cdecl;
  FmuxCanvasSetFillGradient: procedure(Ctx: Pointer; P1, P2: TPointF; Gradient: PFmuxGradient; Count: Integer); cdecl;
  FmuxCanvasSetFillRadialGradient: procedure(Ctx: Pointer; Center, P1, P2: TPointF; Gradient: PFmuxGradient; Count: Integer); cdecl;
  FmuxCanvasSetFillBitmap: procedure(Ctx: Pointer; Bitmap: Pointer; Rect: TRectF; Mode: Integer); cdecl;
  FmuxCanvasEllipse: procedure(Ctx: Pointer; R: TRectF); cdecl;
  FmuxCanvasRect: procedure(Ctx: Pointer; R: TRectF); cdecl;
  FmuxCanvasLine: procedure(Ctx: Pointer; APt1, APt2: TPointF); cdecl;
  FmuxCanvasPath: procedure(Ctx: Pointer; Pts: PFmuxPathPoint; Count: Integer); cdecl;
  FmuxCanvasFill: procedure(Ctx: Pointer; Opacity: Single); cdecl;
  FmuxCanvasPtInPath: function(Pt: TPointF; Pts: PFmuxPathPoint; Count: Integer): Boolean; cdecl;
  FmuxCanvasStroke: procedure(Ctx: Pointer; Opacity: Single); cdecl;
  FmuxCanvasSetStrokeWidth: procedure(Ctx: Pointer; Width: Single); cdecl;
  FmuxCanvasSetStrokeCap: procedure(Ctx: Pointer; Cap: Integer); cdecl;
  FmuxCanvasSetStrokeJoin: procedure(Ctx: Pointer; Join: Integer); cdecl;
  FmuxCanvasSetStrokeDash: procedure(Ctx: Pointer; Offset: Single; DashArray: Pointer; Length: Integer); cdecl;
  FmuxBitmapCreate: function(Width, Height: Integer; Bits: Pointer): Pointer; cdecl;
  FmuxBitmapDestroy: procedure(Bitmap: Pointer); cdecl;
  FmuxGetBitmapInfo: procedure(Bitmap: Pointer; var Width, Height: Integer; var Data: Pointer); cdecl;
  FmuxCanvasDrawBitmap: procedure(Ctx, Bitmap: Pointer; Src, Dst: TRectF; Opacity: Single; HighSpeed: Boolean); cdecl;
  FmuxCreateContext: function(Bitmap: Pointer): Pointer; cdecl;
  FmuxDestroyContext: procedure(Ctx: Pointer); cdecl;

type
  TFmuxReadFunc = function(Param: Pointer; Bits: Pointer; Length: LongWord): Integer; cdecl;

  TFmuxWriteFunc = function(Param: Pointer; Bits: Pointer; Length: LongWord): Integer; cdecl;

var
  FmuxBitmapLoad: function(ReadFunc: TFmuxReadFunc; Param: Pointer; var W, H: Integer; var Bits: Pointer): Pointer; cdecl;
  FmuxBitmapSave: function(ReadFunc: TFmuxReadFunc; Param: Pointer; W, H: Integer; Bits: Pointer; Extension: PChar): Boolean; cdecl;

type
  TFmuxFont = record
    Family: PChar;
    Size: Single;
    Weight: Integer;
    Slant: Integer;
    Underline: Boolean;
    Strikeout: Boolean;
  end;

var
  FmuxCreateTextLayout: function(Text: PChar; var Font: TFmuxFont; Width, Height: Single; Align, Trimming: Integer; WordWrap: Boolean): Pointer; cdecl;
  FmuxDestroyTextLayout: procedure(Layout: Pointer); cdecl;
  FmuxDrawTextLayout: procedure(Ctx, Layout: Pointer; X, Y: Single); cdecl;
  FmuxGetTextLayoutRect: procedure(Layout: Pointer; var R: TRectF); cdecl;
  FmuxLayoutPositionAtPoint: function(Layout: Pointer; APoint: PPointF): Integer; cdecl;
  FmuxLayoutMeasureRange: function(Layout: Pointer; APos, ALength: Integer; Region: PRectF): Integer; cdecl;
  FmuxLayoutToPath: function(Layout: Pointer; Pts: PFmuxPathPoint; Count: Integer): Integer; cdecl;
  FmuxAddCustomFont: function(FileName: PChar): Integer; cdecl;
  FmuxAddCustomFontFromData: function(Data: Pointer; Len: Integer): Integer; cdecl;
  FmuxGetFontCount: function: Integer; cdecl;
  FmuxGetFontName: function(Index: Integer): PChar; cdecl;

type
  TFmuxLog = procedure(S: PChar); cdecl;

var
  FmuxSetLog: procedure(Log: TFmuxLog); cdecl;
  FmuxCreateSharedContext: function: Pointer; cdecl;
  FmuxCreateThreadContext: function: Pointer; cdecl;
  FmuxMakeCurrentContext: procedure(Ctx: Pointer); cdecl;
  FmuxFlushBuffer: procedure(Wnd: Pointer; Texture: Integer); cdecl;

type
  TFmuxMenuClick = procedure(Data: Pointer); cdecl;

  PFmuxMenuItem = ^TFmuxMenuItem;

  TFmuxMenuItem = record
    Text: PChar;
    ShortCut: Integer;
    Data: Pointer;
    Visible: Boolean;
    Checked: Boolean;
    Radio: Boolean;
    Click: TFmuxMenuClick;
  end;

var
  FmuxCreateMainMenu: function(Wnd: Pointer): Pointer; cdecl;
  FmuxCreateMenu: function(Wnd: Pointer): Pointer; cdecl;
  FmuxCreateMenuItem: function(Item: PFmuxMenuItem): Pointer; cdecl;
  FmuxMenuAddItem: procedure(Menu: Pointer; Item: Pointer); cdecl;
  FmuxSetSubmenu: procedure(Item: Pointer; Menu: Pointer); cdecl;
  FmuxUpdateMenuItem: function(Item: Pointer; ItemRec: PFmuxMenuItem): Pointer; cdecl;

const
  FMUX_DGL_Warning = 0;
  FMUX_DGL_Error = 1;
  FMUX_DGL_Information = 2;
  FMUX_DGL_Confirmation = 3;
  FMUX_DGL_Custom = 4;
  FMUX_BTN_Yes = 1;
  FMUX_BTN_No = 2;
  FMUX_BTN_OK = 4;
  FMUX_BTN_Cancel = 8;
  FMUX_BTN_Abort = 16;
  FMUX_BTN_Retry = 32;
  FMUX_BTN_Ignore = 64;
  FMUX_BTN_All = 128;
  FMUX_BTN_NoToAll = 256;
  FMUX_BTN_YesToAll = 512;
  FMUX_BTN_Help = 1024;
  FMUX_BTN_Close = 2048;

var
  FmuxMessageDialog: function(AMessage: PChar; DlgType, Buttons: Integer): Integer; cdecl;
  FmuxInputQuery: function(ACaption, APromt, AValue: PChar; MaxLength: Integer): Boolean; cdecl;

function MsgDlgButtonsToButtons(Btns: TMsgDlgButtons): Integer;

const
  FMUX_FilesDialog_OPEN = 1;
  FMUX_FilesDialog_SAVE = 2;
  FMUX_FilesDialog_FOLDER = 4;
  FMUX_FilesDialog_MULTY = 8;
  FMUX_FilesDialog_OVERWRITE = 16;

var
  FmuxFilesDialog: function(Title, Filter, InitialName, InitialDir, Files: PChar; MaxLength: Integer; var FilterIndex: Integer; AOptions: Integer): Boolean; cdecl;

var
  FmuxClipboardHasText: function: Boolean; cdecl;
  FmuxClipboardGetText: function: PChar; cdecl;
  FmuxClipboardSetText: procedure(Text: PChar); cdecl;
  FmuxClipboardHasImage: function: Boolean; cdecl;
  FmuxClipboardGetImage: procedure(Data: Pointer; var W, H: Integer); cdecl;
  FmuxClipboardSetImage: procedure(Data: Pointer; W, H: Integer); cdecl;
  FmuxClipboardHasCustom: function(Format: PChar): Boolean; cdecl;
  FmuxClipboardGetCustom: procedure(Format: PChar; Data: Pointer; var Size: Integer); cdecl;
  FmuxClipboardSetCustom: procedure(Format: PChar; Data: Pointer; Size: Integer); cdecl;

type
  TFmuxClipboardData = record
    Format: PChar;
    Data: Pointer;
    Size: Integer;
  end;

  PFmuxClipboardDataArray = ^TFmuxClipboardDataArray;

  TFmuxClipboardDataArray = array[0..0] of TFmuxClipboardData;

var
  FmuxClipboardSetArray: procedure(Data: PFmuxClipboardDataArray; Count: Integer); cdecl;

{ Printer }

type
  TFmuxPrintersEnum = procedure(Data: Pointer; Printer: Pointer; Title: PChar); cdecl;

  TFmuxPrintProc = procedure(Page: Integer; Data, Context: Pointer); cdecl;

  TFmuxPageSettings = record
    Width: Single;
    Height: Single;
    Orientation: Integer;
    Margins: TRectF;
  end;

const
  FMUX_poPrintToFile = 1;
  FMUX_poPageNums = 2;
  FMUX_poSelection = 4;
  FMUX_poWarning = 8;
  FMUX_poHelp = 16;
  FMUX_poDisablePrintToFile = 32;

var
  FmuxEnumPrinters: procedure(EnumProc: TFmuxPrintersEnum; Data: Pointer); cdecl;
  FmuxIsDefaultPrinter: function(Printer: Pointer): Boolean; cdecl;
  FmuxGetPageSettings: function(var Settings: TFmuxPageSettings): Boolean; cdecl;
  FmuxPrintDialog: function(var ACollate, APrintToFile: Boolean; var AFromPage, AToPage, ACopies: Integer; AMinPage, AMaxPage: Integer; var APrintRange: TPrintRange; AOptions: Integer; var APrinterIndex: Integer): Boolean; cdecl;
  FmuxPageSetupDefault: function(var AMargin, AMinMargin: TRect; var APaperSize: TPointF; var AUnits: TPageMeasureUnits; AOptions: Integer): Boolean; cdecl;
  FmuxPageSetupDialog: function(var AMargin, AMinMargin: TRect; var APaperSize: TPointF; var AUnits: TPageMeasureUnits; AOptions: Integer): Boolean; cdecl;
  FmuxPrinterRun: function(ShowPrintDialog: Boolean; NumberOfPage: Integer; Data: Pointer; Proc: TFmuxPrintProc): Boolean; cdecl;
  FmuxGetOrientation: function: Integer; cdecl;
  FmuxSetOrientation: procedure(Orientation: Integer); cdecl;

type
  TFmuxPDFWriter = function(UserData: Pointer; Data: Pointer; Length: Cardinal): Boolean; cdecl;

var
  FmuxCreatePDFContext: function(UserData: Pointer; Writer: TFmuxPDFWriter; W, H: Single): Pointer; cdecl;
  FmuxDestroyPDFContext: procedure(context: Pointer); cdecl;
  FmuxPDFContextNewPage: procedure(context: Pointer); cdecl;
  FmuxBeginDoc: function(Printer: Pointer; var Ctx: Pointer): Boolean; cdecl;
  FmuxAbortDoc: procedure(Printer: Pointer); cdecl;
  FmuxEndDoc: function(Printer: Pointer): Boolean; cdecl;
  FmuxBeginPage: function(Ctx: Pointer): Boolean; cdecl;

type
  TFmuxEnumPaperSizesProc = procedure(UserData: Pointer; Name: PChar; Width, Height: Double); cdecl;

var
  FmuxEnumPaperSizes: procedure(Printer: Pointer; EnumProc: TFmuxEnumPaperSizesProc; UserData: Pointer; WithMargins: Boolean); cdecl;
  FmuxAddCustomPaperSize: procedure(Name: PChar; Width, Height: Double); cdecl;
  FmuxSelectFormatByPaperSize: function(Printer: Pointer; Width, Height: Double): Integer; cdecl;
  FmuxSetAlwaysAskOutputFile: procedure(Value: Integer); cdecl;

function PrinterOptionToInt(AOptions: TPrintDialogOptions): Integer;

{ Cursors }

var
  FmuxSetCursor: procedure(Cursor: Integer); cdecl;

{ IME }

type
  TFmuxImeCommitProc = procedure(Data: Pointer; Text: PChar); cdecl;

var
  FmuxImeEnterControl: procedure(Wnd: Pointer; StartProc, ChangedProc, CommitProc: TFmuxImeCommitProc; Rect: TRect; Data: Pointer); cdecl;
  FmuxImeExitControl: procedure(Wnd: Pointer); cdecl;
  FmuxImeSetCaretPos: procedure(Value: TPoint); cdecl;

{ Monitores }

type
  PFmuxDisplayInfo = ^TFmuxDisplayInfo;

  TFmuxDisplayInfo = record
    Primary: Boolean;
    BoundsRect: TRect;
    WorkareaRect: TRect;
  end;

var
  FmuxGetDisplayInfo: function(DisplayInfo: PFmuxDisplayInfo; Index: Integer): Integer; cdecl;
  FmuxGetDisplayFromWindow: function(Wnd: Pointer): Integer; cdecl;
  FmuxGetDisplayFromPoint: function(Point: TPoint): Integer; cdecl;
  FmuxTakeScreenshot: function: Pointer; cdecl;

{ WebView }

type
  TFmuxWebProc = procedure(Data: Pointer); cdecl;

  TFmuxWebViewCallbacks = record
    LoadError: TFmuxWebProc;
    LoadStarted: TFmuxWebProc;
    LoadFinished: TFmuxWebProc;
  end;

var
  FmuxIsWebViewInstalled: function: Boolean; cdecl;
  FmuxCreateWebView: function(Data: Pointer; var Callbacks: TFmuxWebViewCallbacks): Pointer; cdecl;
  FmuxWebViewShow: procedure(WebView: Pointer; Visible: Boolean); cdecl;
  FmuxWebViewSetBounds: procedure(WebView, Parent: Pointer; Rect: TRect); cdecl;
  FmuxWebViewNavigate: procedure(WebView: Pointer; URL: PChar); cdecl;
  FmuxWebViewLoadText: procedure(WebView: Pointer; Text, URL: PChar); cdecl;
  FmuxWebViewCanGoBack: function(WebView: Pointer): Boolean; cdecl;
  FmuxWebViewGoBack: procedure(WebView: Pointer); cdecl;
  FmuxWebViewCanGoForward: function(WebView: Pointer): Boolean; cdecl;
  FmuxWebViewGoForward: procedure(WebView: Pointer); cdecl;
  FmuxWebViewReload: procedure(WebView: Pointer); cdecl;
  FmuxEvaluateJavaScript: procedure(WebView: Pointer; JavaScript: PChar); cdecl;
  FmuxWebViewGetUrl: function(WebView: Pointer): PChar; cdecl;
  FmuxWebViewStop: procedure(WebView: Pointer); cdecl;
  FmuxDestroyWebView: procedure(WebView: Pointer); cdecl;

{ Shell }

var
  FmuxOpenFile: procedure(FileName: PChar); cdecl;
  FmuxOpenUrl: procedure(Url: PChar); cdecl;
  FmuxGetFileIcon: function(FileName: PChar; Size: Integer): Pointer; cdecl;
  FmuxGetFileType: function(FileName: PChar): PChar; cdecl;

{ Media }

const
  FMUX_MEDIA_Playing = 1;
  FMUX_MEDIA_Stopped = 2;

var
  FmuxMediaInstalled: function: Boolean; cdecl;
  FmuxCreateMedia: function(FileName: PChar): Pointer; cdecl;
  FmuxDestroyMedia: procedure(Media: Pointer); cdecl;
  FmuxMediaPlay: procedure(Media: Pointer); cdecl;
  FmuxMediaStop: procedure(Media: Pointer); cdecl;
  FmuxMediaGetDuration: function(Media: Pointer): Int64; cdecl;
  FmuxMediaGetCurrent: function(Media: Pointer): Int64; cdecl;
  FmuxMediaSetCurrent: procedure(Media: Pointer; ACurrent: Int64); cdecl;
  FmuxMediaSetVisible: procedure(Media: Pointer; AVisible: Boolean); cdecl;
  FmuxMediaSetBounds: procedure(Media: Pointer; Parent: Pointer; ABounds: TRectF); cdecl;
  FmuxMediaGetVideoSize: function(Media: Pointer): TPoint; cdecl;
  FmuxMediaGetVolume: function(Media: Pointer): Single; cdecl;
  FmuxMediaSetVolume: procedure(Media: Pointer; AValue: Single); cdecl;
  FmuxMediaGetState: function(Media: Pointer): Integer; cdecl;

{ Drag and Drop }

var
  FmuxBeginDragDrop: procedure(Wnd: Pointer; Data: Pointer; Bitmap: Pointer); cdecl;

{ Video Capture }

type
  TCaptureDeviceProc = procedure(Device: Pointer; ID, Name, Desc: PChar; Default: Boolean; UserData: Pointer); cdecl;

  TSampleReadyProc = procedure(Device: Pointer; W, H: Integer; Bits: Pointer; UserData: Pointer); cdecl;

var
  FmuxCaptureDeviceEnum: procedure(EnumProc: TCaptureDeviceProc; UserData: Pointer); cdecl;
  FmuxStartVideoCapture: function(Device: Pointer; Proc: TSampleReadyProc; UserData: Pointer): Boolean; cdecl;
  FmuxStopVideoCapture: function(Device: Pointer): Boolean; cdecl;

{ Cursor }

var
  FmuxGetMousePos: function: TPointF; cdecl;
  FmuxGetDefaultCursor: function: Pointer; cdecl;
  FmuxGetCursor: function: Pointer; cdecl;
  FmuxGetCursorBitmap: function(var HotX, HotY: Integer): Pointer; cdecl;

{ Events }

var
  FmuxGenMouseMove: function(X, Y: Single): Boolean; cdecl;
  // Button: 1 - Left, 3 - Right, 2 - Middle
  FmuxGenMouseDown: function(Button: Integer): Boolean; cdecl;
  FmuxGenMouseUp: function(Button: Integer): Boolean; cdecl;
  FmuxGenMouseWheel: function(DeltaX, DeltaY: Single): Boolean; cdecl;
  FmuxGenKeyDown: function(KeyCode: Cardinal; KeyChar: Char; State: Integer): Boolean; cdecl;
  FmuxGenKeyUp: function(KeyCode: Cardinal; KeyChar: Char; State: Integer): Boolean; cdecl;

function FmuxStateToShiftState(State: Integer): TShiftState;

function FmuxStateToButton(State: Integer): TMouseButton;

function FmuxButtonToState(Button: TMouseButton): Integer;

function FmuxShiftStateToState(State: TShiftState): Integer;

// Custom Version Info (Linux)

type
  TFmuxVersionInfo = record
    Major, Minor, Build: Cardinal;
    Extra: array[0..100] of Byte;
  end;

var
  FmuxGetVersionInfo: procedure(var VI: TFmuxVersionInfo); cdecl;
  FmuxSetVersionInfo: procedure(var VI: TFmuxVersionInfo); cdecl;

{ Utils }

var
  IsWayland: function: Boolean; cdecl;
  IsBroadway: function: Boolean; cdecl;
  IsInSnap: Boolean;

procedure LoadLib;

implementation

// FireLinux.FmuxLoad calls LoadLib before the backend factory leads to FMX unit initialization.
uses
  FireLinux.Log, FireLinux.FmuxLoad, FireLinux.Backend.Factory;

type
  TFmuxStateBit = record
    Bit: Integer;
    Shift: TShiftState;
  end;

const
  // FMUX_STATE_* bit <-> member of TShiftState.
  CFmuxStateBits: array[0..7] of TFmuxStateBit = (
    (Bit: FMUX_STATE_Shift; Shift: [ssShift]),
    (Bit: FMUX_STATE_Alt; Shift: [ssAlt]),
    (Bit: FMUX_STATE_CTRL; Shift: [ssCtrl]),
    (Bit: FMUX_STATE_SUPER; Shift: [ssCommand]),
    (Bit: FMUX_STATE_LEFT; Shift: [ssLeft]),
    (Bit: FMUX_STATE_RIGHT; Shift: [ssRight]),
    (Bit: FMUX_STATE_MIDDLE; Shift: [ssMiddle]),
    (Bit: FMUX_STATE_DOUBLE; Shift: [ssDouble]));
  CMsgDlgBtnBits: array[TMsgDlgBtn] of Integer = (FMUX_BTN_Yes, FMUX_BTN_No, FMUX_BTN_OK, FMUX_BTN_Cancel,
    FMUX_BTN_Abort, FMUX_BTN_Retry, FMUX_BTN_Ignore, FMUX_BTN_All, FMUX_BTN_NoToAll, FMUX_BTN_YesToAll,
    FMUX_BTN_Help, FMUX_BTN_Close);
  CPrintOptionBits: array[TPrintDialogOption] of Integer = (FMUX_poPrintToFile, FMUX_poPageNums, FMUX_poSelection,
    FMUX_poWarning, FMUX_poHelp, FMUX_poDisablePrintToFile);

function FmuxStateToShiftState;
var
  I: Integer;
begin
  Result := [];
  for I := Low(CFmuxStateBits) to High(CFmuxStateBits) do
    if State and CFmuxStateBits[I].Bit <> 0 then
      Result := Result + CFmuxStateBits[I].Shift;
end;

function FmuxShiftStateToState;
var
  I: Integer;
begin
  Result := 0;
  for I := Low(CFmuxStateBits) to High(CFmuxStateBits) do
    if CFmuxStateBits[I].Shift <= State then
      Result := Result or CFmuxStateBits[I].Bit;
end;

function FmuxStateToButton;
begin
  // The button of a press/release event: the state carries the bit of that button; right and middle win over left
  // (a release of the right button while the left one is held is a right-button release).
  Result := TMouseButton.mbLeft;
  if State and FMUX_STATE_RIGHT <> 0 then
    Result := TMouseButton.mbRight
  else if State and FMUX_STATE_MIDDLE <> 0 then
    Result := TMouseButton.mbMiddle;
end;

function FmuxButtonToState;
const
  CButtonBits: array[TMouseButton] of Integer = (FMUX_STATE_LEFT, FMUX_STATE_RIGHT, FMUX_STATE_MIDDLE);
begin
  Result := CButtonBits[Button];
end;

function MsgDlgButtonsToButtons;
var
  B: TMsgDlgBtn;
begin
  Result := 0;
  for B in Btns do
    Result := Result or CMsgDlgBtnBits[B];
end;

function PrinterOptionToInt;
var
  O: TPrintDialogOption;
begin
  Result := 0;
  for O in AOptions do
    Result := Result or CPrintOptionBits[O];
end;

// Stubs: every function pointer starts with one of these (logs once, returns Default(T)); FireLinux.Wayland.Fmux replaces
// the implemented ones.

procedure Stub_FmuxInit(Flags: Integer); cdecl;
begin
  FmuxStubCalled('FmuxInit');
end;

procedure Stub_FmuxRun(IdleProc: TFmuxIdleProc); cdecl;
begin
  FmuxStubCalled('FmuxRun');
end;

procedure Stub_FmuxTerminate; cdecl;
begin
  FmuxStubCalled('FmuxTerminate');
end;

function Stub_FmuxHandleMessage: Boolean; cdecl;
begin
  FmuxStubCalled('FmuxHandleMessage');
  Result := Default(Boolean);
end;

procedure Stub_FmuxWakeMainThread(Proc: TFmuxWakeMainThreadProc); cdecl;
begin
  FmuxStubCalled('FmuxWakeMainThread');
end;

function Stub_FmuxCreateWindow(var CreateStruct: TFmuxCreateStruct): Pointer; cdecl;
begin
  FmuxStubCalled('FmuxCreateWindow');
  Result := Default(Pointer);
end;

procedure Stub_FmuxDestroyWindow(Wnd: Pointer); cdecl;
begin
  FmuxStubCalled('FmuxDestroyWindow');
end;

procedure Stub_FmuxSetMainWindow(Wnd: Pointer); cdecl;
begin
  FmuxStubCalled('FmuxSetMainWindow');
end;

procedure Stub_FmuxSetWindowState(Wnd: Pointer; AState: TFmuxWindowState); cdecl;
begin
  FmuxStubCalled('FmuxSetWindowState');
end;

procedure Stub_FmuxSetWindowTitle(Wnd: Pointer; Title: PChar); cdecl;
begin
  FmuxStubCalled('FmuxSetWindowTitle');
end;

procedure Stub_FmuxSetWindowIcon(Wnd: Pointer; Data: Pointer; Size: Integer); cdecl;
begin
  FmuxStubCalled('FmuxSetWindowIcon');
end;

procedure Stub_FmuxShowWindow(Wnd: Pointer; Show: Boolean); cdecl;
begin
  FmuxStubCalled('FmuxShowWindow');
end;

procedure Stub_FmuxActivateWindow(Wnd: Pointer); cdecl;
begin
  FmuxStubCalled('FmuxActivateWindow');
end;

procedure Stub_FmuxWindowBringToFront(Wnd: Pointer); cdecl;
begin
  FmuxStubCalled('FmuxWindowBringToFront');
end;

procedure Stub_FmuxWindowSendToBack(Wnd: Pointer); cdecl;
begin
  FmuxStubCalled('FmuxWindowSendToBack');
end;

procedure Stub_FmuxGetClientSize(Wnd: Pointer; var R: TPointF); cdecl;
begin
  FmuxStubCalled('FmuxGetClientSize');
end;

procedure Stub_FmuxSetClientSize(Wnd: Pointer; R: TPointF); cdecl;
begin
  FmuxStubCalled('FmuxSetClientSize');
end;

procedure Stub_FmuxGetWindowRect(Wnd: Pointer; var R: TRectF); cdecl;
begin
  FmuxStubCalled('FmuxGetWindowRect');
end;

procedure Stub_FmuxSetWindowRect(Wnd: Pointer; R: TRectF); cdecl;
begin
  FmuxStubCalled('FmuxSetWindowRect');
end;

procedure Stub_FmuxInvalidateRect(Wnd: Pointer; R: TRectF); cdecl;
begin
  FmuxStubCalled('FmuxInvalidateRect');
end;

procedure Stub_FmuxProcessUpdates(Wnd: Pointer); cdecl;
begin
  FmuxStubCalled('FmuxProcessUpdates');
end;

function Stub_FmuxClientToScreen(Wnd: Pointer; Point: TPointF): TPointF; cdecl;
begin
  FmuxStubCalled('FmuxClientToScreen');
  Result := Default(TPointF);
end;

function Stub_FmuxScreenToClient(Wnd: Pointer; Point: TPointF): TPointF; cdecl;
begin
  FmuxStubCalled('FmuxScreenToClient');
  Result := Default(TPointF);
end;

function Stub_FmuxGetScreenSize: TPointF; cdecl;
begin
  FmuxStubCalled('FmuxGetScreenSize');
  Result := Default(TPointF);
end;

function Stub_FmuxGetScreenScale: Single; cdecl;
begin
  FmuxStubCalled('FmuxGetScreenScale');
  Result := Default(Single);
end;

function Stub_FmuxGetWindowScale(Wnd: Pointer): Single; cdecl;
begin
  FmuxStubCalled('FmuxGetWindowScale');
  Result := Default(Single);
end;

function Stub_FmuxGetWindowFullScreen(Wnd: Pointer): Boolean; cdecl;
begin
  FmuxStubCalled('FmuxGetWindowFullScreen');
  Result := Default(Boolean);
end;

procedure Stub_FmuxSetWindowFullScreen(Wnd: Pointer; AValue: Boolean); cdecl;
begin
  FmuxStubCalled('FmuxSetWindowFullScreen');
end;

procedure Stub_FmuxSetCapture(Wnd: Pointer); cdecl;
begin
  FmuxStubCalled('FmuxSetCapture');
end;

procedure Stub_FmuxReleaseCapture(Wnd: Pointer); cdecl;
begin
  FmuxStubCalled('FmuxReleaseCapture');
end;

function Stub_FmuxGetWindowNativeHandle(Wnd: Pointer): Pointer; cdecl;
begin
  FmuxStubCalled('FmuxGetWindowNativeHandle');
  Result := Default(Pointer);
end;

function Stub_FmuxGetWindowNativeDrawingHandle(Wnd: Pointer): Pointer; cdecl;
begin
  FmuxStubCalled('FmuxGetWindowNativeDrawingHandle');
  Result := Default(Pointer);
end;

procedure Stub_FmuxAddTooltip(Wnd: Pointer; Text: PChar); cdecl;
begin
  FmuxStubCalled('FmuxAddTooltip');
end;

procedure Stub_FmuxRemoveTooltip(Wnd: Pointer); cdecl;
begin
  FmuxStubCalled('FmuxRemoveTooltip');
end;

procedure Stub_FmuxAddGestureRecognizer(Wnd: Pointer; ARec: Integer); cdecl;
begin
  FmuxStubCalled('FmuxAddGestureRecognizer');
end;

procedure Stub_FmuxRemoveGestureRecognizer(Wnd: Pointer; ARec: Integer); cdecl;
begin
  FmuxStubCalled('FmuxRemoveGestureRecognizer');
end;

function Stub_FmuxShowModal(Wnd: Pointer; Proc: TFmuxModal): Integer; cdecl;
begin
  FmuxStubCalled('FmuxShowModal');
  Result := Default(Integer);
end;

function Stub_FmuxGetKeyState: Integer; cdecl;
begin
  FmuxStubCalled('FmuxGetKeyState');
  Result := Default(Integer);
end;

function Stub_FmuxCreateTimer(Interval: Integer; TimerFunc: TFmuxTimerProc; Data, Code: Pointer): NativeInt; cdecl;
begin
  FmuxStubCalled('FmuxCreateTimer');
  Result := Default(NativeInt);
end;

function Stub_FmuxDestroyTimer(Timer: NativeInt): Boolean; cdecl;
begin
  FmuxStubCalled('FmuxDestroyTimer');
  Result := Default(Boolean);
end;

procedure Stub_FmuxSetClipRects(Ctx: Pointer; const ARects: PRectF; const Count: Integer); cdecl;
begin
  FmuxStubCalled('FmuxSetClipRects');
end;

procedure Stub_FmuxIntersectClipRect(Ctx: Pointer; const ARect: TRectF); cdecl;
begin
  FmuxStubCalled('FmuxIntersectClipRect');
end;

procedure Stub_FmuxExcludeClipRect(Ctx: Pointer; const ARect: TRectF); cdecl;
begin
  FmuxStubCalled('FmuxExcludeClipRect');
end;

procedure Stub_FmuxSave(Ctx: Pointer); cdecl;
begin
  FmuxStubCalled('FmuxSave');
end;

procedure Stub_FmuxRestore(Ctx: Pointer); cdecl;
begin
  FmuxStubCalled('FmuxRestore');
end;

procedure Stub_FmuxCanvasSetQuality(Ctx: Pointer; Quality: Integer); cdecl;
begin
  FmuxStubCalled('FmuxCanvasSetQuality');
end;

procedure Stub_FmuxCanvasClear(Ctx: Pointer; C: TAlphaColor); cdecl;
begin
  FmuxStubCalled('FmuxCanvasClear');
end;

procedure Stub_FmuxCanvasClearRect(Ctx: Pointer; R: TRectF; C: TAlphaColor); cdecl;
begin
  FmuxStubCalled('FmuxCanvasClearRect');
end;

procedure Stub_FmuxCanvasSetMatrix(Ctx: Pointer; m11, m12, m21, m22, m31, m32: Single); cdecl;
begin
  FmuxStubCalled('FmuxCanvasSetMatrix');
end;

procedure Stub_FmuxCanvasSetFillColor(Ctx: Pointer; C: TAlphaColor); cdecl;
begin
  FmuxStubCalled('FmuxCanvasSetFillColor');
end;

procedure Stub_FmuxCanvasSetFillGradient(Ctx: Pointer; P1, P2: TPointF; Gradient: PFmuxGradient; Count: Integer); cdecl;
begin
  FmuxStubCalled('FmuxCanvasSetFillGradient');
end;

procedure Stub_FmuxCanvasSetFillRadialGradient(Ctx: Pointer; Center, P1, P2: TPointF; Gradient: PFmuxGradient; Count: Integer); cdecl;
begin
  FmuxStubCalled('FmuxCanvasSetFillRadialGradient');
end;

procedure Stub_FmuxCanvasSetFillBitmap(Ctx: Pointer; Bitmap: Pointer; Rect: TRectF; Mode: Integer); cdecl;
begin
  FmuxStubCalled('FmuxCanvasSetFillBitmap');
end;

procedure Stub_FmuxCanvasEllipse(Ctx: Pointer; R: TRectF); cdecl;
begin
  FmuxStubCalled('FmuxCanvasEllipse');
end;

procedure Stub_FmuxCanvasRect(Ctx: Pointer; R: TRectF); cdecl;
begin
  FmuxStubCalled('FmuxCanvasRect');
end;

procedure Stub_FmuxCanvasLine(Ctx: Pointer; APt1, APt2: TPointF); cdecl;
begin
  FmuxStubCalled('FmuxCanvasLine');
end;

procedure Stub_FmuxCanvasPath(Ctx: Pointer; Pts: PFmuxPathPoint; Count: Integer); cdecl;
begin
  FmuxStubCalled('FmuxCanvasPath');
end;

procedure Stub_FmuxCanvasFill(Ctx: Pointer; Opacity: Single); cdecl;
begin
  FmuxStubCalled('FmuxCanvasFill');
end;

function Stub_FmuxCanvasPtInPath(Pt: TPointF; Pts: PFmuxPathPoint; Count: Integer): Boolean; cdecl;
begin
  FmuxStubCalled('FmuxCanvasPtInPath');
  Result := Default(Boolean);
end;

procedure Stub_FmuxCanvasStroke(Ctx: Pointer; Opacity: Single); cdecl;
begin
  FmuxStubCalled('FmuxCanvasStroke');
end;

procedure Stub_FmuxCanvasSetStrokeWidth(Ctx: Pointer; Width: Single); cdecl;
begin
  FmuxStubCalled('FmuxCanvasSetStrokeWidth');
end;

procedure Stub_FmuxCanvasSetStrokeCap(Ctx: Pointer; Cap: Integer); cdecl;
begin
  FmuxStubCalled('FmuxCanvasSetStrokeCap');
end;

procedure Stub_FmuxCanvasSetStrokeJoin(Ctx: Pointer; Join: Integer); cdecl;
begin
  FmuxStubCalled('FmuxCanvasSetStrokeJoin');
end;

procedure Stub_FmuxCanvasSetStrokeDash(Ctx: Pointer; Offset: Single; DashArray: Pointer; Length: Integer); cdecl;
begin
  FmuxStubCalled('FmuxCanvasSetStrokeDash');
end;

function Stub_FmuxBitmapCreate(Width, Height: Integer; Bits: Pointer): Pointer; cdecl;
begin
  FmuxStubCalled('FmuxBitmapCreate');
  Result := Default(Pointer);
end;

procedure Stub_FmuxBitmapDestroy(Bitmap: Pointer); cdecl;
begin
  FmuxStubCalled('FmuxBitmapDestroy');
end;

procedure Stub_FmuxGetBitmapInfo(Bitmap: Pointer; var Width, Height: Integer; var Data: Pointer); cdecl;
begin
  FmuxStubCalled('FmuxGetBitmapInfo');
end;

procedure Stub_FmuxCanvasDrawBitmap(Ctx, Bitmap: Pointer; Src, Dst: TRectF; Opacity: Single; HighSpeed: Boolean); cdecl;
begin
  FmuxStubCalled('FmuxCanvasDrawBitmap');
end;

function Stub_FmuxCreateContext(Bitmap: Pointer): Pointer; cdecl;
begin
  FmuxStubCalled('FmuxCreateContext');
  Result := Default(Pointer);
end;

procedure Stub_FmuxDestroyContext(Ctx: Pointer); cdecl;
begin
  FmuxStubCalled('FmuxDestroyContext');
end;

function Stub_FmuxBitmapLoad(ReadFunc: TFmuxReadFunc; Param: Pointer; var W, H: Integer; var Bits: Pointer): Pointer; cdecl;
begin
  FmuxStubCalled('FmuxBitmapLoad');
  Result := Default(Pointer);
end;

function Stub_FmuxBitmapSave(ReadFunc: TFmuxReadFunc; Param: Pointer; W, H: Integer; Bits: Pointer; Extension: PChar): Boolean; cdecl;
begin
  FmuxStubCalled('FmuxBitmapSave');
  Result := Default(Boolean);
end;

function Stub_FmuxCreateTextLayout(Text: PChar; var Font: TFmuxFont; Width, Height: Single; Align, Trimming: Integer; WordWrap: Boolean): Pointer; cdecl;
begin
  FmuxStubCalled('FmuxCreateTextLayout');
  Result := Default(Pointer);
end;

procedure Stub_FmuxDestroyTextLayout(Layout: Pointer); cdecl;
begin
  FmuxStubCalled('FmuxDestroyTextLayout');
end;

procedure Stub_FmuxDrawTextLayout(Ctx, Layout: Pointer; X, Y: Single); cdecl;
begin
  FmuxStubCalled('FmuxDrawTextLayout');
end;

procedure Stub_FmuxGetTextLayoutRect(Layout: Pointer; var R: TRectF); cdecl;
begin
  FmuxStubCalled('FmuxGetTextLayoutRect');
end;

function Stub_FmuxLayoutPositionAtPoint(Layout: Pointer; APoint: PPointF): Integer; cdecl;
begin
  FmuxStubCalled('FmuxLayoutPositionAtPoint');
  Result := Default(Integer);
end;

function Stub_FmuxLayoutMeasureRange(Layout: Pointer; APos, ALength: Integer; Region: PRectF): Integer; cdecl;
begin
  FmuxStubCalled('FmuxLayoutMeasureRange');
  Result := Default(Integer);
end;

function Stub_FmuxLayoutToPath(Layout: Pointer; Pts: PFmuxPathPoint; Count: Integer): Integer; cdecl;
begin
  FmuxStubCalled('FmuxLayoutToPath');
  Result := Default(Integer);
end;

function Stub_FmuxAddCustomFont(FileName: PChar): Integer; cdecl;
begin
  FmuxStubCalled('FmuxAddCustomFont');
  Result := Default(Integer);
end;

function Stub_FmuxAddCustomFontFromData(Data: Pointer; Len: Integer): Integer; cdecl;
begin
  FmuxStubCalled('FmuxAddCustomFontFromData');
  Result := Default(Integer);
end;

function Stub_FmuxGetFontCount: Integer; cdecl;
begin
  FmuxStubCalled('FmuxGetFontCount');
  Result := Default(Integer);
end;

function Stub_FmuxGetFontName(Index: Integer): PChar; cdecl;
begin
  FmuxStubCalled('FmuxGetFontName');
  Result := Default(PChar);
end;

procedure Stub_FmuxSetLog(Log: TFmuxLog); cdecl;
begin
  FmuxStubCalled('FmuxSetLog');
end;

function Stub_FmuxCreateSharedContext: Pointer; cdecl;
begin
  FmuxStubCalled('FmuxCreateSharedContext');
  Result := Default(Pointer);
end;

function Stub_FmuxCreateThreadContext: Pointer; cdecl;
begin
  FmuxStubCalled('FmuxCreateThreadContext');
  Result := Default(Pointer);
end;

procedure Stub_FmuxMakeCurrentContext(Ctx: Pointer); cdecl;
begin
  FmuxStubCalled('FmuxMakeCurrentContext');
end;

procedure Stub_FmuxFlushBuffer(Wnd: Pointer; Texture: Integer); cdecl;
begin
  FmuxStubCalled('FmuxFlushBuffer');
end;

function Stub_FmuxCreateMainMenu(Wnd: Pointer): Pointer; cdecl;
begin
  FmuxStubCalled('FmuxCreateMainMenu');
  Result := Default(Pointer);
end;

function Stub_FmuxCreateMenu(Wnd: Pointer): Pointer; cdecl;
begin
  FmuxStubCalled('FmuxCreateMenu');
  Result := Default(Pointer);
end;

function Stub_FmuxCreateMenuItem(Item: PFmuxMenuItem): Pointer; cdecl;
begin
  FmuxStubCalled('FmuxCreateMenuItem');
  Result := Default(Pointer);
end;

procedure Stub_FmuxMenuAddItem(Menu: Pointer; Item: Pointer); cdecl;
begin
  FmuxStubCalled('FmuxMenuAddItem');
end;

procedure Stub_FmuxSetSubmenu(Item: Pointer; Menu: Pointer); cdecl;
begin
  FmuxStubCalled('FmuxSetSubmenu');
end;

function Stub_FmuxUpdateMenuItem(Item: Pointer; ItemRec: PFmuxMenuItem): Pointer; cdecl;
begin
  FmuxStubCalled('FmuxUpdateMenuItem');
  Result := Default(Pointer);
end;

function Stub_FmuxMessageDialog(AMessage: PChar; DlgType, Buttons: Integer): Integer; cdecl;
begin
  FmuxStubCalled('FmuxMessageDialog');
  Result := Default(Integer);
end;

function Stub_FmuxInputQuery(ACaption, APromt, AValue: PChar; MaxLength: Integer): Boolean; cdecl;
begin
  FmuxStubCalled('FmuxInputQuery');
  Result := Default(Boolean);
end;

function Stub_FmuxFilesDialog(Title, Filter, InitialName, InitialDir, Files: PChar; MaxLength: Integer; var FilterIndex: Integer; AOptions: Integer): Boolean; cdecl;
begin
  FmuxStubCalled('FmuxFilesDialog');
  Result := Default(Boolean);
end;

function Stub_FmuxClipboardHasText: Boolean; cdecl;
begin
  FmuxStubCalled('FmuxClipboardHasText');
  Result := Default(Boolean);
end;

function Stub_FmuxClipboardGetText: PChar; cdecl;
begin
  FmuxStubCalled('FmuxClipboardGetText');
  Result := Default(PChar);
end;

procedure Stub_FmuxClipboardSetText(Text: PChar); cdecl;
begin
  FmuxStubCalled('FmuxClipboardSetText');
end;

function Stub_FmuxClipboardHasImage: Boolean; cdecl;
begin
  FmuxStubCalled('FmuxClipboardHasImage');
  Result := Default(Boolean);
end;

procedure Stub_FmuxClipboardGetImage(Data: Pointer; var W, H: Integer); cdecl;
begin
  FmuxStubCalled('FmuxClipboardGetImage');
end;

procedure Stub_FmuxClipboardSetImage(Data: Pointer; W, H: Integer); cdecl;
begin
  FmuxStubCalled('FmuxClipboardSetImage');
end;

function Stub_FmuxClipboardHasCustom(Format: PChar): Boolean; cdecl;
begin
  FmuxStubCalled('FmuxClipboardHasCustom');
  Result := Default(Boolean);
end;

procedure Stub_FmuxClipboardGetCustom(Format: PChar; Data: Pointer; var Size: Integer); cdecl;
begin
  FmuxStubCalled('FmuxClipboardGetCustom');
end;

procedure Stub_FmuxClipboardSetCustom(Format: PChar; Data: Pointer; Size: Integer); cdecl;
begin
  FmuxStubCalled('FmuxClipboardSetCustom');
end;

procedure Stub_FmuxClipboardSetArray(Data: PFmuxClipboardDataArray; Count: Integer); cdecl;
begin
  FmuxStubCalled('FmuxClipboardSetArray');
end;

procedure Stub_FmuxEnumPrinters(EnumProc: TFmuxPrintersEnum; Data: Pointer); cdecl;
begin
  FmuxStubCalled('FmuxEnumPrinters');
end;

function Stub_FmuxIsDefaultPrinter(Printer: Pointer): Boolean; cdecl;
begin
  FmuxStubCalled('FmuxIsDefaultPrinter');
  Result := Default(Boolean);
end;

function Stub_FmuxGetPageSettings(var Settings: TFmuxPageSettings): Boolean; cdecl;
begin
  FmuxStubCalled('FmuxGetPageSettings');
  Result := Default(Boolean);
end;

function Stub_FmuxPrintDialog(var ACollate, APrintToFile: Boolean; var AFromPage, AToPage, ACopies: Integer; AMinPage, AMaxPage: Integer; var APrintRange: TPrintRange; AOptions: Integer; var APrinterIndex: Integer): Boolean; cdecl;
begin
  FmuxStubCalled('FmuxPrintDialog');
  Result := Default(Boolean);
end;

function Stub_FmuxPageSetupDefault(var AMargin, AMinMargin: TRect; var APaperSize: TPointF; var AUnits: TPageMeasureUnits; AOptions: Integer): Boolean; cdecl;
begin
  FmuxStubCalled('FmuxPageSetupDefault');
  Result := Default(Boolean);
end;

function Stub_FmuxPageSetupDialog(var AMargin, AMinMargin: TRect; var APaperSize: TPointF; var AUnits: TPageMeasureUnits; AOptions: Integer): Boolean; cdecl;
begin
  FmuxStubCalled('FmuxPageSetupDialog');
  Result := Default(Boolean);
end;

function Stub_FmuxPrinterRun(ShowPrintDialog: Boolean; NumberOfPage: Integer; Data: Pointer; Proc: TFmuxPrintProc): Boolean; cdecl;
begin
  FmuxStubCalled('FmuxPrinterRun');
  Result := Default(Boolean);
end;

function Stub_FmuxGetOrientation: Integer; cdecl;
begin
  FmuxStubCalled('FmuxGetOrientation');
  Result := Default(Integer);
end;

procedure Stub_FmuxSetOrientation(Orientation: Integer); cdecl;
begin
  FmuxStubCalled('FmuxSetOrientation');
end;

function Stub_FmuxCreatePDFContext(UserData: Pointer; Writer: TFmuxPDFWriter; W, H: Single): Pointer; cdecl;
begin
  FmuxStubCalled('FmuxCreatePDFContext');
  Result := Default(Pointer);
end;

procedure Stub_FmuxDestroyPDFContext(context: Pointer); cdecl;
begin
  FmuxStubCalled('FmuxDestroyPDFContext');
end;

procedure Stub_FmuxPDFContextNewPage(context: Pointer); cdecl;
begin
  FmuxStubCalled('FmuxPDFContextNewPage');
end;

function Stub_FmuxBeginDoc(Printer: Pointer; var Ctx: Pointer): Boolean; cdecl;
begin
  FmuxStubCalled('FmuxBeginDoc');
  Result := Default(Boolean);
end;

procedure Stub_FmuxAbortDoc(Printer: Pointer); cdecl;
begin
  FmuxStubCalled('FmuxAbortDoc');
end;

function Stub_FmuxEndDoc(Printer: Pointer): Boolean; cdecl;
begin
  FmuxStubCalled('FmuxEndDoc');
  Result := Default(Boolean);
end;

function Stub_FmuxBeginPage(Ctx: Pointer): Boolean; cdecl;
begin
  FmuxStubCalled('FmuxBeginPage');
  Result := Default(Boolean);
end;

procedure Stub_FmuxEnumPaperSizes(Printer: Pointer; EnumProc: TFmuxEnumPaperSizesProc; UserData: Pointer; WithMargins: Boolean); cdecl;
begin
  FmuxStubCalled('FmuxEnumPaperSizes');
end;

procedure Stub_FmuxAddCustomPaperSize(Name: PChar; Width, Height: Double); cdecl;
begin
  FmuxStubCalled('FmuxAddCustomPaperSize');
end;

function Stub_FmuxSelectFormatByPaperSize(Printer: Pointer; Width, Height: Double): Integer; cdecl;
begin
  FmuxStubCalled('FmuxSelectFormatByPaperSize');
  Result := Default(Integer);
end;

procedure Stub_FmuxSetAlwaysAskOutputFile(Value: Integer); cdecl;
begin
  FmuxStubCalled('FmuxSetAlwaysAskOutputFile');
end;

procedure Stub_FmuxSetCursor(Cursor: Integer); cdecl;
begin
  FmuxStubCalled('FmuxSetCursor');
end;

procedure Stub_FmuxImeEnterControl(Wnd: Pointer; StartProc, ChangedProc, CommitProc: TFmuxImeCommitProc; Rect: TRect; Data: Pointer); cdecl;
begin
  FmuxStubCalled('FmuxImeEnterControl');
end;

procedure Stub_FmuxImeExitControl(Wnd: Pointer); cdecl;
begin
  FmuxStubCalled('FmuxImeExitControl');
end;

procedure Stub_FmuxImeSetCaretPos(Value: TPoint); cdecl;
begin
  FmuxStubCalled('FmuxImeSetCaretPos');
end;

function Stub_FmuxGetDisplayInfo(DisplayInfo: PFmuxDisplayInfo; Index: Integer): Integer; cdecl;
begin
  FmuxStubCalled('FmuxGetDisplayInfo');
  Result := Default(Integer);
end;

function Stub_FmuxGetDisplayFromWindow(Wnd: Pointer): Integer; cdecl;
begin
  FmuxStubCalled('FmuxGetDisplayFromWindow');
  Result := Default(Integer);
end;

function Stub_FmuxGetDisplayFromPoint(Point: TPoint): Integer; cdecl;
begin
  FmuxStubCalled('FmuxGetDisplayFromPoint');
  Result := Default(Integer);
end;

function Stub_FmuxTakeScreenshot: Pointer; cdecl;
begin
  FmuxStubCalled('FmuxTakeScreenshot');
  Result := Default(Pointer);
end;

function Stub_FmuxIsWebViewInstalled: Boolean; cdecl;
begin
  FmuxStubCalled('FmuxIsWebViewInstalled');
  Result := Default(Boolean);
end;

function Stub_FmuxCreateWebView(Data: Pointer; var Callbacks: TFmuxWebViewCallbacks): Pointer; cdecl;
begin
  FmuxStubCalled('FmuxCreateWebView');
  Result := Default(Pointer);
end;

procedure Stub_FmuxWebViewShow(WebView: Pointer; Visible: Boolean); cdecl;
begin
  FmuxStubCalled('FmuxWebViewShow');
end;

procedure Stub_FmuxWebViewSetBounds(WebView, Parent: Pointer; Rect: TRect); cdecl;
begin
  FmuxStubCalled('FmuxWebViewSetBounds');
end;

procedure Stub_FmuxWebViewNavigate(WebView: Pointer; URL: PChar); cdecl;
begin
  FmuxStubCalled('FmuxWebViewNavigate');
end;

procedure Stub_FmuxWebViewLoadText(WebView: Pointer; Text, URL: PChar); cdecl;
begin
  FmuxStubCalled('FmuxWebViewLoadText');
end;

function Stub_FmuxWebViewCanGoBack(WebView: Pointer): Boolean; cdecl;
begin
  FmuxStubCalled('FmuxWebViewCanGoBack');
  Result := Default(Boolean);
end;

procedure Stub_FmuxWebViewGoBack(WebView: Pointer); cdecl;
begin
  FmuxStubCalled('FmuxWebViewGoBack');
end;

function Stub_FmuxWebViewCanGoForward(WebView: Pointer): Boolean; cdecl;
begin
  FmuxStubCalled('FmuxWebViewCanGoForward');
  Result := Default(Boolean);
end;

procedure Stub_FmuxWebViewGoForward(WebView: Pointer); cdecl;
begin
  FmuxStubCalled('FmuxWebViewGoForward');
end;

procedure Stub_FmuxWebViewReload(WebView: Pointer); cdecl;
begin
  FmuxStubCalled('FmuxWebViewReload');
end;

procedure Stub_FmuxEvaluateJavaScript(WebView: Pointer; JavaScript: PChar); cdecl;
begin
  FmuxStubCalled('FmuxEvaluateJavaScript');
end;

function Stub_FmuxWebViewGetUrl(WebView: Pointer): PChar; cdecl;
begin
  FmuxStubCalled('FmuxWebViewGetUrl');
  Result := Default(PChar);
end;

procedure Stub_FmuxWebViewStop(WebView: Pointer); cdecl;
begin
  FmuxStubCalled('FmuxWebViewStop');
end;

procedure Stub_FmuxDestroyWebView(WebView: Pointer); cdecl;
begin
  FmuxStubCalled('FmuxDestroyWebView');
end;

procedure Stub_FmuxOpenFile(FileName: PChar); cdecl;
begin
  FmuxStubCalled('FmuxOpenFile');
end;

procedure Stub_FmuxOpenUrl(Url: PChar); cdecl;
begin
  FmuxStubCalled('FmuxOpenUrl');
end;

function Stub_FmuxGetFileIcon(FileName: PChar; Size: Integer): Pointer; cdecl;
begin
  FmuxStubCalled('FmuxGetFileIcon');
  Result := Default(Pointer);
end;

function Stub_FmuxGetFileType(FileName: PChar): PChar; cdecl;
begin
  FmuxStubCalled('FmuxGetFileType');
  Result := Default(PChar);
end;

function Stub_FmuxMediaInstalled: Boolean; cdecl;
begin
  FmuxStubCalled('FmuxMediaInstalled');
  Result := Default(Boolean);
end;

function Stub_FmuxCreateMedia(FileName: PChar): Pointer; cdecl;
begin
  FmuxStubCalled('FmuxCreateMedia');
  Result := Default(Pointer);
end;

procedure Stub_FmuxDestroyMedia(Media: Pointer); cdecl;
begin
  FmuxStubCalled('FmuxDestroyMedia');
end;

procedure Stub_FmuxMediaPlay(Media: Pointer); cdecl;
begin
  FmuxStubCalled('FmuxMediaPlay');
end;

procedure Stub_FmuxMediaStop(Media: Pointer); cdecl;
begin
  FmuxStubCalled('FmuxMediaStop');
end;

function Stub_FmuxMediaGetDuration(Media: Pointer): Int64; cdecl;
begin
  FmuxStubCalled('FmuxMediaGetDuration');
  Result := Default(Int64);
end;

function Stub_FmuxMediaGetCurrent(Media: Pointer): Int64; cdecl;
begin
  FmuxStubCalled('FmuxMediaGetCurrent');
  Result := Default(Int64);
end;

procedure Stub_FmuxMediaSetCurrent(Media: Pointer; ACurrent: Int64); cdecl;
begin
  FmuxStubCalled('FmuxMediaSetCurrent');
end;

procedure Stub_FmuxMediaSetVisible(Media: Pointer; AVisible: Boolean); cdecl;
begin
  FmuxStubCalled('FmuxMediaSetVisible');
end;

procedure Stub_FmuxMediaSetBounds(Media: Pointer; Parent: Pointer; ABounds: TRectF); cdecl;
begin
  FmuxStubCalled('FmuxMediaSetBounds');
end;

function Stub_FmuxMediaGetVideoSize(Media: Pointer): TPoint; cdecl;
begin
  FmuxStubCalled('FmuxMediaGetVideoSize');
  Result := Default(TPoint);
end;

function Stub_FmuxMediaGetVolume(Media: Pointer): Single; cdecl;
begin
  FmuxStubCalled('FmuxMediaGetVolume');
  Result := Default(Single);
end;

procedure Stub_FmuxMediaSetVolume(Media: Pointer; AValue: Single); cdecl;
begin
  FmuxStubCalled('FmuxMediaSetVolume');
end;

function Stub_FmuxMediaGetState(Media: Pointer): Integer; cdecl;
begin
  FmuxStubCalled('FmuxMediaGetState');
  Result := Default(Integer);
end;

procedure Stub_FmuxBeginDragDrop(Wnd: Pointer; Data: Pointer; Bitmap: Pointer); cdecl;
begin
  FmuxStubCalled('FmuxBeginDragDrop');
end;

procedure Stub_FmuxCaptureDeviceEnum(EnumProc: TCaptureDeviceProc; UserData: Pointer); cdecl;
begin
  FmuxStubCalled('FmuxCaptureDeviceEnum');
end;

function Stub_FmuxStartVideoCapture(Device: Pointer; Proc: TSampleReadyProc; UserData: Pointer): Boolean; cdecl;
begin
  FmuxStubCalled('FmuxStartVideoCapture');
  Result := Default(Boolean);
end;

function Stub_FmuxStopVideoCapture(Device: Pointer): Boolean; cdecl;
begin
  FmuxStubCalled('FmuxStopVideoCapture');
  Result := Default(Boolean);
end;

function Stub_FmuxGetMousePos: TPointF; cdecl;
begin
  FmuxStubCalled('FmuxGetMousePos');
  Result := Default(TPointF);
end;

function Stub_FmuxGetDefaultCursor: Pointer; cdecl;
begin
  FmuxStubCalled('FmuxGetDefaultCursor');
  Result := Default(Pointer);
end;

function Stub_FmuxGetCursor: Pointer; cdecl;
begin
  FmuxStubCalled('FmuxGetCursor');
  Result := Default(Pointer);
end;

function Stub_FmuxGetCursorBitmap(var HotX, HotY: Integer): Pointer; cdecl;
begin
  FmuxStubCalled('FmuxGetCursorBitmap');
  Result := Default(Pointer);
end;

function Stub_FmuxGenMouseMove(X, Y: Single): Boolean; cdecl;
begin
  FmuxStubCalled('FmuxGenMouseMove');
  Result := Default(Boolean);
end;

function Stub_FmuxGenMouseDown(Button: Integer): Boolean; cdecl;
begin
  FmuxStubCalled('FmuxGenMouseDown');
  Result := Default(Boolean);
end;

function Stub_FmuxGenMouseUp(Button: Integer): Boolean; cdecl;
begin
  FmuxStubCalled('FmuxGenMouseUp');
  Result := Default(Boolean);
end;

function Stub_FmuxGenMouseWheel(DeltaX, DeltaY: Single): Boolean; cdecl;
begin
  FmuxStubCalled('FmuxGenMouseWheel');
  Result := Default(Boolean);
end;

function Stub_FmuxGenKeyDown(KeyCode: Cardinal; KeyChar: Char; State: Integer): Boolean; cdecl;
begin
  FmuxStubCalled('FmuxGenKeyDown');
  Result := Default(Boolean);
end;

function Stub_FmuxGenKeyUp(KeyCode: Cardinal; KeyChar: Char; State: Integer): Boolean; cdecl;
begin
  FmuxStubCalled('FmuxGenKeyUp');
  Result := Default(Boolean);
end;

procedure Stub_FmuxGetVersionInfo(var VI: TFmuxVersionInfo); cdecl;
begin
  FmuxStubCalled('FmuxGetVersionInfo');
end;

procedure Stub_FmuxSetVersionInfo(var VI: TFmuxVersionInfo); cdecl;
begin
  FmuxStubCalled('FmuxSetVersionInfo');
end;

function Stub_IsWayland: Boolean; cdecl;
begin
  FmuxStubCalled('IsWayland');
  Result := Default(Boolean);
end;

function Stub_IsBroadway: Boolean; cdecl;
begin
  FmuxStubCalled('IsBroadway');
  Result := Default(Boolean);
end;

procedure AssignStubs;
begin
  FmuxInit := Stub_FmuxInit;
  FmuxRun := Stub_FmuxRun;
  FmuxTerminate := Stub_FmuxTerminate;
  FmuxHandleMessage := Stub_FmuxHandleMessage;
  FmuxWakeMainThread := Stub_FmuxWakeMainThread;
  FmuxCreateWindow := Stub_FmuxCreateWindow;
  FmuxDestroyWindow := Stub_FmuxDestroyWindow;
  FmuxSetMainWindow := Stub_FmuxSetMainWindow;
  FmuxSetWindowState := Stub_FmuxSetWindowState;
  FmuxSetWindowTitle := Stub_FmuxSetWindowTitle;
  FmuxSetWindowIcon := Stub_FmuxSetWindowIcon;
  FmuxShowWindow := Stub_FmuxShowWindow;
  FmuxActivateWindow := Stub_FmuxActivateWindow;
  FmuxWindowBringToFront := Stub_FmuxWindowBringToFront;
  FmuxWindowSendToBack := Stub_FmuxWindowSendToBack;
  FmuxGetClientSize := Stub_FmuxGetClientSize;
  FmuxSetClientSize := Stub_FmuxSetClientSize;
  FmuxGetWindowRect := Stub_FmuxGetWindowRect;
  FmuxSetWindowRect := Stub_FmuxSetWindowRect;
  FmuxInvalidateRect := Stub_FmuxInvalidateRect;
  FmuxProcessUpdates := Stub_FmuxProcessUpdates;
  FmuxClientToScreen := Stub_FmuxClientToScreen;
  FmuxScreenToClient := Stub_FmuxScreenToClient;
  FmuxGetScreenSize := Stub_FmuxGetScreenSize;
  FmuxGetScreenScale := Stub_FmuxGetScreenScale;
  FmuxGetWindowScale := Stub_FmuxGetWindowScale;
  FmuxGetWindowFullScreen := Stub_FmuxGetWindowFullScreen;
  FmuxSetWindowFullScreen := Stub_FmuxSetWindowFullScreen;
  FmuxSetCapture := Stub_FmuxSetCapture;
  FmuxReleaseCapture := Stub_FmuxReleaseCapture;
  FmuxGetWindowNativeHandle := Stub_FmuxGetWindowNativeHandle;
  FmuxGetWindowNativeDrawingHandle := Stub_FmuxGetWindowNativeDrawingHandle;
  FmuxAddTooltip := Stub_FmuxAddTooltip;
  FmuxRemoveTooltip := Stub_FmuxRemoveTooltip;
  FmuxAddGestureRecognizer := Stub_FmuxAddGestureRecognizer;
  FmuxRemoveGestureRecognizer := Stub_FmuxRemoveGestureRecognizer;
  FmuxShowModal := Stub_FmuxShowModal;
  FmuxGetKeyState := Stub_FmuxGetKeyState;
  FmuxCreateTimer := Stub_FmuxCreateTimer;
  FmuxDestroyTimer := Stub_FmuxDestroyTimer;
  FmuxSetClipRects := Stub_FmuxSetClipRects;
  FmuxIntersectClipRect := Stub_FmuxIntersectClipRect;
  FmuxExcludeClipRect := Stub_FmuxExcludeClipRect;
  FmuxSave := Stub_FmuxSave;
  FmuxRestore := Stub_FmuxRestore;
  FmuxCanvasSetQuality := Stub_FmuxCanvasSetQuality;
  FmuxCanvasClear := Stub_FmuxCanvasClear;
  FmuxCanvasClearRect := Stub_FmuxCanvasClearRect;
  FmuxCanvasSetMatrix := Stub_FmuxCanvasSetMatrix;
  FmuxCanvasSetFillColor := Stub_FmuxCanvasSetFillColor;
  FmuxCanvasSetFillGradient := Stub_FmuxCanvasSetFillGradient;
  FmuxCanvasSetFillRadialGradient := Stub_FmuxCanvasSetFillRadialGradient;
  FmuxCanvasSetFillBitmap := Stub_FmuxCanvasSetFillBitmap;
  FmuxCanvasEllipse := Stub_FmuxCanvasEllipse;
  FmuxCanvasRect := Stub_FmuxCanvasRect;
  FmuxCanvasLine := Stub_FmuxCanvasLine;
  FmuxCanvasPath := Stub_FmuxCanvasPath;
  FmuxCanvasFill := Stub_FmuxCanvasFill;
  FmuxCanvasPtInPath := Stub_FmuxCanvasPtInPath;
  FmuxCanvasStroke := Stub_FmuxCanvasStroke;
  FmuxCanvasSetStrokeWidth := Stub_FmuxCanvasSetStrokeWidth;
  FmuxCanvasSetStrokeCap := Stub_FmuxCanvasSetStrokeCap;
  FmuxCanvasSetStrokeJoin := Stub_FmuxCanvasSetStrokeJoin;
  FmuxCanvasSetStrokeDash := Stub_FmuxCanvasSetStrokeDash;
  FmuxBitmapCreate := Stub_FmuxBitmapCreate;
  FmuxBitmapDestroy := Stub_FmuxBitmapDestroy;
  FmuxGetBitmapInfo := Stub_FmuxGetBitmapInfo;
  FmuxCanvasDrawBitmap := Stub_FmuxCanvasDrawBitmap;
  FmuxCreateContext := Stub_FmuxCreateContext;
  FmuxDestroyContext := Stub_FmuxDestroyContext;
  FmuxBitmapLoad := Stub_FmuxBitmapLoad;
  FmuxBitmapSave := Stub_FmuxBitmapSave;
  FmuxCreateTextLayout := Stub_FmuxCreateTextLayout;
  FmuxDestroyTextLayout := Stub_FmuxDestroyTextLayout;
  FmuxDrawTextLayout := Stub_FmuxDrawTextLayout;
  FmuxGetTextLayoutRect := Stub_FmuxGetTextLayoutRect;
  FmuxLayoutPositionAtPoint := Stub_FmuxLayoutPositionAtPoint;
  FmuxLayoutMeasureRange := Stub_FmuxLayoutMeasureRange;
  FmuxLayoutToPath := Stub_FmuxLayoutToPath;
  FmuxAddCustomFont := Stub_FmuxAddCustomFont;
  FmuxAddCustomFontFromData := Stub_FmuxAddCustomFontFromData;
  FmuxGetFontCount := Stub_FmuxGetFontCount;
  FmuxGetFontName := Stub_FmuxGetFontName;
  FmuxSetLog := Stub_FmuxSetLog;
  FmuxCreateSharedContext := Stub_FmuxCreateSharedContext;
  FmuxCreateThreadContext := Stub_FmuxCreateThreadContext;
  FmuxMakeCurrentContext := Stub_FmuxMakeCurrentContext;
  FmuxFlushBuffer := Stub_FmuxFlushBuffer;
  FmuxCreateMainMenu := Stub_FmuxCreateMainMenu;
  FmuxCreateMenu := Stub_FmuxCreateMenu;
  FmuxCreateMenuItem := Stub_FmuxCreateMenuItem;
  FmuxMenuAddItem := Stub_FmuxMenuAddItem;
  FmuxSetSubmenu := Stub_FmuxSetSubmenu;
  FmuxUpdateMenuItem := Stub_FmuxUpdateMenuItem;
  FmuxMessageDialog := Stub_FmuxMessageDialog;
  FmuxInputQuery := Stub_FmuxInputQuery;
  FmuxFilesDialog := Stub_FmuxFilesDialog;
  FmuxClipboardHasText := Stub_FmuxClipboardHasText;
  FmuxClipboardGetText := Stub_FmuxClipboardGetText;
  FmuxClipboardSetText := Stub_FmuxClipboardSetText;
  FmuxClipboardHasImage := Stub_FmuxClipboardHasImage;
  FmuxClipboardGetImage := Stub_FmuxClipboardGetImage;
  FmuxClipboardSetImage := Stub_FmuxClipboardSetImage;
  FmuxClipboardHasCustom := Stub_FmuxClipboardHasCustom;
  FmuxClipboardGetCustom := Stub_FmuxClipboardGetCustom;
  FmuxClipboardSetCustom := Stub_FmuxClipboardSetCustom;
  FmuxClipboardSetArray := Stub_FmuxClipboardSetArray;
  FmuxEnumPrinters := Stub_FmuxEnumPrinters;
  FmuxIsDefaultPrinter := Stub_FmuxIsDefaultPrinter;
  FmuxGetPageSettings := Stub_FmuxGetPageSettings;
  FmuxPrintDialog := Stub_FmuxPrintDialog;
  FmuxPageSetupDefault := Stub_FmuxPageSetupDefault;
  FmuxPageSetupDialog := Stub_FmuxPageSetupDialog;
  FmuxPrinterRun := Stub_FmuxPrinterRun;
  FmuxGetOrientation := Stub_FmuxGetOrientation;
  FmuxSetOrientation := Stub_FmuxSetOrientation;
  FmuxCreatePDFContext := Stub_FmuxCreatePDFContext;
  FmuxDestroyPDFContext := Stub_FmuxDestroyPDFContext;
  FmuxPDFContextNewPage := Stub_FmuxPDFContextNewPage;
  FmuxBeginDoc := Stub_FmuxBeginDoc;
  FmuxAbortDoc := Stub_FmuxAbortDoc;
  FmuxEndDoc := Stub_FmuxEndDoc;
  FmuxBeginPage := Stub_FmuxBeginPage;
  FmuxEnumPaperSizes := Stub_FmuxEnumPaperSizes;
  FmuxAddCustomPaperSize := Stub_FmuxAddCustomPaperSize;
  FmuxSelectFormatByPaperSize := Stub_FmuxSelectFormatByPaperSize;
  FmuxSetAlwaysAskOutputFile := Stub_FmuxSetAlwaysAskOutputFile;
  FmuxSetCursor := Stub_FmuxSetCursor;
  FmuxImeEnterControl := Stub_FmuxImeEnterControl;
  FmuxImeExitControl := Stub_FmuxImeExitControl;
  FmuxImeSetCaretPos := Stub_FmuxImeSetCaretPos;
  FmuxGetDisplayInfo := Stub_FmuxGetDisplayInfo;
  FmuxGetDisplayFromWindow := Stub_FmuxGetDisplayFromWindow;
  FmuxGetDisplayFromPoint := Stub_FmuxGetDisplayFromPoint;
  FmuxTakeScreenshot := Stub_FmuxTakeScreenshot;
  FmuxIsWebViewInstalled := Stub_FmuxIsWebViewInstalled;
  FmuxCreateWebView := Stub_FmuxCreateWebView;
  FmuxWebViewShow := Stub_FmuxWebViewShow;
  FmuxWebViewSetBounds := Stub_FmuxWebViewSetBounds;
  FmuxWebViewNavigate := Stub_FmuxWebViewNavigate;
  FmuxWebViewLoadText := Stub_FmuxWebViewLoadText;
  FmuxWebViewCanGoBack := Stub_FmuxWebViewCanGoBack;
  FmuxWebViewGoBack := Stub_FmuxWebViewGoBack;
  FmuxWebViewCanGoForward := Stub_FmuxWebViewCanGoForward;
  FmuxWebViewGoForward := Stub_FmuxWebViewGoForward;
  FmuxWebViewReload := Stub_FmuxWebViewReload;
  FmuxEvaluateJavaScript := Stub_FmuxEvaluateJavaScript;
  FmuxWebViewGetUrl := Stub_FmuxWebViewGetUrl;
  FmuxWebViewStop := Stub_FmuxWebViewStop;
  FmuxDestroyWebView := Stub_FmuxDestroyWebView;
  FmuxOpenFile := Stub_FmuxOpenFile;
  FmuxOpenUrl := Stub_FmuxOpenUrl;
  FmuxGetFileIcon := Stub_FmuxGetFileIcon;
  FmuxGetFileType := Stub_FmuxGetFileType;
  FmuxMediaInstalled := Stub_FmuxMediaInstalled;
  FmuxCreateMedia := Stub_FmuxCreateMedia;
  FmuxDestroyMedia := Stub_FmuxDestroyMedia;
  FmuxMediaPlay := Stub_FmuxMediaPlay;
  FmuxMediaStop := Stub_FmuxMediaStop;
  FmuxMediaGetDuration := Stub_FmuxMediaGetDuration;
  FmuxMediaGetCurrent := Stub_FmuxMediaGetCurrent;
  FmuxMediaSetCurrent := Stub_FmuxMediaSetCurrent;
  FmuxMediaSetVisible := Stub_FmuxMediaSetVisible;
  FmuxMediaSetBounds := Stub_FmuxMediaSetBounds;
  FmuxMediaGetVideoSize := Stub_FmuxMediaGetVideoSize;
  FmuxMediaGetVolume := Stub_FmuxMediaGetVolume;
  FmuxMediaSetVolume := Stub_FmuxMediaSetVolume;
  FmuxMediaGetState := Stub_FmuxMediaGetState;
  FmuxBeginDragDrop := Stub_FmuxBeginDragDrop;
  FmuxCaptureDeviceEnum := Stub_FmuxCaptureDeviceEnum;
  FmuxStartVideoCapture := Stub_FmuxStartVideoCapture;
  FmuxStopVideoCapture := Stub_FmuxStopVideoCapture;
  FmuxGetMousePos := Stub_FmuxGetMousePos;
  FmuxGetDefaultCursor := Stub_FmuxGetDefaultCursor;
  FmuxGetCursor := Stub_FmuxGetCursor;
  FmuxGetCursorBitmap := Stub_FmuxGetCursorBitmap;
  FmuxGenMouseMove := Stub_FmuxGenMouseMove;
  FmuxGenMouseDown := Stub_FmuxGenMouseDown;
  FmuxGenMouseUp := Stub_FmuxGenMouseUp;
  FmuxGenMouseWheel := Stub_FmuxGenMouseWheel;
  FmuxGenKeyDown := Stub_FmuxGenKeyDown;
  FmuxGenKeyUp := Stub_FmuxGenKeyUp;
  FmuxGetVersionInfo := Stub_FmuxGetVersionInfo;
  FmuxSetVersionInfo := Stub_FmuxSetVersionInfo;
  IsWayland := Stub_IsWayland;
  IsBroadway := Stub_IsBroadway;
end;

var
  GLoaded: Boolean = False;

procedure LoadLib;
begin
  if GLoaded then
    Exit;
  GLoaded := True;
  InstallFmuxApi(AssignStubs);
end;

initialization
  LoadLib;

end.

