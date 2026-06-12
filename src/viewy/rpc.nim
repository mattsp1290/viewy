## Typed RPC layer (spec section 4.4): the `expose` macro and JSON envelope
## codec.

import std/[asyncdispatch, macros]

import jsony

type
  RpcResolver* = proc(id: string; ok: bool; json: string) {.closure.}
    ## Completes a deferred RPC call. App wiring should pass a resolver that
    ## reaches the backend through its thread-safe dispatch/resolve path.

  RpcWrapper* = proc(id, jsonArgs: string): RpcReply {.closure, gcsafe.}
    ## Invoked by tests and sync-only wiring when a webview binding calls into
    ## Nim. Async wrappers return a structured error here; use
    ## `callWithResolver` for bindings whose metadata has `async = true`.

  RpcAsyncWrapper* = proc(id, jsonArgs: string;
      resolve: RpcResolver): RpcReply {.closure, gcsafe.}
    ## Invoked by app wiring when a webview binding may complete later.

  RpcReply* = object
    ## Immediate wrapper result. Async wrappers return `pending = true` after
    ## scheduling completion through the supplied resolver.
    ok*: bool
      ## True when the RPC completed successfully.
    pending*: bool
      ## True when an async RPC will resolve later through a resolver.
    json*: string
      ## JSON result value on success or JSON error envelope on failure.

  RpcBinding* = object
    ## Runtime binding registered by `expose`.
    name*: string
      ## JavaScript-visible binding name.
    call*: RpcWrapper
      ## Synchronous wrapper used by tests and sync-only call paths.
    callWithResolver*: RpcAsyncWrapper
      ## Wrapper that can complete async results through a resolver.

  RpcParamMetadata* = object
    ## Parameter metadata emitted for future tooling.
    name*: string
      ## Source parameter name.
    typ*: string
      ## Nim type name as captured from the exposed signature.

  RpcBindingMetadata* = object
    ## Compile/runtime metadata for an exposed proc.
    name*: string
      ## JavaScript-visible binding name.
    params*: seq[RpcParamMetadata]
      ## Ordered parameter metadata for the binding.
    returnType*: string
      ## Nim return type name, or the awaited value type for `Future[T]`.
    async*: bool
      ## True when the exposed proc returns a `Future`.

  RpcErrorEnvelope* = object
    ## JSON error payload returned for failed RPC calls.
    message*: string
      ## Human-readable error message.
    `type`*: string
      ## Nim exception type name.

  RpcErrorResponse* = object
    ## Top-level JSON error response shape.
    error*: RpcErrorEnvelope
      ## Structured error details.

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

proc missingResolverReply(): RpcReply =
  RpcReply(
    ok: false,
    json: rpcErrorJson("async RPC wrapper requires a resolver", "ValueError"),
  )

proc completeFuture[T](id: string; fut: Future[T];
    resolver: RpcResolver) {.async.} =
  try:
    let rpcValue = await fut
    {.cast(gcsafe).}:
      resolver(id, true, rpcValue.toJson())
  except CatchableError as error:
    {.cast(gcsafe).}:
      resolver(id, false, rpcErrorJson($error.name, $error.name))

proc completeVoidFuture(id: string; fut: Future[void];
    resolver: RpcResolver) {.async.} =
  try:
    await fut
    {.cast(gcsafe).}:
      resolver(id, true, "")
  except CatchableError as error:
    {.cast(gcsafe).}:
      resolver(id, false, rpcErrorJson($error.name, $error.name))

proc rawArgs(jsonArgs: string; expected: int): seq[RawJson] =
  result = jsonArgs.fromJson(seq[RawJson])
  if result.len != expected:
    raise newException(ValueError, "invalid argument count")

proc registerBinding*(binding: RpcBinding; metadata: RpcBindingMetadata) =
  ## Register one exposed proc wrapper and its metadata.
  var normalized = binding
  if normalized.callWithResolver == nil:
    let syncCall = normalized.call
    normalized.callWithResolver =
      proc(id, jsonArgs: string; resolver: RpcResolver): RpcReply {.gcsafe.} =
        if resolver == nil:
          discard
        syncCall(id, jsonArgs)

  for i in 0 ..< registry.len:
    if registry[i].name == normalized.name:
      registry[i] = normalized
      metadataRegistry[i] = metadata
      return
  registry.add normalized
  metadataRegistry.add metadata

proc bindings*(): lent seq[RpcBinding] =
  ## Return all runtime RPC bindings registered by `expose`.
  registry

proc bindingMetadata*(): lent seq[RpcBindingMetadata] =
  ## Return metadata for all registered RPC bindings.
  metadataRegistry

proc dumpBindingsJson*(): string =
  ## Return a JSON array of `RpcBindingMetadata` objects.
  ##
  ## Field names are part of the public metadata schema consumed by tooling.
  metadataRegistry.toJson()

proc clearBindingsForTests*() =
  ## Clear process-global RPC registries. Intended for unit tests only.
  registry.setLen 0
  metadataRegistry.setLen 0

macro viewyDumpBinding(metadata: static[string]): untyped =
  when defined(viewyDumpBindings):
    ## Compile-time dump mode emits one JSON metadata object per line.
    ## Consumers should parse it as newline-delimited JSON.
    echo metadata
  result = newStmtList()

proc metadataNode(name: string; params: seq[(string, string)];
    ret: string; isAsync: bool): NimNode =
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
  result.add nnkExprColonExpr.newTree(ident("async"), newLit(isAsync))

