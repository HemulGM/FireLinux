unit HelloMain;

{ FireLinux demo. Static controls, animations, dialogs and timers are declared in HelloMain.fmx. }

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Rtti,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Objects, FMX.StdCtrls,
  FMX.Edit, FMX.ListBox, FMX.Ani, FMX.Layouts, FMX.TabControl, FMX.Memo,
  FMX.Filter.Effects, FMX.Controls.Presentation, FMX.Dialogs, HelloWindow,
  FMX.Memo.Types, FMX.ScrollBox, FMX.Menus, FMX.ActnList, System.Actions,
  System.Math.Vectors, FMX.Controls3D, FMX.Objects3D, FMX.Viewport3D,
  FMX.MaterialSources, FMX.Types3D, FireLinux.Vulkan;

type
  THelloForm = class(TForm)
    Header: TLayout;
    TitleText: TText;
    SubtitleLabel: TLabel;
    StatusRow: TLayout;
    MouseLabel: TLabel;
    TimerLabel: TLabel;
    BackendLabel: TLabel;
    DemoTabs: TTabControl;
    ControlsTab: TTabItem;
    ControlsScroll: TVertScrollBox;
    ControlsContent: TLayout;
    ControlsIntro: TLabel;
    ClickRow: TLayout;
    ClickButton: TButton;
    CountLabel: TLabel;
    EditRow: TLayout;
    EditBox: TEdit;
    EchoLabel: TLabel;
    ColorRow: TLayout;
    ColorCombo: TComboBox;
    ColorSwatch: TRectangle;
    ColorLabel: TLabel;
    ToggleRow: TLayout;
    CheckExample: TCheckBox;
    SwitchExample: TSwitch;
    RadioOne: TRadioButton;
    RadioTwo: TRadioButton;
    ProgressRow: TLayout;
    ProgressSlider: TTrackBar;
    ProgressLabel: TLabel;
    ProgressBar: TProgressBar;
    ClipboardRow: TLayout;
    CopyButton: TButton;
    PasteButton: TButton;
    ClipLabel: TLabel;
    NotesLabel: TLabel;
    NotesMemo: TMemo;
    ImagesTab: TTabItem;
    ImagesScroll: TVertScrollBox;
    ImagesContent: TLayout;
    ImagesIntro: TLabel;
    AnimationRow: TLayout;
    GradientBox: TRectangle;
    CircleDock: TLayout;
    Circle: TCircle;
    PulseAnimation: TFloatAnimation;
    SpinnerDock: TLayout;
    Spinner: TRectangle;
    AnimationActions: TLayout;
    SpinCheck: TCheckBox;
    AnimationHint: TLabel;
    ImageRow: TLayout;
    PngCard: TLayout;
    PngLabel: TLabel;
    PngImage: TImage;
    JpegCard: TLayout;
    JpegLabel: TLabel;
    JpegImage: TImage;
    ImageActions: TLayout;
    ImageButton: TButton;
    OpacityLabel: TLabel;
    ImageOpacity: TTrackBar;
    ImageStatusLabel: TLabel;
    DialogsTab: TTabItem;
    DialogsScroll: TVertScrollBox;
    DialogsContent: TLayout;
    DialogsIntro: TLabel;
    BackendRow: TLayout;
    BackendCaption: TLabel;
    BackendCombo: TComboBox;
    FallbackHint: TLabel;
    FileDialogRow: TLayout;
    OpenButton: TButton;
    SaveButton: TButton;
    FolderButton: TButton;
    MessageRow: TLayout;
    MessageButton: TButton;
    InputButton: TButton;
    ResultsLabel: TLabel;
    DialogResults: TMemo;
    PlatformTab: TTabItem;
    PlatformScroll: TVertScrollBox;
    PlatformContent: TLayout;
    PlatformIntro: TLabel;
    WindowRow: TLayout;
    SecondButton: TButton;
    ModalButton: TButton;
    SizeRow: TLayout;
    MaximizeButton: TButton;
    ResizeButton: TButton;
    PlatformResultLabel: TLabel;
    NativeCaption: TLabel;
    NativeInfo: TMemo;
    DragTab: TTabItem;
    DragScroll: TVertScrollBox;
    DragContent: TLayout;
    DragIntro: TLabel;
    DragTextEdit: TEdit;
    DragActions: TLayout;
    DragTextButton: TButton;
    DragFilesButton: TButton;
    SelectDragFilesButton: TButton;
    DragFileLabel: TLabel;
    DropArea: TRectangle;
    DropHint: TText;
    DropResults: TMemo;
    AnimTimer: TTimer;
    NativeTimer: TTimer;
    QuitTimer: TTimer;
    SelfTestTimer: TTimer;
    OpenDialog: TOpenDialog;
    SaveDialog: TSaveDialog;
    ImageDialog: TOpenDialog;
    StyleBookWinUI3: TStyleBook;
    MainMenu: TMainMenu;
    MenuFile: TMenuItem;
    MenuOpen: TMenuItem;
    MenuSave: TMenuItem;
    MenuFolder: TMenuItem;
    MenuFileSeparator: TMenuItem;
    MenuExit: TMenuItem;
    MenuView: TMenuItem;
    MenuTabs: TMenuItem;
    MenuControls: TMenuItem;
    MenuImages: TMenuItem;
    MenuDialogs: TMenuItem;
    MenuPlatform: TMenuItem;
    MenuDrag: TMenuItem;
    MenuViewSeparator: TMenuItem;
    MenuTicks: TMenuItem;
    MenuOptions: TMenuItem;
    MenuModeCopy: TMenuItem;
    MenuModeMove: TMenuItem;
    MenuOptionsSeparator: TMenuItem;
    MenuAvailability: TMenuItem;
    MenuDisabled: TMenuItem;
    MenuHidden: TMenuItem;
    MenuHelp: TMenuItem;
    MenuAbout: TMenuItem;
    MenuActions: TActionList;
    MenuTicksAction: TAction;
    TabItem3D: TTabItem;
    Viewport3D1: TViewport3D;
    SceneLayout: TLayout;
    SceneHint: TLabel;
    SceneActions: TLayout;
    SceneSpin: TCheckBox;
    SceneReset: TButton;
    SceneCube: TCube;
    SceneSphere: TSphere;
    SceneLight: TLight;
    SceneCamera: TCamera;
    SceneMaterial: TLightMaterialSource;
    SphereMaterial: TLightMaterialSource;
    Menu3D: TMenuItem;
    procedure SceneResetClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormResize(Sender: TObject);
    procedure FormMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Single);
    procedure FormKeyDown(Sender: TObject; var Key: Word; var KeyChar: Char; Shift: TShiftState);
    procedure FormMouseWheel(Sender: TObject; Shift: TShiftState; WheelDelta: Integer; var Handled: Boolean);
    procedure ClickButtonClick(Sender: TObject);
    procedure EditChangeTracking(Sender: TObject);
    procedure EditKeyDown(Sender: TObject; var Key: Word; var KeyChar: Char; Shift: TShiftState);
    procedure ComboChange(Sender: TObject);
    procedure CheckChange(Sender: TObject);
    procedure ProgressChange(Sender: TObject);
    procedure CopyButtonClick(Sender: TObject);
    procedure PasteButtonClick(Sender: TObject);
    procedure SecondButtonClick(Sender: TObject);
    procedure ModalButtonClick(Sender: TObject);
    procedure MaximizeButtonClick(Sender: TObject);
    procedure ResizeButtonClick(Sender: TObject);
    procedure MessageButtonClick(Sender: TObject);
    procedure InputButtonClick(Sender: TObject);
    procedure OpenButtonClick(Sender: TObject);
    procedure SaveButtonClick(Sender: TObject);
    procedure FolderButtonClick(Sender: TObject);
    procedure BackendChange(Sender: TObject);
    procedure ImageButtonClick(Sender: TObject);
    procedure ImageOpacityChange(Sender: TObject);
    procedure DemoTabsChange(Sender: TObject);
    procedure AnimTimerTimer(Sender: TObject);
    procedure QuitTimerTimer(Sender: TObject);
    procedure NativeTimerTimer(Sender: TObject);
    procedure SelfTestStep(Sender: TObject);
    procedure DragSourceMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Single);
    procedure SelectDragFilesClick(Sender: TObject);
    procedure DropAreaOver(Sender: TObject; const Data: TDragObject; const Point: TPointF; var Operation: TDragOperation);
    procedure DropAreaDrop(Sender: TObject; const Data: TDragObject; const Point: TPointF);
    procedure DropAreaLeave(Sender: TObject);
    procedure DragSourceEnd(Sender: TObject);
    procedure MenuExitClick(Sender: TObject);
    procedure MenuTabClick(Sender: TObject);
    procedure MenuTicksExecute(Sender: TObject);
    procedure MenuModeClick(Sender: TObject);
    procedure MenuAvailabilityClick(Sender: TObject);
    procedure MenuExampleClick(Sender: TObject);
  private
    FVerbose: Boolean;
    FClicks, FTicks, FSecondCount, FSelfStep: Integer;
    FTickStart: TDateTime;
    FSelfSecond: TDemoWindow;
    FDragFiles: TArray<string>;
    procedure Log(const Text: string);
    procedure DialogResult(const Text: string);
    procedure TraceLayout;
    procedure AppException(Sender: TObject; E: Exception);
  end;

