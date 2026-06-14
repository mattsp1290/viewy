#import "glue.h"

#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

@interface ViewyDarwinAppBox : NSObject
@end

@implementation ViewyDarwinAppBox
@end

@interface ViewyDarwinWindowBox : NSObject <WKScriptMessageHandler,
                                            NSWindowDelegate>
@property(nonatomic, strong) NSWindow *window;
@property(nonatomic, strong) WKWebView *webView;
@property(nonatomic, assign) ViewyDarwinMessageCallback messageCallback;
@property(nonatomic, assign) void *messageUserdata;
@property(nonatomic, assign) ViewyDarwinEventCallback eventCallback;
@property(nonatomic, assign) void *eventUserdata;
@end

@implementation ViewyDarwinWindowBox

- (void)userContentController:(WKUserContentController *)userContentController
      didReceiveScriptMessage:(WKScriptMessage *)message {
  (void)userContentController;
  if (!self.messageCallback || ![message.body isKindOfClass:[NSDictionary class]]) {
    return;
  }

  NSDictionary *body = (NSDictionary *)message.body;
  NSString *name = [body[@"name"] isKindOfClass:[NSString class]] ? body[@"name"] : @"";
  NSString *callId = [body[@"id"] isKindOfClass:[NSString class]] ? body[@"id"] : @"";
  NSString *args = [body[@"args"] isKindOfClass:[NSString class]] ? body[@"args"] : @"[]";
  self.messageCallback(self.messageUserdata, name.UTF8String, callId.UTF8String,
                       args.UTF8String);
}

- (void)windowWillClose:(NSNotification *)notification {
  (void)notification;
  if (self.eventCallback) {
    self.eventCallback(self.eventUserdata, 0, 0, 0);
  }
}

- (void)windowDidBecomeKey:(NSNotification *)notification {
  (void)notification;
  if (self.eventCallback) {
    self.eventCallback(self.eventUserdata, 1, 0, 0);
  }
}

- (void)windowDidResignKey:(NSNotification *)notification {
  (void)notification;
  if (self.eventCallback) {
    self.eventCallback(self.eventUserdata, 2, 0, 0);
  }
}

- (void)windowDidResize:(NSNotification *)notification {
  (void)notification;
  if (!self.eventCallback) {
    return;
  }
  NSRect frame = self.window.contentView.bounds;
  self.eventCallback(self.eventUserdata, 3, (int32_t)frame.size.width,
                     (int32_t)frame.size.height);
}

@end

struct ViewyDarwinApp {
  ViewyDarwinAppBox *box;
};

struct ViewyDarwinWindow {
  ViewyDarwinWindowBox *box;
};

static NSString *ViewyString(const char *value) {
  if (!value) {
    return @"";
  }
  return [NSString stringWithUTF8String:value] ?: @"";
}

static NSString *ViewyJsonString(NSString *value) {
  NSData *data = [NSJSONSerialization dataWithJSONObject:@[ value ?: @"" ]
                                                 options:0
                                                   error:nil];
  if (!data) {
    return @"\"\"";
  }
  NSString *array = [[NSString alloc] initWithData:data
                                          encoding:NSUTF8StringEncoding];
  if (array.length < 2) {
    return @"\"\"";
  }
  return [array substringWithRange:NSMakeRange(1, array.length - 2)];
}

static void ViewyEnsureApp(void) {
  NSApplication *app = [NSApplication sharedApplication];
  [app setActivationPolicy:NSApplicationActivationPolicyRegular];
}

ViewyDarwinApp *viewy_darwin_app_create(void) {
  @autoreleasepool {
    ViewyEnsureApp();
    ViewyDarwinApp *app =
        (ViewyDarwinApp *)calloc(1, sizeof(ViewyDarwinApp));
    if (!app) {
      return NULL;
    }
    app->box = [ViewyDarwinAppBox new];
    return app;
  }
}

void viewy_darwin_app_destroy(ViewyDarwinApp *app) {
  if (!app) {
    return;
  }
  @autoreleasepool {
    app->box = nil;
    free(app);
  }
}

void viewy_darwin_app_run(ViewyDarwinApp *app) {
  (void)app;
  @autoreleasepool {
    ViewyEnsureApp();
    [[NSApplication sharedApplication] run];
  }
}

void viewy_darwin_app_stop(ViewyDarwinApp *app) {
  (void)app;
  dispatch_async(dispatch_get_main_queue(), ^{
    [[NSApplication sharedApplication] stop:nil];
  });
}

void viewy_darwin_app_dispatch(ViewyDarwinApp *app, void (*fn)(void *),
                               void *userdata) {
  (void)app;
  if (!fn) {
    return;
  }
  dispatch_async(dispatch_get_main_queue(), ^{
    fn(userdata);
  });
}

