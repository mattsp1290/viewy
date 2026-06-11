## JavaScript runtime injected into each webview before page scripts run.

const viewyRuntimeJs* = """
(function(w){
var v=w.__viewy||{},e=v._e||{},s=Array.prototype.slice;
v.call=function(n){var f=w[n];if(typeof f!="function")return Promise.reject(new Error("viewy binding not found: "+n));return f.apply(w,s.call(arguments,1));};
v.on=function(n,c){(e[n]||(e[n]=[])).push(c);return function(){v.off(n,c);};};
v.off=function(n,c){var l=e[n],i;if(!l)return;if(!c){delete e[n];return;}for(i=l.length-1;i>=0;i--)if(l[i]===c)l.splice(i,1);if(!l.length)delete e[n];};
v.emit=function(n,p){var l=e[n],i,x;if(!l)return;l=l.slice();for(i=0;i<l.length;i++)try{l[i](p,n);}catch(x){setTimeout((function(y){return function(){throw y;};})(x),0);}};
v._e=e;w.__viewy=v;
})(window);
"""
