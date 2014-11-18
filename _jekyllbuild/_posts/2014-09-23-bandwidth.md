---
layout: post
title: Bandwidth. It's not free...
---
Usually when I performance test internal applications I don't consider bandwidth unless I know we're doing something irrational like transferring multi gigabyte files all the time. And even then I only consider it if we're crossing a WAN or some other "slow" link between sites. But, every now and then there is a project that runs over the Internet and it is very data intensive. And, a lot of that data is out of the control of the developers (images, 3rd party libraries, fonts).

It's a given that it will cost you money, but how much? A dedicated link can run anywhere from $100 a month on a broadband backbone, all the way up to $50,000 for Gbit Level3 Fiber. How much money you want to spend on your connection depends on the amount of content you need to control.

**You may find that if you do some tuning on bandwidth you can save your self hundreds of thousands of dollars per year.** You read that right, **hundreds of thousands of dollars**.

###Background
Recently I was working on a launch of a new website and the main concern was hitting our requests per second target for daily use and what a holiday spike would look like. This is how things normally go. It's easy. You drive load into the system until it eventually cracks. You suggest a fix. It gets implemented. Repeat.

So, here we are about 3 weeks out from our go-live date. We spent months on tuning the system to run as lean as possible. We turned logging down. Compression on. SSL offloading. SQL tuning. Everything. We were ready.

Yet, while doing all of this there wasn't much visual content on the site. It wasn't until this point in the project that "real" images and verbiage were coming in. When it did our bandwidth consumption jumped considerably. I don't mean 2 times; 10 times. **TEN TIMES**. We had to find out just how much data we were pushing, and we needed to know what it looked like from outside of the datacenter.

###Bandwidth Estimation
Before we start running load tests willy nilly out on the open internet we need to do some math. Not hard math, but some fuzzy math to calculate our potential load. I will give some examples with a common website.

For this I always use [Fiddler][fiddler]. There are some great plugins that will help you determine impact of change as well. Here is an [overview][over] of what it can provide. These next few sections assume you're somewhat familiar with Fiddler. I will include a few small steps but nothing in-depth. This isn't a Fiddler tutorial.

When we first navigate to [www.microsoft.com][ms] we will see the total amount of requests that are sent over. We can see this by selecting all of the requests that make up a page. In this case the home page. I have trimmed off some extra data for brevity.

~~~ 
Request Count:   51
Unique Hosts:    14
Bytes Sent:      36,471		(headers:36,471; body:0)
Bytes Received:  884,345	(headers:27,698; body:856,647)

ACTUAL PERFORMANCE
--------------
Requests started at:		16:34:22.077
Responses completed at:		16:34:25.057
Sequence (clock) duration:	00:00:02.9801705
Aggregate Session duration:	00:00:06.823
DNS Lookup time:			1,295ms
TCP/IP Connect duration:	1,181ms

.. response codes snipped ...

RESPONSE BYTES (by Content-Type)
--------------
               image/jpg: 382,186
application/x-javascript: 184,279
application/octet-stream: 86,289
               image/png: 70,863
         text/javascript: 66,832
               text/html: 40,260
               ~headers~: 27,698
                text/css: 19,181
               image/gif: 6,757

... hosts and timing estimates removed ...
~~~ 

For my purposes a very important line was needed. In particular the amount of bytes. More over we need to convert this to bits.

~~~ 
Bytes Received:  884,345		(headers:27,698; body:856,647)
~~~ 

Armed with this information I could start calculating some of this fuzzy math. I knew that if we had 100Mbit of bandwidth and the majority of our users would get **about** the same speed then we can use this formula going forward. This generates a theoretical maximum.

~~~ 
((Bytes Received) * 8) / (Sequence (clock) duration) = effective bandwidth

(884,345B * 8b) / 2.98s = 2,374,080 = 2.4Mbit/sec

100Mbit/sec / 2.4Mbit/sec = 42 THEORETICAL simultaneous NEW page transfers in 3 seconds (14/sec)
~~~ 

