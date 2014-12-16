--- 
layout: post
title: MySQL .NET Hosting Extension - Part 8 - Mimicking IIS (Shadow Copy, Custom Configs)
tags:
- mysql
- .net
- hosting api
- extending
- udf
---
One of the coolest things about deploying to IIS is the shadow copy feature. This allows you to drop in a new DLL and when the application detects it, it will spin up a new AppDomain and send all new requests there. This "seamless" integration is great for achieving high availability. Web servers and SQL servers alike need to experience as little down time as possible. We will walk through adding shadow copy and implementing file watchers inside of the MySQLHostManager that will handle these conditions.

##How to get the code

Enter the following commands in your GIT command prompt. It's that simple. All code changes as I have shown them in this blog post should be there. If you come across this post at a way later date, try increasing the range from 5 to 10, and so on.

~~~
git clone https://github.com/jldgit/mysql_udf_dotnet.git -b wip-nextversion
git log --abbrev-commit -n 5 --pretty=oneline

4a0be76 Changes relating to post 8
e9dc6de Changed relating to post 7
91e2238 Changes relating to post 6
6d017b0 Changes relating to post 5
303d9cd Changes relating to post 4

git checkout 4a0be76
~~~

##What's Changed?
Surprisingly not a lot of code has changed. A while back I added in the ShadowCopy property when spinning up an AppDomain and left it in. This was to test, but I never removed the change. So, there is one line of code that I will focus on in the expanded walk through that explains this.

###MySQLHostManager implements Shadow Copy
As mentioned there is a one line change that enables the shadow copy feature it is the very appropriately named [AppDomainSetup.ShadowCopyFiles][shadcpy] property. This allows us to use the CLR download directory. See the MSDN article ["Shadow Copying Assemblies"][shadcpy2] for an explanation of the process. Be aware I am not implementing a custom download directory as it requires us to maintain the cache.

###MySQLHostManager implements custom configs
As well with the shadow copy implementation I also left in a line of code from when I first started implementing my AppDomain manager in [part 4][pt4]. The [AppDomainSetup.ConfigurationFile][cfgfileprp] property allows the newly created AppDomain to use a separate configuration file from the `mysqld.exe.config` file that sets up the default domains and lets the Hosting API know about our intentions to load files.

##Expanded Walkthrough

###Shadow Copying
The idea behind shadow copying files is simple; when an assembly is loaded the file is locked and cannot be altered. The only way it can be altered is by shutting down all of the AppDomains that have a hold on the file. The means you could be waiting a while. 

However, if shadow copying is enabled the file is copied to another location before being loaded and the copy is locked. This leaves the original free to be altered. This is important because you can replace this file and load it in a new AppDomain. This new file is ALSO copied to the shadow location which means you can also replace the copy with another copy. This can go on for ever.

>**NOTE:** One little caveat to this is the fact that if you use a strong name inside of the `mysqld.exe.config` file you must make sure your file is signed and has the exact version (unless you use a binding redirect).

Let's take a look at the simple code that enables shadow copying.

~~~Csharp
AppDomainSetup ads = new AppDomainSetup();
// .. removed for clarity ..
ads.ShadowCopyFiles = "true";
~~~

This single line requires you to set the value to the string value `"true"` and not `true`. I dunno why, but that is how it has been for a while now. If you look in some of the Microsoft code such as `System.Web.Hosting.ApplicationManager::PopulateDomainBindings()` you will see the same code.

