---
layout: post
title: MySQL .NET Hosting Extension - Part 2 - UDF Deep Dive
tags:
- mysql
- .net
- hosting api
- extending
- udf
---
After I worked through compiling the sources, the next step was to get .NET hosting working at a basic level. I used source from another project called [ADMHost][adm] (App Domain Manager) to base my code on. This code allows you to specify and create a managed AppDomain manager and use it to manage and run your .NET assemblies.

This is a critical piece of this software since we should consider some of the niceties that using the CLR will gain us. In this list consider the fact that each query would run in a separate AppDomain.

1. Isolation
2. Validation
3. Structured Exception Handling
4. Type Safety
5. Robust Libraries
6. Managed Memory
7. Simpler Coding<sup>*</sup>

The critical factor here is **isolation**. If we were to roll this out to a server and it was used by a couple of queries here and there we probably would never have to worry about any of our functions stepping on each other. But if we were to try and execute hundreds of queries simultaneously we start to run into some limitations.

>**\*NOTE** While I listed simpler coding as an example, this doesn't mean that we can't create a robust solution. Or, that we're bound to an inferior language. What I mean by this is you can develop a custom function and be assured that you've got enough safe guards in place to keep the server alive.

But, before we get deep into the guts of the .NET Hosting API we need to first understand the execution of the UDF itself. It will be the gateway into MySQL and will need to be understood to know where to inject our code.

##UDF Anatomy

The UDF program flow is pretty simple to get. There are only three methods we need to implement to make it work for the simplest of values, the humble integer. For my application I will implement a function called `mysqldotnet` and it will work with integer types. Be aware you can also work with REAL and STRING types you just need to implement the proper method signature. There are examples in the source code found at `sql/udf_examples.c`.

For a complete reference check out [this page][ref].

~~~ Cpp
extern "C"
{
	my_bool mysqldotnet_int_init(UDF_INIT *initid, UDF_ARGS *args, char *message);
	long long mysqldotnet_int(UDF_INIT *initid, UDF_ARGS *args, char *is_null, char *error);
	void mysqldotnet_int_deinit(UDF_INIT *initid);
}
~~~ 

>**NOTE** I am using `extern "C"` in this example becaue I am writing my UDF in C++.

###The init function

