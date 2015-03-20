---
layout: post
title: Debugging - "Exception has been thrown by the target of an invocation"
tags:
- visual studio
- windbg
- debugging
---
The other day I had some issues starting up Visual Studio. I got presented with a modal dialog that said `"Exception has been thrown by the target of an invocation"`. I wasn't sure why, so I tried it again, and again, and the once more for good measure. Turns out, it wasn't the way I was clicking the shortcut link. Of course, this is a problem as Visual Studio is my primary tool. Let's see what was causing this.

## TL;DR
Shorten your PATH environment variable. It's preferred max size is under 2048.

## The Problem(s)
Visual Studio failed to load. I would see the splash screen and then a few seconds later I would get the error message. I looked in logs and event logs but couldn't find anything that was useful. I also noticed a few icons on my desktop were showing the default icon instead of the respective application icon. "Hmm, well that's odd," I said. I did a quick Google search and few hits said to shorten your PATH environment variable. This seemed like an okay thing and I know a long PATH can cause funky things, but **WHY** did it affect Visual Studio?

![target_invocation](/images/targetOfInvocation.png)

## The Diagnosis
I decided to use a hammer and fired up WinDbg. When executing the application I could see a number of exceptions being fired before the application would fail.

```
Executable search path is:
(25e8.25ec): Break instruction exception - code 80000003 (first chance)
eax=00000000 ebx=00000000 ecx=e15b0000 edx=001ee018 esi=fffffffe edi=00000000
eip=7749103b esp=002ef898 ebp=002ef8c4 iopl=0         nv up ei pl zr na pe nc
cs=0023  ss=002b  ds=002b  es=002b  fs=0053  gs=002b             efl=00000246
ntdll!LdrpDoDebuggerBreak+0x2c:
7749103b cc              int     3
0:000> g
(25e8.25ec): Unknown exception - code 04242420 (first chance)
(25e8.25ec): Unknown exception - code e0434352 (first chance)
(25e8.25ec): Unknown exception - code e0434352 (first chance)
(25e8.25ec): Unknown exception - code e0434352 (first chance)
(25e8.25ec): Unknown exception - code e0434352 (first chance)
(25e8.25ec): Unknown exception - code e0434352 (first chance)
(25e8.25ec): Unknown exception - code e0434352 (first chance)
(25e8.25ec): Unknown exception - code e0434352 (first chance)
Package 'Environment Package Window Management' failed to load.
(25e8.25ec): Unknown exception - code e0434352 (first chance)
Package 'Environment Package Window Management' failed to load.
(25e8.25ec): Unknown exception - code e0434352 (first chance)
Package 'Environment Package Window Management' failed to load.
(25e8.25ec): Unknown exception - code e0434352 (first chance)
Package 'Environment Package Window Management' failed to load.
(25e8.25ec): Unknown exception - code e0434352 (first chance)
Package 'Environment Package Window Management' failed to load.
(25e8.25ec): Unknown exception - code e0434352 (first chance)
(25e8.25ec): Unknown exception - code e0434352 (first chance)
(25e8.25ec): Unknown exception - code e0434352 (first chance)
eax=00000000 ebx=00000000 ecx=00000000 edx=00000000 esi=774f2100 edi=774f20c0
eip=7740fcc2 esp=002ef984 ebp=002ef9a0 iopl=0         nv up ei pl zr na pe nc
cs=0023  ss=002b  ds=002b  es=002b  fs=0053  gs=002b             efl=00000246
ntdll!NtTerminateProcess+0x12:
7740fcc2 83c404          add     esp,4
```

The `Unknown exception - code e0434352 (first chance)` is a big clue here. If you look at the error you might see some hex that looks familiar '0x43' '0x43' '0x52' or 'C' 'C' 'R'. No, this isn't a homage to Creedence and doesn't mean there is a bad moon rising. This tells me the errors are being thrown from the CLR runtime. Sweet. Things just got a bit easier.

```
0:000> .formats e0434352
Evaluate expression:
  Hex:     e0434352
  Decimal: -532462766
  Octal:   34020641522
  Binary:  11100000 01000011 01000011 01010010
  Chars:   .CCR
  Time:    ***** Invalid
  Float:   low -5.62807e+019 high 0
  Double:  1.85892e-314
```

