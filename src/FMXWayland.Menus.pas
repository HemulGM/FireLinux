{ FMXWayland: TMainMenu rendered by the client on Wayland. MIT license. }
unit FMXWayland.Menus;

interface

uses
  System.SysUtils, System.Classes, System.UITypes, System.Generics.Collections,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Layouts, FMX.Menus;

type
  // The static view is streamed; menu items are dynamic projections of the application's TMainMenu.
  TFMXWaylandMainMenuView = class(TFrame)
    Content: TLayout;
    MenuBar: TMenuBar;
    RefreshTimer: TTimer;
    procedure RefreshTimerTimer(Sender: TObject);
  private
    FModel: TMainMenu;
    FForm: TCommonCustomForm;
    FItems: TDictionary<Pointer, TMenuItem>;
    FRebuild, FUpdating, FDestroying: Boolean;
    procedure Bind(Form: TCommonCustomForm; Model: TMainMenu);
    procedure Rebuild;
    procedure Sync;
    procedure Unbind(ResetHandles: Boolean);
    procedure SourceRemoved(Source: TMenuItem);
    procedure RequestRebuild;
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  end;

procedure InstallWaylandMenuService;
// The actual client-side bar, useful to inspect or test the platform view. Do not free it.
function WaylandMainMenuBar(Model: TMainMenu): TMenuBar;
function HandleWaylandMenuKey(Form: TCommonCustomForm; Key: Word; KeyChar: Char; Shift: TShiftState): Boolean;

implementation

uses System.Types, FMX.Platform, FMX.Helpers.Linux, FMX.ActnList;

{$R *.fmx}

type
  TMenuItemAccess = class(TMenuItem);

  TWaylandMenuItem = class(TMenuItem)
  private
    FSource: TMenuItem;
    FView: TFMXWaylandMainMenuView;
    procedure InvokeSource(Sender: TObject);
    procedure Sync;
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Single); override;
    procedure Click; override;
  public
    destructor Destroy; override;
  end;

  TWaylandMenuService = class(TInterfacedObject, IFMXMenuService)
  private
    FOriginal: IFMXMenuService;
    FViews: TDictionary<Pointer, TFMXWaylandMainMenuView>;
    FRetired: TList<TFMXWaylandMainMenuView>;
    FLoops: TList<IMenuView>;
    FUpdating: Integer;
    FCleanupQueued: Boolean;
    procedure Retire(View: TFMXWaylandMainMenuView; ResetHandles: Boolean);
    procedure Forget(View: TFMXWaylandMainMenuView);
    procedure QueueCleanup;
    procedure Cleanup;
    function ViewOf(Item: TFmxObject): TFMXWaylandMainMenuView;
    function LiveProxy(Item: TMenuItem): Boolean;
    procedure QueuePopup(Item: TMenuItem);
    function KeyDown(Form: TCommonCustomForm; Key: Word; KeyChar: Char; Shift: TShiftState): Boolean;
  public
    constructor Create(const Original: IFMXMenuService);
    destructor Destroy; override;
    procedure StartMenuLoop(const AView: IMenuView);
    function ShortCutToText(ShortCut: TShortCut): string;
    procedure ShortCutToKey(ShortCut: TShortCut; var Key: Word; var Shift: TShiftState);
    function TextToShortCut(Text: string): Integer;
    procedure CreateOSMenu(AForm: TCommonCustomForm; const AMenu: IItemsContainer);
    procedure UpdateMenuItem(const AItem: IItemsContainer; AChange: TMenuItemChanges);
    procedure DestroyMenuItem(const AItem: IItemsContainer);
    function IsMenuBarOnWindowBorder: Boolean;
    procedure UpdateMenuBar;
  end;

var
  GService: IFMXMenuService;
  GServiceObject: TWaylandMenuService;
  GPreviousInit: TProcedure;

procedure SetBackendHandle(Object_: TFmxObject; Handle: TFmxHandle);
var Native: INativeControl;
begin
  if Supports(Object_, INativeControl, Native) then Native.Handle := Handle;
end;

procedure TWaylandMenuItem.InvokeSource(Sender: TObject);
var Source: TMenuItem;
begin
  Source := FSource;
  if (Source = nil) or not Source.Enabled or not Source.Visible or Source.IsSeparator then Exit;
  // Only the source executes Action/OnClick and AutoCheck. The visual clone never duplicates an action link.
  TMenuItemAccess(Source).Click;
end;

procedure TWaylandMenuItem.Click;
begin
  // Queue the model's click, not a disposable clone's click. Structural rebuilds cannot lose the command.
  InvokeSource(Self);
end;

