---
layout: post
title: Debugging - NetExt WinDbg Extension
tags:
- visual studio
- windbg
- debugging
- netext
---
I was poking around for some WinDbg extensions and stumbled upon a new one that I hadn't seen before. [NetExt][netextdl], is written and maintained by [Rodney Viana][rodneyv] an Escalation Engineer with Microsoft. I downloaded it and went through his tutorials on how to use it (available on the CodePlex site). I must say it's pretty nice. The best feature is that it uses the .NET Debugging interfaces as well as a mix of managed code.

## My Favorite Things
First off, it's great to have an internal tool released to the public. In Rodney's blog post he mentions that it was released originally in 2013 but was pulled to upgrade. Looking through the source code it certainly has the feel of a project that has been cared for. According to the blog post it's been alive for four years.

Secondly, it does a great thing for the world of extensibility and allows developers to easily develop extensions for this platform. It does this by introducing .NET into the picture. While this can complicate things if you're doing a ton of interop between the two, Rodney has boiled it down to passing around address pointers and doing the bulk of the work in .NET.

Lastly, it has a unique syntax that allows querying of data from the commands. The documentation goes over one specific command that I could have been using for YEARS now. With this command you can quickly check for SQL that returns data without abandon against a table that contains 100,000,000,000 rows.

~~~
!wfrom -type *.SqlCommand where ( $contains(_commandText, "SELECT") && (!$contains(_commandText,"SELECT TOP")) ) select _commandText
~~~

## The Layout
I had to dig in to see what was going on here so I could better understand how to use and extend it if needs be. It's broken up into a few major components. This isn't a comprehensive list but will get you started if you want to dig in a bit further.

1. NetExt (project)
  - This is the C++ component for the WinDbg Extension
1. EngExtCpp.Cpp
  - This is the template for creating any WinDbg extension
  - This defines and initializes the major components to talk with WinDbg
  - Initializes the ExtExtension class
2. NetExt.Cpp
  - This is the extension class itself
  - Defines all extension methods (!wstack, !wfrom, etc.)
  - Sets up the COM Interop classes for the NetExtShim
3. NextExt.def
  - C++ def file for extension command exports
3. wstack.cpp, wfrom.cpp, etc.
  - A separate file for each method
  - Implementation of the definition in NetExt.h
4. NetExtShim (project)
  - This is the C# .NET "shim" that does the reflection using MS.Diagnostics
5. COMInterop.cs
  - The main workhorse for this extension. Essentially this is what exposes the CLR to WinDbg.

## Extending
With any great tool there are reasons to extend. I started looking at the tcp sockets command Rodney included in the `.cmdtree netext.tl` which shows the socket and it's state. I wanted to add some DML which allows you to specify a HTML like syntax that will execute related WinDbg Commands.

I order to do this I copied the code for `!wcoookie` and modified it to better suit the needs of `System.Net.Sockets`. The code is long but I will dissect it to make it easier to read and digest. If you don't want to view the code broken up you can see the [full code][fullcode] here.

