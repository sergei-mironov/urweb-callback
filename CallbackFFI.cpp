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
#include <srvthread.h>
#include "CallbackFFI.h"
}

#include <map>
#include <string>
#include <memory>
#include <sstream>
#include <list>
#include <vector>
#include <algorithm>
#include <mutex>
#include <condition_variable>
#include <atomic>
#include <climits>


#define dprintf printf

/* 0,1 are pipe ids, 2,3 is zero if pipe is closed */
typedef int uw_System_pipe[4];

#define JOB_SIGNAL SIGUSR1

#define UR_SYSTEM_POLL_TIMOUT_MS 1000

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
  job(jkey _key, const string &_cmd, int _bufsize, atomic& counter_) :
		  key(_key), cmd(_cmd), counter(counter_) {
    buf_stdout.resize(_bufsize);
    sz_stdout = 0;
    sz_stdin = 0;
    exitcode = -1;
    close_stdin = false;
    thread_started = false;
    counter++;

    int x = counter;
    fprintf(stderr, "Hello job #%d (cnt %d)\n", key, x);
  }

  ~job() {
    // FIXME: remove this
    fprintf(stderr, "Bye-bye job #%d\n", key);
    counter--;
  }

  jkey key;

  string cmd;

  string url_completion_cb;
  string url_notify_cb;

  int pid = -1;

  // Host thread running the job
  pthread_t thread;
  bool thread_started;

  mutex m;

  // Exit code. Needs mutex.
  int exitcode;

  bool close_stdin;

  size_t sz_stdout;
  size_t sz_stdin;

  blob buf_stdout;
  blob buf_stdin;

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

private:

  atomic& counter;
};

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

/*{{{ execute */

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

    int pid = fork(); // local var required? TODO
    if (pid == -1)
      r->throw_c([=](oss& e) { e << "fork failed" ; });

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

      /* run command using /bin/sh shell - is there a shorter way to do this? */
      char * argv[3];
      argv[0] = (char*) "/bin/sh";
      argv[1] = (char*) "-c";
      argv[2] = (char*) r->cmd.c_str();
      argv[3] = NULL;
      execv("/bin/sh", argv);
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

        if (ur_to_cmd[1+2] != 0) {
          MY_FD_SET_546( ur_to_cmd[1], &wfds );
        }

        struct timespec tv;
        tv.tv_sec  = UR_SYSTEM_POLL_TIMOUT_MS / 1000;
        tv.tv_nsec = (UR_SYSTEM_POLL_TIMOUT_MS % 1000) * 1000;

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
          int bytes_read;
          unsigned char buf[512+1];
          
          bytes_read = read(cmd_to_ur2[0], &buf[0], 512);
          if(bytes_read > 0) {
            buf[bytes_read] = 0;
            ls->log_error(ls->logger_data,"%s", buf);
          }
        }

        if (FD_ISSET( cmd_to_ur[0], &rfds )) {
          ret--;
          size_t bytes_read;

          if(r->sz_stdout < r->buf_stdout.size()) {
            // FIXME: calling C read while holding a mutex. Looks safe, but
            // still suspicious.
            jlock _(r);
            bytes_read = read(cmd_to_ur[0], &r->buf_stdout[r->sz_stdout], r->buf_stdout.size() - r->sz_stdout);

            if(bytes_read < 0) {
              if(errno == EINTR)
                continue;
              else
                r->throw_c([=](oss& e) { e << "read failed" ; });
            }

            r->sz_stdout += bytes_read;
          }
          else {
            blob devnull(r->buf_stdout.size() / 2);

            bytes_read = read(cmd_to_ur[0], &devnull[0], devnull.size());

            if(bytes_read < 0) {
              if(errno == EINTR)
                continue;
              else
                r->throw_c([=](oss& e) { e << "read failed (devnull)" ; });
            }
            else {
              jlock _(r);
              memcpy(&r->buf_stdout[0], &r->buf_stdout[bytes_read], r->buf_stdout.size() - bytes_read);
              memcpy(&r->buf_stdout[r->buf_stdout.size() - bytes_read], &devnull[0], bytes_read);
            }
          }

          if (bytes_read == 0) {
            UW_SYSTEM_PIPE_CLOSE_OUT(cmd_to_ur);
            break;
          }
        }

        if (FD_ISSET( ur_to_cmd[1], &wfds )) {
          ret--;

          // FIXME: calling C write while holding a mutex. Looks safe, but
          // still suspicious.
          jlock _(r);

          size_t written = write(ur_to_cmd[1], &r->buf_stdin[r->sz_stdin], r->buf_stdin.size() - r->sz_stdin);

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
    r->err << "std::exception " << e.what();
  }
  catch(...) {
    r->err << "C++ `...' exception";
  }

  if (r->pid != -1) {
    int status;
    int rc = waitpid(r->pid, &status, 0);

    jlock _(r);
    if (rc == -1){
      r->err << "waitpid failed: pid " << r->pid << " errno " << errno;
    } else if (rc == r->pid) {
      if(WIFSIGNALED(status))
        r->exitcode = -WTERMSIG(status);
      else
        r->exitcode = WEXITSTATUS(status);
    } else {
      r->err << "waitpid unexpected result: code " << rc;
    }
  }

  UW_SYSTEM_PIPE_CLOSE(cmd_to_ur);
  UW_SYSTEM_PIPE_CLOSE(cmd_to_ur2);
  UW_SYSTEM_PIPE_CLOSE(ur_to_cmd);
}
/*}}}*/


