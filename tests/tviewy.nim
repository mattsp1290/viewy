## Scaffold smoke test: the library root and its re-exported modules
## must at least compile and agree on the version constant.

import viewy

doAssert viewyVersion == "0.1.0"
echo "ok: viewy ", viewyVersion, " scaffold compiles"
