/*
 * Ur/Web FFI module providing callback mechanisms. The main rule: every uw_*
 * function may longjump far-far away so we shouldn't mix it with C++ objects.
 */

extern "C" {
#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include <errno.h>
#include <signal.h>
#include <sys/time.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <pthread.h>

#include <urweb_cpp.h>
#include "CallbackFFI.h"
}

#include <map>
#include <string>
#include <memory>
#include <sstream>
#include <list>
#include <vector>
#include <cassert>
#include <algorithm>
#include <mutex>
#include <condition_variable>
#include <atomic>
#include <climits>


/* 0,1 are pipe ids, 2,3 is zero if pipe is closed */
typedef int uw_System_pipe[4];

#define dprintf(t, args...) do { if(getenv("UWCB_DEBUG")) fprintf(stderr, t, ##args); } while(0)

#define JOB_SIGNAL SIGUSR1

#define UW_SYSTEM_PIPE_INIT(x) { x[2] = 0; x[3]=0; }
#define UW_SYSTEM_PIPE_CLOSE_IN(x)  { close(x[1]); x[1+2] = 0; }
#define UW_SYSTEM_PIPE_CLOSE_OUT(x) { close(x[0]); x[0+2] = 0; }
#define UW_SYSTEM_PIPE_CLOSE(x) do { \
    if (x[0+2]) { close(x[0]); x[0+2] = 0; } \
    if (x[1+2]) { close(x[1]); x[1+2] = 0; } \
  } while(0)

#define UW_SYSTEM_PIPE_CREATE(x) do {     \
    if (pipe(x) >= 0){                    \
        x[2] = 1;                         \
        x[3] = 1;                         \
    } else {                              \
      r->throw_c([=](oss& e) { e << "pipe failed" ; }); \
    }                                     \
  } while(0)

#define MY_FD_SET_546(x, set) { if (x > max_fd) max_fd = x; FD_SET(x, set); }

typedef std::vector<unsigned char> blob;
typedef std::string string;
typedef std::ostringstream oss;
typedef std::mutex mutex;
typedef std::atomic<int> atomic;
typedef long int jkey;



struct job {

  friend struct notifiers;

  class atomic_counter {
    static int cnt;
    static std::mutex m;
    std::unique_lock<std::mutex> l;
  public:
    atomic_counter() : l(m) {
    }

    int& get() { return cnt; }
  };

  job(jkey _key, const string &_cmd, int _bufsize) :
		  key(_key), cmd(_cmd) {
    buf_stdout.resize(_bufsize);
    buf_stderr.resize(_bufsize);
    sz_stdout = 0;
    sz_stderr = 0;
    sz_stdin = 0;
    exitcode = -1;
    close_stdin = false;
    thread_started = false;
    cleanup_flag = 0;
    cmd_and_args = cmd;

    atomic_counter c;
    c.get()++;
    dprintf("Hello job #%d (cnt %d)\n", key, c.get());
  }

  ~job() {
    atomic_counter c;
    c.get()--;
    dprintf("Bye-bye job #%d (cnt %d)\n", key, c.get());
  }

  jkey key;

  string cmd;
  string cmd_and_args;

  string url_completion_cb;
  string url_notify_cb;

  int pid = -1;

  // Host thread running the job
  pthread_t thread;
  bool thread_started;

  std::recursive_mutex m;

  // Exit code. Needs mutex.
  int exitcode;

  bool close_stdin;
  int cleanup_flag;

  size_t sz_stdout;
  size_t sz_stdin;
  size_t sz_stderr;

  blob buf_stdout;
  blob buf_stdin;
  blob buf_stderr;

  std::vector<string> args;

  // Infrastructure errors (not stderr). Needs mutex.
  oss err;

  typedef string exception;

  void throw_c( std::function<void(oss &s)> f) {
    f(err);
    err << " errno " << errno << " strerror " << strerror(errno);
    throw err.str();
  }

  void throw_pure( std::function<void(oss &s)> f) {
    f(err);
    throw err.str();
  }

};

int job::atomic_counter::cnt = 0;
mutex job::atomic_counter::m;

typedef std::shared_ptr<job> jptr;

