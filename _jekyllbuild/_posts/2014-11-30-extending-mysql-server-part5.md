--- 
layout: post
title: MySQL .NET Hosting Extension - Part 5 - AppDomain and Host Safety
tags:
- mysql
- .net
- hosting api
- extending
- udf
---
Now that we have a properly refactored base, and we have a good working solution to load new file from, we need to start considering safety. Not just type safety and integrity of data. No, safety of the executing code as well as the safety of the CLR host---MySQL in this case. Without that we would open up our new plugin library to a lot of malicious things.

##How to get the code

Enter the following commands in your GIT command prompt. It's that simple. All code changes as I have shown them in this blog post should be there. If you come across this post at a way later date, try increasing the range from 5 to 10, and so on.

~~~
git clone https://github.com/jldgit/mysql_udf_dotnet.git -b wip-nextversion
git log --abbrev-commit -n 5 --pretty=oneline

6d017b0 Changes relating to post 5
303d9cd Changes relating to post 4
5d721fa Good working copy.
6a588f8 Work in progress.
f1696c3 Merge branch 'master' of https://github.com/jldgit/mysql_udf.git

git checkout 6d017b0
~~~

##What's Changed?
Not a lot has changed in this version. We are now in at a good cruising speed to add in new components as needed. The major changes here are adding in some new configuration sections relating to permission groups (permission sets) that we can arbitrarily create. I've also added in [Host Access Protection][hap] which will block some features that are useful but dangerous when working in a shared server environment. You can get around them, but you have to go FullTrust.

###Updated AppDomain Manager (MySQLHostManager)
Added in a new configuration section that allows us to define very specific security for the assemblies that are to be loaded in our MySQL process. The example below shows how these items relate. As mentioned in [part 4][pt4] of this series the default execution mode is [SecurityPermissionFlag.Execution][exeflag]. This allows very simplistic computation to be done, but a lot of powerful features in .NET are stripped away. Now, we can grant FullTrust or a very specific set of permissions. 

~~~XML
<?xml version="1.0" encoding="utf-8" ?>
<configuration>

  <configSections>
    <section name ="mysqlassemblies" type="MySQLHostManager.MySQLAssemblyList, 
             MySQLHostManager, Version=1.0.0.0, PublicKeyToken=71c4a5d4270bd29c"/>
  </configSections>

  <mysqlassemblies>
    <permissionsets>

      <permissionset name="MySQLPartial">
        <permissions>
          <add name="FileIOPermission" />
        </permissions>
      </permissionset>

    </permissionsets>

    <assemblies>
      <!--No specific permission set assigned to this assembly; uses default (MySQLPartial)-->
      <assembly name="MySQLCustomClass.CustomMySQLClass" fullname ="MySQLCustomClass, 
                Version=1.0.0.0, PublicKeyToken=a55d172c54d273f4" clrversion="2.0" />

      <!--FullTrust Granted to this assembly-->
      <assembly name="MySQLCustomClass.FullTrustAssemblyDemo" fullname ="MySQLCustomClass, 
                Version=1.0.0.0, PublicKeyToken=a55d172c54d273f4" clrversion="2.0"
                permissions="FullTrust"/>
      <!--MySQLPartial Granted to this assembly-->
      <assembly name="MySQLCustomClass.PartialTrustAssemblyDemo" fullname ="MySQLCustomClass, 
                Version=1.0.0.0, PublicKeyToken=a55d172c54d273f4" clrversion="2.0"
                permissions="MySQLPartial"/>
    </assemblies>
  </mysqlassemblies>
</configuration>
~~~

>**NOTE:**The clrversion attribute has not been implemented yet. I will get to that in the next blog post.

###Updated clr_lib
I added in the Host Access Protection features that will keep the CLR safe in the event of some possible bad things that can be done by code. Here is a list of the items I am stopping for partially trusted code. The key phrase here is that it only stops **PARTIALLY** trusted code. If you mark an assembly as FullTrust, it's game on. This also means you can set up a CAS Policy (for .NET 3.5 and below) and bypass the need to have this setting. But in .NET 4.0 CAS Policy is no longer in use. 

| Attribute | Description |
|-----------|-------------|
| eSynchronization | Specifies that common language runtime classes and members that allow user code to hold locks be blocked from running in partially trusted code.|
| eSelfAffectingThreading | Specifies that managed classes and members whose capabilities can affect threads in the hosted process be blocked from running in partially trusted code. |
| eSelfAffectingProcessMgmt | Specifies that managed classes and members whose capabilities can affect the hosted process be blocked from running in partially trusted code. |
| eExternalProcessMgmt | Specifies that managed classes and members that allow the creation, manipulation, and destruction of external processes be blocked from running in partially trusted code. |
| eExternalThreading | Specifies that managed classes and members that allow the creation, manipulation, and destruction of external threads be blocked from running in partially trusted code. |
| eUI | Specifies that managed classes and members that allow or require human interaction be blocked from running in partially trusted code.|

##Expanded Walkthrough
This wasn't a major code change and we really only scratched the surface of what this change really did. I chose to be a bit more restrictive for HAPso I can whittle away the over restrictive. I also chose to be very flexible for what CAS permissions would be allowed. Let's take a little closer look at the permissions code and the HAP code.

###Security Permissions
The cornerstone of .NET security is [Code Access Security][cas]. This is a set of attributes and assertions that check the rights of the caller(s). In the simplest form it checks to see if any of the callers have access to call the possibly insecure code. For example, if we try to write a file, and we do not have the `FileIOPermission` we will get a security exception. In the code below you can see how we iterate through a plain text list of permissions (case sensitive for now). If we have that permission listed it will add it to the default policy.

