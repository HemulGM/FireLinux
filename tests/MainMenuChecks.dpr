program MainMenuChecks;

uses
  System.StartUpCopy, System.SysUtils, System.Types, System.Classes, System.UITypes,
  System.Diagnostics, FMX.Forms, FMX.Types, FMX.Menus, FMX.Platform, FMUX.Api,
  FMXWayland.Menus, FMXWayland.Platform,
  HelloMain in '..\samples\Hello\HelloMain.pas', HelloWindow in '..\samples\Hello\HelloWindow.pas';

type
  TChecks = class
    Form: THelloForm;
    Bar: TMenuBar;
    Timer: TTimer;
    Root, Nested: TMenuItem;
    Added: TMenuItem;
    Stage, Clicks, ActionCalls: Integer;
    PopupMapped, NestedMapped: Boolean;
    KeyboardMoved, EscapeHandled, ActivationMapped: Boolean;
    procedure CommandClick(Sender: TObject);
    procedure ActionExecute(Sender: TObject);
    procedure PopupTick(Sender: TObject);
  end;

procedure Check(Condition: Boolean; const Message: string);
begin if not Condition then raise Exception.Create(Message); end;

procedure Pump(Delay: Integer = 180);
var Watch: TStopwatch;
begin
  Watch := TStopwatch.StartNew;
  repeat Application.ProcessMessages; TThread.Sleep(2); until Watch.ElapsedMilliseconds >= Delay;
end;

procedure Invoke(Item: TMenuItem);
begin
  Check(Assigned(Item.OnClick), 'Proxy click handler');
  Item.OnClick(Item); Pump;
end;

procedure TChecks.CommandClick(Sender: TObject);
begin Inc(Clicks); end;

procedure TChecks.ActionExecute(Sender: TObject);
begin Inc(ActionCalls); Form.MenuTicksExecute(Sender); end;

function PopupCount: Integer;
var Window: TWlWindow;
begin
  Result := 0;
  for Window in WlDisplay.Windows do
    if (Window.Kind = TWlWindowKind.Popup) and Window.Mapped then Inc(Result);
end;

