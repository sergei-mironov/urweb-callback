structure C = Callback.Default

fun getA {} : transaction string =
  j <- C.createSync (C.shellCommand "echo a");
  return j.Stdout

fun getB {} : transaction string =
  j <- C.createSync (C.shellCommand "echo b");
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

