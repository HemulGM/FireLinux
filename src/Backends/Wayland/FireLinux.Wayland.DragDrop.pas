{ FireLinux: native Wayland platform for Delphi FireMonkey on Linux.
  Copyright (c) 2026 Fasday. MIT license, see LICENSE. }
unit FireLinux.Wayland.DragDrop;

interface

{$SCOPEDENUMS ON}

uses
  System.SysUtils, System.Types;

type
  TWlDragOperation = (None, Move, Copy, Link);

  TWlDragEvent = (Over, Drop, Leave);

  TWlDragData = record
    Internal: Boolean;
    Text: string;
    Files: TArray<string>;
  end;

  TWlDragImage = record
    Width, Height: Integer;
    Pixels: TArray<Cardinal>;
  end;

const
  DragUriMime = 'text/uri-list';
  DragTextMime = 'text/plain;charset=utf-8';
  MaxDragBytes = 64 * 1024 * 1024;

function DragFilesToUriList(const Files: TArray<string>): UTF8String;

function DragUriListToFiles(const Text: string): TArray<string>;

implementation

uses
  System.Classes, System.Generics.Collections;

function DragFilesToUriList(const Files: TArray<string>): UTF8String;
const
  Hex = '0123456789ABCDEF';
var
  FileName: string;
  Bytes: TBytes;
  B: Byte;
  I: Integer;
  Builder: TStringBuilder;
begin
  Builder := TStringBuilder.Create;
  try
    for FileName in Files do
    begin
      if (FileName = '') or (Pos(#0, FileName) <> 0) then
        raise EArgumentException.Create('Drag file path is empty or contains NUL');
      Bytes := TEncoding.UTF8.GetBytes(ExpandFileName(FileName));
      Builder.Append('file://');
      for I := 0 to High(Bytes) do
      begin
        B := Byte(Bytes[I]);
        if (B in [Ord('a')..Ord('z'), Ord('A')..Ord('Z'), Ord('0')..Ord('9')]) or
          (AnsiChar(B) in ['/', '-', '_', '.', '~']) then
          Builder.Append(Char(B))
        else
        begin
          Builder.Append('%');
          Builder.Append(Hex[(B shr 4) + 1]);
          Builder.Append(Hex[(B and 15) + 1]);
        end;
      end;
      Builder.Append(#13#10);
    end;
    Result := UTF8String(Builder.ToString);
  finally
    Builder.Free;
  end;
end;

function DragUriListToFiles(const Text: string): TArray<string>;
var
  Lines: TStringList;
  Files: TList<string>;
  Line, Path, Host: string;
  Raw, Encoded: TBytes;
  I, V, Count: Integer;
  Valid: Boolean;
begin
  Lines := TStringList.Create;
  Files := TList<string>.Create;
  try
    Lines.Text := Text;
    for Line in Lines do
    begin
      if (Line = '') or (Line[1] = '#') then
        Continue;
      if not SameText(Copy(Line, 1, 7), 'file://') then
        Continue;
      Path := Copy(Line, 8, MaxInt);
      I := Pos('/', Path);
      if I = 0 then
        Continue;
      Host := Copy(Path, 1, I - 1);
      if (Host <> '') and not SameText(Host, 'localhost') then
        Continue;
      Path := Copy(Path, I, MaxInt);
      // A file URI is not a URL query. Reject unescaped fragments and malformed escapes.
      if (Pos('#', Path) <> 0) or (Pos('?', Path) <> 0) then
        Continue;
      Encoded := TEncoding.UTF8.GetBytes(Path);
      SetLength(Raw, Length(Encoded));
      Count := 0;
      Valid := True;
      I := 0;
      while I < Length(Encoded) do
      begin
        if Encoded[I] = Ord('%') then
        begin
          if (I + 2 >= Length(Encoded)) or not TryStrToInt('$' + Char(Encoded[I + 1]) + Char(Encoded[I + 2]), V) or
            (V <= 0) or (V > 255) then
          begin
            Valid := False;
            Break;
          end;
          Raw[Count] := V;
          Inc(I, 3);
        end
        else
        begin
          Raw[Count] := Encoded[I];
          Inc(I);
        end;
        Inc(Count);
      end;
      if Valid then
      begin
        SetLength(Raw, Count);
        try
          Path := TEncoding.UTF8.GetString(Raw);
        except
          on E: EEncodingError do
            Continue;
        end;
        // Also reject invalid sequences if a decoder uses replacement characters.
        Encoded := TEncoding.UTF8.GetBytes(Path);
        if (Length(Encoded) = Length(Raw)) and (Length(Raw) > 0) and
          CompareMem(@Encoded[0], @Raw[0], Length(Raw)) and (Pos(#0, Path) = 0) then
          Files.Add(Path);
      end;
    end;
    Result := Files.ToArray;
  finally
    Files.Free;
    Lines.Free;
  end;
end;

end.

