function ge (id)
{
	return document.getElementById(id);
};

/*
url-loading object and a request queue built on top of it
*/

/* namespacing object */
var net=new Object();

net.READY_STATE_UNINITIALIZED=0;
net.READY_STATE_LOADING=1;
net.READY_STATE_LOADED=2;
net.READY_STATE_INTERACTIVE=3;
net.READY_STATE_COMPLETE=4;


/*--- content loader object for cross-browser requests ---*/
net.ContentLoader=function(url,onload,fparams,method,params,contentType){
  this.req=null;
  this.fparams=fparams;
  this.onload=onload;
  //this.onerror=(onerror) ? onerror : this.defaultError;
  this.onerror = this.defaultError;
  this.loadXMLDoc(url,method,params,contentType);
}

net.ContentLoader.prototype.loadXMLDoc=function(url,method,params,contentType){
  if (!method){
    method="GET";
  }
  if (!contentType && method=="POST"){
    contentType='application/x-www-form-urlencoded';
  }
  if (window.XMLHttpRequest){
    this.req=new XMLHttpRequest();
  } else if (window.ActiveXObject){
    this.req=new ActiveXObject("Microsoft.XMLHTTP");
  }
  if (this.req){
    try{
      var loader=this;
      this.req.onreadystatechange=function(){
        net.ContentLoader.onReadyState.call(loader);
      }
      this.req.open(method,url,true);
      if (contentType){
        this.req.setRequestHeader('Content-Type', contentType);
        //this.req.setRequestHeader("Content-Type","multipart/form-data"); 
      }
      this.req.send(params);
    }catch (err){
      this.onerror.call(this);
    }
  }
}


net.ContentLoader.onReadyState=function(){
  var req=this.req;
  var ready=req.readyState;
  if (ready==net.READY_STATE_COMPLETE){
    var httpStatus=req.status;
    if (httpStatus==200 || httpStatus==0){
      this.onload.call(this,this.fparams);
    }else{
      this.onerror.call(this);
    }
  }
}

net.ContentLoader.prototype.defaultError=function(){
  alert("error fetching data!"
    +"\n\nreadyState:"+this.req.readyState
    +"\nstatus: "+this.req.status
    +"\nheaders: "+this.req.getAllResponseHeaders()
     +"\ncontent: "+this.req.responseText);
}



function prepare_post(dataarray)
{
	// important!!! data come in script in utf-8
	var ajax_post = "";
	for (i=0;i<dataarray.length;i++)
	{
		ajax_post += dataarray[i].parametr+"="+encodeURIComponent(dataarray[i].value)+'&';
	};
	return ajax_post;
};

function ajax_url (url,blockId,onLoad) {
	var params = new Array(2);
	params[0] = blockId;
	params[1] = onLoad;
    re = /\?/;
    if (re.test(url)) {
        url = url + '&random='+Math.random();
    }
    else {
        url = url + '?random='+Math.random();
    }; 
	new net.ContentLoader(url,putResponseToBlock,params,'GET');
};

function putResponseToBlock(params){
	var response = this.req.responseText;
	var id = params[0];
	var onLoad = params[1];
	if (response.indexOf('redirect:') != -1) {
		response = response.replace('redirect:','');
		redirect(response);
	}
	else {
		var elem = ge(id);
		if (elem) {
	        //elem.innerHTML = response;
    	    JsExecute(response,id);
		}
		else {
		  alert('AJAX error: target block not found');
		};
	};
	if (onLoad) {
		onLoad.call(this);
	}
};

function JsExecute(text,block) {
    text = ' '+text+' ';
    document.getElementById(block).innerHTML = text;
    var rer = /\r|\n/gi;
    text.replace(rer," ");
    var ScriptRE = /\<\/?script[^\>]*\>/im;
    var UseEditorRE = /UseEditor\(/g;

    var codearray = text.split(ScriptRE);
    if (codearray.length<3)
        return;
        
    for (i=1;i<codearray.length;i=i+2) {
        if (UseEditorRE.test(codearray[i])) {
            //Special dirty hack for TinyMCE in FF (Editor iframe shows only on first form opened on page)
            eval(codearray[i]);
        }
        else {
            jQuery.globalEval( codearray[i] );
        };
    };
};

function zeroprefix(len,values) {
	var str = values + "";
	addzero = len - str.length;
	for (var i=0;i<addzero;i++) {
		str = "0"+str;
	};
	return str;
};

function ajax_form (id,resid)
{
	var data = new Array();
	count = 0;
	for (i=0;i<ge(id).elements.length;i++)
	{
		if (ge(id).elements[i].type == "checkbox" && !ge(id).elements[i].checked)
		{
			continue;
		};
		if (ge(id).elements[i].type == "radio" && !ge(id).elements[i].checked)
		{
			continue;
		};		
		data[count] = {parametr:ge(id).elements[i].name,value:ge(id).elements[i].value};
		count++;
	};
	var action = ge(id).action;

	if (ge(id).method == 'get' || ge(id).method == 'GET') {
		re = /\?/;
		if (re.test(action)) {
			action = action +'&'+ prepare_post(data);
		}
		else {
			action = action +'?'+ prepare_post(data);
		};
		
	};
	new net.ContentLoader(action,ajax_from_frame_to_block,(resid),ge(id).method,prepare_post(data));
};

function ajax_from_frame_to_block(id)
{
var response = this.req.responseText;
  
 
	//alert(response);
	if (response.indexOf('redirect:') != -1)
	{
		response = response.replace('redirect:','');
		window.location.href=response;
	}
	else {
		//	alert('qweqweqwe');
		ge(id).innerHTML = response;
	}
};

function clear_block (id)
{
	ge(id).innerHTML = '';
};

function redirect(url)
{
	window.location = url;
};

function ShowPreview (img,preview)
{
	ge(preview).src = ge(img).value;
	ge(preview).style.display = "block";
};

function PostForm(formObj,block_id,frame_id) {
	var identified = 'ifr_'+formObj.id+'_'+block_id+'_'+Math.random(1000);
	if (frame_id != "") {
		identified = frame_id;
	};
	var divid = "div_"+identified;
	var iframeEl;
	var deleteid = "";

	div = document.createElement('div');
	div.setAttribute('id',divid)
	deleteid = divid;
	div.innerHTML = '<iframe name="'+identified+'" id="'+identified+'" onload="getContentFromIframe(\''+identified+'\',\''+block_id+'\',\''+deleteid+'\')"></iframe>';
	document.body.appendChild(div);		
	iframeEl = document.getElementById(identified);
		

	formObj.setAttribute('target',iframeEl.getAttribute('name'));
	formObj.submit();
};

function getContentFromIframe(iframe_id,block_id,deleteid) {
	var iFrame = document.getElementById(iframe_id);
	iFrame.onload = "";
	var html = "";
	if (iFrame.contentDocument) {
		docObj = iFrame.contentDocument;
		html = docObj.body.innerHTML;
	} else {
		docObj = iFrame.contentWindow.document;
		html = docObj.body.innerHTML;
	}	
	document.getElementById(deleteid).parentNode.removeChild(document.getElementById(deleteid));
	JsExecute(html,block_id);
};