In reality we more than likely won't be able to hit 42. If we kind of squint our eyes and do some estimating we will need to reduce the number of actual page transfers. I always use the 80% rule. So really we could do about 34 new page loads at one time and be safe.

Great. We have a number to shoot for. We're done right? Well, no. If you went to your management and said, we can handle 34 pages per second, you might get a sideways look and be asked to explain.

It may be more helpful to aggregate into minutes and even further translate that to users or sessions per minute. As you fuzz your numbers it may help make the overall point. Regardless of how fast the end user is there is a finite maximum number of pages that can be delivered in a finite amount of time.

So, what do you do next? 

###Deep Estimation
Once you have done your naive estimation, you need to follow up and employ due diligence. Try and flow through the heaviest use cases and do the same math. If there aren't any cases yet, make it up! Remember that what ever your QA team can't find a user will find the first time.

I believe that you have the same abilities. You, dear reader, can behave just like a user. Because, lets face it, you are a user deep in your soul. You order from Amazon, you poke around Ebay, you Google things wrong from time to time. Use this power. Embrace it. Go.

Once you identify the pages, the transfer times, and estimated mixtures you can stop right? No. You need to go a step further and start estimating your return users and how that will affect caching. You are caching aren't you?

###Caching Estimation
Ah, yes. If you forgot, most modern browsers will adhere to caching rules. You need to use this to your advantage. Especially if you have some idea of how many users will be return.

If we visit the same page(s) as before we can capture the same Fiddler statistics to get an idea of our cached content. If you look at the data below it looks as as if we have 20 times LESS data than before. So, in the naive approach we can transfer about 20 times the amount of page views when we have 100% return visitors. Here is an [excellent MSDN article][art] on HTTP performance using Fiddler; read it.

~~~ 
Request Count:   17
Unique Hosts:    9
Bytes Sent:      15,501		(headers:15,501; body:0)
Bytes Received:  48,860		(headers:5,252; body:43,608)

ACTUAL PERFORMANCE
--------------
Requests started at:		17:03:17.465
Responses completed at:		17:03:19.177
Sequence (clock) duration:	00:00:01.7120980
Aggregate Session duration:	00:00:02.368
DNS Lookup time:			121ms
TCP/IP Connect duration:	876ms

RESPONSE CODES
--------------
HTTP/200: 	14
HTTP/304: 	3

RESPONSE BYTES (by Content-Type)
--------------
               text/html: 40,143
               ~headers~: 5,252
application/x-javascript: 2,978
         text/javascript: 401
               image/gif: 86

~~~ 

In the real world you won't have that many return visitors. Depending on the type of requests you have (dynamic v. static) and what your business model is like (information or sales) you could be more in the camp of 30% to 50% return. You know your data best. I could offer some foolhardy estimates based on experience, but it would do you a disservice. Explore your data and know your numbers.

Now, lets take this data and apply some fuzz to it and see what our effective rate at load would be.

~~~ 
New users:
14 pages/sec * 60sec = 840pages/minute * 50% = 420

Return Users:
280 pages/sec * 60sec = 16800/minute * 50% = 8400

Total:
8820 pages per minute

Fuzzed number (80%):
7056 pages per minute

~~~ 

Now, this number sounds more like a enterprise level application. But, it seems kind of high.

###User Estimation
Our goal is to find out if we have enough bandwidth to support our day one user base. Here is an example of our test case:

**Actual Usage**

-  Normal Scenario
  -  5,000 Users 
  -  2 - 3 pages per session
  -  3,000 sessions per minute
  -  6,000 pages per minute
-  Mobile
  -  500 Users
  -  4 - 5 pages per session
  -  1,000 session per minute
  -  5,000 pages per minute

**Virtual Usage**

-  Normal Scenario
  -  1,000 virtual users
  -  50% Return Visitors
  -  3 - 5 pages per test
  -  2,000 test per minute
  -  6,000 pages per minute