Now that I knew the CLR was involved I could use SOS or PSSCOR. The first thing I did before restarting the application was turned on breaking for first chance exceptions for the "Unknown" exception type. You can get here by going to the Debug menu and selecting Event Filters. Set the Unknown exception properties as they are in the image.

![target_invocation](/images/unknown_exception.png)

After I turned that on I fired up the application again and I told the debugger to break when the clr loaded. Using `sxe ld clr` I am able to break on the module load and load SOS by using `.loadby sos clr`. Since I was breaking on unknown exceptions I knew I could use the `g` command and it would execute all code until the next exception.

>NOTE: clr.dll is for v4.0 and up. If you happen to be debugging a lower versions you use mscorwks.dll.

```
CommandLine: "C:\Program Files (x86)\Microsoft Visual Studio 11.0\Common7\IDE\devenv.exe"
=========================================================================================
 ProcDumpExt v6.4 - Copyright 2013 Andrew Richards
=========================================================================================
Symbol search path is: srv*C:\Symbols*http://msdl.microsoft.com/download/symbols;SRV**http://msdl.microsoft.com/download/symbols
Executable search path is:
(1ae0.1880): Break instruction exception - code 80000003 (first chance)
eax=00000000 ebx=00000000 ecx=98400000 edx=0026e1b8 esi=fffffffe edi=00000000
eip=7749103b esp=001df7a8 ebp=001df7d4 iopl=0         nv up ei pl zr na pe nc
cs=0023  ss=002b  ds=002b  es=002b  fs=0053  gs=002b             efl=00000246
ntdll!LdrpDoDebuggerBreak+0x2c:
7749103b cc              int     3
0:000> sxe ld clr; g
ModLoad: 5ff80000 6061b000   C:\Windows\Microsoft.NET\Framework\v4.0.30319\clr.dll
eax=00000000 ebx=00000000 ecx=00000000 edx=00000000 esi=fffdd000 edi=001dda60
eip=7740fc62 esp=001dd934 ebp=001dd988 iopl=0         nv up ei pl zr na pe nc
cs=0023  ss=002b  ds=002b  es=002b  fs=0053  gs=002b             efl=00000246
ntdll!NtMapViewOfSection+0x12:
7740fc62 83c404          add     esp,4
0:000> .loadby sos clr; g
(1ae0.1880): Unknown exception - code 04242420 (first chance)
First chance exceptions are reported before any exception handling.
This exception may be expected and handled.
eax=001dd4ac ebx=00000000 ecx=00000003 edx=00000000 esi=003cb498 edi=00000001
eip=765ec42d esp=001dd4ac ebp=001dd4fc iopl=0         nv up ei pl nz na pe nc
cs=0023  ss=002b  ds=002b  es=002b  fs=0053  gs=002b             efl=00000206
KERNELBASE!RaiseException+0x58:
765ec42d c9              leave
0:000> k
 # ChildEBP RetAddr  
00 001dd4fc 6036fc76 KERNELBASE!RaiseException+0x58
01 001dd578 60060cc1 clr!Debugger::SendRawEvent+0x5e
02 001dda2c 60060a8f clr!Debugger::Startup+0xd9
03 001dda54 6005571b clr!EEDllUnregisterServer+0x21e
04 001ddbcc 60054627 clr!EEStartupHelper+0x681
05 001ddc14 600547ad clr!EEStartup+0x1e
06 001ddcb8 2f46de29 clr!EnsureEEStarted+0xea
07 001ddce8 6f29c449 devenv!CLockClr::ClrStarted+0x18e
08 001dde58 6f27a25f mscoreei!RuntimeDesc::PublishLoad+0x1b0
09 001ddeac 6f27a2a3 mscoreei!RuntimeDesc::EnsureLoaded+0x1b6
0a 001ddec4 6f27dbe6 mscoreei!RuntimeDesc::GetProcAddressInternal+0xe
0b 001ddedc 6f27dc24 mscoreei!RuntimeDesc::GetProcAddressWithCache+0x1a
0c 001ddf18 6f27dd8b mscoreei!CLRRuntimeInfoImpl::CreateClassInternal+0x24
0d 001ddf84 6f2748a2 mscoreei!CLRRuntimeInfoImpl::GetInterfaceInternal+0x2c3
0e 001ddfe4 51bc1912 mscoreei!CLRRuntimeInfoImpl::GetInterface+0xed
0f 001de42c 51bc1969 msenv!LegacyActivationShim::CorBindToRuntimeEx+0xcf
10 001de558 51bc16b4 msenv!VsCorBindToRuntime+0x45
11 001de598 51bc9b73 msenv!VsCoCreateAggregatedManagedObject+0x50
12 001de5fc 51bc9aa9 msenv!VsLoaderCoCreateInstanceUnknown+0x80
13 001de654 51d228b0 msenv!CVsLocalRegistry4::CreateInstance+0x4d
0:000> !CLRStack
OS Thread Id: 0x1880 (0)
Unable to walk the managed stack. The current thread is likely not a
managed thread. You can run !threads to get a list of managed threads in
the process
Failed to start stack walk: 80070057
0:000> g
ModLoad: 61580000 615fd000   C:\Windows\Microsoft.NET\Framework\v4.0.30319\clrjit.dll
eax=00000000 ebx=00000000 ecx=00000000 edx=00000000 esi=fffdd000 edi=001dc7b0
eip=7740fc62 esp=001dc684 ebp=001dc6d8 iopl=0         nv up ei pl zr na pe nc
cs=0023  ss=002b  ds=002b  es=002b  fs=0053  gs=002b             efl=00000246
ntdll!NtMapViewOfSection+0x12:
7740fc62 83c404          add     esp,4
*** WARNING: Unable to verify checksum for C:\Windows\assembly\NativeImages_v4.0.30319_32\Microsoft.Vae4913d6#\c05d390d112193265e7cc71d25ad82a0\Microsoft.VisualStudio.Platform.AppDomainManager.ni.dll
0:000> !pe
There is no current managed exception on this thread
0:000> g
(1ae0.1880): Unknown exception - code e0434352 (first chance)
First chance exceptions are reported before any exception handling.
This exception may be expected and handled.
eax=001db370 ebx=00000005 ecx=00000005 edx=00000000 esi=001db430 edi=00000001
eip=765ec42d esp=001db370 ebp=001db3c0 iopl=0         nv up ei pl nz ac po nc
cs=0023  ss=002b  ds=002b  es=002b  fs=0053  gs=002b             efl=00000212
KERNELBASE!RaiseException+0x58:
765ec42d c9              leave
*** WARNING: Unable to verify checksum for C:\Windows\assembly\NativeImages_v4.0.30319_32\PresentationCore\006d28e7c86f3e70db90ce06ea2f33fb\PresentationCore.ni.dll
0:000> !pe
Exception object: 03d7826c
Exception type:   System.UriFormatException
Message:          Invalid URI: The format of the URI could not be determined.
InnerException:   <none>
StackTrace (generated):
<none>
StackTraceString: <none>
HResult: 80131537

```

