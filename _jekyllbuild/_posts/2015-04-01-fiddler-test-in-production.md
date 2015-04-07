---
layout: post
title: Test in Production (with Fiddler)!
tags:
- fiddler
---
While this does seem like an April fools joke, that wasn't the intention. However, that doesn't stop me from feeling somewhat clever. Anyway, one of our internal teams started complaining about their web pages being slow. Well, yeah, okay; what do you mean by slow? Just slow or SLOOOOOW. Turns out it was the latter. Using the IE and Chrome profiling tools I could see that there was a lot of time being spent in a jQGrid selector. We wanted to test out some code changes, but had to wait to cut a change record. This would have cost us a few days.

As always, change management is a great thing because it keeps track of what you change. But, as always, change management can hinder progress. It can turn a 2 hour engagement into a 2 day engagement or worse. For sake of transparency we were already in our pre-production environment for this test; but we still couldn't just up and change code as we pleased. We also couldn't get a data load on our development environment. There has to be a better way to test UI code changes.

## The Issues and Solutions
Let's look over the problem we have. We did some initial testing with the browser profiling tools and know it's all on the client side.

1. Identified slow UI
2. Identified slow selector
3. It's part of a library
4. We have *some* code we can change

With this list we can go down a couple of roads. Each one would require us to jump on the server and at the very least open notepad. But, as we know, this isn't allowed and it's really not an emergency.

1. Replace jQuery
2. Replace jQGrid
3. Change our code

## Fiddler to the Rescue!
Seriously, how awesome is this tool. Let's just take a moment and understand the power of a GUI based proxy that allows us to "fiddle" with the requests and responses of an application. Go on. Take a moment. Back? Great.

How can Fiddler help in this situation? We all know that it allows us to change our outgoing requests by using the [Composer][composer] and [rules][rules]. But have you spent much time looking at the [AutoResponder][autor]? This little gem allows us to change the file the browser is requesting to what ever we want; as a side note it also allows us to change the response codes as well.

>This same behavior **could** be achieved with rules, but that way is a bit harder to implement.

## Steps and Process

### Step 1 - Select the target request
![Step 1](/images/fiddler_step1_select_session.png)

>Simply highlight the session

### Step 2 - Click "Add Rule" on Auto Responders Tab
![Step 2](/images/fiddler_step2__add_rule.png)

>This will create a rule for the selected session(s)

### Step 3 - Check the check boxes to enable
![Step 3](/images/fiddler_step3_add_rule_selectboxes.png)

>This is required to serve the requests

### Step 4 - Select the file drop down
![Step 4](/images/fiddler_step4_add_rule_selectfile.png)

>This is required to serve the requests

### Step 5 - Reissue the request
![Step 5](/images/fiddler_step5_result.png)

>Depending on your browser and the cache settings of your file, you may want to force a full reload.

## Wrap Up
The process is pretty simple to execute. If you noticed in Step 5 I highlighted the version requested from the server and the version Fiddler returned. I was able to use this technique to replace a couple of other JavaScript files as well and see if upgrading the code helped. In this case we had to make some changes to our code and we were able to test and validate them rather quickly using this method.

While testing in production for server side code is ***NOT RECOMMENDED*** by any means. This type of testing in production is okay and, of course, will only affect the client machine. Happy hacking.

[autor]: http://docs.telerik.com/fiddler/KnowledgeBase/AutoResponder
[composer]: http://docs.telerik.com/fiddler/Modify-Traffic/Tasks/CustomizeRequest
[rules]: http://docs.telerik.com/fiddler/KnowledgeBase/FiddlerScript/ModifyRequestOrResponse
