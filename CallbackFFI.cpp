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

#include <urweb_cpp.h>
#include <srvthread.h>
#include "CallbackFFI.h"
}

#include <map>
#include <string>
#include <memory>
#include <sstream>
#include <vector>
#include <thread>
#include <algorithm>
#include <mutex>


#define dprintf printf

/* 0,1 are pipe ids, 2,3 is zero if pipe is closed */
typedef int uw_System_pipe[4];

#define UR_SYSTEM_POLL_TIMOUT_MS 1000

#define UW_SYSTEM_PIPE_INIT(x) { x[2] = 0; x[3]=0; }
#define UW_SYSTEM_PIPE_CLOSE_IN(x)  { close(x[1]); x[3] = 0; }
#define UW_SYSTEM_PIPE_CLOSE_OUT(x) { close(x[0]); x[2] = 0; }
#define UW_SYSTEM_PIPE_CLOSE(x) do { \
    if (x[2]) { close(x[0]); x[2] = 0; } \
    if (x[3]) { close(x[1]); x[3] = 0; } \
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
typedef long int jkey;

struct job {
  job(jkey _key, const string &_cmd, const blob &_buf_write, int _bufsize) :
		key(_key), cmd(_cmd), buf_write(_buf_write) {
    buf_read.resize(_bufsize);
  }

  ~job() {
    fprintf(stderr, "Bye-bye job #%d\n", key);
  }

  jkey key;

  string cmd;

  int pid = -1;

  mutex m;

  // Exit code. Needs mutex.
  int exitcode = -1;

  size_t total_read = 0;
  size_t total_written = 0;

  // Data to write to job's stdin.
  blob buf_write;

  // Data to read from job's stdout. Needs mutex.
  blob buf_read;

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

/*{{{*/

/* Borrowed from Mark Weber's uw-process. Thanks, Mark. */
static void execute(jptr r)
{
  uw_System_pipe ur_to_cmd;
  uw_System_pipe cmd_to_ur;

  UW_SYSTEM_PIPE_INIT(ur_to_cmd);
  UW_SYSTEM_PIPE_INIT(cmd_to_ur);

  try {
    UW_SYSTEM_PIPE_CREATE(ur_to_cmd);
    UW_SYSTEM_PIPE_CREATE(cmd_to_ur);

    int pid = fork(); // local var required? TODO
    if (pid == -1)
      r->throw_c([=](oss& e) { e << "fork failed" ; });

    r->pid = pid;

    if (r->pid == 0) {
      /* child
       * TODO: should be closing all fds ? but the ones being used? */
      close(ur_to_cmd[1]);
      close(cmd_to_ur[0]);

      /* assign stdin */
      close(0);
      dup(ur_to_cmd[0]);
      close(ur_to_cmd[0]);

      /* assign stdout */
      close(1);
      dup(cmd_to_ur[1]);
      close(cmd_to_ur[1]);

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

        if (r->total_written < r->buf_write.size()){
          MY_FD_SET_546( ur_to_cmd[1], &wfds );
        }

        struct timeval tv;
        tv.tv_sec  = UR_SYSTEM_POLL_TIMOUT_MS / 1000;
        tv.tv_usec = (UR_SYSTEM_POLL_TIMOUT_MS % 1000) * (1000000/1000);

        int ret = select(max_fd +1, &rfds, &wfds, &efds, &tv);

        if (ret < 0)
          r->throw_c([=](oss& e) { e << "select failed" ; });

        if (ret == 0) {
          fprintf(stderr, "select() timeout\n");
        }

        if (FD_ISSET( cmd_to_ur[0], &rfds )) {
          ret--;
          size_t bytes_read;

          if(r->total_read < r->buf_read.size()) {
            // FIXME: calling C read while holding a mutex. Looks safe, but
            // still suspicious.
            jlock _(r);
            bytes_read = read(cmd_to_ur[0], &r->buf_read[r->total_read], r->buf_read.size() - r->total_read);

            if(bytes_read < 0)
              r->throw_c([=](oss& e) { e << "read failed" ; });

            r->total_read += bytes_read;
          }
          else {
            blob devnull(r->buf_read.size() / 2);

            bytes_read = read(cmd_to_ur[0], &devnull[0], devnull.size());

            if(bytes_read < 0)
              r->throw_c([=](oss& e) { e << "read failed (devnull)" ; });
            else {
              jlock _(r);
              memcpy(&r->buf_read[0], &r->buf_read[bytes_read], r->buf_read.size() - bytes_read);
              memcpy(&r->buf_read[r->buf_read.size() - bytes_read], &devnull[0], bytes_read);
            }
          }

          if (bytes_read == 0) {
            UW_SYSTEM_PIPE_CLOSE_OUT(cmd_to_ur);
            break;
          }
        }

        if (FD_ISSET( ur_to_cmd[1], &wfds )) {
          ret--;

          size_t written = write(ur_to_cmd[1], &r->buf_write[r->total_written], r->buf_write.size() - r->total_written);

          if(written < 0)
            r->throw_c([=](oss& e) { e << "write failed" ; });

          r->total_written += written;

          if (r->total_written == r->buf_write.size()) {
            UW_SYSTEM_PIPE_CLOSE_IN(ur_to_cmd);
          }
        }

        if(ret > 0) {
          fprintf(stderr, "CallbackFFI BUG: select() reports unhandled state\n");
        }

      }
    }
  }
  catch(string &e) { }

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
  UW_SYSTEM_PIPE_CLOSE(ur_to_cmd);
}
/*}}}*/

