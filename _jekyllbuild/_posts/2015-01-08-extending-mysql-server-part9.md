---
layout: post
title: MySQL .NET Hosting Extension - Part 9 - Strings, _bstr_t, SafeArrays, SysAllocString, SysFreeString
tags:
- mysql
- .net
- hosting api
- extending
- udf
---
Up until now I've been dealing with integers and reals. This is great for a lot of statistical information but we all know that databases are used for more than just storing numbers. Depending on your type of database you will most likely have a number of text items that are used to describe or othewise identify some integer value. In order to work with these values we have to marshal the data to and fro. Let's dive in to what's happening.

## How to get the code

Enter the following commands in your GIT command prompt. It's that simple. All code changes as I have shown them in this blog post should be there. If you come across this post at a way later date, try increasing the range from 5 to 10, and so on.

~~~
git clone https://github.com/jldgit/mysql_udf_dotnet.git -b wip-nextversion
git log --abbrev-commit -n 5 --pretty=oneline

a790145 Changes relating to post 9
dfcc022 Added Installer executables
0956be5 Added Installers
4a0be76 Changes relating to post 8
e9dc6de Changed relating to post 7

git checkout a790145
~~~

## What's changed
A lot of code has changed in all of the function types. Most notably we have extended and enhanced all of the `mysqldotnet_string` functions. We have also added the ability to identify multipart functions with the keyword **"MULTI"** which is configurable (this is for **all** functions not just the for the string methods). As well to support international characters I have included an option for a code page by setting the first parameter of the string function to an integer.

### MULTI keyword
This configurable keyword tells the UDF that there are multiple values that need to be processed inside of our .NET function calls. For example:

~~~SQL
select mysqldotnet_real("MySQLCustomClass.CustomMySQLClass", "MULTI", 4.1235, 5.345);
~~~

~~~SQL
select mysqldotnet_real("MySQLCustomClass.GeoDistance", "MULTI", 47.63958, -122.12838, 35.14080, -80.92012);
~~~

In the second SQL statement we see that we're calling **"MULTI"** on the GeoDistance function. The implementation details are in the next section. In this case we're expecting 4 values. These 4 values are coordinates on a map of two Microsoft campuses.

### mysqldotnet_string function
Before, this was more of a hollow shell. It didn't provide any correct argument parsing or string use. Now, we can take in and parse string values. There is a new reserved keword **"MULTI"** which tells the function that there is more than one parameter and to pass it to the function that takes in an array. This keyword is configurable in the app settings section in the `mysqld.exe.config` file; as well as the code page.

~~~XML
<mysqlassemblies>
<applicationDefaults
codepage="1252"
multikeyword="MULTI" />
</mysqlassemblies>
~~~

In order to pass a string along to our .NET functions we have to convert the string from a [multibyte][multibyte] character to a Unicode character. Multibyte character buffers are used for anything that is not UTF-16 (which is *Unicode* inside Windows; code page 1200). The characters are still allowed to carry the extended character set, but they do not use a constant 2-byte representation. Read [this wiki][utf8wiki] entry for more detailed information about BOMs and code points.

Unfortunately, there is no built in way to tell what MySQL is sending over in the function without inspecting the element. This gets tricky (tedious) because we have to check the values coming in to the UDF. The best way to do this is have the user supply a code page that corresponds to the Windows supported [code pages][cps]. So, this command now looks for a code page integer as the first argument; otherwise it assumes 1252 (Latin1) based off of the default setting.

## Expanded Walkthrough

### MULTI keyword implementation
As we started talking about in the previous section we have introduced the **"MULTI"** keyword for our GeoCoordinates .NET function. If we were to call the same function with out **"MULTI"** the application would error out because we haven't implemented the single value function.

~~~Csharp
public double RunReal(double value)
{
  throw new NotImplementedException();
}

public double RunReals(double[] values)
{
  if (values.Length >= 4)
  {
    var gc = new System.Device.Location.GeoCoordinate(values[0], values[1]);
    return gc.GetDistanceTo(
      new System.Device.Location.GeoCoordinate(values[2], values[3]));
    }
  }
~~~

The way we've implemented this is simple. We check for an occurance of the keyword in the arguments being passed into the UDF. The code has been abridged, but the basic structure is:

  1. Check for the occurence of a string that should be the **"MULTI"** keyword
  2. Create an array of doubles using a custom templated function
  3. Pass that to our `RunReals()` function.
  4. Return the value directly from the function which should prevent any leaks.

