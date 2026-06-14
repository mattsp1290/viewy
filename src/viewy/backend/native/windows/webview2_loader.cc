#define WEBVIEW_EDGE 1
#define WEBVIEW_MSWEBVIEW2_BUILTIN_IMPL 1
#define WEBVIEW_MSWEBVIEW2_EXPLICIT_LINK 1
#define WEBVIEW_STATIC 1

#include "webview.h"
#include "webview2_loader.h"

extern "C" HRESULT viewy_webview2_create_environment_with_options(
    PCWSTR browserExecutableFolder, PCWSTR userDataFolder,
    ICoreWebView2EnvironmentOptions *environmentOptions,
    ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler
        *environmentCreatedHandler) {
  static const webview::detail::mswebview2::loader loader;
  return loader.create_environment_with_options(
      browserExecutableFolder, userDataFolder, environmentOptions,
      environmentCreatedHandler);
}
