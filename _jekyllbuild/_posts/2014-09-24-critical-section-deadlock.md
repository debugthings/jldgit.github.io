---
layout: post
title: Debugging - Fixing a deadlock

---
More often than not I do postmortem debugging. That is to say, I get a dump file long after the machine has experienced an issue. But, on occasion I get pulled in to take a look at problems that need to be run through the debugger. This article will show you some commands you can use to locate and fix code using WinDbg.

While I don't recommend what I am doing for an application you are delivering to production, sometimes you have to be creative when debugging. However, your hands may be tied and this set of solutions could help.

For this article I am making an assumption you have a working knowledge of WinDbg. As well I suspect you should have working knowledge of C or C++. And also, of Win32. Do I even need to mention the stack?

If you don't know them I'd check out the following links.

- [Debugging Using WinDbg](http://msdn.microsoft.com/en-us/library/windows/hardware/hh406283(v=vs.85).aspx)
- [Walkthrough: Creating a Win32 Console Program (C++)](http://msdn.microsoft.com/en-us/library/ms235629.aspx)
- [Creating Threads](http://msdn.microsoft.com/en-us/library/windows/desktop/ms682516(v=vs.85).aspx)
- [Critical Section Objects](http://msdn.microsoft.com/en-us/library/windows/desktop/ms682530(v=vs.85).aspx)

Now that you know everything there is to know about Win32 programming and WinDbg, lets get started. :)

##The Application
The application that is being used is a contrived example that demonstrates a deadlock in the purest sense. One application, two threads, two locks out of order.

The repository for the code [is here][code], and is displayed below.
{% highlight cpp %}
int _tmain(int argc, _TCHAR* argv[])
{
  hStdOut = GetStdHandle(STD_OUTPUT_HANDLE);
  InitializeCriticalSection(&cs1);
  InitializeCriticalSection(&cs2);
  DWORD tid1;
  DWORD tid2;
  HANDLE t1 = CreateThread(NULL, 0, Thread1, NULL, 0, &tid1);
  HANDLE t2 = CreateThread(NULL, 0, Thread2, NULL, 0, &tid2);
  HANDLE multiHandle[2] = { t1, t2 };
  WaitForMultipleObjects(2, multiHandle, TRUE, INFINITE);
  return 0;
}

DWORD WINAPI  Thread1(LPVOID lpParam)
{
  int i = 0;
  do
  {
    EnterCriticalSection(&cs2);
    Sleep(5); // Artificial do work
    EnterCriticalSection(&cs1);
    SetConsoleTextAttribute(hStdOut, FOREGROUND_RED);
    std::cout << ++i << "Thread 1" << std::endl;
    Sleep(250);
    LeaveCriticalSection(&cs2);
    LeaveCriticalSection(&cs1);
  } while (true);
}

DWORD WINAPI  Thread2(LPVOID lpParam)
{
  int i = 0;
  do
  {
    EnterCriticalSection(&cs1);
    Sleep(5); // Artificial do work
    EnterCriticalSection(&cs2);
    
    SetConsoleTextAttribute(hStdOut, FOREGROUND_BLUE);
    std::cout << ++i << " Thread 2" << std::endl;
    Sleep(250);
    LeaveCriticalSection(&cs1);
    LeaveCriticalSection(&cs2);
    
  } while (true);
}
{% endhighlight %}

##The Problem
In this example the problem is simply the locks are out of order. The fix is simple if you have the source code.  Have the locks fire in order and your problems will go away.

But, what if you don't have the code? What do you do then? What if the code is critical and just started doing this because of a change in load or a change in the operating system, or ... the list goes on and on.

It's not often you will encounter this, but you just might.

##The Solution Overview
**WinDbg!** The worlds most loved and hated tool of developers. The pro tool. The last line of defense. When all hope is lost, use WinDbg.

>**NOTE** I recommend running all of your C++ code through WinDbg. But, There is no better way to step through your code and get all of the information you need with one tool. 

In order to fix this problem we need to do the following steps. These steps would take a minute or two in Visual Studio; and once you get to be proficient at WinDbg, it could be just as fast.

1. Identify the threads being created
2. Identify the locking pattern
3. Locate the locks
4. Change the order in which the locks are executed

##The Solution Details

From here on out I will make some assumptions about your familiarity with the tool and concepts. I may simply state: "Open the executable in WinDbg," and expect you to know what I mean.

###Step 1 - Start the application
Open the CriticalSectionDeadlock executable in WinDbg... 

###Step 2 - Let it load
Type g in the command line until the command line says `Debugee is running...`.

###Step 3 - Inspect threads
The application should be in a failed state. We will break into the application by typing ``Ctrl+Break``.

Next, type ``~`` to view the active threads. You should see a screen that resembles this:

~~~ 
0:003> ~
   0  Id: 1618.1570 Suspend: 1 Teb: 7efdd000 Unfrozen
   1  Id: 1618.18fc Suspend: 1 Teb: 7efda000 Unfrozen
   2  Id: 1618.bc8 Suspend: 1 Teb: 7efd7000 Unfrozen
.  3  Id: 1618.1bd0 Suspend: 1 Teb: 7efaf000 Unfrozen
~~~ 

*The period(.) next to the Thread Number lets you know that this is the thread you are currently inspecting.*

>**TIP** type ``.hh ~`` to view the help file for the thread syntax command. You can use ``.hh`` for every single command that you use with WinDbg, save for some of the custom extensions.

Now that we can see we have three threads (and one debug thread) we should take a look at what each one is doing. First lest switch to **Thread 1**. The syntax of the command is ``~1s``. We can then inspect the call stack using ``k`` to output the methods only or ``kbn`` to display the frame numbers, method name, and the first three arguments. I added the line breaks to make it easier to read.

~~~ 
0:001> ~1s
eax=00000000 ebx=00000000 ecx=00000000 edx=00000000 esi=01164450 edi=00000000
eip=77dcf8d1 esp=006df7d8 ebp=006df83c iopl=0         nv up ei pl zr na pe nc
cs=0023  ss=002b  ds=002b  es=002b  fs=0053  gs=002b             efl=00000246
ntdll!ZwWaitForSingleObject+0x15:
77dcf8d1 83c404          add     esp,4

0:001> k
ChildEBP RetAddr  
006df7d8 77de8e44 ntdll!ZwWaitForSingleObject+0x15
006df83c 77de8d28 ntdll!RtlpWaitOnCriticalSection+0x13e
006df864 011610ea ntdll!RtlEnterCriticalSection+0x150
006df880 765b338a CriticalSectionDeadlock!Thread1+0x2a 
006df88c 77de9f72 kernel32!BaseThreadInitThunk+0xe
006df8cc 77de9f45 ntdll!__RtlUserThreadStart+0x70
006df8e4 00000000 ntdll!_RtlUserThreadStart+0x1b

0:001> kbn
 # ChildEBP RetAddr  Args to Child              
00 006df7d8 77de8e44 0000003c 00000000 00000000 ntdll!ZwWaitForSingleObject+0x15

01 006df83c 77de8d28 00000000 00000000 765b10ff ntdll!RtlpWaitOnCriticalSection+0x13e

02 006df864 011610ea 01164450 00000000 00000000 ntdll!RtlEnterCriticalSection+0x150

03 006df880 765b338a 00000000 006df8cc 77de9f72 CriticalSectionDeadlock!Thread1+0x2a 

04 006df88c 77de9f72 00000000 776a58cd 00000000 kernel32!BaseThreadInitThunk+0xe

05 006df8cc 77de9f45 011610c0 00000000 00000000 ntdll!__RtlUserThreadStart+0x70

06 006df8e4 00000000 011610c0 00000000 00000000 ntdll!_RtlUserThreadStart+0x1b
~~~ 

If you look at frame 02, you can see that we are entering a critical section. Let's see if there is anything else going on. We will take a look at **Thread 2** this time.

~~~ 
0:002> ~2kbn
 # ChildEBP RetAddr  Args to Child              
00 00b3f970 77de8e44 00000040 00000000 00000000 ntdll!ZwWaitForSingleObject+0x15

01 00b3f9d4 77de8d28 00000000 00000000 765b10ff ntdll!RtlpWaitOnCriticalSection+0x13e

02 00b3f9fc 0116117a 01164438 00000000 00000000 ntdll!RtlEnterCriticalSection+0x150

03 00b3fa18 765b338a 00000000 00b3fa64 77de9f72 CriticalSectionDeadlock!Thread2+0x2a

04 00b3fa24 77de9f72 00000000 77b45a65 00000000 kernel32!BaseThreadInitThunk+0xe

05 00b3fa64 77de9f45 01161150 00000000 00000000 ntdll!__RtlUserThreadStart+0x70

06 00b3fa7c 00000000 01161150 00000000 00000000 ntdll!_RtlUserThreadStart+0x1b

~~~ 

>**TIP** Use the shortcut command ``~2kbn`` which executes the ``kbn`` command without switching to thread 2.

If we look at this thread stack we can see that we also are entering a critical section. At the very top of the stack we can see the `ZwWaitForSingleObject()` method, this tells me that we're blocked waiting for this particular CS. Lets take a look at the data behind the CS and find out why.

###Step 4 - Inspect CRITICAL_SECTION(s)
In the previous step we looked at the call stacks of the deadlocked threads. Judging from those call stacks we know that we are entering a critical section and we are waiting on something. But what are we waiting on?

In order to synchronize the critical sections Windows needs to be able to signal to other threads when it becomes available. In order to do this it uses a reset event. Let's take a look at the `ZwWaitForSingleObject()` parameters on **Thread 2**

~~~ 
0:001> ~2kbn 1
 # ChildEBP RetAddr  Args to Child              
00 00b3f970 77de8e44 00000040 00000000 00000000 ntdll!ZwWaitForSingleObject+0x15

~~~ 

This method is waiting on a handle (`40`). Let's take a look at the handle in the parameter by using the ``!handle`` command.

~~~ 
0:001> !handle 40
Handle 40
  Type          Event

0:001> !handle 40 f
Handle 40
  Type          Event
  Attributes    0
  GrantedAccess 0x100003:
         Synch
         QueryState,ModifyState
  HandleCount   2
  PointerCount  4
  Name          <none>
  Object Specific Information
    Event Type Auto Reset
    Event is Waiting
~~~ 

We can see that this handle is an auto reset event, but for what? We know that we are waiting on a critical section, let's confirm it's relationship. Let's inspect the critical section using the ``!cs`` command, with the parameter from the `RtlEnterCriticalSection()` function in frame 02 (`01164438`).

~~~ 
0:002> !cs 01164438 
-----------------------------------------
Critical section   = 0x01164438 (CriticalSectionDeadlock!cs2+0x0)
DebugInfo          = 0x0079a1b0
LOCKED
LockCount          = 0x1
WaiterWoken        = No
OwningThread       = 0x000018fc
RecursionCount     = 0x1
LockSemaphore      = 0x40
SpinCount          = 0x00000000
~~~ 

We can see that we are indeed waiting on this critical section's lock semaphore (auto reset event). But, if the other thread is trying to enter a different critical section, why are we blocked? This is because this critical section is already LOCKED, as indicated by the ``!cs`` command.

In fact, it is locked by thread `0x18fc`, let's find out who that is. Use the ``~~[TID]`` command for this.

~~~ 
0:001> ~~[0x18fc]
.  1  Id: 1618.18fc Suspend: 1 Teb: 7efda000 Unfrozen
      Start: CriticalSectionDeadlock!Thread1 (011610c0)
      Priority: 0  Priority class: 32  Affinity: ff
~~~ 

Look at that. It is **Thread 1**. But, we don't see the call to that critical section in the call stack.  We can only assume that the call has came and went. Let's find out how these calls are made inside of the `Thread1()` and `Thread2()` functions. We will need to take a look at the disassembly of the `Thread2()` function located at stack frame 03 for **Thread 2**.

###Step 5 - Inspect the code
Now that we're certain we have a blocked thread we need to take a look at the functions that are part of this executable. In order to do that we will use the un-assemble ``u`` command, and use the ``uf`` variant to un-assemble a function. I added line breaks to make some lines easier to read.

~~~ asm
# CriticalSectionDeadlock!Thread2:
mov     ebp,esp
and     esp,0FFFFFFF8h
push    ebp
push    ecx
push    ebx
mov     ebx,dword ptr [CriticalSectionDeadlock!_imp__Sleep (01163014)]
push    esi
push    edi
mov     edi,dword ptr [CriticalSectionDeadlock!_imp__EnterCriticalSection (01163010)]
xor     esi,esi

# CriticalSectionDeadlock!Thread2+0x18:
push    offset CriticalSectionDeadlock!cs1 (01164450)
call    edi
push    5
call    ebx
push    offset CriticalSectionDeadlock!cs2 (01164438)
call    edi
push    2
push    dword ptr [CriticalSectionDeadlock!hStdOut (01164468)]
call    dword ptr [CriticalSectionDeadlock!_imp__SetConsoleTextAttribute (01163018)]
push    offset CriticalSectionDeadlock!std::endl<char,std::char_traits<char> > (01161420)
push    ecx
mov     ecx,dword ptr [CriticalSectionDeadlock!_imp_?coutstd (01163080)]
inc     esi
push    esi
call    dword ptr [CriticalSectionDeadlock!_imp_??6?$basic_ostreamDU?$char_traitsDstdstdQAEAAV01HZ (01163064)]
mov     edx,offset CriticalSectionDeadlock!`string' (011631a4)
mov     ecx,eax
call    CriticalSectionDeadlock!std::operator<<<std::char_traits<char> > (011611e0)
add     esp,4
mov     ecx,eax
call    dword ptr [CriticalSectionDeadlock!_imp_??6?$basic_ostreamDU?$char_traitsDstdstdQAEAAV01P6AAAV01AAV01ZZ (01163068)]
push    0FAh
call    ebx
push    offset CriticalSectionDeadlock!cs1 (01164450)
call    dword ptr [CriticalSectionDeadlock!_imp__LeaveCriticalSection (0116301c)]
push    offset CriticalSectionDeadlock!cs2 (01164438)
call    dword ptr [CriticalSectionDeadlock!_imp__LeaveCriticalSection (0116301c)]
jmp     CriticalSectionDeadlock!Thread2+0x18 (01161168)

~~~ 

I won't walk this code line by line, but I will point out some interesting parts.

**Storing the EnterCriticalSection function pointer in $edi**

~~~ asm
mov     edi,dword ptr [CriticalSectionDeadlock!_imp__EnterCriticalSection (01163010)]
~~~ 

**Calls to $edi**

We first `push` the critical section to the stack and then call the function located at $edi. The addresses to the left are important.

~~~ asm
push    offset CriticalSectionDeadlock!cs1 (01164450)
call    edi
~~~ 
and

~~~ asm
push    offset CriticalSectionDeadlock!cs2 (01164438)
call    edi
~~~ 

These two parts of the code are critical to understanding the code flow and how we will go about editing the application to get it to work.

What we need to do now is locate this function in memory and edit the `push` instruction to push the proper instructions.

###Step 6 - Edit the code
First a little background on x86 architecture and what we are looking at here. The Intel x86 architecture uses [little endian][end] byte order. So, instead of looking at a WORD starting at 0x00 and ending at 0x01 in order from left to right, it would be reversed.

So, 0XDEAD would be represented in memory as it is show, but would be 0xADDE when passed to the instruction.

Let's look at the instruction at address `0x01161168` in the `Thread2()` function. We will use the display memory ``d`` command to do so.

~~~ 
Size of Pointers
0:002> dp 0x01161168 L 4
01161168  16445068 6ad7ff01 68d3ff05 01164438

Size of Words
0:002> dw 0x01161168 L 4
01161168  5068 1644 ff01 6ad7

Size of Bytes
0:002> db 0x01161168 L 5
01161168  68 50 44 16 01

~~~ 

Notice that I specified length using L. Pay attention to the last command when I displayed the bytes and notice I specified the number 5. Why?

The `push` instruction on x86 is represented by one byte (`0x68`) plus four bytes for the address (`0x01164450`). 

>**NOTE** Notice how the bytes aren't really in an order you expect to see them? The reason for this is they a normal address is a double word and would have to be aligned on a word boundary to be displayed properly.
>
>Since instructions can (and usually are) odd sizes the code ends up misaligned. This is okay because the real issue is getting a code segment to fit into a cache line to be run by the processor. In most cases your entire function code block is aligned on a proper boundary.

Since our main code defined the two critical sections directly next to each other the compiler gave them sequential addresses (plus the size of the object).  In reality it doesn't always behave this way, but this sample application happens to.

Now all we need to do is edit the proper byte in the function instruction to swap the order of the calling sequence. We can do this by using the edit memory ``e`` command.

The instruction addresses I'm concerned with are the following:

~~~ 
EnterCriticalSection order:
01161168 6850441601      push    offset CriticalSectionDeadlock!cs1 (01164450)
01161173 6838441601      push    offset CriticalSectionDeadlock!cs2 (01164438)

LeaveCriticalSection order:
011611ba 6850441601      push    offset CriticalSectionDeadlock!cs1 (01164450)
011611c5 6838441601      push    offset CriticalSectionDeadlock!cs2 (01164438)
~~~ 

The actual edit command. *I will repeat this for each of the addresses substituting the proper byte.*

~~~ 
Before:
0:002> db 0x01161168+0x1 L 1
01161169  50 

After:
0:002> eb 0x01161168+0x1 38
0:002> db 0x01161168+0x1 L 1
01161169  38  
~~~ 

>**TIP** Do not edit more than you need to. In the previous example the instructions only differed by 1 byte.

Here is the resulting assembly.  Look for the code at the addresses we've changed and you will see the order of the locks has changed.

~~~ asm
CriticalSectionDeadlock!Thread2:
push    ebp
mov     ebp,esp
and     esp,0FFFFFFF8h
push    ecx
push    ebx
mov     ebx,dword ptr [CriticalSectionDeadlock!_imp__Sleep (01163014)]
push    esi
push    edi
mov     edi,dword ptr [CriticalSectionDeadlock!_imp__EnterCriticalSection (01163010)]
xor     esi,esi

CriticalSectionDeadlock!Thread2+0x18:
push    offset CriticalSectionDeadlock!cs2 (01164438)
call    edi
push    5
call    ebx
push    offset CriticalSectionDeadlock!cs1 (01164450)
call    edi
push    2
push    dword ptr [CriticalSectionDeadlock!hStdOut (01164468)]
call    dword ptr [CriticalSectionDeadlock!_imp__SetConsoleTextAttribute (01163018)]
push    offset CriticalSectionDeadlock!std::endl<char,std::char_traits<char> > (01161420)
push    ecx
mov     ecx,dword ptr [CriticalSectionDeadlock!_imp_?coutstd (01163080)]
inc     esi
push    esi
call    dword ptr [CriticalSectionDeadlock!_imp_??6?$basic_ostreamDU?$char_traitsDstdstdQAEAAV01HZ (01163064)]
mov     edx,offset CriticalSectionDeadlock!`string' (011631a4)
mov     ecx,eax
call    CriticalSectionDeadlock!std::operator<<<std::char_traits<char> > (011611e0)
add     esp,4
mov     ecx,eax
call    dword ptr [CriticalSectionDeadlock!_imp_??6?$basic_ostreamDU?$char_traitsDstdstdQAEAAV01P6AAAV01AAV01ZZ (01163068)]
push    0FAh
call    ebx
push    offset CriticalSectionDeadlock!cs2 (01164438)
call    dword ptr [CriticalSectionDeadlock!_imp__LeaveCriticalSection (0116301c)]
push    offset CriticalSectionDeadlock!cs1 (01164450)
call    dword ptr [CriticalSectionDeadlock!_imp__LeaveCriticalSection (0116301c)]
jmp     CriticalSectionDeadlock!Thread2+0x18 (01161168)
~~~ 

###Step 7 - Run it!
Go on, hit g. Let your code run! GO ON.

Did you do it? Why isn't it running?

Don't forget, you're still in a wait state. We have to clear that. But, how?

Before the application makes the first call into the thread functions you can over write them and test to see if the fix works. There is not much you need to do here.

1. Launch WinDbg and run executable
2. Wait for WinDbg to break before loading file (first break)
3. Load executable with ``ld`` command
4. Patch the function
5. Run

>**NOTE** There is another way to do this that involves using the `.call` command. In order to use it you need proper symbols so you can execute the function. WinDbg needs the function prototype for this to work.

###Step 8 - Patching the executable
This step is not for the faint of heart, but I will describe it anyway.

So, you can't just dump an executable from memory. By the time it is loaded Windows has fixed up your imports and exports, translated all of your RVAs and loaded the file into properly aligned memory sections.

The result is code that will execute if loaded into a process at the exact same address as you dumped it. Not likely. In fact, if you attempted to dump the file with the same exact length you will get a partial file.

What you need to do is patch the executable before it gets translated. There are some decent tools out there that allow you to save a patched version of an executable as you are debugging it. [OllyDbg][olly] comes to mind.

We can do this in WinDbg. It just takes some finesse. 

###Step 8.1 - Finding the RVA and file location
I'd say the first real step is finding the location of the function inside of the actual executable file. In order to do this I will use `DUMPBIN` which can be found in the Visual Studio Tools package.

*You will also want to get the RVA of the critical sections.  We won't be dumping any information about them, but it will help in step 7.2.*

To locate the RVA of **Thread2** run the following, the output is below:

~~~ 
dumpbin /relocations CriticalSectionDeadlock.exe | findstr /i Thread2


87  HIGHLOW            00401150  ?Thread2@@YGKPAX@Z (unsigned long __stdcall Thread2(void *))

~~~ 

Make note of the address 00401150. Your address **could** be different, but it is not likely because that is the standard base address for PE32 files. You can rebase your images if you want, but that is a different topic.



To locate the RVA of the **critical sections** type the following, the output is below:

~~~ 
dumpbin /relocations CriticalSectionDeadlock.exe | findstr /i cs.@


      51  HIGHLOW            00404450  ?cs1@@3U_RTL_CRITICAL_SECTION@@A (struct
_RTL_CRITICAL_SECTION cs1)
      5D  HIGHLOW            00404438  ?cs2@@3U_RTL_CRITICAL_SECTION@@A (struct
_RTL_CRITICAL_SECTION cs2)
      D9  HIGHLOW            00404438  ?cs2@@3U_RTL_CRITICAL_SECTION@@A (struct
_RTL_CRITICAL_SECTION cs2)
      E4  HIGHLOW            00404450  ?cs1@@3U_RTL_CRITICAL_SECTION@@A (struct
_RTL_CRITICAL_SECTION cs1)
     12B  HIGHLOW            00404438  ?cs2@@3U_RTL_CRITICAL_SECTION@@A (struct
_RTL_CRITICAL_SECTION cs2)
     136  HIGHLOW            00404450  ?cs1@@3U_RTL_CRITICAL_SECTION@@A (struct
_RTL_CRITICAL_SECTION cs1)
     169  HIGHLOW            00404450  ?cs1@@3U_RTL_CRITICAL_SECTION@@A (struct
_RTL_CRITICAL_SECTION cs1)
     174  HIGHLOW            00404438  ?cs2@@3U_RTL_CRITICAL_SECTION@@A (struct
_RTL_CRITICAL_SECTION cs2)
     1BB  HIGHLOW            00404450  ?cs1@@3U_RTL_CRITICAL_SECTION@@A (struct
_RTL_CRITICAL_SECTION cs1)
     1C6  HIGHLOW            00404438  ?cs2@@3U_RTL_CRITICAL_SECTION@@A (struct
_RTL_CRITICAL_SECTION cs2)
~~~ 

Make note of the addresses 00404450 and 00404438. Your address **could** be different.

Once you have your RVA location for the `Thread2()` function we can find the location it should be in the actual file. Run the following command to work it out.

~~~ 
dumpbin CriticalSectionDeadlock.exe /headers

Which outputs:

Microsoft (R) COFF/PE Dumper Version 12.00.30723.0
Copyright (C) Microsoft Corporation.  All rights reserved.


Dump of file CriticalSectionDeadlock.exe

PE signature found

File Type: EXECUTABLE IMAGE

FILE HEADER VALUES
             14C machine (x86)
               5 number of sections
        542317A3 time date stamp Wed Sep 24 15:12:35 2014
               0 file pointer to symbol table
               0 number of symbols
              E0 size of optional header
             102 characteristics
                   Executable
                   32 bit word machine

OPTIONAL HEADER VALUES
             10B magic # (PE32)
           12.00 linker version
            1600 size of code
            1C00 size of initialized data
               0 size of uninitialized data
            1F0B entry point (00401F0B) _wmainCRTStartup
            1000 base of code
            3000 base of data
          400000 image base (00400000 to 00406FFF)
            1000 section alignment
             200 file alignment

... removed for brevity ...

SECTION HEADER #1
   .text name
    153B virtual size
    1000 virtual address (00401000 to 0040253A)
    1600 size of raw data
     400 file pointer to raw data (00000400 to 000019FF)
       0 file pointer to relocation table
       0 file pointer to line numbers
       0 number of relocations
       0 number of line numbers
60000020 flags
         Code
         Execute Read

... removed for brevity ...
~~~ 

This command outputs the RVA (virtual address) starting point and it also gives us the file pointer. We can use this to work out the actual location of the function inside of the file. This will be critical for the next step.

~~~ 
  RVA of function:      00401150
- Image Base:           00400000
- VA Starting Address:  00001000
+ File Pointer Offset:  00000400
--------------------------------
Location in file:       00000550

~~~ 

The location of the start of `Thread2()` in the executable is **0x500**.

###Step 8.2 - Loading the file into WinDbg
Now that we have the file offset, we need to load it into WinDbg to alter the code. The assembly will look a bit different but you will get it once you see it.

In order to load the file into WinDbg you need to allocate space with ``.dvalloc`` and then you need to read the file into memory using ``.readmem``. Once it's loaded you can use ``uf`` to inspect the function.

Please note the address returned by ``.dvalloc`` can be different depending on a few factors. Mind the address that is returned by this command. Also note that the radix for these commands is 16, so all of the numbers are in hex.

~~~ 
0:000> .dvalloc 0n13000
Allocated 4000 bytes starting at 000f0000

0:000> .readmem ..\..\CriticalSectionDeadlock2.exe 0xf0000 L 0n12800
Reading 3200 bytes.......

0:000> uf 0xf0000+0x550
000f0550 55              push    ebp
000f0551 8bec            mov     ebp,esp
000f0553 83e4f8          and     esp,0FFFFFFF8h
000f0556 51              push    ecx
000f0557 53              push    ebx
000f0558 8b1d14304000    mov     ebx,dword ptr ds:[403014h]
000f055e 56              push    esi
000f055f 57              push    edi
000f0560 8b3d10304000    mov     edi,dword ptr ds:[403010h]
000f0566 33f6            xor     esi,esi

000f0568 6850444000      push    404450h
000f056d ffd7            call    edi
000f056f 6a05            push    5
000f0571 ffd3            call    ebx
000f0573 6838444000      push    404438h
000f0578 ffd7            call    edi
000f057a 6a02            push    2
000f057c ff3568444000    push    dword ptr ds:[404468h]
000f0582 ff1518304000    call    dword ptr ds:[403018h]
000f0588 6820144000      push    401420h
000f058d 51              push    ecx
000f058e 8b0d80304000    mov     ecx,dword ptr ds:[403080h]
000f0594 46              inc     esi
000f0595 56              push    esi
000f0596 ff1564304000    call    dword ptr ds:[403064h]
000f059c baa4314000      mov     edx,4031A4h
000f05a1 8bc8            mov     ecx,eax
000f05a3 e838000000      call    000f05e0
000f05a8 83c404          add     esp,4
000f05ab 8bc8            mov     ecx,eax
000f05ad ff1568304000    call    dword ptr ds:[403068h]
000f05b3 68fa000000      push    0FAh
000f05b8 ffd3            call    ebx
000f05ba 6850444000      push    404450h
000f05bf ff151c304000    call    dword ptr ds:[40301Ch]
000f05c5 6838444000      push    404438h
000f05ca ff151c304000    call    dword ptr ds:[40301Ch]
000f05d0 eb96            jmp     000f0568


~~~ 

You will notice this disassembly looks close to the disassembly in previous steps. However, none of the symbols are resolved. That's because this file isn't actually loaded, it is just resident in memory.

**Using Steps 5, 6 and 7 you can write the proper bytes to the function as you did before while debugging it.**

###Step 8.3 - Writing the file to disk
We're in the home stretch. If you've made it this far, you're an animal. After we've deduced all of the information we need to about the file and corrected the bug, we need to save the file.

To do this we will use the ``.witemem`` command.

~~~ 
0:000> .writemem c:\temp\fixedfile.exe 0xf0000 L 0n12800
Writing 3200 bytes.......

~~~ 

Thats it! 

###Conclusion
This article series showed us how to work with the debugger, fix a bug, and then patch an executable all without using the source code or Visual Studio.

As I said before WinDbg is a powerful tool with a steep learning curve. But, once you get inside and poke around, it's not so bad. I hope you found this article helpful. Leave me a tweet [@debugthings][twitter]


[code]: https://github.com/jldgit/DebugThingsCode
[end]: http://en.wikipedia.org/wiki/Endianness
[olly]: http://www.ollydbg.de/
[twitter]: https://twitter.com/debugthings