struct jlock {
  jlock(jptr j_)  : j(j_) {
    j->m.lock();
  }

  ~jlock() {
    j->m.unlock();
  }

private:
  jptr j;
};

/*{{{ Execute function */

static ssize_t read_job(int fd, jptr j, blob job::*buf, size_t job::*buf_sz, bool dump_to_stderr = false)
{
  size_t bytes_read;
  blob& b = *(j.get()).*buf;
  size_t &bs = *(j.get()).*buf_sz;

  if(bs < b.size()) {
    jlock _(j);
    bytes_read = read(fd, &b[bs], b.size() - bs);

    if(bytes_read < 0) {
      if(errno == EINTR)
        return -EINTR;
      else
        j->throw_c([=](oss& e) { e << "read failed" ; });
    }

    bs += bytes_read;
  }
  else {
    // FIXME: inefficient, don't use stack for buffers
    blob devnull(b.size() / 2);

    bytes_read = read(fd, &devnull[0], devnull.size());

    if(bytes_read < 0) {
      if(errno == EINTR)
        return -EINTR;
      else
        j->throw_c([=](oss& e) { e << "read failed (devnull)" ; });
    }
    else {
      jlock _(j);
      memmove(&b[0], &b[bytes_read], b.size() - bytes_read);
      memcpy(&b[b.size() - bytes_read], &devnull[0], bytes_read);
    }
  }

  if(dump_to_stderr && bytes_read > 0) {
    blob buf(&b[0] + bs - bytes_read, &b[0] + bs);
    buf.push_back('\0');
    fprintf(stderr, "%s", &buf[0]);
  }

  return bytes_read;
}

