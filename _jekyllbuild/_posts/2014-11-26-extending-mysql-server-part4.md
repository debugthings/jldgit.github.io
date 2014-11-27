--- 
layout: post
title: MySQL .NET Hosting Extension - Part 4 - Extending the AppDomain Manager
tags:
- mysql
- .net
- hosting api
- extending
- udf
---
So far the application was simple and was able to load and run a command from inside of our AppDomain manager. As promised, I am extending this functionality to allow loading of any number of classes. In order to do this I made some large changes to the application. In order to keep things somewhat coherent between Parts 1, 2 and 3---I branched off into a work in progress(wip) area that should make it easier to follow along.

##How to get the code

Enter the following commands in your GIT command prompt. It's that simple. All code changes as I have shown them in this blog post should be there. If you come across this post at a way later date, try increasing the range from 5 to 10, and so on.

~~~
git log --abbrev-commit -n 5 --pretty=oneline

303d9cd Changes relating to post 4
5d721fa Good working copy.
6a588f8 Work in progress.
f1696c3 Merge branch 'master' of https://github.com/jldgit/mysql_udf.git
ac92302 Included support for .NET 4.0. Refactored a few items.

git checkout 303d9cd
~~~

##What's Changed?
Pretty much everything. I re-factored a lot of the code to match up with the way I want the application to read near the end. More than likely this will happen again, but the name changes should be subtle.

###Updated AppDomain Manager (MySQLHostManager, IManagedHost)
This is the first real significant change. I have extended the interface to allow me to get back some specific data from our application. I have also added a new interface calls `ICustomAssembly` this is what all extension classes will inherit from.

We now have some rudimentary form of security. The AppDomains that are created from the DefaultDomain are now limited to [SecurityPermissionFlag.Execution][exeflag]; meaning that we will allow code to execute, but no other permissions are given. This is quite limiting as there are a lot of use assemblies that are rendered useless. We will take care of this in the next blog post.

Along with the standardized interface and the tightened security, I have introduced a custom configuration section that allows us to define assemblies that can be loaded in our AppDomains. This section will grow a bit over time, right now it takes in a short name and provides a full name. The name can be partial as it's used in the [Assembly.Load()][asmload] method.

~~~XML
<?xml version="1.0" encoding="utf-8" ?>
<configuration>
  
   <configSections>
    <section name ="mysqlassemblies" type="MySQLHostManager.MySQLAssemblyList, 
             MySQLHostManager, Version=1.0.0.0, PublicKeyToken=71c4a5d4270bd29c"/>
  </configSections>

  <mysqlassemblies>
    <assemblies>
      <assembly name="MySQLCustomClass" fullname ="MySQLCustomClass, 
                Version=1.0.0.0, PublicKeyToken=a55d172c54d273f4" clrversion="2.0" />
    </assemblies>
  </mysqlassemblies>
</configuration>
~~~


###Updated IUnmanagedHost
A small but powerful change was added to the IUnmanagedHost interface. I added the `Unload()` method. This---as the name would suggest---unloads the domain. This, used in conjunction with `CreateDomain` provide the proper isolation per method execution. Right now this is in it's simplest form and immediately unloads the domain. We will expand this later to heuristically drop domains as they are no longer needed.

###Updated MySQLUDFBridge (mysql_udf)
Starting from the humble UDF example provided we were able to start the CLR and execute a simple command. But, if we were to do this a bunch we might run into issues (stability comes to mind). So, the code was expanded to add checks for existing instances of the CLR and to create an AppDomain for the command execution.

We now have included all of the exports for int, real and string methods so we can execute any of these from this one library. For now, we'll focus on the int methods and work out from there.

##Expanded Walkthrough
So, now that we have more things we can play with, what does it mean? In the most basic sense we start to gain control over the bad things that could affect the stability of our server environment. Let's take a look at how this stability will take shape.

###Security
.NET security is a very, very complex subject and can't be described in its entirety in a blog post or 10. Our security, for now, is very basic. It limits the permissions of any code we deploy to the MySQL server. In the code snippit below you will see the simple security set we give the new AppDomain. Notice we're only granting the `Execution` permission for the new AppDomain. This will carry in to assemblies loaded inside of the AppDomain that aren't granted FullTrust.

~~~csharp
PermissionSet permissions = new PermissionSet(PermissionState.None);
permissions.AddPermission(new SecurityPermission(SecurityPermissionFlag.Execution));
~~~

