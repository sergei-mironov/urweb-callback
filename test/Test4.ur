structure C = Callback.Make(
  struct
    val f = fn x => return (<xml>{[x.Stdout]}</xml> : xbody)
    val depth = 1000
    val stdout_sz = 1024
  end)

fun getA {} : transaction string =
  j <- C.runNow ("echo a") (textBlob "");
  return j.Stdout

fun getB {} : transaction string =
  j <- C.runNow ("echo b") (textBlob "");
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

