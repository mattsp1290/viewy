# viewy tray app example

This example demonstrates the native tray API with a tooltip, attached menu,
menu-id callbacks, a hidden backing window that can be shown from the tray, and
Linux icon updates. macOS and Windows use the platform default tray icon until
the example adds platform-specific icon assets.

Run it from this directory with a native backend:

```bash
mkdir -p build
nim c --mm:orc --threads:on -d:viewyBackend=native --out:build/tray-app -r src/main.nim
```

Linux requires GTK/WebKitGTK and a runtime AppIndicator library. GNOME sessions
also need a StatusNotifier/AppIndicator tray host extension.

The app still creates a backing webview because viewy apps are webview-backed,
but it starts hidden and can be shown or hidden through the tray menu.
