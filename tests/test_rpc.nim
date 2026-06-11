import std/[json, strutils]

import jsony
import viewy/rpc

type
  Thing = object
    x: int
    name: string

expose greet(name: string): string =
  "hello " & name

expose add(a, b: int): int =
  a + b

expose invert(flag: bool): bool =
  not flag

expose bump(items: seq[int]): seq[int] =
  items & @[items.len]

expose touch(t: Thing): Thing =
  Thing(x: t.x + 1, name: t.name)

proc raiseSecret(): string =
  raise newException(ValueError, "secret implementation detail")

expose fail(): string =
  raiseSecret()

proc binding(name: string): RpcBinding =
  for item in bindings():
    if item.name == name:
      return item
  raise newException(ValueError, "missing binding: " & name)

doAssert binding("greet").call("1", "[\"world\"]").json.fromJson(string) == "hello world"
doAssert binding("add").call("2", "[2,3]").json.fromJson(int) == 5
doAssert binding("invert").call("3", "[true]").json.fromJson(bool) == false
doAssert binding("bump").call("4", "[[1,2]]").json.fromJson(seq[int]) == @[1, 2, 2]

let touched = binding("touch").call("5", """[{"x": 4, "name": "oak"}]""")
doAssert touched.ok
doAssert touched.json.fromJson(Thing).x == 5

let arity = binding("add").call("6", "[1]")
doAssert not arity.ok
let arityJson = parseJson(arity.json)
doAssert arityJson["error"]["type"].getStr == "ValueError"
doAssert not arityJson["error"]["message"].getStr.contains("offset")

let failed = binding("fail").call("7", "[]")
doAssert not failed.ok
let failedJson = parseJson(failed.json)
doAssert failedJson["error"]["type"].getStr == "ValueError"
doAssert failedJson["error"]["message"].getStr == "ValueError"
doAssert failedJson["error"]["message"].getStr != "secret implementation detail"

let metadata = parseJson(dumpBindingsJson())
doAssert metadata.kind == JArray
doAssert metadata.len == bindings().len
doAssert metadata[0]["name"].getStr == "greet"
doAssert metadata[0]["params"][0]["name"].getStr == "name"
doAssert metadata[0]["params"][0]["typ"].getStr == "string"
doAssert metadata[0]["returnType"].getStr == "string"
doAssert metadata[0]["async"].getBool == false

echo "ok: rpc expose wrappers"
