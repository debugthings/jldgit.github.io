--- 
layout: post
title: MySQL .NET Hosting Extension - Part 7 - AppDomain Pools
tags:
- mysql
- .net
- hosting api
- extending
- udf
---
If we look at some of the performance metrics of the MySQL UDF extension, we're not looking great for a few items. Number one, of course, is the loading of the .NET CLR. Unfortunately unless I integrate this tool into the MySQL code itself I can't control that. The next is the loading and use of the AppDomain. That, however, I can fix.

##How to get the code

Enter the following commands in your GIT command prompt. It's that simple. All code changes as I have shown them in this blog post should be there. If you come across this post at a way later date, try increasing the range from 5 to 10, and so on.

~~~
git clone https://github.com/jldgit/mysql_udf_dotnet.git -b wip-nextversion
git log --abbrev-commit -n 5 --pretty=oneline

e9dc6de Changed relating to post 7
91e2238 Changes relating to post 6
6d017b0 Changes relating to post 5
303d9cd Changes relating to post 4
5d721fa Good working copy.

git checkout e9dc6de
~~~

##What's Changed?
I've updated the code to address a problem with loading and unloading AppDomains each time the code is called. The majority of the updates are inside of the managed AppDomainManager assembly.

###Updated AppDomainManager
I added some new configuration items that revolve around the newly implemented AppDomain cleanup timer. This timer fires in an increment you set in the .config file. 

###Updated clr_lib
I removed some extraneous code that was used to save copies of the AppDomain names to be reused. This is gone by the wayside to use the raw pointer when calling the functions. Much, much faster.

###Updated mysql_udf.c
As mentioned above I am now using the raw pointer. I have updated the UDF code to reflect this. I have also added some extra logging that will be sent back to the MySQL client.

##The Problem
When an AppDomain is created and an assembly is loaded the following high-level steps must happen. These steps can take any amount of time depending on how busy the machine is. On my Core i7 laptop with minimal load it was around **500ms** for a cold start and maybe 300ms after things have been used a few times.

 1. MySQL .NET UDF gets a pointer to the default domain.
 2. The default domain reads the config file to determine the CLR for the selected assembly.
 3. MySQL .NET UDF uses the default CLR to get a pointer to the correct domain.
 4. The correct domain reads from the config file to look up specific options for the assembly.
 5. The default domain then creates a domain and returns a pointer to the newly created managed host to MySQL .NET UDF.
   - On initialization of the domain, it loads the assembly from the file store.
 6. MySQL .NET UDF takes the managed host and passes it as one of the UDF parameters to be reused.

This isn't a lot of unique steps per se, but each one is computationally expensive. There are a lot of code checks and JITing that must happen each time the domain is loaded and the newly loaded methods are called. The solution to this is rather simple.

##The Solution
Instead of spinning up a new AppDomain each time the methods are called in a query, we can pool them instead. The newly created domains are stored in a Dictionary collection and are selectively reused. The new steps are now the following for a first time domain start up.

 1. MySQL .NET gets a pointer to the default domain.
 2. The default domain reads the config file to determine the CLR for the selected assembly.
 3. MySQL .NET uses the default CLR to get a pointer to the correct domain.
 4. The correct domain reads from the config file to look up specific options for the assembly.
 5. The default domain then creates a domain 
   - **On initialization of the domain, it loads the assembly from the file store.**
 6. A pointer is kept for the new AppDomain and stored in the "Domains In Use" Dictionary.
 7. It then returns returns the pointer to the newly created managed host, back to MySQL .NET UDF.
 6. MySQL .NET UDF takes the managed host and passes it as one of the UDF parameters to be reused.

Once the AppDomain is created it has a configurable finite life time. This lifetime can be set inside of the mysqld.config file. Now that we're using pools let's take a look at the configuration for the timers; and the new load sequence for a domain that is created but not being used.

~~~XML
<appDomainCleanup
  interval="0.00:05:00"
  forcedInterval="1.00:00:00" />
~~~

 1. MySQL .NET UDF gets a pointer to the default domain.
 2. The default domain reads the config file to determine the CLR for the selected assembly.
 3. MySQL .NET UDF uses the default CLR to get a pointer to the correct domain.
 4. The correct domain checks to see if an AppDomain is created and available for the assembly.
 5. It then checks to see if the domain is "too old".
   - If so, it will be moved to a structure that is unloaded every minute (on a separate thread).
   - If not, it moves on to step 5.
 5. The correct domain returns the pointer to MySQL .NET UDF.

