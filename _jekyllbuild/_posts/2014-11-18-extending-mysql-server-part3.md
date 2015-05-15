--- 
layout: post
title: MySQL .NET Hosting Extension - Part 3 - Adding in the .NET Hosting API
tags:
- mysql
- .net
- hosting api
- extending
- udf
---
Now that we've walked through the basics of a UDF, let's start bolting on an AppDomain Manager. As I mentioned before in [part 2][pt2] my example is based off of the [ADMHost][adm] sample provided by Microsoft. The code is used as a jump off point, but we will be extending it as these posts progress. This part of the series will focus on the insertion points rather than the actual code. That will be in the next part. For some extra information on the hosting API check out [Customizing the Microsoft® .NET Framework][custombook] by [Steven Pratschner][stevep]. Also check out [MSDN][hosting] for update information on the APIs.

##Foreword
In order to host the CLR we must first start it. And to start it we must bind to it. In the newer versions of the CLR you can bind to both v2.0 and v4.0 at the same time. This means you need to be able to support both versions of the code.

This presents some challenges as it requires you to write and maintain two AppDomain Managers, as well as understand the security polices of both versions. I will touch on these as we move forward. But, for now, we're going to accept (most of) the defaults and not worry about the nuances.

##Execution Flow
The execution flow is pretty straight forward, but if you don't have a background in Application Domains or the hosting process it can seem a bit convoluted. Here is a quick rundown of methods and execution for both the first run and subsequent runs.

###First Run on Server Start
1. MySQLd starts
2. mysqldotnet Plug-In is loaded
3. First call to `mysqldotnet_xxx()` executes `mysqldotnet_xxx_init()`
4. `mysqldotnet_xxx_init()` loads the hosting API via `CClrHost::BindToRuntime()`
5. `CClrHost::BindToRuntime()` spins up both CLRs side-by-side
  - This is configurable 
6. `CClrHost::BindToRuntime()` saves a pointer to `ICLRRuntimeInfo` per CLR 
7. `mysqldotnet_xxx_init()` starts the CLR via `IUnmanagedHost::Start()`
8. `IUnmanagedHost::Start()` internally calls `IUnmanagedHost::raw_Start()`
9. `IUnmanagedHost::raw_Start()` configures each CLR, it repeats the following steps
    1. The CLR is given a pointer to the `CClrHost` instance to implement `IHostManager`
    2. The CLR is given a proper AppDomain Manager using `ICLRControl::SetAppDomainManagerType()` 
    3. Internally `ICLRControl::SetAppDomainManagerType()` calls the overridden method `AppDomainManager::InitializeNewDomain()` which sets the `RegisterWithHost` flag
    4. This registration calls `IHostManager::SetAppDomainManager()` which is implemented by `CClrHost::SetAppDomainManager()`
    5. `CClrHost::SetAppDomainManager()` stores a copy of the **DEFAULT** domain that was created in our std::map
10. Control is then returned to `mysqldotnet_xxx_init()` which determines the outcome
12. MySQL executes `mysqldotnet_xxx()`
13. `mysqldotnet_xxx()` calls the "Run()" command on the AppDomain Manager for the query
14. The custom assembly executes its internal "Run()" command to return the result

###Additional Runs
1. A call to `mysqldotnet_xxx()` executes `mysqldotnet_xxx_init()`
2. `mysqldotnet_xxx_init` checks to see if we have a pointer to our `IHostManager`
  - If one is not loaded it will load it like the First Run
3. MySQL executes mysqldotnet_xxx
4. mysqldotnet_xxx calls the "Run()" command on the AppDomain Manager for the assembly
5. The custom assembly executes its internal "Run()" command to return the result

##Initialization
MySQL executes `mysqldotnet_xxx_init()` which in turn calls `CClrHost::BindToRuntime()`. This method creates a COM instance of our `CClrHost` class. This is an ATL helper that allows you to instantiate abstract classes, it is akin to a singleton, but slightly different as it is based on CoCreateInstance.

The `CComObject<Base>::CreateInstance()` method has some internal checks and methods it calls. One of the methods we override is `CComObjectRootEx::FinalConstruct()`. This method is called once we've completed a some bounds checking. This is where we actually start the CLR. See [MSDN][ccom] for more information.

