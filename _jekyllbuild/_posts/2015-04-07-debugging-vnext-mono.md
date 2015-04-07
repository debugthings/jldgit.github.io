---
layout: post
title: Debugging - vNext, Mono, xUnit ... On Linux - Part 1
tags:
- vnext
- mono
- deugging
- linux
- xunit
---
Earlier this week I was browsing twitter and I came across a post by [@davidfowler][dfowl] (a dev on the ASPNET team) asking for help with mono. I'm by no means an expert but I thought I could help none the less. I was able to provide some context around the errors the team was seeing for two separate issues. Today I'll walk through some of the steps I took to debug the first issue.

## The Environment
- Ubuntu LTS Server 3.13.0
- Most recent [Mono][monorepo] repo clone
- [xUnit 2][xunit]
- [ASPNET Hosting][aspnethosting] xUnit Tests
- [ASPNET DNX][aspnetdnx] Runtime

The last three items are the combination that the ASPNET dev team is having issues with. I pulled a clone of Mono so I could fiddle with it. The version of Linux doesn't matter as this is centered around Mono for now.

This article will skim the usage of xUnit, Mono and DNX. If you get lost I recommend checking out the links in the Environment list above. Also, I will be digging into [GDB][gdb] and will explain a few of the commands.

## The Problem - Hung Console
The first issue I looked at was a hung console when using the xUnit console runner under Mono. From the open [issue][xunitissue] it stated that no matter the test size if you ran the test parallel it would hang. Even creating a single test with nothing inside of it would cause this issue. So, that is to say if you had a xUnit Fact like the one below, your console would hang. This is especially bad for automated builds because depending on your build platform it will never complete and potentially throw build failures.

~~~CSharp
using System;
using Xunit;

namespace Broken.xUnit.Test
{
    public class HangWindow
    {
        [Fact]
        public void DoNotingToCauseHang()
        {
        }

    }
}
~~~

## Setting up our Debugger
In order to view what was happening I used [GDB][gdb] (GNU Debugger) to attach to the already hung process. In my setup I used two SSH sessions, however I could have put the application in the background (Ctrl-Z) to get the same effect. Also, once I knew it was reproducible I was able to run the command directly in GDB. I will show you how to do attach to a process and how to run it directly.

**If you already know how to do this stuff skip to the actual analysis.**

### Some initial steps - .gdbinit
Taken directly from the [mono debugging page][monodebug], I updated my `.gdbinit` with the following code. This turns off a few signals that pop up quite a bit. It also creates the `mono_stack` and `mono_backtrace` commands we will use to inspect our stack trace.

~~~
handle SIGXCPU SIG33 SIG35 SIGPWR nostop noprint

define mono_backtrace
 select-frame 0
 set $i = 0
 while ($i < $arg0)
   set $foo = (char*) mono_pmip ($pc)
   if ($foo)
     printf "#%d %p in %s\n", $i, $pc, $foo
   else
     frame
   end
   up-silently
   set $i = $i + 1
 end
end


define mono_stack
 set $mono_thread = mono_thread_current ()
 if ($mono_thread == 0x00)
   printf "No mono thread associated with this thread\n"
 else
   set $ucp = malloc (sizeof (ucontext_t))
   call (void) getcontext ($ucp)
   call (void) mono_print_thread_dump ($ucp)
   call (void) free ($ucp)
 end
end
~~~

### Method One - Attach
In order to attach to an existing process you have to use `gdb -pid=<PID>`. Recent Linux hardening practices prohibit the use of ptrace by default so this requires you to set a flag, here `/proc/sys/kernel/yama/ptrace_scope`, and as well here `/etc/sysctl.d/10-ptrace.conf`. The default value is `1`, change it to `0`. Now you can attach to a process running on another session or in the background.

First let's run the process in another session using `dnx . test`. Now that it's running and entered the hung state let's switch to another session and find the process we want to attach to by using `ps`. ***Take note of the `mono` command line, it will help us for Method 2.***