Before these changes, when the UDF was done with the AppDomain it used to unload it right there on the same thread. This was also expensive as it causes GCs to run and Finalizers to execute. Also, the clr_lib used to keep a stored copy of the data in a std::map<> member. This was a bit redundant so it was removed. However, the CLRs are still stored in a std::map<> and will stay there to help "future proof" the application. Now when the UDF is done the following steps are taken.

 1. MySQL .NET UDF deinit is called
 2. The stored pointer is used to call the UnloadAppDomain() function if IUnmanagedHost passing in the AppDomain name.
 3. The UnloadAppDomain() function calls the Unload() function on the proper default domain.
 4. The Unload() function does not actually unload the domain. Instead it checks to see if the AppDomain's configurable lifetime has expired. If it has, it adds it to the AppDomains to die.

This allows us to offload the timer to unload old domains when the time is right. For now, this guy is on a loop that fires every minute no matter what.

##Issues
So, now that we're doing more than just loading a domain each time, we have to be mindful of some multi-threading possibilities. No, not in the .NET extension code, but in the AppDomainManager code.

When a new item is added or removed from the Dictionary collection we need to lock() around it to make sure we're not grabbing an unloaded domain, or grabbing a domain that is in transition from Active to Inactive. The background on the Dictionary key naming scheme is simple. Create a double pipe delimited list of the Assembly and a FileTime and use that information to verify the run.

I know I probably should create a class that holds this information and also holds lock structures to access specific properties. But, there is a problem with such a complicated solution. Namely, I have to create and dispose a ton of objects over time, each with sub objects and so on and so forth. The performance hit is amortized over the lifetime of the application but could cause some undue and unforeseen GC time.

But even with a simpler approach I still introduced a bug during one of my test runs by just one simple mistake. Here it is for your viewing pleasure.

~~~Csharp
string AppDomainName = string.Format("{0}||{1}", typeName, 
DateTime.Now.ToFileTime().ToString()); //BUG Here
lock (objLock)
{
    if (activeAppDomains.ContainsKey(assemblyName))
    {
        AppDomainName = string.Format("{0}||{1}", typeName, (DateTime.Now.ToFileTime() 
        + new Random().Next(1, 10000000)).ToString());
    }
}
~~~

This was a sneaky one. Basically there would be a few threads queued up on the lock---all of them with the same time. The locks would release, but since the action is happening so fast a couple of threads end up getting the same quantum and the Random() would issue the same value. The fix was simple.

~~~Csharp
lock (objLock)
{
    string AppDomainName = string.Format("{0}||{1}", typeName, 
    DateTime.Now.ToFileTime().ToString()); //No BUG Here
    if (activeAppDomains.ContainsKey(assemblyName))
    {
        AppDomainName = string.Format("{0}||{1}", typeName, (DateTime.Now.ToFileTime() 
        + new Random().Next(1, 10000000)).ToString());
    }
}
~~~

By moving the FileTime string creation to inside of the lock() I can guarantee that we should be gifted a unique time as the FileTime is in 100ns intervals. However, if for some reason we run faster than that I still have the Random() number being added just in case.

##Testing (limited)
In order to test the database I loaded it with the [MySQL employee sample database][sampdb]. My test harness calls the following SQL across 10 threads 600 times in a row.

`SELECT MYSQLDOTNET_INT('MySQLCustomClass.CustomMySQLClass', emp_no), emp_no, first_name, last_name FROM employees`

`SELECT  (emp_no * 3.14) + 10, emp_no, first_name, last_name FROM employees`

This SQL is trivial but will all in all spins up and shuts down 6,000 AppDomains. When the test is running the memory footprint of my instance of MySQL does not climb over 90MB.

Single threaded the non .NET query takes an average of 1.5 seconds. Single threaded .NET query runs at **1.4** seconds average. My only guess is the extra math being executed inside of MySQL has to be lexed, parsed, and finally computed. On the surface it looks like we're faster, but more than likely this is just an effect of bad query writing on my part.

##Wrap Up
Now the application really has some substance. I have been running performance tests for a few days now and the results are promising. Still more testing has to be done for longer amounts of time to be sure.

In the next post I will introduce shadow copies and how we can use it to modify query results between runs without having to restart the MySQL process and without having to unload any plugins.

[sampdb]: https://dev.mysql.com/doc/employee/en/
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