---
layout: post
title: Writing code to write code
---
Every now and then a balance needs to be struck from the every day coding of an application. While personal life is usually the topic for these types of posts, today that is not the case. Sometimes you have to write code in order to write code. This is somewhat of an extended rant from my previous post.

While developing the core components of my [ChainsAPM](http://www.github.com/chainsapm) solution I felt the need to write down thoughts and musings of what I'm trying to do as well as explain some details of the implementation. Plus, I have other things to talk about aside from that project. At the same time I need to keep myself organized; so I needed to make a separate space.

Behold, the humble blog. This has always been the best sounding board for getting ideas out there. While the normal blogging scene is great, there are a lot of gotchas and really some implementation details I don't want to mess with. Places like Wordpress and blogger have excellent packages, software and templates. I have used these places before to bring to life some idea or useful tip. But, in all of this simplicity, lay a problem I never thought about. Once I signed up, I usually never signed back in once I wrote a couple of blogs.

Part of the reason for this is beacause I never really used the software as it was intended. I didn't connect with like minded bloggers, I didn't share the pages and I was just overall uninterested in the process. I didn't have much control over what the pages looked like unless I wanted to get into some Wordpress implementation details that I didn't need.

GitHub provides a very minimalistic blogging infrastructure based on Jekyll (which was written at GitHub). It's a Ruby implemented web server that uses simple templating to make static content. Once you compile the Jekyll site you can publish it anywhere and not require any databases or other silly things just to deliver content.

But, going this route meant I had to learn **YET ANOTHER** thing in order to get some words on the internets. It's starting to feel like Wordpress all over again. But, this time I have a vested interest because it's somewhat of a unified front. I'm developing my blog site in my normal IDE using familiar tools and publishing to a place that I visit every day.

So instead of just sluffing off the task I decided to learn this new-to-me skill because it was also more robust and allowed me to do things that would be difficult at best and impossible overall to implement. I am now able to combine efforts and cross post to my two blogs. 

After plowing through a month of coding in C++ I found myself wanting something a bit prettier, something that I could craft a bit more organically and not stress about all of the implementation details. In other words, I had to write this code in order to write other code.
