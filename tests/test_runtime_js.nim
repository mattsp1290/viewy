import std/strutils

import viewy

doAssert viewyRuntimeJs.len < 2048
doAssert "(function(w)" in viewyRuntimeJs
doAssert "w.__viewy" in viewyRuntimeJs
doAssert "v.call=function" in viewyRuntimeJs
doAssert "v.on=function" in viewyRuntimeJs
doAssert "v.off=function" in viewyRuntimeJs
doAssert "v.emit=function" in viewyRuntimeJs
doAssert "Promise.reject" in viewyRuntimeJs
doAssert "apply(w,s.call(arguments,1))" in viewyRuntimeJs

echo "ok: viewy runtime js ", viewyRuntimeJs.len, " bytes"
