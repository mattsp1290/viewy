#import "glue.h"

#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

static const NSUInteger ViewyMaxSchemeBodyBytes = 10 * 1024 * 1024;

@class ViewyDarwinMenuTarget;

@interface ViewyDarwinAppBox : NSObject
@property(nonatomic, assign) ViewyDarwinMenuCallback menuCallback;
@property(nonatomic, assign) void *menuUserdata;
@property(nonatomic, strong) NSMenu *mainMenu;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSStatusItem *> *statusItems;
@property(nonatomic, strong) NSMutableDictionary<NSString *, ViewyDarwinMenuTarget *> *statusTargets;
@end

@implementation ViewyDarwinAppBox

- (instancetype)init {
  self = [super init];
  if (self) {
    _statusItems = [NSMutableDictionary dictionary];
    _statusTargets = [NSMutableDictionary dictionary];
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

@class ViewyDarwinSchemeHandler;

@interface ViewyDarwinSchemeRequest : NSObject
@property(nonatomic, strong) id<WKURLSchemeTask> task;
@property(nonatomic, strong) ViewyDarwinSchemeHandler *handler;
@end

@implementation ViewyDarwinSchemeRequest
@end

@interface ViewyDarwinSchemeHandler : NSObject <WKURLSchemeHandler>
@property(nonatomic, assign) ViewyDarwinSchemeCallback callback;
@property(nonatomic, assign) void *userdata;
@property(nonatomic, strong) NSHashTable<id<WKURLSchemeTask>> *activeTasks;
@end

@implementation ViewyDarwinSchemeHandler

- (instancetype)init {
  self = [super init];
  if (self) {
    _activeTasks = [NSHashTable weakObjectsHashTable];
  }
  return self;
}

- (void)webView:(WKWebView *)webView
    startURLSchemeTask:(id<WKURLSchemeTask>)urlSchemeTask {
  (void)webView;
  [self.activeTasks addObject:urlSchemeTask];
  ViewyDarwinSchemeRequest *schemeRequest = [ViewyDarwinSchemeRequest new];
  schemeRequest.task = urlSchemeTask;
  schemeRequest.handler = self;
  if (!self.callback) {
    viewy_darwin_scheme_finish((__bridge_retained void *)schemeRequest, 404,
                               "Not Found",
                               "text/plain; charset=utf-8", "[]",
                               (const uint8_t *)"not found", 9);
    return;
  }

  NSURLRequest *request = urlSchemeTask.request;
  NSURL *url = request.URL;
  NSURLComponents *components =
      url ? [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO]
          : nil;
  NSString *scheme = url.scheme ?: @"";
  NSString *method = request.HTTPMethod ?: @"GET";
  NSString *path = components.path.length > 0 ? components.path : @"/";
  NSString *query = components.query ?: @"";

  NSMutableArray<NSDictionary *> *headers = [NSMutableArray array];
  [request.allHTTPHeaderFields
      enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value,
                                           BOOL *stop) {
        (void)stop;
        [headers addObject:@{
          @"name" : key ?: @"",
          @"value" : value ?: @""
        }];
      }];
  NSData *headersData = [NSJSONSerialization dataWithJSONObject:headers
                                                        options:0
                                                          error:nil];
  NSString *headersJson =
      headersData ? [[NSString alloc] initWithData:headersData
                                          encoding:NSUTF8StringEncoding]
                  : @"[]";

  NSData *body = request.HTTPBody;
  if (!body && request.HTTPBodyStream) {
    NSMutableData *streamBody = [NSMutableData data];
    uint8_t buffer[4096];
    [request.HTTPBodyStream open];
    while (true) {
      NSInteger count =
          [request.HTTPBodyStream read:buffer maxLength:sizeof(buffer)];
      if (count < 0) {
        [request.HTTPBodyStream close];
        viewy_darwin_scheme_finish((__bridge_retained void *)schemeRequest, 500,
                                   "Internal Server Error",
                                   "text/plain; charset=utf-8", "[]",
                                   (const uint8_t *)"internal server error", 21);
        return;
      }
      if (count == 0) {
        break;
      }
      if (streamBody.length + (NSUInteger)count > ViewyMaxSchemeBodyBytes) {
        [request.HTTPBodyStream close];
        viewy_darwin_scheme_finish((__bridge_retained void *)schemeRequest, 413,
                                   "Payload Too Large",
                                   "text/plain; charset=utf-8", "[]",
                                   (const uint8_t *)"payload too large", 17);
        return;
      }
      [streamBody appendBytes:buffer length:(NSUInteger)count];
    }
    [request.HTTPBodyStream close];
    body = streamBody;
  } else if (body.length > ViewyMaxSchemeBodyBytes) {
    viewy_darwin_scheme_finish((__bridge_retained void *)schemeRequest, 413,
                               "Payload Too Large",
                               "text/plain; charset=utf-8", "[]",
                               (const uint8_t *)"payload too large", 17);
    return;
  }

  self.callback(self.userdata, (__bridge_retained void *)schemeRequest,
                scheme.UTF8String, method.UTF8String, path.UTF8String,
                query.UTF8String, headersJson.UTF8String, body.bytes,
                (int64_t)body.length);
}

- (void)webView:(WKWebView *)webView
    stopURLSchemeTask:(id<WKURLSchemeTask>)urlSchemeTask {
  (void)webView;
  [self.activeTasks removeObject:urlSchemeTask];
}

@end

@interface ViewyDarwinWindowBox : NSObject <WKScriptMessageHandler,
                                            NSWindowDelegate>
@property(nonatomic, strong) NSWindow *window;
@property(nonatomic, strong) WKWebView *webView;
@property(nonatomic, strong) NSMutableSet<NSString *> *handlerNames;
@property(nonatomic, strong)
    NSMutableDictionary<NSString *, ViewyDarwinSchemeHandler *> *schemeHandlers;
@property(nonatomic, strong) NSMutableArray<NSString *> *userScripts;
@property(nonatomic, assign) BOOL debug;
@property(nonatomic, assign) ViewyDarwinMessageCallback messageCallback;
@property(nonatomic, assign) void *messageUserdata;
@property(nonatomic, assign) ViewyDarwinEventCallback eventCallback;
@property(nonatomic, assign) void *eventUserdata;
@property(nonatomic, assign) BOOL hasLoaded;
@end

@implementation ViewyDarwinWindowBox

- (instancetype)init {
  self = [super init];
  if (self) {
    _handlerNames = [NSMutableSet set];
    _schemeHandlers = [NSMutableDictionary dictionary];
    _userScripts = [NSMutableArray array];
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

static NSString *ViewyMenuKeyEquivalent(NSString *key) {
  if (key.length == 0) {
    return @"";
  }
  if (key.length == 1) {
    return key.lowercaseString;
  }
  NSDictionary<NSString *, NSString *> *punctuation = @{
    @"Plus" : @"+",
    @"Minus" : @"-",
    @"Comma" : @",",
    @"Period" : @".",
    @"Slash" : @"/",
    @"Backslash" : @"\\",
    @"Semicolon" : @";",
    @"Quote" : @"'",
    @"BracketLeft" : @"[",
    @"BracketRight" : @"]",
    @"Equal" : @"=",
    @"Grave" : @"`",
    @"Space" : @" "
  };
  NSString *mapped = punctuation[key];
  if (mapped) {
    return mapped;
  }

  unichar ch = 0;
  if ([key isEqualToString:@"Enter"]) {
    ch = NSCarriageReturnCharacter;
  } else if ([key isEqualToString:@"Escape"]) {
    ch = 0x1B;
  } else if ([key isEqualToString:@"Tab"]) {
    ch = NSTabCharacter;
  } else if ([key isEqualToString:@"Backspace"]) {
    ch = NSBackspaceCharacter;
  } else if ([key isEqualToString:@"Delete"]) {
    ch = NSDeleteCharacter;
  } else if ([key isEqualToString:@"Insert"]) {
    ch = NSInsertFunctionKey;
  } else if ([key isEqualToString:@"Home"]) {
    ch = NSHomeFunctionKey;
  } else if ([key isEqualToString:@"End"]) {
    ch = NSEndFunctionKey;
  } else if ([key isEqualToString:@"PageUp"]) {
    ch = NSPageUpFunctionKey;
  } else if ([key isEqualToString:@"PageDown"]) {
    ch = NSPageDownFunctionKey;
  } else if ([key isEqualToString:@"Up"]) {
    ch = NSUpArrowFunctionKey;
  } else if ([key isEqualToString:@"Down"]) {
    ch = NSDownArrowFunctionKey;
  } else if ([key isEqualToString:@"Left"]) {
    ch = NSLeftArrowFunctionKey;
  } else if ([key isEqualToString:@"Right"]) {
    ch = NSRightArrowFunctionKey;
  } else if ([key hasPrefix:@"F"]) {
    NSInteger n = [key substringFromIndex:1].integerValue;
    if (n >= 1 && n <= 24) {
      ch = NSF1FunctionKey + (unichar)(n - 1);
    }
  }

  if (ch != 0) {
    return [NSString stringWithCharacters:&ch length:1];
  }
  return @"";
}

static NSEventModifierFlags ViewyMenuModifierFlags(NSArray *flags) {
  NSEventModifierFlags result = 0;
  if (![flags isKindOfClass:[NSArray class]]) {
    return result;
  }
  for (id raw in flags) {
    if (![raw isKindOfClass:[NSString class]]) {
      continue;
    }
    NSString *flag = (NSString *)raw;
    if ([flag isEqualToString:@"ctrl"]) {
      result |= NSEventModifierFlagControl;
    } else if ([flag isEqualToString:@"shift"]) {
      result |= NSEventModifierFlagShift;
    } else if ([flag isEqualToString:@"alt"]) {
      result |= NSEventModifierFlagOption;
    } else if ([flag isEqualToString:@"super"]) {
      result |= NSEventModifierFlagCommand;
    }
  }
  return result;
}

static NSInteger ViewyMenuKind(NSDictionary *dict) {
  id value = dict[@"kind"];
  if ([value isKindOfClass:[NSString class]]) {
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
  if ([value respondsToSelector:@selector(integerValue)]) {
    return [value integerValue];
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
  NSString *keyEquivalent =
      ViewyMenuKeyEquivalent(ViewyDictString(dict, @"keyEquivalent"));
  if (keyEquivalent.length > 0) {
    item.keyEquivalent = keyEquivalent;
    item.keyEquivalentModifierMask = ViewyMenuModifierFlags(dict[@"modifierFlags"]);
  }

  if (kind == 2) {
    id children = dict[@"children"];
    if ([children isKindOfClass:[NSArray class]]) {
      item.submenu = ViewyBuildMenu(children, callback, userdata, targets);
    }
    return item;
  }

  NSString *itemId = ViewyDictString(dict, @"id");
  if (itemId.length > 0) {
    item.identifier = itemId;
  }
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

static NSMenuItem *ViewyFindMenuItem(NSMenu *menu, NSString *itemId) {
  if (!menu || itemId.length == 0) {
    return nil;
  }
  for (NSMenuItem *item in menu.itemArray) {
    if ([item.identifier isEqualToString:itemId]) {
      return item;
    }
    ViewyDarwinMenuTarget *target =
        [item.representedObject isKindOfClass:[ViewyDarwinMenuTarget class]]
            ? (ViewyDarwinMenuTarget *)item.representedObject
            : nil;
    if ([target.itemId isEqualToString:itemId]) {
      return item;
    }
    NSMenuItem *nested = ViewyFindMenuItem(item.submenu, itemId);
    if (nested) {
      return nested;
    }
  }
  return nil;
}

static WKWebViewConfiguration *ViewyBuildWebViewConfiguration(
    ViewyDarwinWindowBox *box) {
  WKWebViewConfiguration *config = [WKWebViewConfiguration new];
  WKUserContentController *controller = [WKUserContentController new];
  config.userContentController = controller;

  for (NSString *source in box.userScripts) {
    WKUserScript *script = [[WKUserScript alloc]
          initWithSource:source
           injectionTime:WKUserScriptInjectionTimeAtDocumentStart
        forMainFrameOnly:YES];
    [controller addUserScript:script];
  }
  for (NSString *handler in box.handlerNames) {
    [controller addScriptMessageHandler:box name:handler];
  }
  for (NSString *scheme in box.schemeHandlers) {
    [config setURLSchemeHandler:box.schemeHandlers[scheme] forURLScheme:scheme];
  }

  if (box.debug) {
    if (@available(macOS 13.3, *)) {
      [config.preferences setValue:@YES forKey:@"developerExtrasEnabled"];
    }
  }
  return config;
}

static void ViewyRebuildWebView(ViewyDarwinWindow *window) {
  if (!window || !window->box.window) {
    return;
  }
  NSRect frame = window->box.webView ? window->box.webView.frame
                                     : window->box.window.contentView.bounds;
  WKWebViewConfiguration *config = ViewyBuildWebViewConfiguration(window->box);
  window->box.webView = [[WKWebView alloc] initWithFrame:frame
                                           configuration:config];
  window->box.window.contentView = window->box.webView;
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
    for (NSString *itemId in app->box.statusItems.allKeys) {
      NSStatusItem *item = app->box.statusItems[itemId];
      if (item) {
        [[NSStatusBar systemStatusBar] removeStatusItem:item];
      }
    }
    [app->box.statusItems removeAllObjects];
    [app->box.statusTargets removeAllObjects];
    if ([NSApplication sharedApplication].mainMenu == app->box.mainMenu) {
      [NSApplication sharedApplication].mainMenu = [NSMenu new];
    }
    app->box.mainMenu = nil;
    app->box.menuCallback = NULL;
    app->box.menuUserdata = NULL;
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
    box.debug = debug != 0;

    NSRect frame = NSMakeRect(0, 0, 800, 600);
    NSUInteger style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                       NSWindowStyleMaskMiniaturizable |
                       NSWindowStyleMaskResizable;
    box.window = [[NSWindow alloc] initWithContentRect:frame
                                             styleMask:style
                                               backing:NSBackingStoreBuffered
                                                 defer:NO];
    box.webView = [[WKWebView alloc]
        initWithFrame:frame
        configuration:ViewyBuildWebViewConfiguration(box)];
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
  window->box.hasLoaded = YES;
  [window->box.webView loadHTMLString:ViewyString(html) baseURL:nil];
}

void viewy_darwin_window_navigate(ViewyDarwinWindow *window, const char *url) {
  if (!window) {
    return;
  }
  NSURL *nsurl = [NSURL URLWithString:ViewyString(url)];
  if (nsurl) {
    window->box.hasLoaded = YES;
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
  [window->box.userScripts addObject:ViewyString(js)];
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

int32_t viewy_darwin_register_scheme(ViewyDarwinWindow *window,
                                      const char *scheme,
                                      ViewyDarwinSchemeCallback callback,
                                      void *userdata) {
  if (!window || !scheme || !callback) {
    return 0;
  }
  NSString *schemeName = ViewyString(scheme);
  if (schemeName.length == 0 || window->box.schemeHandlers[schemeName] ||
      window->box.hasLoaded) {
    return 0;
  }

  ViewyDarwinSchemeHandler *handler = [ViewyDarwinSchemeHandler new];
  handler.callback = callback;
  handler.userdata = userdata;
  @try {
    window->box.schemeHandlers[schemeName] = handler;
    ViewyRebuildWebView(window);
  } @catch (NSException *exception) {
    (void)exception;
    [window->box.schemeHandlers removeObjectForKey:schemeName];
    return 0;
  }
  return 1;
}

void viewy_darwin_scheme_finish(void *request, int32_t status,
                                const char *status_text,
                                const char *mime_type,
                                const char *headers_json,
                                const uint8_t *body, int64_t body_len) {
  ViewyDarwinSchemeRequest *schemeRequest =
      (__bridge_transfer ViewyDarwinSchemeRequest *)request;
  id<WKURLSchemeTask> task = schemeRequest.task;
  ViewyDarwinSchemeHandler *handler = schemeRequest.handler;
  if (!task || !handler || ![handler.activeTasks containsObject:task]) {
    return;
  }

  NSInteger code = status >= 100 ? status : 500;
  (void)status_text;

  NSMutableDictionary<NSString *, NSString *> *headers =
      [NSMutableDictionary dictionary];
  NSString *mimeType = ViewyString(mime_type);
  if (mimeType.length > 0) {
    headers[@"Content-Type"] = mimeType;
  }
  id rawHeaders = ViewyJson(headers_json);
  if ([rawHeaders isKindOfClass:[NSArray class]]) {
    for (id raw in (NSArray *)rawHeaders) {
      if (![raw isKindOfClass:[NSDictionary class]]) {
        continue;
      }
      NSString *name = ViewyDictString(raw, @"name");
      NSString *value = ViewyDictString(raw, @"value");
      if (name.length > 0 && value.length > 0) {
        headers[name] = value;
      }
    }
  }
  if (mimeType.length > 0 && !headers[@"Content-Type"]) {
    headers[@"Content-Type"] = mimeType;
  }

  NSHTTPURLResponse *response =
      [[NSHTTPURLResponse alloc] initWithURL:task.request.URL
                                  statusCode:code
                                 HTTPVersion:@"HTTP/1.1"
                                headerFields:headers];
  @try {
    [task didReceiveResponse:response];
    if (body && body_len > 0) {
      NSData *data = [NSData dataWithBytes:body length:(NSUInteger)body_len];
      [task didReceiveData:data];
    }
    [task didFinish];
  } @catch (NSException *exception) {
    (void)exception;
  } @finally {
    [handler.activeTasks removeObject:task];
  }
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
  app->box.mainMenu = menu;
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

  if (callback) {
    ViewyDarwinMenuTarget *target = [ViewyDarwinMenuTarget new];
    target.itemId = itemId;
    target.callback = callback;
    target.userdata = userdata;
    item.button.target = target;
    item.button.action = @selector(activate:);
    app->box.statusTargets[itemId] = target;
  }

  id menuItems = options[@"menu"];
  if ([menuItems isKindOfClass:[NSArray class]]) {
    NSMutableArray<ViewyDarwinMenuTarget *> *targets = [NSMutableArray array];
    item.menu = ViewyBuildMenu(menuItems, callback, userdata, targets);
  }
  app->box.statusItems[itemId] = item;
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
    ViewyDarwinMenuTarget *target = app->box.statusTargets[itemId];
    item.menu = ViewyBuildMenu(menuItems, target.callback, target.userdata,
                               targets);
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
  [app->box.statusTargets removeObjectForKey:itemId];
}

int32_t viewy_darwin_test_menu_item_accelerator_flags(ViewyDarwinApp *app,
                                                      const char *item_id,
                                                      const char *key_equivalent,
                                                      int64_t modifier_mask) {
  if (!app || !item_id || !key_equivalent) {
    return 0;
  }
  NSString *itemId = ViewyString(item_id);
  NSMenuItem *item = ViewyFindMenuItem(app->box.mainMenu, itemId);
  if (!item) {
    return 0;
  }
  int32_t result = 1;
  NSString *expectedKey = ViewyString(key_equivalent);
  if ([item.keyEquivalent isEqualToString:expectedKey]) {
    result |= 2;
  }
  if ((item.keyEquivalentModifierMask & NSEventModifierFlagDeviceIndependentFlagsMask) ==
      ((NSEventModifierFlags)modifier_mask &
       NSEventModifierFlagDeviceIndependentFlagsMask)) {
    result |= 4;
  }
  return result;
}