/* Borrowed from Mark Weber's uw-process. Thanks, Mark. */
static void execute(jptr r, uw_loggers *ls, sigset_t *pss)
{
  uw_System_pipe ur_to_cmd;
  uw_System_pipe cmd_to_ur;
  uw_System_pipe cmd_to_ur2;

  UW_SYSTEM_PIPE_INIT(ur_to_cmd);
  UW_SYSTEM_PIPE_INIT(cmd_to_ur);
  UW_SYSTEM_PIPE_INIT(cmd_to_ur2);

  try {
    UW_SYSTEM_PIPE_CREATE(ur_to_cmd);
    UW_SYSTEM_PIPE_CREATE(cmd_to_ur);
    UW_SYSTEM_PIPE_CREATE(cmd_to_ur2);

    dprintf("Job #%d ready to fork\n", r->key);

    int pid = fork(); // local var required? TODO
    if (pid == -1) {
      r->throw_c([=](oss& e) { e << "fork failed" ; });
    }

    r->pid = pid;

    if (r->pid == 0) {
      /* child
       * TODO: should be closing all fds ? but the ones being used? */
      close(ur_to_cmd[1]);
      close(cmd_to_ur[0]);
      close(cmd_to_ur2[0]);

      /* assign stdin */
      close(0);
      dup(ur_to_cmd[0]);
      close(ur_to_cmd[0]);

      /* assign stdout */
      close(1);
      dup(cmd_to_ur[1]);
      close(cmd_to_ur[1]);

      /* assign stderr */
      close(2);
      dup(cmd_to_ur2[1]);
      close(cmd_to_ur2[1]);

#if 0
      if(r->args.size() == 0) {
        /* The Insecure way */
        char * argv[3];
        argv[0] = (char*) "/bin/sh";
        argv[1] = (char*) "-c";
        argv[2] = (char*) r->cmd.c_str();
        argv[3] = NULL;
        dprintf("Warning: insecure execv\n");
        for(int i=0; i<3; i++)
          dprintf("arg[%d]: %s\n", i, argv[i]);
        execv("/bin/sh", argv);
      }
      else
#endif
      {
        /* The Secure way */
        char* cmd = (char*) r->cmd.c_str();
        char** argv = new char* [r->args.size() + 2];
        int argc = 0;
        argv[argc++] = cmd;
        dprintf("arg[0]: %s\n", cmd);
        for(int i=0; i<r->args.size(); i++, argc++) {
          argv[argc] = (char*)r->args[i].c_str();
          dprintf("arg[%d]: %s\n", argc, argv[argc]);
        }
        argv[argc] = NULL;
        execv(cmd, argv);
      }
      fprintf(stderr, "execv '%s': %m\n", r->cmd.c_str());
      exit(1);
    }
    else {
      /* parent */

      /* close pipe ends which are not used */
      UW_SYSTEM_PIPE_CLOSE_IN ( cmd_to_ur );
      UW_SYSTEM_PIPE_CLOSE_IN ( cmd_to_ur2 );
      UW_SYSTEM_PIPE_CLOSE_OUT( ur_to_cmd );

      while (1){
        fd_set rfds, wfds, efds;

        int max_fd = 0;
        FD_ZERO(&rfds);
        FD_ZERO(&wfds);
        FD_ZERO(&efds);

        if(cmd_to_ur[2] != 0) {
          MY_FD_SET_546( cmd_to_ur[0], &rfds );
        }

        if(cmd_to_ur2[2] != 0) {
          MY_FD_SET_546( cmd_to_ur2[0], &rfds );
        }

        {
          jlock _(r);
          if(r->buf_stdin.size() > r->sz_stdin) {
            if (ur_to_cmd[1+2] != 0) {
              MY_FD_SET_546( ur_to_cmd[1], &wfds );
            }
          }
        }

        struct timespec tv;
        tv.tv_sec  = 1;
        tv.tv_nsec = 0;

        int ret = pselect(max_fd+1, &rfds, &wfds, &efds, &tv, pss);

        if (ret < 0) {
          if(errno == EINTR) {
            continue;
          }
          else {
            r->throw_c([=](oss& e) { e << "select failed" ; });
          }
        }

        if (FD_ISSET( cmd_to_ur2[0], &rfds )) {
          ret--;
          read_job(cmd_to_ur2[0], r, &job::buf_stderr, &job::sz_stderr, true);
          /* ignore return value compeletely */
        }

        if (FD_ISSET( cmd_to_ur[0], &rfds )) {
          ret--;
          ssize_t ret = read_job(cmd_to_ur[0], r, &job::buf_stdout, &job::sz_stdout);
          if(ret < 0)
            continue;
          else if (ret == 0) {
            UW_SYSTEM_PIPE_CLOSE_OUT(cmd_to_ur);
            break;
          }
        }

        if (FD_ISSET( ur_to_cmd[1], &wfds )) {
          ret--;

          jlock _(r);

          size_t towrite = std::min(size_t(2*1024), r->buf_stdin.size() - r->sz_stdin);
          dprintf("Job #%d, going to write %d bytes\n", r->key, towrite);

          size_t written = write(ur_to_cmd[1], &r->buf_stdin[r->sz_stdin], towrite);

          dprintf("Job #%d, written %d bytes\n", r->key, written);

          if(written < 0) {
            if (errno == EINTR)
              continue;
            else
              r->throw_c([=](oss& e) { e << "write failed" ; });
          }

          r->sz_stdin += written;

          if ((r->sz_stdin == r->buf_stdin.size()) && r->close_stdin) {
            UW_SYSTEM_PIPE_CLOSE_IN(ur_to_cmd);
          }
        }

        if(ret > 0) {
          ls->log_error(ls->logger_data, "CallbackFFI BUG: select() reports unhandled state\n");
        }
      }
    }
  }
  catch(string &e) {
  }
  catch(std::exception &e) {
    dprintf("Job #%d exception %s\n", r->key, e.what());
    r->err << "std::exception " << e.what();
  }
  catch(...) {
    dprintf("Job #%d exception unknown\n", r->key);
    r->err << "C++ `...' exception";
  }

  if(r->err.str().size() > 0)
    dprintf("Job #%d's main loop executed with errors: %s\n", r->err.str().c_str());

  if (r->pid != -1) {
    int status;
    int rc = waitpid(r->pid, &status, 0);

    jlock _(r);
    if (rc == -1){
      dprintf("Job #%d waitpid() failed with %m\n", r->key);
    } else if (rc == r->pid) {
      if(WIFSIGNALED(status))
        r->exitcode = -WTERMSIG(status);
      else
        r->exitcode = WEXITSTATUS(status);
    } else {
      dprintf("Job #%d waitpid unexpected result code %d\n", r->key, rc);
    }
  }

  UW_SYSTEM_PIPE_CLOSE(cmd_to_ur);
  UW_SYSTEM_PIPE_CLOSE(cmd_to_ur2);
  UW_SYSTEM_PIPE_CLOSE(ur_to_cmd);
}
/*}}}*/

