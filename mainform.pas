unit mainform;

(*
Ultibo Auto Uploader

This app contains a web server and uses a telnet session to prod the Raspberry
Pi, running an Ultibo application with the ShellUpdate unit enabled, into downloading
and installing a new kernel.

The Pi must be configured with a SHELL_UPDATE_HTTP_SERVER= setting in cmdline.txt
which points at the host that is running this software.

The application can be run in one of two modes;
- standalone mode, where the application is used interactively
- automatic mode, where the application installs the kernel on the device automatically.

Usage:
ultiboautouploader [ <kernel file location> [<Pi device IP address>] ]

If no parameters are specified this puts the application into pure standalone mode,
without any web server support. You can use the application interactively in this
mode, but you cannot upload files to the device without separately starting a web
server. Note this application is not intended to replace a proper telnet session.
It is only intended to provide for kernel updating or rebooting the device.

If the first parameter is specified, kernel file location, then a web server is
started pointing at the given location. This makes it possible to use the 'update kernel'
button without starting a separate web server.

If the second parameter is included, then the first must also be present, and this
puts the application into automatic mode. In automatic mode, as soon as the application
is loaded, it will start a web server, connect to the Pi, issue a kernel update command,
serve the binary via its internal web server, and then terminate.


Use of Automatic Mode

The purpose of automatic mode is to allow the application to be integrated
into the Ultibo build system. In the Project Options there is a setting at the bottom
of the list called 'Compiler Commands'. This setting opens a page which enables
applications to be executed before and after Compile, Build, and Run.
Ultibo does not support Run, so you must integrate the application into either
Compile Or Build.

Typically I use Build as this recompiles the whole application and can be invoked
with Shift-F9. Hence for a compile without upload I use Ctrl-F9, and for a compile
with upload I use Shift-F9.

To set up automatic mode enable the 'Build' option in the "Execute After" section,
and enter the absolute path to the auto uploader executable, followed by a space, then
the absolute path to where your kernel binaries are located (this is usually the
irectory where your project file is located), then another space, then the IP address of
your Pi device.

Close the dialog, press shift-F9, and after compilation the kernel image will be
sent directly to your Pi and the Pi will reboot.
*)

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls,
  Ipfilebroker, blcksock, tlntsend, Synautil, fphttpserver, fpwebfile;

const
  CONNECT_COMMAND = '##connect';              {connect to the telnet server on the pi}
  LOGOUT_COMMAND = '##logout';                {disconnect from telnet server}
  UPDATE_KERNEL_COMMAND = '##updatekernel';   {execute update kernel command}
  RESTART_COMMAND = '##restart';              {reboot the pi}
  FINISH_COMMAND = '##finish';                {close the application; for being called
                                               with a server IP from the Ultibo IDE}

type

  {serves up the binaries to the Pi when requested over HTTP}
  TWebserverThread = class(TThread)
  private
    FHTTPServer : TFPHTTPServer;
  public
    constructor Create(AOnReq : THTTPServerRequestHandler);
    destructor Destroy; override;
    procedure Execute; override;
  end;

  {used to send commands to the Pi over telnet}
  TTelnetThread = class(TThread)
    FTelNet : TTelnetSend;
    FCommandLock : TRTLCriticalSection;
    FServerIP : string;
    FMessage : string;
    FCommandList : TStringList;

    constructor Create;
    destructor Destroy; override;
    procedure Execute; override;
    procedure AddCommand(acommand : string);
    procedure SetServerIP(ip : string);
    procedure AddThreadMessage(amessage : string);
  end;

  {main dialog}
  TForm1 = class(TForm)
    RestartButton: TButton;
    ConnectButton: TButton;
    ServerIP: TEdit;
    Label1: TLabel;
    UpdateKernelButton: TButton;
    LogoutButton: TButton;
    Edit1: TEdit;
    Memo1: TMemo;
    procedure ConnectButtonClick(Sender: TObject);
    procedure FormActivate(Sender: TObject);
    procedure ServerIPChange(Sender: TObject);
    procedure UpdateKernelButtonClick(Sender: TObject);
    procedure LogoutButtonClick(Sender: TObject);
    procedure RestartButtonClick(Sender: TObject);
    procedure Edit1KeyPress(Sender: TObject; var Key: char);
    procedure FormCreate(Sender: TObject);
  private
    FURL : string;
    FreqStr : string;
    fhandler : TFPCustomFileModule;
    FWebServerThread : TWebServerThread;
    FTelnetThread : TTelnetThread;
    procedure ShowURL;
    procedure DoHandleRequest(Sender: TObject;
                        var ARequest: TFPHTTPConnectionRequest;
                        var  AResponse: TFPHTTPConnectionResponse);
    procedure ShowSessionLog;
    procedure ButtonStateLoggedIn;
    procedure ButtonStateLoggedOut;
    procedure ClearMemoText;
    procedure AddThreadMessage;
    procedure CloseApplication;
  public

  end;


