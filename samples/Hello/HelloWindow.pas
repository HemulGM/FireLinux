unit HelloWindow;

interface

uses
  System.Classes, System.SysUtils, System.Types, System.UITypes, FMX.Types, FMX.Controls, FMX.Forms,
  FMX.Layouts, FMX.StdCtrls, FMX.Controls.Presentation;

type
  TDemoWindow = class(TForm)
    Content: TLayout;
    DescriptionLabel: TLabel;
    Buttons: TLayout;
    CloseButton: TButton;
    OKButton: TButton;
    CancelButton: TButton;
    SelfCloseTimer: TTimer;
    procedure CloseButtonClick(Sender: TObject);
    procedure WindowClose(Sender: TObject; var Action: TCloseAction);
    procedure WindowShow(Sender: TObject);
    procedure SelfCloseTimerTimer(Sender: TObject);
  private
    FModal: Boolean;
    FVerbose: Boolean;
  public
    procedure Configure(const Number: Integer; Modal: Boolean; const Style: TStyleBook; Verbose: Boolean = False);
  end;

implementation

{$R *.fmx}

procedure TDemoWindow.Configure(const Number: Integer; Modal: Boolean; const Style: TStyleBook; Verbose: Boolean);
begin
  FModal := Modal;
  FVerbose := Verbose;
  StyleBook := Style;
  CloseButton.Visible := not Modal;
  OKButton.Visible := Modal;
  CancelButton.Visible := Modal;
  if Modal then
  begin
    Caption := 'Modal form';
    DescriptionLabel.Text := 'Модальная форма из FMX-разметки. Выберите OK или Cancel.';
  end
  else
  begin
    Caption := Format('Second form %d', [Number]);
    DescriptionLabel.Text := Format('Независимое окно № %d. Закройте его кнопкой или через заголовок.', [Number]);
  end;
end;

procedure TDemoWindow.CloseButtonClick(Sender: TObject);
begin Close; end;

procedure TDemoWindow.WindowShow(Sender: TObject);
var Button: TButton; Point: TPointF;
begin
  if not FVerbose then Exit;
  for Button in [CloseButton, OKButton, CancelButton] do
  begin
    Point := Button.LocalToAbsolute(PointF(Button.Width / 2, Button.Height / 2));
    Writeln(Format('[hello] layout %s %.0f %.0f', [Button.Name, Point.X, Point.Y]));
  end;
  Flush(Output);
end;

procedure TDemoWindow.WindowClose(Sender: TObject; var Action: TCloseAction);
begin
  if not FModal then
  begin
    Action := TCloseAction.caFree;
    if FVerbose then begin Writeln('[hello] second form closed'); Flush(Output); end;
  end;
end;

procedure TDemoWindow.SelfCloseTimerTimer(Sender: TObject);
begin SelfCloseTimer.Enabled := False; ModalResult := mrRetry; end;

end.
