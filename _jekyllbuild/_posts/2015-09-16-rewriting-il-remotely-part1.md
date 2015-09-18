---
layout: post
title: Rewriting IL - Part 1 - Metadata Interfaces
tags:
- programming
- debugging
- rewrite il
- chainsapm
- metadata
---
I think it goes without saying that rewriting IL is no trivial thing. However, I'll just go ahead and say it again, rewriting IL is no trivial thing. If you jump on Code Project you'll find a ton of resources that span the years. In fact when I started my project I turned to these very same articles. I found a couple of them that rely on using an injection library but are somewhat of a hack---very brilliant hacks mind you. So, in order to be above board I started down the path of using a profiler to inject IL. Let's find out why this is not a trivial thing.

##IL Rewriting Basics - Getting Metadata
Before I jump right in to the dirty details I'm going to give a 10,000 foot view of the process I'm following. I will give a bit more detail on each step in this post and then just firehose you with shit you don't want to know in later posts.

1. Load the Profiler
2. Initialize the profiling interface
3. **Monitor module loads**
4. **Get the module metadata interfaces**
5. Monitor JIT compilation start
6. Rewrite IL before it's compiled
7. Pray it worked

I left out a bunch of details for the sake of not making the list over 100 items long. There are seriously a lot of rules in place, it's not like x86 assembly where you can add a JMP any old place you please, PUSHAD, POPAD and then JMP back. Well, I mean you **COULD** do this, but you're just asking for trouble.

## #3 Monitoring Module Loads
Yeah, I skipped 1 and 2. For now, just know that when the profiler dll is loaded by the CLR you're given a chance to do initialization (an interface callback into your profiler.) Inside of the initialization you query for the proflier info interface.

I will have a few articles on this later down the road. For now I want to dig into the meat of what this profiler is meant to do. Quite simply I'm viewing(Importing) and altering(Emiting) the metadata for my assemblies as well as my modules. The first thing we need to do is know when a module has been loaded and ready to be consumed.

In order to monitor these loads I set the [`COR_PRF_MONITOR_MODULE_LOADS`][modloads] flag using [`ICorProfilerInfo::SetEventMask`][setmask]. A full code example can be found in the [`Cprofilermain::SetMask()`][cprofsetmask] in the ChainsAPM project. You should note that `SetEventMask2()` is preferred. For now you can use the non versioned one.

~~~cpp
Cprofilermain::SetMask() {
  // Trimmed down version for example
  DWORD eventMask = (DWORD)(COR_PRF_MONITOR_MODULE_LOADS);
  m_pICorProfilerInfo->SetEventMask(eventMask);
}
~~~

After this flag is set the [`ICorProfilerCallback::ModuleLoadStarted()`][modstart] and [`ICorProfilerCallback::ModuleLoadFinished()`][modfin] interfaces are now wired up. These will execute for each module that is loaded whether it is bound to an assembly or not. So, this means you may run into a case where you try to find the parent assembly but it's NULL. So in that case you can look for it in [`ICorProfilerCallback::ModuleAttachedToAssembly()`][modattached]. See the note below for a longer explanation.

>A module can be loaded through an import address table (IAT), through a call to LoadLibrary, or through a metadata reference. As a result, the common language runtime (CLR) loader has multiple code paths for determining the assembly in which a module lives. Therefore, it is possible that after ICorProfilerCallback::ModuleLoadFinished is called, the module does not know what assembly it is in and getting the parent assembly ID is not possible. The ModuleAttachedToAssembly method is called when the module is attached to its parent assembly and its parent assembly ID can be obtained.

## #4 Get the Module Metadata Interface
Now that the profiler is letting us know that we have modules loading, unloading and attaching we can go about the business of getting the metadata Interfaces. These interfaces are the heart and soul of how we're going to start rewriting. In order to do this there is a method you call from the `ICorProfilerInfo` interface you got from the mysterious steps 1 and 2. You use that interface to call this method [`ICorProfilerInfo::GetModuleMetaData()`][modmeta].

