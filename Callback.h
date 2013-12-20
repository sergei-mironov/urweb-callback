
#include <types_cpp.h>
#include <urweb_cpp.h>

#ifdef __cplusplus
extern "C" {
#endif


struct job;

typedef int uw_Callback_jobref;

uw_Callback_jobref uw_Callback_create(
  struct uw_context *ctx,
  uw_Basis_string cmd,
  uw_Basis_string _stdin,
  uw_Basis_int stdout_sz);

uw_Basis_unit uw_Callback_run(
  struct uw_context *ctx,
  uw_Callback_jobref k,
  uw_Basis_string _url);

uw_Basis_int uw_Callback_pid(struct uw_context *ctx, uw_Callback_jobref t);
uw_Basis_int uw_Callback_exitcode(struct uw_context *ctx, uw_Callback_jobref t);
uw_Basis_string uw_Callback_stdout(struct uw_context *ctx, uw_Callback_jobref t);
uw_Basis_unit uw_Callback_cleanup(struct uw_context *ctx, uw_Callback_jobref t);
uw_Basis_string uw_Callback_errors(struct uw_context *ctx, uw_Callback_jobref t);

#ifdef __cplusplus
} // extern "C"
#endif
