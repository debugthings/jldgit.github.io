---
layout: post
title: Debugging - vNext, Mono, xUnit ... On Linux - Part 2
tags:
- vnext
- mono
- deugging
- linux
- xunit
---
Last time we found an issue with the threading model and the execution context that caused the xUnit custom thread manager to attempt to join on itself causing an infinite wait condition. This time the execution context is breaking us in an entirely new way. In this session I will show you two ways to find the issue using GDB. Hang on because we're going deep in this one.

## The Environment
- Ubuntu LTS Server 3.13.0
- [Mono][monorepo] 3.12.0 repo clone
- [xUnit 2][xunit]
- [ASPNET Hosting][aspnethosting] xUnit Tests
- [ASPNET DNX][aspnetdnx] Runtime

I found out from [Alex Köplinger][alexk] that the thread pool implementation in "edge" is a bit different than in 3.12.0. I've rolled back to the latest stable release of Mono to be on the safe side. Last time I was debugging against the edge of Mono---more specifically the master repository.

This article will skim the usage of xUnit, Mono and DNX. If you get lost I recommend checking out the links in the Environment list above. Also, I will be digging into [GDB][gdb] and will explain a few of the commands.

## The Problem - Missing CallContext
This issue was stranger than the last one. The test would seemingly fail on random items, most of the time I could reproduce the same exact outcome. But, occasionally I'd get a different number of passed / failed tests. When looking at the stack traces and all of the outcomes I'd see various messages, but ultimately it all related to this stack trace below. It is complaining of a null reference when trying to get a service provider from DNX. As before, this would throw build failures.