typedef std::map<jkey,jptr> jobmap;

struct joblock {
  joblock() { pthread_mutex_lock(&m); }
  ~joblock() { pthread_mutex_unlock(&m); }

  jobmap& get() { return jm; }
  jobmap& operator& () { return jm; } 

private:
  static jobmap jm;
  static pthread_mutex_t m;
};

pthread_mutex_t joblock::m = PTHREAD_MUTEX_INITIALIZER;
jobmap          joblock::jm;

jptr get(uw_CallbackFFI_job j) { return *((jptr*)j); }

uw_CallbackFFI_job uw_CallbackFFI_createB(
  struct uw_context *ctx,
  uw_Basis_string cmd,
  uw_Basis_blob _stdin,
  uw_Basis_int stdout_sz,
  uw_Basis_int jr)
{
  joblock l;
  jobmap& js(l.get());
  jptr j(new job(jr,
                 cmd,
                 blob(_stdin.data, _stdin.data + _stdin.size),
                 stdout_sz));

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

uw_CallbackFFI_job uw_CallbackFFI_create(
  struct uw_context *ctx,
  uw_Basis_string cmd,
  uw_Basis_string _stdin,
  uw_Basis_int stdout_sz,
  uw_Basis_int jr)
{
  uw_Basis_blob b;
  b.data = _stdin;
  b.size = strlen(_stdin);

  return uw_CallbackFFI_createB(ctx, cmd, b, stdout_sz, jr);
}


uw_Basis_unit uw_CallbackFFI_run(
  struct uw_context *ctx,
  uw_CallbackFFI_job _j,
  uw_Basis_string _u)
{

  uw_context* ctx2 = uw_init(-1, uw_get_loggers(ctx));
  uw_set_app(ctx2, uw_get_app(ctx));
  uw_set_headers(ctx2, [](void*, const char*)->char*{return NULL;}, NULL);
  uw_set_env(ctx2, [](void*, const char*)->char*{return NULL;}, NULL);

  struct pack { string u; jptr j; uw_context *ctx; };

  uw_register_transactional(ctx, new pack {_u, get(_j), ctx2},
    [](void* data) {
      std::thread t([](pack *p){
          try {
            execute(p->j);
          }
          catch(job::exception &e) {
            fprintf(stderr,"CallbackFFI execute: %s\n", e.c_str());
          }

          uw_context *ctx =  p->ctx;
          char *path = (char*)p->u.c_str(); // FIXME C-cast
          uw_loggers *ls = uw_get_loggers(p->ctx);

          int retries_left = 5;
          failure_kind r;
          do {
            uw_reset(ctx);
            uw_set_deadline(ctx, uw_time + uw_time_max);
            r = uw_begin(ctx, path);
            if (r == BOUNDED_RETRY)
              --retries_left;
            else if (r == UNLIMITED_RETRY)
              ls->log_debug(ls->logger_data, "Error triggers unlimited retry in loopback: %s\n", uw_error_message(ctx));
            else if (r == BOUNDED_RETRY)
              ls->log_debug(ls->logger_data, "Error triggers bounded retry in loopback: %s\n", uw_error_message(ctx));
            else if (r == FATAL)
              ls->log_error(ls->logger_data, "Fatal error: %s\n", uw_error_message(ctx));
            if (r == FATAL || r == BOUNDED_RETRY || r == UNLIMITED_RETRY)
              if (uw_rollback(ctx, 0)) {
                ls->log_error(ls->logger_data, "Fatal error: rollback failed in loopback\n");
                break;
              }
          } while (r == UNLIMITED_RETRY || (r == BOUNDED_RETRY && retries_left > 0));

          if (r != FATAL && r != BOUNDED_RETRY)
            uw_commit(ctx);

          uw_free(p->ctx);
          delete p;
        }, (pack*)data);

      t.detach();
    },

    [](void *p) {
      delete (pack*)p;
    },

    [](void *p, int x) {
      printf("handler3\n");
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
    uw_CallbackFFI_job* pp2 = (uw_CallbackFFI_job*)uw_malloc(ctx, sizeof(uw_CallbackFFI_job*));
    uw_register_transactional(ctx, pp, NULL, NULL, [](void* pp, int) {delete ((jptr*)pp);});
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
  size_t sz = get(j)->total_read;
  char* str = (char*)uw_malloc(ctx, sz + 1);

  jlock _(get(j));
  memcpy(str, get(j)->buf_read.data(), sz);
  str[sz] = 0;

  return str;
}

uw_Basis_string uw_CallbackFFI_command(struct uw_context *ctx, uw_CallbackFFI_job j)
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

