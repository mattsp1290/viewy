import viewy/assets

doAssert generatedAssetsModuleName == "viewy_assets"
doAssert generatedEmbeddedHtmlSymbol == "viewyEmbeddedHtml"
doAssert fallbackEmbeddedHtml == "<!doctype html><meta charset=\"utf-8\"><div id=\"app\"></div>"
doAssert embeddedHtml() == fallbackEmbeddedHtml

echo "ok: embedded asset contract"
