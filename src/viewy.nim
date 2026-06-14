## viewy — a Tauri/Wails-style desktop app framework for Nim.
##
## Backend in Nim, frontend in HTML/CSS/JS rendered by the OS-native
## webview. This module re-exports the public API surface.

import viewy/[app, rpc, events, assets, assets_served, menu, runtime_js]
export app, rpc, events, assets, assets_served, menu, runtime_js
from viewy/backend/api import ContextMenuOptions, MenuCallback, MenuItem,
    MenuItemKind, WindowEvent, WindowEventKind
export ContextMenuOptions, MenuCallback, MenuItem, MenuItemKind, WindowEvent,
    WindowEventKind

const viewyVersion* = "0.2.0"
  ## Library version, kept in sync with viewy.nimble.