struct notifiers {

  typedef std::pair<jptr, string> jpair;

  static void push(jpair j) {
    lock l;
    l.get().push_back(j);
    l.c.notify_one();
  }

  // TODO: check whether threads have started successfully or not
  static void init(uw_context* ctx, int nthreads) {

    g.app = uw_get_app(ctx);
    g.lg = uw_get_loggers(ctx);

    threads.resize(nthreads);
    for (auto i=threads.begin(); i!=threads.end(); i++) {

      pthread_create(&(*i),NULL,[](void *p_) -> void* {

        int ret;
        fprintf(stderr, "CallbackFFI: Starting new thread\n");

        uw_loggers *ls = g.lg;
        uw_context* ctx = uw_init(-1, ls);
        ret = uw_set_app(ctx, g.app);
        if(ret != 0) {
          fprintf(stderr, "CallbackFFI: failed to set the app (ret %d)\n", ret);
          uw_free(ctx);
          return NULL;
        }

        uw_set_headers(ctx, [](void*, const char*)->char*{return NULL;}, NULL);
        uw_set_env(ctx, [](void*, const char*)->char*{return NULL;}, NULL);

        bool ok = false;
        int retries_left;
        failure_kind fk;

        retries_left = 5;
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

        char *path = NULL;
        while(ok) {
          jpair jp = pop();
          jptr& j = jp.first;

          if(path) free(path);
          path = strdup(jp.second.c_str());

          retries_left = 50;
          do {
            uw_reset(ctx);
            uw_set_deadline(ctx, uw_time + uw_time_max);

            fk = uw_begin(ctx, path);

            if (fk == UNLIMITED_RETRY)
              ls->log_debug(ls->logger_data, "Error triggers unlimited retry in loopback: %s\n", uw_error_message(ctx));
            else if (fk == BOUNDED_RETRY) {
              --retries_left;
              ls->log_debug(ls->logger_data, "Error triggers bounded retry in loopback: %s (with delay)\n", uw_error_message(ctx));
              sleep(1);
              // FIXME: have to save retries_left in the job state
              push(jp);
            }
            else if (fk == FATAL)
              ls->log_error(ls->logger_data, "Fatal error: %s\n", uw_error_message(ctx));

            if (fk == FATAL || fk == BOUNDED_RETRY || fk == UNLIMITED_RETRY)
              if (uw_rollback(ctx, 0)) {
                ls->log_error(ls->logger_data, "Fatal error: rollback failed in loopback\n");
                continue;
              }
          } while (fk == UNLIMITED_RETRY || (fk == BOUNDED_RETRY && retries_left > 0));

          if (fk != FATAL && fk != BOUNDED_RETRY)
            uw_commit(ctx);

        } /* while(ok) */

        uw_free(ctx);
        return NULL;

      }, NULL);
    }
  }

  static std::atomic<int> started;

private:

  struct globals {
    uw_app *app = NULL;
    uw_loggers *lg = NULL;
  } static g;


  static jpair pop() {
    lock l;
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
};

std::atomic<int> notifiers::started(0);
std::vector<pthread_t> notifiers::threads;
std::mutex notifiers::lock::m;
std::condition_variable notifiers::lock::c;
notifiers::joblist notifiers::lock::q;
notifiers::globals notifiers::g;



typedef std::map<jkey,jptr> jobmap;

struct joblock {
  joblock() { m.lock(); }
  ~joblock() { m.unlock(); }

  jobmap& get() { return jm; }
  jobmap& operator& () { return jm; } 