The first line grants zero permissions to the new AppDomain. The second like adds the Execution security flag to the domain. This means that when any securely written code Demands or Asserts specific access---`FileIOPermission` for example---it will not be allowed and could possibly throw an exception. This can limit even the most trivial of commands, but is a powerful ally. If we think about what could be done with `FileIOPermission` the damage could be far reaching if for some reason the MySQL server runs with elevated access.

###AppDomain Creation
Up until now, we just used the DefaultDomain. This meant that if any code that executed in this domain threw an unhandled exception it would bubble up into our unmanaged code. This isn't completely detremental unless we understand that an exception thrown on a thread has the potential to take down an application if it's fatal or uncaught.

Now, we isolate the domain when we call the `xxx_init` functions. The domain is created on the fly and is given a unique number based off of FileTime. Once the domain is created we pass back the `IManagedHost` instance to the CLR host to keep track of it.

~~~Cpp
my_bool InitializeCLR(UDF_INIT *initid, UDF_ARGS *args, char *message)
{
  int returnCode = 0;
  HRESULT hrCoInit = CoInitializeEx(NULL, COINIT_APARTMENTTHREADED);

  try
  {
    if (pClrHost == NULL)
    {
      HRESULT hrBind = CClrHost::BindToRuntime(&pClrHost.GetInterfacePtr());
      if (FAILED(hrBind))
        _com_raise_error(hrBind);
      // start it up
      pClrHost->Start();
    }
    if (args->arg_count > 0)
    {
      if (args->arg_type[0] == STRING_RESULT)
      {
        auto ret = pClrHost->CreateAppDomainForQuery(_bstr_t(args->args[0]));
        initid->ptr = (char*)ret.copy();
      }
    }

  }
  catch (const _com_error &e)
  {
    const wchar_t *message = (wchar_t *)e.Description() == NULL ?
      L"" :
      (wchar_t *)e.Description();
    std::wcerr << L"Error 0x" << std::hex << e.Error() << L") : " << message << std::endl;

    returnCode = e.Error();
  }

  //initid->ptr = reinterpret_cast<char *>(&pClrHost);
  return 0;
}
~~~

~~~Cpp
STDMETHODIMP CClrHost::raw_CreateAppDomainForQuery(BSTR FnName, BSTR *pRetVal)
{
  IManagedHostPtr pAppMgr = this->GetDefaultManagedHost();
  IManagedHostPtr pNewDomain = pAppMgr->CreateAppDomain(FnName);
  *pRetVal = (BSTR)pNewDomain->GetAppDomainName;
  this->m_NewlyCreatedAppDomains[std::wstring(*pRetVal)] = pNewDomain;
  return S_OK;
}
~~~

In the previous excerpts from the C++ code, we can see that `Initialize()` checks for the existence of a GLOBAL variable `pClrHost`. If that variable is not null, it goes through the initialization steps listed in [part 3][pt3]. After the CLR is initialized we blindly create a new AppDomain. This executes the `CreateAppDomain()` method below.

~~~csharp
 public IManagedHost CreateAppDomain(string typeName)
{
    var section = System.Configuration.ConfigurationManager.GetSection("mysqlassemblies") as MySQLAssemblyList;
    var assemblyName = typeName.Split('.')[0];
    var className = typeName.Split('.')[1];
    var obj = section.assemblies[assemblyName];

    PermissionSet permissions = new PermissionSet(PermissionState.None);
    permissions.AddPermission(new SecurityPermission(SecurityPermissionFlag.Execution));

    AppDomainSetup ads = new AppDomainSetup();
    ads.AppDomainInitializer = ADIDelegate;
    ads.AppDomainInitializerArguments = new string[] { assemblyName, className };
    ads.ConfigurationFile = "mysqldotnet.config";
    ads.ApplicationBase = string.Format("{0}..\\", AppDomain.CurrentDomain.SetupInformation.ApplicationBase);
    ads.PrivateBinPath = "RelWithDebInfo;lib\\plugin";

    string AppDomainName = DateTime.Now.ToFileTime().ToString();

    var appdomain = AppDomain.CreateDomain(
        AppDomainName,
        AppDomain.CurrentDomain.Evidence,
        ads,
        permissions,
        CreateStrongName(Assembly.GetExecutingAssembly()));

    activeAppDomains.Add(AppDomainName, appdomain);

    return (IManagedHost)appdomain.DomainManager;
}
~~~

In the previous example we use the [AppDomainSetup][adsetup] class to define a few specific changes to the AppDomain we are creating. First, we change the config file name so we don't keep looking inside of `mysqld.exe.config` this allows us to isolate AppSettings per assembly and AppDomain. Second, we change the `ApplicationBase` to go up one level so we can define the `PrivateBinPath`.