The first 2 breaks were not actually managed threads. The first exception is encountered when devenv starts to host the CLR. The second exception is when the AppDomainManager is firing up.

The 3 break is when our real exception is thrown. I did some investigating and found that all of the exceptions thrown after this one were parent exceptions. This first exception is the inner most exception. This may not always be the case when debugging, but in this case it was.

I could see there was a UriFormat exception. Alright, well what is throwing this exception? In this instance it being thrown from the `MS.Internal.FontCache.Util..cctor()` when calling `System.Uri::.ctor`. Well that's odd. Let's see what this guy is doing. In the stack trace I can see the instruction pointer and can use the SOS method `!IP2MD` to find it's MethodDescription. Using the MethodDescription I can dump the IL.


```
0:000> !CLRStack
OS Thread Id: 0xcd8 (0)
Child SP       IP Call Site
003ab7dc 765ec42d [HelperMethodFrame: 003ab7dc]
003ab898 5e376c16 System.Uri.CreateThis(System.String, Boolean, System.UriKind)
003ab8b4 5dd1d866 System.Uri..ctor(System.String, System.UriKind)
003ab8c4 5b53b42e MS.Internal.FontCache.Util..cctor()
003aba5c 5ff83de2 [GCFrame: 003aba5c]
003abf44 5ff83de2 [HelperMethodFrame: 003abf44]
003abfd0 5b54c464 MS.Internal.FontCache.Util.get_Dpi()
...
<<< REMOVED FOR CLARITY >>>

0:000> !ip2md 5dd1d866
MethodDesc:   5dbb80a8
Method Name:  System.Uri..ctor(System.String, System.UriKind)
Class:        5db73088
MethodTable:  5ddcd270
mdToken:      06001c69
Module:       5db71000
IsJitted:     yes
CodeAddr:     5dd1d850
Transparency: Safe critical
```