~~~cpp
ICorProfilerCallback::ModuleLoadFinished(ModuleID moduleID, HRESULT hrStatus) {}
  CComPtr<IMetaDataImport> pImport;
  {
  	CComPtr<IUnknown> pUnk;

  	hr = m_pICorProfilerInfo->GetModuleMetaData(moduleID, ofRead, IID_IMetaDataImport, &pUnk);
  	hr = pUnk->QueryInterface(IID_IMetaDataImport, (LPVOID * ) &pImport);
  }


  CComPtr<IMetaDataAssemblyImport> pAssemblyImport;
  {
    CComPtr<IUnknown> pUnk;

    hr = m_pICorProfilerInfo->GetModuleMetaData(moduleID, ofRead, IID_IMetaDataAssemblyImport, &pUnk);
    hr = pUnk->QueryInterface(IID_IMetaDataAssemblyImport, (LPVOID * )&pAssemblyImport);

  }
}
~~~

This snippet shows that we can use the `ICorProfilerCallback::ModuleLoadFinished` callback to grab the metadata for this specific module. Now we have the keys to the *meta*-phorical kingdom (see what I did there?) Yeah, I want to kill me for making that joke too. Anyway, we now can do just about anything the CLR does to resolve your code.

If you've ever wondered how you get such descriptive information from the CLR, like stack traces, parameter names, method names, etc. It all hinges on the robust metadata system that .NET uses. Well now that we have it what can we do with it? Let's take a look.

###Enumerate all referenced assemblies
Using this you can see what assemblies your module's assembly is referencing---that is of course if the module is bound to an assembly. Knowing this you can easily do a TypeRef lookup against that assembly if you know the type name.

~~~cpp
// Generic buffers for enumeration
HCORENUM hEnumAssembly = NULL;
mdAssemblyRef rgAssemblyRefs[1024]{ 0 };
ULONG numberOfTokens;
wchar_t assemblyRefNameBuffer[255];
ULONG numChars = 0;
// Resuable buffers for assembly info
char *publicKeyToken = NULL;
char *hashVal = NULL;
ULONG pktLen = 0;
ULONG hashLen = 0;
DWORD flags = 0;
ASSEMBLYMETADATA amd{ 0 };
do
{
  hr = pAssemblyImport->EnumAssemblyRefs(
    &hEnumAssembly,
    rgAssemblyRefs,
    _countof(rgAssemblyRefs),
    &numberOfTokens);

  for (size_t i = 0; i < numberOfTokens; i++)
  {

    pAssemblyImport->GetAssemblyRefProps(rgAssemblyRefs[i],
    (const void**)&publicKeyToken,
      &pktLen,
      assemblyRefNameBuffer,
      _countof(assemblyRefNameBuffer),
      &numChars,
      &amd,
      (const void**)&hashVal,
      &hashLen,
      &flags);
  }
} while (hr == S_OK);
pImport->CloseEnum(hEnumAssembly);
~~~

###Enumerate all defined types
All types (classes, value types, etc.) are defined inside of your module. You can use this enumeration to find all of your types and use these type definitions to enumerate all of your methods, properties, events, signatures, everything.

~~~cpp
// Enum Type Defs

HCORENUM hEnumTypeDefs = NULL;
mdTypeDef rgTypeDefs[1024]{ 0 };
ULONG numberOfTokens;
wchar_t typeDeffNameBuffer[255];
ULONG numChars = 0;
DWORD attrFlags = 0;
mdToken tkExtends = mdTokenNil;

do
{
  hr = pImport->EnumTypeDefs(
    &hEnumTypeDefs,
    rgTypeDefs,
    _countof(rgTypeDefs),
    &numberOfTokens);

  for (size_t i = 0; i < numberOfTokens; i++)
  {
    pImport->GetTypeDefProps(rgTypeDefs[i],
    	typeDeffNameBuffer,
    	255,
    	&numChars,
    	&attrFlags,
    	&tkExtends);
    auto s = std::wstring(typeDeffNameBuffer);
  }

} while (hr == S_OK);