procedure TWaylandMenuItem.Sync;
var Source: TMenuItem;
begin
  Source := FSource;
  if Source = nil then Exit;
  Text := Source.Text;
  Enabled := Source.Enabled;
  Visible := Source.Visible;
  ShortCut := Source.ShortCut;
  AutoCheck := False;
  RadioItem := Source.RadioItem;
  GroupIndex := Source.GroupIndex;
  IsChecked := Source.IsChecked;
  ImageIndex := Source.ImageIndex;
  IGlyph(Self).Images := Source.Images;
  if not Bitmap.EqualsBitmap(Source.Bitmap) then Bitmap.Assign(Source.Bitmap);
end;

procedure TWaylandMenuItem.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Single);
begin
  if FView <> nil then FView.Sync;
  inherited;
end;

procedure TWaylandMenuItem.Notification(AComponent: TComponent; Operation: TOperation);
var Source: TMenuItem;
begin
  inherited;
  if (Operation = opRemove) and (AComponent = FSource) then
  begin
    Source := FSource; FSource := nil;
    Enabled := False; Visible := False;
    if FView <> nil then FView.SourceRemoved(Source);
  end;
end;

destructor TWaylandMenuItem.Destroy;
begin
  if FSource <> nil then FSource.RemoveFreeNotification(Self);
  FSource := nil; FView := nil;
  inherited;
end;

constructor TFMXWaylandMainMenuView.Create(AOwner: TComponent);
begin
  inherited;
  FItems := TDictionary<Pointer, TMenuItem>.Create;
end;

procedure TFMXWaylandMainMenuView.Bind(Form: TCommonCustomForm; Model: TMainMenu);
begin
  FForm := Form; FModel := Model;
  Model.FreeNotification(Self); Form.FreeNotification(Self);
  Parent := Form;
  // Loaded runs before this standalone frame has a form; TMenuBar then hides itself.
  // Restore visibility after attaching the scene so Align can size and paint the bar.
  MenuBar.Visible := True;
  SetBackendHandle(Model, TFmxHandle(Self));
  FRebuild := True;
  Sync;
end;

procedure TFMXWaylandMainMenuView.RequestRebuild;
begin
  if FDestroying then Exit;
  FRebuild := True;
end;

procedure TFMXWaylandMainMenuView.SourceRemoved(Source: TMenuItem);
begin
  FItems.Remove(Source);
  RequestRebuild;
end;

procedure TFMXWaylandMainMenuView.Rebuild;

  procedure AddItems(const Source: IItemsContainer; Parent_: TFmxObject);
  var I: Integer; Item: TMenuItem; Clone: TWaylandMenuItem;
  begin
    for I := 0 to Source.GetItemsCount - 1 do
      if Source.GetItem(I) is TMenuItem then
      begin
        Item := TMenuItem(Source.GetItem(I));
        Clone := TWaylandMenuItem.Create(Self);
        Clone.FSource := Item; Clone.FView := Self;
        Item.FreeNotification(Clone);
        Clone.OnClick := Clone.InvokeSource;
        Clone.Parent := Parent_;
        FItems.Add(Item, Clone);
        SetBackendHandle(Item, TFmxHandle(Clone));
        Clone.Sync;
        AddItems(Item, Clone);
      end;
  end;

var Source: Pointer; Clone: TMenuItem;
begin
  FRebuild := False;
  for Source in FItems.Keys do SetBackendHandle(TMenuItem(Source), 0);
  FItems.Clear;
  while MenuBar.ItemsCount > 0 do
  begin Clone := MenuBar.Items[0]; Clone.Free; end;
  MenuBar.Images := FModel.Images;
  AddItems(FModel, MenuBar);
end;

procedure TFMXWaylandMainMenuView.Sync;
var Clone: TMenuItem; I: Integer; AnyVisible: Boolean;
begin
  if FUpdating or FDestroying or (FModel = nil) or (GServiceObject = nil) or
    (csDestroying in FModel.ComponentState) then Exit;
  FUpdating := True;
  Inc(GServiceObject.FUpdating);
  try
    // FMX popups temporarily reparent visual children; never replace them inside a menu loop.
    if FRebuild and (GServiceObject.FLoops.Count = 0) then Rebuild;
    for Clone in FItems.Values.ToArray do TWaylandMenuItem(Clone).Sync;
    AnyVisible := False;
    for I := 0 to MenuBar.ItemsCount - 1 do if MenuBar.Items[I].Visible then begin AnyVisible := True; Break; end;
    Visible := AnyVisible;
  finally Dec(GServiceObject.FUpdating); FUpdating := False; end;
end;

