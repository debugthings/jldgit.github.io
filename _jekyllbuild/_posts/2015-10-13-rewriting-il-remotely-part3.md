---
layout: post
title: Rewriting IL - Part 3 - Signatures and Compression
tags:
- programming
- debugging
- rewrite il
- chainsapm
- metadata
---
In the [last post][lastpost] we talked about tokens and how they are like handles to types, methods, signatures, and really just about everything else. They are the currency that the CLR deals with. Today we talk about signatures, these guys are the biggest consumers of tokens outside of IL.

##What Are Signatures?
Signatures are the first line of defense when it comes to fully describing your parameters and locals at runtime. The method signature will help identify all of the types being supplied to the method, the direction of the types, number of elements in an array, the list goes on. Since it's a well defined format that doesn't rely on raw address spaces it has the benefit of being the same between machine to machine and architecture to architecture.

Some key enumerations can be found here:

* [CorElementAttr][CorElem] - Managed types
* [CorCallingConvention][CorCall] - Calling conventions
* [CorMethodImpl][CorImpl] - Method implementation features
* [CorMethodAttr][CorAttr] - Method features

##Simple Static Method Signature
Let's look at a method and it's signature in Metadata. This is a fairly trivial signature to decode just by looking at it. The static method takes in two strings and outputs one string.

~~~csharp
static string ConcatStrings (string str1, string str2) {}
~~~

~~~
00 02 0e 0e 0e
~~~

|Calling Convention|Parameter Count|Return Type|Parameter 1|Parameter 2|
|------------------|---------------|-----------|-----------|-----------|
|`0x00`|`0x02`|`0x0e`|`0x0e`|`0x0e`|

The table above has the following 1 byte identifiers specifying a simple type.

* `0x00 = `[`IMAGE_CEE_CS_CALLCONV_DEFAULT`][defaultcc]
* `0x02 = 2 parameters`
* `0x0e = `[`ELEMENT_TYPE_STRING`][elemstring]
* `0x0e = `[`ELEMENT_TYPE_STRING`][elemstring]
* `0x0e = `[`ELEMENT_TYPE_STRING`][elemstring]

*Wait. Where is `static`?* This isn't held in the signature (directly) because its an attribute of the method (see [CorMethodAttr][CorAttr]). What's great about this is if I have any amount of methods with this signature the compiler will only emit this once. For example, I have four static methods defined in another type. If you look at the Metadata directly below the C# code you'll see that I have 5 methods defined and all of them have the same signature blob \#53.

>Click on the ELEMENT_TYPE_* or IMAGE_CEE_* names to see their definition in the [corhdr.h][corhdr] file on GitHub.

~~~csharp
public static string ConcatStrings5 (string str1, string str2) {
  return str1 + str2;
}

private static string ConcatStrings6 (string str1, string str2) {
  return str1 + str2;
}

internal static string ConcatStrings7 (string str1, string str2) {
  return str1 + str2;
}

protected static string ConcatStrings8 (string str1, string str2) {
  return str1 + str2;
}
~~~

~~~
=================================================
 6(0x6): Method               cRecs:   17(0x11), cbRec: 14(0xe), cbTable:   238(0xee)
  col  0:  RVA          oCol: 0, cbCol:4, ULONG  
  col  1:  ImplFlags    oCol: 4, cbCol:2, USHORT
  col  2:  Flags        oCol: 6, cbCol:2, USHORT
  col  3:  Name         oCol: 8, cbCol:2, string
  col  4:  Signature    oCol: a, cbCol:2, blob   
  col  5:  ParamList    oCol: c, cbCol:2, Param  
