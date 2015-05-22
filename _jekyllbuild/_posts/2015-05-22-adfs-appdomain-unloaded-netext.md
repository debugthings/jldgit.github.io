---
layout: post
title: Debugging - ADFS AppDomainUnloadedException with NetExt
tags:
- debugging
- visual studio
- netext
---
I got a quick message yesterday about a machine running out of space. Normally this is just handled by our second line support. But this time the developer jumped on the box to find out what was causing it and noticed there were a lot of dump files. I looked at it with the developer and found there were a bunch of crash dumps being created by a monitoring tool. This tool captures unhandled exceptions and will create a mini dump for it. Neither of us liked the fact there were numerous dumps, so I decided to dig deeper.

##TL;DR
This isn't nessecarily related to ADFS, it could happen to any application. If you came here looking for the following things, you should start looking at the code that you deployed and if it has an explicit unload or if it modifies any files. In our case .NET patching was happening and the machine.config would be refreshed. This caused the AppDomain to be unloaded and restarted in the w3wp process.

* AppDomainUnloadedException
* HRESULT COR_E_APPDOMAINUNLOADED 0x80131014

## The Problem - ADFS and Crashing W3WP
Not surprisingly, we didn't know there was a problem. As it turns out the application would fail and it would get restarted almost instantaneously due to traffic coming in. The way we found it was non traditional; we have a monitoring solution that will generate a minidump when the process experiences an unhandled exception. Inside of the log directory we had minidumps running all the way back to late last year.

All of these minidumps amounted to a little over 10GB and triggered an out of space warning. Seeing such a large amount of dumps makes me a bit edgy because I start to wonder if our monitoring solution is causing the issue. Looking at the dump files that was not the case, but was there something else that was happening? I can see where a few requests would hang and fail.

## The Analysis
The great thing about what was happening here is that I have a dump that occurred around this time. The second great thing is that it's .NET. I can use a number of tools and extensions to dig out the metadata and the object structure.

I started by loading [NetExt][netext] and took a look at the threads. If you look at thread 0x20(0n32) you can see there is an AppDomainUnloadedException on the stack. Well this looks interesting; let's go check it out.

