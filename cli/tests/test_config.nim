import std/[os, tempfiles, unittest]

import viewy_cli/config

suite "viewy config":
  test "loadConfig returns defaults when viewy.json is absent":
    let dir = createTempDir("viewy-config", "")
    let old = getCurrentDir()
    try:
      setCurrentDir(dir)
      let cfg = loadConfig()
      check cfg == DefaultConfig
    finally:
      setCurrentDir(old)
      removeDir(dir)

  test "parseConfig accepts a complete config":
    let cfg = parseConfig("""
      {
        "name": "demo",
        "title": "Demo",
        "width": 800,
        "height": 600,
        "resizable": false,
        "assets": "served",
        "devUrl": "http://127.0.0.1:5173",
        "frontendDir": "frontend",
        "nimMain": "src/main.nim"
      }
    """)
    check cfg.name == "demo"
    check cfg.assets == amServed
    check cfg.resizable == false

  test "parseConfig fills omitted fields from defaults":
    let cfg = parseConfig("""{ "name": "partial" }""")
    check cfg.name == "partial"
    check cfg.title == DefaultConfig.title
    check cfg.width == DefaultConfig.width
    check cfg.assets == DefaultConfig.assets

  test "parseConfig reports malformed JSON as ConfigError":
    expect ConfigError:
      discard parseConfig("{ nope")

  test "parseConfig reports invalid asset mode as ConfigError":
    expect ConfigError:
      discard parseConfig("""{ "assets": "zip" }""")

  test "parseConfig validates required fields":
    expect ConfigError:
      discard parseConfig("""
        {
          "name": "",
          "title": "Demo",
          "width": 800,
          "height": 600,
          "resizable": true,
          "assets": "single",
          "devUrl": "http://127.0.0.1:5173",
          "frontendDir": "frontend",
          "nimMain": "src/main.nim"
        }
      """)
