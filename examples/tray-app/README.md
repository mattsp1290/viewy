# viewy tray app example

This example demonstrates the native tray API with a tooltip, attached menu,
menu-id callbacks, and Linux icon updates. macOS and Windows use the platform
default tray icon until the example adds platform-specific icon assets.

Run it from this directory with a native backend:

```bash
mkdir -p build
nim c --mm:orc --threads:on -d:viewyBackend=native --out:build/tray-app -r src/main.nim
```

Linux requires GTK/WebKitGTK and a runtime AppIndicator library. GNOME sessions
also need a StatusNotifier/AppIndicator tray host extension.

The current public API still creates the backing webview window. A true
start-hidden tray-only app is tracked separately because viewy does not yet
expose a backend-neutral hide/show window capability.
