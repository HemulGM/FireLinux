program FMXFileDialogChecks;

uses
  System.StartUpCopy, System.SysUtils, System.Classes, System.IOUtils, System.UITypes,
  Posix.Stdlib, FMX.Forms, FMX.Types, FMX.Controls, FMX.ListBox, FMX.Edit, FMX.Dialogs, FMUX.Api,
  FMXWayland.Dialogs, FMXWayland.DialogTypes, FMXWayland.FileDialog;

type
  TDialogDriver = class
  private
    FBusy: Boolean;
  public
    Action: TProc<TFMXWaylandFileDialog>;
    NestedResult: TModalResult;
    NestedInput: string;
    Failure: string;
    Calls: Integer;
    procedure Tick(Sender: TObject);
  end;

procedure Check(Condition: Boolean; const Message: string);
begin if not Condition then raise Exception.Create(Message); end;

procedure SetEdit(Object_: TFmxObject; const Value: string);
var I: Integer;
begin
  if Object_ is TEdit then TEdit(Object_).Text := Value;
  for I := 0 to Object_.ChildrenCount - 1 do SetEdit(Object_.Children[I], Value);
end;

procedure TDialogDriver.Tick(Sender: TObject);
var I: Integer; Form: TCommonCustomForm;
begin
  for I := 0 to Screen.FormCount - 1 do
  begin
    Form := Screen.Forms[I];
    if not Form.Visible then Continue;
    if FBusy then
    begin
      if not (Form is TFMXWaylandFileDialog) and (NestedResult <> mrNone) then
      begin
        if NestedInput <> '' then SetEdit(Form, NestedInput);
        Form.ModalResult := NestedResult;
      end;
    end
    else if Form is TFMXWaylandFileDialog then
    begin
      Inc(Calls);
      FBusy := True;
      try
        try Action(TFMXWaylandFileDialog(Form));
        except on E: Exception do begin Failure := E.Message; Form.ModalResult := mrCancel; end; end;
      finally FBusy := False; end;
      Exit;
    end;
  end;
end;

function FindItem(Dialog: TFMXWaylandFileDialog; const Name: string): TListBoxItem;
var I: Integer;
begin
  Result := nil;
  for I := 0 to Dialog.FileList.Count - 1 do
    if (Dialog.FileList.ListItems[I].Text = Name) or (Dialog.FileList.ListItems[I].Text = Name + '/') then
      Exit(Dialog.FileList.ListItems[I]);
end;

procedure SelectItem(Dialog: TFMXWaylandFileDialog; const Name: string);
var Item: TListBoxItem;
begin
  Item := FindItem(Dialog, Name);
  Check(Item <> nil, 'Missing item: ' + Name);
  Item.IsSelected := True;
end;

procedure RunChecks(const Root: string; Driver: TDialogDriver);
var
  Backend: IFMXWaylandDialogBackend;
  Request: TWaylandFileDialogRequest;
  Files: TArray<string>; Index: Integer; Accepted: Boolean;
  Key: Word; KeyChar: WideChar;
