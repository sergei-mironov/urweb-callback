
#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include <errno.h>
#include <urweb.h>

#include "Callback.h"

extern void mimic_request(uw_context ctx, const char* c_url);

uw_Basis_unit  uw_Callback_call (uw_context ctx, uw_Basis_string url)
{
  printf("\n\nurl: %s\n", url);

  mimic_request(ctx, url);

  return 0;
}