var
  HelloForm: THelloForm;

implementation

{$R *.fmx}

uses
  System.UIConsts, System.DateUtils, System.IOUtils, FMX.Platform,
  FMX.DialogService.Sync, FireLinux.Dialogs;

type
  // Same contract a renderer such as FastCanvas can declare without depending on FireLinux.
  IWaylandNativeWindowContract = interface
    ['{B04A2FBC-1322-42BC-98A6-D526A7854F2C}']
    function GetWaylandDisplay: Pointer;
    function GetWaylandSurface(const AHandle: TWindowHandle): Pointer;
    function GetBufferSize(const AHandle: TWindowHandle): TSize;
    function GetScale(const AHandle: TWindowHandle): Single;
    procedure SetExternalPresentation(const AHandle: TWindowHandle; const AValue: Boolean);
  end;

const
  CComboColors: array[0..4] of TAlphaColor = (TAlphaColors.Crimson, TAlphaColors.Seagreen,
    TAlphaColors.Royalblue, TAlphaColors.Gold, TAlphaColors.Darkorchid);

procedure THelloForm.Log(const Text: string);
begin
  if FVerbose then
  begin
    Writeln('[hello] ', Text);
    Flush(Output);
  end;
end;

procedure THelloForm.FormCreate(Sender: TObject);
var
  I, QuitAfter: Integer;
  Argument, TabName: string;