  static atomic cnt;

private:
  static jobmap jm;
  static mutex m;
};

mutex joblock::m;
jobmap joblock::jm;
atomic joblock::cnt;

jptr get(uw_CallbackFFI_job j) { return *((jptr*)j); }

uw_Basis_unit uw_CallbackFFI_initialize(
  struct uw_context *ctx,
  uw_Basis_int nthread)
{
  if((notifiers::started++) == 0) {
    notifiers::init(ctx,nthread);
  }
  return 0;
}

uw_CallbackFFI_job uw_CallbackFFI_create(
  struct uw_context *ctx,
  uw_Basis_string cmd,
  uw_Basis_int stdout_sz,
  uw_Basis_int jr)
{
  joblock l;
  jobmap& js(l.get());
  jptr j(new job(jr,
                 cmd,
                 stdout_sz,
                 l.cnt));

  js.insert(js.end(), jobmap::value_type(j->key, j));

  jptr* pp = new jptr(j);
  uw_register_transactional(ctx, pp, NULL,
    [] (void *pp) {
      joblock l;
      jobmap &js(l.get());

      auto i = js.find(get(pp)->key);
      if (i != js.end()) {
        js.erase(i);
      }
    },
    [](void* pp, int) {
      delete ((jptr*)pp);
    });
  return pp;
}

uw_Basis_unit uw_CallbackFFI_pushStdin(struct uw_context *ctx,
    uw_CallbackFFI_job j,
    uw_Basis_blob _stdin,
    uw_Basis_int maxsz)
{
  enum {ok, closed, err} ret = err;

  {
    jlock _(get(j));
    if(!get(j)->close_stdin) {
      blob &buf_stdin = get(j)->buf_stdin;
      size_t oldsz = buf_stdin.size() - get(j)->sz_stdin;
      size_t newsz = buf_stdin.size() + _stdin.size - get(j)->sz_stdin;
      if(newsz <= maxsz ) {
        buf_stdin.resize(newsz);
        memcpy(&buf_stdin[0], &buf_stdin[get(j)->sz_stdin], oldsz);
        memcpy(&buf_stdin[oldsz], _stdin.data, _stdin.size);
        get(j)->sz_stdin = 0;

        if(get(j)->thread_started)
          pthread_kill(get(j)->thread, JOB_SIGNAL);
        ret = ok;
      }
    }
    else {
      ret = closed;
    }
  }

  switch(ret) {
    case closed:
      uw_error(ctx, FATAL, "job %d stdin closed\n", get(j)->key);
      break;
    case err:
      uw_error(ctx, FATAL, "job %d stdin size exceeds limit\n", get(j)->key);
      break;
    default:
      break;
  }

  return 0;
}

uw_Basis_unit uw_CallbackFFI_pushStdinEOF(struct uw_context *ctx, uw_CallbackFFI_job j)
{
  jlock _(get(j));
  get(j)->close_stdin = true;
  if(get(j)->thread_started)
    pthread_kill(get(j)->thread, JOB_SIGNAL);
  return 0;
}

uw_Basis_unit uw_CallbackFFI_setCompletionCB(struct uw_context *ctx, uw_CallbackFFI_job j, uw_Basis_string mburl)
{
  jlock _(get(j));
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
  jlock _(get(j));
  if(mburl) {
    get(j)->url_notify_cb = string(mburl);
  }
  else {
    get(j)->url_notify_cb = string();
  }
  return 0;
}

uw_Basis_unit uw_CallbackFFI_run(
  struct uw_context *ctx,
  uw_CallbackFFI_job _j)
{
  if(notifiers::started == 0 ) {
    uw_error(ctx, FATAL, "CallbackFFI: notifiers pool is not initialized");
  }

  int ret;

  uw_context* ctx2 = uw_init(-1, uw_get_loggers(ctx));
  if(!ctx2)
    uw_error(ctx, FATAL, "CallbackFFI: Failed to create the context");

  ret = uw_set_app(ctx2, uw_get_app(ctx));
  if(ret != 0)
    uw_error(ctx, FATAL, "CallbackFFI: Failure in uw_set_app; ret %d", ret);

  uw_set_headers(ctx2, [](void*, const char*)->char*{return NULL;}, NULL);
  uw_set_env(ctx2, [](void*, const char*)->char*{return NULL;}, NULL);

  struct pack { jptr j; uw_context *ctx; };

  uw_register_transactional(ctx,
    new pack {get(_j), ctx2},
    [](void* p_) {
      pack* p = (pack*)p_;
      int ret;
      
      ret = pthread_create(&p->j->thread, NULL, [](void *p_) -> void* {
        pack* p = (pack*)p_;

        uw_context *ctx = p->ctx;
        uw_loggers *ls = uw_get_loggers(p->ctx);

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
          execute(p->j, ls, &oldss);
        }
        catch(job::exception &e) {
          fprintf(stderr,"CallbackFFI execute: %s\n", e.c_str());
        }

        {
          jlock _(p->j);
          if(p->j->url_completion_cb.size() > 0)
            notifiers::push(notifiers::jpair(p->j, p->j->url_completion_cb));
        }

      out:
        delete p;
        return NULL;

      }, p_);

      if(ret != 0) {
        fprintf(stderr,"CallbackFFI execute: bad state for #%d\n", p->j->key);
        p->j->exitcode = INT_MAX;
        delete p;
      }
    },

    [](void *p_) {
      pack* p = (pack*)p_;
      delete p;
    },

    [](void *p, int x) {
    });

