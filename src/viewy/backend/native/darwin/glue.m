#import "glue.h"

#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

@interface ViewyDarwinAppBox : NSObject
@property(nonatomic, assign) ViewyDarwinMenuCallback menuCallback;
@property(nonatomic, assign) void *menuUserdata;
@property(nonatomic, assign) ViewyDarwinMenuCallback trayCallback;
@property(nonatomic, assign) void *trayUserdata;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSStatusItem *> *statusItems;
@end

@implementation ViewyDarwinAppBox

- (instancetype)init {
  self = [super init];
  if (self) {
    _statusItems = [NSMutableDictionary dictionary];
  }
  return self;
}

@end

@interface ViewyDarwinMenuTarget : NSObject
@property(nonatomic, copy) NSString *itemId;
@property(nonatomic, assign) ViewyDarwinMenuCallback callback;
@property(nonatomic, assign) void *userdata;
- (void)activate:(id)sender;
@end

@implementation ViewyDarwinMenuTarget

- (void)activate:(id)sender {
  (void)sender;
  if (self.callback) {
    self.callback(self.userdata, self.itemId.UTF8String);
  }
}

@end

@interface ViewyDarwinWindowBox : NSObject <WKScriptMessageHandler,
                                            NSWindowDelegate>
@property(nonatomic, strong) NSWindow *window;
@property(nonatomic, strong) WKWebView *webView;
@property(nonatomic, strong) NSMutableSet<NSString *> *handlerNames;
@property(nonatomic, assign) ViewyDarwinMessageCallback messageCallback;
@property(nonatomic, assign) void *messageUserdata;
@property(nonatomic, assign) ViewyDarwinEventCallback eventCallback;
@property(nonatomic, assign) void *eventUserdata;
@end

@implementation ViewyDarwinWindowBox

- (instancetype)init {
  self = [super init];
  if (self) {
    _handlerNames = [NSMutableSet set];
  }
  return self;
}

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

static id ViewyJson(const char *value) {
  NSData *data = [ViewyString(value) dataUsingEncoding:NSUTF8StringEncoding];
  if (!data) {
    return nil;
  }
  return [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
}

static NSString *ViewyDictString(NSDictionary *dict, NSString *key) {
  id value = dict[key];
  return [value isKindOfClass:[NSString class]] ? value : @"";
}

static BOOL ViewyDictBool(NSDictionary *dict, NSString *key, BOOL fallback) {
  id value = dict[key];
  return [value respondsToSelector:@selector(boolValue)] ? [value boolValue]
                                                         : fallback;
}

static NSInteger ViewyMenuKind(NSDictionary *dict) {
  id value = dict[@"kind"];
  if ([value respondsToSelector:@selector(integerValue)]) {
    return [value integerValue];
  }
  if (![value isKindOfClass:[NSString class]]) {
    return 0;
  }
  NSString *kind = (NSString *)value;
  if ([kind isEqualToString:@"separator"]) {
    return 1;
  }
  if ([kind isEqualToString:@"submenu"]) {
    return 2;
  }
  if ([kind isEqualToString:@"checkbox"]) {
    return 3;
  }
  if ([kind isEqualToString:@"radio"]) {
    return 4;
  }
  return 0;
}

static NSMenu *ViewyBuildMenu(NSArray *items, ViewyDarwinMenuCallback callback,
                              void *userdata,
                              NSMutableArray<ViewyDarwinMenuTarget *> *targets);

static NSMenuItem *ViewyBuildMenuItem(NSDictionary *dict,
                                      ViewyDarwinMenuCallback callback,
                                      void *userdata,
                                      NSMutableArray<ViewyDarwinMenuTarget *> *targets) {
  NSInteger kind = ViewyMenuKind(dict);
  if (kind == 1) {
    return [NSMenuItem separatorItem];
  }

  NSString *label = ViewyDictString(dict, @"label");
  NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:label
                                                action:nil
                                         keyEquivalent:@""];
  item.enabled = ViewyDictBool(dict, @"enabled", YES);

  if (kind == 2) {
    id children = dict[@"children"];
    if ([children isKindOfClass:[NSArray class]]) {
      item.submenu = ViewyBuildMenu(children, callback, userdata, targets);
    }
    return item;
  }

  NSString *itemId = ViewyDictString(dict, @"id");
  if (itemId.length > 0 && callback) {
    ViewyDarwinMenuTarget *target = [ViewyDarwinMenuTarget new];
    target.itemId = itemId;
    target.callback = callback;
    target.userdata = userdata;
    item.target = target;
    item.action = @selector(activate:);
    item.representedObject = target;
    [targets addObject:target];
  }
  if (kind == 3 || kind == 4) {
    item.state = ViewyDictBool(dict, @"checked", NO) ? NSControlStateValueOn
                                                     : NSControlStateValueOff;
  }
  return item;
}