begin
  SetTextCodePage(Output, CP_UTF8);
  FTickStart := Now;
  QuitAfter := 0;
  for I := 1 to ParamCount do
  begin
    Argument := ParamStr(I);
    if Argument.StartsWith('--quit-after=') then
      QuitAfter := StrToIntDef(Argument.Substring(13), 0)
    else if Argument = '--verbose' then
      FVerbose := True
    else if Argument = '--selftest' then
    begin
      FVerbose := True;
      SelfTestTimer.Enabled := True;
    end
    else if Argument.StartsWith('--tab=') then
      TabName := Argument.Substring(6);
  end;
  if TabName = 'images' then
    DemoTabs.ActiveTab := ImagesTab
  else if TabName = 'dialogs' then
    DemoTabs.ActiveTab := DialogsTab
  else if TabName = 'platform' then
    DemoTabs.ActiveTab := PlatformTab
  else if TabName = 'drag' then
    DemoTabs.ActiveTab := DragTab
  else if TabName = '3d' then
    DemoTabs.ActiveTab := TabItem3D;
  if Viewport3D1.Context is TVulkanContext then
  begin
    TabItem3D.Text := '3D / Vulkan';
    Menu3D.Text := TabItem3D.Text;
    SceneHint.Text := 'TViewport3D / Vulkan: ' + VulkanRendererName;
  end;
  SceneMaterial.Texture.Assign(PngImage.Bitmap);
  SceneResetClick(nil);
  DemoTabsChange(nil);
  if QuitAfter > 0 then
  begin
    QuitTimer.Interval := QuitAfter * 1000;
    QuitTimer.Enabled := True;
  end;
  Application.OnException := AppException;
  Log('created');
  Log('canvas ' + TCanvasManager.DefaultCanvas.ClassName);
  Log(Format('demo: %d tabs, PNG %dx%d, JPEG %dx%d', [DemoTabs.TabCount,
        PngImage.Bitmap.Width, PngImage.Bitmap.Height, JpegImage.Bitmap.Width, JpegImage.Bitmap.Height]));