/*{{{ Notifier threads */
class notifiers {

  typedef std::pair<jptr, string> jpair;

  struct globals {
    uw_app *app = NULL;
    uw_loggers *lg = NULL;
  } static g;

  static jpair pop() {
    lock l;
    if(l.get().size() == 0)
      l.wait();
    jpair j = l.get().front();
    l.get().pop_front();
    return j;
  }

  static std::vector<pthread_t> threads;
  typedef std::list<jpair> joblist;

  struct lock {
    lock() : l(m) { }

    joblist& get() { return q; }

    void wait() { c.wait(l, []{return q.size() > 0; }); }

    static std::condition_variable c;

  private:
    std::unique_lock<std::mutex> l;

    static joblist q;
    static std::mutex m;
  };

public:

  static std::atomic<int> started;

  static void push(const jptr &j) {
    lock l;
    l.get().push_back(jpair(j, j->url_completion_cb));
    l.c.notify_one();
  }

  // TODO: check whether threads have started successfully or not
  static void init(uw_context* ctx, int nthreads) {

    g.app = uw_get_app(ctx);
    g.lg = uw_get_loggers(ctx);

    size_t tn = 1;
    threads.resize(nthreads);
    for (auto i=threads.begin(); i!=threads.end(); i++,tn++) {

      pthread_create(&(*i),NULL,[](void *tn_) -> void* {

        size_t tn = (size_t)tn_;
        int ret;
        uw_loggers *ls = g.lg;

        ls->log_debug(ls->logger_data, "CallbackFFI: Starting new thread\n");

        uw_context* ctx = uw_init(-(int)tn, ls);
        ret = uw_set_app(ctx, g.app);
        if(ret != 0) {
          ls->log_error(ls->logger_data, "CallbackFFI: failed to set the app (ret %d)\n", ret);
          uw_free(ctx);
          return NULL;
        }

        uw_set_headers(ctx, [](void*, const char*)->char*{return NULL;}, NULL);
        uw_set_env(ctx, [](void*, const char*)->char*{return NULL;}, NULL);

        bool ok = false;

        {
        failure_kind fk;
        int retries_left = 5;
        while(1) {
          fk = uw_begin_init(ctx);
          if (fk == SUCCESS) {
            ls->log_debug(ls->logger_data, "Database connection initialized.\n");
            ok = true;
            break;
          } else if (fk == BOUNDED_RETRY) {
            if (retries_left) {
              ls->log_debug(ls->logger_data, "Initialization error triggers bounded retry: %s\n", uw_error_message(ctx));
              --retries_left;
            } else {
              ls->log_error(ls->logger_data, "Fatal initialization error (out of retries): %s\n", uw_error_message(ctx));
              break;
            }
          } else if (fk == UNLIMITED_RETRY)
            ls->log_debug(ls->logger_data, "Initialization error triggers unlimited retry: %s\n", uw_error_message(ctx));
          else if (fk == FATAL) {
            ls->log_error(ls->logger_data, "Fatal initialization error: %s\n", uw_error_message(ctx));
            break;
          } else {
            ls->log_error(ls->logger_data, "Unknown uw_begin_init return code!\n");
            break;
          }
        }
        }

        char *path = NULL;
        while(ok) {
          jpair jp = pop();
          jptr& j = jp.first;

          if(path) free(path);
          path = strdup(jp.second.c_str());

          /* int retries_left = 50; */
          failure_kind fk;

          do {
            uw_reset(ctx);
            uw_set_deadline(ctx, uw_time + uw_time_max);

            fk = uw_begin(ctx, path);

            if (fk == FATAL ) {
              ls->log_error(ls->logger_data, "[CB] Fatal error: job #%d text '%s'\n",
                j->key, uw_error_message(ctx));

              if (uw_rollback(ctx, 0)) {
                ls->log_error(ls->logger_data, "[CB] Fatal error: rollback failed: job #%d\n", j->key);
              }
              break;
            }
            
            /* FIXME: BOUNDER RETRIES are treated as unlimited retries here */
            if( fk == BOUNDED_RETRY || fk == UNLIMITED_RETRY) {
              ls->log_debug(ls->logger_data, "[CB] Error triggers unlimited retry: job #%d text '%s'\n",
                j->key, uw_error_message(ctx));

              if (uw_rollback(ctx, 1)) {
                ls->log_error(ls->logger_data, "[CB] Fatal error: rollback failed: job #%d\n", j->key);
                break;
              }

              usleep(1000);
              continue;
            }

            if (fk == SUCCESS) {
              int ret = uw_commit(ctx);
              if(ret == 1) {
                ls->log_error(ls->logger_data, "[CB] Commit db_commit error for job #%d\n", j->key);
                continue;
              }
              else if( uw_has_error(ctx)) {
                ls->log_error(ls->logger_data, "[CB] Commit generic error for job #%d\n", j->key);
                continue;
              }
              else {
                ls->log_debug(ls->logger_data, "[CB] Commit successful for job #%d\n", j->key);
                break;
              }
            }
          } while (1);

        } /* while(ok) */

        ls->log_debug(ls->logger_data, "[CB] Exiting from worker %d\n", tn);
        uw_free(ctx);
        return NULL;

      }, (void*)tn);
    }
  }
};

