val s = "Hello kitty\n"

structure C = Callback.Make(
  struct
    val gc_depth = 1000
    val stdout_sz = 1024
    val stdin_sz = String.length s
    val callback = fn _ => return {}
  end)
structure CF = CallbackFFI

fun template (mb:transaction xbody) : transaction page =
  b <- mb;
  return
    <xml>
      <head/>
      <body>{b}</body>
    </xml>

fun feed jr i : transaction page =
  C.feed jr (Callback.Chunk (textBlob i.Text, None));
  redirect (url (job_monitor jr))

and feedEOF jr i : transaction page =
  C.feed jr (Callback.Chunk (textBlob "", Some Callback.EOF));
  redirect (url (job_monitor jr))

and job_monitor (jr:C.jobref) : transaction page = template (
  j <- C.get jr;
  return <xml>
    <div>
      <form>
        Feed some input:
        <br/>
        <textbox{#Text}/>
        <br/>
        <submit value="Feed text line" action={feed jr}/>
        <i>(Note Stdout changes)</i>
      </form>
      <br/>
      <form>
        <submit value="EOF" action={feedEOF jr}/>
        <i>(Note ExitCode changes)</i>
      </form>
    </div>

    <hr/>

    <div>
      JobRef : {[jr]}
      <br/>
      Cmd : {[j.Cmd]}
      <br/>
      ExitCode : {[j.ExitCode]}
      <br/>
      Stdout:  {[j.Stdout]}
    </div>

  </xml>)


fun job_start {} : transaction page =
  ja <- return (C.shellCommand "cat");
  jr <- C.create (ja -- #Stdin ++ {Stdin = Callback.Chunk (textBlob s, None)});
  redirect (url (job_monitor jr))

fun main {} : transaction page = template (
  return
    <xml>
      This test will the 'cat' job and allow the user to feed it's input.
      Initially, the cat will be provided with <b>{[s]}</b> string.
      <br/>
      <a link={job_start {}}>Start the job</a>
    </xml>)

