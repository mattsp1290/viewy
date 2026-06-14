#pragma once

#include <windows.h>
#include <WebView2.h>

#ifdef __cplusplus
extern "C" {
#endif

HRESULT viewy_webview2_create_environment_with_options(
    PCWSTR browserExecutableFolder,
    PCWSTR userDataFolder,
    ICoreWebView2EnvironmentOptions *environmentOptions,
    ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler
        *environmentCreatedHandler);

#ifdef __cplusplus
}
#endif