~~~
Microsoft.AspNet.TestHost.TestClientTests.GetAsyncWorks [FAIL]
     System.NullReferenceException : Object reference not set to an instance of an object
     Stack Trace:
          at Microsoft.Framework.DependencyInjection.ServiceProviderExtensions.GetRequiredService (IServiceProvider provider, System.Type serviceType) [0x00000] in <filename unknown>:0
          at Microsoft.Framework.DependencyInjection.ServiceProviderExtensions.GetRequiredService[IServiceManifest] (IServiceProvider provider) [0x00000] in <filename unknown>:0
          at Microsoft.AspNet.Hosting.Internal.RootHostingServiceCollectionInitializer.Build () [0x00007] in <filename unknown>:0
          at Microsoft.AspNet.Hosting.WebHost.CreateFactory (IServiceProvider fallbackServices, System.Action`1 configureServices) [0x00012] in <filename unknown>:0
          at Microsoft.AspNet.Hosting.WebHost.CreateEngine (IServiceProvider fallbackServices, IConfiguration config, System.Action`1 configureServices) [0x00001] in <filename unknown>:0
          at Microsoft.AspNet.TestHost.TestServerBuilder.Build () [0x000a0] in <filename unknown>:0
          at Microsoft.AspNet.TestHost.TestServer.Create (IServiceProvider fallbackServices, IConfiguration config, System.Action`1 configureApp, System.Action`1 configureServices) [0x0000a] in <filename unknown>:0
          at Microsoft.AspNet.TestHost.TestServer.Create (System.Action`1 configureApp) [0x00001] in <filename unknown>:0
          at Microsoft.AspNet.TestHost.TestClientTests..ctor () [0x00008] in <filename unknown>:0
          at (wrapper managed-to-native) System.Reflection.MonoCMethod:InternalInvoke (System.Reflection.MonoCMethod,object,object[],System.Exception&)
          at System.Reflection.MonoCMethod.InternalInvoke (System.Object obj, System.Object[] parameters) [0x00002] in <filename unknown>:0

~~~

## Setting up our Debugger
**See this section in [part 1][pt1].**

## The Actual Analysis
This was tricky, I started with the debugger and I'd get the exception long after the problem had occurred. This is the beauty and danger of using async tasks; depending on the type of exception it will be very hard to capture. So, my attempt at using the debugger was a bit flawed. As the saying goes, if all you have is a hammer...

In order to find out what was happening here I had to do some code walking to see why this would happen. The method `Microsoft.Framework.DependencyInjection.ServiceProviderExtensions.GetRequiredService()` was throwing the null reference. Since this was causing the test to fail I wanted to follow the code back to the method that causes it to leave our testing assembly. This lead me to the method [Microsoft.AspNet.Hosting.Internal.RootHostingServiceCollectionInitializer.Build ()][dnxline31]. It's a simple enough builder and is failing when it tries to get a service from some IServiceProvder.

Talking to [@davidfowler][dfowl] he said it's because of [dnx.host.ServiceProviderLocator][splocator]. This class keeps a list of all of the possible services you might need to invoke from inside of your code. In the case of dnx, it stores `IAssemblyLoaderContainer`, `IAssemblyLoadContextAccessor`, and `IApplicationEnvironment`. You can see that here in the [CallContextServiceLocator][callcontextlocator].

What does this all mean? Let's focus in on what the ASPNET team is trying to do here. They are providing a one stop, thread safe implementation of a data store. They are using [CallContext][cc] to achieve this cross thread communication---this is akin to TLS, but a bit more powerful. CallContext allows you to pass data along a string of threads. So for instance, thread 1 creates thread 2, which creates thread 3; using the CallContext class you can pass data between them. However, this is a forward copy only and will not move back down the chain. That way, anything set on thread 3 will not poison thread 2.

Why isn't it working? This is something that requires the deep inspection of some of the mono code. I know that the [ExecutionContext][execontext] is what contains our [LogicalCallContext][logiccall] and is [explained][execontext] in the ExecutionContext documentation. Also explained in the remarks section is when it ***won't*** be copied--specifically the part about the thread pool. When I asked David and team about the thread pool, they said they weren't using it explicitly---they were using Tasks. Tasks themselves DO use the thread pool by default to schedule execution; that is unless you override the scheduler.

I started grokking the System.Threading.Task code and found that in Mono, everything comes back to [Task.Factory.StartNew()][startnew]. As mentioned in the last paragraph the default sheduler is the thread pool scheduler, or the [TpScheduler][tpsched]. As we walk down to the final methods that schedule the task we are left with, none other than, Schedule(). Which calls QueueTask from the TpScheduler. This intern calls QueueWorkItem().

~~~Csharp
// TpScheduler Methods
namespace System.Threading.Tasks
{
  sealed class TpScheduler: TaskScheduler
  {
    internal void Schedule (bool throwException)
    {
      Status = TaskStatus.WaitingToRun;
      try {
        scheduler.QueueTask (this);
        }
        catch (Exception inner) {
          var ex = new TaskSchedulerException (inner);
          TrySetException (new AggregateException (ex), false, true);
          if (throwException)
            throw ex;
        }
    }

    protected internal override void QueueTask (Task task)
    {
      if ((task.CreationOptions & TaskCreationOptions.LongRunning) != 0) {
        var thread = new Thread (l => ((Task)l).Execute ()) {
          IsBackground = true
        };

        thread.Start (task);
        return;
      }
      ThreadPool.QueueWorkItem (callback, task);
    }
  }
}
// TpScheduler Methods
namespace System.Threading {
  public static class ThreadPool {
    internal static void QueueWorkItem (WaitCallback callBack, object state)
    {
      pool_queue (new AsyncResult (callBack, state, false));
    }
  }
}
~~~


Looking at this code I can see the `pool_queue` internal method that accepts a new [AsyncResult][asyncresult]. Hmm, well let's start with the AsyncResult, it seems highly relevant as we're doing asynchronus tasks. I take a look at the constructor and I see something that is almost unreal. Right there, there is a condition to check to see if it should capture the execution context. I literally blink as I can't imagine getting any luckier to find it. But there is a problem. Our code path explicitly calls false when using the QueueWorkItem() method.

~~~Csharp
namespace System.Runtime.Remoting.Messaging {
  public class AsyncResult : IAsyncResult, IMessageSink {
    internal AsyncResult (WaitCallback cb, object state, bool capture_context)
    {
      async_state = state;
      async_delegate = cb;
      if (capture_context)
        current = ExecutionContext.Capture ();
    }
  }
}
~~~

Now what? In the corlib of Mono, this is how it's all implemented. While looking at the thread pool implementation of QueueWorkItem() I also looked QueueUserWorkItem()---this has a code path that will clone the ExecutionContext. Cool, we have a work around. Done. Right? Well, no. Unfortunately I had David try this again using the thread pool and no dice. What gives?

This is where we get into the nity gritty of what is happening here. We are still losing the execution context. But where? According to [Brad Wilson][bradw] this shouldn't be happening as he is not using the standard scheduler. So, let's find out who ***IS*** causing the issue. From here I will describe two ways to get to the data. The first way is the long way; it involves some hacking of the Mono framework to add a break point to be consumed in GDB. The second way only uses the debugger and some internal mono calls.

### First Way - The "long" way
In order to break on a Mono component I need to have a way to set a break point as it's symbols won't be valid in GDB. When I first started hacking around I decided to use the `System.Diagnostics.Debugger.Break()` method to insert a break point. In fact if you read the Mono page on [debugging][monodebugpage], they mention just that. The only problem here is I'd get a SIGTRACE sent back to the console and it would throw some onerous errors sometimes. But, I was more concerned with debugging the issue at the time so I went that direction.

I added the command to the following file `/mono/mcs/class/corlib/System.Runtime.Remoting.Messaging/AsyncResult.cs` in the constructor that I found. ***The link to the source is in the previous section near the `pool_queue` paragraph.*** Here is what my code looked like after.

~~~Csharp
namespace System.Runtime.Remoting.Messaging {
  public class AsyncResult : IAsyncResult, IMessageSink {
    internal AsyncResult (WaitCallback cb, object state, bool capture_context)
    {
      System.Diagnostics.Debugger.Break();
      async_state = state;
      async_delegate = cb;
      if (capture_context)
        current = ExecutionContext.Capture ();
    }
  }
}
~~~

Of course, I had to recompile Mono. This takes some time, and if you make a change and forget to add a line terminator or what have you, the compile process will complain and you'll have to start over again. Personally I ended up calling `make clean` **A LOT** to push in the new changes each time. Plus, did I mention it takes a while?

All the particulars aside, when my application executed I could see all instances of when AsyncResult was instantiated. I restarted the application and found the following stack trace using `mono_stack`.

~~~
(gdb) mono_stack
"<unnamed thread>" tid=0x0x7ffff7fe97c0 this=0x0x7ffff7f6c010 thread handle 0x403 state : not waiting owns ()
  at <unknown> <0xffffffff>
  at (wrapper managed-to-native) object.__icall_wrapper_mono_debugger_agent_user_break () <0xffffffff>
  at System.Runtime.Remoting.Messaging.AsyncResult..ctor (System.Threading.WaitCallback,object,bool) <0x00036>
  at System.Threading.ThreadPool.QueueWorkItem (System.Threading.WaitCallback,object) <0x00030>
  at System.Threading.Tasks.TpScheduler.QueueTask (System.Threading.Tasks.Task) <0x000f1>
  at System.Threading.Tasks.Task.Schedule (bool) <0x0004b>
  at System.Threading.Tasks.Task.Start (System.Threading.Tasks.TaskScheduler) <0x000be>
  at System.Threading.Tasks.TaskFactory.StartNew (System.Action,System.Threading.CancellationToken,System.Threading.Tasks.TaskCreationOptions,System.Threading.Tasks.TaskScheduler) <0x00082>
  at System.Threading.Tasks.Task.Run (System.Action,System.Threading.CancellationToken) <0x00079>
  at System.Threading.Tasks.Task.Run (System.Action) <0x0001e>
  at Xunit.Sdk.TestFrameworkDiscoverer.Find (bool,Xunit.Abstractions.IMessageSink,Xunit.Abstractions.ITestFrameworkDiscoveryOptions) <0x001a2>
  at Xunit.Xunit2Discoverer.Find (bool,Xunit.Abstractions.IMessageSink,Xunit.Abstractions.ITestFrameworkDiscoveryOptions) <0x0003e>
  at Xunit.XunitFrontController.Find (bool,Xunit.Abstractions.IMessageSink,Xunit.Abstractions.ITestFrameworkDiscoveryOptions) <0x0003c>
  at Xunit.Runner.AspNet.Program.ExecuteAssembly (object,string,Xunit.XunitProjectAssembly,bool,bool,bool,System.Nullable`1<bool>,System.Nullable`1<int>,Xunit.XunitFilters,bool,bool,System.Collections.Generic.IReadOnlyList`1<string>) <0x0064f>
  at Xunit.Runner.AspNet.Program.RunProject (string,Xunit.XunitProject,bool,bool,System.Nullable`1<bool>,System.Nullable`1<bool>,System.Nullable`1<int>,bool,bool,System.Collections.Generic.IReadOnlyList`1<string>) <0x0080f>
  at Xunit.Runner.AspNet.Program.Main (string[]) <0x0047f>

