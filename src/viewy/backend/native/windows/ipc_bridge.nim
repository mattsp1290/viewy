## Pure Windows WebView2 IPC bridge helpers.

import std/[json, strutils]

import jsony

type
  WindowsIpcMessage* = object
    name*: string
    id*: string
    jsonArgs*: string

proc jsCall(expr: string): string =
  "(function(){try{" & expr & "}catch(e){setTimeout(function(){throw e;},0);}})();"

proc windowsResolveScript*(id: string; ok: bool; jsonResult: string): string =
  jsCall("if(window.__viewy&&window.__viewy._resolve)window.__viewy._resolve(" &
      id.toJson() & "," & (if ok: "true" else: "false") & "," &
      jsonResult.toJson() & ");")

proc windowsBindScript*(name: string): string =
  jsCall("""
var w=window,v=w.__viewy||(w.__viewy={}),p=v._p||(v._p={}),b=v._b||(v._b={}),s=Array.prototype.slice;
v._seq=v._seq||0;
v._id=v._id||function(){
  var c=w.crypto||w.msCrypto,b,i,a=[];
  if(c&&c.getRandomValues){
    b=new Uint8Array(16);
    c.getRandomValues(b);
    for(i=0;i<b.length;i++)a.push(("0"+b[i].toString(16)).slice(-2));
    return a.join("");
  }
  return String(Date.now())+"-"+String(Math.random()).slice(2)+"-"+String(++v._seq);
};
v._resolve=v._resolve||function(id,ok,json){
  var q=p[id],value;
  if(!q)return;
  delete p[id];
  try{value=json===""?undefined:JSON.parse(json);}catch(e){ok=false;value=e;}
  (ok?q.resolve:q.reject)(value);
};
if((Object.hasOwn?Object.hasOwn(w,$1):Object.prototype.hasOwnProperty.call(w,$1))&&!b[$1])throw new Error("Property "+$1+" already exists");
b[$1]=true;
w[$1]=function(){
  var args=s.call(arguments),id=v._id();
  return new Promise(function(resolve,reject){
    p[id]={resolve:resolve,reject:reject};
    chrome.webview.postMessage(JSON.stringify({name:$1,id:id,args:JSON.stringify(args)}));
  });
};
""" % [name.toJson()])

proc windowsUnbindScript*(name: string): string =
  jsCall("if(window.__viewy&&window.__viewy._b)delete window.__viewy._b[" &
      name.toJson() & "];delete window[" & name.toJson() & "];")

proc parseWindowsWebMessage*(message: string): WindowsIpcMessage =
  let payload = parseJson(message)
  WindowsIpcMessage(
    name: payload{"name"}.getStr(),
    id: payload{"id"}.getStr(),
    jsonArgs: payload{"args"}.getStr(),
  )
