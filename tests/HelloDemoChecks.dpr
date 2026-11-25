program HelloDemoChecks;

uses
  System.StartUpCopy, System.SysUtils, System.Classes, System.UITypes, System.Math,
  FMX.Forms, FMX.Dialogs, FMX.Objects, FMUX.Api,
  FMXWayland.Dialogs, FMXWayland.DialogTypes,
  HelloMain in '..\samples\Hello\HelloMain.pas',
  HelloWindow in '..\samples\Hello\HelloWindow.pas';

type
  TDemoBackend = class(TFMXWaylandDialogBackend)
  public
    Path: string;
    Accept: Boolean;
    Kind: TWaylandFileDialogKind;
    function FileDialog(const Request: TWaylandFileDialogRequest; out Files: TArray<string>;
      var FilterIndex: Integer): Boolean; override;
    function MessageDialog(const Message: string; DialogType: TMsgDlgType; Buttons: TMsgDlgButtons;
      DefaultButton: TMsgDlgBtn): TModalResult; override;
    function InputQuery(const Caption: string; const Prompts: TArray<string>;
      var Values: TArray<string>): Boolean; override;
  end;

procedure Check(Condition: Boolean; const Message: string);
begin if not Condition then raise Exception.Create(Message); end;

function TDemoBackend.FileDialog(const Request: TWaylandFileDialogRequest; out Files: TArray<string>;
  var FilterIndex: Integer): Boolean;
begin Kind := Request.Kind; Files := [Path]; Result := Accept; end;

function TDemoBackend.MessageDialog(const Message: string; DialogType: TMsgDlgType;
  Buttons: TMsgDlgButtons; DefaultButton: TMsgDlgBtn): TModalResult;
begin Result := mrYes; end;

function TDemoBackend.InputQuery(const Caption: string; const Prompts: TArray<string>;
  var Values: TArray<string>): Boolean;
begin Values[0] := 'Ответ ✓'; Result := Accept; end;

var
  Form: THelloForm; Mock: TDemoBackend; Backend, Previous: IFMXWaylandDialogBackend;
begin
  try
    Check(ParamStr(1) <> '', 'Pass the landscape.png fixture path');
    Application.Initialize;
    Form := THelloForm.Create(nil);
    try
      Form.Show;
      Application.ProcessMessages;
      // Initial configure is asynchronous; settle it before testing a client-requested resize.
      for var I := 1 to 20 do begin Application.ProcessMessages; TThread.Sleep(10); end;
      Check((Form.DemoTabs.TabCount = 6) and (Form.PngImage.Bitmap.Width = 256) and
        (Form.JpegImage.Bitmap.Width = 256), 'Streamed tabs and image formats');
      Form.ClickButton.OnClick(Form.ClickButton);
      Check(Form.CountLabel.Text.EndsWith('1'), 'Streamed button binding');
      Form.EditBox.Text := 'Unicode ✓'; Form.EditBox.OnChangeTracking(Form.EditBox);
      Check(Form.EchoLabel.Text.EndsWith('Unicode ✓'), 'Streamed edit binding');
      Form.ProgressSlider.Value := 73;
      Check(SameValue(Form.ProgressBar.Value, 73), 'Streamed slider binding');
      Form.DemoTabs.ActiveTab := Form.ImagesTab;
      Check(Form.PulseAnimation.Enabled, 'Animation starts on image tab');
      Form.ImageOpacity.Value := 0.5;
      Check(SameValue(Form.PngImage.Opacity, 0.5) and SameValue(Form.JpegImage.Opacity, 0.5), 'Image opacity binding');
      Form.DemoTabs.ActiveTab := Form.DialogsTab;
      Check(not Form.PulseAnimation.Enabled, 'Hidden tab stops animation');
      Previous := GetWaylandDialogBackend;
      Form.BackendCombo.ItemIndex := 1;
      Check(GetWaylandDialogBackend <> Previous, 'Backend selector binding');
      Mock := TDemoBackend.Create; Backend := Mock; Mock.Accept := True; Mock.Path := ParamStr(1);
      SetWaylandDialogBackend(Backend);
      Form.OpenButton.OnClick(Form.OpenButton);
      Check((Mock.Kind = TWaylandFileDialogKind.OpenFile) and Form.DialogResults.Text.Contains(Mock.Path), 'Open demo binding');
      Form.SaveButton.OnClick(Form.SaveButton);
      Check((Mock.Kind = TWaylandFileDialogKind.SaveFile) and Form.DialogResults.Text.Contains(Mock.Path), 'Save demo binding');
      Form.FolderButton.OnClick(Form.FolderButton);
      Check(Mock.Kind = TWaylandFileDialogKind.SelectFolder, 'Folder demo binding');
      Form.MessageButton.OnClick(Form.MessageButton);
      Check(Form.DialogResults.Text.Contains(IntToStr(mrYes)), 'Message demo binding');
      Form.InputButton.OnClick(Form.InputButton);
      Check(Form.DialogResults.Text.Contains('Ответ ✓'), 'Input demo binding');
      Mock.Accept := False; Form.OpenButton.OnClick(Form.OpenButton);
      Check(Form.DialogResults.Text.Contains('отменено'), 'Demo cancellation');
      Mock.Accept := True; Form.ImageButton.OnClick(Form.ImageButton);
      Check(Form.ImageStatusLabel.Text.Contains('256'), 'Image loading demo binding');
      Form.ClientWidth := 760; Form.ClientHeight := 560;
      Application.ProcessMessages;
      Check((Form.DemoTabs.Width <= 760) and (Form.DialogResults.Width <= Form.DemoTabs.Width), 'Layout after resizing');
      Form.BackendCombo.ItemIndex := 0;
      Writeln('Demo FMX resources, event bindings, images, dialog modes and resize checks passed');
    finally Form.Free; end;
  except on E: Exception do begin Writeln(ErrOutput, E.ClassName + ': ' + E.Message); Halt(1); end; end;
end.