end;

procedure THelloForm.AppException(Sender: TObject; E: Exception);
begin
  Log(Format('exception %s: %s (at %p)', [E.ClassName, E.Message, ExceptAddr]));
  Application.ShowException(E);
end;

procedure THelloForm.FormDestroy(Sender: TObject);
begin
  Application.OnException := nil;
  FreeAndNil(FSelfSecond);
  Log('destroyed');
end;

procedure THelloForm.TraceLayout;
var
  Control: TControl;
  Point: TPointF;
begin
  if not FVerbose or (DemoTabs = nil) then
    Exit;
  for Control in [ControlsTab, ImagesTab, DialogsTab, PlatformTab, DragTab, DragTextButton, DropArea, ClickButton, EditBox, ColorCombo, SpinCheck, CopyButton, PasteButton, SecondButton, ModalButton, MaximizeButton, ResizeButton] do
  begin
    Point := Control.LocalToAbsolute(PointF(Control.Width / 2, Control.Height / 2));
    Log(Format('layout %s %.0f %.0f', [Control.Name, Point.X, Point.Y]));
  end;
end;

procedure THelloForm.FormResize(Sender: TObject);
begin
  Log(Format('resize %dx%d state %d', [ClientWidth, ClientHeight, Ord(WindowState)]));
  if MaximizeButton <> nil then
    if WindowState = TWindowState.wsMaximized then
      MaximizeButton.Text := 'Восстановить'
    else
      MaximizeButton.Text := 'Развернуть';
  TraceLayout;
end;

procedure THelloForm.FormMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Single);
begin
  if (X < 0) or (Y < 0) then
    MouseLabel.Text := 'Mouse: вне окна'
  else
    MouseLabel.Text := Format('Mouse: %.0f, %.0f', [X, Y]);
end;

procedure THelloForm.FormKeyDown(Sender: TObject; var Key: Word; var KeyChar: Char; Shift: TShiftState);
begin
  Log(Format('key down vk=%d char=#%d', [Key, Ord(KeyChar)]));
end;

procedure THelloForm.FormMouseWheel(Sender: TObject; Shift: TShiftState; WheelDelta: Integer; var Handled: Boolean);
begin
  Spinner.RotationAngle := Spinner.RotationAngle + WheelDelta / 12;
  Handled := Sender = Spinner;
  Log(Format('wheel %d', [WheelDelta]));
end;

procedure THelloForm.ClickButtonClick(Sender: TObject);
begin
  Inc(FClicks);
  CountLabel.Text := Format('Нажатий: %d', [FClicks]);
  Log(Format('click %d', [FClicks]));
end;

procedure THelloForm.EditChangeTracking(Sender: TObject);
begin
  EchoLabel.Text := 'Введено: ' + EditBox.Text;
  Log('edit "' + EditBox.Text + '"');
end;

procedure THelloForm.EditKeyDown(Sender: TObject; var Key: Word; var KeyChar: Char; Shift: TShiftState);
begin
  Log(Format('edit key vk=%d char=#%d ctrl=%s shift=%s', [Key, Ord(KeyChar),
        BoolToStr(ssCtrl in Shift, True), BoolToStr(ssShift in Shift, True)]));
end;

procedure THelloForm.ComboChange(Sender: TObject);
begin
  if (ColorCombo <> nil) and (ColorSwatch <> nil) and (ColorCombo.ItemIndex >= 0) then
  begin
    ColorSwatch.Fill.Color := CComboColors[ColorCombo.ItemIndex];
    Circle.Fill.Color := CComboColors[ColorCombo.ItemIndex];
    Log('combo ' + ColorCombo.Items[ColorCombo.ItemIndex]);
  end;
