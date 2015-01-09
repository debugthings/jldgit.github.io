--- 
layout: post
title: MySQL .NET Hosting Extension - Part 9 - Final Bits
tags:
- mysql
- .net
- hosting api
- extending
- udf
---
The first commit of this project was on November 11th, 2014. At that time I just planned on loading the CLR and running some basic code just to prove it worked. But, as I read through [Customizing the Microsoft® .NET Framework Common Language Runtime (Developer Reference)][custombook] I found some great ideas to keep the project from being just a book mark on a page somwhere and really added enough features and robustness to be run on an enterprise level server.

##Download
No GIT commands this time. Please follow [this link][installer] to get the installer.

##What's Included?
Inside of ths installer you will have the following items to choose from. The source code is available.

 - 64-bit version of plugin
 - 32-bit version of 
 - MySQL scripts for registering plugin
 - Samples
   + mysqld.exe.config file examples
   + MySQL Stored Procedure examples
   + Source for SimpleExtension
   + Binaries for SimpleExtension
   + Source for ComplexExtension
   + Binaries for SimpleExtension

##MySQL .NET UDF Installation
 1. Download Installer
 2. Run Installer
 3. Select MySQL Directory
 4. Select version of code
 5. Finish

##MySQL .NET UDF SQL Installation Steps
 1. Open your favorite MySQL client
 2. Run install_udf.sql
 3. Test installation by executing `SELECT MYSQLDOTNET_INT('MySQLCustomClass.CustomMySQLClass', 3);`
 4. Load Sample Applications using the provided Stored Procedure examples

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