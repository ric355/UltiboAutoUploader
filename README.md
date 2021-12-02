# Ultibo Auto Uploader

This app is used to prod a Raspberry Pi running an Ultibo application into updating itself.
It contains a web server and uses a telnet session to communicate with the Ultibo application
running on the Pi. The application must be compiled with the ShellUpdate unit enabled as
it uses this method to trigger the download.

Note this application is not intended to replace a proper
telnet session. It is only intended to provide for kernel updating or rebooting the device.

The Pi must be configured with a SHELL_UPDATE_HTTP_SERVER= setting in cmdline.txt
which points at the host that is running this software. The web server within this application
is bound to port 8000, which is the standard for Ultibo updating over HTTP.

The application can be run in one of two modes;
- standalone mode, where the application is used interactively
- automatic mode, where the application installs the kernel on the device automatically.

## Usage:
```
ultiboautouploader [ <kernel file location> [<Pi device IP address>] ]
```

If no parameters are specified this puts the application into pure standalone mode,
without any web server support. You can use the application interactively in this
mode, but you cannot upload files to the device without separately starting a web
server.

If the first parameter is specified, kernel file location, then a web server is
started pointing at the given location. This makes it possible to use the 'update kernel'
button without starting a separate web server.

If the second parameter is included, then the first must also be present, and this
puts the application into automatic mode. In automatic mode, as soon as the application
is loaded, it will start a web server, connect to the Pi, issue a kernel update command,
serve the binary via its internal web server, and then terminate. After updating, the
Pi will reboot and your new kernel will be started.


## Use of Automatic Mode

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

## Supported OS'

The application has only been tested on Linux. It should work on Windows too as there are
no hard coded file paths so feel free to give it a try.

## Building

In order to build the software you will need to have installed the Ararat Synapse library
for the Telnet support. The web server is packaged as standard with Lazarus so there should
be nothing else needed.