end;

procedure THelloForm.CheckChange(Sender: TObject);
begin
  if SpinCheck <> nil then
    Log('check ' + BoolToStr(SpinCheck.IsChecked, True));
end;

procedure THelloForm.ProgressChange(Sender: TObject);
begin
  if (ProgressSlider <> nil) and (ProgressBar <> nil) then
  begin
    ProgressBar.Value := ProgressSlider.Value;
    ProgressLabel.Text := Format('Значение: %.0f%%', [ProgressSlider.Value]);
  end;
end;

procedure THelloForm.CopyButtonClick(Sender: TObject);
var
  Service: IFMXClipboardService;
begin
  if TPlatformServices.Current.SupportsPlatformService(IFMXClipboardService, Service) then
  begin
    Service.SetClipboard(EditBox.Text);
    ClipLabel.Text := 'Скопировано: ' + EditBox.Text;
    Log('copied "' + EditBox.Text + '"');
  end;
end;

procedure THelloForm.PasteButtonClick(Sender: TObject);
var
  Service: IFMXClipboardService;
  Value: TValue;
begin
  if TPlatformServices.Current.SupportsPlatformService(IFMXClipboardService, Service) then
  begin
    Value := Service.GetClipboard;
    if Value.IsEmpty then
      ClipLabel.Text := 'Буфер обмена пуст'
    else
      ClipLabel.Text := 'Из буфера: ' + Value.ToString;
    Log('pasted "' + Value.ToString + '"');
  end;
end;

procedure THelloForm.SecondButtonClick(Sender: TObject);
var
  Window: TDemoWindow;
begin
  Inc(FSecondCount);
  Window := TDemoWindow.Create(Application);
  Window.Configure(FSecondCount, False, StyleBookWinUI3, FVerbose);
  Window.Show;
  Log('second form shown');
end;

procedure THelloForm.ModalButtonClick(Sender: TObject);
var
  Window: TDemoWindow;
  Result: TModalResult;
begin
  Window := TDemoWindow.Create(nil);
  try
    Window.Configure(0, True, StyleBookWinUI3, FVerbose);
    Log('modal shown');
    Result := Window.ShowModal;
    Log(Format('modal result %d', [Result]));
    PlatformResultLabel.Text := Format('Результат модальной формы: %d', [Result]);
  finally
    Window.Free;
  end;
end;

procedure THelloForm.MaximizeButtonClick(Sender: TObject);
begin
  if WindowState = TWindowState.wsMaximized then
    WindowState := TWindowState.wsNormal
  else
    WindowState := TWindowState.wsMaximized;
  Log('window state ' + IntToStr(Ord(WindowState)));
end;

procedure THelloForm.ResizeButtonClick(Sender: TObject);
begin
  ClientWidth := 760;
  ClientHeight := 560;
  Log(Format('resized by code to %dx%d', [ClientWidth, ClientHeight]));
end;

procedure THelloForm.DialogResult(const Text: string);
begin
  DialogResults.Lines.Text := Text;
  Log('dialog: ' + Text);
end;

procedure THelloForm.MessageButtonClick(Sender: TObject);
var
  Result: TModalResult;
begin
  Log('message shown');
  Result := TDialogServiceSync.MessageDialog('Вам нравится FMX на Wayland?', TMsgDlgType.mtConfirmation,
    [TMsgDlgBtn.mbYes, TMsgDlgBtn.mbNo], TMsgDlgBtn.mbYes, 0);
  Log(Format('message result %d', [Result]));
  DialogResult(Format('Результат сообщения: %d', [Result]));
end;

procedure THelloForm.InputButtonClick(Sender: TObject);
var
  Values: TArray<string>;
begin
  Values := ['Привет, Wayland!', 'Delphi 13'];
  if TDialogServiceSync.InputQuery('Ввод текста', ['Сообщение', 'Имя'], Values) then
    DialogResult(string.Join(sLineBreak, Values))
  else
    DialogResult('Ввод отменён');
end;

