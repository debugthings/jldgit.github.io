---
layout: post
title: MySQL .NET Hosting Extension - Part 1 - Compile Sample UDF
tags:
 - mysql
 - .net
 - hosting api
 - extending
 - udf
---
So, the first thing I had to do was compile the MySQL sample UDF which is included in the source tree. While it seems like a simple thing to do with CMake and all of the proper tools installed, there are a few things not documented. The steps to compile [can be found here][compile]. The steps are really straight forward, but there is a catch. In order to build on Windows there are a few steps you will need to do in order to fully get the example working.

##Prerequisites
 1. [The source files][down]
 2. [CMake][cmake]
 3. [Bison][bison]
 4. [Visual Studio 2013][vs2013]

##Issues
With the source tree downloaded I was able to get started. I unfortunately went the route of installing Bazaar and downloading the source. The easier---and better---way is to go [here and download][down] the developer source; make sure you select `Source Code` from the drop down box.

After the source is downloaded, follow the [UDF compile][compile] instructions. Now, try it. Did it work? Probably not. You can try and update the `CMakeLists.txt` file to include extra directories, because it seems like it would help.

```
cmake_minimum_required(VERSION 3.1)
PROJECT(udf_example)

# Path for MySQL include directory
INCLUDE_DIRECTORIES("C:/Users/James/Source/BazaarRepos/mysql-server/mysql-5.5/include")
INCLUDE_DIRECTORIES("C:/Users/James/Source/BazaarRepos/mysql-server/mysql-5.5/sql")
INCLUDE_DIRECTORIES("C:/Users/James/Source/BazaarRepos/mysql-server/mysql-5.5/regex")

ADD_DEFINITIONS("-DHAVE_DLOPEN")
ADD_LIBRARY(udf_example MODULE udf_example.c udf_example.def)
TARGET_LINK_LIBRARIES(udf_example wsock32)

```

Try again. Nope?

You may have seen an error like this: `include\my_global.h(77): fatal error C1083: Cannot open include file: 'my_config.h': No such file or directory`. This is pretty straight forward and says you don't have that file. But how do we get it?

What I found I had to do was do a [full compile][fullcomp] of the MySQL source to generate all of the proper libraries and to generate a few configuration header files. In hind sight if I had found that article before starting with the UDF I would have gotten a lot further.

However, there is still a gotcha here. When compiling `mysqld.exe` you may get an error that looks like this `error LNK2001: unresolved external symbol _xmm@0000001100000010000000050000000f`. Apparently when you compile with debug symbols a few compiler intrinsics make it through the `create_def_file.js` CScript file. In order to fix this you can alter the `IsCompilerDefinedSymbol()` method in the CScript file to look like below. This removes any instance of XMM that is generated in the DEF file.

```js
// returns true if the symbol is compiler defined
function IsCompilerDefinedSymbol(symbol)
{
    return ((symbol.indexOf("__real@") != -1) ||
    (symbol.indexOf("_RTC_") != -1) || 
    (symbol.indexOf("??_C@_") != -1) ||
    (symbol.indexOf("??_R") != -1) ||
    (symbol.indexOf("??_7") != -1)  ||
    (symbol.indexOf("?_G") != -1) ||           // scalar deleting destructor
    (symbol.indexOf("_VInfreq_?") != -1) ||    // special label (exception handler?) for Intel compiler
    (symbol.indexOf("?_E") != -1) ||           // vector deleting destructor
    (symbol.indexOf("_xmm") != -1)||           // Compiler XMM intrinsic
    (symbol.indexOf("__xmm") != -1));          // Compiler XMM intrinsic
}
```

After this change I was able to run the following command `devenv MySQL.sln /build RelWithDebInfo > output_build.txt` to generate all of the files I needed.

Once I had the binaries compiled and all of the headers I needed I attempted to create a standalone project again. This time I only received one error.
`1>udf_example.obj : error LNK2019: unresolved external symbol _stpcpy referenced in function _avgcost_init`. 

In order to fix this I made a quick change to a line of code in the `udf_example.c` file. The proper way would have been to include the strings library that was generated from the full compile but I didn't want to fuss with it completely.

```C
// udf_example.c - Lines removed for brevity

/* BEFORE */
#include <string.h>
#define strmov(a,b) stpcpy(a,b)
#define bzero(a,b) memset(a,0,b)
#endif

/* AFTER CODE CHANGE */
#include <string.h>
#define strmov(a,b) strcpy(a,b)
#define bzero(a,b) memset(a,0,b)
#endif
```

Now the application will compile! At least it did for me. If you want to check you can either install it using the instructions from the compile link above or just execute the `<root>\sql\RelWithDebInfo\mysqld.exe`.

##Results
I compiled and renamed the UDF example to myudf.dll. I was able to load this hello world function into MySQL using the `CREATE FUNCTION` command.

```
mysql> CREATE FUNCTION myfunc_double RETURNS REAL SONAME "myudf.dll";
Query OK, 0 rows affected (0.01 sec)

mysql> SELECT myfunc_double(1.2);
+--------------------+
| myfunc_double(1.2) |
+--------------------+
|              48.33 |
+--------------------+
1 row in set (0.00 sec)

mysql> SELECT myfunc_double(22);
+-------------------+
| myfunc_double(22) |
+-------------------+
|             50.00 |
+-------------------+
1 row in set (0.00 sec)

mysql> SELECT myfunc_double(10000);
+----------------------+
| myfunc_double(10000) |
+----------------------+
|                48.20 |
+----------------------+
1 row in set (0.00 sec)

mysql> SELECT myfunc_double(10000);
+----------------------+
| myfunc_double(10000) |
+----------------------+
|                48.20 |
+----------------------+
1 row in set (0.00 sec)

mysql> SELECT myfunc_double(10000);
+----------------------+
| myfunc_double(10000) |
+----------------------+
|                48.20 |
+----------------------+
1 row in set (0.00 sec)

mysql>
```


[compile]: http://dev.mysql.com/doc/refman/5.5/en/udf-compiling.html
[down]: http://dev.mysql.com/downloads/mysql/
[cmake]: http://www.cmake.org/
[bison]: http://gnuwin32.sourceforge.net/packages/bison.htm
[vs2013]: http://msdn.microsoft.com/en-us/library/dd831853.aspx
[fullcomp]: http://dev.mysql.com/doc/internals/en/cmake-howto-detailed.html
[pt0]: ({% post_url 2014-10-21-hostprotectionexception-ssrs %})
