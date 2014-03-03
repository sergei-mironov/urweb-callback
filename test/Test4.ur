(*

This test demonstrates C FFI bug. Tested with patched Urweb 1991:7db8356caef5
Patches are nessesary to build Callback FFI and are available in the project's
top directory (see *patch) files

The error message is:

$ LANG=C make

...

urweb -dbms postgres ./test/Test4
gcc  -pthread -Wimplicit -Werror -Wno-unused-value -I /home/grwlf/local/include/urweb  -c /tmp/webapp.c -o /tmp/webapp.o -g
/tmp/webapp.c: In function '__uwn_runNow_1700':
/tmp/webapp.c:448:16: error: implicit declaration of function 'uw_CallbackFFI_cmd' [-Werror=implicit-function-declaration]
                {uw_CallbackFFI_cmd(ctx, __uwr_j_4), 
                                ^
                                /tmp/webapp.c:448:16: error: initialization makes pointer from integer without a cast [-Werror]
                                /tmp/webapp.c:448:16: error: (near initialization for 'tmp.__uwf_Cmd') [-Werror]
                                cc1: all warnings being treated as errors
                                make[1]: *** [.fix-multy4] Error 1
                                make[1]: Leaving directory `/home/grwlf/proj/urweb-callback'
                                make: *** [.fix-multy1] Error 2


Note, both

  fun main {} : transaction page =
    a <- getA {}; (* b <- getB {}; *)
    return <xml> <body> {[a]} (* {[b]} *) </body> </xml>

and

  fun main {} : transaction page =
    (* a <- getA {}; *)  b <- getB {}; 
    return <xml> <body> (*{[a]}*) {[b]} </body> </xml>

snippets compile without errors

*)

structure C = Callback.Make(
  struct
    val f = fn x => return (<xml>{[x.Stdout]}</xml> : xbody)
  end)

fun getA {} : transaction string =
  j <- C.runNow ("echo a") "";
  return j.Stdout

fun getB {} : transaction string =
  j <- C.runNow ("echo b") "";
  return j.Stdout

fun main {} : transaction page =
  a <- getA {};
  b <- getB {};
  return
    <xml>
      <body>
      {[a]}
      {[b]}
      </body>
    </xml>

