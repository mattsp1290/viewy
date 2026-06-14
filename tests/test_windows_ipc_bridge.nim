import std/[os, osproc, strutils, tempfiles]

import viewy/backend/native/windows/ipc_bridge
import viewy/runtime_js

let parsed = parseWindowsWebMessage(
  """{"name":"ready","id":"abc","args":"[\"via-call\",42]"}""")
doAssert parsed.name == "ready"
doAssert parsed.id == "abc"
doAssert parsed.jsonArgs == """["via-call",42]"""

let bindJs = windowsBindScript("ready")
doAssert "chrome.webview.postMessage" in bindJs
doAssert "JSON.stringify({name:" in bindJs
doAssert "v._resolve" in bindJs

let resolveOk = windowsResolveScript("fixed-id", true, "\"ok\"")
doAssert "window.__viewy._resolve" in resolveOk
doAssert "\"fixed-id\"" in resolveOk
doAssert "true" in resolveOk

let (_, nodeCheck) = execCmdEx("node --version")
if nodeCheck != 0:
  echo "skipped windows ipc bridge runtime contract: node unavailable"
  quit 0

let dir = createTempDir("viewy_windows_ipc_bridge_", "")
let scriptPath = dir / "bridge_contract.js"
let nodeScript = """
const assert = require("assert");
const sent = [];
globalThis.window = {};
globalThis.chrome = {webview: {postMessage(message) { sent.push(message); }}};
var window = globalThis.window;
var chrome = globalThis.chrome;
window.crypto = {getRandomValues(bytes) { for (let i = 0; i < bytes.length; i++) bytes[i] = i + 1; }};
""" & viewyRuntimeJs & "\n" & windowsBindScript("ready") &
    """

(async function() {
  window.__viewy._id = function() { return "fixed-id"; };
  const okPromise = window.__viewy.call("ready", "via-call", 42);
  assert.strictEqual(sent.length, 1);
  const okEnvelope = JSON.parse(sent[0]);
  assert.strictEqual(okEnvelope.name, "ready");
  assert.strictEqual(okEnvelope.id, "fixed-id");
  assert.deepStrictEqual(JSON.parse(okEnvelope.args), ["via-call", 42]);
""" & windowsResolveScript("fixed-id", true, "\"ok\"") &
    """
  assert.strictEqual(await okPromise, "ok");

  window.__viewy._id = function() { return "reject-id"; };
  const rejectPromise = window.ready("bad");
  assert.strictEqual(JSON.parse(sent[1]).id, "reject-id");
""" & windowsResolveScript("reject-id", false, "{\"error\":\"fail\"}") &
    """
  let rejected = false;
  try {
    await rejectPromise;
  } catch (error) {
    rejected = true;
    assert.deepStrictEqual(error, {error: "fail"});
  }
  assert.strictEqual(rejected, true);
""" & windowsUnbindScript("ready") & """
  assert.strictEqual(Object.prototype.hasOwnProperty.call(window, "ready"), false);
})().catch((error) => {
  console.error(error && error.stack || error);
  process.exit(1);
});
"""
writeFile(scriptPath, nodeScript)

let (output, exitCode) = execCmdEx("node " & quoteShell(scriptPath))
removeDir(dir)
doAssert exitCode == 0, output

echo "ok: windows ipc bridge contract"
