{ FireLinux: text-input-v3 transport and UTF-8 state. MIT license. }
unit FireLinux.Wayland.TextInput;

interface

uses
  System.SysUtils, System.Types, FireLinux.Wayland.Protocol.Wayland,
  FireLinux.Wayland.Protocol.TextInputUnstableV3;

type
  TWaylandTextState = record
    Enabled, HasSurrounding: Boolean;
    Text: UTF8String;
    Cursor, Anchor: Integer; // UTF-8 bytes, never UTF-16 indices.
    CursorRect: TRect; // Logical surface coordinates, not buffer pixels.
    Hint, Purpose: Cardinal;
  end;

  TWaylandTextBatch = record
    Preedit, Commit: string;
    CursorBegin, CursorEnd: Integer;
    BeforeLength, AfterLength: Cardinal;
  end;

  TWaylandTextInput = class
  private
    FProxy: Pzwp_text_input_v3;
    FSurface, FEntered: Pwl_surface;
    FGetState: TFunc<TWaylandTextState>;
    FApply: TProc<TWaylandTextBatch>;
    FCancel: TProc;
    FState: TWaylandTextState;
    FPending: TWaylandTextBatch;
    FEnabled, FApplying, FWaitForDone: Boolean;
    FSerial, FEnableSerial, FGeneration: Cardinal;
    procedure CommitState;
    procedure ResetPending;
    procedure CancelComposition;
    procedure Enter(Surface: Pwl_surface);
    procedure Leave(Surface: Pwl_surface);
    procedure Done(Serial: Cardinal);
  public
    constructor Create(Manager: Pzwp_text_input_manager_v3; Seat: Pwl_seat);
    destructor Destroy; override;
    procedure SetTarget(Surface: Pwl_surface; const GetState: TFunc<TWaylandTextState>; const Apply: TProc<TWaylandTextBatch>; const Cancel: TProc);
    procedure ClearTarget(Notify: Boolean = True);
    procedure Sync(Cause: Cardinal = ZWP_TEXT_INPUT_V3_CHANGE_CAUSE_OTHER);
    property TargetSurface: Pwl_surface read FSurface;
  end;

function MakeSurrounding(const Text: string; Cursor, Anchor: Integer): TWaylandTextState;

function TextPointToOffset(const Text: string; const Point: TPoint): Integer;

function Utf8RangeToUtf16(const Text: UTF8String; StartByte, ByteCount: Integer): Integer;

implementation

uses
  System.Math;

function TextPointToOffset(const Text: string; const Point: TPoint): Integer;
var
  I, Line: Integer;
