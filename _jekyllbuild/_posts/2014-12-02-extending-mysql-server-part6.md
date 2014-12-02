--- 
layout: post
title: MySQL .NET Hosting Extension - Part 6 - Supporting Side-by-Side .NET CLRs
tags:
- mysql
- .net
- hosting api
- extending
- udf
---
So far, we've done a lot to the CLR hosting engine to properly handle type loading, type safety and custom assemblies. Now we have the task to support some desired functionality supplied with the CLR. Namely being able to support, or not support side-by-side CLR loading. We will take a look at what code changes are involved and what we can do to ensure proper loading.

##How to get the code

Enter the following commands in your GIT command prompt. It's that simple. All code changes as I have shown them in this blog post should be there. If you come across this post at a way later date, try increasing the range from 5 to 10, and so on.

~~~
git clone https://github.com/jldgit/mysql_udf_dotnet.git -b wip-nextversion
git log --abbrev-commit -n 5 --pretty=oneline

91e2238 Changes relating to post 6
6d017b0 Changes relating to post 5
303d9cd Changes relating to post 4
5d721fa Good working copy.
6a588f8 Work in progress.

git checkout 91e2238
~~~

##What's Changed?
In this version I added support for both v4.0 binding and legacy (v2.0) binding. The legacy binding only allows one CLR at a time to be loaded. By default v4.0 allows side-by-side loading of the CLRs. This is by design so you can properly load and execute [mixed-mode assemblies][mixed]--assemblies that contain both native and managed code.

###Updated clr_lib
The static .NET CLR library has been updated to check what version of .NET is loaded using C++. With that check it knows to use the newer APIs or the legacy APIs. Being able to select the proper binding method allows the hosting engine to behave as users would expect.

###MySQLHostManager has 2 versions
We now have 2 versions of the MySQLHostManager. This allows us to configure per CLR version specific features. For the time being they are copies of each other. There isn't much difference between the AppDomain versions, but at least we're linking to the proper assemblies.

As well these assemblies are installed in the GAC so they can be referenced by their fully qualified name. This is used when setting the AppDomain manager for the DefaultDomain in each CLR.

##Expanded Walkthrough
The code changes made were simple enough. The first item I'll walk through is enumerating the registry for the installed CLR versions. The second item I'll walk through is the binding logic.

###Enumerating the CLR versions 
Thankfully Microsoft provides [this article][clrreg] on how to determine what version(s) of .NET are installed on your machine. It is as simple as enumerating the registry with `RegOpenKeyEx()` and `RegEnumKeyEx()`. I don't flag the bitness in my code as it would highly unlikely that the x64 version is installed and the x86 is not.

~~~Cpp
// Use this to find out what versions of the CLR are installed.
// We will prefer to use v4.0 for now; this is not future proof as v5 may come out soon
#define MAXSTRING 128
HKEY netFrame;
hr = RegOpenKeyEx(HKEY_LOCAL_MACHINE, "SOFTWARE\\Microsoft\\NET Framework Setup\\NDP", 
NULL, KEY_READ | KEY_QUERY_VALUE | KEY_ENUMERATE_SUB_KEYS, &netFrame);
int keyIndex = 0;
char keys[10][MAXSTRING]; // Store 10 keys x 128bytes
BOOL has40 = FALSE;
WCHAR version[MAXSTRING];
DWORD versionSize = 0;

while (hr == 0)
{
  DWORD keyLen = MAXSTRING;
  ZeroMemory(keys[keyIndex], MAXSTRING);
  hr = RegEnumKeyEx(netFrame, keyIndex, keys[keyIndex], &keyLen, NULL, NULL, NULL, NULL);
  if (hr == ERROR_ACCESS_DENIED)
    return hr;
  if (!has40)
  {
    has40 = strcmp(V4, keys[keyIndex]);
  }
  if (keyIndex++ > 10)
    break; // There shouldn't be 10 keys here, but some high random number is better than 
           // letting it go forever.
}
~~~

###Proper CLR Binding
After we check to see what versions of the CLR we have loaded we need to check to see if we are using a legacy binding model. Most machines now have .NET 4.0. Version 4.5 comes standard since Sever 2012 and .NET 4.0 was released in 2010. However they may be a few Machines out there that only have .NET 3.5 installed. Since MySQL runs just about everywhere it's plausible that we will be on a Windows 2008 server somewhere.