std::atomic<int> notifiers::started(0);
std::vector<pthread_t> notifiers::threads;
std::mutex notifiers::lock::m;
std::condition_variable notifiers::lock::c;
notifiers::joblist notifiers::lock::q;
notifiers::globals notifiers::g;
/*}}}*/

class jobset {

  typedef std::map< jkey, std::list<jptr> > jobmap;

  static jobmap jm;
  static std::mutex m;

public:
  jobset() { m.lock(); }
  ~jobset() { m.unlock(); }

  bool insert(const jptr &j) {
    auto i = jm.find(j->key);
    if (i != jm.end()) {
      if(j.get() != i->second.front().get()) {
        return false;
      }
      else {
        i->second.push_back(j);
        return true;
      }
    }
    else {
      std::list<jptr> l;
      l.push_back(j);
      jm.insert(jm.end(), jobmap::value_type(j->key, l));
      return true;
    }
  }

  void remove(const jptr &j) {
    auto i = jm.find(j->key);
    if (i != jm.end()) {
      i->second.pop_front();
      if(i->second.size() == 0) {
        jm.erase(i);
        dprintf("jobset: removing #%d (finally)\n", j->key);
      }
      else {
        dprintf("jobset: removing #%d\n", j->key);
      }
    }
  }

  jptr find(int key) {
    auto i = jm.find(key);
    if (i != jm.end())
      return i->second.front();
    else
      return jptr();
  }
};

mutex jobset::m;
jobset::jobmap jobset::jm;


jptr get(void* j) { return *((jptr*)j); }

uw_Basis_unit uw_CallbackFFI_initialize(
  struct uw_context *ctx,
  uw_Basis_int nthread)
{
  if((notifiers::started++) == 0) {
    notifiers::init(ctx,nthread);
  }
  return 0;
}

static char UWCB_LIMIT[] = "UWCB_LIMIT\0";

uw_CallbackFFI_job uw_CallbackFFI_create(
  struct uw_context *ctx,
  uw_Basis_string cmd,
  uw_Basis_int stdout_sz,
  uw_Basis_int jr)
{
  jptr* pp;

  int limit = (long int)uw_get_global(ctx, UWCB_LIMIT);
  if(limit > 0) {
    bool fail;
    { job::atomic_counter c;
      fail = c.get() > limit-1;
    }
    if(fail) {
      uw_error(ctx, FATAL, "Job count exceedes limit of %d\n", limit);
    }
  }

  {
    pp = new jptr(new job(jr, cmd, stdout_sz));
    get(pp)->m.lock();
    dprintf("Job #%d create lock (cmd %s)\n", get(pp)->key, cmd);

    jobset s;
    if(! s.insert(get(pp))) {
      delete ((jptr*)pp);
      pp = NULL;
    }
  }

  if(pp == NULL)
    uw_error(ctx, FATAL, "Failed to create a job %s using jey #%d\n", cmd, jr);

  uw_register_transactional(ctx, pp, NULL, NULL,
    [](void* pp, int) {
      jobset s;
      s.remove(get(pp));
      get(pp)->m.unlock();
      dprintf("Job #%d create unlock\n", get(pp)->key);
      delete ((jptr*)pp);
    });

  uw_register_transactional(ctx, pp,
    [] (void *pp) {
      jobset s;
      bool ret = s.insert(get(pp));
      assert(ret == true);
    },
    NULL, NULL);

  return pp;
}