<<<REMOVED REFLECTION AND DNX LINES FOR CLARITY>>>
~~~

This was the very first breakpoint hit and the first trace that came back. I removed some of the other lines as I was more concerned about who created the AsyncResult and how. The last item before the hand-off to our Task library was [Xunit.Sdk.TestFrameworkDiscoverer.Find][frameworkdiscover]. In this method we can see that we're calling a Task.Run(). As we found out before, all Task methods end up going through the TaskFactory which will use the ThreadPool. Which, of course, smashes the EC.

So now we have who is causing this issue to propagate up the stack. Looks like it was xUnit after all. But, before you get out your pitchforks and chase down the contributors to xUnit, you should realize that this problem is because of Mono and it's implementation of thread pooling.

Now that we found the issue this way. Let me share another way to find it that does not require hacking of the Mono framework.

### Second Way - The "better" way
As I mentioned I started down the "long" path and it got me where I needed to be. But, it left me in a bad spot of having to go back and hack the Mono source code each time I wanted to explore a new area. As you can imagine, this blog post---while long---is cutting out a lot of the in-between information and just presenting the "gems."

Unfortunately if you've looked at any back traces in GDB you will only find addresses and a few symbols here and there. For example:

~~~
(gdb) bt
#0  0x0000000040352e46 in ?? ()
#1  0x00007ffff61a72c0 in ?? ()
#2  0x00007ffff61a7298 in ?? ()
#3  0x000000004001e470 in ?? ()
#4  0x00007ffff61a7380 in ?? ()
#5  0x00007ffff61a7380 in ?? ()
#6  0x00007fffffffd3f8 in ?? ()
#7  0x0000000040352df0 in ?? ()
#8  0x00007fffffffce70 in ?? ()
#9  0x00007fffffffcd40 in ?? ()
#10 0x00007ffff499af3b in System.Threading.ThreadPool:QueueWorkItem (callBack=..., state=0x7ffff61a7380)
#11 0x00007ffff49ce8e2 in System.Threading.Tasks.TpScheduler:QueueTask (this=<optimized out>, task=...)
#12 0x00007ffff49b4b2c in System.Threading.Tasks.Task:Schedule (this=..., throwException=true)
#13 0x00007ffff49b3f4f in System.Threading.Tasks.Task:Start (this=..., scheduler=...)
#14 0x00007ffff49ad19e in System.Threading.Tasks.TaskFactory:StartNew<TResult> (this=..., function=..., cancellationToken=0,
    creationOptions=(unknown: -166038656), scheduler=...)
