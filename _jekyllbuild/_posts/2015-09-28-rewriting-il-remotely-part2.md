---
layout: post
title: Rewriting IL - Part 2 - Tokens
tags:
- programming
- debugging
- rewrite il
- chainsapm
- metadata
---
In the [last post][lastpost] we talked about getting the metadata interfaces. This allows us to read (import) and even fiddle (emit) with our precious metadata. What can we do with this? Right now tools like Just Decompile, ILSpy, [ILDASM][ildasm] and others use these to read the files off disk and chew through the data to produce a decompiled version. What are we going to do with it? We're going to merge in arbitrary .NET code into existing libraries. In order to do that we have to have correct tokens.

##What Are Tokens?
Tokens are a way for the .NET to look up and identify Definitions (Def) and References (Ref). You can think of them like handles in programming. They are abstract identifiers that describe nothing other than what table and what row you can find this data in. If you open up [ILDASM][ildasm] and turn on "Show Token Values" you can start peering into how the CLR will stitch things together .

![TokenMenu](/images/ildasm_viewtoken.png)

You can also view the actual tables using [ILDASM][ildasm], by selecting the options below. This will produce all of the metadata tables used by this assembly.

![TokenMenu](/images/ildasm_viewmeta.png)

Some key enumerations can be found here:

* [CorElementAttr][CorElem] - Managed types
* [CorCallingConvention][CorCall] - Calling conventions
* [CorMethodImpl][CorImpl] - Method implementation features
* [CorMethodAttr][CorAttr] - Method features

##MetaData Tables
When the CLR profiler loads a module it gives you the ability to query for the ModuleMetaData interfaces you need by using the [`ICorProfilerInfo::GetModuleMetaData()`][modmeta] method. The best place to do this is in the [`ICorProfilerCallback::ModuleLoadFinished()`][modfin] method. This ensures all data is in memory from the file. A code example is in my last blog post [here][lastpost].

However, if you want to look at ALL of the data you can just open up [ILDASM][ildasm] from your developer command prompt. If you view the MetaInfo you will find a lot of tables like the one below. There is a lot of information packed in there and you can start making sense of it by referencing the [ECMA-335 spec][ecma]. It's a dry read; for me it was easier to start poking at the interfaces and MetaInfo and referring back to the spec for clarification.

There are a ton of metadata tables (44) some are unused and some are reserved for future use. The list below is pared down to show the ones that are most used when rewriting. That's not to say you'd NEVER use the other ones, but it depends on what you want to do. Let's look at the method table to get our feet wet.

|Table ID|Table Type|
|---|---|
| 0x1 | TypeRef - Defines types OUTSIDE of this assembly. |              
| 0x2 | TypeDef - Defines types INSIDE of this assembly.|              
| 0x6 | Method - Defines a Method INSIDE of this assembly. |                      
| 0xa | MemberRef - Defines a method, property, field, etc. either inside or outside of this assembly |                 
| 0x11 | StandAloneSig - Used to define signatures for fields, properties, and locals. |       
| 0x1a | ModuleRef - Any managed or unmanaged DLL reference. |           
| 0x1b | TypeSpec - Used to define instantiated generic types. |            
| 0x23 | AssemblyRef - Created a reference to an OUTSIDE assembly. |          
| 0x2b | MethodSpec - Used to define instantiated generic methods.  |           

##MetaInfo Method Table (0x6) Detail from ILDASM
~~~
=================================================
 6(0x6): Method               cRecs:   18(0x12), cbRec: 14(0xe), cbTable:   252(0xfc)
  col  0:  RVA          oCol: 0, cbCol:4, ULONG  
  col  1:  ImplFlags    oCol: 4, cbCol:2, USHORT
  col  2:  Flags        oCol: 6, cbCol:2, USHORT
  col  3:  Name         oCol: 8, cbCol:2, string
  col  4:  Signature    oCol: a, cbCol:2, blob   
  col  5:  ParamList    oCol: c, cbCol:2, Param  
-------------------------------------------------
   1 == 0:00002050, 1:0000, 2:0886, 3:string#6f8, 4:blob#8a, 5:Param[8000001]
   2 == 0:00002058, 1:0000, 2:0886, 3:string#70b, 4:blob#10, 5:Param[8000001]
   3 == 0:00002061, 1:0000, 2:0886, 3:string#71e, 4:blob#8a, 5:Param[8000002]
   4 == 0:00002069, 1:0000, 2:0886, 3:string#72f, 4:blob#10, 5:Param[8000002]
