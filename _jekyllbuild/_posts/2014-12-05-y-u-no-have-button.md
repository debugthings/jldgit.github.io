--- 
layout: post
title: Y U NO HAVE BUTTON?
tags:
- mysql
- .net
- hosting api
- extending
- udf
---
Seriously, it's 2014 almost 2015. I wanted to add a file type association to my machine using the provided Windows interfaces. I added an association by using the open file dialog, but realized after the fact that I wanted to give the file type a better name. A quick Google search provided a number of links asking how, but only one that told me how.

[This][mslink] MSDN article describes how to do this. The first few steps are pretty straight forward. Use regedit, use the "Open File" context menu. But one of the steps says the following line verbatim: "**Step 3:** Call the [SHChangeNotify][SHChangeNotify] function to notify the Shell to update its icon cache." I mean yeah, I get it. But, what?

![YUNO](/images/yuno.jpg)

Judging by the comments I am not alone. While I'm not a UX guy, I would assume a button could be added that just says "Update File Associations". Please take note of the following UI design change. I think this sums it up nicely.

![For Rent](/images/UpdateBox.png)

Here is one of my favorite quotes from [Lenin Carrion][lenin]. This guy for real made an account just so he could comment on this page.

>What a ridiculous explanation.
"Call the SHChangeNotify function", yeah, very easy. **Do I have to first read to "how to be a geek or a nerd chapter 34 thousand"?**   What is call a function in that step? for what I saw it was a C sharp function. What does a C# function has to do here?
Lenin_Carrion
11/27/2014

In the link above it talks about using [SHChangeNotify][SHChangeNotify] to update the file associations. This seems a bit heavy handed, and probably out of scope for MOST computer techs out there that just want to make someone see the correct icon or text. But, for those who'd like to be able to do this and have some form of compiler, here is the code. For real, it's only two lines of code. So, why can't Microsoft add this button?

~~~Cpp

#include <tchar.h>
#include <Shlobj.h>


int _tmain(int argc, _TCHAR* argv[])
{
SHChangeNotify(
    SHCNE_ASSOCCHANGED,
    SHCNF_FLUSH,
    NULL,
    NULL
    );
return 0;
}

~~~

[mslink]: http://msdn.microsoft.com/en-us/library/windows/desktop/hh127427%28v=vs.85%29.aspx
[SHChangeNotify]: http://msdn.microsoft.com/en-us/library/windows/desktop/bb762118(v=vs.85).aspx
[lenin]: https://social.msdn.microsoft.com/profile/lenin_carrion/