```
0:000> !dumpil 5dbb80a8
ilAddr = 5dbb80a8
IL_0000: ldc.i4.5
IL_0001: newarr System.String
IL_0006: stloc.0
IL_0007: ldloc.0
IL_0008: ldc.i4.0
IL_0009: ldstr ".COMPOSITEFONT"
IL_000e: stelem.ref
IL_000f: ldloc.0
IL_0010: ldc.i4.1
IL_0011: ldstr ".OTF"
IL_0016: stelem.ref
IL_0017: ldloc.0
IL_0018: ldc.i4.2
IL_0019: ldstr ".TTC"
IL_001e: stelem.ref
IL_001f: ldloc.0
IL_0020: ldc.i4.3
IL_0021: ldstr ".TTF"
IL_0026: stelem.ref
IL_0027: ldloc.0
IL_0028: ldc.i4.4
IL_0029: ldstr ".TTE"
IL_002e: stelem.ref
IL_002f: ldloc.0
IL_0030: stsfld MS.Internal.FontCache.Util::SupportedExtensions
IL_0035: call System.IO.Path::GetInvalidFileNameChars
IL_003a: stsfld MS.Internal.FontCache.Util::InvalidFileNameChars
IL_003f: newobj System.Object::.ctor
IL_0044: stsfld MS.Internal.FontCache.Util::_dpiLock
IL_0049: ldc.i4.0
IL_004a: stsfld MS.Internal.FontCache.Util::_dpiInitialized
IL_004f: ldc.i4.1
IL_0050: ldstr "Windir"
IL_0055: newobj System.Security.Permissions.EnvironmentPermission::.ctor
IL_005a: stloc.2
IL_005b: ldloc.2
IL_005c: callvirt System.Security.CodeAccessPermission::Assert
.try
{
  IL_0061: ldstr "windir"
  IL_0066: call System.Environment::GetEnvironmentVariable
  IL_006b: ldstr "\Fonts\"
  IL_0070: call System.String::Concat
  IL_0075: stloc.1
  IL_0076: leave.s IL_007e
} // end .try
.finally
{
  IL_0078: call System.Security.CodeAccessPermission::RevertAssert
  IL_007d: endfinally
} // end .finally
IL_007e: ldloc.1
IL_007f: callvirt System.String::ToUpperInvariant
IL_0084: stsfld MS.Internal.FontCache.Util::_windowsFontsLocalPath
IL_0089: ldsfld MS.Internal.FontCache.Util::_windowsFontsLocalPath
IL_008e: ldc.i4.1
IL_008f: newobj System.Uri::.ctor
IL_0094: stsfld MS.Internal.FontCache.Util::_windowsFontsUriObject
IL_0099: ldsfld MS.Internal.FontCache.Util::_windowsFontsUriObject
IL_009e: ldc.i4.s 127
IL_00a0: ldc.i4.3
IL_00a1: callvirt System.Uri::GetComponents
IL_00a6: stsfld MS.Internal.FontCache.Util::_windowsFontsUriString
IL_00ab: ret
```

Scanning the IL there is only one place that tries to construct a new Uri, `IL_008f: newobj System.Uri::.ctor` so now we see whats going on. If you look at the try block the code is trying to load up the fonts directory. It does this by concatenating two strings the expanded version of "windir" and "\Fonts\". So, I decided to look at what was on the stack to see what might have been passed into this function

```
0:000> !dso
OS Thread Id: 0xcd8 (0)
ESP/REG  Object   Name
003AB738 03d4826c System.UriFormatException
003AB780 03d4826c System.UriFormatException
003AB7D0 03d47fb0 System.Uri
003AB800 03d4826c System.UriFormatException
003AB83C 03d49dbc System.String    Invalid URI: The format of the URI could not be determined.
003AB844 03d4826c System.UriFormatException
003AB84C 03d4826c System.UriFormatException
003AB858 03d47fb0 System.Uri
003AB878 03d4826c System.UriFormatException
003AB87C 03d4826c System.UriFormatException
003AB898 03d4826c System.UriFormatException
003AB8A0 03d47fb0 System.Uri
003AB8C4 03d47a9c System.String    \Fonts\
003AB8DC 03d47be4 System.Security.FrameSecurityDescriptor
003ABF90 03d47980 System.Windows.DependencyProperty
003AC00C 03d47778 MS.Win32.NativeMethods+LOGFONT

```