In order to initialize the proper CLR we first must loop through all of the installed CLRs on the system. We call the `CLRCreateInstance()` method to query for the `IID_ICLRMetaHost`. Once we have a pointer to the MetaHost we can Enumerate all of the installed versions of the CLR. `ICLRMetaHost::GetInterface()` returns a pointer to the runtime host. We can then store the pointer to the CLR Runtime Host in our `std::map`.

>**NOTE** There are numerous versions of the CLR for the same base version. For example the build can differ between two machines. So, if you were to add in any logic to look for a specific CLR you should limit to Major.Minor.Revision and not Major.Minor.Revision.Build.

~~~Cpp 
//Global parameter (I know, shame on me)
IUnmanagedHostPtr pClrHost = NULL;

my_bool mysqldotnet_int_init(UDF_INIT *initid, UDF_ARGS *args, char *message)
{
  int returnCode = 0;
  HRESULT hrCoInit = CoInitializeEx(NULL, COINIT_APARTMENTTHREADED);

  try
  {
    if (pClrHost == NULL)
    {
      HRESULT hrBind = 
        CClrHost::BindToRuntime(&pClrHost.GetInterfacePtr());

      if (FAILED(hrBind))
        _com_raise_error(hrBind);
      // start it up
      pClrHost->Start();
    }

  }
  catch (const _com_error &e)
  {
    const wchar_t *message = (wchar_t *)e.Description() == NULL ?
      L"" :
      (wchar_t *)e.Description();
    std::wcerr << L"Error 0x" << std::hex << e.Error() 
      << L") : " << message << std::endl;

    returnCode = e.Error();
  }
  return 0;
}
~~~ 

~~~ Cpp
HRESULT CClrHost::BindToRuntime(__deref_in IUnmanagedHost **pHost)
{
  _ASSERTE(pHost != NULL);
  *pHost = NULL;

  CComObject<CClrHost> *pClrHost = NULL;
  HRESULT hrCreate = CComObject<CClrHost>::CreateInstance(&pClrHost);

  if (SUCCEEDED(hrCreate))
  {
    pClrHost->AddRef();
    *pHost = static_cast<IUnmanagedHost *>(pClrHost);
  }

  return hrCreate;
}
~~~ 


~~~ cpp
HRESULT CClrHost::FinalConstruct()
{
  ICLRMetaHost       *pMetaHost = NULL;
  HRESULT hr;
  hr = CLRCreateInstance(CLSID_CLRMetaHost, IID_ICLRMetaHost,
    (LPVOID*)&pMetaHost);

  IEnumUnknown * pRtEnum = NULL;
  ICLRRuntimeInfo *info = NULL;
  ULONG fetched = 0;
  ICLRRuntimeHost *m_pClr = NULL;
  bool runtimesLoaded = false;
  WCHAR strName[128];
  DWORD len = 128;

  pMetaHost->EnumerateInstalledRuntimes(&pRtEnum);
  while ((hr = pRtEnum->Next(1, (IUnknown **)&info, &fetched)) 
    == S_OK && fetched > 0)
  {
    ZeroMemory(strName, sizeof(strName));
    info->GetVersionString(strName, &len);
    hr = info->GetInterface(CLSID_CLRRuntimeHost,
      IID_ICLRRuntimeHost,
      reinterpret_cast<LPVOID *>(&m_pClr));
    if (!SUCCEEDED(hr))
      printf("hr failed....");
    m_CLRRuntimeMap[std::wstring(strName)] = m_pClr;
    this->m_lastCLR.assign(strName);
  }
  pRtEnum->Release();
  pRtEnum = NULL;
  pMetaHost->Release();

  return S_OK;
}
~~~ 

##Start
Once we've found and loaded all of the CLRs we want, we need to start them. But before we do, we need to set our options. If you were to call `IUnmanagedHost::Start()` without setting any of the additional interfaces you will get a standard CLR to execute your .NET code in.

That is good. But we need to customize our CLR a bit so we can spin up new application domains when a query is started and unload them when it is finished. **This functionality is not implemented in these examples but will be in later posts.**

