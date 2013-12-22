
#include <types_cpp.h>
#include <urweb_cpp.h>

#ifdef __cplusplus
extern "C" {
#endif


typedef void* uw_Callback_job;
typedef int uw_Callback_jobref;

uw_Callback_job uw_Callback_create(
  struct uw_context *ctx,
  uw_Basis_string cmd,
  uw_Basis_string _stdin,
  uw_Basis_int stdout_sz);

uw_Basis_unit uw_Callback_run(
  struct uw_context *ctx,
  uw_Callback_job k,
  uw_Basis_string _url);

uw_Callback_job uw_Callback_deref(struct uw_context *ctx, uw_Callback_jobref jr);
uw_Callback_job* uw_Callback_tryDeref(struct uw_context *ctx, uw_Callback_jobref jr);
uw_Callback_jobref uw_Callback_ref(struct uw_context *ctx, uw_Callback_job j);

uw_Basis_int uw_Callback_pid(struct uw_context *ctx, uw_Callback_job t);
uw_Basis_int uw_Callback_exitcode(struct uw_context *ctx, uw_Callback_job t);
uw_Basis_string uw_Callback_stdout(struct uw_context *ctx, uw_Callback_job t);
uw_Basis_unit uw_Callback_cleanup(struct uw_context *ctx, uw_Callback_job t);
uw_Basis_string uw_Callback_errors(struct uw_context *ctx, uw_Callback_job t);

#ifdef __cplusplus
} // extern "C"
#endif
