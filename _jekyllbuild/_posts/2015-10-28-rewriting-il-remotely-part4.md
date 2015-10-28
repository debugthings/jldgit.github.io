---
layout: post
title: Rewriting IL - Part 4 - Token Replacement and Signature Rewriting
tags:
- programming
- debugging
- rewrite il
- chainsapm
- metadata
---
In the [last post][lastpost] we talked about signatures and compression and we expanded on Metadata in general. Now we need to talk about the idea of replacing tokens inside of IL and inside of signatures. Being able to do this gives you a tremendous amount of power and flexibility when you start down the path of rewriting IL. Let's take a look at some examples and look at some sample code to replace tokens in a signature and lay the ground work for injecting arbitrary IL.

##Recap on Tokens and Signatures
If you haven't been reading this series I recommend going back a few posts and starting from the beginning to get a better handle on this. But in short, a Metadata token is a way for the CLR to look up a type and know its definition; this can include class layout, methods, members, events, etc. Metadata is broken up into a number of areas (tables) and the token defines the table and row.

A signature is a way for the CLR to know how to consume a specific method or a generic instantiation. The signature is made up of known constants, tokens, integers and algorithms that define things like classes, primitive types, arrays and generic classes.

Some key enumerations can be found here:

* [CorElementAttr][CorElem] - Managed types
* [CorCallingConvention][CorCall] - Calling conventions
* [CorMethodImpl][CorImpl] - Method implementation features
* [CorMethodAttr][CorAttr] - Method features

##Some assumptions
At this point in time I'm going to just dive into the rewriting process. So unfortunately I have to make some assumptions. I will do my best to describe without giving a lesson on writing a CLR profiler or an IL compiler.

1. You are somewhat familiar with IL
2. You can read and understand the [ILRewriting samples][ilsamples]
3. You know about method signatures and compression
4. You are somewhat familiar with Metadata
5. You know why you want to do this

##Replacing a token in a signature
The idea of replacing a token in a signature means you have a signature that contains one or more class---or generic---definitions. For the purposes of this article this original signature will reside in an existing assembly. It also means you have an assembly or module you want to insert this signature into.

Let's start out with the complex stuff first. I say it's complex because of the steps needed to unroll a signature and then package it back up:

1. Parse signature bytes stream
2. Determine if the type is a class or generic
 - If not skip to 10
 - If NULL (end of sig) then exit loop
3. Uncompress that token
4. Look up that token in your source assembly
5. Get the text identifiers (ex. namespace, class, member)
6. Look up that set of identifiers in your destination class
7. Get the resulting token
8. Compress the token
9. Replace token
10. Repeat/Continue at 1

This is the general algorithm and would require some additional logic when looking up the identifier in the target assembly. For instance, you may find that you're using a type that is defined inside of the assembly so you would want to find a TypeDef  (0x02000000) instead of a TypeRef (0x01000000).

This method also applies to your locals signature.

##Replacing a token in IL
A simpler thing to do is replace the token in IL. This is because the token is not compressed and the general structure of IL doesn't have complex logic for definition, such as an array in a signature. You'll notice the steps are just a bit smaller.

1. Parse the IL byte stream
2. Determine if the instruction takes a token
 - If not skip to 8
 - If end of stream then exit loop
3. Look up that token in your source assembly
4. Get the text identifiers (ex. namespace, class, member)
5. Look up that set of identifiers in your destination class
6. Get the resulting token
7. Replace token
8. Repeat/Continue at 1

Tokens in IL are usually constrained to TypeDef/Ref, MethodDef/Ref, TypeSpec, and MethodSpec. As with signatures it's crucial that you replace with a properly defined token. For instance you may use a method in your source assembly that actually belongs to your target assembly. In this case you will need to replace the MethodRef with a MethodDef.

##Creating the Map
In both sets of steps I talk about looking up a token from one assembly and then using that information to look up the resulting token in another assembly. This can get complex because you may find that you don't have a reference in your target assembly so you would need to create one.

I have some [sample code][mdtoken] here that will give the general idea and will keep this blog post from being 2MB of text. This code is inside of a class I named `MetadataHelper`, I use this class to simplify some of the operations that are common against the Metadata for how I intend to use it.