#15 0x00007ffff49ad040 in System.Threading.Tasks.TaskFactory:StartNew<TResult> (this=..., function=...)
#16 0x00000000403529d7 in ?? ()
#17 0x0000000002976560 in ?? ()
#18 0x0000000000000000 in ?? ()
~~~

This can be a bit hard to read so you can turn to `mono_backtrace <number>` to get a better call stack. This will fill in the blanks for a few things like the call wrappers and some other native transitions.

~~~
(gdb) mono_backtrace 20
#0 0x40352e46 in  (wrapper managed-to-native) System.Threading.ThreadPool:pool_queue (System.Runtime.Remoting.Messa
#1  0x00007ffff61a72c0 in ?? ()
#2  0x00007ffff61a7298 in ?? ()
#3 0x4001e470 in  (wrapper runtime-invoke) object:runtime_invoke_void__this__ (object,intptr,intptr,intptr) + 0x0 (
#4  0x00007ffff61a7380 in ?? ()
#5  0x00007ffff61a7380 in ?? ()
#6  0x00007fffffffd3f8 in ?? ()
#7  0x0000000040352df0 in ?? ()
#8  0x00007fffffffce70 in ?? ()
#9  0x00007fffffffcd40 in ?? ()
#10 0x7ffff499af3b in  System.Threading.ThreadPool:QueueWorkItem (System.Threading.WaitCallback,object) + 0x3b (0x7
#11 0x7ffff49ce8e2 in  System.Threading.Tasks.TpScheduler:QueueTask (System.Threading.Tasks.Task) + 0xf2 (0x7ffff49
#12 0x7ffff49b4b2c in  System.Threading.Tasks.Task:Schedule (bool) + 0x4c (0x7ffff49b4ae0 0x7ffff49b4c02) [0x9cf4c0
#13 0x7ffff49b3f4f in  System.Threading.Tasks.Task:Start (System.Threading.Tasks.TaskScheduler) + 0xbf (0x7ffff49b3
#14 0x7ffff49ad19e in  System.Threading.Tasks.TaskFactory:StartNew<TResult> (System.Func`1<TResult>,System.Threadin0 0x7ffff49ad1aa) [0x9cf4c0 - dnx.mono.managed.dll]
#15 0x7ffff49ad040 in  System.Threading.Tasks.TaskFactory:StartNew<TResult> (System.Func`1<TResult>) + 0x60 (0x7fff
#16 0x403529d7 in  Program:Main () + 0x117 (0x403528c0 0x40352c48) [0x9cf4c0 - dnx.mono.managed.dll]
#17 0x0000000002976560 in ?? ()
#18 0x0000000000000000 in ?? ()
~~~

