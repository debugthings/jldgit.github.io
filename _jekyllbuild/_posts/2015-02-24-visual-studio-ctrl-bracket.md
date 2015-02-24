---
layout: post
title: Visual Studio Productivity, you're doing it wrong (Ctrl+])
tags:
- visual studio
---
So, I was working through an old project today and encountered a method that was about 200(!!) lines long. The code is in a dire need of refactoring and I set down the stupid path of doing so.

The issue here isn't the code per-se, but the amount of code that needs to be surgically removed or is a candidate for refactoring. In order to do this, generally, you need to select, copy, paste, etc. your code. If your code lies between a number of segments of code that can't---or shouldn't---be removed, you have to get in there and start selecting. This either means by performing a Shift+Click, by a bunch of Shift+Arrow combinations, or by natural selection using the mouse.

That can become tedious because you're having to hold your primary mouse button AND use the scroll wheel AND make some lateral movement like some dexterous ninja. This delicate act is honed in over time and you get good at it. But, it's still a bit time consuming and prone to error.

Enter the **Ctrl+]** short cut key. This has been around for well over a decade and possibly even longer. But, it's **BRAND NEW** to me. So, what does it do? Well if you position yourself on a block definition `{ } ( ) [ ] " " /* */` it will move to the opposite block item. If you use **Ctrl+Shift+]** it will **SELECT** the entire block, including the curly brace.

##Some Uses
- If you happen to be inside of a very long broken literal string `@""` then you can place the cursor on a letter and find the beginning or end of the definition.
- You can find the end of an array definition by selecting one of the square braces.
- Grabbing the argument list by selecting the first parenthesis in the method signature.
- Selecting the entire multi-line MIT license bible comment with one key stroke.

## Some Gotcha's
- Absolutely does not work for VB. Period.
- It usually it will select the character to the right of the block. This means it will select your semicolon along with your block, or it will select the newline break, or it can select another critical character.
- Depending on the direction of the select---that is top-to-bottom, or left-to-right, and vice versa--it will dictate if you can Shift+ArrowUp or Shift+ArrowDown and expect the correct behavior.
- It may be more useful to Ctrl+] to the end of the block and then Ctrl+Shift+] to the beginning so you can Shift+ArrowUp to select the method signature or the if statement.
- This will not work for case statement blocks as there is no surrounding block identifier.

## The Wrong Way
This requires me to select the curly brace and scroll down to find it's mate. Once I find it I can Shift+Click and select all that I need. Not so bad, but requires me to scroll to find it's match.

![WrongWay](/images/WrongWay.gif)

## The Right Way
I select the top curly brace, press Ctrl+Shift+] and violà, the entire block is selected. Done. Let's get some coffee.

![RightWay](/images/RightWay.gif)

>Take notice of this animation and you can see where it selects the curly brace to the right of the actual block end. This is listed in the gotchas above.

[orlcc]: http://www.orlandocodecamp.com/
