Urweb-callback
--------------

Urweb-callback is a library for managing asynchronous processes directly from an
[Ur/Web](http://www.impredicative.com/ur/) application.


Installation
------------

Urweb-callback requires certain patches to be applied over the Ur/Web compiler.
Follow the instructions below:

1. Obtain the sources and prepare the patches

        $ hg clone http://hg.impredicative.com/urweb
        $ git clone https://github.com/grwlf/urweb-callback
        $ cp -t urweb urweb-callback/*patch

2. Build the Ur/Web compiler. You may try the latest Ur/Web from the official
   repo. In case it doesn't work, please test the known-good revision (see
   below).

        $ cd urweb

              # (skip this line to stay on latets Ur/Web)
        $ hg checkout 924e2ef31f5a
    
        $ ./autogen.sh
        $ ./configure
        $ make install
        $ cd ..

3. Build the urweb-callback
 
        $ cd urweb-callback
        $ make
     
Note: gcc supporting C++11 is required to compile the library.


The API
-------

Urweb-callback defines 3 levels of API. he first one is the CallbackFFI API which is
the low-level operations. In general, users should not use it. Callback and CallbackNotify
modules define the secons and third levels.

### Callback module

The second level is 
defined in the Callback.ur module via Make functor. 

_Callback.Make_ functor acceppts the following parameters:

    (* Depth of garbage-collecting. All finished jobs older then current - gc_depth
     * will be removed *)
    val gc_depth : int

    (* Stdout buffer contains last stdout_sz lines *)
    val stdout_sz : int

    (* Callback to call upon job completion *)
    val callback : (record jobrec) -> transaction unit

_Callback.Default_ funtor calls Callback.Make with all default values.

The most important functions returned by Make are:

    con jobrec = [JobRef = int, ExitCode = option int, Cmd = string, Stdout = string]

    type jobref = CallbackFFI.jobref

    val nextjob : unit -> transaction jobref

    val create : jobref -> string -> blob -> transaction unit

    val get : jobref -> transaction (record jobrec)

    val runNow : jobref -> string -> blob -> transaction (record jobrec)

`nextjob` issues unique job references, `create` accepts the following arguments:
jobref, command line, stdin, then runs the process. `get` returns it's state.

`runNow` creates the procees and runs it synchronously. This function blocks
Ur/Web's handler thread. Use it at your own risk.

### CallbackNotify module

CallbackNotify shows how to use callback argument of the Callaback.Make to implement client
notification. It is able to send the job state over Ur/Web channels. See test/Test6.ur for
an example.

Usage
-----

Below is an example appication demonstrating the Callback API usage. This application 
starts the shell script which counts from 1 to 5.

    structure C = Callback.Default

    fun template (mb:transaction xbody) : transaction page =
      b <- mb;
      return
        <xml>
          <head/>
          <body>{b}</body>
        </xml>

    fun job_monitor (jr:C.jobref) : transaction page = template (
      j <- C.get jr;
      return <xml>
          Job : {[jr]}
          <br/>
          ExitCode : {[j.ExitCode]}
          <br/>
          Stdout:  {[j.Stdout]}
        </xml>)

    fun job_start {} : transaction page =
      n <- C.abortMore 20;
      jr <- C.nextjob {};
      C.create jr "for i in `seq 1 1 5`; do echo -n $i; sleep 2 ; done" (textBlob "");
      redirect (url (job_monitor jr))

    fun main {} : transaction page = template (
      return
        <xml>
          <a link={job_start {}}>Start a sleep job</a>
        </xml>)

See test/ folder for more examples.


Debugging and testing
---------------------

To enable debug messages, set the UWCB\_DEBUG environment variable to some
value before runnung the application.

To run the stress-testing, 1) Start the ./test/Stress.exe 2) Run the ./stress.sh
from another terminal. 3) Kill the ./test/Stress.exe. There should be no
'Bye-bye' after the termination. If they are exist, there is a memory leak in
the code. Please, drop me a message about this.

Regards,
Sergey Mironov
grrwlf@gmail.com