static NSMenu *ViewyBuildMenu(NSArray *items, ViewyDarwinMenuCallback callback,
                              void *userdata,
                              NSMutableArray<ViewyDarwinMenuTarget *> *targets) {
  NSMenu *menu = [NSMenu new];
  for (id raw in items) {
    if (![raw isKindOfClass:[NSDictionary class]]) {
      continue;
    }
    [menu addItem:ViewyBuildMenuItem(raw, callback, userdata, targets)];
  }
  return menu;
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
    WKUserContentController *controller =
        window->box.webView.configuration.userContentController;
    for (NSString *handler in window->box.handlerNames) {
      [controller removeScriptMessageHandlerForName:handler];
    }
    [window->box.handlerNames removeAllObjects];
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
  if ([window->box.handlerNames containsObject:handler]) {
    return 0;
  }
  window->box.messageCallback = callback;
  window->box.messageUserdata = userdata;
  [window->box.webView.configuration.userContentController
      addScriptMessageHandler:window->box
                         name:handler];
  [window->box.handlerNames addObject:handler];
  return 1;
}

void viewy_darwin_clear_message_handler(ViewyDarwinWindow *window,
                                        const char *handler_name) {
  if (!window || !handler_name) {
    return;
  }
  NSString *handler = ViewyString(handler_name);
  if (![window->box.handlerNames containsObject:handler]) {
    return;
  }
  [window->box.webView.configuration.userContentController
      removeScriptMessageHandlerForName:handler];
  [window->box.handlerNames removeObject:handler];
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

int32_t viewy_darwin_set_app_menu(ViewyDarwinApp *app, const char *json_menu,
                                  ViewyDarwinMenuCallback callback,
                                  void *userdata) {
  if (!app) {
    return 0;
  }
  id raw = ViewyJson(json_menu);
  if (![raw isKindOfClass:[NSArray class]]) {
    return 0;
  }
  NSMutableArray<ViewyDarwinMenuTarget *> *targets = [NSMutableArray array];
  NSMenu *menu = ViewyBuildMenu(raw, callback, userdata, targets);
  app->box.menuCallback = callback;
  app->box.menuUserdata = userdata;
  [NSApplication sharedApplication].mainMenu = menu;
  return 1;
}

int32_t viewy_darwin_tray_create(ViewyDarwinApp *app, const char *json_options,
                                 ViewyDarwinMenuCallback callback,
                                 void *userdata) {
  if (!app) {
    return 0;
  }
  id raw = ViewyJson(json_options);
  if (![raw isKindOfClass:[NSDictionary class]]) {
    return 0;
  }
  NSDictionary *options = (NSDictionary *)raw;
  NSString *itemId = ViewyDictString(options, @"id");
  if (itemId.length == 0 || app->box.statusItems[itemId]) {
    return 0;
  }

  NSStatusItem *item = [[NSStatusBar systemStatusBar]
      statusItemWithLength:NSVariableStatusItemLength];
  NSString *tooltip = ViewyDictString(options, @"tooltip");
  item.button.toolTip = tooltip;
  item.button.title = tooltip.length > 0 ? tooltip : itemId;

  NSString *iconPath = ViewyDictString(options, @"iconPath");
  NSString *templateIconPath = ViewyDictString(options, @"templateIconPath");
  NSString *selectedIconPath = templateIconPath.length > 0 ? templateIconPath : iconPath;
  if (selectedIconPath.length > 0) {
    NSImage *image = [[NSImage alloc] initWithContentsOfFile:selectedIconPath];
    image.template = templateIconPath.length > 0;
    item.button.image = image;
    item.button.title = @"";
  }

  id menuItems = options[@"menu"];
  if ([menuItems isKindOfClass:[NSArray class]]) {
    NSMutableArray<ViewyDarwinMenuTarget *> *targets = [NSMutableArray array];
    item.menu = ViewyBuildMenu(menuItems, callback, userdata, targets);
  }
  app->box.statusItems[itemId] = item;
  app->box.trayCallback = callback;
  app->box.trayUserdata = userdata;
  return 1;
}

void viewy_darwin_tray_update(ViewyDarwinApp *app, const char *tray_id,
                              const char *json_options) {
  if (!app || !tray_id) {
    return;
  }
  NSString *itemId = ViewyString(tray_id);
  NSStatusItem *item = app->box.statusItems[itemId];
  if (!item) {
    return;
  }
  id raw = ViewyJson(json_options);
  if (![raw isKindOfClass:[NSDictionary class]]) {
    return;
  }
  NSDictionary *options = (NSDictionary *)raw;
  NSString *tooltip = ViewyDictString(options, @"tooltip");
  if (tooltip.length > 0) {
    item.button.toolTip = tooltip;
    if (!item.button.image) {
      item.button.title = tooltip;
    }
  }
  id menuItems = options[@"menu"];
  if ([menuItems isKindOfClass:[NSArray class]]) {
    NSMutableArray<ViewyDarwinMenuTarget *> *targets = [NSMutableArray array];
    item.menu = ViewyBuildMenu(menuItems, app->box.trayCallback,
                               app->box.trayUserdata, targets);
  }
}

void viewy_darwin_tray_destroy(ViewyDarwinApp *app, const char *tray_id) {
  if (!app || !tray_id) {
    return;
  }
  NSString *itemId = ViewyString(tray_id);
  NSStatusItem *item = app->box.statusItems[itemId];
  if (!item) {
    return;
  }
  [[NSStatusBar systemStatusBar] removeStatusItem:item];
  [app->box.statusItems removeObjectForKey:itemId];
}