-------------------------------------------------
<<< 0 - 8 REMOVED >>>
9 == 0:00002124, 1:0000, 2:0096, 3:string#50, 4:blob#53, 5:Param[800000b]
a == 0:00002140, 1:0000, 2:0091, 3:string#5f, 4:blob#53, 5:Param[800000d]
b == 0:0000215c, 1:0000, 2:0093, 3:string#6e, 4:blob#53, 5:Param[800000f]
c == 0:00002178, 1:0000, 2:0094, 3:string#7d, 4:blob#53, 5:Param[8000011]
<<< d - f REMOVED >>>
10 == 0:000021b0, 1:0000, 2:0091, 3:string#30d, 4:blob#53, 5:Param[8000016]

Blob Heap:  444(0x1bc) bytes
<<< LINES REMOVED >>>
   53,5 : 00 02 0e 0e 0e                                   >                <
~~~

##Simple Instance Method Signature
This isn't terribly different from the static instance except for the calling convention.

~~~csharp
string ConcatStringsInstance (string str1, string str2) {}
~~~

~~~
20 02 0e 0e 0e
~~~

|Calling Convention|Parameter Count|Return Type|Parameter 1|Parameter 2|
|------------------|---------------|-----------|-----------|-----------|
|`0x20`|`0x02`|`0x0e`|`0x0e`|`0x0e`|

The table above has the following 1 byte identifiers specifying a simple type.

* `0x20 = `[`IMAGE_CEE_CS_CALLCONV_HASTHIS`][hasthiscc]` (0x20) |  `[`IMAGE_CEE_CS_CALLCONV_DEFAULT`][defaultcc]` (0x00)`
* `0x02 = 2 parameters`
* `0x0e = `[`ELEMENT_TYPE_STRING`][elemstring]
* `0x0e = `[`ELEMENT_TYPE_STRING`][elemstring]
* `0x0e = `[`ELEMENT_TYPE_STRING`][elemstring]

This tells the CLR that this signature has the `this` parameter as the first parameter. This is not unlike instance members in C++ where the `__thiscall` is implied and passes the `this` parameter as the first parameter.

##A More Complex Method Example
Of course this is a simple method, but .NET isn't a simple language to implement. Nor are the problems being solved. Let's take a look at a signature for a method with a few external types, generics and even some arrays.

~~~csharp
public Something ReturnSomething(int one, System.Threading.Thread t) {
  return new Something ();
}
~~~

~~~
20 02 12 0c 08 12 45
~~~

|Calling Convention|Parameter Count|Return Type|Parameter 1|Parameter 2|
|------------------|---------------|-----------|-----------|-----------|
|`0x20`|`0x02`|`0x12 0x0c`|`0x08`|`0x12 0x45`|

The table above has the following 1 byte identifiers specifying a simple type.

* `0x20 = `[`IMAGE_CEE_CS_CALLCONV_HASTHIS`][hasthiscc]` (0x20) |  `[`IMAGE_CEE_CS_CALLCONV_DEFAULT`][defaultcc]` (0x00)`
* `0x02 = 2 parameters`
* `0x12 = `[`ELEMENT_TYPE_CLASS`][elemclass]
  * `0x0c = Compressed Token; see below`
* `0x08 = `[`ELEMENT_TYPE_I4`][elemint]
* `0x12 = `[`ELEMENT_TYPE_CLASS`][elemclass]
  * `0x45 = Compressed Token; see below`

###Compressed Tokens
Let's take a pause and look at how compression is implemented. Right away you can see there is something strange here. If you've been keeping up with the series you might expect to see a fully qualified token after the element type; perhaps something like `0x12 0x03 0x00 0x00 0x02` for the return value as `Something` is defined inside of this module. Well, as I've said before, the idea of Metadata was to shave off bytes wherever possible and reduce bandwidth. Sending 4 bytes for each type in a signature would easily increase the size a substantial amount even for simple definitions `type1 method(type2)` for example would be 12 bytes instead of 6.

To get around this, the tokens are compressed. When defining a type you have a couple of ways to do so. A TypeDef, TypeRef, or TypeSpec. Since all tokens are a full integer they will be compressed with the big data logic. Let's step through it here to determine what happens. The full C code is linked [here][corsig].