proc metadataJson(name: string; params: seq[(string, string)];
    ret: string; isAsync: bool): string =
  var meta = RpcBindingMetadata(name: name, returnType: ret, async: isAsync)
  for param in params:
    meta.params.add RpcParamMetadata(name: param[0], typ: param[1])
  meta.toJson()

proc futureValueType(ret: NimNode): tuple[ok: bool; value: NimNode] =
  if ret.kind == nnkBracketExpr and ret.len == 2:
    let head = ret[0]
    let isFuture =
      if head.kind in {nnkIdent, nnkSym}:
        head.repr == "Future"
      elif head.kind == nnkDotExpr and head.len > 0:
        head[^1].repr == "Future"
      else:
        false
    if not isFuture:
      return (false, ret)
    return (true, ret[1])
  (false, ret)

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
  ## Define and register a synchronous or `Future`-returning RPC proc.
  let parsed = parseExposeSignature(sig)
  let procName = parsed.name
  let procNameStr = $procName
  let parsedBody = parseExposeBody(body)
  let ret = parsedBody.ret
  let futureType = futureValueType(ret)
  let isAsync = futureType.ok
  let exposedRet = futureType.value
  let retName = if exposedRet.kind == nnkIdent and $exposedRet ==
      "void": "void" else: exposedRet.repr
  let def = procDefNode(procName, ret, parsedBody.body, parsed.params)
  let wrapperName = genSym(nskProc, procNameStr & "ViewyWrapper")
  let wrapperWithResolverName = genSym(nskProc,
      procNameStr & "ViewyWrapperWithResolver")
  let registerName = genSym(nskProc, procNameStr & "ViewyRegister")
  let syncArgsName = genSym(nskLet, "args")
  let asyncArgsName = genSym(nskLet, "args")
  let syncIdName = genSym(nskParam, "id")
  let syncJsonArgsName = genSym(nskParam, "jsonArgs")
  let asyncIdName = genSym(nskParam, "id")
  let asyncJsonArgsName = genSym(nskParam, "jsonArgs")
  let resolveName = genSym(nskParam, "resolve")

  var paramMeta: seq[(string, string)] = @[]
  var syncParseStmts = newStmtList()
  var asyncParseStmts = newStmtList()
  var syncCallArgs = newSeq[NimNode]()
  var asyncCallArgs = newSeq[NimNode]()

  for argIndex, param in parsed.params:
    let syncLocalName = genSym(nskLet, $param[0])
    let asyncLocalName = genSym(nskLet, $param[0])
    let typ = param[1]
    let indexLit = newLit(argIndex)
    paramMeta.add(($param[0], typ.repr))
    syncParseStmts.add quote do:
      let `syncLocalName` = string(`syncArgsName`[`indexLit`]).fromJson(`typ`)
    asyncParseStmts.add quote do:
      let `asyncLocalName` = string(`asyncArgsName`[`indexLit`]).fromJson(`typ`)
    syncCallArgs.add syncLocalName
    asyncCallArgs.add asyncLocalName

  let metadataExpr = metadataNode(procNameStr, paramMeta, retName, isAsync)
  let metadataJsonLiteral = metadataJson(procNameStr, paramMeta, retName, isAsync)
  let syncCallExpr = newCall(procName, syncCallArgs)
  let asyncCallExpr = newCall(procName, asyncCallArgs)
  let argCountLit = newLit(parsed.params.len)

  let syncSuccessExpr =
    if isAsync:
      quote do:
        missingResolverReply()
    elif retName == "void":
      quote do:
        `syncCallExpr`
        RpcReply(ok: true, json: "")
    else:
      quote do:
        let rpcValue = `syncCallExpr`
        RpcReply(ok: true, json: rpcValue.toJson())

  let asyncSuccessExpr =
    if not isAsync:
      quote do:
        `wrapperName`(`asyncIdName`, `asyncJsonArgsName`)
    elif retName == "void":
      let futureName = genSym(nskLet, "rpcFuture")
      quote do:
        if `resolveName` == nil:
          missingResolverReply()
        else:
          let `futureName` = `asyncCallExpr`
          asyncCheck completeVoidFuture(`asyncIdName`, `futureName`, `resolveName`)
          RpcReply(ok: true, pending: true, json: "")
    else:
      let futureName = genSym(nskLet, "rpcFuture")
      quote do:
        if `resolveName` == nil:
          missingResolverReply()
        else:
          let `futureName` = `asyncCallExpr`
          asyncCheck completeFuture(`asyncIdName`, `futureName`, `resolveName`)
          RpcReply(ok: true, pending: true, json: "")

  result = quote do:
    `def`

    proc `wrapperName`(`syncIdName`, `syncJsonArgsName`: string): RpcReply {.gcsafe.} =
      discard `syncIdName`
      try:
        let `syncArgsName` = rawArgs(`syncJsonArgsName`, `argCountLit`)
        `syncParseStmts`
        `syncSuccessExpr`
      except CatchableError as error:
        exceptionReply(error)

    proc `wrapperWithResolverName`(`asyncIdName`, `asyncJsonArgsName`: string;
        `resolveName`: RpcResolver): RpcReply {.gcsafe.} =
      try:
        let `asyncArgsName` = rawArgs(`asyncJsonArgsName`, `argCountLit`)
        `asyncParseStmts`
        `asyncSuccessExpr`
      except CatchableError as error:
        exceptionReply(error)

    proc `registerName`() {.used.} =
      registerBinding(
        RpcBinding(name: `procNameStr`, call: `wrapperName`,
            callWithResolver: `wrapperWithResolverName`),
        `metadataExpr`,
      )

    `registerName`()
    viewyDumpBinding(`metadataJsonLiteral`)