begin
  Backend := TFMXWaylandDialogBackend.Create;
  Request := Default(TWaylandFileDialogRequest);
  Request.Title := 'FMX File Dialog'; Request.InitialFolder := Root;
  Request.Filters := [Default(TWaylandFileFilter), Default(TWaylandFileFilter)];
  Request.Filters[0].Name := 'Текст'; Request.Filters[0].Patterns := ['*.txt'];
  Request.Filters[1].Name := 'Все файлы'; Request.Filters[1].Patterns := ['*.*'];
  Request.FilterIndex := 1; Index := 1;
  Driver.Action := procedure(Dialog: TFMXWaylandFileDialog)
    begin
      Check(FindItem(Dialog, 'other.bin') = nil, 'Initial filter');
      Check(FindItem(Dialog, '.hidden.txt') = nil, 'Hidden files default');
      Check(Dialog.FileList.Height > 200, 'List layout height');
      Dialog.ClientWidth := 620; Dialog.ClientHeight := 440;
      Check(Dialog.FileList.Width > 500, 'Resize list alignment');
      SelectItem(Dialog, 'тест файл.txt');
      Dialog.AcceptClick(nil);
    end;
  Check(Backend.FileDialog(Request, Files, Index) and (Files[0] = Root + '/тест файл.txt'), 'FMX open');
  Request.Multiple := True;
  Driver.Action := procedure(Dialog: TFMXWaylandFileDialog)
    begin SelectItem(Dialog, 'тест файл.txt'); SelectItem(Dialog, 'second.txt'); Dialog.AcceptClick(nil); end;
  Check(Backend.FileDialog(Request, Files, Index) and (Length(Files) = 2), 'FMX multiple');
  Request.Multiple := False;
  Driver.Action := procedure(Dialog: TFMXWaylandFileDialog)
    begin
      Dialog.FilterCombo.ItemIndex := 1;
      Check(FindItem(Dialog, 'other.bin') <> nil, 'Changed filter');
      Dialog.HiddenCheck.IsChecked := True;
      Check(FindItem(Dialog, '.hidden.txt') <> nil, 'Show hidden');
      SelectItem(Dialog, 'other.bin'); Dialog.AcceptClick(nil);
    end;
  Check(Backend.FileDialog(Request, Files, Index) and (Index = 2) and (Files[0] = Root + '/other.bin'), 'Filter result');
  Driver.Action := procedure(Dialog: TFMXWaylandFileDialog)
    begin
      Dialog.LocationEdit.Text := Root + '/подпапка'; Dialog.GoClick(nil);
      Check(Dialog.CurrentFolder = Root + '/подпапка', 'Location navigation');
      Dialog.UpClick(nil); Check(Dialog.CurrentFolder = Root, 'Parent navigation');
      Dialog.LocationEdit.Text := Root + '/missing-folder'; Dialog.GoClick(nil);
      Check(Dialog.CurrentFolder = Root, 'Bad folder preserves listing');
      Dialog.NameEdit.Text := 'missing.txt'; Dialog.AcceptClick(nil);
      Check(Dialog.ModalResult = mrNone, 'Nonexistent file rejected');
      Dialog.NameEdit.Text := 'тест файл.txt'; Dialog.AcceptClick(nil);
    end;
  Check(Backend.FileDialog(Request, Files, Index) and (Files[0] = Root + '/тест файл.txt'), 'Navigation and typed name');
  Request.Kind := TWaylandFileDialogKind.SelectFolder;
  Driver.Action := procedure(Dialog: TFMXWaylandFileDialog)
    begin
      Check(not Dialog.NameRow.Visible, 'Folder hides file input');
      Check(FindItem(Dialog, 'second.txt') = nil, 'Folder list excludes files');
      SelectItem(Dialog, 'подпапка'); Dialog.AcceptClick(nil);
    end;
  Check(Backend.FileDialog(Request, Files, Index) and (Files[0] = Root + '/подпапка'), 'Selected folder');
  Driver.Action := procedure(Dialog: TFMXWaylandFileDialog) begin Dialog.AcceptClick(nil); end;
  Check(Backend.FileDialog(Request, Files, Index) and (Files[0] = Root), 'Current folder');
  Driver.NestedResult := mrOK; Driver.NestedInput := 'созданная папка';
  Driver.Action := procedure(Dialog: TFMXWaylandFileDialog)
    begin
      Dialog.NewFolderClick(nil);
      Check(Dialog.CurrentFolder = Root + '/созданная папка', 'New folder navigation');
      Dialog.AcceptClick(nil);
    end;
  Check(Backend.FileDialog(Request, Files, Index) and DirectoryExists(Root + '/созданная папка'), 'Create folder');
  Driver.NestedInput := ''; Request.Kind := TWaylandFileDialogKind.SaveFile;
  Request.InitialFile := 'новый.txt'; Request.ConfirmOverwrite := True;
  Driver.Action := procedure(Dialog: TFMXWaylandFileDialog) begin Dialog.AcceptClick(nil); end;
  Check(Backend.FileDialog(Request, Files, Index) and (Files[0] = Root + '/новый.txt') and
    not FileExists(Files[0]), 'Save selects path without writing');
  Request.InitialFile := 'second.txt'; Driver.NestedResult := mrNo;
  Driver.Action := procedure(Dialog: TFMXWaylandFileDialog)
    begin
      Dialog.AcceptClick(nil); Check(Dialog.ModalResult = mrNone, 'Overwrite declined');
      Dialog.NameEdit.Text := 'replacement.txt'; Dialog.AcceptClick(nil);
    end;
  Check(Backend.FileDialog(Request, Files, Index) and (Files[0] = Root + '/replacement.txt'), 'Overwrite declined then new name');
  Driver.NestedResult := mrYes;
  Driver.Action := procedure(Dialog: TFMXWaylandFileDialog) begin Dialog.AcceptClick(nil); end;
  Check(Backend.FileDialog(Request, Files, Index) and (Files[0] = Root + '/second.txt'), 'Overwrite accepted');
  Driver.NestedResult := mrNone; Index := 2;
  Driver.Action := procedure(Dialog: TFMXWaylandFileDialog)
    begin Key := vkEscape; KeyChar := #0; Dialog.DialogKeyDown(nil, Key, KeyChar, []); end;
  Accepted := Backend.FileDialog(Request, Files, Index);
  Check(not Accepted and (Files = nil) and (Index = 2), 'Cancel preserves filter and returns no files');
  Check(Driver.Failure = '', Driver.Failure);
  Writeln('Pure FMX file dialog checks passed');
