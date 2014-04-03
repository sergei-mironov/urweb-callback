
#include <types_cpp.h>
#include <urweb_cpp.h>

#ifdef __cplusplus
extern "C" {
#endif


/* A pointer to the _real_ pointer which keeps the ref counting. Full
 * specification would be
 *
 * typedef shared_ptr<job>* uw_CallbackFFI_job
 *
 */
typedef void* uw_CallbackFFI_job;

typedef int uw_CallbackFFI_jobref;

uw_Basis_unit uw_CallbackFFI_initialize(
  struct uw_context *ctx,
  uw_Basis_int nthread);

uw_CallbackFFI_job uw_CallbackFFI_create(
  struct uw_context *ctx,
  uw_Basis_string cmd,
  uw_Basis_int stdout_sz,
  uw_Basis_int jobref);

uw_Basis_unit uw_CallbackFFI_setCompletionCB(struct uw_context *ctx, uw_CallbackFFI_job j, uw_Basis_string mburl);
uw_Basis_unit uw_CallbackFFI_setNotifyCB(struct uw_context *ctx, uw_CallbackFFI_job j, uw_Basis_string mburl);
uw_Basis_unit uw_CallbackFFI_pushStdin(struct uw_context *ctx, uw_CallbackFFI_job j, uw_Basis_blob _stdin, uw_Basis_int maxsz);
uw_Basis_unit uw_CallbackFFI_pushStdinEOF(struct uw_context *ctx, uw_CallbackFFI_job j);

uw_Basis_unit uw_CallbackFFI_run(
  struct uw_context *ctx,
  uw_CallbackFFI_job k);

uw_Basis_int uw_CallbackFFI_nactive(struct uw_context *ctx, uw_Basis_unit u);

uw_CallbackFFI_job uw_CallbackFFI_deref(struct uw_context *ctx, uw_CallbackFFI_jobref jr);
uw_CallbackFFI_job* uw_CallbackFFI_tryDeref(struct uw_context *ctx, uw_CallbackFFI_jobref jr);
uw_CallbackFFI_jobref uw_CallbackFFI_ref(struct uw_context *ctx, uw_CallbackFFI_job j);

uw_Basis_int uw_CallbackFFI_pid(struct uw_context *ctx, uw_CallbackFFI_job j);
uw_Basis_int uw_CallbackFFI_exitcode(struct uw_context *ctx, uw_CallbackFFI_job j);
uw_Basis_string uw_CallbackFFI_stdout(struct uw_context *ctx, uw_CallbackFFI_job j);
uw_Basis_string uw_CallbackFFI_cmd(struct uw_context *ctx, uw_CallbackFFI_job j);
uw_Basis_unit uw_CallbackFFI_cleanup(struct uw_context *ctx, uw_CallbackFFI_job j);
uw_Basis_string uw_CallbackFFI_errors(struct uw_context *ctx, uw_CallbackFFI_job j);

uw_Basis_string uw_CallbackFFI_lastLine(struct uw_context *ctx, uw_Basis_string s);

uw_Basis_unit uw_CallbackFFI_forceBoundedRetry(struct uw_context *ctx, uw_Basis_string msg);

uw_CallbackFFI_job uw_CallbackFFI_runNow(
  struct uw_context *ctx,
  uw_Basis_string cmd,
  uw_Basis_int stdout_sz,
  uw_Basis_blob _stdin,
  uw_Basis_int jobref);

#ifdef __cplusplus
} // extern "C"
#endif