~~~C
switch (args->arg_type[i]) {
  case STRING_RESULT:         /* Add string lengths */
  if (strcmp((char*)args->args[i], "MULTI") == 0)
  {
    for (size_t j = 0; j < args->arg_count - 2; j++)
    {
      longArray[j] = getIntegerForArray<double>(args->args[j], args->arg_type[j]);
    }
    val = RunReals(mhp, _bstr_t(argName), longArray, args->arg_count - 2);
    delete[] longArray;
    return val;
  }
  break;
}
~~~

Each function type (int, real, string) has it's own implementation of the **"MULTI"** keyword check. However, the integer and real versions look very similar. One thing I should point out is the templated function to do a proper job of converting the data from the remainder of the values in the array that is passed in.

~~~Cpp
template<typename _type>
_type getIntegerForArray(char* arg, Item_result type)
{
  switch (type) {
    case INT_RESULT:            /* Add numbers */
    return (_type)*((longlong*)arg);
    break;
    case REAL_RESULT:           /* Add numers as longlong */
    return (_type)*((double*)arg);
    break;
    case STRING_RESULT:
    return (_type)strlen(arg);
    break;
    default:
    return 0;
    break;
  }
}
~~~

### mysqldotnet_string function
In order to support multiple languages we must use Unicode to work with our data. In most RDBMSs you can select a specific characterset and collation. Depending on your locale MySQL will most often use Latin1 (CP_1252) as the default characterset and collation. Latin is a very common and LARGE implmentation but it has some limitations. One of these limitations is it does not contain a definition for Cyrillic text. This presents a small problem if we wish to take this application to places other than the United States, Spain, France, or any other latin based character language.

So, how do we inspect a string to see if it's Unicode or Latin? Fortunately for us there is a built in Windows function that takes care of this for us. It is the aptly named [IsTextUnicode][isunicode] function. Here I will show how we pass in the `char*` to our function from the MySQL UDF.

~~~Cpp
_bstr_t RunString(IManagedHostPtr &pClr, _bstr_t &functionName, char *input, int size, int *codepage)
{
  if (*codepage == 0)
  {
    *codepage = g_codepage;
  }
  int sizeplusterm = size + 1;
  wchar_t* buffer = new wchar_t[sizeplusterm];
  ZeroMemory(buffer, sizeplusterm * sizeof(wchar_t));
  int unicodecheck = IS_TEXT_UNICODE_UNICODE_MASK | IS_TEXT_UNICODE_REVERSE_MASK;
  IsTextUnicode(input, size, &unicodecheck);
  if (unicodecheck > 0 | *codepage == CP_WINUNICODE)
  {
    for (size_t i = 0, j = 0; i < size / 2; i++, j += 2)
    {
      buffer[i] |= (((wchar_t)input[j]) << 0x8) | ((wchar_t)(input[j + 1]));
    }
  }
  else {
    MultiByteToWideChar(*codepage, NULL, input, size, buffer, sizeplusterm);
  }
  return pClr->RunString(functionName, buffer);
}
~~~

If you notice I am calling `pClr->RunString()` directly and I am not converting it to `_bstr_t`. This is because that constructor takes in types of `wchar_t*`. The downside to this is there is no Rvalue reference for the string so it is copied into the new `_bstr_t` object using [SysAllocString][sysalloc]. However, the `_bstr_t` object does a simple copy of the pointer data when passing the bits around so the string is only copied once. Also since we're using a Rvalue the `_bstr_t` object evaporates and calls [SysFreeString][sysfree].

For the **"MULTI"** valued version we have to do a bit more work and it requires us to create a [SafeArray][safearray] to pass data. This is true for **ALL** multi valued functions, but I will show the string implementation to stay on track. The SafeArray isn't the only way to pass data, just as BSTR isn't the only way to pass strings. However, the SafeArray simplfies a lot of steps and performs some helpful cleanup.  The `RunStrings()` code isn't very complex. In short it does the following:

  1. Check to see if we're using a codepage
  2. If so increase the start index from 2 to 3; otherwise set code page to the default
  3. Create a new bounded safe array (see MSDN code example)
  4. Create a new SafeArray with the proper number of elements
  5. Loop through arguments and convert input if needed
  - I explicitly call MultiByteToWideChar() to honor our code pages
  6. Use SysAllocString() to create an OLECHAR to add to the array
  7. Call our .NET function and pass in the array
  8. Destroy the array
  9. Return the `_bstr_t` created from the .NET function

>See the [mysqldotnet_string()][mysqludfcode] function to see how we are assigning the `_bstr_t` from the return of this method to the one on the stack. This will take care of freeing up the resources.

