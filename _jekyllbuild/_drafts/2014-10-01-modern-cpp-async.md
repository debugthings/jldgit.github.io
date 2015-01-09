---
layout: post
title: Modern C++ - std::async
--- 
While writing my side project (ChainsAPM) I have found an obvious need to run things asyncronously. This leads to the common problems of synchronization and serialization. Some long operations, or items that can clash, need to be offloaded to another thread. But, how performant is this and does it starve the application of proper resources. I explore my findings in this blog.

Not every operation takes a long time, but when you have hundreds or thousands of threads competing for a time slice you can start affecting the bottom line. 