In order to set a break point in Mono we can use the `mono_debugger_insert_breakpoint` method exposed in [debug-mini.c][debugmini]. If you follow that link you will notice that it says to remove that call from the public API. While this post may be relevant for a better part of 2015, who knows when it will stop. An example of how to use this is below. However this example does not produce the desired effect that I want. It does set a breakpoint, but not on the method I asked it to. The parameters are simply the full method signature with namespace (optional) and parameters (also optional), and a boolean flag to indicate the namespace is being used.

~~~
call mono_debugger_insert_breakpoint("System.Runtime.Remoting.Messaging.AsyncResult:.ctor (System.Threading.WaitCallback,object,bool)", 1)
~~~

There is a better, albeit slightly more involved, way of setting a breakpoint using the mono APIs directly. This involves getting the corlib image, assembly and ultimately the class and method. Once we have all of that we can call the JIT to compile the method and return our new instruction pointer. I will walk this script line by line and explain the APIs. You will see that the Mono developers were not shy in using long descriptive names when designing the API.

~~~
(gdb) set $image = mono_get_corlib ()
(gdb) set $klassAsync = mono_class_from_name($image, "System.Runtime.Remoting.Messaging", "AsyncResult")
(gdb) set $meth = mono_class_get_method_from_name ( $klassAsync, ".ctor", 3)
(gdb) set $jit = mono_jit_compile_method($meth)
(gdb) b *$jit
Breakpoint 1 at 0x7ffff4a8b9c0: file ~/mono/mcs/class/corlib/System.Runtime.Remoting.Messaging/AsyncResult.cs, line 70.
~~~

~~~
set $image = mono_get_corlib ()
~~~

This line gets the image from the corlib assembly and sets it to variable `$image`.

~~~
set $klassAsync = mono_class_from_name($image, "System.Runtime.Remoting.Messaging", "AsyncResult")
~~~

Using the newly returned `$image` variable, we are able to get a pointer to the `MonoClass` by passing in the Namespace `System.Runtime.Remoting.Messaging` and the class name `AsyncResult`. This instance of `MonoClass` is stored in the `$klassAsync`. **This method  is case sensitive**

~~~
set $meth = mono_class_get_method_from_name ( $klassAsync, ".ctor", 3)
~~~

Now that we have the class (`$klassAsync`) we can get a specific `MonoMethod` pointer from this class, including the constructor `.ctor`. The integer at the end specifies how many parameters are in the method's signature. If you're thinking ahead, you might wonder what happens when a method is overloaded with the exact same number of parameters? Well in this case the first one wins. I will go over how to enumerate these in another blog post. **This method  is case sensitive**

~~~
set $jit = mono_jit_compile_method($meth)
~~~

