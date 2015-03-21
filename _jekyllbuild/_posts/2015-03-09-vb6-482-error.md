---
layout: post
title: VB6 and 482 Printer errors (Hello 1998)
tags:
- procmon
---
Recently at my day job I was called in to check out an issue that sprung up after a new printer driver was installed. My first thoughts were *"Oh, they can't print now; let's back-level the drivers."* Of course, I work with a great bunch of folks, and that had already been tried and the problem was still there. Ah, well that mea.. what?

## Background
This is an old school VB6 application that does little more than update a local SQL instance and print out some reports. There is a new application replacing it, but they have to live side-by-side for a few weeks. After that, all work is shifted to the new system. In order for the new system to work a new printer is being used. This is where the print driver comes in.

This application is old. It's no longer maintained. It's going away in a few weeks. Why are we fixing it? Turns out one of the reports---the only report that's broken mind you---is needed for daily operations. As the application is rolled out the report will be used for two weeks and eventually be replaced by the new. This means we need to have that report working.

## What Caused It?
As with any strange issue, it could only be reproduced under certain conditions. In our case some of the details were flaky but boiled down to this:

1. Only happened on one specific report
2. Wouldn't happen with the running user had Admin rights
3. Would throw a 482 error in the log

The interesting thing here was the 482 error and the fact it worked for Administrators. I had the code available and we could see that it was using the simple `PrintForm` VB6 function. This function was being called inside of an old Crystal Reports control. The problem came up because before it would print it would check some properties. This would usually be fine, but since the application was written to simplify user interaction a lot of values were pulled from registry settings. Below I have a screen shot of the [procmon][procmondl] capture, this shows the spool service trying to call the **EPSON TM-L90 Label** printer.

As it turns out, part of the driver install is to remove the old printer names and unify them under one unique name. This unfortunately broke this specific part of the application because it would call out to the spooler and it would return an unknown error code.

![procmon](/images/procmonprinter.png)

## The fix
Well in this instance we were able to change our registry setting inside of the application to a printer that existed and it allowed the application to press on. But, if you run into this issue your self you can use [procmon][procmondl] to see what your spoolsv.exe is trying to contact.


[procmondl]: https://technet.microsoft.com/en-us/library/bb896645.aspx
