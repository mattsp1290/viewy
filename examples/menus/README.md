# viewy menus example

This example demonstrates native app/window menus, accelerators, checked menu
state, radio menu state, submenu dispatch, and the context-menu API.

Run it from this directory:

```bash
nimble run -y
```

The app requires the native backend on Linux, macOS, or Windows. The app menu is
installed at startup. Right-click the window content to exercise the context
menu path; current runtimes show an in-app status message until their
`capContextMenu` implementation is advertised.
