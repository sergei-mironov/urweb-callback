
extern "C" {
#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include <errno.h>
#include <sys/time.h>
#include <sys/types.h>
#include <sys/wait.h>

#include <urweb_cpp.h>
#include <srvthread.h>
#include "Callback.h"
}

#include <map>
#include <string>
#include <memory>
#include <sstream>
#include <vector>

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
typedef long int jkey;

struct job {
  job(jkey _key, const string &_cmd, const blob &_buf_write, int _bufsize) :
		key(_key), cmd(_cmd), buf_write(_buf_write) {
    buf_read.resize(_bufsize);
  }

  jkey key;

  int pid = -1;
  int exitcode = -1;

  size_t total_read = 0;
  size_t total_written = 0;

  blob buf_read;
  blob buf_write;

  oss err;

  string cmd;

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

static void execute(jptr r)/*{{{*/
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

        if (FD_ISSET( cmd_to_ur[0], &rfds )) {
          ret--;
          size_t bytes_read;

          if(r->total_read < r->buf_read.size()) {
            bytes_read = read(cmd_to_ur[0], &r->buf_read[r->total_read], r->buf_read.size() - r->total_read);

            if(bytes_read < 0)
              r->throw_c([=](oss& e) { e << "read failed" ; });

            r->total_read += bytes_read;
          }
          else {
            static blob devnull(1024);

            bytes_read = read(cmd_to_ur[0], &devnull[0], devnull.size());

            if(bytes_read < 0)
              r->throw_c([=](oss& e) { e << "read failed (devnull)" ; });
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
          fprintf(stderr, "Callback BUG: select() reports unhandled state\n");
        }
        else {
          fprintf(stderr, "select() timeout\n");
        }

      }
    }
  }
  catch(string &e) { }

  if (r->pid != -1) {
    int status;
    int rc = waitpid(r->pid, &status, 0);
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
  int nextkey() { return keys++; };

private:
  static int keys;
  static jobmap jm;
  static pthread_mutex_t m;
};

pthread_mutex_t joblock::m = PTHREAD_MUTEX_INITIALIZER;
jobmap          joblock::jm;
int             joblock::keys = 0;

uw_Callback_jobref uw_Callback_create(
  struct uw_context *ctx,
  uw_Basis_string cmd,
  uw_Basis_string _stdin,
  uw_Basis_int stdout_sz)
{
  joblock l;
  jobmap& js(l.get());
  jptr j(new job(l.nextkey(),
                 cmd,
                 blob(_stdin, _stdin+strlen(_stdin)),
                 stdout_sz));

  js.insert(js.end(), jobmap::value_type(j->key, j));
  return j->key;
}

uw_Basis_unit uw_Callback_run(
  struct uw_context *ctx,
  uw_Callback_jobref k,
  uw_Basis_string _url)
{
  struct pack {
    string url;
    int key;
  };

  uw_register_transactional(ctx, new pack {_url, k},
      [](void* data) -> void {
        st_create(
          [](void* data) -> void* {
            pack *p = (pack*)data;

            try {

              jptr j;

              {
                joblock l;
                jobmap& js(l.get());

                auto i = js.find(p->key);
                if (i==js.end())
                  throw job::exception("job not found");
                j = i->second;
              };

              execute(j);

              st_loopback_enqueue(p->url.c_str());
            }
            catch(job::exception &e) {
              fprintf(stderr,"Callback execute: %s\n", e.c_str());
            }

            delete p;
            return NULL;
          }, data);

        return;
      }, NULL, NULL);

  return 0;
}

jptr* safe_find_job(struct uw_context *ctx, uw_Callback_jobref k)
{
  jptr* pp = new jptr();
  uw_push_cleanup(ctx, [](void* pp){ delete ((jptr*)pp);}, pp);

  joblock l;
  jobmap& js(l.get());

  jobmap::iterator j = js.find(k);
  if (j == js.end())
    return NULL;
  *pp = j->second;
  return pp;
}

uw_Basis_unit uw_Callback_cleanup(struct uw_context *ctx, uw_Callback_jobref k)
{
  joblock l;
  jobmap &js(l.get());

  auto j = js.find((uw_Callback_jobref)k);
  if (j != js.end()) {
    js.erase(j);
  }
}

uw_Basis_int uw_Callback_exitcode(struct uw_context *ctx, uw_Callback_jobref k)
{
  jptr *p = safe_find_job(ctx, k);
  if(!p)
    return -1;

  return (*p)->exitcode;
}

uw_Basis_int uw_Callback_pid(struct uw_context *ctx, uw_Callback_jobref k)
{
  jptr *p = safe_find_job(ctx, k);
  if(!p)
    return -1;

  return (*p)->pid;
}

uw_Basis_string uw_Callback_stdout(struct uw_context *ctx, uw_Callback_jobref k)
{
  jptr *p = safe_find_job(ctx, k);
  if(!p) {
    char* null = (char*)uw_malloc(ctx, 1);
    null[0] = 0;
    return null;
  }

  jptr &j = *p;
  size_t sz = j->total_read;
  char* str = (char*)uw_malloc(ctx, sz + 1);
  memcpy(str, j->buf_read.data(), sz);
  str[sz] = 0;
  return str;
}

uw_Basis_string uw_Callback_errors(struct uw_context *ctx, uw_Callback_jobref k)
{
  char* null = (char*)uw_malloc(ctx, 1);
  null[0] = 0;

  jptr *p = safe_find_job(ctx, k);
  if(!p) {
    return null;
  }

  jptr &j = *p;

  // FIXME: not thread-safe!!
  size_t sz = j->err.str().length();
  char* str = (char*)uw_malloc(ctx, sz + 1);
  memcpy(str, j->err.str().c_str(), sz);
  str[sz] = 0;
  return str;
}