In order to get the actual instruction pointer we need to first try to compile the method. Depending on when you try to set your break points your target method may not have been JITted yet. We pass the `$meth` variable which holds our `MonoMethod` instance.

~~~
break *$jit
~~~

This last method sets the break point for GDB. When using a raw address you need to tell GDB it's a pointer. Otherwise it does not know how to dereference the address space.

It's important to note that we're breaking before the debugger has had a chance to set up the parameters. Let's take a look at the disassembly of this simple method to see if there is a better place to break.

~~~
gdb$ disas $jit
Dump of assembler code for function System.Runtime.Remoting.Messaging.AsyncResult:.ctor:
   0x00007ffff4a8b9c0 <+0>:     sub    rsp,0x28                            # setup stack
   0x00007ffff4a8b9c4 <+4>:     mov    QWORD PTR [rsp],r12                 # move TaskFactory object to stack
   0x00007ffff4a8b9c8 <+8>:     mov    r12,rdi                             # load this pointer
   0x00007ffff4a8b9cb <+11>:    mov    QWORD PTR [rsp+0x8],rsi             # move WaitCallBack to stack
   0x00007ffff4a8b9d0 <+16>:    mov    QWORD PTR [rsp+0x10],rdx            # move state object to stack
   0x00007ffff4a8b9d5 <+21>:    mov    QWORD PTR [rsp+0x18],rcx            # move capture_context to stack
   0x00007ffff4a8b9da <+26>:    mov    rax,rdx                             # move state (Threading.Task) to RAX
   0x00007ffff4a8b9dd <+29>:    mov    QWORD PTR [r12+0x10],rax            # set async_state to state
   0x00007ffff4a8b9e2 <+34>:    lea    rcx,[r12+0x10]                      # load async_state PTR into rcx
   0x00007ffff4a8b9e7 <+39>:    shr    ecx,0x9                             # shift right by 9 places
   0x00007ffff4a8b9ea <+42>:    and    rcx,0x7fffff                        # Mersenne prime 23 (hashmap?)
   0x00007ffff4a8b9f1 <+49>:    mov    rdx,QWORD PTR [rip+0x444700]        # 0x7ffff4ed00f8 <mono_aot_mscorlib_got+16>
   0x00007ffff4a8b9f8 <+56>:    add    rcx,rdx                             # locate final address space
   0x00007ffff4a8b9fb <+59>:    mov    BYTE PTR [rcx],0x1                  # set hashmap address to 0x1
   0x00007ffff4a8b9fe <+62>:    mov    rax,QWORD PTR [rsp+0x8]
   0x00007ffff4a8ba03 <+67>:    mov    QWORD PTR [r12+0x20],rax
   0x00007ffff4a8ba08 <+72>:    lea    rcx,[r12+0x20]
   0x00007ffff4a8ba0d <+77>:    shr    ecx,0x9
   0x00007ffff4a8ba10 <+80>:    and    rcx,0x7fffff
   0x00007ffff4a8ba17 <+87>:    mov    rdx,QWORD PTR [rip+0x4446da]        # 0x7ffff4ed00f8 <mono_aot_mscorlib_got+16>
   0x00007ffff4a8ba1e <+94>:    add    rcx,rdx
   0x00007ffff4a8ba21 <+97>:    mov    BYTE PTR [rcx],0x1                  # same logic for async_delegate
   0x00007ffff4a8ba24 <+100>:   movzx  eax,BYTE PTR [rsp+0x18]             # move capture_context into eax (zero extended)
   0x00007ffff4a8ba29 <+105>:   test   eax,eax                             # is it 1?
   0x00007ffff4a8ba2b <+107>:   je     0x7ffff4a8ba57                      # if not jump to <AsyncResult:.ctor+151>
   0x00007ffff4a8ba31 <+113>:   call   0x7ffff4b62a30                      # else call <ExecutionContext:Capture>
   0x00007ffff4a8ba36 <+118>:   mov    QWORD PTR [r12+0x48],rax
   0x00007ffff4a8ba3b <+123>:   lea    rcx,[r12+0x48]
   0x00007ffff4a8ba40 <+128>:   shr    ecx,0x9
   0x00007ffff4a8ba43 <+131>:   and    rcx,0x7fffff
   0x00007ffff4a8ba4a <+138>:   mov    rdx,QWORD PTR [rip+0x4446a7]        # 0x7ffff4ed00f8 <mono_aot_mscorlib_got+16>
   0x00007ffff4a8ba51 <+145>:   add    rcx,rdx
   0x00007ffff4a8ba54 <+148>:   mov    BYTE PTR [rcx],0x1
   0x00007ffff4a8ba57 <+151>:   mov    r12,QWORD PTR [rsp]
   0x00007ffff4a8ba5b <+155>:   add    rsp,0x28
   0x00007ffff4a8ba5f <+159>:   ret
