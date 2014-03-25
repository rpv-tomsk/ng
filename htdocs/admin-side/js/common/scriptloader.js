/*
* Class: ScriptLoader
*     Загружает указанные скрипты из директории scripts.
*/
var ScriptLoader = {
 
    request: null,
 
    loaded: {},
 
    load: function() {
        for (var i = 0, len = arguments.length; i < len; i++) {
            var filename = arguments[i];
            if (!this.loaded[filename]) {
                if (!this.request) {
                    if (window.XMLHttpRequest) this.request = new XMLHttpRequest;
                    else if (window.ActiveXObject) {
                        try { this.request = new ActiveXObject('MSXML2.XMLHTTP'); }
                        catch (e) { this.request = new ActiveXObject('Microsoft.XMLHTTP'); }
                    }
                }
                if (this.request) {
                    this.request.open('GET', 'scripts/'+filename, false); // synchronous request!
                    this.request.send(null);
                    if (this.request.status == 200) {
                        this.globalEval(this.request.responseText);
                        this.loaded[filename] = true;
                    }
                }
            }
        }
    },
 
    globalEval: function(code) {
        if (window.execScript) window.execScript(code, 'javascript');
        else window.eval(code);
    }
}