~~~
jldgit@ubuntu:/repos/Razor/test/test2$ ps -ax | grep dnx
17312 pts/1    tl     0:07 /usr/local/bin/mono --debug /home/jldgit/.dnx/runtimes/dnx-mono.1.0.0-beta5-11469/bin/dnx.mono.managed.dll . test
17480 pts/0    Tl     0:02 mono /home/jldgit/.dnx/runtimes/dnx-mono.1.0.0-beta5-11479/bin/dnx.mono.managed.dll . test
17500 pts/0    S+     0:00 grep --color=auto dnx
~~~
>NOTE: You might notice there are two versions of DNX, during my testing I pulled the latest revision to see if it fixed anything. Spoiler alert: No.

That's it. Now that you have the PID you can simply enter `gdb -pid=17480`. This will start the debugger and should attach, if it does not, or throws an error make sure you typed the correct PID and also make sure you read the first paragraph carefully. We'll explain Method Two breifly and then we'll move on to the analysis.

### Method Two - Direct Run
Since we were able to reproduce this error each time there was no need to spin up a second session or a background process to debug this issue. So, we can use another method to execute the application in the foreground with the debugger attached from the very beginning.

If you read the first method you might have noticed a process command line like this `mono /home/jldgit/.dnx/runtimes/dnx-mono.1.0.0-beta5-11479/bin/dnx.mono.managed.dll . test`. When you call `dnx . test` it's just a shell script that calls mono and applies the latest dnx runtime.

In order to debug we need to use `gdb --args <command>` to execute the Mono runtime. So, the full command would be `gdb --args mono /home/jldgit/.dnx/runtimes/dnx-mono.1.0.0-beta5-11479/bin/dnx.mono.managed.dll . test`. Enter that command and you will be presented with the (gdb) prompt. Once here you need to enter `r` to **run** your application.

~~~
jldgit@ubuntu:/repos/Razor/test/test2$ gdb --args mono --debug=gdb /home/jldgit/.dnx/runtimes/dnx-mono.1.0.0-beta5-11479/bin/dnx.mono.managed.dll . test
GNU gdb (Ubuntu 7.7.1-0ubuntu5~14.04.2) 7.7.1
Copyright (C) 2014 Free Software Foundation, Inc.
License GPLv3+: GNU GPL version 3 or later <http://gnu.org/licenses/gpl.html>
This is free software: you are free to change and redistribute it.
There is NO WARRANTY, to the extent permitted by law.  Type "show copying"
and "show warranty" for details.
This GDB was configured as "x86_64-linux-gnu".
Type "show configuration" for configuration details.
For bug reporting instructions, please see:
<http://www.gnu.org/software/gdb/bugs/>.
Find the GDB manual and other documentation resources online at:
<http://www.gnu.org/software/gdb/documentation/>.
For help, type "help".
Type "apropos word" to search for commands related to "word"...
Reading symbols from mono...done.
Mono support loaded.
(gdb) r
~~~

Depending on your mono installation you will have a file located at `/usr/local/bin/mono-sgen-gdb.py` which may throw an error on load. In order to fix that you need to set the following line in that file. This is located in the StringPrinter class near the top of the file.

~~~Python
if val >= 256:
  c = unichr (val)
else:
  c = chr (val)
~~~

### The Actual Analysis
The first thing I thought of was this was sitting waiting for input (Console.ReadLine()). Of course, it wasn't likely as any normal input was ignored and you had to use Ctrl-C twice to exit. This is the keyboard shortcut for the SIGINT signal in Linux. This isn't anything special, but it does mean that we have to exit this application in a way that is unexpected.

The first thing I always look for are threads in a wait state. In order to do this you first need to look at the running threads using the `info threads` command.

