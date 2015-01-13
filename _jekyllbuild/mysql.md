---
layout: default
---
##Download
[Download 64-bit Installer][32bit](includes 32-bit)

[Download 32-bit Installer][64bit]

##What's Included?
Inside of ths installer you will have the following items to choose from. The source code is available.

 - MySQL .NET UDF
   + 64-bit version of the plugin
   + 32-bit version of the plugin
 - Samples
   + MySQL scripts for registering plugin
   + Binaries for SimpleExtension
   + Binaries for ComplexExtension
 - Simple Documentation to get you started

##Packaged Installation
 1. Download installer
 2. Run installer
 3. Select MySQL versions to install for
 4. Select additional options
 5. Done

##QUICKSTART

If you want to jump in using the included examples here is what you need to do.

 1. Verify mysqld.exe.config is in the %MYSQLHOME%\bin\ directory
 2. Copy Samples\MySQLCustomClass.dll to %MYSQLHOME%\lib\plugins\
 - You may also copy it to %MYSQLHOME%\lib\plugins\MySQLCustomClass\
 3. Execute sql_install.sql from the command line or your favorite client

That's it!

Execute one of the following stored procedures. Descriptions included.

**simple_add3toint(int)** --- Adds 3 to the input number

**simple_add3toreal(real)** --- Adds 3 to the input number

**simple_addtostring(string)** --- Adds "SIMPLE EXAMPLE" to the end of the input

**adv_isinradius(LatCenter, LongCenter, LatPoint, LongPoint, radius)** --- Calculates to see if the point is inside of the specified radius from the center.

**adv_distance(LatStart, LongStart, LatEnd, LongEnd)** --- Calculates the distance in meters between the two points.

**adv_getwebpage(webpage)** --- Uses System.WebClient to pull the raw HTML back from the URL in the function.

Examples:

~~~SQL
SELECT dotnet_schema.adv_isinradius(28.03, 81.95, 28.43, 81.32, 80000.0);
SELECT dotnet_schema.adv_distance(28.03, 81.95, 28.43, 81.32);
SELECT dotnet_schema.adv_getwebpage("http://www.google.com");
~~~

[32bit]: https://github.com/jldgit/mysql_udf_dotnet/releases/download/v1.0-rc1/mysql_dotnet_udf_x86_installer_v1.0.msi
[64bit]: https://github.com/jldgit/mysql_udf_dotnet/releases/download/v1.0-rc1/mysql_dotnet_udf_x64_installer_v1.0.msi