procedure THelloForm.OpenButtonClick(Sender: TObject);
begin
  try
    if OpenDialog.Execute then
      DialogResult('Выбраны файлы:' + sLineBreak + OpenDialog.Files.Text)
    else
      DialogResult('Открытие отменено');
  except
    on E: Exception do
      DialogResult(E.Message);
  end;
end;

procedure THelloForm.SaveButtonClick(Sender: TObject);
begin
  try
    if SaveDialog.Execute then
      DialogResult('Путь для сохранения (файл не записан):' + sLineBreak + SaveDialog.FileName)
    else
      DialogResult('Сохранение отменено');
  except
    on E: Exception do
      DialogResult(E.Message);
  end;
end;

procedure THelloForm.FolderButtonClick(Sender: TObject);
var
  Directory: string;
begin
  Directory := GetCurrentDir;
  try
    if SelectDirectory('Выберите папку', Directory, Directory) then
      DialogResult('Выбрана папка:' + sLineBreak + Directory)
    else
      DialogResult('Выбор папки отменён');
  except
    on E: Exception do
      DialogResult(E.Message);
  end;
end;

procedure THelloForm.BackendChange(Sender: TObject);
begin
  if (BackendCombo = nil) or (BackendCombo.ItemIndex < 0) then
    Exit;
  if BackendCombo.ItemIndex = 1 then
    SetFireLinuxDialogBackend(TFireLinuxDialogBackend.Create)
  else
    SetFireLinuxDialogBackend(nil);
  if DialogResults <> nil then
    DialogResult('Бэкенд: ' + BackendCombo.Items[BackendCombo.ItemIndex]);
end;

procedure THelloForm.ImageButtonClick(Sender: TObject);
begin
  try
    if ImageDialog.Execute then
    begin
      PngImage.Bitmap.LoadFromFile(ImageDialog.FileName);
      ImageStatusLabel.Text := Format('%s (%d × %d)', [TPath.GetFileName(ImageDialog.FileName),
          PngImage.Bitmap.Width, PngImage.Bitmap.Height]);
    end;
  except
    on E: Exception do
      ImageStatusLabel.Text := E.Message;
  end;
end;

procedure THelloForm.ImageOpacityChange(Sender: TObject);
begin
  if (ImageOpacity <> nil) and (PngImage <> nil) and (JpegImage <> nil) then
  begin
    PngImage.Opacity := ImageOpacity.Value;
    JpegImage.Opacity := ImageOpacity.Value;
  end;
end;

procedure THelloForm.DemoTabsChange(Sender: TObject);
begin
  if (DemoTabs = nil) or (PulseAnimation = nil) or (DemoTabs.ActiveTab = nil) then
    Exit;
  PulseAnimation.Enabled := DemoTabs.ActiveTab = ImagesTab;
  Log('tab ' + DemoTabs.ActiveTab.Name);
  TraceLayout;
end;

procedure THelloForm.DragSourceMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Single);
var
  Service: IFMXDragDropService;
  Data: TDragObject;
begin
  if Button <> TMouseButton.mbLeft then
    Exit;
  Data := Default(TDragObject);
  Data.Source := Sender;
  if Sender = DragFilesButton then
  begin
    if Length(FDragFiles) = 0 then
    begin
      DragFileLabel.Text := 'Сначала выберите файлы';
      Exit;
    end;
    Data.Files := Copy(FDragFiles);
  end
  else
    Data.Data := DragTextEdit.Text;
  if TPlatformServices.Current.SupportsPlatformService(IFMXDragDropService, Service) then
    Service.BeginDragDrop(Self, Data, nil);
end;

procedure THelloForm.SelectDragFilesClick(Sender: TObject);
begin
  if OpenDialog.Execute then
  begin
    FDragFiles := OpenDialog.Files.ToStringArray;
    DragFileLabel.Text := Format('Выбрано файлов: %d', [Length(FDragFiles)]);
  end;
end;

procedure THelloForm.DropAreaOver(Sender: TObject; const Data: TDragObject; const Point: TPointF; var Operation: TDragOperation);
begin
  Operation := TDragOperation.None;
  if (Length(Data.Files) > 0) or Data.Data.IsType<string> or (Data.Source <> nil) then
  begin
    Operation := TDragOperation.Copy;
    DropArea.Fill.Color := $FF345B78;
  end;
