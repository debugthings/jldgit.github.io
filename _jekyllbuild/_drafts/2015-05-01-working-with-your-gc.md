---
layout: post
title: Working with your Garbage Collector and ArraySegments<>
tags:
- development
- performance
- garbage collector
---
Sometime late last year I had an idea to write a [CLR profiler][chainsapm] and perform the work of some great applications like AppNeta, dynaTrace, AppDynamics and the like. Part of my requirements were to have a low latency network transfer between the .NET application (monitor/agent) and the intermediate communication device (aggregator/collector). When I ran my application under light load I never experienced any issues. But, when I tried to scale up my throughput I quickly learned some of the pitfalls of a managed language and sub-optimal programming.

##TL;DR
If you're looking for information about 1GCSettings.LatencyMode like Batch, LowLatency and SustainedLowLatency skip to the **Garbage Collector Tuning** section. If you like rambling narratives, read on.

## Thoughts
First of all let me say that developing a profiler that is efficient and non-blocking is difficult at best. Second of all, to make it scale can be challenging. Depending on what technology you invest in can set the tone for a lot of things such as throughput and machine footprint. The following list is purely subjective but commonly agreed upon by managed Windows developers.

* C --- Realtime, Small, Few Language Features, Mostly Portable, Long Development Time*
* C++ --- Realtime, Robust, Better Language Features, Mostly Portable, Long Development Time*
* .NET --- Fast, Robust, Excellent Language Features, Somewhat Portable, Quick Development Time*
* Java --- Fast, Robust, Great Language Features, Highly Portable, Quick Development Time*

>* Depending on your experience/proficiency, this will vary. By language features I mean things like API and syntax that make complicated tasks simple. For example async/await in .NET.

## My Problem
With this in mind let's consider what I am trying to do here. I want hundreds of applications talking to my end services and I want to be as realtime as possible with the information. By "realtime" I mean within an acceptable threshold, so under 3 seconds is my magical number. That means I have to send an event from my agent to my aggregator and off to the server to be processed. Durning my calculations I figured I'd be sending close to 5,000 to 6,000 events for a busy system, so if I have 100 clients it's an easy 500,000 events to process.

When I started working out the network protocol for events I landed on a simple format that consisted of **\[byte length\]\[command number\]\[data\]\[terminator\]**. And wrapping that I had a byte length and terminator for batched messages. That way I could spend less time on the agent with I/O. So, this meant that I'd have fragmented packets coming in more often depending on the number of events and the size of the data.

When it came time to process the messages on the server side I'd ***copy*** around the chunks of the byte arrays and process the data from there. If you've ever worked with .NET and a lot of allocations you would know right away that this is the root cause of all of my problems. When I used existing profiling tools I noticed a lot of my time was spent in heap allocation. Most of the time this was because of something like `byte[] packet = new byte[packetsize];` when looping through the big chunks of data.

To make the application fast, scalable and responsive I used asynchronous everything. Async I/O, Timers, Thread Pools, async/await---you name it. This brought in a whole slew of other "thought provoking" problems that I will talk about in the later sections.

## How I Tested
When testing at a semi-large scale (100 clients) I'd noticed that the time to process the same amount of messages would swing wildly. My testing rig was my Core i7 laptop as the server and my Core i7 desktop emulating 150 clients. My test consisted of random packets at random sizes. I also sent canary messages with timestamps that would be logged to a text file (this was batched so it didn't cause issues).

All of these allocations were causing high GC and my application would pause every 1 or 2 seconds. This would cause work to queue up and I'd eventually see my canary times rise and they'd end up at 2 seconds consistently at my highest load time. I was within my self imposed SLA, but in this test my messages weren't being processed into persisted (database) data.

This isn't good. As soon as I add something else to the backend of the chain, my end processing times could be well beyond acceptable.

## Garbage Collector Tuning
So, as I hinted in the first section and the title of the post, Garbage Collection was my biggest enemy. Before making any large code changes I wanted to see if there was a way to tune the garbage collector. I know this sounds counter intuitive to all of the other sources out there that say **DON'T TOUCH THE GC** well, in most cases that's a correct statement. You really don't have to mess with it. But, if you do a lot of allocations or if you have a high rate of work you can't have suspended while it's processing then you need to do it.

### Registering for a Full GC
My application uses timers and async/await events to pull data from the network. I noticed I was having a problem with queueing of events when the GC was suspending every few seconds. All of my in-flight timers were getting thrashed and I'd be stuck waiting on an open completion port or a thread to become available. All the while some async iterator was chewing down through my byte structures. Again, I was copying a lot of data around so GCs were pretty frequent.

My first inkling was to see about reducing blocking GCs. As I started researching this topic I ran across the `GC.RegisterForFullGCNotification()` API. This allows you to find out when a blocking GC is about to occur and you can offload your data to another process. This seemed a bit complex, but I was curious about what would happen.

In my case I suspended all my timers, this allowed data to be buffered by the NIC and the OS and when it resumed I would get proper throughput.

### GC Latency Mode
Starting with .NET 3.5 you have had the option to set the latency mode for your garbage collector.

### GC Mode (Server or Workstation)
 On my development workstation under a Release configuration I noticed I wasn't in [server mode][gcserver]. After playing around with some of the latency settings and registering for notifications I

* .NET 4.0 Garbage Collection runs in Background for workstations by default.
* .NET 4.5 Garbage Collection runs in Background for both by default.

This setting had a pretty noticeable impact right away. My full GCs were happening less frequently and I'd be utilizing less memory for a sustained period of time. I was able to keep up with my clients. But as I turned up the volume I'd end up in the same boat. When a full GC would occur I'd end up going from 1.2 GB of committed memory to 6.0 GB almost instantly. This would trigger some low memory conditions and I'd start banging around between GCs again.

Even though I consider this a win for a 100 clients, I still had head room on both my client emulator and my laptop.

### GC Concurrency (Background or Concurrent)
Reading the documentation Microsoft explicitly states that Concurrent and Background are used interchangeably. However they are **NOT** interchangeable in terms of performance. Here is a simple breakdown of .NET GC settings.

**Server GC Explained**

* Before 4.0 only non concurrent GC was allowed, but was spread across multiple threads.
* In 4.0 concurrent GC was introduced and allowed threads to run while Gen 2 GCs were occurring. This behaves just like workstation concurrent.
* In 4.5 background GC was introduced.

||Server(C)|Server(BG)|Workstation(C)|Workstation(BG)|
|.NET 2.0| | |X| |
|.NET 3.0| | |X| |
|.NET 3.5| | |X| |
|.NET 4.0|X| |X|X|
|.NET 4.0|X|X|X|X|

At the time I started playing around with this I had done some tuning of my object allocations and didn't go back to see how this would have affected my application.





## ArraySegments and Allocation


[chainsapm]: https://github.com/chainsapm
[gcserver]: https://msdn.microsoft.com/en-us/library/vstudio/ms229357(v=vs.110).aspx
