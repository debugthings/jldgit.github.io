---
layout: post
title: Simple Beginnings - ChainsAPM
tags:
- programming
- debugging
- procrastination
- chainsapm
---
In my last post I prattle on about the normal hang ups that any software developer has. I don't have time for this, I would rather be doing that... Now that, *that's* over I can get back to doing what I enjoy doing. Breaking things and making really terrible design decisions. Today I'm going to bore you with some background of my pet project [ChainsAPM][chains].

##Simple Beginnings
A few years ago I got interested in how our APM tools at work actually work. After some research and questioning the folks in that space I found out. Soon after that I wanted to make my own. Fast forward to last year (2014) and you'll find me reading a bunch of stuff on [Dave Broman's blog][davebro]. If you browse the blog you'll notice that most of the articles are well over 5 years old and some are 10 years old.

Turns out profiling, while extremely useful, is not very popular. If you do a search you will find a lot of intro to profiling and a wasteland of projects like mine in various states of completeness. Again Dave shines through by providing the [CLRProfiler][clrprofiler]. You can find the source code for all of this and start making things.

In fact this is where I got my start. 

###What is my project?
Simply put, it's an open source APM tool based on an IL rewriting profiler. Right now (and probably for a long time) it will focus on the .NET development stack.

###Aren't there already tools...
There are actually some great tools out there that dominate this space. Some of my favorites are [Glimpse][glimpse], [AppNeta][appneta] and [New Relic][newrelic].

###What can it do?
Right now it's in the simplest mode possible. It's adding a few entry/exit instrumentation points and sending those over the network to a backend server. This backend server takes this data and will spit out a stack trace with timings to a log folder--it even adds spaces to simulate nesting!

###Is that it?
Yup.

##What's Next?
Now that I've actually written something down, I probably need to actually do some work. I've cleared enough of a path to just start doing things. I have a lot of things I did in this that will make for some interesting reading. My first post will be on the simple parts of IL rewriting and how that works.

Keep an eye open on the blog since I will be doing quite a bit in the coming months.


[davebro]: http://blogs.msdn.com/b/davbr/
[clrprofiler]: https://clrprofiler.codeplex.com/
[chains]: https://github.com/chainsapm/chainsapm
[glimpse]: http://getglimpse.com/
[appneta]: http://www.appneta.com/
[newrelic]: http://newrelic.com/