pImport->CloseEnum(hEnumTypeDefs);
~~~

###Enumerate all referenced types
Any type that is not defined in your assembly will have a TypeRef defined for some other distinct type. For instance you might call System.Threading.Thread.Sleep(). This would have an AssemblyRef to `mscorlib` and a TypeRef to `System.Threading.Thread`. You would them have a `MemberRef` to the `Sleep()` method.

~~~cpp
//Enum TypeRefs

HCORENUM hEnumTypeRefs = NULL;
mdTypeRef rgTypeRefs[1024]{ 0 };
ULONG numberOfTokens;
wchar_t typeDeffNameBuffer[255];

ULONG numChars = 0;
DWORD attrFlags = 0;
mdToken tkExtends = mdTokenNil;
mdToken resolutionScope;

do {
  hr = pImport->EnumTypeRefs(
    &hEnumTypeRefs,
    rgTypeRefs,
    _countof(rgTypeRefs),
    &numberOfTokens);

    for (size_t i = 0; i < numberOfTokens; i++)
    {
      pImport->GetTypeRefProps(rgTypeRefs[i],
        &resolutionScope,
        typeDeffNameBuffer,
        255,
        &numChars);
      if ((resolutionScope & 0x1A000000) == 0x1A000000)
      {
        pImport->GetModuleRefProps(resolutionScope,
        modRefNameBuffer,
        255,
        &numChars);
        auto s2 = std::wstring(typeDeffNameBuffer);
      }

      if ((resolutionScope & 0x23000000) == 0x23000000)
      {
        char publicKeyToken[1024];
        char hashVal[1024];
        ULONG pktLen = 0;
        ULONG hashLen = 0;
        DWORD flags = 0;
        ASSEMBLYMETADATA amd{ 0 };
        pAssemblyImport->GetAssemblyRefProps(resolutionScope,
          (const void**)&publicKeyToken,
          &pktLen,
          modRefNameBuffer,
          255,
          &numChars,
          &amd,
          (const void**)&hashVal,
          &hashLen,
          &flags);

        auto s2 = std::wstring(typeDeffNameBuffer);
      }
    }
} while (hr == S_OK);

pImport->CloseEnum(hEnumTypeRefs);
~~~

## What's next?
Now that we've seen how we can get this well defined data we can start making some smart decisions on how we want to rewrite our IL. As stated I could get type  references to other classes and call `newobj` using that TypeRef to create a brand new `System.Diagnostics.Stopwatch`. I could then get a MemberRef to `calllvirt Start()`.

Really, I can do just about anything now that I know how it's going to be referenced. In the next post I'm going deep on metadata. I'll explain about the tables and how they are used. I will also talk about some things you can and can't do with the System.Reflection namespace that would be useful for rewriting.

[davebro]: http://blogs.msdn.com/b/davbr/
[clrprofiler]: https://clrprofiler.codeplex.com/
[chains]: https://github.com/chainsapm/chainsapm
[setmask]: https://msdn.microsoft.com/en-us/library/ms230853(v=vs.110).aspx
[modloads]: view-source:https://msdn.microsoft.com/en-us/library/ms231874(v=vs.110).aspx
[cprofsetmask]: https://github.com/chainsapm/chainsapm/blob/7719622aa908954807c339b704f77acafcf467be/clrprofiler/src/profiler/profilermain.cpp#L476-L551
[modstart]: https://msdn.microsoft.com/en-US/library/ms231897(v=VS.110).aspx
[modfin]: https://msdn.microsoft.com/en-us/library/ms230105(v=vs.110).aspx
[modattached]: https://msdn.microsoft.com/en-us/library/ms232480(v=vs.110).aspx
[modmeta]: https://msdn.microsoft.com/en-us/library/ms231432(v=vs.110).aspx
