## Typed RPC layer (spec section 4.4): the `expose` macro and JSON envelope
## codec.

import std/macros

import jsony

type
  RpcWrapper* = proc(id, jsonArgs: string): RpcReply {.closure, gcsafe.}
    ## Invoked by app wiring when a webview binding calls into Nim.

  RpcReply* = object
    ## Result of a synchronous RPC wrapper. Async support will reuse `id` and
    ## resolve later through backend dispatch.
    ok*: bool
    json*: string

  RpcBinding* = object
    ## Runtime binding registered by `expose`.
    name*: string
    call*: RpcWrapper

  RpcParamMetadata* = object
    ## Parameter metadata emitted for future tooling.
    name*: string
    typ*: string

  RpcBindingMetadata* = object
    ## Compile/runtime metadata for an exposed proc.
    name*: string
    params*: seq[RpcParamMetadata]
    returnType*: string
    async*: bool

  RpcErrorEnvelope* = object
    message*: string
    `type`*: string

  RpcErrorResponse* = object
    error*: RpcErrorEnvelope

var
  registry {.global.}: seq[RpcBinding]
  metadataRegistry {.global.}: seq[RpcBindingMetadata]

proc rpcErrorJson(message, typ: string): string =
  RpcErrorResponse(error: RpcErrorEnvelope(message: message,
      `type`: typ)).toJson()

proc exceptionReply(error: ref Exception): RpcReply =
  RpcReply(
    ok: false,
    json: rpcErrorJson($error.name, $error.name),
  )

proc rawArgs(jsonArgs: string; expected: int): seq[RawJson] =
  result = jsonArgs.fromJson(seq[RawJson])
  if result.len != expected:
    raise newException(ValueError, "invalid argument count")

proc registerBinding*(binding: RpcBinding; metadata: RpcBindingMetadata) =
  ## Register one exposed proc wrapper and its metadata.
  for i in 0 ..< registry.len:
    if registry[i].name == binding.name:
      registry[i] = binding
      metadataRegistry[i] = metadata
      return
  registry.add binding
  metadataRegistry.add metadata

proc bindings*(): lent seq[RpcBinding] =
  ## Return all runtime RPC bindings registered by `expose`.
  registry

proc bindingMetadata*(): lent seq[RpcBindingMetadata] =
  ## Return metadata for all registered RPC bindings.
  metadataRegistry

proc dumpBindingsJson*(): string =
  ## Return JSON metadata for tooling and `-d:viewyDumpBindings` verification.
  metadataRegistry.toJson()

proc clearBindingsForTests*() =
  ## Clear process-global RPC registries. Intended for unit tests only.
  registry.setLen 0
  metadataRegistry.setLen 0

macro viewyDumpBinding(metadata: static[string]): untyped =
  when defined(viewyDumpBindings):
    echo metadata
  result = newStmtList()

proc metadataNode(name: string; params: seq[(string, string)];
    ret: string): NimNode =
  result = nnkObjConstr.newTree(ident("RpcBindingMetadata"))
  result.add nnkExprColonExpr.newTree(ident("name"), newLit(name))

  var paramItems = newSeq[NimNode]()
  for param in params:
    paramItems.add nnkObjConstr.newTree(
      ident("RpcParamMetadata"),
      nnkExprColonExpr.newTree(ident("name"), newLit(param[0])),
      nnkExprColonExpr.newTree(ident("typ"), newLit(param[1])),
    )
  let paramsSeq = nnkPrefix.newTree(ident("@"), nnkBracket.newTree(paramItems))
  result.add nnkExprColonExpr.newTree(ident("params"), paramsSeq)
  result.add nnkExprColonExpr.newTree(ident("returnType"), newLit(ret))
  result.add nnkExprColonExpr.newTree(ident("async"), ident("false"))

proc metadataJson(name: string; params: seq[(string, string)];
    ret: string): string =
  var meta = RpcBindingMetadata(name: name, returnType: ret, async: false)
  for param in params:
    meta.params.add RpcParamMetadata(name: param[0], typ: param[1])
  meta.toJson()