procedure TFMXWaylandMainMenuView.Unbind(ResetHandles: Boolean);
var Source: Pointer; Model: TMainMenu; Clone: TMenuItem;
begin
  RefreshTimer.Enabled := False;
  Model := FModel; FModel := nil;
  if Model <> nil then Model.RemoveFreeNotification(Self);
  if FForm <> nil then FForm.RemoveFreeNotification(Self);
  FForm := nil;
  Inc(GServiceObject.FUpdating);
  try
    if ResetHandles and (Model <> nil) then SetBackendHandle(Model, 0);
    for Source in FItems.Keys do
    begin
      if ResetHandles then SetBackendHandle(TMenuItem(Source), 0);
      Clone := FItems[Source]; TMenuItem(Source).RemoveFreeNotification(Clone);
      TWaylandMenuItem(Clone).FSource := nil;
    end;
    FItems.Clear;
  finally Dec(GServiceObject.FUpdating); end;
end;

procedure TFMXWaylandMainMenuView.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited;
  if (Operation = opRemove) and ((AComponent = FModel) or (AComponent = FForm)) and (GServiceObject <> nil) then
    GServiceObject.Retire(Self, AComponent <> FModel);
end;

destructor TFMXWaylandMainMenuView.Destroy;
begin
  FDestroying := True;
  if GServiceObject <> nil then
  begin GServiceObject.Forget(Self); Unbind(True); end;
  FItems.Free;
  inherited;
end;

procedure TFMXWaylandMainMenuView.RefreshTimerTimer(Sender: TObject);
begin Sync; end;

constructor TWaylandMenuService.Create(const Original: IFMXMenuService);
begin
  inherited Create;
  FOriginal := Original;
  FViews := TDictionary<Pointer, TFMXWaylandMainMenuView>.Create;
  FRetired := TList<TFMXWaylandMainMenuView>.Create;
  FLoops := TList<IMenuView>.Create;
end;

destructor TWaylandMenuService.Destroy;
var View: TFMXWaylandMainMenuView;
begin
  for View in FViews.Values.ToArray do View.Free;
  for View in FRetired.ToArray do View.Free;
  FViews.Free; FRetired.Free; FLoops.Free;
  inherited;
end;

procedure TWaylandMenuService.Forget(View: TFMXWaylandMainMenuView);
begin
  if View.FModel <> nil then FViews.Remove(View.FModel);
  FRetired.Remove(View);
end;

procedure TWaylandMenuService.Retire(View: TFMXWaylandMainMenuView; ResetHandles: Boolean);
var Loop: IMenuView;
begin
  Forget(View);
  View.Visible := False;
  View.Unbind(ResetHandles);
  if FLoops.Count = 0 then View.Free
  else
  begin
    // End the nested native/FMХ menu loop first; Popup's finally block still owns the clones.
    for Loop in FLoops do Loop.Loop := False;
    View.Parent := nil; // A closing form must not free this frame before Popup unwinds.
    FRetired.Add(View);
    QueueCleanup;
  end;
end;

procedure TWaylandMenuService.QueueCleanup;
var Task: TThreadProcedure;
begin
  if FCleanupQueued then Exit;
  FCleanupQueued := True;
  Task := procedure
    begin
      if GServiceObject <> Self then Exit;
      FCleanupQueued := False; Cleanup;
    end;
  TThread.ForceQueue(nil, Task);
end;

procedure TWaylandMenuService.Cleanup;
var View: TFMXWaylandMainMenuView;
begin
  if FLoops.Count <> 0 then Exit;
  for View in FRetired.ToArray do View.Free;
  for View in FViews.Values.ToArray do View.Sync;
end;

function TWaylandMenuService.ViewOf(Item: TFmxObject): TFMXWaylandMainMenuView;
begin
  Result := nil;
  if Item is TMainMenu then FViews.TryGetValue(TMainMenu(Item), Result)
  else if Item is TMenuItem then FViews.TryGetValue(TMenuItem(Item).MainMenu, Result);
end;

procedure TWaylandMenuService.StartMenuLoop(const AView: IMenuView);
var I: Integer; Item: TMenuItem;
begin
  if AView = nil then Exit;
  FLoops.Add(AView);
  if AView.Selected = nil then
    for I := 0 to AView.GetItemsCount - 1 do
      if AView.GetItem(I) is TMenuItem then
      begin
        Item := TMenuItem(AView.GetItem(I));
        if Item.Visible and Item.Enabled and not Item.IsSeparator then begin AView.Selected := Item; Break; end;
      end;
  try
    // Keep TPlatformLinux's menu stack: it routes keyboard input to nested FMX menus.
    if FOriginal <> nil then FOriginal.StartMenuLoop(AView)
    else
    begin
      AView.Loop := True;
      while AView.Loop and not Application.Terminated do Application.HandleMessage;
    end;
  finally FLoops.Remove(AView); QueueCleanup; end;