End of assembler dump.
~~~

If you look at instruction `0x00007ffff4a8ba29 <+105>:   test   eax,eax                             # is it 1?` you will notice this is taking in the `capture_context` variable and checking it for true. So, this is a great place to stop our execution to inspect the variables as they would be set by now. And for good measure we should also set a breakpoint at `0x00007ffff4a8ba5f <+159>:   ret` to capture what's happening at the end of the constructor.

~~~
gdb$ break *0x00007ffff4a8ba29
Breakpoint 2 at 0x7ffff4a8ba29: file /home/jldgit/mono/mcs/class/corlib/System.Runtime.Remoting.Messaging/AsyncResult.cs, line 143.

gdb$ break *0x00007ffff4a8ba5f
Breakpoint 3 at 0x7ffff4a8ba5f: file /home/jldgit/mono/mcs/class/corlib/System.Runtime.Remoting.Messaging/AsyncResult.cs, line 144.

gdb$ c
Continuing.

Breakpoint 1, System.Runtime.Remoting.Messaging.AsyncResult:.ctor (this=..., cb=..., state=0x7ffff68012d8, capture_context=0xd8) at /home/jldgit/mono/mcs/class/corlib/System.Runtime.Remoting.Messaging/AsyncResult.cs:70
70              internal AsyncResult (WaitCallback cb, object state, bool capture_context)

gdb$ c
Continuing.

Breakpoint 2, System.Runtime.Remoting.Messaging.AsyncResult:.ctor (this=..., cb=..., state=0x7ffff68012d8, capture_context=0x0) at /home/jldgit/mono/mcs/class/corlib/System.Runtime.Remoting.Messaging/AsyncResult.cs:143
143

gdb$ p $rax
$1 = 0x0  <<<<< capture_context is FALSE

gdb$ c
Continuing.

