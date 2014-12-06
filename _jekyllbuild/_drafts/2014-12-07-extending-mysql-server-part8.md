--- 
layout: post
title: MySQL .NET Hosting Extension - Part 8 - Mimicking IIS (Shadow Copy)
tags:
- mysql
- .net
- hosting api
- extending
- udf
---
One of the coolest things about deploying to IIS is the shadow copy feature. This allows you to drop in a new DLL and when the application detects it, it will spin up a new AppDomain and send all new requests there.

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