~~~
(gdb) info threads
  Id   Target Id         Frame
  10   Thread 0x7fffeda9f700 (LWP 17324) "Threadpool work" sem_timedwait ()
  9    Thread 0x7fffedd53700 (LWP 17323) "Timer-Scheduler" pthread_cond_wait@@GLIBC_2.3.2 ()

  7    Thread 0x7fffee363700 (LWP 17321) "mono" pthread_cond_wait@@GLIBC_2.3.2 ()
  4    Thread 0x7fffee97b700 (LWP 17318) "Threadpool work" sem_timedwait ()
  3    Thread 0x7fffef37b700 (LWP 17317) "Threadpool moni" sem_wait ()
  2    Thread 0x7ffff4d13700 (LWP 17316) "Finalizer" sem_wait ()
* 1    Thread 0x7ffff7fe97c0 (LWP 17312) "mono" pthread_cond_wait@@GLIBC_2.3.2 ()
~~~
>NOTE: I pulled all of the code locations from the symbol data for clarity. Here is an example `7    Thread 0x7fffee363700 (LWP 17321) "mono" pthread_cond_wait@@GLIBC_2.3.2 () at ../nptl/sysdeps/unix/sysv/linux/x86_64/pthread_cond_wait.S:185
`

When looking at the thread stack I see a few threads I expect and a couple that I'm not familiar with. From what I can see, a number of threads are in a wait state. Let's take a look at thread 1 and examine the stack. Switch to the thread using `thread 1` and examine the callstack using `backttrace` (`bt` for short).

~~~
(gdb) thread 1
[Switching to thread 1 (Thread 0x7ffff7fe97c0 (LWP 17312))]
#0  pthread_cond_wait@@GLIBC_2.3.2 () at ../nptl/sysdeps/unix/sysv/linux/x86_64/pthread_cond_wait.S:185
185     in ../nptl/sysdeps/unix/sysv/linux/x86_64/pthread_cond_wait.S

(gdb) bt
#0  pthread_cond_wait@@GLIBC_2.3.2 () at ../nptl/sysdeps/unix/sysv/linux/x86_64/pthread_cond_wait.S:185
#1  0x00000000005fd6db in _wapi_handle_timedwait_signal_handle (handle=0x400, timeout=timeout@entry=0x0, alertable=alertable@entry=1, poll=poll@entry=0)
    at handles.c:1615
#2  0x00000000005fd765 in _wapi_handle_wait_signal (poll=poll@entry=0) at handles.c:1548
#3  0x0000000000610d38 in WaitForMultipleObjectsEx (numobjects=2, handles=handles@entry=0x7fffffffdfa0, waitall=waitall@entry=0,
    timeout=timeout@entry=4294967295, alertable=alertable@entry=1) at wait.c:637
#4  0x00000000005861da in wait_for_tids_or_state_change (timeout=4294967295, wait=0x7fffffffdfa0) at threads.c:2725
#5  mono_thread_manage () at threads.c:2928
#6  0x000000000048a4b2 in mono_main (argc=5, argv=<optimized out>) at driver.c:2025
#7  0x00007ffff7106ec5 in __libc_start_main (main=0x41ec80 <main>, argc=5, argv=0x7fffffffe5a8, init=<optimized out>, fini=<optimized out>,
    rtld_fini=<optimized out>, stack_end=0x7fffffffe598) at libc-start.c:287
#8  0x000000000041ef24 in _start ()
~~~

In frame #3 I can see this thread is waiting for 2 objects and it's never going to timeout since it's using -1 for it's value; I know it says 4294967295, but that is represented as 0y11111111111111111111111111111111 which is -1 for a singed integer.

Alright so the main thread is waiting on some handles. What is it waiting on then? Let's inspect the handle array using the `x` (examine memory). The format below is the number of items (**2**), the format (**x** - HEX), and the size of the inspection (**g** - gigantic (64bit)).

~~~
(gdb) x/2xg 0x7fffffffdfa0
0x7fffffffdfa0: 0x000000000000043b      0x0000000000000402
~~~

Hmm. Two handles, well I wonder what they are. This requires a bit of poking around. There are no handy commands like in WinDbg. I did some leg work and found the code that gets the handle struct. Let's define a function to make this eaisier on us we will use `define <function>` to create this new helper.