-  Mobile
  -  200 virtual users
  -  40% Return Visitors
  -  4 - 5 pages per test
  -  1,000 tests per minute
  -  4,000 pages per minute

This test load simulated production traffic with less users than were reported on the site.  By sacrificing "actual" user load you can save some additional overhead of extraneous virtual users. This will come in handy later when you get to the bottom of the page.

###Caution
We now have a page goal, and our possible load pattern. I urge you to exercise caution here. If you were keeping up and doing the math yourself you probably noticed were doing somewhere around 2,600 requests per second. Even at 260 requests/sec per server your looking at 10 servers serving this web site. Is that too many, is it not enough? 

Don't get caught up in the theoretical maximums. It is in everyone's best interest to test as often as you can. Especially when you suggest a change, no matter how small. When in doubt, look at my previous blog post [Always Performance Test!][apt]

###Sanity Check
Now is the time to apply some best practices before you test. Before you go all out on an external test, here are some low hanging fruit that will improve your bandwidth.

- Caching
  	- Make use of the caching tab in Fiddler
- Static Resource Sizes
  	- Images
  	- CSS
  	- JS
- Page Sizes
  	- Static
  	- Dynamic
- Bundling
  	- Most web frameworks have a package that will bundle and minify
- Minification
	- If you can't bundle, you should minify
- Compression
  	- Above all else you should compress
- Content Delivery Network
  	- If all else fails, seriously consider this
  	- Some common libraries are CDN'd for free, like jQuery on Google for instance

###Can We Test Now?!
Yes. Go ahead and start putting together a plan to test from the outside. 

It's no secret that when you use a Microsoft product it will cost you. But, in this case, you can easily map out the amount of money you need to spend. I haven't used any other services that integrate so well with a tool set I'm familiar with. VSO, provided a great platform to test on. I was even able to bring that data back into my local load test database. No I'm not some shill recommending random products. It was genuinely a pleasant experience and I highly recommend it.

Knowing my goal allowed me to save a lot of money. The going rate for testing in the cloud at the time of this writing is $0.002 per user minute. For example:

~~~ 
1000 virtual users x 30 minutes = 30,000 virtual user minutes * $0.002 = $60
5000 virtual users x 30 minutes = 150,000 virtual user minutes * $0.002 = $300
5000 virtual users x 60 minutes = 300,000 virtual user minutes * $0.002 = $600
~~~ 

If you can afford some bad response times at the beginning of your test you should attempt to shorten your ramp-up time. So, if your normal user load takes 2 hours to be at capacity you can try shortening that to 10 or 20 minutes on an internal load test and see how your system handles it. Once you confirm you can take that kind of hit you should alter your load test to match that. Next, if your test had normally run for a couple of hours, you should consider only running for 30 minutes. 

I know, I know. That is not a great amount of testing, but it all depends on what your goals are.  If you have tons of disposable cash then by all means crank up 10,000 users and have them sit idle for hours on end.

###Conclusion
We all know bandwidth costs money. But you can really save yourself a ton of **actual** dollars, and you can greatly enhance your user experience. Some of the glamor in performance testing, if there is such a thing, is finding that critical bit of code that would have taken down the site. But, we should not neglect this very fundamental test metric.

This wasn't really meant as a tutorial but an overview of a process that may be skirted from time to time. It's easy to forgo certain tests and skip over goals. Here are a few more links that will help out [Web Fundamentals](https://developers.google.com/web/fundamentals/), [PageSpeed Insights](https://developers.google.com/speed/docs/insights/rules), [Yahoo Best Practices](https://developer.yahoo.com/performance/rules.html)(a bit older but useful).

[vso]: http://http://www.visualstudio.com/
[fiddler]: http://www.telerik.com/fiddler
[over]: http://www.telerik.com/fiddler/web-app-performance-testing
[ms]: http://www.microsoft.com/
[apt]: /2014/09/16/always-performance-test/
[art]: http://msdn.microsoft.com/en-us/library/bb250442(v=vs.85).aspx