Breakpoint 3, 0x00007ffff4a8ba5f in System.Runtime.Remoting.Messaging.AsyncResult:.ctor (this=..., cb=..., state=0x7ffff68012d8, capture_context=0xd8) at /home/jldgit/mono/mcs/class/corlib/System.Runtime.Remoting.Messaging/AsyncResult.cs:144
144             public virtual void SetMessageCtrl (IMessageCtrl mc)
gdb$ call mono_object_describe_fields ($rdi)
At 0x7ffff6801ee8 (ofs: 16) async_state: System.Threading.Tasks.Task`1 object at 0x7ffff68012d8 (klass: 0xa2ba68)
At 0x7ffff6801ef0 (ofs: 24) handle: (null)
At 0x7ffff6801ef8 (ofs: 32) async_delegate: System.Threading.WaitCallback object at 0x7ffff6801e70 (klass: 0xa22798)
At 0x7ffff6801f00 (ofs: 40) data: (nil)
At 0x7ffff6801f08 (ofs: 48) object_data: (null)
At 0x7ffff6801f10 (ofs: 56) sync_completed: False (0)
At 0x7ffff6801f11 (ofs: 57) completed: False (0)
At 0x7ffff6801f12 (ofs: 58) endinvoke_called: False (0)
At 0x7ffff6801f18 (ofs: 64) async_callback: (null)
At 0x7ffff6801f20 (ofs: 72) current: (null)
At 0x7ffff6801f28 (ofs: 80) original: (null)
At 0x7ffff6801f30 (ofs: 88) add_time: 0
At 0x7ffff6801f38 (ofs: 96) call_message: (null)
At 0x7ffff6801f40 (ofs: 104) message_ctrl: (null)
At 0x7ffff6801f48 (ofs: 112) reply_message: (null)
~~~

At the end of the method execution you can see that only a couple of fields are set in the AsyncResult. If you know your calling conventions you would know that $rdi is the location for the "this" pointer. If you didn't know that, you do now. I can pass the $rdi register into `mono_object_describe_fields` to get all of the fields and their values. The most important ones `current` and `original` are the ExecutionContext states; and both of these are NULL. So, as we already know we are not capturing the EC.

## Workarounds
1. **Use ThreadPool.QueueUserWorkItem()**
  - This creates a proper context copy
2. **Implement your own scheduler and create your own threads**
  - xUnit does this
3. **Upgrade and compile the bleeding edge version of Mono and set MONO_THREADPOOL="microsoft"**
  - The latest version supports the native thread pool
4. **Create your own context and pass it along as a parameter to your Tasks**
  - Simple enough, but requires a lot of extra work to make sure you're capturing what you need.
5. **Hack the AsyncResult constructors to always copy the EC**
  - **DON'T DO THIS** as it may cause unforeseen issues.


## Wrapping Up
This bug is kinda of damning for using CallContext across threads as you would expect. The Mono team is aware of this based on [this bug report][bug] I filed. As I mentioned there are a couple of workarounds, but none of them are easy or "drop-in" replacements. I plan on going over a few of these Mono scripts and will create a GitHub repository.

[monorepo]: https://github.com/mono/mono
[xunit]: http://xunit.github.io/
[aspnethosting]: https://github.com/aspnet/Hosting
[aspnetdnx]: https://github.com/aspnet/Home#optimistic-dnvm-2
[xunitissue]: https://github.com/xunit/aspnet.xunit/issues/6
[monodebug]: http://www.mono-project.com/docs/debug+profile/debug/
[gdb]: https://www.gnu.org/software/gdb/
[bradw]: https://twitter.com/bradwilson
[dfowl]: https://twitter.com/davidfowl
[bug]: https://bugzilla.xamarin.com/show_bug.cgi?id=28828
[execon]: http://referencesource.microsoft.com/#mscorlib/system/threading/executioncontext.cs,5a5eb57d2b341635
[smtst]: http://io.smashthestack.org/
[alexk]: https://github.com/akoeplinger
[dnxline31]: https://github.com/aspnet/Hosting/blob/77e2dc263f11655312d4c73bb8e22d7b6254d485/src/Microsoft.AspNet.Hosting/Internal/RootHostingServiceCollectionInitializer.cs#L31
[splocator]: https://github.com/aspnet/dnx/blob/1cd7c16acf86f202b260e3da5f200f43967a4be2/src/dnx.host/ServiceProviderLocator.cs
[callcontextlocator]: https://github.com/aspnet/dnx/blob/1cd7c16acf86f202b260e3da5f200f43967a4be2/src/dnx.host/Bootstrapper.cs#L70
[cc]: https://msdn.microsoft.com/en-us/library/System.Runtime.Remoting.Messaging.CallContext(v=vs.110).aspx
[execontext]: https://msdn.microsoft.com/en-us/library/system.threading.executioncontext%28v=vs.110%29.aspx
[logiccall]: https://msdn.microsoft.com/en-us/library/system.runtime.remoting.messaging.logicalcallcontext%28v=vs.110%29.aspx
[startnew]: https://msdn.microsoft.com/en-us/library/dd321439(v=vs.110).aspx
[tpsched]: https://github.com/mono/mono/blob/mono-3.12.0-tls-hotfix/mcs/class/corlib/System.Threading.Tasks/TpScheduler.cs
[asyncresult]: https://github.com/mono/mono/blob/mono-3.12.0-branch/mcs/class/corlib/System.Runtime.Remoting.Messaging/AsyncResult.cs
[frameworkdiscover]: https://github.com/xunit/xunit/blob/61102c0eeddf6f5ffa33933bc2f598c52958f8df/src/xunit.execution/Sdk/Frameworks/TestFrameworkDiscoverer.cs#L89
[debugmini]: https://github.com/mono/mono/blob/mono-3.12.0-branch/mono/mini/debug-mini.c#L714
[pt1]: http://www.debugthings.com/2015/04/07/debugging-vnext-mono/
[monodebugpage]: http://www.mono-project.com/docs/debug+profile/debug/#triggering-the-debugger