These two settings change the locations in which the AppDomain will look for assemblies **NOT** in the GAC. If you need a refresher in .NET assembly loading, I suggest looking [here][asmloading]. If your assembly is loaded in the GAC, it will use that one instead as we have not changed any of the binding policies.

###Custom Assemblies
Before we just executed a simple `Run()` method inside of the DefaultDomain. Now, we can execute a custom assembly that implements `MySQLHostManager.ICustomAssembly` from `MySQLHostManager.dll`. This custom interface allows your new code to properly execute.

~~~csharp
namespace MySQLHostManager
{
  public interface ICustomAssembly
  {
    Int64 RunInteger(Int64 value);
    Int64 RunIntegers(Int64[] values);


    double RunReal(double value);
    double RunReals(double[] values);


    string RunString(string value);
    string RunStrings(string[] values);
  }
}
~~~

This interface exposes both the single execution and the aggregate execution models. You do not have to implement ALL of these functions, you just have to be mindful of how you call the custom function from MySQL. These custom assemblies are loaded into a domain and instantiated when you first call the method.

An assembly is first loaded when the AppDomain is initialized. If you look back at the previous section you will see `ads.AppDomainInitializer = ADIDelegate;`. This tells the new AppDomain to run this static delegate upon successful load. You can also see that it gets it's input from the `ads.AppDomainInitializerArguments = new string[] { assemblyName, className };` line. Notice, that if your custom assembly contains more than one type (class) inside of it, the loader will take care of it.

~~~csharp

static void ADIDelegate(string[] args)
{
  var asm = AppDomain.CurrentDomain.Load(args[0]);
}

public long RunInteger(string functionName, long value)
{
  InitFunctions(functionName);
  return functions[functionName].RunInteger(value);
}

private void InitFunctions(string functionName)
{
  if (functions == null)
  {
      functions = new System.Collections.Generic.Dictionary<string, ICustomAssembly>();
  }
  if (!functions.ContainsKey(functionName))
  {
    foreach (var item in AppDomain.CurrentDomain.GetAssemblies())
    {
      var typ = item.GetType(functionName);
      if (typ != null && typ.GetInterface("MySQLHostManager.ICustomAssembly") == typeof(ICustomAssembly))
      {
          functions.Add(functionName, (ICustomAssembly)item.CreateInstance(functionName));
      }
    }
  }
}
~~~

###New Calling Convention for UDF
Before we just passed in a simple integer. Now we are specifying the function to be run. So in order to do that we must pass in the class name. Let's take a look at the new UDF code that makes sure we have this. If you look at lines 17 and 20, you will notice we're calling the method with `args->args[0]`. This is the FIRST parameter you pass into the MySQL UDF---which is the name of the type `MySQLCustomClass.CustomMySQLClass`.

~~~SQL
SELECT mysqldotnet_int("MySQLCustomClass.CustomMySQLClass",3);
~~~

~~~Cpp
long long mysqldotnet_int(UDF_INIT *initid, UDF_ARGS *args, char *is_null,
    char *error)
{
  int returnCode = 0;
  try
  {
    longlong val = 0;
    uint i;
    IManagedHostPtr mhp = pClrHost->GetSpecificManagedHost(BSTR((BSTR*)initid->ptr));

    for (i = 1; i < args->arg_count; i++)
    {
      if (args->args[i] == NULL)
        continue;
      switch (args->arg_type[i]) {
      case INT_RESULT:      /* Add numbers */
        val += RunInteger(mhp, std::string(args->args[0]), *((longlong*)args->args[i]));
        break;
      case REAL_RESULT:     /* Add numers as longlong */
        val += RunInteger(mhp, std::string(args->args[0]), *((longlong*)args->args[i]));
        break;
      default:
        break;
      }
    }
    return val;
    // run the application
  }
  catch (const _com_error &e)
  {
    const wchar_t *message = (wchar_t *)e.Description() == NULL ?
      L"" :
      (wchar_t *)e.Description();
    std::wcerr << L"Error 0x" << std::hex << e.Error() << L") : " << message << std::endl;

    returnCode = e.Error();
  }
  return 0;
}

~~~

##Wrapping Up
As you can (hopefully) see, we are getting close to a more first class plugin for MySQL and .NET. As of now, it goes without saying that this is under HEAVY BETA and shouldn't be used in production. I did some performance tests against it, but haven't stress tested or load tested the database.

If you do want to use it in production let me know and I can help guide you with some updates to the code. Mainly these updates will be around bounds checking and type safety.

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

[pt3]: {% post_url 2014-11-18-extending-mysql-server-part3 %}