~~~ C
my_bool mysqldotnet_int_init(UDF_INIT *initid, UDF_ARGS *args, char *message);
~~~ 
This name self explanatory. It will be used to initialize the run of this method. This is run **once** per query. So, if you have a need to setup memory, check values, load libraries, etc. you could do that here. It is important to note that your code needs to be thread safe. If you decide to use global variables (which you shouldn't) you need to protect them.

####initd
The `UDF_INIT initd` parameter represents state that is passed to all of the corresponding functions. In the structure definition below we can see what the intentions are. Depending on what type of function you implement will drive the use of the structure members.

This structure has one interesting member that we will visit in future posts, `void *extension`. This item has the potential to store anything we desire, an address pointer, a new structure, an external library function. The list is obviously endless.

~~~ cpp
typedef struct st_udf_init
{
	my_bool maybe_null;          /* 1 if function can return NULL */
	unsigned int decimals;       /* for real functions */
	unsigned long max_length;    /* For string functions */
	char *ptr;                   /* free pointer for function data */
	my_bool const_item;          /* 1 if function always returns the same value */
	void *extension;
} UDF_INIT;
~~~ 

####args
The next important parameter is `UDF_ARGS *args`. These are the actual arguments that are passed to your function. In the initialize function you are allowed to strongly type the parameters to the function. For example `SELECT mysqldotnet_int(3,"MultiplyFunction");`

This query calls the int function of my custom code. I pass in a raw value of 3 and a string value of "MultuplyFunction". The number of arguments is not defined and is arbitrary in length. In the init function you can check the type of the arguments to ensure valid operation before continuing.

~~~ cpp
typedef struct st_udf_args
{
	unsigned int arg_count;           /* Number of arguments */
	enum Item_result *arg_type;       /* Pointer to item_results */
	char **args;                      /* Pointer to argument */
	unsigned long *lengths;           /* Length of string arguments */
	char *maybe_null;                 /* Set to 1 for all maybe_null args */
	char **attributes;                /* Pointer to attribute name */
	unsigned long *attribute_lengths;     /* Length of attribute arguments */
	void *extension;
} UDF_ARGS;
~~~ 

####message
The `char* message` parameter contains a pointer to where you can write out your error or status message on init. We will show more about this pointer in the up comming series. For now, be aware that it exists and you can use it to send a message back to the MySQL console. Please note the max size is `MYSQL_ERRMSG_SIZE`; which is defined as `#define MYSQL_ERRMSG_SIZE	512` in `mysql_com.h`.

###The "core" function

~~~ C
long long mysqldotnet_int(UDF_INIT *initid, UDF_ARGS *args, char *is_null, char *error);
~~~ 

This is the heart of your UDF. In the simplest of terms this code sits in the middle of a loop and will be executed for each record. A lot can take place during the execution of your code and you need to be careful about how you (ab)use the data handed to you.

####initd
The `UDF_INIT initd` parameter is the state information that is saved between function calls. If you set something in your init function you can retrieve it from here. You can also alter state of this parameter here, but I would caution only to do so when it's absolutely necessary. For sake of speed and safety you should only work with local variables.


~~~ cpp
typedef struct st_udf_init
{
	my_bool maybe_null;          /* 1 if function can return NULL */
	unsigned int decimals;       /* for real functions */
	unsigned long max_length;    /* For string functions */
	char *ptr;                   /* free pointer for function data */
	my_bool const_item;          /* 1 if function always returns the same value */
	void *extension;
} UDF_INIT;
~~~ 

####args
For each execution of your UDF you will get a fresh copy of UDF_ARGS. They shouldn't vary too much since (hopefully) your parameters should be the same. However, if there is any logic built in to the SQL statement you could, of course, run into times where you're passed an integer and then a decimal. That example would be a sign of poor query writing, but you need to be aware of it for casting issues.

~~~ cpp
typedef struct st_udf_args
{
	unsigned int arg_count;           /* Number of arguments */
	enum Item_result *arg_type;       /* Pointer to item_results */
	char **args;                      /* Pointer to argument */
	unsigned long *lengths;           /* Length of string arguments */
	char *maybe_null;                 /* Set to 1 for all maybe_null args */
	char **attributes;                /* Pointer to attribute name */
	unsigned long *attribute_lengths;     /* Length of attribute arguments */
	void *extension;
} UDF_ARGS;
~~~ 

In order to loop through your args properly you need to account for what the arguments are. An example would be a function that is expecting to do work on a collection of integers. Now, consider the following SQL query `SELECT mysqldotnet_int(3, 6, 78, 4.0, 10, "AddAllTogether");`. The intention of the function is to add all of them together, but there are varying types.

Your function, again by use of branching instructions such as `CASE` and `IF`, can introduce significant variation in the parameters you accept. You could use the code example below. This was extracted from the [UDF documentation][ARGS].

~~~ C
long long myfunc_int(UDF_INIT *initid, UDF_ARGS *args, char *is_null,
		char *error)
	{
		longlong val = 0;
		uint i;
		for (i = 0; i < args->arg_count; i++)
		{
			if (args->args[i] == NULL)
				continue;
			switch (args->arg_type[i]) {
			case STRING_RESULT:			/* Add string lengths */
				val += args->lengths[i];
				break;
			case INT_RESULT:			/* Add numbers */
				val += *((longlong*)args->args[i]);
				break;
			case REAL_RESULT:			/* Add numers as longlong */
				val += (longlong)((double)*((longlong*)args->args[i]));
				break;
			default:
				break;
			}
			return val;
		}
	}
~~~ 

####is_null
This is a one char (one byte) feild that you can set to let MySQL know that the result is NULL. This will override the value you return and set it to NULL.

~~~ C
long long myfunc_int(UDF_INIT *initid, UDF_ARGS *args, char *is_null,
		char *error)
	{
		*is_null = 1;
		return -1;
	}
~~~ 

####error
This is a one char (one byte) feild that you can set to let MySQL know that there is an error. This will override the value you return and set it NULL.

~~~ C
long long myfunc_int(UDF_INIT *initid, UDF_ARGS *args, char *is_null,
		char *error)
	{
		*error = 1;
		return -1;
	}
~~~ 

>**NOTE:** Once you set this, all subsequent calls to this method will return NULL. This field is to indicate that your function cannot continue.

###The deinit function
~~~ C
long long mysqldotnet_int(UDF_INIT *initid, UDF_ARGS *args, char *is_null, char *error);
~~~ 
This function is run when the SQL statement ends. This can be used to clean up any allocations or other items that you may have created when running this UDF.

####initd
If the `UDF_INIT initd` parameter was set during the init function or altered during the execution of the SQL statement, then you can inspect the state of this to perform the proper actions.

##Summary
This overview of the UDF structure will provide the foundation on to which we will start to build the .NET Hosting environment. In the next series I will explain the simple .NET Hosting API based on ADMHost.

[ref]: http://dev.mysql.com/doc/refman/5.0/en/udf-calling.html
[ARGS]: http://dev.mysql.com/doc/refman/5.0/en/udf-arguments.html
[adm]: http://www.microsoft.com/en-us/download/details.aspx?id=7325
[pt0]: ({% post_url 2014-10-21-hostprotectionexception-ssrs %})
