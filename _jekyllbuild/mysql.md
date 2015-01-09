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

##MySQL .NET UDF SQL Installation Steps
 1. Copy .NET Samples (or your own) to the `lib\plugins` directory
 2. Open your favorite MySQL client
 2. Run `CREATE FUNCTION MYSQLDOTNET_INT RETURNS INTEGER SONAME "MySQLDotNet.dll";`
 3. Test installation by executing `SELECT MYSQLDOTNET_INT('MySQLCustomClass.CustomMySQLClass', 3);`
 4. Load Sample Applications using the provided Stored Procedure examples

[32bit]: /installer
[64bit]: /installer