After we've checked the CLR versions we set a flag `has40` to let us know if we should use the newer binding facilities. While .NET 2.0 is supported (for now), the legacy methods are being depreciated and should not be used.

We check use the `IMetaHostPolicy` interface which looks at the mysqld.exe.config file to determine a few things. The first thing it can determine is if we're using the v2 binding policy. We apply a mask to the `actFlags` DWORD and check to see if the value true us set. If it is we will disable the side-by-side load--as you can see in the second code snippet.

We can also check to see what the preferred CLR version is. This is a good way to guarantee that we're only loading a specific version of the .NET CLR. While it's not very common you could load an older version of the CLR; so if you end up deploying this to multiple servers you can lock in the version. This would be useful for consistency.

If the version string is invalid for the default CLR to load then we will return an error.

~~~Cpp
bool disableSxS = FALSE;
// If we have 4.0 try to use the 4.0 binding policy.
if (has40)
{
  DWORD actFlags = 0;
  hr = CLRCreateInstance(CLSID_CLRMetaHostPolicy, IID_ICLRMetaHostPolicy,
    (LPVOID*)&pMetaHostPolicy);
  if (FAILED(hr))
    return hr;

  hr = pMetaHostPolicy->GetRequestedRuntime(
    METAHOST_POLICY_USE_PROCESS_IMAGE_PATH,
    NULL,
    NULL,
    NULL,
    &versionSize,
    NULL,
    NULL,
    &actFlags,
    IID_ICLRRuntimeInfo,
    reinterpret_cast<LPVOID *>(&info));
  if (FAILED(hr))
    return hr;

  // Check the preferred version
  hr = info->GetVersionString(version, &versionSize);
  if (FAILED(hr))
    return hr;

  disableSxS = (actFlags & METAHOST_CONFIG_FLAGS_LEGACY_V2_ACTIVATION_POLICY_MASK) 
  & METAHOST_CONFIG_FLAGS_LEGACY_V2_ACTIVATION_POLICY_TRUE; // Disable SxS

  hr = CLRCreateInstance(CLSID_CLRMetaHost, IID_ICLRMetaHost,
    (LPVOID*)&pMetaHost);
  if (FAILED(hr))
    return hr;
}

// If we don't have 4.0, bind the old way to the latest version (v2.0.50727)
if (!has40) {

  // In the case of our binding we will force the required version.
  // If we fail this kills the initilization of the CLR
  hr = GetCORRequiredVersion(version, MAXSTRING, &versionSize);
  if (FAILED(hr))
    return hr;

  hr = CorBindToRuntimeEx(version,
    NULL,
    0,
    CLSID_CLRRuntimeHost,
    IID_ICLRRuntimeHost,
    reinterpret_cast<LPVOID *>(&m_pClr));

  if (FAILED(hr))
    return hr;

  // Pulled out common startup items.
  return SetupCLR(m_pClr, version, version);

}
~~~


~~~Cpp
// If no runtimes are loaded we will make sure to load them all based on the policy.
// This will set the default runtime as the last CLR to be loaded.
// At the time of writing this application it is 4.5 (4.0)
if (!runtimesLoaded)
{
  pMetaHost->EnumerateInstalledRuntimes(&pRtEnum);
  while ((hr = pRtEnum->Next(1, (IUnknown **)&info, &fetched)) == S_OK && fetched > 0)
  {
    ZeroMemory(strName, sizeof(strName));
    info->GetVersionString(strName, &len);

    // If we are disabling side by side execution 
    // (useLegacyV2RuntimeActivationPolicy) then only load the speficied CLR
    // If we haven't specified SxS policy then load all.
    if (((StrCmpW(strName, version) == 0) & disableSxS) || !disableSxS)
    {
      hr = info->GetInterface(CLSID_CLRRuntimeHost,
        IID_ICLRRuntimeHost,
        reinterpret_cast<LPVOID *>(&m_pClr));
      if (FAILED(hr))
        return hr;

      // Pulled out common startup items.
      hr = SetupCLR(m_pClr, strName, version);
      if (FAILED(hr))
        return hr;
    }

  }
  pRtEnum->Release();
}
~~~

##Wrapping Up
This version of the code supports proper side-by-side loading and binding depending on the policy selected. We also check to make sure that we are being passed a correct specific version of the CLR.

As we move forward with the utility we will incorporate some new functionality that allows configuration on a per assembly level.

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