proc parseExposeBody(body: NimNode): tuple[ret, body: NimNode] =
  if body.kind == nnkStmtList and body.len == 1 and body[0].kind == nnkAsgn:
    (body[0][0], body[0][1])
  else:
    (ident("void"), body)

proc parseExposeSignature(sig: NimNode): tuple[name: NimNode; params: seq[(
    NimNode, NimNode)]] =
  if sig.kind notin {nnkCall, nnkObjConstr} or sig.len == 0:
    error("expose expects syntax like: expose name(arg: Type): Return = body", sig)

  result.name = sig[0]
  var pending: seq[NimNode] = @[]
  for i in 1 ..< sig.len:
    let item = sig[i]
    case item.kind
    of nnkIdent:
      pending.add item
    of nnkExprColonExpr:
      for name in pending:
        result.params.add((name, item[1]))
      pending.setLen 0
      result.params.add((item[0], item[1]))
    else:
      error("unsupported expose parameter syntax", item)

  if pending.len > 0:
    error("expose parameter lacks a type", pending[0])

proc procDefNode(name, ret, body: NimNode; params: seq[(NimNode,
    NimNode)]): NimNode =
  var formalParams = nnkFormalParams.newTree(ret)
  for param in params:
    formalParams.add nnkIdentDefs.newTree(param[0], param[1], newEmptyNode())

  nnkProcDef.newTree(
    name,
    newEmptyNode(),
    newEmptyNode(),
    formalParams,
    nnkPragma.newTree(ident("gcsafe")),
    newEmptyNode(),
    body,
  )

macro expose*(sig: untyped; body: untyped): untyped =
  ## Define and register a synchronous RPC proc.
  let parsed = parseExposeSignature(sig)
  let procName = parsed.name
  let procNameStr = $procName
  let parsedBody = parseExposeBody(body)
  let ret = parsedBody.ret
  let retName = if ret.kind == nnkIdent and $ret ==
      "void": "void" else: ret.repr
  let def = procDefNode(procName, ret, parsedBody.body, parsed.params)
  let wrapperName = genSym(nskProc, procNameStr & "ViewyWrapper")
  let registerName = genSym(nskProc, procNameStr & "ViewyRegister")
  let argsName = genSym(nskLet, "args")
  let idName = genSym(nskParam, "id")
  let jsonArgsName = genSym(nskParam, "jsonArgs")

  var paramMeta: seq[(string, string)] = @[]
  var parseStmts = newStmtList()
  var callArgs = newSeq[NimNode]()

  for argIndex, param in parsed.params:
    let localName = genSym(nskLet, $param[0])
    let typ = param[1]
    let indexLit = newLit(argIndex)
    paramMeta.add(($param[0], typ.repr))
    parseStmts.add quote do:
      let `localName` = string(`argsName`[`indexLit`]).fromJson(`typ`)
    callArgs.add localName

  let metadataExpr = metadataNode(procNameStr, paramMeta, retName)
  let metadataJsonLiteral = metadataJson(procNameStr, paramMeta, retName)
  let callExpr = newCall(procName, callArgs)
  let argCountLit = newLit(parsed.params.len)

  let successExpr =
    if retName == "void":
      quote do:
        `callExpr`
        RpcReply(ok: true, json: "")
    else:
      quote do:
        let rpcValue = `callExpr`
        RpcReply(ok: true, json: rpcValue.toJson())

  result = quote do:
    `def`

    proc `wrapperName`(`idName`, `jsonArgsName`: string): RpcReply {.gcsafe.} =
      discard `idName`
      try:
        let `argsName` = rawArgs(`jsonArgsName`, `argCountLit`)
        `parseStmts`
        `successExpr`
      except CatchableError as error:
        exceptionReply(error)

    proc `registerName`() {.used.} =
      registerBinding(
        RpcBinding(name: `procNameStr`, call: `wrapperName`),
        `metadataExpr`,
      )

    `registerName`()
    viewyDumpBinding(`metadataJsonLiteral`)