end;

procedure FallbackChecks(const Root: string; Driver: TDialogDriver; FolderMode: Boolean);
var Open: TOpenDialog; Save: TSaveDialog; Directory: string;
begin
  SetWaylandDialogBackend(nil);
  if FolderMode then
  begin
    Driver.Action := procedure(Dialog: TFMXWaylandFileDialog) begin Dialog.AcceptClick(nil); end;
    Directory := '';
    Check(SelectDirectory('Folder fallback', Root, Directory) and (Directory = Root), 'Old portal folder fallback');
  end
  else
  begin
    Open := TOpenDialog.Create(nil);
    try
      Open.InitialDir := Root;
      Driver.Action := procedure(Dialog: TFMXWaylandFileDialog)
        begin SelectItem(Dialog, 'тест файл.txt'); Dialog.AcceptClick(nil); end;
      Check(Open.Execute and (Open.FileName = Root + '/тест файл.txt'), 'Missing portal fallback through TOpenDialog');
    finally Open.Free; end;
    Save := TSaveDialog.Create(nil);
    try
      Save.InitialDir := Root; Save.FileName := 'fallback-save.txt';
      Driver.Action := procedure(Dialog: TFMXWaylandFileDialog) begin Dialog.AcceptClick(nil); end;
      Check(Save.Execute and (Save.FileName = Root + '/fallback-save.txt'), 'Missing portal save fallback');
    finally Save.Free; end;
  end;
  Check(Driver.Calls > 0, 'Fallback form was not shown');
  Check(Driver.Failure = '', Driver.Failure);
  Writeln('Automatic FMX fallback checks passed');
end;

var
  Root: string; Id: TGUID; Driver: TDialogDriver; Timer: TTimer;
  OldAddress: UTF8String;
begin
  try
    Application.Initialize;
    CreateGUID(Id); Root := TPath.Combine(TPath.GetTempPath, 'fmx-file-dialog-' + GUIDToString(Id));
    TDirectory.CreateDirectory(Root + '/подпапка');
    TFile.WriteAllText(Root + '/тест файл.txt', 'test', TEncoding.UTF8);
    TFile.WriteAllText(Root + '/second.txt', 'test', TEncoding.UTF8);
    TFile.WriteAllText(Root + '/other.bin', 'test', TEncoding.UTF8);
    TFile.WriteAllText(Root + '/.hidden.txt', 'test', TEncoding.UTF8);
    Driver := TDialogDriver.Create; Timer := TTimer.Create(nil);
    try
      Timer.Interval := 200; Timer.OnTimer := Driver.Tick; Timer.Enabled := True;
      if ParamStr(1) = '--fallback-version2' then FallbackChecks(Root, Driver, True)
      else if ParamStr(1) = '--fallback-missing' then FallbackChecks(Root, Driver, False)
      else if ParamStr(1) = '--fallback-no-bus' then
      begin
        OldAddress := UTF8String(GetEnvironmentVariable('DBUS_SESSION_BUS_ADDRESS'));
        setenv('DBUS_SESSION_BUS_ADDRESS', 'unix:path=/tmp/fmxwayland-nonexistent-bus', 1);
        try FallbackChecks(Root, Driver, False);
        finally
          if OldAddress <> '' then setenv('DBUS_SESSION_BUS_ADDRESS', PAnsiChar(OldAddress), 1)
          else unsetenv('DBUS_SESSION_BUS_ADDRESS');
        end;
      end
      else RunChecks(Root, Driver);
    finally Timer.Free; Driver.Free; TDirectory.Delete(Root, True); end;
  except on E: Exception do begin Writeln(ErrOutput, E.ClassName + ': ' + E.Message); Halt(1); end; end;
end.
