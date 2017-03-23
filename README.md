Urweb-callback
--------------

Urweb-callback is a library for managing asynchronous processes directly from
an [Ur/Web](http://www.impredicative.com/ur/) application.

The current version is 4.0. Comparing to previous version, many simplifications
were made. The main difference is that urweb-callback doesn't declare jobs
table. The table should be declared on the application side and passed to
urweb-callback using ML Functor interface.  This scheme allows applications to
control the resources more accurately.

Installation
------------

The Project requires [Nix](www.nixos.org/nix) package manager to be installed and
[urweb-build](http://github.com/grwlf/urweb-build) expression available
via NIX\_PATH variable.

    $ git clone https://github.com/grwlf/urweb-callback
    $ cd urweb-callback
    $ nix-build -A callback

Compiling the Demo
------------------

    $ nix-build -A callback-demo
    $ ./result/mkdb.sh
    $ ./result/CallbackDemo.exe
    $ browser http://127.0.0.1:8080/Callback1/main


Regards,
Sergey Mironov
grrwlf@gmail.com


