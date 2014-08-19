Hello, I am glad to announce the release of urweb-callback library version 2.0.

Urweb-callback offers the API for launching asynchronous server-side
processes which may call the callback procedures upon completion. During the
execution, user may inspect their exit code, standard output, process id
and other parameters.

The application which uses callbacks may now be as simple as:

    structure C = Callback.Default

    fun template (mb:transaction xbody) : transaction page =
      b <- mb;
      return
        <xml>
          <head/>
          <body>{b}</body>
        </xml>

    fun monitor (jr:C.jobref) : transaction page = T.template (
      j <- C.get jr;
      return <xml>{[j.Stdout]}</xml>)

    fun main (world:string) : transaction page = T.template (
      x <- C.abortMore 20;
      jr <- C.create (C.shellCommand ("echo Hello " ^ world));
      redirect (url (monitor jr)))

To get the sources, type:

    $ git clone https://github.com/grwlf/urweb-callback
    $ cd urweb-callback
    $ make demo

I have run a demo application at

    http://46.38.250.132:8080/Demo2/main

Please, notify me about problems by creating Github issues or by e-mail.

Regards,
Sergey