With this set we can open up mysqld.exe in WinDbg, load SOS, and use the `!DumpDomain` command to  take a look at where the assembly is being loaded from. Look at the bottom of this listing and you can see the MySQLCustomClass assembly being loaded from `C:\Users\James\AppData\Local\assembly\dl3\XDO19CO6.93L\QWVBM69E.1HJ\05b42dd0\d00c85ba_2618d001\`. This indicates that the CLR copied this file to the download cache directory and is using it from there.

~~~
0:035> !DumpDomain 
<<<<<< DATA REMOVED FOR CLARITY >>>>>>
--------------------------------------
Domain 23:          0e0277d0
LowFrequencyHeap:   0e027c3c
HighFrequencyHeap:  0e027c88
StubHeap:           0e027cd4
Stage:              OPEN
SecurityDescriptor: 0def63d0
Name:               MySQLCustomClass.CustomMySQLClass||130631735636773794
Assembly:           0df78388 [C:\Windows\Microsoft.Net\assembly\GAC_32\mscorlib\v4.0_4.0.0.0__b77a5c561934e089\mscorlib.dll]
ClassLoader:        0e31ee60
SecurityDescriptor: 00681c30
  Module Name
70871000    C:\Windows\Microsoft.Net\assembly\GAC_32\mscorlib\v4.0_4.0.0.0__b77a5c561934e089\mscorlib.dll

Assembly:           0df79a08 [C:\Windows\Microsoft.Net\assembly\GAC_MSIL\MySQLHostManager\v4.0_4.0.0.0__71c4a5d4270bd29c\MySQLHostManager.dll]
ClassLoader:        0067f610
SecurityDescriptor: 00681878
  Module Name
0d4743f8    C:\Windows\Microsoft.Net\assembly\GAC_MSIL\MySQLHostManager\v4.0_4.0.0.0__71c4a5d4270bd29c\MySQLHostManager.dll

Assembly:           0df79408 [C:\Windows\assembly\GAC_MSIL\MySQLHostManager\2.0.0.0__71c4a5d4270bd29c\MySQLHostManager.dll]
ClassLoader:        0e5a88b8
SecurityDescriptor: 00681f60
  Module Name
0d4749b8    C:\Windows\assembly\GAC_MSIL\MySQLHostManager\2.0.0.0__71c4a5d4270bd29c\MySQLHostManager.dll

Assembly:           0df78d48 [C:\Users\James\AppData\Local\assembly\dl3\XDO19CO6.93L\QWVBM69E.1HJ\05b42dd0\d00c85ba_2618d001\MySQLCustomClass.dll]
ClassLoader:        0e5a86b0
SecurityDescriptor: 006805e0
  Module Name
0d475fcc    C:\Users\James\AppData\Local\assembly\dl3\XDO19CO6.93L\QWVBM69E.1HJ\05b42dd0\d00c85ba_2618d001\MySQLCustomClass.dll
~~~

###Config file changes watcher
In ASP.NET you can have multiple applications under multiple virtual directories. I wanted to have the ability to make a change to either any of the config files and have the default domain spin down the old domains and spin up new ones.

In order to track when a config file changes, we need to use the `FileSystemWatcher` class. This class takes in a file path in the constructor and has you attach an event on specific file actions like Create, Changed or Deleted. In our case we are only attaching to the changed event.

~~~Csharp
// This free standing code snippet is located in the constructor.
{
    var configFileWatcher = new System.IO.FileSystemWatcher(".\\mysqld.exe.config");
    configFileWatcher.Changed += configFileWatcher_Changed;
}

// This event sets the AppDomain manager private members to tell us when this event occured.
void configFileWatcher_Changed(object sender, FileSystemEventArgs e)
{
    System.Configuration.ConfigurationManager.RefreshSection("mysqlassemblies");
    fileWatcherPurge = DateTime.Now;
}

// Upon any active application creation or unload we will check to see if it's created time is less than the purge
if (mysqlhost.FirstAccessed < fileWatcherPurge)
{
    // Set Appdomain to die
}
~~~

With this event I tell the default domain to refresh the section under `mysqlassemblies` so it will jettison the cached version of the config file. I also set a date time to do a check when we create or unload an AppDomain that will remove it if it finds that the domain was created before the file change.

There is also repeated code for the `mysqldotnet.config` files.

###Targeted mysqldotnet.config files
Another possibility to consider is you want to use specific configurable settings inside of your custom code. You could just plop your DLLs and .config file in the `MYSQLROOT\lib\plugins` directory but then you'd have the chance of overwriting any settings you may have for one particular assembly. The way to make this work properly is to set the [AppDomainSetup.ApplicationBase][privbin].

With this path set, the assembly probing will begin at `MYSQLROOT\lib\plugins` and search for the assembly in the follwing pattern. Since we do not specify a culture we do not probe any culture directories.

  1. MYSQLROOT\lib\plugins
  2. MYSQLROOT\lib\plugins\MySQLCustomClass
  3. MYSQLROOT\lib\plugins\bin\
  4. MYSQLROOT\lib\plugins\bin\MySQLCustomClass

We can now place our assembly and .config file inside of `MYSQLROOT\lib\plugins\MySQLCustomClass`. Now, we have a properly paired assembly and .config file. All settings will be inherited from this .config and will not be carried over from the default domain.

To validate we are loading from the proper directory we can review the Fusion Log. You must turn on the fusion log before you execute a query that uses the MySQL plugin. Check out this MSDN page on the [Assembly Binding Log Viewer][fuslog] to learn how to setup and use the tool.

~~~
LOG: Attempting download of new URL file:///C:/Users/James/Source/BazaarRepos/mysql-server/mysql-5.5/sql/lib/plugin/MySQLCustomClass.DLL.
LOG: Attempting download of new URL file:///C:/Users/James/Source/BazaarRepos/mysql-server/mysql-5.5/sql/lib/plugin/MySQLCustomClass/MySQLCustomClass.DLL.
LOG: Assembly download was successful. Attempting setup of file: C:\Users\James\Source\BazaarRepos\mysql-server\mysql-5.5\sql\lib\plugin\MySQLCustomClass\MySQLCustomClass.dll
~~~

##Wrapping Up
With all of the peices starting to fall in place we're getting close to a release of this code. I will have a final part to clear up any miscellanea that didn't make it into the first 8 posts. I will try to focus on performance testing the code and give some better examples. I will also get a proper installer out there for both 32bit and 64bit versions.

[fuslog]: http://msdn.microsoft.com/en-us/library/e74a18c4%28v=vs.110%29.aspx
[privbin]: http://msdn.microsoft.com/en-us/library/system.appdomainsetup.privatebinpath%28v=vs.110%29.aspx
[cfgfileprp]: http://msdn.microsoft.com/en-us/library/system.appdomainsetup.configurationfile(v=vs.110).aspx
[shadcpy]: http://msdn.microsoft.com/en-us/library/system.appdomainsetup.shadowcopyfiles%28v=vs.110%29.aspx
[shadcpy2]: http://msdn.microsoft.com/en-us/library/ms404279(v=vs.110).aspx
[hosting]: http://msdn.microsoft.com/en-us/library/ms404385(v=vs.110).aspx
[cpp]: https://github.com/jldgit/mysql_udf_dotnet/blob/master/clr_host/ClrHost.cpp
[udf]: https://github.com/jldgit/mysql_udf_dotnet/blob/master/mysql_udf.c
[ARGS]: http://dev.mysql.com/doc/refman/5.0/en/udf-arguments.html
[adm]: http://www.microsoft.com/en-us/download/details.aspx?id=7325
[ccom]: http://msdn.microsoft.com/en-us/library/9e31say1.aspx
[custombook]: http://www.amazon.com/gp/product/0735619883/
[stevep]: http://blogs.msdn.com/b/stevenpr/
[exeflag]: http://msdn.microsoft.com/en-us/library/system.security.permissions.securitypermissionflag%28v=vs.110%29.aspx
[asmload]: http://msdn.microsoft.com/en-us/library/ky3942xh(v=vs.110).aspx
[adsetup]: http://msdn.microsoft.com/en-us/library/system.appdomainsetup%28v=vs.110%29.aspx
[asmloading]: http://msdn.microsoft.com/en-us/library/yx7xezcf%28v=vs.110%29.aspx
[hap]: http://msdn.microsoft.com/en-us/library/system.security.permissions.hostprotectionattribute(v=vs.110).aspx
[cas]: http://msdn.microsoft.com/en-us/library/c5tk9z76(v=vs.110).aspx
[pt4]: {% post_url 2014-11-26-extending-mysql-server-part4 %}
[mixed]: http://msdn.microsoft.com/en-us/library/x0w2664k.aspx
[clrreg]: http://msdn.microsoft.com/en-us/library/hh925568%28v=vs.110%29.aspx