~~~c
inline ULONG CorSigCompressToken(   // return number of bytes that compressed form of the token will take
    mdToken  tk,                    // [IN] given token
    void *   pDataOut)              // [OUT] buffer where the token will be compressed and stored.
{
    RID     rid = RidFromToken(tk);
    ULONG32 ulTyp = TypeFromToken(tk);

    if (rid > 0x3FFFFFF)
        // token is too big to be compressed
        return (ULONG) -1;

    rid = (rid << 2);

    // TypeDef is encoded with low bits 00
    // TypeRef is encoded with low bits 01
    // TypeSpec is encoded with low bits 10
    // BaseType is encoded with low bit 11
    //
    if (ulTyp == g_tkCorEncodeToken[1])
    {
        // make the last two bits 01
        rid |= 0x1;
    }
    else if (ulTyp == g_tkCorEncodeToken[2])
    {
        // make last two bits 0
        rid |= 0x2;
    }
    else if (ulTyp == g_tkCorEncodeToken[3])
    {
        rid |= 0x3;
    }
    return CorSigCompressData((ULONG)rid, pDataOut);
}
~~~
1. First we get the row ID by bitwise AND of 0x00FFFFFF
  - `0x02000003 & 0x00FFFFFF = 0x03`
2. Then we get the type by bitwise AND of 0xFF000000
 - `0x02000003 & 0xFF000000 = 0x02000000`
3. Check to see if we're compressing a number larger than 0x3FFFFFFF
 - `0y0011 1111 1111 1111` This makes sure the top two MSBs are clear
4. Left shift 2 bits leaving the LSBs clear
- `0x03 << 2 = 0x0C = 0y0000 1100`
5. We check the type against the [`g_tkCorEncodeToken`][corencode] array
 - Since we're a TypeDef we don't change the bottom bits. So the resulting encoded token is 0xC. `0y0000 1100 = 0xC`
6. Compress the newly generated number further
 - 0x0C is less than 0x80 so don't compress it. [See here][compress]

Using this same methodology (in reverse) we can uncompress 0x45 to represent `TypeRef 0x01000011`.

~~~
0y0100 0101
         ^^ = TypeRef (0x01000000)

0y0100 0101 >> 2 = 0y0001 0001 = 0x11
~~~

##Local Signature with a Generic
Locals follow the same convention as signatures and the only real change is instead of a calling convention and return types they just define that it's a local signature and how many parameters there are.

~~~csharp
public ITemplate<Something> ReturnSomethingTemplate
  (int one, ITemplate<System.Net.Sockets.Socket> socket) {
  return new ITemplate<Something> ();
}
~~~

~~~
07 01 15 12 08 01 12 0c
~~~

While it doesn't look like any locals are defined, there actually is ONE local. That is the placeholder for the address that will be returned by the constructor of this method. Let's break this apart and we can see that we have one local for a generic type.

|Calling Convention|Local Count|Parameter 1|
|------------------|-----------|-----------|
|`0x07`|`0x01`|`0x15 0x12 0x08 0x01 0x12 0x0c`|

|GENERICINST|Generic Type|Number of Parameters|Paramter 1|
|-----------|------------|--------------------|----------|
|`0x15`|`0x12 0x08`|`0x01`| `0x12 0x0c`|

* `0x07 = `[`IMAGE_CEE_CS_CALLCONV_LOCAL_SIG`][localcc]
* `0x01 = 1 parameter`
* `0x15 = `[`ELEMENT_TYPE_GENERICINST`][elemgen]
  * `0x12 = `[`ELEMENT_TYPE_CLASS`][elemclass]
    * `0x08 = 0x02000002 (ITemplate'1)`
  * `0x01 = One Generic Type Definition`
  * `0x12 = `[`ELEMENT_TYPE_CLASS`][elemclass]
    * `0x0C = 0x02000003 (Something)`