procedure TChecks.PopupTick(Sender: TObject);
var ParentView: IMenuView;
begin
  case Stage of
    0: begin
      PopupMapped := PopupCount > 0;
      HandleWaylandMenuKey(Form, vkEnd, #0, []);
      KeyboardMoved := Root.View.ChildView.Selected.Text = Form.MenuTicks.Text;
      HandleWaylandMenuKey(Form, vkHome, #0, []);
      KeyboardMoved := KeyboardMoved and (Root.View.ChildView.Selected = Nested);
      Stage := 1;
      HandleWaylandMenuKey(Form, vkRight, #0, []); // The same timer ends the nested loop on its next tick.
      Stage := 2;
      // Add and delete source items while the outer popup still owns its projected children.
      Added := TMenuItem.Create(Form); Added.Text := 'Добавлен в открытом меню'; Added.Parent := Form.MenuView;
      FreeAndNil(Form.MenuTicks);
      ParentView := Root.View.ChildView;
      if ParentView <> nil then ParentView.Loop := False;
    end;
    1: begin
      NestedMapped := PopupCount >= 2;
      EscapeHandled := HandleWaylandMenuKey(Form, vkEscape, #0, []);
    end;
    10: begin
      ActivationMapped := PopupCount > 0;
      HandleWaylandMenuKey(Form, vkEscape, #0, []);
      Stage := 11;
    end;
    20: begin
      ActivationMapped := PopupCount > 0;
      HandleWaylandMenuKey(Form, Ord('O'), #0, [ssCtrl]);
      Stage := 21;
    end;
    30: begin
      Stage := 31;
      FreeAndNil(Form.MainMenu);
    end;
  end;
end;

procedure CompareTree(Source: IItemsContainer; Clone: IItemsContainer);
var I: Integer; Original, View: TMenuItem; Native: INativeControl;
begin
  Check(Source.GetItemsCount = Clone.GetItemsCount, 'Projected item count');
  for I := 0 to Source.GetItemsCount - 1 do
  begin
    Original := TMenuItem(Source.GetItem(I)); View := TMenuItem(Clone.GetItem(I));
    Check((Original <> View) and (Original.Text = View.Text), 'Source identity and projected caption');
    Check(Supports(Original, INativeControl, Native) and (Native.Handle <> 0), 'Backend item handle');
    CompareTree(Original, View);
  end;
end;

var Test: TChecks; Clone, Dynamic: TMenuItem; Key: Word; KeyChar: Char;
  Service: IFMXMenuService; Shift: TShiftState; Main: TMainMenu;
begin
  try
    Application.Initialize;
    Test := TChecks.Create;
    try
      Test.Form := THelloForm.Create(nil);
      try
        Test.Form.Show; Pump;
        Test.Bar := WaylandMainMenuBar(Test.Form.MainMenu);
        Check((Test.Bar <> nil) and (Test.Bar.ItemsCount = 4), 'Standard TMainMenu creates a visible bar');
        Check(Test.Bar.Scene.GetObject = Test.Form, 'Bar belongs to the correct FMX scene');
        Check(Test.Bar.Visible and (Test.Bar.Width >= Test.Form.ClientWidth - 16) and
          (Test.Bar.Height >= 24) and (Test.Bar.Items[0].Width > 0), 'Menu row is visible and aligned across the form');
        CompareTree(Test.Form.MainMenu, Test.Bar);
        Check(Test.Form.MainMenu.ItemsCount = 4, 'Model retains its complete tree');
        Check(Test.Form.Header.Position.Y >= 32, 'Align-based layout reserves the menu row');
        Check(not Test.Bar.Items[2].Items[4].Enabled and not Test.Bar.Items[2].Items[5].Visible, 'Disabled and hidden items');
        Test.Form.MenuDisabled.Text := 'Динамическое имя 你好😀';
        Check(Test.Bar.Items[2].Items[4].Text = Test.Form.MenuDisabled.Text, 'Immediate caption update');
        Test.Form.MenuDisabled.Enabled := True;
        Test.Form.MenuHidden.Visible := True;
        Check(Test.Bar.Items[2].Items[4].Enabled and Test.Bar.Items[2].Items[5].Visible, 'Immediate enabled/visible update');
        Test.Form.MenuDisabled.OnClick := Test.CommandClick;
        Invoke(Test.Bar.Items[2].Items[4]); Check(Test.Clicks = 1, 'One original click');
        Test.Form.MenuDisabled.Enabled := False;
        Invoke(Test.Bar.Items[2].Items[4]); Check(Test.Clicks = 1, 'Disabled item cannot execute');
        Test.Form.MenuTicksAction.OnExecute := Test.ActionExecute;
        Clone := Test.Bar.Items[1].Items[2];
        Invoke(Clone);
        Check((Test.ActionCalls = 1) and not Test.Form.MenuTicksAction.Checked and not Clone.IsChecked and
          not Test.Form.AnimTimer.Enabled, 'Action and AutoCheck execute once');
        Key := Ord('T'); KeyChar := #0; Test.Form.KeyDown(Key, KeyChar, [ssCtrl]); Pump;
        Check((Test.ActionCalls = 2) and Test.Form.MenuTicksAction.Checked and Test.Form.AnimTimer.Enabled,
          'Ctrl+T executes the original menu action');
        Invoke(Test.Bar.Items[2].Items[1]);
        Check(Test.Form.MenuModeMove.IsChecked and not Test.Form.MenuModeCopy.IsChecked and
          Test.Bar.Items[2].Items[1].IsChecked and not Test.Bar.Items[2].Items[0].IsChecked, 'Radio group state');
        TPlatformServices.Current.SupportsPlatformService(IFMXMenuService, Service);
        Test.Form.MenuDisabled.ShortCut := Service.TextToShortCut('Ctrl+Shift+K');
        Service.ShortCutToKey(Test.Form.MenuDisabled.ShortCut, Key, Shift);
        Check((Key = Ord('K')) and (Shift = [ssCtrl, ssShift]) and
          (Test.Bar.Items[2].Items[4].ShortCut = Test.Form.MenuDisabled.ShortCut), 'Shortcut conversion and update');
        Dynamic := TMenuItem.Create(Test.Form); Dynamic.Text := 'Runtime'; Dynamic.Parent := Test.Form.MenuOptions;
        Pump;
        Check(Test.Bar.Items[2].ItemsCount = 7, 'Dynamic addition');
        Dynamic.Free; Pump;
        Check(Test.Bar.Items[2].ItemsCount = 6, 'Dynamic deletion');
        CompareTree(Test.Form.MainMenu, Test.Bar);
        // Real FMX Popup -> native xdg_popup surfaces, with nesting and a source change inside the menu loop.
        Test.Root := Test.Bar.Items[1]; Test.Nested := Test.Root.Items[0];
        Test.Timer := TTimer.Create(nil);
        try
          Test.Timer.Interval := 120; Test.Timer.OnTimer := Test.PopupTick;
          Test.Root.Popup;
          Test.Timer.Enabled := False;
        finally Test.Timer.Free; end;
        Pump;
        Check((Test.Stage = 2) and Test.PopupMapped and Test.NestedMapped, 'Mapped nested Wayland menu popups');
        Check(Test.KeyboardMoved and Test.EscapeHandled, 'Keyboard selection and nested Escape');
        Check(Test.Bar.Items[1].ItemsCount = 3, 'Deferred rebuild after the popup loop');
        CompareTree(Test.Form.MainMenu, Test.Bar);
        Test.Timer := TTimer.Create(nil);
        try
          Test.Stage := 10; Test.Timer.Interval := 120; Test.Timer.OnTimer := Test.PopupTick;
          Check(HandleWaylandMenuKey(Test.Form, vkF10, #0, []), 'F10 enters the main menu');
          Test.Timer.Enabled := False;
          Check((Test.Stage = 11) and Test.ActivationMapped, 'F10 opens a native popup');
          Test.Form.MenuFile.Text := '&File';
          Test.Stage := 10; Test.ActivationMapped := False; Test.Timer.Enabled := True;
          Check(HandleWaylandMenuKey(Test.Form, Ord('F'), 'f', [ssAlt]), 'Alt mnemonic enters the menu');
          Test.Timer.Enabled := False;
          Check((Test.Stage = 11) and Test.ActivationMapped, 'Alt mnemonic opens a native popup');
          Test.Form.MenuOpen.OnClick := Test.CommandClick;
          Test.Stage := 20; Test.ActivationMapped := False; Test.Timer.Enabled := True;
          HandleWaylandMenuKey(Test.Form, vkF10, #0, []);
          Test.Timer.Enabled := False;
          Check((Test.Stage = 21) and Test.ActivationMapped, 'Shortcut closes an open menu');
        finally Test.Timer.Free; end;
        Pump;
        Check(Test.Clicks = 2, 'Command shortcut in the popup executes once');
        Main := Test.Form.MainMenu;
        Test.Root := Test.Bar.Items[0]; Test.Stage := 30;
        Test.Timer := TTimer.Create(nil);
        try
          Test.Timer.Interval := 120; Test.Timer.OnTimer := Test.PopupTick;
          Test.Root.Popup;
          Test.Timer.Enabled := False;
        finally Test.Timer.Free; end;
        Pump;
        Check(Test.Stage = 31, 'Destroying the model inside an open popup unwinds safely');
        Check(WaylandMainMenuBar(Main) = nil, 'Destroyed main menu releases its view');
        Check(Test.Form.Header.Position.Y = 0, 'Destroying the menu releases the layout row');
        Main := TMainMenu.Create(Test.Form); Main.Parent := Test.Form;
        Dynamic := TMenuItem.Create(Main); Dynamic.Text := 'Повторное создание'; Dynamic.Parent := Main;
        Main.RecreateOSMenu; Pump;
        Check(WaylandMainMenuBar(Main) <> nil, 'Main menu can be recreated');
        Main.Free;
        Writeln('TMainMenu projection, state, actions, shortcuts, nested xdg_popup and lifetime checks passed (FMX)');
      finally Test.Form.Free; end;
    finally Test.Free; end;
  except on E: Exception do begin Writeln(ErrOutput, E.ClassName + ': ' + E.Message); Halt(1); end; end;
end.
