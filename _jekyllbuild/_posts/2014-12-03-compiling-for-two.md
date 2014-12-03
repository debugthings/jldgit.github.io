--- 
layout: post
title: Compiling for Two (.NET versions)
---
While writing the [MySQL plugin][plugin] I found a strange need to compile two versions of my AppDomain Manager. Mainly it was for future compatibility. Plus I figured as long as my Interfaces didn't change, everything would be great. But it left me with a sucking hole in my project solution. I was going to have to maintain two versions of source code **FOR THE EXACT SAME THING**. I didn't like that.

##Something Symbolic
Instead of trying to do some whizbang copy command each time I reached a little deeper into my toolkit and remembered [symbolic links][symlink] from way back when. I don't use them that often any more, however in my hardcore Linux days I used them all the time.

In windows you can use the [mklink][mklink] command to create a new softlink. This softlink behaves just like a real file. Except when you delete the link you do not delete the original file. This has the useful benefit of being able to be referenced inside of numerous locations, but you only edit one file.

In my case I wanted to duplicate functionality between two assemblies. Why didn't I just stick with the older version and just load it into the new CLR? Aren't they the same? Yep, the CLRs are very, very backwards compatible. However, I didn't want to get myself into a spot where 3 years down the road my v2.0 version is obsolete and I have to migrate the project in one big chunk. So, I decided to link it and add a compiler directive to allow me to selectively turn code off and on.

Let's take a look at the mklink command. I list all of the options here but since I'm only looking at creating a symlink. Below the help text is the command I executed.

~~~
>mklink
Creates a symbolic link.

MKLINK [[/D] | [/H] | [/J]] Link Target

        /D      Creates a directory symbolic link.  Default is a file
                symbolic link.
        /H      Creates a hard link instead of a symbolic link.
        /J      Creates a Directory Junction.
        Link    specifies the new symbolic link name.
        Target  specifies the path (relative or absolute) that the new link
                refers to.
~~~

~~~
mklink MySQLHostManager.cs ..\mysql_managed_interface\MySQLHostManager.cs
symbolic link created for MySQLHostManager.cs <<===>> ..\mysql_managed_interface\MySQLHostManager.cs
~~~

That previous command created a new link to `MySQLHostManager.cs` from the actual `MySQLHostManager.cs` file in another directory. The great think about this link is it is relative. So, if you happen to move the entire directory structure up or down a level this will be honored.

##What IF it's a new machine?
Creating this link on my machine was great. But what about my other dev machine, or my VM, or my other machine, or someone else's machine? The answer wasn't to create a wiki page or a link in a doc somewhere, or even this blog post. No, the real solution was to make sure this was repeatable.

Inside of my solution I have a project for the v4.0 version of my assembly. Complete with new references for the new CLR. I added a build event to my assembly to make this link before each run. The problem here is we need to be able to make sure that we don't run the `mklink` command each and every time. Again, falling back to my bag of tricks I used a simple one line batch [IF command][ifcmd].

~~~
IF EXIST MySQLHostManager.cs ( echo "Link Exists") 
ELSE (mklink MySQLHostManager.cs ..\mysql_managed_interface\MySQLHostManager.cs)
~~~

I placed this command inside of my project properties in the pre-build event section. This will guarantee that the link is created the first time you run the build and it will not be attempted to be created after the build.

![Property Page](/images/props.png)

##What about new methods?
Since we now have a good solution to compile for two versions of the CLR, we will need some way to make sure that depreciated methods, or non-existent methods (in the case of v2.0) do not find their way into the wrong compiler. The solution for this was easy as well.

I once again turned to the property pages and added a compilation symbol to designate what version I was compiling for. This can be used in conjunction with a `#ifdef` compiler directive to selectively compile code based on what version you're targeting.

![Compilation Symbol](/images/props_compilation_symbol.png)

~~~Csharp
static void ADIDelegate(string[] args)
{
#if DOTNET40
  var asm = Assembly.Load(args[0]); 
#else
  var asm = AppDomain.CurrentDomain.Load(args[0]);
#endif
}
~~~

##Easy, right?
Well this wasn't a super technical post, but I wanted to get this written down because I couldn't find a good way to compile for both v2.0 and v4.0 AND get updated project references.

There may be a more elegant way that I'm not aware of, but this works well for me. If in any case you wanted to do this for any number of files you even have the option to create a directory link.

[plugin]: https://github.com/jldgit/mysql_udf_dotnet
[symlink]: http://en.wikipedia.org/wiki/Symbolic_link
[mklink]: http://msdn.microsoft.com/en-us/library/windows/desktop/aa365006%28v=vs.85%29.aspx
[ifcmd]: http://technet.microsoft.com/en-us/library/bb490920.aspx