### Declaration Macro with optional parameters
~~~C
EXT_COMMAND(wsocket,
	"Dump all open sockets. Use '!whelp wsocket' for detailed help",
	"{;e,o;;Address, Socket Address (optional)}"
	"{all;b,o;;Dump all sockets including closed}"
	"{summary;b,o;;Display a summary only}"
	"{uniqip;b,o;;Display unique IP addresses}"
	"{ip;s,o;;Display Socket information for IP addresses (eg. -ip 192.168.0.1)}"
	)
{
~~~

>Since we're developing against the EngExtCpp we get the benefit of [parameter parsing][pparse]. Visit the link for details.

### Single Socket?
~~~C
	INIT_API();
	CLRDATA_ADDRESS addr = 0;
	bool isSocket = false;

	if (HasUnnamedArg(0))
	{
		addr = GetUnnamedArgU64(0);
		ObjDetail obj(addr);

		if (!obj.IsValid())
		{
			Out("Error: Could not find a valid object at %p\n", addr);
			return;
		}
		if (obj.TypeName() != L"System.Net.Sockets.Socket")
		{
			Out("Error: Expected type Socket. Found: %S\n", obj.TypeName().c_str());
			return;
		}
		isSocket = (obj.TypeName() == L"System.Net.Sockets.Socket");
	}
~~~
>Here we're checking to see if the single object we passed in was indeed a socket.

### Check Arguments and Set Flags
~~~C
	string name;
	string value;
	wstring ipaddress;
	bool dumpAllSockets = HasArg("all");
	bool searchIP = HasArg("ip");
	bool summary = HasArg("summary");
	bool uniqueip = HasArg("uniqip");
	if (searchIP)
	{
		ipaddress.assign(CA2W(GetArgStr("ip")));
	}

	if (!indc && !addr)
	{
		Dml("To list all sockets, run <link cmd=\"!windex;!wsocket\">!wsocket</link> first\n");
		return;
	}
~~~
>Display a friendly error message if we have bad parameters

### Setup Collections
~~~C
	MatchingAddresses addresses;
	AddressList al;
	al.push_back(addr);
	//std::map<string, IntPair> summary;

	if (addr)
	{
		addresses.push_back(&al);
	}
	else
	{
		indc->GetByType(L"System.Net.Sockets.Socket", addresses);
	}
	AddressEnum adenum;
	if (addresses.size() == 0)
	{
		Out("Found no Socket object(s) in heap\n");
		return;
	}

	AddressList tempVector;
	adenum.Start(addresses);
	int totalSockets = 0;
	int connectedSockets = 0;
	int displayedSockets = 0;
	map<wstring, int> summaryIPMap;
~~~
>If no address or any other items are defined the `GetByType()` method searches the heap for all occurences of `System.Net.Sockets.Socket`.

### Main Loop
~~~C
	while (CLRDATA_ADDRESS curr = adenum.GetNext())
	{
		++totalSockets;
		if (IsInterrupted())
			return;
		std::vector<std::string> fields;
		fields.push_back("m_RightEndPoint");
		fields.push_back("m_RightEndPoint.m_Address.m_ToString");
		fields.push_back("m_RightEndPoint.m_Port");
		fields.push_back("m_IsConnected");
		fields.push_back("isListening");
		varMap fieldV;
		DumpFields(curr, fields, 0, &fieldV);

		if (fieldV["m_RightEndPoint"].ObjAddress > 0)
		{
			if ((fieldV["m_IsConnected"].Value.i == 1 || dumpAllSockets) && !summary)
			{

				if ((searchIP & fieldV["m_RightEndPoint.m_Address.m_ToString"].strValue.find(ipaddress)
        == wstring::npos))
					continue;
				if (uniqueip)
				{
					++(summaryIPMap[fieldV["m_RightEndPoint.m_Address.m_ToString"].strValue]);
				}
				else {

					++displayedSockets;
					Out("===============================================================\n");
					Out("System.Net.Sockets.Socket    :  ");
					Dml("<link cmd=\"!wdo %p\">%p</link>\n", curr, curr);

					if (fieldV["m_RightEndPoint.m_Address.m_ToString"].strValue.size() > 0)
					{
						Dml("IP Address:\t\t<link cmd=\".shell -x ping %S\">%S</link>\n",
             fieldV["m_RightEndPoint.m_Address.m_ToString"].strValue.c_str(),
              fieldV["m_RightEndPoint.m_Address.m_ToString"].strValue.c_str());
					}
					if (fieldV["m_RightEndPoint.m_Port"].Value.i > 0)
					{
						Out("Port:\t\t\t%d\n", fieldV["m_RightEndPoint.m_Port"].Value.i);
					}
					string connected = fieldV["m_IsConnected"].Value.i == 1 ? "Yes" : "No";
					if (fieldV["m_IsConnected"].Value.i == 1)
						++connectedSockets;
					Out("Connected:\t\t%s (0n%d)\n", connected.c_str(), fieldV["m_IsConnected"].Value.i);
					string listening = fieldV["isListening"].Value.i == 1 ? "Yes" : "No";
					Out("Listening:\t\t%s (0n%d)\n", listening.c_str(), fieldV["isListening"].Value.i);
				}
			}
		}

	}
~~~
>These 50 or so lines of code pulls the fields and the values using the `DumpFields()` method. This method auto generates a std::map<> of a CLR data type. Each field requested is pushed into `std::vector<std::string> fields;` which is passed in to the `DumpFields()` method.

### Only Unique IP Addresses
~~~C
	if (uniqueip)
	{
		Out("======================================================================================\n");
		Out("System.Net.Sockets.Socket IP Address Summary\n");
		Out("IP Address\t\t\tCount\n");
		for (auto &x : summaryIPMap)
		{
			Dml("<link cmd=\"!wsocket -ip %S\">%S</link> \t\t\t%d\n",
      x.first.c_str(), x.first.c_str(), x.second);
		}
		Out("\n");
	}
~~~
>Checks for the -uniqip flag and displays a list of IP addresses that link to !wsock -ip <ipaddress>

### Create Summary
~~~C
	else {
		Out("======================================================================================\n");
		Out("System.Net.Sockets.Socket Summary\n");
		Out("Total Sockets: %d\t\tDisplayed Sockets: %d\t\tConnected Sockets: %d\n\n",
    totalSockets, displayedSockets, connectedSockets);

	}
}
~~~
>Final summary that is displayed telling how many sockets are in memory, shown and connected.