In the example below you can see that we are looping through the `m_CLRRuntimeMap` that was populated in the Initialization step above. This allows us to set our main `CClrHost` object as the implementation of IHostControl. We also set our AppDomainManager type with the two strings provided.

Once we're done we call `ICLRRuntimeHost::Start()`. This kicks off a new application domain and calls the `AppDomainManager::InitializeNewDomain()` method. This sets the flag `RegisterWithHost`.
This flag tells the AppDomain to call into the `IHostManager::SetAppDomainManager()` method.

Inside of the `IHostManager::SetAppDomainManager()` we are given the AppDomain integer Id as well as a pointer to the AppDomain Manager. We check to see if it implements our `IManagedHost` interface. If it does we call a method we created called `IManagedHost::GetCLR()` this returns a text representation of the current version. This is used to add to the AppDomainManager std::map; this std::map holds the DEFAULT AppDomains.

After this method returns we have officially started our CLR.

>**NOTE** As before, this code will run for BOTH v2.0 and v4.0. It would also run for any OTHER CLRs that are allowed to be loaded side by side.

~~~ Cpp
const wchar_t *CClrHost::AppDomainManagerAssembly 
  = L"mysql_managed_interface, Version=1.0.0.0, PublicKeyToken=71c4a5d4270bd29c";
const wchar_t *CClrHost::AppDomainManagerType 
  = L"mysql_managed_interface.MySQLHostManager";

STDMETHODIMP CClrHost::raw_Start()
{
  // we should have bound to the runtime, but not yet started it upon entry
  if (!m_started)
  {
    _ASSERTE(!m_started);
    for (auto &x : m_CLRRuntimeMap)
    {
      ICLRRuntimeHost *m_pClr = x.second;
      // get the CLR control object
      HRESULT hrClrControl = m_pClr->GetCLRControl(&m_pClrControl);
      if (FAILED(hrClrControl))
        return hrClrControl;

      // set ourselves up as the host control
      HRESULT hrHostControl = 
      m_pClr->SetHostControl(static_cast<IHostControl *>(this));

      // setup the AppDomainManager
      HRESULT hrSetAdm = 
      m_pClrControl->SetAppDomainManagerType(
        AppDomainManagerAssembly, 
        AppDomainManagerType);

      if (FAILED(hrSetAdm))
        return hrSetAdm;

      // finally, start the runtime
      HRESULT hrStart = m_pClr->Start();
      if (FAILED(hrStart))
        return hrStart;
    }

    // mark as started
    m_started = true;
  }
  return S_OK;
}
~~~ 


~~~ Csharp
 public override void InitializeNewDomain(AppDomainSetup appDomainInfo)
{
  // let the unmanaged host know about us
  InitializationFlags = AppDomainManagerInitializationOptions.RegisterWithHost;
  return;
}
~~~ 


~~~ Cpp
STDMETHODIMP CClrHost::SetAppDomainManager(DWORD dwAppDomainId, 
  __in IUnknown *pUnkAppDomainManager)
{
  // get the managed host interface
  IManagedHost *pAppDomainManager = NULL;
  if (FAILED(pUnkAppDomainManager->QueryInterface(
    __uuidof(IManagedHost), 
    reinterpret_cast<void **>(&pAppDomainManager))))
  {
    _ASSERTE(!"AppDomainManager does not implement IManagedHost");
    return E_NOINTERFACE;
  }
  // register ourselves as the unmanaged host
  HRESULT hrSetUnmanagedHost = 
    pAppDomainManager->raw_SetUnmanagedHost(
      static_cast<IUnmanagedHost *>(this));

  if (FAILED(hrSetUnmanagedHost))
    return hrSetUnmanagedHost;

  auto clr = std::wstring(pAppDomainManager->GetCLR());
  // save a copy
  m_appDomainManagers[clr] = pAppDomainManager;
  return S_OK;
}
~~~ 

##Running Our Method

Now that we have our default AppDomain spun up it is time to execute code. After MySQL finishes with the `_init()` method, it calls the core function. In this case `mysqldotnet_int()`. This is where we will actually execute our custom method and return the data to MySQL.

For now, we're not actually going to spin up a new AppDomain to load an assembly. What we are going to do is use our default application domain manager to execute our simple `Run()` method.