##Local Signature with an Array
Generics seem tricky but can be done pretty straight forward. Some other types require a bit more logic to pick apart. The quintessential type is the array. Something that is so fundamental requires some solid definition to make sure we understand the shape of the array as well as the number of elements.

~~~csharp
public int [] ReturnTheNubmers (string [] [] number) {
  int [] twenty = new int [20];
  int [,] twenty2 = new int [20, 20];
  return twenty;
}
~~~
~~~
07 03 1d 08 14 08 02 00  02 00 00 1d 08
~~~

|Calling Convention|Local Count|Parameter 1|Parameter 2|Parameter 3|
|------------------|-----------|-----------|-----------|-----------|
|`0x07`|`0x03`|`0x1d 0x08`|`0x14 0x08 0x02 0x00 0x02 0x00 0x00`|`0x1d 0x08`|

###Parameter 1 int[]

|SZARRAY|Array Type|
|-------|----------|
|`0x1d`|`0x08`|

###Parameter 2 int[,]

|ARRAY|Array Type|Array Rank|# of Sizes|Sizes|# of LowerBounds|Lower Bounds|
|-----|----------|----------|----------|-----|----------------|------------|
|`0x1d`|`0x08`   |`0x02`    |`0x00`    | n/a |`0x02`          |`0x00 0x00` |

###Parameter 3 int[]

|SZARRAY|Array Type|
|-------|----------|
|`0x1d`|`0x08`|

* `0x07 = `[`IMAGE_CEE_CS_CALLCONV_LOCAL_SIG`][localcc]
* `0x03 = 3 parameters`
* `0x1d = `[`ELEMENT_TYPE_SZARRAY`][elemsza]
  * `0x08 = `[`ELEMENT_TYPE_I4`][elemint]
* `0x14 = `[`ELEMENT_TYPE_ARRAY`][elemarr]
  * `0x08 = `[`ELEMENT_TYPE_I4`][elemint]
  * `0x02 = Rank`
  * `0x00 = Number of Sizes (0 skips)`
  * `0x02 = Number of Lower Bounds`
  * `0x00 = Lower Bound 1`
  * `0x00 = Lower Bound 2`
* `0x1d = `[`ELEMENT_TYPE_SZARRAY`][elemsza]
  * `0x08 = `[`ELEMENT_TYPE_I4`][elemint]

The simple `int[]` array probably makes sense, but the multi dimensional array will cause you to have to watch it when you decompress as you can have multiple nested types. Imagine the following `ITemplate<string[,,,],ITemplate<List<int[]>, Something>>[,,,,,]` This has multiple types, generics with nested generics and oddly defined arrays. I can tell you it's not pretty. In fact, here ya go. :) If the type names were any shorter than the signature blob would be larger than the string that defines it.

~~~
14 08 02 00 02 00 00 14 15 12 08 02 14 0e 04 00 04 00 00 00 00 15 12 08 02 15 12 45 01 1d 08 12 0c 06 00 06 00 00 00 00 00 00
~~~

##Now What?
Since we can rip apart signatures and locals we can start to understand how to locate locals, to inspect the types, and how to decompress, alter and compress to change the tokens to something else. You can also use this information to write out the signatures of methods to a string.

If you want a good example of a signature parser head over to [Dave Broman's blog][davebro] and check out the [Signature Parser][sigparse]. It was last updated in 2010, but it looks feature complete so it should be able to work on generics and arrays.


##Conclusion
So far we've touched on Metadata, Tokens and Signatures. With these few simple things we can start identifying methods and inspect them to see what types they take in and return. We can also look at the locals and determine what information is being moved around inside of this method.

Next we'll talk about some miscellanea around Rewriting IL that works with all of these things. We'll talk about mapping a token from one type to another. We'll discuss what a safe point is inside of IL and how to detect if we're inside of a branch.

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
[lastpost]: ({% post_url 2015-09-28-rewriting-il-remotely-part2 %})