begin
  I := 1;
  Line := 0;
  while (I <= Length(Text)) and (Line < Point.Y) do
  begin
    if Text[I] = #13 then
    begin
      Inc(Line);
      Inc(I);
      if (I <= Length(Text)) and (Text[I] = #10) then
        Inc(I);
    end
    else if Text[I] = #10 then
    begin
      Inc(Line);
      Inc(I);
    end
    else
      Inc(I);
  end;
  Result := I - 1;
  I := 0;
  while (Result < Length(Text)) and (I < Max(0, Point.X)) and not CharInSet(Text[Result + 1], [#10, #13]) do
  begin
    Inc(Result);
    Inc(I);
  end;
end;

function Boundary(const Text: UTF8String; Offset: Integer): Boolean;
begin
  Result := (Offset >= 0) and (Offset <= Length(Text));
  if Result and (Offset < Length(Text)) then
    Result := (Byte(Text[Offset + 1]) and $C0) <> $80;
end;

function Utf8RangeToUtf16(const Text: UTF8String; StartByte, ByteCount: Integer): Integer;
begin
  if (ByteCount < 0) or (StartByte < 0) or (StartByte > Length(Text)) or
    (ByteCount > Length(Text) - StartByte) or not Boundary(Text, StartByte) or
    not Boundary(Text, StartByte + ByteCount) then
    raise EArgumentException.Create('IME range is not on UTF-8 character boundaries');
  Result := Length(UTF8ToString(Copy(Text, StartByte + 1, ByteCount)));
end;

function MakeSurrounding(const Text: string; Cursor, Anchor: Integer): TWaylandTextState;
var
  First, Last, C, A: Integer;
  Bytes: UTF8String;
begin
  Result := Default(TWaylandTextState);
  Result.Enabled := True;
  Cursor := EnsureRange(Cursor, 0, Length(Text));
  Anchor := EnsureRange(Anchor, 0, Length(Text));
  // A UTF-16 selection must not divide a surrogate pair.
  if (Cursor > 0) and (Cursor < Length(Text)) and (Ord(Text[Cursor]) >= $D800) and (Ord(Text[Cursor]) <= $DBFF) and
    (Ord(Text[Cursor + 1]) >= $DC00) and (Ord(Text[Cursor + 1]) <= $DFFF) then
    Dec(Cursor);
  if (Anchor > 0) and (Anchor < Length(Text)) and (Ord(Text[Anchor]) >= $D800) and (Ord(Text[Anchor]) <= $DBFF) and
    (Ord(Text[Anchor + 1]) >= $DC00) and (Ord(Text[Anchor + 1]) <= $DFFF) then
    Dec(Anchor);
  Bytes := UTF8String(Text);
  C := Length(UTF8String(Copy(Text, 1, Cursor)));
  A := Length(UTF8String(Copy(Text, 1, Anchor)));
  if Abs(C - A) > 4000 then
    Exit; // Cannot describe the complete selection within the protocol limit.
  First := Max(0, Min(C, A) - (4000 - Abs(C - A)) div 2);
  while not Boundary(Bytes, First) do
    Inc(First);
  Last := Min(Length(Bytes), First + 4000);
  while not Boundary(Bytes, Last) do
    Dec(Last);
  Result.HasSurrounding := True;
  Result.Text := Copy(Bytes, First + 1, Last - First);
  Result.Cursor := C - First;
  Result.Anchor := A - First;
end;

procedure InputEnter(Data: Pointer; Input: Pzwp_text_input_v3; Surface: Pwl_surface); cdecl;
begin
  TWaylandTextInput(Data).Enter(Surface);
end;

procedure InputLeave(Data: Pointer; Input: Pzwp_text_input_v3; Surface: Pwl_surface); cdecl;
begin
  TWaylandTextInput(Data).Leave(Surface);
end;

procedure InputPreedit(Data: Pointer; Input: Pzwp_text_input_v3; Text: PAnsiChar; First, Last: Int32); cdecl;
begin
  with TWaylandTextInput(Data) do
  begin
    if Text = nil then
      FPending.Preedit := ''
    else
      FPending.Preedit := UTF8ToString(Text);
    FPending.CursorBegin := First;
    FPending.CursorEnd := Last;
  end;
end;

procedure InputCommit(Data: Pointer; Input: Pzwp_text_input_v3; Text: PAnsiChar); cdecl;
begin
  if Text = nil then
    TWaylandTextInput(Data).FPending.Commit := ''
  else
    TWaylandTextInput(Data).FPending.Commit := UTF8ToString(Text);
end;

procedure InputDelete(Data: Pointer; Input: Pzwp_text_input_v3; Before_, After_: UInt32); cdecl;
begin
  with TWaylandTextInput(Data) do
  begin
    FPending.BeforeLength := Before_;
    FPending.AfterLength := After_;
  end;
end;

procedure InputDone(Data: Pointer; Input: Pzwp_text_input_v3; Serial: UInt32); cdecl;
begin
  TWaylandTextInput(Data).Done(Serial);
end;

const
  Listener: Tzwp_text_input_v3_listener = (enter: InputEnter; leave: InputLeave;
      preedit_string: InputPreedit; commit_string: InputCommit; delete_surrounding_text: InputDelete; done: InputDone);

constructor TWaylandTextInput.Create(Manager: Pzwp_text_input_manager_v3; Seat: Pwl_seat);
begin
  inherited Create;
  FProxy := zwp_text_input_manager_v3_get_text_input(Manager, Seat);
  zwp_text_input_v3_add_listener(FProxy, @Listener, Self);
end;

destructor TWaylandTextInput.Destroy;
begin
  // Owners may already be destroyed: never invoke application callbacks from teardown.
  FApply := nil;
  FCancel := nil;
  FGetState := nil;
  if FProxy <> nil then
    zwp_text_input_v3_destroy(FProxy);
  inherited;
end;

procedure TWaylandTextInput.ResetPending;
begin
  FPending := Default(TWaylandTextBatch);
end;

procedure TWaylandTextInput.CommitState;
begin
  zwp_text_input_v3_commit(FProxy);
  Inc(FSerial);
end;

procedure TWaylandTextInput.CancelComposition;
var
  Cancel: TProc;
begin
  ResetPending;
  Cancel := FCancel;
  if Assigned(Cancel) then
    Cancel();
end;

procedure TWaylandTextInput.SetTarget(Surface: Pwl_surface; const GetState: TFunc<TWaylandTextState>; const Apply: TProc<TWaylandTextBatch>; const Cancel: TProc);
begin
  ClearTarget;
  Inc(FGeneration);
  FSurface := Surface;
  FGetState := GetState;
  FApply := Apply;
  FCancel := Cancel;
  Sync;
end;

procedure TWaylandTextInput.ClearTarget(Notify: Boolean);
var
  Cancel: TProc;
begin
  Inc(FGeneration);
  if Notify then
    Cancel := FCancel;
  FGetState := nil;
  FApply := nil;
  FCancel := nil;
  FSurface := nil;
  FWaitForDone := False;
  ResetPending;
  if FEnabled then
  begin
    zwp_text_input_v3_disable(FProxy);
    CommitState;
    FEnabled := False;
  end;
  if Assigned(Cancel) then
    Cancel();
end;

procedure TWaylandTextInput.Enter(Surface: Pwl_surface);
begin
  FEntered := Surface;
  FEnabled := False;
  FWaitForDone := False;
  ResetPending;
  Sync;
end;

procedure TWaylandTextInput.Leave(Surface: Pwl_surface);
begin
  if Surface <> FEntered then
    Exit;
  FEntered := nil;
  FEnabled := False;
  FWaitForDone := False;
  CancelComposition;
end;

function SameState(const A, B: TWaylandTextState): Boolean;
begin
  Result := (A.Enabled = B.Enabled) and (A.HasSurrounding = B.HasSurrounding) and (A.Text = B.Text) and
    (A.Cursor = B.Cursor) and (A.Anchor = B.Anchor) and (A.CursorRect = B.CursorRect) and
    (A.Hint = B.Hint) and (A.Purpose = B.Purpose);
end;

procedure TWaylandTextInput.Sync(Cause: Cardinal);
var
  State: TWaylandTextState;
  Enabling: Boolean;
  Generation: Cardinal;
begin
  if FApplying or FWaitForDone or (FSurface = nil) or (FSurface <> FEntered) or not Assigned(FGetState) then
    Exit;
  Generation := FGeneration;
  State := FGetState();
  if Generation <> FGeneration then
    Exit;
  if not State.Enabled then
  begin
    if FEnabled then
    begin
      zwp_text_input_v3_disable(FProxy);
      CommitState;
      FEnabled := False;
      CancelComposition;
    end;
    Exit;
  end;
  Enabling := not FEnabled;
  if not Enabling and SameState(State, FState) then
    Exit;
  // enable resets the last advertised state, including surrounding-text support and privacy hints.
  if Enabling or (FState.HasSurrounding <> State.HasSurrounding) or (FState.Hint <> State.Hint) or
    (FState.Purpose <> State.Purpose) then
  begin
    if FEnabled then
    begin
      Generation := FGeneration;
      CancelComposition;
      if (Generation <> FGeneration) or not Assigned(FGetState) then
        Exit;
      State := FGetState();
    end;
    zwp_text_input_v3_enable(FProxy);
    Enabling := True;
  end;
  if State.HasSurrounding then
    zwp_text_input_v3_set_surrounding_text(FProxy, PAnsiChar(State.Text), State.Cursor, State.Anchor);
  zwp_text_input_v3_set_content_type(FProxy, State.Hint, State.Purpose);
  zwp_text_input_v3_set_cursor_rectangle(FProxy, State.CursorRect.Left, State.CursorRect.Top,
    Max(1, State.CursorRect.Width), Max(1, State.CursorRect.Height));
  zwp_text_input_v3_set_text_change_cause(FProxy, Cause);
  CommitState;
  if Enabling then
    FEnableSerial := FSerial;
  FEnabled := True;
  FState := State;
end;

procedure TWaylandTextInput.Done(Serial: Cardinal);
var
  Batch: TWaylandTextBatch;
  Apply: TProc<TWaylandTextBatch>;
  Generation: Cardinal;
begin
  Batch := FPending;
  ResetPending;
  if not FEnabled or (FSurface <> FEntered) then
    Exit;
  // A response belonging to a previous control must not insert text into the next control.
  if Int32(Serial - FEnableSerial) < 0 then
    Exit;
  Generation := FGeneration;
  Apply := FApply;
  FApplying := True;
  try
    if Assigned(Apply) then
      Apply(Batch);
  finally
    FApplying := False;
  end;
  if Generation <> FGeneration then
    Exit;
  FWaitForDone := Serial <> FSerial;
  // A stale done still applies its batch; only state publication waits for a matching serial.
  if not FWaitForDone then
    Sync(ZWP_TEXT_INPUT_V3_CHANGE_CAUSE_INPUT_METHOD);
end;

end.