ViewyDarwinWindow *viewy_darwin_window_create(ViewyDarwinApp *app,
                                              int32_t debug) {
  (void)app;
  @autoreleasepool {
    ViewyEnsureApp();
    ViewyDarwinWindow *window =
        (ViewyDarwinWindow *)calloc(1, sizeof(ViewyDarwinWindow));
    if (!window) {
      return NULL;
    }

    ViewyDarwinWindowBox *box = [ViewyDarwinWindowBox new];
    WKWebViewConfiguration *config = [WKWebViewConfiguration new];
    WKUserContentController *controller = [WKUserContentController new];
    config.userContentController = controller;

    if (debug) {
      if (@available(macOS 13.3, *)) {
        [config.preferences setValue:@YES forKey:@"developerExtrasEnabled"];
      }
    }

    NSRect frame = NSMakeRect(0, 0, 800, 600);
    NSUInteger style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                       NSWindowStyleMaskMiniaturizable |
                       NSWindowStyleMaskResizable;
    box.window = [[NSWindow alloc] initWithContentRect:frame
                                             styleMask:style
                                               backing:NSBackingStoreBuffered
                                                 defer:NO];
    box.webView = [[WKWebView alloc] initWithFrame:frame configuration:config];
    box.window.contentView = box.webView;
    box.window.delegate = box;
    [box.window center];
    [box.window makeKeyAndOrderFront:nil];

    window->box = box;
    return window;
  }
}

void viewy_darwin_window_destroy(ViewyDarwinWindow *window) {
  if (!window) {
    return;
  }
  @autoreleasepool {
    [window->box.webView.configuration.userContentController
        removeAllUserScripts];
    window->box.window.delegate = nil;
    [window->box.window close];
    window->box = nil;
    free(window);
  }
}

void viewy_darwin_window_set_title(ViewyDarwinWindow *window,
                                   const char *title) {
  if (!window) {
    return;
  }
  window->box.window.title = ViewyString(title);
}

void viewy_darwin_window_set_size(ViewyDarwinWindow *window, int32_t width,
                                  int32_t height, int32_t hints) {
  (void)hints;
  if (!window) {
    return;
  }
  NSRect frame = window->box.window.frame;
  frame.size = NSMakeSize(width, height);
  [window->box.window setFrame:frame display:YES];
}

void viewy_darwin_window_set_html(ViewyDarwinWindow *window, const char *html) {
  if (!window) {
    return;
  }
  [window->box.webView loadHTMLString:ViewyString(html) baseURL:nil];
}

void viewy_darwin_window_navigate(ViewyDarwinWindow *window, const char *url) {
  if (!window) {
    return;
  }
  NSURL *nsurl = [NSURL URLWithString:ViewyString(url)];
  if (nsurl) {
    [window->box.webView loadRequest:[NSURLRequest requestWithURL:nsurl]];
  }
}

void viewy_darwin_window_eval(ViewyDarwinWindow *window, const char *js) {
  if (!window) {
    return;
  }
  [window->box.webView evaluateJavaScript:ViewyString(js)
                        completionHandler:nil];
}

void viewy_darwin_window_init_script(ViewyDarwinWindow *window, const char *js) {
  if (!window) {
    return;
  }
  WKUserScript *script = [[WKUserScript alloc]
        initWithSource:ViewyString(js)
         injectionTime:WKUserScriptInjectionTimeAtDocumentStart
      forMainFrameOnly:YES];
  [window->box.webView.configuration.userContentController addUserScript:script];
}

int32_t viewy_darwin_set_message_handler(ViewyDarwinWindow *window,
                                         const char *handler_name,
                                         ViewyDarwinMessageCallback callback,
                                         void *userdata) {
  if (!window || !handler_name || !callback) {
    return 0;
  }
  NSString *handler = ViewyString(handler_name);
  window->box.messageCallback = callback;
  window->box.messageUserdata = userdata;
  [window->box.webView.configuration.userContentController
      addScriptMessageHandler:window->box
                         name:handler];
  return 1;
}

void viewy_darwin_clear_message_handler(ViewyDarwinWindow *window,
                                        const char *handler_name) {
  if (!window || !handler_name) {
    return;
  }
  [window->box.webView.configuration.userContentController
      removeScriptMessageHandlerForName:ViewyString(handler_name)];
  window->box.messageCallback = NULL;
  window->box.messageUserdata = NULL;
}

void viewy_darwin_resolve(ViewyDarwinWindow *window, const char *id, int32_t ok,
                          const char *json_result) {
  if (!window) {
    return;
  }
  NSString *escapedId = ViewyJsonString(ViewyString(id));
  NSString *escapedJson = ViewyJsonString(ViewyString(json_result));
  NSString *script = [NSString
      stringWithFormat:
          @"if(window.__viewy&&window.__viewy._resolve)window.__viewy._resolve(%@,%@,%@);",
          escapedId, ok ? @"true" : @"false", escapedJson];
  [window->box.webView evaluateJavaScript:script completionHandler:nil];
}

void viewy_darwin_set_event_callback(ViewyDarwinWindow *window,
                                     ViewyDarwinEventCallback callback,
                                     void *userdata) {
  if (!window) {
    return;
  }
  window->box.eventCallback = callback;
  window->box.eventUserdata = userdata;
}

void viewy_darwin_set_app_menu(ViewyDarwinApp *app, const char *json_menu,
                               ViewyDarwinMenuCallback callback,
                               void *userdata) {
  (void)app;
  (void)json_menu;
  (void)callback;
  (void)userdata;
}

int32_t viewy_darwin_tray_create(ViewyDarwinApp *app, const char *json_options,
                                 ViewyDarwinMenuCallback callback,
                                 void *userdata) {
  (void)app;
  (void)json_options;
  (void)callback;
  (void)userdata;
  return 0;
}

void viewy_darwin_tray_update(ViewyDarwinApp *app, const char *id,
                              const char *json_options) {
  (void)app;
  (void)id;
  (void)json_options;
}

void viewy_darwin_tray_destroy(ViewyDarwinApp *app, const char *id) {
  (void)app;
  (void)id;
}