end;

function TWaylandMenuService.LiveProxy(Item: TMenuItem): Boolean;
var View: TFMXWaylandMainMenuView; Clone: TMenuItem;
begin
  Result := False;
  for View in FViews.Values do
    for Clone in View.FItems.Values do if Pointer(Clone) = Pointer(Item) then Exit(True);
end;

procedure TWaylandMenuService.QueuePopup(Item: TMenuItem);
var Task: TThreadProcedure;
begin
  Task := procedure
    begin
      if (GServiceObject <> Self) or not LiveProxy(Item) then Exit;
      if Item.Visible and Item.Enabled then Item.Popup;
    end;
  TThread.ForceQueue(nil, Task);
end;

function TWaylandMenuService.KeyDown(Form: TCommonCustomForm; Key: Word; KeyChar: Char; Shift: TShiftState): Boolean;

  function Select(View: IMenuView; Direction: Integer; Edge: Boolean = False): TMenuItem;
  var I, Start, Count, Index: Integer; Item: TMenuItem;
  begin
    Result := nil; Count := View.GetItemsCount; Start := -1;
    if not Edge then
      for I := 0 to Count - 1 do if View.GetItem(I) = View.Selected then begin Start := I; Break; end;
    if Edge or (Start < 0) then
      if Direction > 0 then Start := -1 else Start := Count;
    for I := 1 to Count do
    begin
      Index := (Start + I * Direction + Count * 2) mod Count;
      if not (View.GetItem(Index) is TMenuItem) then Continue;
      Item := TMenuItem(View.GetItem(Index));
      if Item.Visible and Item.Enabled and not Item.IsSeparator then
      begin View.Selected := Item; Exit(Item); end;
    end;
  end;

  procedure Open(Item: TMenuItem);
  begin
    if Item = nil then Exit;
    if Item.ItemsCount > 0 then Item.Popup
    else
    begin
      TMenuItemAccess(Item).Click;
      for var Loop in FLoops do Loop.Loop := False;
    end;
  end;

var View, Parent: IMenuView; Item: TMenuItem; Frame: TFMXWaylandMainMenuView; I, P, Direction: Integer; CommandKey: Word;
  Text: string; BareF10: Boolean;