~~~C
#define _WAPI_PRIVATE_HANDLES(x) (_wapi_private_handles [x / _WAPI_HANDLE_INITIAL_COUNT][x % _WAPI_HANDLE_INITIAL_COUNT])
~~~

~~~
(gdb) define mono_handle
Type commands for definition of "mono_handle".
End with a line saying just "end".
>set $index = $arg0 / 256
>set $slot = $arg0 % 256
>p  _wapi_private_handles[$index][$slot]
>end
~~~

Now that we have this newly minted `mono_handle` method we can see what exactly is going on here.

~~~
(gdb) mono_handle 0x43b
$25 = {type = WAPI_HANDLE_THREAD, ref = 6, signalled = 0, signal_mutex = {__data = {__lock = 0, __count = 0, __owner = 0, __nusers = 1, __kind = 0,
      __spins = 0, __elision = 0, __list = {__prev = 0x0, __next = 0x0}}, __size = '\000' <repeats 12 times>, "\001", '\000' <repeats 26 times>,
    __align = 0}, signal_cond = {__data = {__lock = 0, __futex = 1, __total_seq = 1, __wakeup_seq = 0, __woken_seq = 0, __mutex = 0x9ca1d0,
      __nwaiters = 2, __broadcast_seq = 0},
    __size = "\000\000\000\000\001\000\000\000\001", '\000' <repeats 23 times>, "С\234\000\000\000\000\000\002\000\000\000\000\000\000",
    __align = 4294967296}, u = {event = {manual = -298436864, set_count = 32767}, file = {filename = 0x7fffee363700 "", share_info = 0x7fffd80008c0,
      fd = 1083, security_attributes = 0, fileaccess = 0, sharemode = 0, attrs = 0}, find = {namelist = 0x7fffee363700, dir_part = 0x7fffd80008c0 "",
      num = 1083, count = 0}, mutex = {pid = -298436864, tid = 140736817268928, recursion = 1083}, sem = {val = 3996530432, max = 32767}, sock = {
      domain = -298436864, type = 32767, protocol = -671086400, saved_error = 32767, still_readable = 1083}, thread = {id = 140737189918464,
      owned_mutexes = 0x7fffd80008c0, wait_handle = 0x43b}, process = {id = -298436864, exitstatus = 32767, main_thread = 0x7fffd80008c0, create_time = {
        dwLowDateTime = 1083, dwHighDateTime = 0}, exit_time = {dwLowDateTime = 0, dwHighDateTime = 0}, proc_name = 0x0, min_working_set = 0,
      max_working_set = 0, exited = 0, mono_process = 0x0}, shared = {offset = 3996530432}}}
~~~

Boom, look at that! The first handle I tried `0x43b` comes up as `WAPI_HANDLE_THREAD` we even have a thread address. The thread object has an id, this id is in decimal format (140737189918464); it's also flanked by a TON of other information. I decided I wanted to be able to get this id into something more readable so I created another function that will give me just the thread id. Knowing the thread ID is contained in the thread info output, I can search for it using `thread find <tid>`.

~~~
(gdb) define mono_handle_thread
Type commands for definition of "mono_handle_thread".
End with a line saying just "end".
>set $index = $arg0 / 256
>set $slot = $arg0 % 256
>p/x _wapi_private_handles[$index][$slot])->u->thread->id
>end

(gdb) mono_handle_thread 0x43b
$27 = 0x7fffee363700

(gdb) thread find 0x7fffee363700
Thread 7 has target id 'Thread 0x7fffee363700 (LWP 17321)'
~~~

Nice, we have a thread now. Let's take a look at its stack and see what we can see. Switch to the thread by typing `thread 7` and check it's call stack with `bt`.