~~~
0:032> .load netext
netext version 2.0.1.5000 Mar 23 2015
License and usage can be seen here: !whelp license
Check Latest version: !wupdate
For help, type !whelp (or in WinDBG run: '.browse !whelp')
Questions and Feedback: http://netext.codeplex.com/discussions
Copyright (c) 2014-2015 Rodney Viana (http://blogs.msdn.com/b/rodneyviana)
Type: !windex -tree or ~*e!wstack to get started

0:032> !wthreads
Id OSId Address          Domain           Allocation Start:End              COM  GC Type  Locks Type / Status             Last Exception
2 0e90 0000009d2d93fa30 0000009d2d8dd630 0000000000000000:0000000000000000 MTA  Preemptive   0 Background|Finalizer
5 0700 0000009f565c1cc0 0000009d2d8dd630 0000000000000000:0000000000000000 MTA  Preemptive   0 Background|Timer|Worker  
8 1068 0000009f58cde3a0 0000009d2d8dd630 0000009d2ff3b1f0:0000009d2ff3cc88 MTA  Preemptive   0 Background
9 1e80 0000009f58bc52b0 0000009d2d8dd630 0000000000000000:0000000000000000 MTA  Preemptive   0 Background
10 1250 0000009f58cdd140 0000009d2d8dd630 0000000000000000:0000000000000000 NONE Preemptive   0 Background
13 0bd0 0000009f58d6c590 0000009d2d8dd630 0000000000000000:0000000000000000 NONE Preemptive   0 Background|Wait|Worker
14 0df4 0000009f58ca44d0 0000009d2d8dd630 0000000000000000:0000000000000000 NONE Preemptive   0 Background
12 1130 0000009f58d6bdc0 0000009d2d8dd630 0000000000000000:0000000000000000 NONE Preemptive   0 Background|GC
26 18f8 0000009f5cd91de0 0000009d2d8dd630 0000000000000000:0000000000000000 NONE Preemptive   0 Background|GC
15 0414 0000009f5d149060 0000009d2d8dd630 0000000000000000:0000000000000000 NONE Preemptive   0 Background
11 1a84 0000009f58ca2d60 0000009d2d8dd630 0000000000000000:0000000000000000 NONE Preemptive   0 Background
1 1c60 0000009f5d149830 0000009d2d8dd630 0000000000000000:0000000000000000 NONE Preemptive   0 Background
29 ---- 0000009f5cc5bc40 0000009d2d8dd630 0000000000000000:0000000000000000 MTA  Preemptive   0 Terminated
16 ---- 0000009f5cd93d20 0000009d2d8dd630 0000000000000000:0000000000000000 MTA  Preemptive   0 Terminated
4 0de4 0000009f58ca5470 0000009d2d8dd630 0000000000000000:0000000000000000 MTA  Preemptive   0 Background|Worker
23 06a8 0000009f5cafb570 0000009d2d8dd630 0000000000000000:0000000000000000 NONE Preemptive   0 Background
22 1d90 0000009f5cafbd40 0000009d2d8dd630 0000000000000000:0000000000000000 MTA  Preemptive   0 Background|Worker
20 0adc 0000009f5d14a000 0000009d2d8dd630 0000000000000000:0000000000000000 MTA  Preemptive   0 Background|Worker         System.AppDomainUnloadedException
24 096c 0000009f5d00be00 0000009d2d8dd630 0000000000000000:0000000000000000 MTA  Preemptive   0 Background|Worker
17 0a3c 0000009f5924e430 0000009d2d8dd630 0000000000000000:0000000000000000 MTA  Preemptive   0 Background|Worker
19 1e34 0000009f5cafc510 0000009d2d8dd630 0000000000000000:0000000000000000 MTA  Preemptive   0 Background|IOCPort
6 09e4 0000009f5d00a690 0000009d2d8dd630 0000000000000000:0000000000000000 MTA  Preemptive   0 Background|IOCPort
7 1f74 0000009f5924ec00 0000009d2d8dd630 0000000000000000:0000000000000000 MTA  Preemptive   0 Background|IOCPort
3 1f68 0000009f5cafada0 0000009d2d8dd630 0000000000000000:0000000000000000 MTA  Preemptive   0 Background|IOCPort
27 0f74 0000009f5d14a7d0 0000009d2d8dd630 0000000000000000:0000000000000000 MTA  Preemptive   0 Background|Worker


0:032> !wclrstack
Thread Id: 32 OS Id: adc Locks: 0
Thread is Alive
Last Exception: (System.AppDomainUnloadedException) The application domain in which the thread was running has been unloaded.

0000009f5b14f498 0000000000000000 GCFrame
~~~

Well, there's nothing managed on the thread; but there is a managed exception. This is odd, but not unlikely. Let's check out the unmanaged stack to see if anything is happening here. Let's switch to the exception record and inspect the stack.

~~~
0:032> .ecxr
rax=0000009f5b14f008 rbx=0000009f5b14f3a8 rcx=0000009f5d14a000
rdx=000007fbdfc77f66 rsi=0000000000000001 rdi=0000000000000005
rip=000007fbea7b64a8 rsp=0000009f5b14f240 rbp=0000009f5b14f599
 r8=000007fbdfb14954  r9=fffffffffffffffe r10=000007fbe01f86d3
r11=0000cd2f8431210b r12=0000000000004000 r13=0000000000000000
r14=00000000e0434352 r15=0000009f5b14f948
iopl=0         nv up ei pl nz na po nc
cs=0033  ss=002b  ds=002b  es=002b  fs=0053  gs=002b             efl=00000206
KERNELBASE!RaiseException+0x68:
000007fb`ea7b64a8 488b8c24c0000000 mov     rcx,qword ptr [rsp+0C0h] ss:0000009f`5b14f300=000028ab509810f9


0:032> kn
  *** Stack trace for last set context - .thread/.cxr resets it
 # Child-SP          RetAddr           Call Site
00 0000009f`5b14f240 000007fb`dfcfe6af KERNELBASE!RaiseException+0x68
01 0000009f`5b14f320 000007fb`dfeb8154 clr!RaiseTheExceptionInternalOnly+0x28b
02 0000009f`5b14f410 000007fb`dfeb8eb2 clr!RaiseTheException+0xa4
03 0000009f`5b14f440 000007fb`dfeb8194 clr!RealCOMPlusThrowWorker+0x36
04 0000009f`5b14f470 000007fb`dfeb81ac clr!RealCOMPlusThrow+0x3c
05 0000009f`5b14f4e0 000007fb`dfe895ea clr!RealCOMPlusThrow+0xc
06 0000009f`5b14f510 000007fb`dfe89160 clr!Thread::RaiseCrossContextExceptionHelper+0xae
07 0000009f`5b14f600 000007fb`e011d757 clr!Thread::RaiseCrossContextException+0xa9
08 0000009f`5b14f820 000007fb`dfbb4ebd clr!Thread::DoADCallBack+0x5d1f4b
09 0000009f`5b14f9f0 000007fb`dfd1918d clr!UM2MDoADCallBack+0x8d
0a 0000009f`5b14fa70 000007fb`e09c1d6e clr!UMThunkStub+0x26d
0b 0000009f`5b14fb00 000007fb`e09c2276 webengine4!W3_MGD_HANDLER::ProcessNotification+0x78
0c 0000009f`5b14fb30 000007fb`dfb4b1c2 webengine4!ProcessNotificationCallback+0x42
0d 0000009f`5b14fb60 000007fb`dfb49e8b clr!UnManagedPerAppDomainTPCount::DispatchWorkItem+0x11a
0e 0000009f`5b14fc00 000007fb`dfb49d8a clr!ThreadpoolMgr::ExecuteWorkRequest+0x4c
0f 0000009f`5b14fc30 000007fb`dfb6adde clr!ThreadpoolMgr::WorkerThreadStart+0xf6
10 0000009f`5b14fcf0 000007fb`ec601842 clr!Thread::intermediateThreadProc+0x7d
11 0000009f`5b14fe30 000007fb`ed7d02a9 kernel32!BaseThreadInitThunk+0x1a
12 0000009f`5b14fe60 00000000`00000000 ntdll!RtlUserThreadStart+0x1d
~~~

Alright. It looks like the CLR is throwing the exception in the unmanaged world. If you look at frame 0x0d you can see were in the unmanaged thread pool (`UnManagedPerAppDomainTPCount`). This explains why we have an unhandled exception. If you read the [MSDN documentation][msdnapp] about AppDomainUnloadedException it explains exactly what is happening.

>In the .NET Framework version 2.0, an AppDomainUnloadedException that is not handled in user code has the following effect:
>
>* If a thread was started in managed code, it is terminated. The unhandled exception is not allowed to terminate the application.
>* If a task is executing on a ThreadPool thread, it is terminated and the thread is returned to the thread pool. The unhandled exception is not allowed to terminate the application.
>* **If a thread started in unmanaged code, such as the main application thread, it is terminated. The unhandled exception is allowed to proceed, and the operating system terminates the application.**
>
>AppDomainUnloadedException uses the HRESULT COR_E_APPDOMAINUNLOADED, which has the value 0x80131014.

Cool. That explains why the application died. But why was the AppDomain unloaded in the first place? Something had to cause this application domain unload. Let's use a couple of goodies inside of NetExt to see what's going on. I know a problem is occurring inside of the `W3_MGD_HANDLER` so let's look at the HttpRuntime by using `!wruntime` to see if something is going on.

~~~
0:032> !wruntime
Runtime Settings per Application Pool

=========================================================================
Address         : 0000009D2FA4B130
First Request   : 5/16/2015 3:52:33 AM
App Pool User   : *************
Trust Level     : Full
App Domnain Id  : /LM/W3SVC/1/ROOT/adfs/ls-7-130762219536261032
Debug Enabled   : True (Not recommended in production)
Active Requests : 0n1
Path            : C:\inetpub\adfs\ls\ (local disk)
Temp Folder     : C:\Windows\Microsoft.NET\Framework64\v4.0.30319\Temporary ASP.NET Files
Compiling Folder: C:\Windows\Microsoft.NET\Framework64\v4.0.30319\Temporary ASP.NET Files\adfs_ls\a6c27ef8\7adb2961
Shutdown Reason : ConfigurationChange at 5/17/2015 3:12:33 AM

CONFIG change
HostingEnvironment initiated shutdown
HostingEnvironment caused shutdownn   at System.Environment.GetStackTrace(Exception e, Boolean needFileInfo)
   at System.Environment.get_StackTrace()
   at System.Web.Hosting.HostingEnvironment.InitiateShutdownInternal()
   at System.Web.HttpRuntime.ShutdownAppDomain(String stackTrace)
   at System.Configuration.BaseConfigurationRecord.OnStreamChanged(String streamname)
   at System.Web.DirectoryMonitor.FireNotifications()
   at System.Web.Util.WorkItem.CallCallbackWithAssert(WorkItemCallback callback)
   at System.Threading.ExecutionContext.RunInternal(ExecutionContext executionContext, ContextCallback callback, Object state, Boolean preserveSyncCtx)
   at System.Threading.ExecutionContext.Run(ExecutionContext executionContext, ContextCallback callback, Object state, Boolean preserveSyncCtx)
   at System.Threading.QueueUserWorkItemCallback.System.Threading.IThreadPoolWorkItem.ExecuteWorkItem()
   at System.Threading.ThreadPoolWorkQueue.Dispatch()
~~~

Looks like a file is being modified and is causing the recycle. Let's see if we can find this file. To do so we need to find all of the System.Web.FileMonitor objects.

*Also, let's get the app team to turn off debug mode. :smile:*

~~~
0:032> !windex -type *FileMonitor
Index is up to date
 If you believe it is not, use !windex -flush to force reindex
0000009d2fa4c478 000007fb80ab8a80 System.Web.FileMonitor       88   0 2
0000009d2fa4c888 000007fb80ab8a80 System.Web.FileMonitor       88   0 2
0000009d2fa4cc48 000007fb80ab8a80 System.Web.FileMonitor       88   0 2
0000009d2fa4cff0 000007fb80ab8a80 System.Web.FileMonitor       88   0 2
0000009d2fa4d2c0 000007fb80ab8a80 System.Web.FileMonitor       88   0 2
<<< REMOVED FOR CLARITY >>>
<<< 22 instances >>>
~~~

Ugh, 22 objects, it could be worse but it can take some time to go through all of these and to parse the information properly. Let's look at the output from just one of the objects (web.config).

~~~
0:032> !wdo 0000009D2FA76FE0
Address: 0000009d2fa76fe0
Method Table/Token: 000007fb80ab8a80/200031604
Class Name: System.Web.FileMonitor
Size : 88
EEClass: 000007fb80ad6850
Instance Fields: 10
Static Fields: 0
Total Fields: 20
Heap/Generation: 0/2
Module: 0000000057350000
Assembly: 000000002d9436a0
Domain: 00000000e03d2210
Assembly Name: C:\Windows\Microsoft.Net\assembly\GAC_64\System.Web\v4.0_4.0.0.0__b03f5f7f11d50a3a\System.Web.dll
Inherits: System.Object (000007FB80526248)
000007fb807a65e0                 System.Web.DirectoryMonitor +0000          DirectoryMonitor 0000009d2fa76d28
000007fb8082f0e8    System.Collections.Specialized.HybridDic +0008                   Aliases 0000009d2fa77060
000007fb80564d58                               System.String +0010             _fileNameLong 0000009d2fa76db8 web.config
000007fb80564d58                               System.String +0018            _fileNameShort 0000009d2fa76de8 WEB~1.CON
000007fb8082f0e8    System.Collections.Specialized.HybridDic +0020                  _targets 0000009d2fa77038
000007fb80ab9070          System.Web.Util.FileAttributesData +0028                      _fad 0000009d2fa76e18
000007fb805c1378                               System.Byte[] +0030                     _dacl 0000009d2fa76e50
000007fb80ab8928                       System.Web.FileAction +0038               _lastAction 0 (0n0) Overwhelming
000007fb8052c7b8                              System.Boolean +003c                   _exists 1 (True)
000007fb807579c0                             System.DateTime +0040        _utcLastCompletion -mt 000007FB807579C0 0000009D2FA77028 #INVALIDDATE#
~~~

A couple of fields stand out to me; **\_utcLastCompletion** and **\_lastAction**. Let's create a `!wfrom` query to pull this data. This query pulls the address, the name of the file, the lastAction and the date time. I specified the where clause to pick up any \_lastAction that wasn't 0. This was simply because I inspected a couple of items and found 0 to be common.


~~~
0:032> !wfrom -type *FileMonitor where _lastAction > 0 select $addr(), _fileNameLong, _lastAction, $tickstodatetime(_utcLastCompletion.dateData)
calculated: 0000009D2FA52478
_fileNameLong: machine.config
_lastAction: 0n3
calculated: 5/17/2015 3:12:33 AM

1 Object(s) listed
21 Object(s) skipped by filter


0:032> !wdo 0000009D2FA52478
Address: 0000009d2fa52478
Method Table/Token: 000007fb80ab8a80/200031604
Class Name: System.Web.FileMonitor
Size : 88
EEClass: 000007fb80ad6850
Instance Fields: 10
Static Fields: 0
Total Fields: 20
Heap/Generation: 0/2
Module: 0000000057350000
Assembly: 000000002d9436a0
Domain: 00000000e03d2210
Assembly Name: C:\Windows\Microsoft.Net\assembly\GAC_64\System.Web\v4.0_4.0.0.0__b03f5f7f11d50a3a\System.Web.dll
Inherits: System.Object (000007FB80526248)
000007fb807a65e0                      System.Web.DirectoryMonitor +0000          DirectoryMonitor 0000009d2fa521d0
000007fb8082f0e8         System.Collections.Specialized.HybridDic +0008                   Aliases 0000009d2fa524f8
000007fb80564d58                                    System.String +0010             _fileNameLong 0000009d2fa52260 machine.config
000007fb80564d58                                    System.String +0018            _fileNameShort 0000009d2fa52298 MACHIN~1.CON
000007fb8082f0e8         System.Collections.Specialized.HybridDic +0020                  _targets 0000009d2fa524d0
000007fb80ab9070               System.Web.Util.FileAttributesData +0028                      _fad 0000009d2ff36f10
000007fb805c1378                                    System.Byte[] +0030                     _dacl 0000009d2fa52388
000007fb80ab8928                            System.Web.FileAction +0038               _lastAction 3 (0n3) Modified
000007fb8052c7b8                                   System.Boolean +003c                   _exists 1 (True)
000007fb807579c0                                  System.DateTime +0040        _utcLastCompletion -mt 000007FB807579C0 0000009D2FA524C0 5/17/2015 3:12:33 AM

~~~

Found it! It looks like the machine.config was updated sometime around 5/16 @ 11:12am (UTC -04:00), which happens to coincide with the shutdown reason from `!wruntime`. If you read [this old blog post][tess] by Tess Ferandez, it lists the things that can cause an AppDomain recycle. The machine.config is the first one listed.

## Final Notes
In our case this was because of off-cycle security patching. Normally the systems are updated during a maintenance window, but in this case there were a few critical updates that needed to be installed.

[msdnapp]: https://msdn.microsoft.com/en-us/library/system.appdomainunloadedexception%28v=vs.110%29.aspx
[netext]: https://netext.codeplex.com/
[tess]: http://blogs.msdn.com/b/tess/archive/2006/08/02/asp-net-case-study-lost-session-variables-and-appdomain-recycles.aspx
