---
layout: post
title: MySQL .NET Hosting Extension - Part 0
tags:
 - mysql
 - .net
 - hosting api
 - extending
---
For some reason I feel compelled to write an extension for [MySQL][mysql] that allows use of .NET classes for functions. It's really a purely academic exercise---even though I'm not in school---that I'm using to explore the use of the [.NET Hosting APIs][hst]. I will use my blog as a way to keep myself focused and accountable. But more over it's so I don't forget what I wanted to do. I will line out a few milestones.

##Background
I started messing around with the Hosting API when I was researching a debugging issue surrounding Host Access Protection. I have a [blog post][blg] that talks about it. This got me curious as to some areas it would be applicable. I wanted to make the extension useful and not just a way for me to load a .NET assembly into a "hello world!" application. Although, that's where this all started.

###What is the Hosting API?
Quite simply, it is a way for you (the developer) to integrate [Microsoft's CLR][clr] implementation into your application. You can extend your application by allowing managed code execution in safe containers that can interact with the state of your application by predefined interfaces. Check out this [article][hst] for more info. I also highly recommend reading [Customizing the .NET Framework][book] by [Steven Pratschner][steve].

###Why MySQL?
Well, I have a soft spot in my heart for this particular database. It was the first real RDBMS that I developed with. I started back in 1999 using the good 'ole LAMP stack. Also, MySQL is used on Windows occasionally and I thought it would be fun trying to extend something I've used for so long.

###Will this be production ready?
No, probably never. I think the idea is great, but its too niche to be of any use to a lot of people. I'd like to see it mentioned as examples of what (not) to do when extending MySQL or using the Hosting API.

##Milestones
Like I said before in my opening, I wanted to use the blog as a way to hold myself accountable. The milestones are going to be lofty, changing and probably never fully realized. That being said, here is a short list of what I want to do in the coming weeks and months.

1. <del>Create a simple hello world application using the hosting API</del>
2. <del>Create a simple [User Defined Function][udf] (UDF) for MySQL</del>
3. <del>Send and retrieve data from the UDF</del>
3. <del>Extend the simple UDF to load the CLR</del>
4. <del>Implement a custom interface to interact with the UDF</del>
5. <del>Load an assembly from the file system</del>
6. <del>Allow dynamic loading of UDF based on parameters</del>
7. <del>Implement Host Access Protection to protect MySQL</del>
8. <del>*Extend MySQL to include a BLOB table to install assemblies*</del>
9. <del>*Load assemblies from BLOB table*</del>
10. <del>*Write the same for [Mono][mono]?*</del>

**[EDIT 12/16/2014] I struck out items 9, 10, and 11 even though they are not implemented. As I wrote the tool it was better to load the assemblies from a directory instead of a table for better features. Mono has no defined host integrations that I have found so it may never happen.**

[clr]: http://msdn.microsoft.com/en-us/library/8bs2ecf4(v=vs.110).aspx
[hst]: http://msdn.microsoft.com/en-us/library/dd380850(v=vs.110).aspx
[book]: https://www.microsoft.com/learning/en-us/book.aspx?ID=6895&locale=en-us
[steve]: http://www.linkedin.com/pub/steven-pratschner/0/a92/8a4
[mysql]: http://www.mysql.com/
[udf]: http://dev.mysql.com/doc/refman/5.1/en/adding-udf.html
[mono]: http://www.mono-project.com/
[blg]: ({% post_url 2014-10-21-hostprotectionexception-ssrs %})
