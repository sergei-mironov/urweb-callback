Hello, I am glad to announce the release of urweb-callback library version 3.0.

Urweb-callback offers the API for launching asynchronous server-side
processes which calls the callback procedures upon completion. During the
execution, user may inspect job`s exit code, standard output, process id
and other parameters.

Some features:

  * Added support for the Stderr stream.
  * Stdin, Stdout and Stderr are now blobs. This allows passing binary data to the input of a job.
  * String helper functions are moved to the Callback module.
  * Improved CallbackNotify API.
  * New automatic tests.

See the README (https://github.com/grwlf/urweb-callback) for more details.  The
example code is listed below:

    structure CB = Callback
    structure C = CallbackNotify.Default

    fun search (p:string) : transaction xbody =
      x <- C.abortMore 20;
      jr <- C.create (C.shellCommand ("sleep 2 ; find " ^ p ^ " -maxdepth 2"));
      C.monitorX jr (fn j =>
        case j.ExitCode of
          |Some _ => <xml><pre>{[j.Stdout]}</pre></xml>
          |None => <xml>Searching...</xml>)

    fun main {} : transaction page =
      s <- source <xml/>;
      return <xml>
        <head/>
        <body>
          <button value="Search files" onclick={fn _ =>
            x <- rpc(search ".");
            set s x
          }/>
          <hr/>
          <dyn signal={signal s}/>
        </body>
      </xml>


To get the sources, type:

    $ git clone https://github.com/grwlf/urweb-callback
    $ cd urweb-callback
    $ make demo

The demo application is running here

    http://46.38.250.132:8080/Demo2/main

Please, notify me about problems by creating Github issues or by e-mail.

Regards,
Sergey