The code shows that I am taking in a set of text for the module, namespace, class and member.  This text gets inspected and ends up calling either Find or Define methods on the IMetaDataEmit interfaces. As well I am also taking in signatures so I can rewrite them if needed. One other key parameter is the original token. This original token is used in the [`GetMappedToken`][mappedtoken] method, that just looks up the token inside of a `std::map<>` member inside of this class.

I did want to show what it looks like to find a member reference inside of another assembly. The idea is if we are looking inside of the same module or assembly then we would look up the type definition, once we have the TypeDef token we would look up the MemberDef.

You can see that I'm also taking in a signature. In order to find the proper method we need to rewrite the signature to accept the proper types. So you can start to see that there is an order of operations that must happen to create a full map before attempting to rewrite.

1. TypeRefs
 - Get ALL TypeRefs
 - Map TypeRef (Convert to TypeDef if needed)
2. MemberRefs
 - Use TypeRef mapping to rewrite signature
 - Map MemberRef (Convert to MemberDef/MethodDef if needed)
3. TypeSpecs
 - Rewrite TypeSpec signature with TypeRefs/TypeDefs
 - Map TypeSpec (Convert parent type to TypeDef if needed)
4. MemberRefs
 - Rewrite MemberRef signature with map
 - Map MemberRef (Convert parent type to TypeDef if needed)
5. MethodSpecs
  - Rewrite MethodSpec signature with map
  - Map MethodSpec (Convert parent type to TypeDef if needed)

>**NOTE** My method will make sure to properly convert from a reference to a definition if it detects the item to be mapped is from that module.

~~~cpp
HRESULT ModuleMetadataHelpers::FindMemberDefOrRef(std::wstring ModuleOrAssembly, std::wstring TypeName,
  std::wstring MemberName, PCCOR_SIGNATURE MethodSignature, ULONG SigLength, mdToken & TypeRefOrDef)
{
  if (ModuleOrAssembly == GetModuleName() | ModuleOrAssembly == GetAssemblyName())
  {
    pMetaDataImport->FindTypeDefByName(TypeName.c_str(), NULL, &TypeRefOrDef);
    if (TypeRefOrDef != mdTypeDefNil)
    {
      return pMetaDataImport->FindMember(TypeRefOrDef, MemberName.c_str(), MethodSignature, SigLength, &TypeRefOrDef);
    }
  }
  else {
    auto match = AssemblyRefs.find(ModuleOrAssembly);
    if (match != AssemblyRefs.end())
    {
      mdToken matchToken = match->second;
      pMetaDataImport->FindTypeRef(matchToken, TypeName.c_str(), &TypeRefOrDef);
      return pMetaDataImport->FindMemberRef(TypeRefOrDef, MemberName.c_str(), MethodSignature, SigLength, &TypeRefOrDef);
    }
    match = ModuleRefs.find(ModuleOrAssembly);
    if (match != ModuleRefs.end())
    {
      mdToken matchToken = match->second;
      pMetaDataImport->FindTypeRef(matchToken, TypeName.c_str(), &TypeRefOrDef);
      return pMetaDataImport->FindMemberRef(TypeRefOrDef, MemberName.c_str(), MethodSignature, SigLength, &TypeRefOrDef);
    }
  }
  return E_FAIL;
}
~~~

##Remote Metadata
The concept of remote Metadata for this post is any Metadata that is not native inside of the assembly you're looking to fiddle with. If you've tried to write your own profiler or other tool, you might have come across the issue of how you're going to take your source assembly Metadata and IL and wedge it into a destination assembly. The task was kind of daunting and I started making some bad decisions going into it.

Shortly after cranking out hundreds of lines of code to transmit the Metadata  ineeded, I found the [`IMetaDataDispenser`][mddispense] interface and the [`OpenScopeOnMemory()`][openscope] method. This solved pretty much all of my concerns. I was now able to lift the metadata as one big blob and send it over the wire. No need to translate the Metadata into some convoluted intermediate format.

Let's take a look at the code that gets the Metadata from a source assembly and saves it to a byte stream so you can send it over the wire, or what ever else you've conjured up. In this code example I'm saving the data into a safe array because it is being consumed by a .NET method. This method uses the [`IMetaDataEmit`][emit]::[`SaveToMemory `][savetomem] method.