end;

procedure THelloForm.DropAreaDrop(Sender: TObject; const Data: TDragObject; const Point: TPointF);
var
  FileName: string;
begin
  DropResults.Lines.Clear;
  if Data.Source <> nil then
    DropResults.Lines.Add('Источник внутри приложения');
  if Length(Data.Files) > 0 then
  begin
    DropResults.Lines.Add(Format('Файлов: %d', [Length(Data.Files)]));
    for FileName in Data.Files do
      DropResults.Lines.Add(FileName);
  end;
  if Data.Data.IsType<string>then
    DropResults.Lines.Add(Data.Data.AsString);
  Log('drop: ' + DropResults.Lines.Text.Trim);
  DropAreaLeave(nil);
end;

procedure THelloForm.DropAreaLeave(Sender: TObject);
begin
  DropArea.Fill.Color := $FF26323E;
end;

procedure THelloForm.DragSourceEnd(Sender: TObject);
begin
  Log('drag ended');
end;

procedure THelloForm.MenuExitClick(Sender: TObject);
begin
  Close;
end;

procedure THelloForm.MenuTabClick(Sender: TObject);
begin
  if Sender = MenuControls then
    DemoTabs.ActiveTab := ControlsTab
  else if Sender = MenuImages then
    DemoTabs.ActiveTab := ImagesTab
  else if Sender = MenuDialogs then
    DemoTabs.ActiveTab := DialogsTab
  else if Sender = MenuPlatform then
    DemoTabs.ActiveTab := PlatformTab
  else if Sender = MenuDrag then
    DemoTabs.ActiveTab := DragTab
  else if Sender = Menu3D then
    DemoTabs.ActiveTab := TabItem3D;
end;

procedure THelloForm.MenuTicksExecute(Sender: TObject);
begin
  AnimTimer.Enabled := MenuTicksAction.Checked;
  Log('menu: timer ' + BoolToStr(AnimTimer.Enabled, True));
end;

procedure THelloForm.MenuModeClick(Sender: TObject);
begin
  Log('menu: ' + TMenuItem(Sender).Text);
end;

procedure THelloForm.MenuAvailabilityClick(Sender: TObject);
begin
  MenuDisabled.Enabled := not MenuDisabled.Enabled;
  MenuHidden.Visible := not MenuHidden.Visible;
end;

procedure THelloForm.MenuExampleClick(Sender: TObject);
begin
  PlatformResultLabel.Text := 'Меню: ' + TMenuItem(Sender).Text;
  Log('menu: ' + TMenuItem(Sender).Text);
end;

procedure THelloForm.SceneResetClick(Sender: TObject);
begin
  SceneCube.RotationAngle.Point := Point3D(-20, 30, 0);
  SceneSphere.RotationAngle.Point := Point3D(0, 0, 0);
end;

procedure THelloForm.AnimTimerTimer(Sender: TObject);
var
  Seconds: Double;
begin
  Inc(FTicks);
  if SpinCheck.IsChecked and (DemoTabs.ActiveTab = ImagesTab) then
    Spinner.RotationAngle := Spinner.RotationAngle + 3;
  if SceneSpin.IsChecked and (DemoTabs.ActiveTab = TabItem3D) then
  begin
    SceneCube.RotationAngle.Y := SceneCube.RotationAngle.Y + 0.8;
    SceneSphere.RotationAngle.Y := SceneSphere.RotationAngle.Y - 0.5;
  end;
  Seconds := MilliSecondsBetween(Now, FTickStart) / 1000;
  if Seconds >= 1 then
  begin
    TimerLabel.Text := Format('Timer: %.0f ticks/s', [FTicks / Seconds]);
    FTicks := 0;
    FTickStart := Now;
  end;
end;

procedure THelloForm.NativeTimerTimer(Sender: TObject);
var
  Service: IWaylandNativeWindowContract;
  Size: TSize;
