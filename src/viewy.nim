## viewy — a Tauri/Wails-style desktop app framework for Nim.
##
## Backend in Nim, frontend in HTML/CSS/JS rendered by the OS-native
## webview. This module re-exports the public API surface.

import viewy/[app, rpc, events, assets, runtime_js]
export app, rpc, events, assets, runtime_js

const viewyVersion* = "0.1.0"
  ## Library version, kept in sync with viewy.nimble.