~~~
(gdb) thread 7
[Switching to thread 7 (Thread 0x7fffee363700 (LWP 17321))]
#0  pthread_cond_wait@@GLIBC_2.3.2 () at ../nptl/sysdeps/unix/sysv/linux/x86_64/pthread_cond_wait.S:185
185     ../nptl/sysdeps/unix/sysv/linux/x86_64/pthread_cond_wait.S: No such file or directory.
(gdb) bt
#0  pthread_cond_wait@@GLIBC_2.3.2 () at ../nptl/sysdeps/unix/sysv/linux/x86_64/pthread_cond_wait.S:185
#1  0x00000000005fd6db in _wapi_handle_timedwait_signal_handle (handle=handle@entry=0x43b, timeout=timeout@entry=0x0, alertable=alertable@entry=1,
    poll=poll@entry=0) at handles.c:1615
#2  0x00000000005fd79b in _wapi_handle_wait_signal_handle (handle=handle@entry=0x43b, alertable=alertable@entry=1) at handles.c:1560
#3  0x000000000061042b in WaitForSingleObjectEx (handle=handle@entry=0x43b, timeout=timeout@entry=4294967295, alertable=alertable@entry=1) at wait.c:194
#4  0x00000000005844a3 in ves_icall_System_Threading_Thread_Join_internal (this=0x7fffeeb87480, ms=-1, thread=0x43b) at threads.c:1334
#5  0x00000000404958f9 in ?? ()
#6  0x00007ffff61752b0 in ?? ()
#7  0x00007fffee362e00 in ?? ()
#8  0x00007ffff6049590 in ?? ()
#9  0x00007ffff6174e60 in ?? ()
#10 0x00007ffff6175318 in ?? ()
<< REMOVED SOME LINES >>
~~~

We can see that this thread is definitely waiting on something. Look at frame #3, there is a `WaitForSingleObjectEx` method being called on handle `0x43b`. Wait... according to the handle output that is this thread! Okay, that's not good. If you look at frame #4 we're calling `ves_icall_System_Threading_Thread_Join_internal`; without knowing too much of the internals of Mono I can assume that this equates to a Thread.Join() operation.

Looking at the remainder of the frames I can see a lot of addresses but no symbols. Let's try `mono_backtrace <number>` to see if there are any Mono methods.

~~~
(gdb) mono_backtrace 33

<< REMOVED FRAMES FOR CLARITY >>

#5 0x404958f9 in  (wrapper managed-to-native) System.Threading.Thread:Join_internal (System.Threading.InternalThread,int,intptr) + 0x69 (0x40495890 0x40495933) [0x9d42e0 - dnx.mono.managed.dll]

<< REMOVED FRAMES FOR CLARITY >>

#17 0x40495878 in  System.Threading.Thread:Join () + 0x48 (0x40495830 0x40495881) [0x9d42e0 - dnx.mono.managed.dll]

<< REMOVED FRAMES FOR CLARITY >>

#21 0x40495818 in  Xunit.Sdk.XunitWorkerThread:Join () + 0x28 (0x404957f0 0x4049581d) [0x9d42e0 - dnx.mono.managed.dll]

<< REMOVED FRAMES FOR CLARITY >>

#25 0x406339f0 in  Xunit.Sdk.MaxConcurrencySyncContext:Dispose () + 0x80 (0x40633970 0x40633a56) [0x9d42e0 - dnx.mono.managed.dll]

<< REMOVED FRAMES FOR CLARITY >>
~~~

As I expected I can see a Thread.Join() being called. It happens to be coming from `Xunit.Sdk.MaxConcurrencySyncContext::Dispose()`. As we know, we should ***NEVER*** call Thread.Join() against your own thread. Let's run `mono_stack` to see what information it gives us. The more context around this issue the better.

~~~
(gdb) mono_stack