~~~Cpp
_bstr_t RunStrings(IManagedHostPtr &pClr, _bstr_t &functionName, char** input,
  unsigned long *lengths, uint args, int *codepage)
{
  int codepageIndex = 2;
  if (*codepage != 0)
  {
    ++codepageIndex; // Increase index if we have an explicit code page.
  }
  else
  {
    *codepage = g_codepage; // If there is no code page we fall back to the default.
  }


  SAFEARRAYBOUND rgsabound[1];
  rgsabound[0].lLbound = 0;
  rgsabound[0].cElements = args - (codepageIndex - 1);
  SAFEARRAY* sa = SafeArrayCreate(VT_BSTR, 1, rgsabound);
  HRESULT hr = SafeArrayLock(sa);
  for (uint ix = codepageIndex; ix <= args; ix++)
  {
    int txtLen = lengths[ix] + 1;
    auto txt = new wchar_t[txtLen] {};
      int unicodecheck = IS_TEXT_UNICODE_UNICODE_MASK | IS_TEXT_UNICODE_REVERSE_MASK;
      IsTextUnicode(input[ix], lengths[ix], &unicodecheck);
      if ((unicodecheck > 0) | (*codepage == CP_WINUNICODE))
      {
        for (size_t i = 0, j = 0; i < lengths[ix] / 2; i++, j += 2)
        {
          txt[i] |= (((wchar_t)input[j]) << 0x8) | ((wchar_t)(input[j + 1]));
        }
      }
      else {
        MultiByteToWideChar(*codepage, NULL, input[ix], lengths[ix], txt, txtLen);
      }
      ((BSTR*)sa->pvData)[ix - codepageIndex] = SysAllocString(txt);
      delete txt;
    }
    hr = SafeArrayUnlock(sa);
    auto retstring = pClr->RunStrings(functionName, sa);
    SafeArrayDestroy(sa);
    return retstring;
}
~~~

This set of code has demonstrated how we implement SafeArrays, `BSTR` and `_bstr_t` to marshal data between our code bases. You have the ability to marshal your data at `WCSTR` and `CSTR`, but the problem with this is you must define a MAX buffer size. As well you have to remember to delete your string data once you're done.

## Some notes on \_bstr\_t_, BSTR, OLECHAR, SysAllocString and SysFreeString

When I started working with the `_bstr_t` COM helper I noticed I had a lot of memory leaks. So, I set about figuring out why this was happening. In a couple of places, namely the RunStrings() code I was newing up a `_bstr_t` and casting it to a BSTR inside of my safe array. When looking at the MSDN definition of the function it clearly states **"psz [in, optional] The string to copy."** So, when my code would call [SafeArrayDestroy][sadestroy] it would clear out the SafeArray just fine, but it would leave my `_bstr_t` hanging. This also had the added perk of duplicating the string a couple of extra times.

## Finishing Up

One thing I can say for sure is strings are dumb; mainly because I am dumb. It's not often that I deal with special characters since English drops a lot of the accents and diacritial marks, but a lot of folks do. This gets doubly tough if the language is Indo-Asian and deals with glyphs, accents, punctiation all rolled into one symbol. But, truth be told, once you get the hang of it all it's not so bad.

A constant challenge for me was cleaning up the strings as I was moving along. I wasn't used to dealing with referenced counted objects and would prematurely delete some data. Some helpers create copies, while others try to convert your character set if you're not using wide characters; which also creates copies. Some use the standard new operator and some would use SysAllocString. I have blog post coming up that shows how to use WinDbg to debug heap leaks and using VMMap to see where and when my data grows when messing around with strings, _bstr_t_ and BSTR.

[sadestroy]: http://msdn.microsoft.com/en-us/library/windows/desktop/ms221702%28v=vs.85%29.aspx
[mysqludfcode]: https://github.com/jldgit/mysql_udf_dotnet/blob/wip-nextversion/mysql_udf.c#L259
[safearray]: http://msdn.microsoft.com/en-us/library/windows/desktop/ms221482%28v=vs.85%29.aspx
[sysalloc]: http://msdn.microsoft.com/en-us/library/windows/desktop/ms221458(v=vs.85).aspx
[sysfree]: http://msdn.microsoft.com/en-us/library/windows/desktop/ms221481(v=vs.85).aspx
[isunicode]: http://msdn.microsoft.com/en-us/library/windows/desktop/dd318672(v=vs.85).aspx
[utf8wiki]: http://en.wikipedia.org/wiki/UTF-8
[cps]: http://msdn.microsoft.com/en-us/library/windows/desktop/dd317756(v=vs.85).aspx
[multibyte]: http://msdn.microsoft.com/en-us/library/4bb3e64h.aspx
[installer]: /installer
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
