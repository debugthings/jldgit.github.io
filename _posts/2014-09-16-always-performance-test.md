---
layout: post
title: Always Performance Test!
excerpt: While thumbing through Twitter I ran across an [article][cmpblog] written by [@grabnerandi][grabtwit] about a company not being able to load test a change for dependency injection. I can't tell you how many times in my job that performance testing has been brushed over for speed to market.
---

While thumbing through Twitter I ran across an [article][cmpblog] written by [@grabnerandi][grabtwit] about a company not being able to load test a change for dependency injection. I can't tell you how many times in my job that performance testing has been brushed over for speed to market.

Look, I get it. **Money**. There, I said it. Most of the time the driving factor for not doing something you should be disciplined about is the bottom line. While I get it I don't like it. I have had to inject myself into a release process to be the harbinger of doom. I try not to get all "the sky is falling," but in reality it could.

I know, I know. **Time**. Right after money, but usually goes hand-in-hand, is time. This excuse gets even the best of us. Does anyone have time? No. Do we do it anyway? Sometimes. I'd like to say that while being the performance testing and DevOps advocate that I just ooze availability. But, I don't. Just like everyone else I have constraints.

What does it mean? Money + Time = **Effort*. It always comes down to effort. This is the way to merge both time and money into one shortsighted mess. The effort required to test is usually deemed greater than the effort to just put it in. This is the death bringer of many of once stable applications.

##Story Time
A while ago our team was asked to performance test a new web application. We got our grubby little hands on it we shredded the code and the database layout. Only to be met with "No one runs it like that." Apparently we were "no one." As a good performance testing team we provided solutions to the problems and the application team would make sure they went in. 

Ever since then, just about every dot release (x.1, x.2, etc.) has been tested by our team. A lot of things change from version to version, but we now had enough experience with the style of the developers and could keep up with the changes. Each time we found one or two things, but we rarely had major problems like we did in the first few releases. Our performance results always came back with positive results.

Fast forward about 2 years. Multiple major and minor releases have come and went without issue. The application team had requested a new feature a few months ago and it was now ready for deployment. The change was "small" and carried only a couple of new screens. *Our team never even heard about it.*

On go live, the applications started out fine but would always start performing poorly around 11am. This happened to be the peak time the application was used. A recycle would happen and the problem would go away for an hour and happen again. This process was repeated daily for a week. The application team was working with the vendor to find a solution.

Our team got involved and we decided to take a look at what was going on. Since the application didn't have any APM tools on it we went the traditional route and started monitoring performance counters. We went back in time and looked at the historical data. We could see that CPU was definitely becoming saturated. A bit deeper inspection into the .NET counters revealed that the [# of Induced GC][induced] counter was going up at a steady rate.

We compared the counters to a date just before the go-live and to no one's surprise the issue was not there. We went back and performance tested the new application with existing scripts (we did not include the new screens) and the issue was still there. This showed there was something wrong in something else besides the proposed "only changes."

Luckily we had [dynaTrace][dt] at our disposal in our lower life cycle and we were able to quickly find the offending code. Analysis from the vendor showed a junior developer pulled from a previous branch that had a bug that was fixed long ago. A patch was issued that day by the vendor. We performance tested it. :)

##Lesson
###Always Performance Test!

Considering all of the time, money, and effort (yes all three) wasted on: deploying bad code, end user impact, and time to resolution. It might have been quicker, easier, and cheaper to performance test this code.

If you're ever in a situation where one of these big three come up you should always make a statement, on record, about the need to performance test. If you are silent it's not a great place to be if someone asks why it was never done. Being in DevOps you have just as much of a responsibility and burden to ensure application performance is as high as possible.

[grabtwit]: https://twitter.com/grabnerandi
[cmpblog]: http://apmblog.compuware.com/2014/09/16/detecting-bad-deployments-resource-impact-response-time-hotspot-garbage-collection/
[induced]: http://msdn.microsoft.com/en-us/library/x2tyfybc(v=vs.110).aspx
[dt]: http://www.compuware.com/en_us/application-performance-management.html