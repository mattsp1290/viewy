#pragma once

/* WebView2.h includes "EventToken.h". Some MinGW-w64 SDKs provide the
   Windows SDK header as lowercase <eventtoken.h> on case-sensitive filesystems.
   Current hosted Windows images expose an eventtoken.h that does not make the
   WinRT token type visible to this vendored WebView2 header, so keep this shim
   self-contained. */
#include <eventtoken.h>

#ifndef EventRegistrationToken
typedef struct EventRegistrationToken {
  __int64 value;
} EventRegistrationToken;
#endif