var
  Form1: TForm1;

implementation

{$R *.lfm}

{ TForm1 }

procedure TTelnetThread.SetServerIP(ip : string);
begin
  {set the server ip address}
  EnterCriticalSection(FCommandLock);
  FServerIP := ip;
  LeaveCriticalSection(FCommandLock);
end;

procedure TTelnetThread.AddCommand(acommand : string);
begin
  {add a command to the list. Commands processed in order of being added}
  EnterCriticalSection(FCommandLock);
  FCommandList.Add(acommand);
  LeaveCriticalSection(FCommandLock);
end;

constructor TTelnetThread.Create;
begin
  FTelNet := TTelnetSend.Create;
  FCommandList := TStringList.Create;

  InitCriticalSection(FCommandLock);

  inherited Create(false);
end;

destructor TTelnetThread.Destroy;
begin
  {release resources}
  FTelNet.Free;
  FCommandList.Free;
  DoneCriticalSection(FCommandLock);

  inherited Destroy;
end;

procedure TTelnetThread.AddThreadMessage(amessage : string);
begin
  {put a message on the display}
  FMessage := amessage;
  Synchronize(@Form1.AddThreadMessage);
end;

procedure TTelnetThread.Execute;
var
  MoreLeft : boolean;
  Command : string;
begin
  while not terminated do
  begin
     {wait to keep CPU time down}
     sleep(10);
     EnterCriticalSection(FCommandLock);

     {check command present}
     if (FCommandList.Count > 0) then
     begin
       {remove command from queue and process}
       Command := FCommandList[0];
       FCommandList.Delete(0);

       if (Command = RESTART_COMMAND) then
       begin
         {reboot the pi}
         FTelNet.sessionlog := '';
         Synchronize(@Form1.ClearMemoText);

         FTelNet.Send('restart'+#13+#10);

         FTelNet.timeout := 30000;

         FTelNet.WaitFor('C:\>');
         Synchronize(@Form1.ShowSessionLog);
       end
       else
       if (Command = UPDATE_KERNEL_COMMAND) then
       begin
         {execute an 'update get kernel /r' command}
         AddThreadMessage('Update kernel started.');
         FTelNet.sessionlog := '';
         Synchronize(@Form1.ClearMemoText);

         FTelNet.Send('update get kernel /r'+#13+#10);

         FTelNet.Timeout:=300;

         MoreLeft := true;
         while MoreLeft do
         begin
           MoreLeft := not FTelNet.WaitFor('C:\>');
           Synchronize(@Form1.ShowSessionLog);
         end;

         {reboots after update, so we're logged out}
         Synchronize(@Form1.ButtonStateLoggedOut);
       end
       else
       if (Command = LOGOUT_COMMAND) then
       begin
         {logout of the telnet connection}
         AddThreadMessage('Telnet connection closed.');
         FTelNet.Logout;
         Synchronize(@Form1.ButtonStateLoggedOut);
       end
       else
       if (Command = CONNECT_COMMAND) then
       begin
         {initiate a telnet session}
         AddThreadMessage('Connect to server ' + FServerIP);
         FTelNet.TargetHost:= FServerIP;
         FTelNet.TargetPort:='23';

         if not FTelNet.login then
           AddThreadMessage('Failed to telnet login')
         else
           AddThreadMessage('Successful connection');

         FTelNet.WaitFor('>');

         Synchronize(@Form1.ButtonStateLoggedIn);
         FTelNet.SessionLog:=RightStr(FTelnet.SessionLog, Length(FTelnet.SessionLog)-7);
         Synchronize(@Form1.ShowSessionLog);

         {We do this because we need the prompt to change to the drive letter.
          note for this to work the application has to be built with ShellFilesystem unit.
          Clear the session log so the results don't show in the display.}
         FTelNet.Send('dir'+#13+#10);
         FTelNet.WaitFor('C:\>');
         FTelNet.sessionlog := '';
       end
       else
       if (Command = FINISH_COMMAND) then
       begin
         {terminate - used when called with a parameter to allow automatic termination of the app}
         Synchronize(@Form1.CloseApplication);
       end
       else
       if (Command <> '') then
       begin
         {manually typed Command}
         MoreLeft := true;
         FTelNet.Timeout:=300;
         FTelNet.Send(Command);
         while MoreLeft do
         begin
           MoreLeft := not FTelNet.WaitFor('C:\>');
           Synchronize(@Form1.ShowSessionLog);
         end;
       end;
     end;

     LeaveCriticalSection(FCommandLock);
  end;
end;

constructor TWebServerThread.Create(AOnReq : THTTPServerRequestHandler);
begin
  {wed server thread handles requests from the pi}
  FHTTPServer:=TFPHTTPServer.Create(Nil);
  FHTTPServer.Threaded:=False;
  FHTTPServer.Port:=8000;
  FHTTPServer.OnRequest := AonReq;
  FHTTPServer.AcceptIdleTimeout:=1000;

  inherited Create(false);
end;

destructor TWebServerThread.Destroy;
begin
  {free resources}
  FHTTPServer.Free;

  inherited Destroy;
end;

procedure TWebserverThread.Execute;
begin
  {this doesn't return until the web server is stopped}
  {not ideal, but it is what it is}
  FHTTPServer.Active:=True;
end;


procedure TForm1.ClearMemoText;
begin
  memo1.text := '';
end;

procedure TForm1.AddThreadMessage;
begin
  memo1.lines.add(FTelnetThread.FMessage);
end;

procedure TForm1.ButtonStateLoggedIn;
begin
  UpdateKernelButton.Enabled := true;
  RestartButton.Enabled := true;
  LogoutButton.Enabled := true;
end;

procedure TForm1.ButtonStateLoggedOut;
begin
  ConnectButton.Enabled := true;
  LogoutButton.Enabled := false;
  UpdateKernelButton.Enabled := false;
  RestartButton.Enabled := false;
end;

procedure TForm1.ShowSessionLog;
begin
  memo1.text := FTelnetThread.FTelNet.SessionLog;
end;

procedure TForm1.ConnectButtonClick(Sender: TObject);
begin
  FTelnetThread.SetServerIP(ServerIP.Text);
  FTelnetThread.AddCommand(CONNECT_COMMAND);
end;

procedure TForm1.FormActivate(Sender: TObject);
begin
  if (Paramstr(2) <> '') then
  begin
    {this is the IP address to connect to, in order to initiate an automatic connection}
    ServerIP.Text := ParamStr(2);
    ConnectButtonClick(Sender);
    UpdateKernelButtonClick(Sender);
    FTelnetThread.AddCommand(FINISH_COMMAND);
  end;
end;

procedure TForm1.ServerIPChange(Sender: TObject);
begin
  FTelnetThread.SetServerIP(ServerIP.Text);
end;

procedure TForm1.UpdateKernelButtonClick(Sender: TObject);
begin
  FTelnetThread.AddCommand(UPDATE_KERNEL_COMMAND);
end;

procedure TForm1.LogoutButtonClick(Sender: TObject);
begin
  FTelnetThread.AddCommand(LOGOUT_COMMAND);
end;

procedure TForm1.RestartButtonClick(Sender: TObject);
begin
  FTelnetThread.AddCommand(RESTART_COMMAND);
end;

procedure TForm1.Edit1KeyPress(Sender: TObject; var Key: char);
begin
  if (key = #13) then
  begin
    FTelnetThread.AddCommand(edit1.text + #13 + #10);
  end;
end;

procedure TForm1.DoHandleRequest(Sender: TObject;
                    var ARequest: TFPHTTPConnectionRequest;
                    var  AResponse: TFPHTTPConnectionResponse);
Var
  F : TStringStream;
begin
  FURL:=Arequest.URL;
  FReqStr := ARequest.Method;
  FWebServerThread.Synchronize(@ShowURL);

  if (ARequest.Method = 'HEAD') then
  begin
    F:=TStringStream.Create('');
    try
      AResponse.ContentLength:=1000;
      AResponse.ContentStream:=F;
      AResponse.SendContent;
      AResponse.ContentStream:=Nil;
    finally
      F.Free;
    end;
  end
  else
    FHandler.HandleRequest(ARequest,AResponse);
end;

procedure TForm1.ShowURL;
begin
  memo1.Lines.Add('Serving up request for '+FURL +'('+FReqStr+')');
end;

procedure TForm1.CloseApplication;
begin
  {brutal but will do the job}
  halt;
end;

procedure TForm1.FormCreate(Sender: TObject);
var
  FileLocation : string;
begin
  if (ParamStr(1) <> '') then
  begin
    {this is the file location of where to serve files from}
    FileLocation := ParamStr(1);
    Memo1.Lines.Add('Files will be served from [' + FileLocation + ']');

    {setup file location and web server}
    RegisterFileLocation('files', FileLocation);

    {this is not needed as it defaults to octet stream if not present}
    {that is preferable as we don't know where this file will be on all OS'}
    {MimeTypesFile:='/etc/mime.types';}

    FHandler:=TFPCustomFileModule.CreateNew(Self);
    FHandler.BaseURL:='files/';

    FWebServerThread := TWebserverThread.Create(@DoHandleRequest);
  end
  else
  begin
    FileLocation := '.';
    Memo1.Lines.Add('Warning: The web server is not active when a file location is not provided on the command line.');
  end;

  FTelnetThread := TTelnetThread.Create
end;

end.

