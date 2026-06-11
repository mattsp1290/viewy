## Scaffold smoke test: the library root and its re-exported modules
## must at least compile, and viewyVersion must match viewy.nimble so
## the two cannot drift apart silently.

import std/strutils
import viewy

const nimbleVersion = block:
  var v = ""
  for line in staticRead("../viewy.nimble").splitLines:
    if line.startsWith("version"):
      v = line.split('"')[1]
      break
  v

doAssert nimbleVersion != "", "could not parse version from viewy.nimble"
doAssert viewyVersion == nimbleVersion
echo "ok: viewy ", viewyVersion, " scaffold compiles"