~~~

>**TIP** if you search for a specific table you should try searching for N(0x#): where N is the base 10 number and # is the base 16 number so for MemberRef seach for 10(0xa):

Above we can see there are 6 columns (plus the row 1 == 0:00...). From left to right they are the Relative Virtual Addess, the Implmentation Flags, the Method Name in the string heap, Method Flags, Signature Blob Entry, Parameters.

So in table form we would have this:

|Row|RVA|ImplFlags|Flags|Name|Signature|ParamList|
|---|---|---------|-----|----|---------|---------|
|1|00002050|0000|0886|string#6f8|blob#8a|Param[8000001]|
|2|00002058|0000|0886|string#70b|blob#10|Param[8000001]|
|3|00002061|0000|0886|string#71e|blob#8a|Param[8000002]|
|4|00002069|0000|0886|string#72f|blob#10|Param[8000002]|

In code you might see a token resembling `0x06000001` which would indicate we're looking for a Method Definition at row 1. This method's IL could be found at the RVA of 0x2050. The [implementation flags][CorImpl] suggest this is IL code (see below), and the [attribute flags][CorAttr] say this is a special name, hide by sig, and public.

I can also see this has 0 parameters. By convention all parameters are stored sequentially for a method definition. So, it would appear that the first method definition takes no paramters because the ParamList value is the same as the next row. This is a convention you can find in  [ECMA-335 spec][ecma] quoted below.

>ParamList (an index into the Param table). It marks the first of a contiguous run of Parameters owned by this method. The run continues to the smaller of:
>
* the last row of the Param table
* the next run of Parameters, found by inspecting the ParamList of the next
row in the MethodDef table

What is a Special name? Well thats anything thats `get_`, `set_`, `.ctor`, `.cctor`, etc. In fact if we look at the string blob for this item it's `get_ModuleToTarget()` which of course is the internal implementation for a property getter.

What about the Signature? See the next section on heaps for more info.

~~~cpp
typedef enum CorMethodImpl
{
    // code impl mask
    miIL                 =   0x0000,   // Method impl is IL.

    // Flags removed for clarity, see link above
} CorMethodImpl;
~~~

~~~cpp
// MethodDef attr bits, Used by DefineMethod.
typedef enum CorMethodAttr
{
    // member access mask - Use this mask to retrieve accessibility information.
    mdPublic                    =   0x0006,     // Accessibly by anyone who has visibility to this scope.
    // end member access mask

    mdHideBySig                 =   0x0080,     // Method hides by name+sig, else just by name.

    // method implementation attributes.
    mdSpecialName               =   0x0800,     // Method is special.  Name describes how.

    // Flags removed for clarity, see link above
} CorMethodAttr;
~~~

##Heaps and Blobs - String Heap

Some data can't be stored inline because it would alter the layout of the row on disk. That would have the terrible side effect of creating a variable length rows which would have to encode an integer and not allow for reuse of things like an empty constructor signature, or the interning of strings.

If you read through blog posts of some of the original creators of the CLR one of the main tenets was to make everything small. Bandwidth will show up A LOT in these older documents. Which stands to reason as back in 2000 dial-up was alive and well in a lot of places and if you had to download an applicaiton, an extra couple megabytes in metadata could add a few minutes of download time.

There are two main storage locations that metadata will pull from. The BLOB (Binary Large Object) heap and the String Heap. Let's first look at the string heap as it will make the most sense. The string heap is a Multi-Byte characater heap; which is surprising given .NET and Window's nature to support Unicode explicitily. From [ILDASM][ildasm] it would look something like this. In order to find your string you would simply look at the hex address after the string#. So for instance `string#6f8` from above would be found in the list at address 000006f8.

>**TIP** if you search for strings by just the smallest number "6f8" you might have a few dozen to a few hundred hits. Pad the number with a few 0's to help. (ie. 0006f8)

~~~
String Heap:  2397(0x95d) bytes
00000000: 00                                               >                <
00000001: 49 45 6e 75 6d 65 72 61  62 6c 65 60 31 00       >IEnumerable`1   <
0000000f: 49 43 6f 6c 6c 65 63 74  69 6f 6e 60 31 00       >ICollection`1   <
0000001d: 49 4c 69 73 74 60 31 00                          >IList`1         <
00000025: 3c 4d 6f 64 75 6c 65 3e  00                      ><Module>        <
<<< REMOVED FOR CLARITY >>>
000006f8: 67 65 74 5f 4d 6f 64 75  6c 65 54 6f 54 61 72 67 >get_ModuleToTarg<
        : 65 74 00                                         >et              <
<<< REMOVED FOR CLARITY >>>
~~~

**String Interning** In an effort to save space the string heap may intern your data. So a likely case would be if you use IEnumerable<T> and Enumerable<T> in your code, both sting references would point to the same location, however IEnumerable would have the address of 0xf and Enumerable would be 0x10 (0xf + 1).

The string heap is obviously easy to understand because you can read. But something not as obvious is the blob heap.

##Heaps and Blobs - Blob Heap

In the spirit of saving space the CLR team decided to store your signatures, typespecs, methodspecs, and just about everything else inside of the blob heap. If it can be cleanly be stored as binary and isn't part of the string heap or string locals it will be here.

The most common thing you will find here are signatures. Whether they are for a method, locals, fields or properties, they will be here. Let's focus on the simple signature from the same method above.

I'm going to skim a few details about the signature in this post but will go in depth in a later post. Don't worry, if you want to skip ahead this info is in [ECMA-335 spec][ecma]. In this instance we can see that we are looking at a method signature that is a default calling convention and it `HASTHIS`. It has 0 parameters and returns a string. This is probably one of the simplest signatures out there so you can read it manually; however, look at #e8. It's a local signature with 25 local variables containing generics, classes, and primitive types.

|Calling Convention|Parameter Count|Return Type|
|------------------|---------------|-----------|
|IMAGE_CEE_CS_CALLCONV_DEFAULT (0x00) \| IMAGE_CEE_CS_CALLCONV_HASTHIS (0x20) | 0x00 | ELEMENT_TYPE_STRING (0x0e) |


~~~
Blob Heap:  812(0x32c) bytes
    0,0 :                                                  >                <
    1,4 : 20 01 01 08                                      >                <
    6,3 : 20 00 01                                         >                <
<<< REMOVED FOR CLARITY >>>
   e8,30: 07 19 02 15 12 71 01 0e  15 12 71 01 0e 15 12 71 >     q    q    q<
        : 01 0e 15 12 71 01 08 0e  0e 0e 0e 1d 05 08 08 02 >    q           <
        : 02 02 12 69 1c 12 6d 02  12 69 1c 02 02 12 69 1c >   i  m  i    i <
<<< REMOVED FOR CLARITY >>>
   7b,5 : 20 00 12 80 81                                   >                <
   81,4 : 20 00 12 69                                      >   i            <
   86,3 : 20 00 1c                                         >                <
   8a,3 : 20 00 0e                                         >                <
   8e,6 : 15 12 80 89 01 0e                                >                <
~~~

~~~cpp
typedef enum CorCallingConvention
{
    // ITEMS REMOVED FOR CLARITY

    IMAGE_CEE_CS_CALLCONV_DEFAULT       = 0x0,
    // The high bits of the calling convention convey additional info
    IMAGE_CEE_CS_CALLCONV_HASTHIS   = 0x20,  // Top bit indicates a 'this' parameter
} CorCallingConvention;
~~~

~~~cpp
typedef enum CorElementType
{
    // ITEMS REMOVED FOR CLARITY

    ELEMENT_TYPE_VOID           = 0x01,
    ELEMENT_TYPE_BOOLEAN        = 0x02,
    ELEMENT_TYPE_CHAR           = 0x03,
    ELEMENT_TYPE_I1             = 0x04,
    ELEMENT_TYPE_U1             = 0x05,
    ELEMENT_TYPE_I2             = 0x06,
    ELEMENT_TYPE_U2             = 0x07,
    ELEMENT_TYPE_I4             = 0x08,
    ELEMENT_TYPE_U4             = 0x09,
    ELEMENT_TYPE_I8             = 0x0a,
    ELEMENT_TYPE_U8             = 0x0b,
    ELEMENT_TYPE_R4             = 0x0c,
    ELEMENT_TYPE_R8             = 0x0d,
    ELEMENT_TYPE_STRING         = 0x0e,

} CorElementType;
~~~

##What can we do with these?
Using the metadata interfaces we can start looking at the properties of the tokens and creating an internal mapping of the types in our injection assembly and we can attempt to find them in the target assembly. Here is a high level of what I am doing in my application.

1. Enumerate my injection assembly for all types, methods, references, etc.
2. Build a list of tokens and identifiers I can use to search my target assembly
3. Loop through my list of tokens and search for matching types, methods and specs in the target
4. Create definitions and references if needed
5. Create a map of injection -> target lookups
6. Scan the injection IL for tokens and replace with the proper versions
7. Append or Prepend IL

###Tokens in IL
In this example we're looking at `MemberRefs (0x0A)` since all of the methods we're calling are members of an assembly not contained in this assembly or module. In general you'll find the following tokens inside of IL.

|Table ID|Table Type|
|---|---|
| 0x1 | TypeRef - Found when casting or checking |
| 0x2 | TypeDef - Found when casting or checking |
| 0x6 | Method - Found when calling |
| 0xa | MemberRef - Found when calling or loading (field instance)|
| 0x11 | StandAloneSig - Found when calling |
| 0x1b | TypeSpec - Found when casting or checking |
| 0x2b | MethodSpec - Found when calling  |

If we wanted to inject this method into another type inside of another assembly we'd have to find all definitions of System.DateTime, System.DateTime::get_Now(), System.DateTime::ToFileTimeUtc() and map these accordingly. If there aren't any we'd have to use the emit interfaces to define mappings to DateTime. My hunch is they are already there in bigger libraries.

In that same mind set, if we wanted to insert new code into `mscorlib` we could actually replace the MemberRef tokens with MethodDef (0x06) tokens.  I have provided the [ILDASM][ildasm] output of the code and an in memory view (modified) of the IL code as it would be stored.

>**Note** I am displaying the tokens as they would be found in memory, that is little-endian format, where AA BB CC DD left to right would be DD CC BB AA.

>**Another Note** I am making up the tokens below.
0A000032 will map to 06000A32
0A000033 will map to 06000A33

~~~
.method /*06000016*/ public hidebysig instance void
        DateTimeExample() cil managed
// SIG: 20 00 01
{
  // Method begins at RVA 0x26cc
  // Code size       16 (0x10)
  .maxstack  1
  .locals /*11000004*/ init ([0] uint64 dtutc,
           [1] valuetype [mscorlib/*23000001*/]System.DateTime/*0100001E*/ V_1)
  IL_0000:  /* 00   |                  */ nop
  IL_0001:  /* 28   | (0A)000032       */ call       valuetype [mscorlib/*23000001*/]System.DateTime/*0100001E*/ [mscorlib/*23000001*/]System.DateTime/*0100001E*/::get_Now() /* 0A000032 */
  IL_0006:  /* 0B   |                  */ stloc.1
  IL_0007:  /* 12   | 01               */ ldloca.s   V_1
  IL_0009:  /* 28   | (0A)000033       */ call       instance int64 [mscorlib/*23000001*/]System.DateTime/*0100001E*/::ToFileTimeUtc() /* 0A000033 */
  IL_000e:  /* 0A   |                  */ stloc.0
  IL_000f:  /* 2A   |                  */ ret
} // end of method
~~~

###Original in Memory
~~~
IL_0000:  00              nop
IL_0001:  28 32 00 00 0A  call
IL_0006:  0B              stloc.1
IL_0007:  12 01           ldloca.s   V_1
IL_0009:  28 33 00 00 0A  call
IL_000e:  0A              stloc.0
IL_000f:  2A              ret
~~~

###Rewritten in Memory
~~~
IL_0000:  00              nop
IL_0001:  28 32 0a 00 06  call
IL_0006:  0B              stloc.1
IL_0007:  12 01           ldloca.s   V_1
IL_0009:  28 33 0a 00 06  call
IL_000e:  0A              stloc.0
IL_000f:  2A              ret
~~~

##Conclusion
Tokens are the currency of rewriting IL. You use them in exchange for methods, types, and signatures. If you know how to convert your currency you can easily rewrite existing methods. We'll make a quick stop at signature parsing and token compression beforehand. After that, we can dig deeper on things like Generics and really get into some powerful rewriting.

[CorImpl]: https://msdn.microsoft.com/en-us/library/ms233456(v=vs.110).aspx
[CorAttr]: https://msdn.microsoft.com/en-us/library/ms231030(v=vs.110).aspx
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
[lastpost]: ({% post_url 2015-09-16-rewriting-il-remotely-part1 %})
