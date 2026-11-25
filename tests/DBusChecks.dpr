program DBusChecks;

uses
  System.SysUtils, FireLinux.DBus;

var
  Bus: TDBusConnection;
  Reply: TDBusMessage;
  Intf, Prop: TDBusValue;
begin
  try
    Bus := TDBusConnection.Create;
    try
      Writeln('D-Bus connected: ' + Bus.UniqueName);
      Intf := TDBusValue.Str('org.freedesktop.portal.FileChooser');
      Prop := TDBusValue.Str('version');
      try
        Reply := Bus.Call('org.freedesktop.portal.Desktop', '/org/freedesktop/portal/desktop',
          'org.freedesktop.DBus.Properties', 'Get', [Intf, Prop]);
        try
          Writeln('FileChooser version: ' + UIntToStr(Reply.Body[0].Children[0].Number));
        finally
          Reply.Free;
        end;
      finally
        Intf.Free;
        Prop.Free;
      end;
    finally
      Bus.Free;
    end;
  except
    on E: Exception do
    begin
      Writeln(ErrOutput, E.ClassName + ': ' + E.Message);
      Halt(1);
    end;
  end;
end.
