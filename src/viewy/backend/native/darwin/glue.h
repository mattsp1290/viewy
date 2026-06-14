#ifndef VIEWY_NATIVE_DARWIN_GLUE_H
#define VIEWY_NATIVE_DARWIN_GLUE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct ViewyDarwinApp ViewyDarwinApp;
typedef struct ViewyDarwinWindow ViewyDarwinWindow;

typedef void (*ViewyDarwinMessageCallback)(void *userdata, const char *name,
                                           const char *id,
                                           const char *json_args);

typedef void (*ViewyDarwinMenuCallback)(void *userdata, const char *id);

typedef void (*ViewyDarwinEventCallback)(void *userdata, int32_t kind,
                                         int32_t width, int32_t height);

ViewyDarwinApp *viewy_darwin_app_create(void);
void viewy_darwin_app_destroy(ViewyDarwinApp *app);
void viewy_darwin_app_run(ViewyDarwinApp *app);
void viewy_darwin_app_stop(ViewyDarwinApp *app);
void viewy_darwin_app_dispatch(ViewyDarwinApp *app, void (*fn)(void *),
                               void *userdata);

ViewyDarwinWindow *viewy_darwin_window_create(ViewyDarwinApp *app,
                                              int32_t debug);
void viewy_darwin_window_destroy(ViewyDarwinWindow *window);
void viewy_darwin_window_set_title(ViewyDarwinWindow *window,
                                   const char *title);
void viewy_darwin_window_set_size(ViewyDarwinWindow *window, int32_t width,
                                  int32_t height, int32_t hints);
void viewy_darwin_window_set_html(ViewyDarwinWindow *window, const char *html);
void viewy_darwin_window_navigate(ViewyDarwinWindow *window, const char *url);
void viewy_darwin_window_eval(ViewyDarwinWindow *window, const char *js);
void viewy_darwin_window_init_script(ViewyDarwinWindow *window, const char *js);

int32_t viewy_darwin_set_message_handler(ViewyDarwinWindow *window,
                                         const char *handler_name,
                                         ViewyDarwinMessageCallback callback,
                                         void *userdata);
void viewy_darwin_clear_message_handler(ViewyDarwinWindow *window,
                                        const char *handler_name);
void viewy_darwin_resolve(ViewyDarwinWindow *window, const char *id,
                          int32_t ok, const char *json_result);

void viewy_darwin_set_event_callback(ViewyDarwinWindow *window,
                                     ViewyDarwinEventCallback callback,
                                     void *userdata);

int32_t viewy_darwin_set_app_menu(ViewyDarwinApp *app, const char *json_menu,
                                  ViewyDarwinMenuCallback callback,
                                  void *userdata);

int32_t viewy_darwin_tray_create(ViewyDarwinApp *app, const char *json_options,
                                 ViewyDarwinMenuCallback callback,
                                 void *userdata);
void viewy_darwin_tray_update(ViewyDarwinApp *app, const char *tray_id,
                              const char *json_options);
void viewy_darwin_tray_destroy(ViewyDarwinApp *app, const char *tray_id);

#ifdef __cplusplus
}
#endif

#endif
