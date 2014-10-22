---
layout: post
title: Debugging - HostProtectionException in SSRS
excerpt: Our BI team is currently going through an uplift from Win2k3 to Win2012. It is quite a massive undertaking of course. But, beyond the amount of work that has to be done there is another dangerous killer out there.  Undocumented changes. In this article I describe the System.Security.HostProtectionException in relation to SSRS and custom code.
---
##Overview##
Our BI team is currently going through an uplift from Win2k3 to Win2012. It is quite a massive undertaking of course. But, beyond the amount of work that has to be done there is another dangerous killer out there.  Undocumented changes. In this article I describe the System.Security.HostProtectionException in relation to SSRS and custom code.

In this case I was working with an in-house developed bit of custom code that has been alive for **YEARS**. This code is used inside of a SSRS report to render a special type of image that comes from the database.

Sometime between SSRS install, v1, and vNow of this custom DLL there were numerous changes before during, and after deployment. Most of these changes are just code deployment for SSRS. But, some are a bit more insidious. There are OS level changes, patches, security updates and the like.

So, it's probably fair to say that the code we once had is not the code we have now. Knowing that simple--but useful--fact,  we can get right down to business.

##Steps##
The first thing I always do when trying to debug a "we've been working on it for weeks," scenario is try to figure out who has been doing what. In this case we had a very skilled senior engineer working on the issue. So, I was able to forego a ton of leg work and get down to the meat of the problem. The engineer had already compared config files, checked parameters, run numerous tests, and even added some compensating configuration changes but to no avail.

1. Run report. Fail.
2. Check Application Log. Clean.
3. Check System log. Clean.
4. Check SSRS log. Clean.
5. Run report while watching in WinDbg. Exception.
  - Run the report a couple of times to correlate exceptions

##Debugging##
Once I was able to see there was an exception I needed to see what the exception was. So I loaded up PSSCOR2 and dumped all of the exceptions using `!dae`. With this I was able to see that there were 2 exceptions. This correlated to the number of times that I ran this particular report. An output example is below.  Note the first line of the output.

```
0:000> !dae
Going to dump the .NET Exceptions found in the heap.
Loading the heap objects into our cache.

<<<removed topmost common exceptions>>>

Number of exceptions of this type:        2
Exception MethodTable: 6b8bf514
Exception object: 02a0f438
Exception type: System.Security.HostProtectionException
Message: Attempted to perform an operation that was forbidden by the CLR host.
InnerException: <none>
StackTrace (generated):
<none>
StackTraceString: <none>
HResult: 80131640
-----------------
```

After seeing that I was able to use `!StopOnException (!soe)` to pause the execution once we reached this particular exception. To ensure I was ready once the CLR was loaded. I did this by setting an exception(event) breakpoint by using `sxe ld mscorwks; g`. After that I loaded PSSCOR2 with `.load exts/psccor2`. Look at the following WinDbg log recreation below.

With the command `!soe -create System.Security.HostProtectionException 1` I created a break point on the first chance exception of this host protection exception. The `-create` option tells `!soe` to stop on first chance. The number `1` is a psuedo register that you can use to check for a passfail condition. This is useful if you need to use ADPlus and check exactly WHAT exception was thrown automagically.

>**NOTE** There are help files in WinDbg that breifly explain ADPlus. However, you can also use procdump.exe to create dump files on specific exceptions. ADPlus gives very, very, very granular control over taking a crash dump; there is a learning curve. Procdump.exe gives great power with one command line but does not allow for complex evaluations.