uw_Basis_unit uw_CallbackFFI_pushStdin(struct uw_context *ctx,
    uw_CallbackFFI_job j,
    uw_Basis_blob _stdin,
    uw_Basis_int maxsz)
{

  int jr = get(j)->key;

  dprintf("Job #%d push_stdin\n", get(j)->key);

  if(_stdin.size > maxsz)
    uw_error(ctx, FATAL, "pushStdin: input of size %d will never fit into job #%d's buffer of size %d\n",
      _stdin.size, jr, maxsz);

  enum {ok, closed, err} ret = err;

  {
    if(!get(j)->close_stdin) {
      blob &buf_stdin = get(j)->buf_stdin;

      size_t oldsz = buf_stdin.size() - get(j)->sz_stdin;
      size_t newsz = oldsz + _stdin.size;
      if(newsz <= maxsz) {
        buf_stdin.resize(newsz);
        memcpy(&buf_stdin[0], &buf_stdin[get(j)->sz_stdin], oldsz);
        memcpy(&buf_stdin[oldsz], _stdin.data, _stdin.size);
        get(j)->sz_stdin = 0;

        if(_stdin.size > 0) {
          if(get(j)->thread_started) {
            int ret = pthread_kill(get(j)->thread, JOB_SIGNAL);
            if(ret != 0)
              dprintf("pushStdin: pthread_kill() failed with %d\n", ret);
          }
        }
        else {
          dprintf("pushStdin: stdin.size == 0, doing nothing\n", ret);
        }
        ret = ok;
      }
      else {
        ret = err;
      }
    }
    else {
      ret = closed;
    }
  }

  switch(ret) {
    case closed:
      uw_error(ctx, FATAL, "job #%d stdin closed\n", jr);
      break;
    case err:
      uw_error(ctx, BOUNDED_RETRY, "job #%d stdin size exceeds limit\n", jr);
      break;
    default:
      break;
  }

  return 0;
}

uw_Basis_unit uw_CallbackFFI_pushStdinEOF(struct uw_context *ctx, uw_CallbackFFI_job j)
{
  get(j)->close_stdin = true;
  if(get(j)->thread_started) {
    int ret = pthread_kill(get(j)->thread, JOB_SIGNAL);
    if(ret != 0)
      dprintf("pushStdin: pthread_kill() failed with %d\n", ret);
  }
  return 0;
}

uw_Basis_unit uw_CallbackFFI_pushArg(struct uw_context *ctx, uw_CallbackFFI_job j, uw_Basis_string arg)
{
  dprintf("Job #%d push_arg\n", get(j)->key);
  if(get(j)->thread_started)
    uw_error(ctx, FATAL, "pushArg: job #%d is already running\n", get(j)->key);
  get(j)->args.push_back(arg); 
  get(j)->cmd_and_args += (string(" ") + arg);
}

uw_Basis_unit uw_CallbackFFI_setCompletionCB(struct uw_context *ctx, uw_CallbackFFI_job j, uw_Basis_string mburl)
{
  if(mburl) {
    get(j)->url_completion_cb = string(mburl);
  }
  else {
    get(j)->url_completion_cb = string();
  }
  return 0;
}

uw_Basis_unit uw_CallbackFFI_setNotifyCB(struct uw_context *ctx, uw_CallbackFFI_job j, uw_Basis_string mburl)
{
  if(mburl) {
    get(j)->url_notify_cb = string(mburl);
  }
  else {
    get(j)->url_notify_cb = string();
  }
  return 0;
}