The `RunApplication()` method gets the default managed host and calls the `Run()` method with the parameter. Remember that in our `CComObjectRootEx::FinalConstruct()` method we set the member `m_lastCLR` to what ever the last thing to fall out of the enumeration was. *In my case it was the v4.0 CLR.*

We use this default host when we go to execute our `Run()` method we implemented. Our AppDomain manager exposes `Run()` via a COM visible interface. The implementation is simple right now, but we will expand it to run a custom assembly in later posts.

>**NOTE** I should go ahead and say I'm breaking one of those cardinal rules of when to use globals. Since our UDFs have the ability for us to pass items between methods I should use that construct. However, we need to make sure we keep our references to our std::maps or they will be deleted when the object goes out of scope. I trust that this is an okay use, but requires some extra protection around it dealing with multi threaded calls. That being said I can be a bit lazy sometimes.

~~~ Cpp
// MySQL UDF core implementation

long long mysqldotnet_int(UDF_INIT *initid, UDF_ARGS *args, 
  char *is_null, char *error)
{
  int returnCode = 0;
  try
  {
    longlong val = 0;
    uint i;
    for (i = 0; i < args->arg_count; i++)
    {
      if (args->args[i] == NULL)
        continue;
      switch (args->arg_type[i]) {
      case STRING_RESULT:    /* Add string lengths */
        val += args->lengths[i];
        break;
      case INT_RESULT:    /* Add numbers */
        val += RunApplication(pClrHost, 
          *((longlong*)args->args[i]));
        break;
      case REAL_RESULT:    /* Add numers as longlong */
        val += (longlong)((double)RunApplication(pClrHost, 
          *((longlong*)args->args[i])));
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

~~~ Cpp
// Global method called by our UDF

long long RunApplication(IUnmanagedHostPtr &pClr, long long input)
{
  // Get the default managed host
  IManagedHostPtr pManagedHost = pClr->DefaultManagedHost;
  return pManagedHost->Run(input);
}
~~~ 

~~~ Cpp
// IUnmanagedHost::DefaultManagedHost property calls this internally

STDMETHODIMP CClrHost::get_DefaultManagedHost(__out IManagedHost **ppHost)
{
  // just get the AppDomainManager for the default AppDomain
  return raw_GetManagedHost(1, BSTR(m_lastCLR.c_str()), ppHost);
}
~~~ 

~~~Csharp
// Our actual .NET code (cute isn't it?)
public Int64 Run(Int64 path)
{
  return (path * 3);
}
~~~ 

##Subsequent Runs
The same steps are taken when we actually run the core function. However, the only real difference is when the `*_init()` method is called we check the pointer to see if it is null. Check the first code example for this code path.

During testing I found if I assigned a pointer to the ptr field in UDF_INIT, a delete was called by MySQL somewhere in the execution chain. The CLR wasn't unloaded but it cleared out my maps and other state members.

##Wrapping Up
This quick walk through was to show where the code is injected into the MySQL plugin. At this point in the posting we are still adding on features as we go. From here on out I plan to have specific commits that will expose the code examples at the proper points in time.

The next section will go into how we can isolate code execution by spinning up unique application domains per query. This will be one of the core features that makes this solution robust as we can prevent any external code from destroying the integrity of the MySQL environment.

If you have any questions, feel free to leave a comment or contact me on Twitter.

[hosting]: http://msdn.microsoft.com/en-us/library/ms404385(v=vs.110).aspx
[cpp]: https://github.com/jldgit/mysql_udf_dotnet/blob/master/clr_host/ClrHost
[udf]: https://github.com/jldgit/mysql_udf_dotnet/blob/master/mysql_udf.c
[ARGS]: http://dev.mysql.com/doc/refman/5.0/en/udf-arguments.html
[adm]: http://www.microsoft.com/en-us/download/details.aspx?id=7325
[ccom]: http://msdn.microsoft.com/en-us/library/9e31say1.aspx
[custombook]: http://www.amazon.com/gp/product/0735619883/
[stevep]: http://blogs.msdn.com/b/stevenpr/
[pt2]: ({% post_url 2014-11-16-extending-mysql-server-part2 %})