```
0:000> sxe ld mscorwks; g
ModLoad: 6bb20000 6c0ce000   C:\Windows\Microsoft.NET\Framework\v2.0.50727\mscorwks.dll
eax=00000000 ebx=00000000 ecx=00000000 edx=00000000 esi=7efdd000 edi=003eeb3c
eip=77a5fc62 esp=003eea10 ebp=003eea64 iopl=0         nv up ei pl zr na pe nc
cs=0023  ss=002b  ds=002b  es=002b  fs=0053  gs=002b             efl=00000246
ntdll!NtMapViewOfSection+0x12:
77a5fc62 83c404          add     esp,4
0:000> .load exts/psscor2
0:000> !soe -create System.Security.HostProtectionException 1
Breakpoint set
0:000> g

'System.Security.HostProtectionException hit'
First chance exceptions are reported before any exception handling.
This exception may be expected and handled.
eax=003eddc0 ebx=e0434f4d ecx=00000001 edx=00000000 esi=003ede48 edi=0067c598
eip=75d9c42d esp=003eddc0 ebp=003ede10 iopl=0         nv up ei pl nz ac pe nc
cs=0023  ss=002b  ds=002b  es=002b  fs=0053  gs=002b             efl=00000216
KERNELBASE!RaiseException+0x58:
75d9c42d c9              leave

0:000> !CLRStack
OS Thread Id: 0x3520 (0)
ESP       EIP     
003ede98 75d9c42d [HelperMethodFrame: 003ede98] 
003edf3c 6b6ed297 System.Security.CodeAccessSecurityEngine.ThrowSecurityException(System.Reflection.Assembly, System.Security.PermissionSet, System.Security.PermissionSet, System.RuntimeMethodHandle, System.Security.Permissions.SecurityAction, System.Object, System.Security.IPermission)
003edf6c 6b6ed345 System.Security.CodeAccessSecurityEngine.ThrowSecurityException(System.Object, System.Security.PermissionSet, System.Security.PermissionSet, System.RuntimeMethodHandle, System.Security.Permissions.SecurityAction, System.Object, System.Security.IPermission)
003edf94 6b6ed4b1 System.Security.CodeAccessSecurityEngine.CheckSetHelper(System.Security.PermissionSet, System.Security.PermissionSet, System.Security.PermissionSet, System.RuntimeMethodHandle, System.Object, System.Security.Permissions.SecurityAction, Boolean)
003edfe4 6b6ed3fb System.Security.CodeAccessSecurityEngine.CheckSetHelper(System.Threading.CompressedStack, System.Security.PermissionSet, System.Security.PermissionSet, System.Security.PermissionSet, System.RuntimeMethodHandle, System.Reflection.Assembly, System.Security.Permissions.SecurityAction)
003ee194 6bb21b4c [GCFrame: 003ee194] 
003ee904 6bb21b4c [GCFrame: 003ee904] 
003ee96c 6bb21b4c [GCFrame: 003ee96c] 
003ee9bc 6bb21b4c [GCFrame: 003ee9bc] 
003eea4c 6bb21b4c [DebuggerSecurityCodeMarkFrame: 003eea4c] 
003eea20 6bb21b4c [GCFrame: 003eea20] 
003eeab8 6bb21b4c [HelperMethodFrame: 003eeab8] System.Reflection.MethodBase.PerformSecurityCheck(System.Object, System.RuntimeMethodHandle, IntPtr, UInt32)
003eeb1c 6b24f947 System.Reflection.RuntimeConstructorInfo.Invoke(System.Reflection.BindingFlags, System.Reflection.Binder, System.Object[], System.Globalization.CultureInfo)
003eebac 00dbb800 System.Diagnostics.TraceUtils.GetRuntimeObject(System.String, System.Type, System.String)
003eebf0 00dbb6d0 System.Diagnostics.TypedElement.BaseGetRuntimeObject()
003eec04 00dbb457 System.Diagnostics.ListenerElement.GetRuntimeObject()
003eec38 00dbb22a System.Diagnostics.ListenerElementsCollection.GetRuntimeObject()
003eec70 00dbb0a7 System.Diagnostics.TraceInternal.get_Listeners()
003eec9c 005f0369 System.Diagnostics.TraceInternal.WriteLine(System.String)
003eecd8 005f0306 System.Diagnostics.Trace.WriteLine(System.String)
...
```

This stack trace shows us that when we call `Trace.WriteLine()` it invokes security checks. This is all fine and well, but my code is executing as FullTrust. Right?

Well, not exactly. Depending on how you use your custom code it may not execute with FullTrust. For example, if I use my code in an expression it will inherit it's security from `Report_Expressions_Default_Permissions` which is a CodeGroup with a permission set of Execution. This whacks any FullTrust you may have set on your custom code.

##Explanation##
The SSRS reporting engine hosts it's own CLR (CLR Integration) and this is where your code will execute. As mentioned in the previous paragraph the "Expressions Engine" will take default permissions of **Execute**. This causes the code to inherit the lowered security. So, in this case it will perform the security checks required to validate the CAS. Otherwise FullTrust code will cause this check to [evaporate][evap] and not be looked at.

##Resolution##
So, in this case we had the application team remove the `Trace.WriteLine()` calls. This kept us from having to put our SSRS server in some insecure state according to this page on [SSRS Security Policies][ssrssecpol].

While this explains the behvior, it does not explain why the code used to work and now it does not. While I would assume there is some change in 



[ssrssecpol]: http://msdn.microsoft.com/en-us/library/ms154466
[evap]: http://msdn.microsoft.com/en-us/library/system.security.permissions.hostprotectionattribute(v=vs.110).aspx