Ah-ha! Only the "\Fonts\" string is present; this of course is an invalid Uri. But, why isn't it expanded? Using `!peb` you can see all of the environment variables and other useful information.

```
0:000> !peb
PEB at fffde000
    InheritedAddressSpace:    No
    ReadImageFileExecOptions: No
    BeingDebugged:            Yes
    ImageBaseAddress:         2f460000
    Ldr                       774f0200
    Ldr.Initialized:          Yes
    Ldr.InInitializationOrderModuleList: 00353bb0 . 036bc8c0
    Ldr.InLoadOrderModuleList:           00353b10 . 036bc8b0
    Ldr.InMemoryOrderModuleList:         00353b18 . 036bc8b8

    <<< REMOVED FOR CLARITY >>>

    Environment:  003b3fe8

        <<< REMOVED FOR CLARITY >>>

        PATH=C:\Program Files (x86)\Debugging Tools for Windows (x86)\winext\arcade;C:\Windows\;C:\Windows\System32\
        PATHEXT=.COM;.EXE;.BAT;.CMD;.VBS;.JS;.WS;.MSC

        <<< REMOVED FOR CLARITY >>>

        VSLANG=1033
        WINDBG_DIR=C:\Program Files (x86)\Debugging Tools for Windows (x86)
        _NT_DEBUGGER_EXTENSION_PATH="C:\Program Files (x86)\Debugging Tools for Windows (x86)\WINXP;C:\Program Files (x86)\Debugging Tools for Windows (x86)\winext;C:\Program Files (x86)\Debugging Tools for Windows (x86)\winext\arcade;C:\Program Files (x86)\Debugging Tools for Windows (x86)\pri;C:\Program Files (x86)\Debugging Tools for Windows (x86);C:\Program Files (x86)\Debugging Tools for Windows (x86)\winext\arcade;C:\Program Files (x86)\Debugging Tools for Windows (x86)\exts"
        _NT_SYMBOL_PATH=srv*c:\Symbols*http://msdl.microsoft.com/download/symbols
```
Umm? Where is WINDIR? And, what is up with my PATH?! I went over to my system properties and attempted to look at my path to see if there was something wrong. I got an error I've never seen:

![cannot_find](/images/cannot_find_advprop.png)

"Windows cannot find '%windir%\system32\systempropertiesadvanced.exe'. Make sure you typed the name correctly, and then try again." WTF? Well, that's a problem. I executed the application from the command line (not using the expanded path) and it worked.

So knowing that I have missing PATH entries and this expansion problem I thought to look in the registry. My first intention was to see if somehow the PATH was not set to `REG_EXPAND_SZ`. This wasn't the case, but I did pull the path value and noticed it was about 2200 characters long.

Yep, that's it. The PATH environment variable was too long. I was not aware however that it would break the environment completely by not exposing WINDIR.

## The Fix and Cause
Simply, I just shortened the PATH. Once I did that, I killed explorer.exe and Visual Studio started working. I rebooted for good measure.

But, it was caused by something I hadn't thought about. Since this is on my work machine I have little control over what is installed and when. It turns out that a few days ago they installed some new software and pushed my already lengthy PATH beyond what is recommended.

Here is the `!peb` command after:

```
0:000> !peb
PEB at fffde000
    InheritedAddressSpace:    No
    ReadImageFileExecOptions: No
    BeingDebugged:            Yes
    ImageBaseAddress:         2fd80000
    Ldr                       774f0200
    Ldr.Initialized:          Yes
    Ldr.InInitializationOrderModuleList: 00427950 . 0042ab10
    Ldr.InLoadOrderModuleList:           004278b0 . 0042ab00
    Ldr.InMemoryOrderModuleList:         004278b8 . 0042ab08

    <<< REMOVED FOR CLARITY >>>

    Environment:  00420810

        <<< REMOVED FOR CLARITY >>>

        PATH=C:\Program Files (x86)\Debugging Tools for Windows (x86)\winext\arcade;C:\Program Files (x86)\IBM\WebSphere MQ\Java\lib;C:\Program Files (x86)\CA\Shar edComponents\PEC\bin;C:\Oracle\Ora11_ODAC;C:\Oracle\Ora11_ODAC\bin;C:\Oracle\Or a11\bin;C:\Program Files (x86)\Teradata\Client\13.0\ODBC Driver for Teradata\Li b\;C:\Windows\system32;C:\Windows;C:\Windows\System32\Wbem;C:\Windows\System32\ WindowsPowerShell\v1.0\;C:\Program Files (x86)\Microsoft Team Foundation Server  2010 Power Tools\;C:\Program Files (x86)\Microsoft Team Foundation Server 2010  Power Tools\Best Practices Analyzer\;C:\Program Files (x86)\Sandcastle\Product ionTools\;C:\Program Files (x86)\Teradata\Client\13.0\Shared ICU Libraries for  Teradata\lib\;C:\Program Files (x86)\CA\Cryptography\;C:\Program Files (x86)\CA \AllFusion Harvest Change Manager;C:\Program Files\Microsoft SQL Server\100\DTS \Binn\;C:\Program Files (x86)\Microsoft SQL Server\100\Tools\Binn\VSShell\Commo n7\IDE\;C:\Program Files (x86)\Microsoft SQL Server\100\Tools\Binn\;C:\Program  Files\Microsoft SQL Server\100\Tools\Binn\;C:\Program Files (x86)\Microsoft SQL  Server\100\DTS\Binn\;C:\Program Files (x86)\Microsoft Visual Studio 9.0\Common 7\IDE\PrivateAssemblies\;C:\Program Files (x86)\Microsoft SQL Server\80\Tools\B inn\;C:\Program Files\Microsoft Windows Performance Toolkit\;C:\Program Files ( x86)\IBM\WebSphere MQ\bin64;C:\Program Files (x86)\IBM\WebSphere MQ\bin;C:\Prog ram Files (x86)\IBM\WebSphere MQ\tools\c\samples\bin;C:\PROGRA~2\IBM\SQLLIB\BIN ;C:\PROGRA~2\IBM\SQLLIB\FUNCTION;C:\Program Files\Microsoft\Web Platform Instal ler\;C:\Program Files (x86)\Log Parser 2.2;C:\Program Files (x86)\Microsoft Vis ual Studio 2008 SDK\VisualStudioIntegration\Tools\Sandcastle\ProductionTools\;C:\Windows\;C:\Windows\System32\
        PATHEXT=.COM;.EXE;.BAT;.CMD;.VBS;.VBE;.JS;.JSE;.WSF;.WSH;.MSC

        <<< REMOVED FOR CLARITY >>>

        VSSDK100Install=C:\Program Files (x86)\Microsoft Visual Studio 2010 SDK SP1\
        VSSDK90Install=C:\Program Files (x86)\Microsoft Visual Studio 2008 SDK\
        WINDBG_DIR=C:\Program Files (x86)\Debugging Tools for Windows (x86)
        windir=C:\Windows
        windows_tracing_flags=3
        windows_tracing_logfile=C:\BVTBin\Tests\installpackage\csilogfile.log
        WIX=C:\Program Files (x86)\Windows Installer XML v3\
        _NT_DEBUGGER_EXTENSION_PATH="C:\Program Files (x86)\Debugging Tools for Windows (x86)\WINXP;C:\Program Files (x86)\Debugging Tools for Windows (x86)\winext;C:\Program Files (x86)\Debugging Tools for Windows (x86)\winext\arcade;C:\Program Files (x86)\Debugging Tools for Windows (x86)\pri;C:\Program Files (x86)\Debugging Tools for Windows (x86);C:\Program Files (x86)\Debugging Tools for Windows (x86)\winext\arcade;C:\Program Files (x86)\Debugging Tools for Windows (x86)\exts"
        _NT_SYMBOL_PATH=srv*c:\Symbols*http://msdl.microsoft.com/download/symbols
```

And there we have it. The WINDIR environment variable is back.

## Conclusion
I did Google the error and found a couple of posts about it. One of the links was from a microsoft form that just said to shorten the PATH. I was okay with that answer---but really, I had to know.

If you happen to run into this in your normal line of work, it may not always be so cut and dry as finding the answer online. I never hurts to dig in.




[procmondl]: https://technet.microsoft.com/en-us/library/bb896645.aspx
