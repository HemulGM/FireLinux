program TextInputChecks;

uses
  System.SysUtils, System.Types, System.Diagnostics, FireLinux.Wayland.Platform, FireLinux.Wayland.TextInput;

procedure Check(Condition: Boolean; const Message: string);
begin if not Condition then raise Exception.Create(Message); end;

var
  Display: TWlDisplay; Window: TWlWindow; State: TWaylandTextState;
  Watch: TStopwatch; Stage, SecondCalls, Cancels: Integer; Text: string;
  Apply: TProc<TWaylandTextBatch>; Raised: Boolean;
begin
  try
    State := MakeSurrounding('A你好😀B', 5, 1);
    Check((State.Cursor = 11) and (State.Anchor = 1), 'UTF-16/UTF-8 indices');
    Check(Utf8RangeToUtf16(State.Text, 7, 4) = 2, 'Supplementary character range');
    Raised := False;
    try Utf8RangeToUtf16(State.Text, 2, 1); except on E: EArgumentException do Raised := True; end;
    Check(Raised, 'Split UTF-8 code point rejected');
    State := MakeSurrounding(StringOfChar('漢', 5000), 4999, 4998);
    Check(State.HasSurrounding and (Length(State.Text) <= 4000) and (State.Cursor <= Length(State.Text)), '4000-byte window');
    State := MakeSurrounding(StringOfChar('漢', 5000), 5000, 0);
    Check(not State.HasSurrounding, 'Oversized selection not advertised');
    Check(TextPointToOffset('甲乙' + #13#10 + '丙丁', Point(1,1)) = 5, 'Multiline offset');
    Display := TWlDisplay.Create;
    try
      Display.Connect;
      Check(Display.HasTextInput, 'Late-bound text input manager/seat');
      Window := TWlWindow.Create(Display, TWlWindowKind.Toplevel, False);
      try
        Text := 'AB'; State := MakeSurrounding(Text,1,1); State.CursorRect := Rect(10,20,11,40);
        Apply := procedure(Batch: TWaylandTextBatch)
          begin
            Inc(Stage);
            case Stage of
              1: Check(Batch.Preedit = 'ni', 'Preedit batch');
              2: begin Check((Batch.Commit = '你好😀') and (Batch.Preedit = '新'), 'Commit plus new preedit'); Text := 'A你好😀B'; State := MakeSurrounding(Text,5,5); end;
              3: begin Check((Batch.BeforeLength = 4) and (Batch.AfterLength = 1), 'Byte deletion'); Text := 'A你好界'; State := MakeSurrounding(Text,4,4); end;
              4: begin Check(Batch.Commit = '文', 'Stale serial still applies'); Text := Text + '文'; State := MakeSurrounding(Text,5,5); end;
              5: begin Check(Batch.Commit = '字', 'Matching serial resumes publication'); Text := Text + '字'; State := MakeSurrounding(Text,6,6); end;
              6: begin
                Check(Batch.Commit = '甲', 'Old control final batch');
                Text := 'Q'; State := MakeSurrounding(Text,1,1); State.CursorRect := Rect(10,20,11,40);
                Display.BeginTextInput(Window, function: TWaylandTextState begin Result := State; end,
                  procedure(NewBatch: TWaylandTextBatch)
                  begin
                    Inc(SecondCalls); Check(NewBatch.Commit = '新', 'Old response discarded on control switch');
                    Text := Text + NewBatch.Commit; State := MakeSurrounding(Text,2,2); State.CursorRect := Rect(10,20,11,40);
                  end, procedure begin Inc(Cancels); end);
              end;
            else raise Exception.Create('Unexpected batch for first control');
            end;
            State.CursorRect := Rect(10+Stage,20,11+Stage,40);
          end;
        Display.BeginTextInput(Window, function: TWaylandTextState begin Result := State; end,
          Apply, procedure begin Inc(Cancels); end);
        Watch := TStopwatch.StartNew;
        while (SecondCalls = 0) and (Watch.ElapsedMilliseconds < 5000) do Display.ProcessEvents(20);
        for var I := 1 to 10 do Display.ProcessEvents(10);
        Check((Stage = 6) and (SecondCalls = 1) and (Text = 'Q新') and (Cancels >= 2), 'Focus switch and leave lifecycle');
        Display.EndTextInput(Window);
      finally Window.Free; end;
    finally Display.Free; end;
    Writeln('UTF-8, IME batches, stale serials and focus checks passed');
  except on E: Exception do begin Writeln(ErrOutput,E.ClassName + ': ' + E.Message); Halt(1); end; end;
end.
