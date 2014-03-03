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