struct pack {
  pack(jptr j_, uw_loggers *lg_):j(j_),lg(lg_) {}
  pack(const pack &p) : j(p.j), lg(p.lg) {}

  jptr j;
  uw_loggers *lg;
};

uw_Basis_unit uw_CallbackFFI_run(
  struct uw_context *ctx,
  uw_CallbackFFI_job _j)
{
  if(notifiers::started == 0 ) {
    uw_error(ctx, FATAL, "CallbackFFI: notifiers pool is not initialized");
  }

  pack *p = new pack(get(_j), uw_get_loggers(ctx));

  uw_register_transactional(ctx, p, NULL, NULL,
    [](void* p_, int) {
      delete (pack*)p_;
    });

  uw_register_transactional(ctx, p,
    [](void* p_) {
      pack* p = new pack(*(pack*)p_);
      int ret;

      ret = pthread_create(&p->j->thread, NULL, [](void *p_) -> void* {
        pack* p = (pack*)p_;

        struct sigaction s;
        memset(&s, 0, sizeof(struct sigaction));
        s.sa_handler = [](int signo) -> void { (void) signo; };
        sigemptyset(&s.sa_mask);
        s.sa_flags = 0;
        sigaction(JOB_SIGNAL, &s, NULL);

        sigset_t ss, oldss;
        sigemptyset(&ss);
        sigaddset(&ss, JOB_SIGNAL);
        pthread_sigmask(SIG_BLOCK, &ss, &oldss);

        p->j->thread_started = true;

        try {
          execute(p->j, p->lg, &oldss);
        }
        catch(job::exception &e) {
          dprintf("CallbackFFI execute: %s\n", e.c_str());
        }

        {
          jlock _(p->j);
          if(p->j->url_completion_cb.size() > 0) {
            notifiers::push(p->j);
          }
        }

        delete p;
        return NULL;

      }, p);

      if(ret != 0) {
        dprintf("CallbackFFI execute: bad state for #%d\n", p->j->key);
        p->j->exitcode = INT_MAX;
        delete p;
      }
    }, NULL, NULL);

  return 0;
}

uw_Basis_unit uw_CallbackFFI_cleanup(struct uw_context *ctx, uw_CallbackFFI_job j_)
{
  if(get(j_)->cleanup_flag > 0)
    uw_error(ctx, FATAL, "duplicate cleanup call for job #%d", get(j_)->key);

  get(j_)->cleanup_flag = 1;

  void* j = new jptr(get(j_));

  uw_register_transactional(ctx, j, NULL, NULL,
    [](void* j_, int) {
      get(j_)->cleanup_flag--;
      delete ((jptr*)j_);
    });

  uw_register_transactional(ctx, j,
    [](void* j_) {
      jobset s;
      s.remove(get(j_));
      get(j_)->cleanup_flag++;
    }, NULL , NULL);

  return 0;
}

uw_CallbackFFI_job* uw_CallbackFFI_tryDeref(struct uw_context *ctx, uw_CallbackFFI_jobref k)
{
  void* pp = NULL;

  {
    jobset s;
    jptr j = s.find(k);
    if (j)
      pp = new jptr(j);
    else
      pp = NULL;
  }

  if(pp) {
    get(pp)->m.lock();
    dprintf("Job #%d deref lock\n", get(pp)->key);

    uw_register_transactional(ctx, pp, NULL, NULL,
      [](void* pp, int) {
        dprintf("Job #%d deref unlock\n", get(pp)->key);
        get(pp)->m.unlock();
        delete ((jptr*)pp);
      });

    uw_CallbackFFI_job* pp2 = (uw_CallbackFFI_job*)uw_malloc(ctx, sizeof(uw_CallbackFFI_job*));
    *pp2 = pp;
    return pp2;
  }

  return NULL;
}

uw_CallbackFFI_job uw_CallbackFFI_deref(struct uw_context *ctx, uw_CallbackFFI_jobref k)
{
  uw_CallbackFFI_job* pp = uw_CallbackFFI_tryDeref(ctx, k);

  if(!pp)
    uw_error(ctx, FATAL, "No such job #%d", k);

  return *pp;
}