>**NOTE** If you were inside of a profiler or any other CLR process that provides a direct line to your Metadata interfaces, you will not need to use IMetaDataDispenser. For example the [`ICorProfilerInfo`][corprof] interface provides the [`GetModuleMetaData`][modmeta] method.

~~~cpp
void GetMetadataBytesFromFile()
{
	CComPtr<IMetaDataDispenserEx> pMetaDispense;
	CComPtr<IMetaDataEmit2> pMetaEmit;

	CoCreateInstance(
		CLSID_CorMetaDataDispenser,
		NULL,
		CLSCTX_INPROC,
		IID_IMetaDataDispenser,
		(LPVOID *)&pMetaDispense);

  LPWSTR fileName = L"C:\\Windows\\Microsoft.NET\\Framework\\v4.0.30319\\mscorlib.dll";

	pMetaDispense->OpenScope(fileName, ofRead, IID_IMetaDataEmit2, (IUnknown**)&pMetaEmit);

	ULONG SaveSize = 0;
	pMetaEmit->GetSaveSize(cssAccurate, &SaveSize);
	void * saveData = malloc(SaveSize);
	pMetaEmit->SaveToMemory(saveData, SaveSize);
	SAFEARRAYBOUND bounds[1];
	bounds[0].cElements = SaveSize;
	bounds[0].lLbound = 0;
	bytearray = SafeArrayCreate(VT_UI1, 1, bounds);
	void * pDataArray;
	SafeArrayAccessData(bytearray, &pDataArray);
	memcpy(pDataArray, saveData, SaveSize);
}

~~~

Now that this method has given us an in memory copy of the we need to open it on our remote system that will do the injection. To do this you simply create another `IMetadataDispenser` interface on your target machine and call `OpenScopeOnMemory`.

~~~cpp
void OpenFromMemory(const void * memoryAllocation, ULONG totalSize)
{

	CComPtr<IMetaDataDispenserEx> pMetaDispense;
	CComPtr<IMetaDataImport2> pMetaImportMemory;
	CoCreateInstance(
		CLSID_CorMetaDataDispenser,
		NULL,
		CLSCTX_INPROC,
		IID_IMetaDataDispenser,
		(LPVOID *)&pMetaDispense);

	pMetaDispense->OpenScopeOnMemory(memoryAllocation, totalSize, ofRead, IID_IMetaDataImport2, (IUnknown**)&pMetaImportMemory);

  // Enumerate members

  // Get Tokens

  // Etc.
}
~~~

Cool. Now that we have an easy way to get the Metadata, let's look at an easy way to rewrite your method and local signatures so you don't have to do too much heavy lifting.

##Mapping Signatures the Easy Way
So while pouring over the Metadata interfaces documents I found a few methods that looked like they would work. Before I found this way I worked through all of the ways to find, define and rewrite my own signatures. It was rewarding because I now know the ins and outs of that process. I recommend you attempt this yourself or study existing code to grapple with the basics. This will help you debug any execution engine exceptions.

While I do recommend you attempt the code yourself, it can become kind of flimsy if things change between CLR versions (unlikely). You should also have a strong concept of mapping tokens manually since there are no helper methods for IL.

What I'm going to demonstrate is the the [`TranslateSigWithScope()`][transsig] method. This guy makes the whole process of signature rewriting a breeze.

For this we will need the following interfaces.

1. A **blank** `IMetaDataEmit` interface
 - `pMetaEmitBlank`
2. An `IMetaDataAssemblyImport` interface for the source assembly
 - `pMetaAssemblyImport`
3. An `IMetaDataImport` interface for the source assembly
 - `pMetaImport`
4. An `IMetaDataAssemblyEmit` for the target assembly
 - `pMetaAssemblyEmitDLL`
5. An `IMetaDataEmit` for the target assembly
 - `pMetaEmitDLL`

~~~cpp
// This snippet is from a a larger bit of code.

CComPtr<IMetaDataEmit2> pMetaEmitBlank;