If we happen to have the phrase FullTrust in the assembly permissions attribute, we give the app domain an Unrestricted permission state. This is the same as adding each permission. This means that **ALL** assemblies loaded in this domain will have full trust. We will circle back in later blog posts to fix a possible security flaw in this design.

~~~csharp
private PermissionSet GetAssemblyPermissions(MySQLAsembly typeName)
{
  PermissionSet permissions = new PermissionSet(PermissionState.None);
  permissions.AddPermission(new SecurityPermission(SecurityPermissionFlag.Execution));

  if (!string.IsNullOrEmpty(typeName.permissions))
  {
    if (typeName.permissions.Equals("fulltrust", StringComparison.InvariantCultureIgnoreCase))
    {
      // override the default permission set with a full trust permission set.
      permissions = new PermissionSet(PermissionState.Unrestricted);
    }
    else
    {
      var section2 = System.Configuration.ConfigurationManager.GetSection("mysqlassemblies") 
      as MySQLAssemblyList;
      var permlists = section2.permissionsetscollection;
      var permlist = permlists[typeName.permissions];

  
      foreach (MySQLPermission permission in permlist.permissionscollection)
      {
          switch (permission.Name)
          {
            // Removed code for brevity ...
            case "OdbcPermission": permissions.AddPermission(
              new System.Data.Odbc.OdbcPermission(PermissionState.Unrestricted));
                break;
            case "OleDbPermission": permissions.AddPermission(
              new System.Data.OleDb.OleDbPermission(PermissionState.Unrestricted));
                break;
            case "SqlClientPermission": permissions.AddPermission(
              new System.Data.SqlClient.SqlClientPermission(PermissionState.Unrestricted));
                break;
            case "EnvironmentPermission": permissions.AddPermission(
              new System.Security.Permissions.EnvironmentPermission(PermissionState.Unrestricted));
                break;
            case "FileDialogPermission": permissions.AddPermission(
              new System.Security.Permissions.FileDialogPermission(PermissionState.Unrestricted));
                break;
            case "FileIOPermission": permissions.AddPermission(
              new System.Security.Permissions.FileIOPermission(PermissionState.Unrestricted));
                break;
            // Removed code for brevity ...

            default:
                break;
          }
        }
    }

  }
  return permissions;
}
~~~

###Host Access Protection
In order to make sure we don't inadvertantly shut MySQL down, or even block a thread indefinitely we implement Host Protection. This is not exactly the same as Code Access Security. Meaning, it has nothing to do with the call stack. The [HostProtectionAttibute][hap] immediately stops execution if it is found while JITting the code. So, this means you could have code that is not "host aware" running that would clear the CAS checks, but could still cause stability issues.

An example of this is calling `System.Diagnostics.Debug.WriteLine("Yaaassss!");` inside of your code. There is nothing particularly bad here as it's not writing to the UI so it would seem this code is safe. However, if you look inside of the code you will find the following things to be true. The `WriteLine()` method internally calls on the trace listeners collection and that acquires a lock.

The lock compiles down into `Monitor.Enter()` and `Monitor.Exit()`. If we look at this code we can see the HostProtection attribute is establishing that it has both Synchronization (eSynchronization) and ExternalThreading (eExternalThreading). This trips the HAP when the code is being JITted.

The way around this is to grant the AppDomain unrestricted security which turns off the verification. So essentially, you can bypass host access protection by setting an assembly (or the domain) to FullTrust.

~~~csharp
public static void WriteLine(string message)
{
  if (!TraceInternal.UseGlobalLock)
  {
     // Internal trace lister code that does not acquire a lock.
     // Removed for brevity.
  }
  else
  {
    lock (TraceInternal.critSec)
    {
      foreach (TraceListener traceListener in TraceInternal.Listeners)
      {
        traceListener.WriteLine(message);
        if (!TraceInternal.AutoFlush)
        {
            continue;
        }
        traceListener.Flush();
      }
    }
  }
}
~~~

~~~csharp
[ComVisible(true)]
[HostProtection(SecurityAction.LinkDemand, Synchronization=true, ExternalThreading=true)]
public static class Monitor
{
   // Removed code for brevity 

   public static extern void Enter(object obj);
}

~~~

This is the code snippet that turns on the Host Protection manager with our specified flags.

~~~Cpp
// get the host protection manager
ICLRHostProtectionManager *pHostProtectionManager = NULL;
HRESULT hrGetProtectionManager = m_pClrControl->GetCLRManager(
  IID_ICLRHostProtectionManager,
  reinterpret_cast<void **>(&pHostProtectionManager));
if (FAILED(hrGetProtectionManager))
  return hrGetProtectionManager;

// setup host proctection to disallow any threading from partially trusted code.
// Why? well, if a thread is allowed to hang indefinitely the command could get stuck.
HRESULT hrHostProtection = pHostProtectionManager->SetProtectedCategories(
  (EApiCategories)(eSynchronization | eSelfAffectingThreading | eSelfAffectingProcessMgmt 
  | eExternalProcessMgmt | eExternalThreading | eUI));
~~~

##Wrapping Up
Now that we have a solid foundation from part 4 we can extend it to be a bit more restrictive (*yes, that's what we want*) so we can protect our server. As we move into the next few posts we will start to add on some more security and some more useful features. Shadow Copy comes to mind.

As always, I'm here to help if you have questions. Look for a v1.0 before the end of December. I will make sure the application has an installer and can be used with both 32bit and 64bit.

[hosting]: http://msdn.microsoft.com/en-us/library/ms404385(v=vs.110).aspx
[cpp]: https://github.com/jldgit/mysql_udf_dotnet/blob/master/clr_host/ClrHost
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
