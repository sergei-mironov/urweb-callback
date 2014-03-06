structure C = Callback.Make(
  struct
    val f = fn x => return (<xml>{[x.Stdout]}</xml> : xbody)
    val depth = 1000
    val stdout_sz = 1024
  end)

fun getA {} : transaction string =
  jr <- C.nextjob {};
  j <- C.runNow jr ("echo a") (textBlob "");
  return j.Stdout

fun getB {} : transaction string =
  jr <- C.nextjob {};
  j <- C.runNow jr ("echo b") (textBlob "");
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