## Summary and Usage
This extension was put to use right away by me when I was debugging a hung application due to an open socket. I was able to find the list of IP addresses and drill into the call stack by using `!GCRoot <addr>` from SOS. I have redacted some information.

### Find Unique IPs
~~~
0:011> !wsocket -uniqip
======================================================================================
System.Net.Sockets.Socket IP Address Summary
IP Address			Count
xxx.xxx.211.196 			3
~~~
>This matched what I saw in netstat.

### Look at all of the connections
~~~
0:011> !wsocket -ip xxx.xxx.211.196
======================================================================================
System.Net.Sockets.Socket    :  0255e2ac
IP Address:		xxx.xxx.211.196
Port:			8081
Connected:		Yes (0n1)
Listening:		No (0n0)
======================================================================================
System.Net.Sockets.Socket    :  02582c68
IP Address:		xxx.xxx.211.196
Port:			8081
Connected:		Yes (0n1)
Listening:		No (0n0)
======================================================================================
System.Net.Sockets.Socket    :  0258553c
IP Address:		xxx.xxx.211.196
Port:			8081
Connected:		Yes (0n1)
Listening:		No (0n0)
======================================================================================
System.Net.Sockets.Socket Summary
Total Sockets: 6		Displayed Sockets: 3		Connected Sockets: 3
~~~
>Confirming they are all connected to the same endpoint.

~~~
0:011> !GCRoot 0255e2ac
Thread 355c:
    0511f124 703e23f3 System.Net.Sockets.Socket.Receive(Byte[], Int32, Int32, System.Net.Sockets.SocketFlags, System.Net.Sockets.SocketError ByRef)
        esi:
            ->  0255e2ac System.Net.Sockets.Socket

    0511f178 00550615 BHN_Downloader.Program.DownloadFromBHN()
        esi:
            ->  0255e214 System.Net.Sockets.TcpClient
            ->  0255e2ac System.Net.Sockets.Socket

Found 2 unique roots (run '!GCRoot -all' to see all roots).
~~~
>Found the thread and the call these guys were rooted in.

## Wrap-Up
I have written some custom purpose built extensions before but they relied on generating long `.foreach` statements combined with some of the EngExtCpp commands to get addresses. However, they were fragile and were not self contained. Rodney's extension breaks that barrier by allowing us to call into the CLR directly. I look forward to adding a few more commands to this tool to round out my arsenal.

[netextdl]: https://netext.codeplex.com/
[netextblog]: http://blogs.msdn.com/b/rodneyviana/archive/2015/03/10/getting-started-with-netext.aspx
[sosmsdn]: https://msdn.microsoft.com/en-us/library/bb190764%28v=vs.110%29.aspx
[rodneyv]: https://msdn.microsoft.com/en-us/gg602412.aspx
[pparse]: https://msdn.microsoft.com/en-us/library/windows/hardware/ff553340(v=vs.85).aspx
[fullcode]: https://github.com/jldgit/netext/blob/cda626d25cb5af0ac5827047d5d28b699067554f/NetExt/wdict.cpp#L144
*[DML]: Debugger Markup Language