begin
  NativeTimer.Enabled := False;
  TraceLayout;
  if TPlatformServices.Current.SupportsPlatformService(IWaylandNativeWindowContract, Service) then
  begin
    Size := Service.GetBufferSize(Handle);
    NativeInfo.Lines.Text := Format('Wayland display: %p' + sLineBreak + 'Wayland surface: %p' + sLineBreak +
      'Buffer: %d × %d' + sLineBreak + 'Scale: %.2f', [Service.GetWaylandDisplay,
        Service.GetWaylandSurface(Handle), Size.cx, Size.cy, Service.GetScale(Handle)]);
    Log(Format('native: display=%p surface=%p buffer=%dx%d scale=%.2f', [Service.GetWaylandDisplay,
          Service.GetWaylandSurface(Handle), Size.cx, Size.cy, Service.GetScale(Handle)]));
  end;
end;

procedure THelloForm.SelfTestStep(Sender: TObject);
var
  Service: IFMXClipboardService;
  Value: TValue;
  Window: TDemoWindow;
  Result: TModalResult;
begin
  Inc(FSelfStep);
  case FSelfStep of
    1:
      TThread.CreateAnonymousThread(
        procedure
        begin
          TThread.Synchronize(nil,
            procedure
            begin
              Log('selftest: synchronize from a thread, on the main thread ' + BoolToStr(TThread.Current.ThreadID = MainThreadID, True));
            end);
          TThread.Queue(nil,
            procedure
            begin
              Log('selftest: queue from a thread, on the main thread ' + BoolToStr(TThread.Current.ThreadID = MainThreadID, True));
            end);
        end).Start;
    2:
      if TPlatformServices.Current.SupportsPlatformService(IFMXClipboardService, Service) then
      begin
        Service.SetClipboard('selftest clipboard ' + #$2713);
        Value := Service.GetClipboard;
        Log('selftest: clipboard "' + Value.ToString + '"');
      end;
    3:
      begin
        DemoTabs.ActiveTab := ControlsTab;
        ColorCombo.DropDown;
        Log('selftest: drop-down open ' + BoolToStr(ColorCombo.DroppedDown, True));
      end;
    7:
      begin
        if ColorCombo.DroppedDown then
          ColorCombo.DropDown;
        Log('selftest: drop-down closed ' + BoolToStr(not ColorCombo.DroppedDown, True));
      end;
    8:
      begin
        FSelfSecond := TDemoWindow.Create(nil);
        FSelfSecond.Configure(1, False, StyleBookWinUI3);
        FSelfSecond.Show;
        Log('selftest: second form shown');
      end;
    9:
      begin
        FreeAndNil(FSelfSecond);
        Log('selftest: second form freed');
      end;
    10:
      WindowState := TWindowState.wsMaximized;
    11:
      begin
        Log(Format('selftest: maximized %s %dx%d', [BoolToStr(WindowState = TWindowState.wsMaximized, True), ClientWidth, ClientHeight]));
        WindowState := TWindowState.wsNormal;
      end;
    12:
      Log(Format('selftest: restored %dx%d', [ClientWidth, ClientHeight]));
    13:
      begin
        SelfTestTimer.Enabled := False;
        Window := TDemoWindow.Create(nil);
        try
          Window.Configure(0, True, StyleBookWinUI3);
          Window.SelfCloseTimer.Enabled := True;
          Result := Window.ShowModal;
          Log(Format('selftest: modal result %d', [Result]));
        finally
          Window.Free;
        end;
        SelfTestTimer.Enabled := True;
      end;
    14:
      begin
        DemoTabs.ActiveTab := ImagesTab;
        Log('selftest: images tab');
      end;
    15:
      begin
        DemoTabs.ActiveTab := DialogsTab;
        BackendCombo.ItemIndex := 1;
        Log('selftest: FMX dialog backend');
      end;
    16:
      begin
        DemoTabs.ActiveTab := PlatformTab;
        Log('selftest: platform tab');
      end;
    17:
      begin
        SelfTestTimer.Enabled := False;
        Log('selftest: done');
        Close;
      end;
  end;
end;

procedure THelloForm.QuitTimerTimer(Sender: TObject);
begin
  QuitTimer.Enabled := False;
  Log('quit timer: closing');
  Close;
end;

end.