  return 0;
}

uw_Basis_unit uw_CallbackFFI_cleanup(struct uw_context *ctx, uw_CallbackFFI_job j)
{
  uw_register_transactional(ctx, j,
    [](uw_CallbackFFI_job j) {
      joblock l;
      jobmap &js(l.get());

      auto i = js.find(get(j)->key);
      if (i != js.end()) {
        js.erase(i);
      }
    }, NULL, NULL);
  return 0;
}

uw_CallbackFFI_job* uw_CallbackFFI_tryDeref(struct uw_context *ctx, uw_CallbackFFI_jobref k)
{
  uw_CallbackFFI_job pp = NULL;

  {
    joblock l;
    jobmap& js(l.get());

    jobmap::iterator j = js.find(k);
    if (j != js.end())
      pp = new jptr(j->second);
    else
      pp = NULL;
  }

  if(pp) {
    uw_register_transactional(ctx, pp, NULL, NULL, [](void* pp, int) {delete ((jptr*)pp);});
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
  jlock _(get(j));
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

uw_Basis_string uw_CallbackFFI_stdout(struct uw_context *ctx, uw_CallbackFFI_job j)
{
  size_t sz = get(j)->sz_stdout;
  char* str = (char*)uw_malloc(ctx, sz + 1);

  jlock _(get(j));
  memcpy(str, get(j)->buf_stdout.data(), sz);
  str[sz] = 0;

  return str;
}

uw_Basis_string uw_CallbackFFI_cmd(struct uw_context *ctx, uw_CallbackFFI_job j)
{
  size_t sz = get(j)->cmd.length();
  char* str = (char*)uw_malloc(ctx, sz + 1);
  memcpy(str, get(j)->cmd.c_str(), sz);
  str[sz] = 0;
  return str;
}

uw_Basis_string uw_CallbackFFI_errors(struct uw_context *ctx, uw_CallbackFFI_job j)
{
  size_t sz = get(j)->err.str().length();
  char* str = (char*)uw_malloc(ctx, sz + 1);

  jlock _(get(j));
  memcpy(str, get(j)->err.str().c_str(), sz);
  str[sz] = 0;

  return str;
}

uw_Basis_string uw_CallbackFFI_lastLine(struct uw_context *ctx, uw_Basis_string o)
{
  int i;
  size_t end = strlen(o);
  for(i=end-1; i>=0; i--) {

    if(o[i] == '\n') {
      if((end-(i+1)) >= 1) {
        break;
      }
      else {
        end = i;
      }
    }

    if(o[i] == 0 ) {
      end = i;
    }

  }

  char* str = (char*) uw_malloc(ctx, end-(i+1)+1);
  memcpy(str, &o[(i+1)], end-(i+1));
  str[end-(i+1)] = 0;
  return str;
}

uw_CallbackFFI_job uw_CallbackFFI_runNow(
  struct uw_context *ctx,
  uw_Basis_string cmd,
  uw_Basis_int stdout_sz,
  uw_Basis_blob _stdin,
  uw_Basis_int jobref)
{
  uw_CallbackFFI_job j = uw_CallbackFFI_create(ctx, cmd, stdout_sz, jobref);
  uw_CallbackFFI_pushStdin(ctx, j, _stdin, _stdin.size);
  uw_CallbackFFI_pushStdinEOF(ctx, j);

  try {
    execute(get(j), uw_get_loggers(ctx), NULL);
  }
  catch(job::exception &e) {
    fprintf(stderr,"CallbackFFI::runNow error: %s\n", e.c_str());
  }

  return j;
}

uw_Basis_unit uw_CallbackFFI_forceBoundedRetry(struct uw_context *ctx, uw_Basis_string msg)
{
  uw_error(ctx, BOUNDED_RETRY, "CallbackFFI::retry: %s", msg);
  return 0;
}

uw_Basis_int uw_CallbackFFI_nactive(struct uw_context *ctx, uw_Basis_unit u)
{
  int x;
  {joblock l;
    x = l.cnt;
  }
  return x;
}

