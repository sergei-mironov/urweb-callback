(* CallbackFFI without callback *)

sequence jobrefs

fun monitor (jr:CallbackFFI.jobref) : transaction page =
  j <- CallbackFFI.deref jr;
  e <- return (CallbackFFI.exitcode j);
  case e of
    |0 =>
      CallbackFFI.cleanup j;
      return <xml><body>Exit code: {[CallbackFFI.exitcode j]} (last one)</body></xml>
    |_ =>
      return <xml><body>Exit code: {[CallbackFFI.exitcode j]}</body></xml>

fun run {} : transaction page =
  jr <- nextval jobrefs;
  j <- CallbackFFI.create "for i in `seq 1 1 5`; do echo -n $i; sleep 2 ; done" 100 jr;
  CallbackFFI.run j (textBlob "") None;
  redirect (url (monitor jr))

fun main {} : transaction page =
  return <xml><body><a link={run {}}>Run the test</a></body></xml>
