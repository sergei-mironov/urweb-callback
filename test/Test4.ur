structure C = Callback.Default

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

