---
layout: post
title: Time Flies! - Prepping for Code on the Beach
tags:
- speaking
- code on the beach
- application insights
---
I was looking back at my site for reference here at work and I noticed I haven't written anything for over a month now! So, as the title says, time flies. Plenty of things have been broken and fixed in the past month, so I'll be getting back to it soon. However, the past month or so, I've been devoting my free time at night to fully preparing for [Code on the Beach][cotb].

I will have a follow up post soon after this one that will put some extra context around the code in my upcoming talk. I'll make sure to both pin it on Twitter and link to it above. This seems like a good a time as any to give an abstract of the talk.

## Overview
I wanted to focus on setting up [Application Insights][appinsights] far in advance of actually releasing your application to production. In my day-to-day job I spend a great deal of time making sure an application will be monitored correctly once it's in PROD. Sometimes this works out well---and sometimes not. Part of the reason for this is because you can't know how your application will behave under load. As well you won't know all of the code paths until real people start exercising it.

- Adding Insights
  - Brand new Application
  - Existing Application
  - Using the SDK on VS2010 and VS2012
- Create Custom Measurements
  - Custom Dependencies
  - Custom Metrics
  - Web Page Metrics
- Creating and Running a Performance test in VSO
  - Jump start for Web Performance Test
  - Jump start for Load Test
  - Running the test on-line
- Pulling it All Together
  - Wash, rinse, repeat (iterative methodology)
  - Show the resulting dashboards
  - Export Reports

## Come on Out!
This topic will be pretty packed with Demos. I have just a few blurbs to talk about before each demo, but I wanted to get the ideas flowing with folks who may have not seen a load test or APM tool before.

Plus, I love to talk about this stuff. Do you have a complex problem and wonder if you can solve it with a load test? Application Insights? WinDbg? VooDoo? Seriously, let's talk about it. Hope to see you there!

[appinsights]: http://azure.microsoft.com/en-us/services/application-insights/
[cotb]: https://www.codeonthebeach.com/