CoCreateInstance(
    CLSID_CorMetaDataDispenser,
    NULL,
    CLSCTX_INPROC,
    IID_IMetaDataDispenser,
    (LPVOID *)&pMetaDispense);

pMetaDispense->DefineScope(CLSID_CorMetaDataRuntime, ofRead, IID_IMetaDataEmit2, (IUnknown**)&pMetaEmitBlank);

pMetaImport->GetMemberRefProps(mdMembrRef,
    	&memberToken,
    	memberRefNameBuffer,
    	_ countof(memberRefNameBuffer),
    	&numChars,
    	&originalMemberSigature,
    	&originalMemberSigatureLen);
if (originalMemberSigatureLen > 0)
{
	// Translate the signatures to align with our injected DLL
	pMetaEmitBlank->TranslateSigWithScope(
    pMetaAssemblyImport,
    hashVal,
    hashLen,
    pMetaImport,
    originalMemberSigature,
    originalMemberSigatureLen,
    pMetaAssemblyEmitDLL,
    pMetaEmitDLL,
    newSigBuff,
    1024,
    &newSigBuffLen);
}
~~~

That's it. Two method calls.

#Quick Point in IL Token Replacement
Replacing tokens in IL is not the difficult part. What can be difficult is being able to predict the call site and not cause too much over head. I will get into that in a blog post that follows this one. But for now let's take a look at the code that helps us replace tokens.

This bit of code extends the ILRewriter class that [Dave Broman][davebro] provides as an example. The class is created by passing in the IL body bytes and turning it into a doubly linked list of IL instructions. The list items help identify the IL opcode and the parameter being passed to that code.

In the sample below are all of the opcodes that use tokens. You'll notice that I'm taking in my `ModuleMetadataHelpers` class to call the `GetMappedToken` method. If you recall in the "Mapping" section I describe how we can map all of the source types, methods, and what not to the destination tokens.

~~~cpp
HRESULT ILRewriter::ReplaceTokens(std::shared_ptr<ModuleMetadataHelpers> mdHelper)
{
	for (ILInstr * pInstr = m_IL.m_pNext; pInstr != &m_IL; pInstr = pInstr->m_pNext)
	{
		switch (pInstr->m_opcode)
		{
		case CEE_BOX:
		case CEE_CALL:
		case CEE_CALLI:
		case CEE_CALLVIRT:
		case CEE_CASTCLASS:
		case CEE_CPOBJ:
		case CEE_INITOBJ:
		case CEE_ISINST:
		case CEE_JMP:
		case CEE_LDELEM:
		case CEE_LDFTN:
		case CEE_LDOBJ:
		case CEE_LDSFLD:
		case CEE_LDSFLDA:
		case CEE_LDTOKEN:
		case CEE_LDVIRTFTN:
		case CEE_NEWARR:
		case CEE_NEWOBJ:
		case CEE_REFANYVAL:
		case CEE_SIZEOF:
		case CEE_STELEM:
		case CEE_STFLD:
		case CEE_STOBJ:
		case CEE_STSFLD:
		case CEE_UNBOX:
		case CEE_UNBOX_ANY:
			pInstr->m_Arg32 = mdHelper->GetMappedToken(pInstr->m_Arg32);
		default:
			break;
		}
	}
	return S_OK;
}
~~~

Where this is necessary is if you have foreign IL code that you're trying to inject into an existing method. Again, this topic is waaaayyy out of scope for this specific post, but will become clearer in the next post (or two).

##Conclusion
Now, things are really heating up. The previous three posts were to get you familiar with signatures, tokens, and Metadata at large. From this post forward we will start covering general rewriting and get a little deeper into the unmanaged CLR interfaces.