"<unnamed thread>" tid=0x0x7fffee363700 this=0x0x7fffeeb87480 thread handle 0x43b state : waiting on 0x43b : Thread  owns ()
  at <unknown> <0xffffffff>
  at (wrapper managed-to-native) System.Threading.Thread.Join_internal (System.Threading.InternalThread,int,intptr) <IL 0x0000f, 0xffffffff>
  at System.Threading.Thread.Join () [0x00000]
  at Xunit.Sdk.XunitWorkerThread.Join () <IL 0x00006, 0x00027>
  at Xunit.Sdk.MaxConcurrencySyncContext.Dispose () <IL 0x0001a, 0x0007f>
  at Xunit.Sdk.XunitTestAssemblyRunner.Dispose () <IL 0x0000b, 0x00034>
  at Xunit.Sdk.XunitTestFrameworkExecutor/<RunTestCases>d__6.MoveNext () <IL 0x000bb, 0x002ad>
  at (wrapper unbox) Xunit.Sdk.XunitTestFrameworkExecutor/<RunTestCases>d__6.MoveNext () <IL 0x0000a, 0xffffffff>
  at System.Threading.Tasks.SynchronizationContextContinuation.<Execute>m__0 (object) [0x00000] in
  at Xunit.Sdk.MaxConcurrencySyncContext/<>c__DisplayClass8_0.<WorkerThreadProc>b__0 (object) <IL 0x0001c, 0x00071>
  at System.Threading.ExecutionContext.Run (System.Threading.ExecutionContext,System.Threading.ContextCallback,object) [0x00027]
  at Xunit.Sdk.MaxConcurrencySyncContext.WorkerThreadProc () <IL 0x00050, 0x00167>
  at Xunit.Sdk.XunitWorkerThread/<>c__DisplayClass1_0.<.ctor>b__0 () <IL 0x00006, 0x00026>
  at (wrapper runtime-invoke) object.runtime_invoke_void__this__ (object,intptr,intptr,intptr) <IL 0x0004e, 0xffffffff>
~~~

Yep, this confirms even more what we already know. Clearly in the first line of the output it says `thread handle 0x43b state : waiting on 0x43b : Thread owns ()`. So, it's a dead lock like situation. But, how can this happen? Surely we wouldn't call Thread.Join() on ourselves? And, of course, we're not. This happens to be a bug in Mono's implementation of Thread and Execution context.

I'll spare you the gritty details of xUnit's custom thread pool, but it was implemented to be flexible across multiple platforms. Therefore a lot of the work the standard System.Threading.ThreadPool class is doing xUnit is doing.

For more info on the bounds checking have a look at the [ExecutionContext][execon] definition on Reference Source.

If you want to know more about why it affected xUnit, check out the [bug report][bug] [@bradwilson][bradw] filed with the Mono team.

Brad fixed this by adding in some checking of his own and now his code will work around the Mono threading implementation. You can see this in the same [issue][xunitissue] open on GitHub.

## Wrapping Up
What's interesting here is this bug is pretty subtle. It's not very often you will find applications rolling their own thread pools. In the case of xUnit since they have to be flexible enough for just about any environment they are using some pretty advanced techniques to create a scalable and workable solution no matter where they end up.

If you find yourself in a situation where your applications works as expected in Windows with the full CLR but has some quirkiness when running under Mono you shouldn't back away slowly. Instead you should open up your debugger and find out what is going on. All of the code for [Mono][monorepo] is open source and on GitHub, you could even write your own patch and submit it as a PR.

[monorepo]: https://github.com/mono/mono
[xunit]: http://xunit.github.io/
[aspnethosting]: https://github.com/aspnet/Hosting
[aspnetdnx]: https://github.com/aspnet/Home#optimistic-dnvm-2
[xunitissue]: https://github.com/xunit/aspnet.xunit/issues/6
[monodebug]: http://www.mono-project.com/docs/debug+profile/debug/
[gdb]: https://www.gnu.org/software/gdb/
[bradw]: https://twitter.com/bradwilson
[dfowl]: https://twitter.com/davidfowl
[bug]: https://bugzilla.xamarin.com/show_bug.cgi?id=28793
[execon]: http://referencesource.microsoft.com/#mscorlib/system/threading/executioncontext.cs,5a5eb57d2b341635
[smtst]: http://io.smashthestack.org/