uw_Basis_int uw_CallbackFFI_exitcode(struct uw_context *ctx, uw_CallbackFFI_job j)
{
  return get(j)->exitcode;
}

uw_Basis_int uw_CallbackFFI_pid(struct uw_context *ctx, uw_CallbackFFI_job j)
{
  return get(j)->pid;
}

uw_CallbackFFI_jobref uw_CallbackFFI_ref(struct uw_context *ctx, uw_CallbackFFI_job j)
{
  return get(j)->key;
}

uw_Basis_blob uw_CallbackFFI_stdout(struct uw_context *ctx, uw_CallbackFFI_job j)
{
  uw_Basis_blob b;
  b.size = get(j)->sz_stdout;
  b.data = (char*)uw_malloc(ctx, b.size);
  memcpy(b.data, get(j)->buf_stdout.data(), b.size);
  return b;
}

uw_Basis_blob uw_CallbackFFI_stderr(struct uw_context *ctx, uw_CallbackFFI_job j)
{
  uw_Basis_blob b;
  b.size = get(j)->sz_stderr;
  b.data = (char*)uw_malloc(ctx, b.size);
  memcpy(b.data, get(j)->buf_stderr.data(), b.size);
  return b;
}

uw_Basis_string uw_CallbackFFI_cmd(struct uw_context *ctx, uw_CallbackFFI_job j)
{
  string *s = &get(j)->cmd_and_args;
  size_t sz = s->length();
  char* str = (char*)uw_malloc(ctx, sz + 1);
  memcpy(str, s->c_str(), sz);
  str[sz] = 0;
  return str;
}

uw_Basis_string uw_CallbackFFI_errors(struct uw_context *ctx, uw_CallbackFFI_job j)
{
  size_t sz = get(j)->err.str().length();
  char* str = (char*)uw_malloc(ctx, sz + 1);

  memcpy(str, get(j)->err.str().c_str(), sz);
  str[sz] = 0;

  return str;
}

uw_Basis_string uw_CallbackFFI_blobLines(struct uw_context *ctx, uw_Basis_blob b)
{
  size_t len = strnlen(b.data, b.size);
  char* str = (char*) uw_malloc(ctx, len+1);
  memcpy(str, b.data, len);
  str[len] = 0;
  return str;
}

uw_Basis_string uw_CallbackFFI_lastLines(struct uw_context *ctx, int cnt, uw_Basis_blob b)
{
  int i;
  size_t end;

  if(cnt == 0) {
    static char s[] = "";
    return s;
  }

  const char *o = (const char*)b.data;
  end = b.size;
  for(i=end-1; i>=0; i--) {

    if(o[i] == '\n') {
      if((end-(i+1)) >= 1) {
        if(cnt == 1)
          break;
        cnt--;
      }
      else {
        end = i;
      }
    }

    if(o[i] == 0 ) {
      /* Extra zero's ?? */
      end = i;
      cnt = 0;
    }

  }

  char* str = (char*) uw_malloc(ctx, end-(i+1)+1);
  memcpy(str, &o[(i+1)], end-(i+1));
  str[end-(i+1)] = 0;
  return str;
}

uw_Basis_unit uw_CallbackFFI_executeSync(
  struct uw_context *ctx,
  uw_CallbackFFI_job j)
{
  try {
    dprintf("Job #%d executeSync\n", get(j)->key);
    execute(get(j), uw_get_loggers(ctx), NULL);
  }
  catch(job::exception &e) {
    dprintf("CallbackFFI::executeSync error: %s\n", e.c_str());
  }
}

uw_Basis_unit uw_CallbackFFI_forceBoundedRetry(struct uw_context *ctx, uw_Basis_string msg)
{
  uw_error(ctx, BOUNDED_RETRY, "CallbackFFI::retry: %s", msg);
  return 0;
}

uw_Basis_int uw_CallbackFFI_nactive(struct uw_context *ctx)
{
  job::atomic_counter c;
  return c.get();
}

uw_Basis_unit uw_CallbackFFI_limitActive(struct uw_context *ctx, uw_Basis_int l)
{
  uw_set_global(ctx, UWCB_LIMIT, (void*)l, NULL);
}