[ilsamples]: http://clrprofiler.codeplex.com/releases/view/97738
[corprof]: https://msdn.microsoft.com/en-us/library/vstudio/ms233177(v=vs.100).aspx
[emit]: https://msdn.microsoft.com/en-us/library/vstudio/ms230877(v=vs.100).aspx
[savetomem]: https://msdn.microsoft.com/en-us/library/vstudio/ms232930(v=vs.100).aspx
[mddispense]: https://msdn.microsoft.com/en-us/library/vstudio/ms231881(v=vs.100).aspx
[openscope]: https://msdn.microsoft.com/en-us/library/vstudio/ms230286(v=vs.100).aspx
[transsig]: https://msdn.microsoft.com/en-us/library/vstudio/ms230816(v=vs.100).aspx
[mappedtoken]: https://github.com/chainsapm/chainsapm/blob/c786e252c3fcefc68834fdb84cc3f1122727afd3/metadatastaticlib/src/ModuleMetadataHelpers.cpp#L214-L222
[mdtoken]: https://github.com/chainsapm/chainsapm/blob/c786e252c3fcefc68834fdb84cc3f1122727afd3/metadatastaticlib/src/ModuleMetadataHelpers.cpp#L231-L315
[corencode]: https://github.com/dotnet/coreclr/blob/e879597385221df7131042d1e0830b87f7632a01/src/inc/cor.h#L2226
[elemclass]: https://github.com/dotnet/coreclr/blob/4cf8a6b082d9bb1789facd996d8265d3908757b2/src/inc/corhdr.h#L884
[elemgen]: https://github.com/dotnet/coreclr/blob/4cf8a6b082d9bb1789facd996d8265d3908757b2/src/inc/corhdr.h#L887
[localcc]: https://github.com/dotnet/coreclr/blob/4cf8a6b082d9bb1789facd996d8265d3908757b2/src/inc/corhdr.h#L957
[elemsza]: https://github.com/dotnet/coreclr/blob/4cf8a6b082d9bb1789facd996d8265d3908757b2/src/inc/corhdr.h#L894
[elemarr]: https://github.com/dotnet/coreclr/blob/4cf8a6b082d9bb1789facd996d8265d3908757b2/src/inc/corhdr.h#L886
[hasthiscc]: https://github.com/dotnet/coreclr/blob/4cf8a6b082d9bb1789facd996d8265d3908757b2/src/inc/corhdr.h#L967
[defaultcc]: https://github.com/dotnet/coreclr/blob/4cf8a6b082d9bb1789facd996d8265d3908757b2/src/inc/corhdr.h#L953
[sigparse]: http://blogs.msdn.com/b/davbr/archive/2005/10/13/sample-a-signature-blob-parser-for-your-profiler.aspx
[elemstring]: https://github.com/dotnet/coreclr/blob/4cf8a6b082d9bb1789facd996d8265d3908757b2/src/inc/corhdr.h#L876
[elemint]: https://github.com/dotnet/coreclr/blob/4cf8a6b082d9bb1789facd996d8265d3908757b2/src/inc/corhdr.h#L870
[elemclass]: https://github.com/dotnet/coreclr/blob/4cf8a6b082d9bb1789facd996d8265d3908757b2/src/inc/corhdr.h#L884
[corsig]: https://github.com/dotnet/coreclr/blob/e879597385221df7131042d1e0830b87f7632a01/src/inc/cor.h#L2090-L2514
[corhdr]: https://github.com/dotnet/coreclr/blob/4cf8a6b082d9bb1789facd996d8265d3908757b2/src/inc/corhdr.h
[compress]: https://github.com/dotnet/coreclr/blob/e879597385221df7131042d1e0830b87f7632a01/src/inc/cor.h#L2372-L2400
[CorImpl]: https://msdn.microsoft.com/en-us/library/ms233456(v=vs.110).aspx
[CorAttr]: https://msdn.microsoft.com/en-us/library/ms231030(v=vs.110).aspx
[CorElem]: https://msdn.microsoft.com/en-us/library/ms232600(v=vs.110).aspx
[CorCall]: https://msdn.microsoft.com/en-us/library/ms231239(v=vs.110).aspx
[ildasm]: https://msdn.microsoft.com/en-us/library/aa309387(v=vs.71).aspx
[multifile]: https://msdn.microsoft.com/en-us/library/168k2ah5(v=vs.110).aspx
[modmeta]: https://msdn.microsoft.com/en-us/library/ms231432(v=vs.110).aspx
[ecma]: http://www.ecma-international.org/publications/files/ECMA-ST/ECMA-335.pdf
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
[lastpost]: {% post_url 2015-10-13-rewriting-il-remotely-part3 %}