begin
  Result := False;
  BareF10 := (Key = vkF10) and (Shift = []);
  if FLoops.Count = 0 then
  begin
    if not BareF10 and not ((Shift = [ssAlt]) and (KeyChar <> #0)) then Exit;
    for Frame in FViews.Values do
      if (Frame.FForm = Form) and Frame.Visible then
      begin
        Frame.Sync; View := Frame.MenuBar; Item := nil;
        if BareF10 then Item := Select(View, 1, True)
        else for I := 0 to View.GetItemsCount - 1 do
        begin
          Text := TMenuItem(View.GetItem(I)).Text; P := 1;
          while P < Length(Text) do
          begin
            if Text[P] = '&' then
            begin
              if Text[P+1] = '&' then Inc(P)
              else if SameText(Text[P+1], string(KeyChar)) then begin Item := TMenuItem(View.GetItem(I)); Break; end;
            end;
            Inc(P);
          end;
          if Item <> nil then Break;
        end;
        if (Item <> nil) and Item.Enabled and Item.Visible then
        begin View.Selected := Item; Open(Item); Exit(True); end;
      end;
    Exit;
  end;
  View := FLoops.Last;
  if BareF10 then begin for View in FLoops do View.Loop := False; Exit(True); end;
  if Shift * [ssCtrl, ssAlt, ssCommand] <> [] then
  begin
    if View.Selected is TWaylandMenuItem then
    begin
      Frame := TWaylandMenuItem(View.Selected).FView;
      if (Frame <> nil) and (Frame.FModel <> nil) then
      begin
        CommandKey := Key;
        Frame.FModel.DialogKey(CommandKey, Shift);
        if CommandKey = 0 then
        begin for View in FLoops do View.Loop := False; Exit(True); end;
      end;
    end;
    Exit;
  end;
  Result := True;
  case Key of
    vkEscape: View.Loop := False;
    vkUp: Select(View, -1);
    vkDown: Select(View, 1);
    vkHome: Select(View, 1, True);
    vkEnd: Select(View, -1, True);
    vkReturn, vkSpace: Open(View.Selected);
    vkLeft, vkRight:
      begin
        Item := View.Selected;
        if (Key = vkRight) and (Item <> nil) and (Item.ItemsCount > 0) then Open(Item)
        else
        begin
          Parent := View.ParentView;
          if (Parent <> nil) and Parent.IsMenuBar then
          begin
            Direction := 1; if Key = vkLeft then Direction := -1;
            Item := Select(Parent, Direction);
            View.Loop := False;
            if Item <> nil then QueuePopup(Item);
          end
          else if Key = vkLeft then View.Loop := False;
        end;
      end;
  else Result := False; end;
end;

function TWaylandMenuService.ShortCutToText(ShortCut: TShortCut): string;
begin Result := FMX.Helpers.Linux.ShortCutToText(ShortCut); end;

procedure TWaylandMenuService.ShortCutToKey(ShortCut: TShortCut; var Key: Word; var Shift: TShiftState);
begin FMX.Helpers.Linux.ShortCutToKey(ShortCut, Key, Shift); end;

function TWaylandMenuService.TextToShortCut(Text: string): Integer;
begin Result := FMX.Helpers.Linux.TextToShortCut(Text); end;

procedure TWaylandMenuService.CreateOSMenu(AForm: TCommonCustomForm; const AMenu: IItemsContainer);
var Model: TMainMenu; View: TFMXWaylandMainMenuView;
begin
  if (FUpdating > 0) or (AMenu = nil) or not (AMenu.GetObject is TMainMenu) or (AForm = nil) then Exit;
  Model := TMainMenu(AMenu.GetObject);
  if [csLoading, csDestroying, csDesigning] * AForm.ComponentState <> [] then Exit;
  if csDestroying in Model.ComponentState then Exit;
  if FViews.TryGetValue(Model, View) then
  begin
    if View.FForm = AForm then begin View.RequestRebuild; View.Sync; Exit; end;
    Retire(View, True);
  end;
  View := TFMXWaylandMainMenuView.Create(nil);
  FViews.Add(Model, View);
  try View.Bind(AForm, Model);
  except View.Free; raise; end;
end;

procedure TWaylandMenuService.UpdateMenuItem(const AItem: IItemsContainer; AChange: TMenuItemChanges);
var View: TFMXWaylandMainMenuView;
begin
  if (FUpdating > 0) or (AItem = nil) then Exit;
  View := ViewOf(AItem.GetObject);
  if View <> nil then View.Sync;
end;

procedure TWaylandMenuService.DestroyMenuItem(const AItem: IItemsContainer);
var View: TFMXWaylandMainMenuView;
begin
  if (FUpdating > 0) or (AItem = nil) then Exit;
  View := ViewOf(AItem.GetObject);
  if View = nil then Exit;
  if AItem.GetObject is TMainMenu then Retire(View, False)
  else View.RequestRebuild;
end;

function TWaylandMenuService.IsMenuBarOnWindowBorder: Boolean;
begin Result := False; end;

procedure TWaylandMenuService.UpdateMenuBar;
begin Cleanup; end;

procedure InstallWaylandMenuService;
var Original: IFMXMenuService;
begin
  if GService <> nil then Exit;
  if not TPlatformServices.Current.SupportsPlatformService(IFMXMenuService, Original) then Exit;
  GServiceObject := TWaylandMenuService.Create(Original);
  GService := GServiceObject;
  TPlatformServices.Current.RemovePlatformService(IFMXMenuService);
  TPlatformServices.Current.AddPlatformService(IFMXMenuService, GService);
end;

procedure InitializeMenus;
begin
  if Assigned(GPreviousInit) then GPreviousInit;
  // Core platform services are registered after this unit's initialization in the FMUX dependency cycle.
  // Install before forms read their TMainMenu/TMenuItem fields and cache IFMXMenuService.
  InstallWaylandMenuService;
end;

function WaylandMainMenuBar(Model: TMainMenu): TMenuBar;
var View: TFMXWaylandMainMenuView;
begin
  Result := nil;
  if (GServiceObject <> nil) and GServiceObject.FViews.TryGetValue(Model, View) then Result := View.MenuBar;
end;

function HandleWaylandMenuKey(Form: TCommonCustomForm; Key: Word; KeyChar: Char; Shift: TShiftState): Boolean;
begin
  Result := (GServiceObject <> nil) and GServiceObject.KeyDown(Form, Key, KeyChar, Shift);
end;

initialization
  GPreviousInit := TProcedure(InitProc);
  InitProc := @InitializeMenus;
finalization
  if InitProc = @InitializeMenus then InitProc := @GPreviousInit;
  if TPlatformServices.Current <> nil then TPlatformServices.Current.RemovePlatformService(IFMXMenuService);
  GService := nil;
  GServiceObject := nil;
end.
