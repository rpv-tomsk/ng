
//Картинки
function MM_swapImgRestore() { //v3.0
  var i,x,a=document.MM_sr; for(i=0;a&&i<a.length&&(x=a[i])&&x.oSrc;i++) x.src=x.oSrc;
}

function MM_preloadImages() { //v3.0
  var d=document; if(d.images){ if(!d.MM_p) d.MM_p=new Array();
    var i,j=d.MM_p.length,a=MM_preloadImages.arguments; for(i=0; i<a.length; i++)
    if (a[i].indexOf("#")!=0){ d.MM_p[j]=new Image; d.MM_p[j++].src=a[i];}}
}

function MM_findObj(n, d) { //v4.01
  var p,i,x;  if(!d) d=document; if((p=n.indexOf("?"))>0&&parent.frames.length) {
    d=parent.frames[n.substring(p+1)].document; n=n.substring(0,p);}
  if(!(x=d[n])&&d.all) x=d.all[n]; for (i=0;!x&&i<d.forms.length;i++) x=d.forms[i][n];
  for(i=0;!x&&d.layers&&i<d.layers.length;i++) x=MM_findObj(n,d.layers[i].document);
  if(!x && d.getElementById) x=d.getElementById(n); return x;
}

function MM_swapImage() { //v3.0
  var i,j=0,x,a=MM_swapImage.arguments; document.MM_sr=new Array; for(i=0;i<(a.length-2);i+=3)
   if ((x=MM_findObj(a[i]))!=null){document.MM_sr[j++]=x; if(!x.oSrc) x.oSrc=x.src; x.src=a[i+2];}
}


//Переключатели табов с деревьями слева
function en_c(pageid,moduleid) {
    ajax_url(
        '/admin-side/?_left=struct&_ajax=1&_pageid='+pageid,
        'middle_left_tree',
        function() {
            document.getElementById('left_s').className="active_left";
            document.getElementById('right_s').className="active_right";
            document.getElementById('s').className="active";
            document.getElementById('left_m').className="no-active_left";
            document.getElementById('right_m').className="no-active_right";
            document.getElementById('m').className="no-active";
            document.getElementById('m').innerHTML = '<a href="/admin-side/?_left=content" onclick="return en_s('+"'"+pageid+"','"+moduleid+"'"+');">Модули сайта</a>';
            document.getElementById('s').innerHTML = '<p>Структура сайта</p>';
        }
    ); 
    return false;
};

function en_s(pageid,moduleid) {
    ajax_url(
        '/admin-side/?_left=content&_ajax=1&_moduleid='+moduleid,
        'middle_left_tree',
        function(){
            document.getElementById('left_m').className="active_left";
            document.getElementById('right_m').className="active_right";
            document.getElementById('m').className="active";
            document.getElementById('left_s').className="no-active_left";
            document.getElementById('right_s').className="no-active_right";
            document.getElementById('s').className="no-active";
            document.getElementById('m').innerHTML = '<p>Модули сайта</p>';
            document.getElementById('s').innerHTML = '<a href="/admin-side/?_left=struct" onclick="return en_c('+"'"+pageid+"','"+moduleid+"'"+');">Структура сайта</a>';
        }
    );
    return false;		
};

//Поддержка rtf-редакторов в универсальных формах
var NgEditors = {};
function CloseEditors(tparentid) {
    var elem = NgEditors[tparentid];
    if (!elem) {
        return;
    };

    for (e in elem) {
        tinyMCE.remove(tinyMCE.get(elem[e]));
    };
    NgEditors[tparentid] = Array();
};
		
function UseEditor(tname,thandler,tparentid,tconfig) {
    var elem = NgEditors[tparentid];
    if (!elem) {
        elem = NgEditors[tparentid] = Array();
    }
    elem.push(tname);
    
    
    //конфигурация по умолчанию
    params={
        theme : "advanced",
        language : "ru",
        theme_advanced_toolbar_location : "top",
        theme_advanced_toolbar_align : "left",
        mode : "exact",
        elements: tname,
        plugins : "table,advimage,advlink,preview,print,searchreplace,contextmenu,paste,template",
        plugin_preview_width : "600",
        convert_urls : false,
        relative_urls : true,  
        plugin_preview_height : "400",
        theme_advanced_buttons1: "newdocument,pasteword,formatselect,bold,italic,underline,justifyleft,justifycenter,justifyright,justifyfull,bullist,numlist,undo,redo,link,unlink,image,code,removeformat",
        theme_advanced_buttons2: "tablecontrols",
        theme_advanced_buttons3: "",
        theme_advanced_statusbar_location : "bottom",
        theme_advanced_resizing : true,
        theme_advanced_resize_horizontal : false,
        theme_advanced_image_processURL : thandler,
        theme_advanced_image_parentid : tparentid,
        extended_valid_elements :"a[name|href|target|title|onclick],img[class|src|border=0|alt|title|hspace|vspace|width|height|align|onmouseover|onmouseout|name|style],font[face|size|color|style],span[class|align|style],br[clear]",
        theme_advanced_blockformats : "h1,h2"
        //content_css : css_file,
    };  
    if (tconfig) {
        tconfig(params);
    }
    else {
        tinyMCE.init(params);
    };
}; 

$.fn.initClickableCheckboxes = function(options) {
    return this.each(function() {
        var wrapper = $(this);
        var checkboxes = wrapper.find('div.list-checkbox.clickable');
        checkboxes.each(function(){
            var checkbox = $(this);
            checkbox.click(function() {
                var data = {
                    field: checkbox.attr('data-field'),
                    id:    checkbox.attr('data-id'),
                    action: 'checkboxclick',
                    _ajax: 'json'
                };
                data.checked = !checkbox.hasClass('checked');
                $.ajax({
                    url: options.url,
                    data: data,
                    type: 'POST',
                    dataType: 'json',
                    success: function(obj) {
                        if (obj.status == 'ok') {
                            if (obj.checked)
                                checkbox.addClass('checked')
                            else
                                checkbox.removeClass('checked');
                        };
                        if (obj.status == 'error') {
                            alert(obj.error);
                        };
                    }
                });
                //$(this).toggleClass('checked');
                //checkbox.toggleClass('checked');
            });
        });
    });
};
$.fn.initMultiactionCheckboxes = function(options) {
    var wrapper = $(this);
    var checkboxes = wrapper.find('div.list-multiactioncb');
    
    var panel = $("div.list-multiaction-panel");
    var select = panel.find('select[name=mult_op]');
    var btn    = panel.find("div.button");
    
    for (var i = 0; i < options.actions.length; i++) {
        var action = options.actions[i];
        var newOption = $('<option value="'+action.action+'">'+action.name+'</option>');
        newOption.data('action',action);
        select.append(newOption);
    };
    
    btn.click(function(){
        var idStack = [],
            selectedOption = select.find('option:selected'),
            confirmed = 0;
            
        if (!selectedOption) {
            return;
        };
        var action = selectedOption.data('action')
        if (!action) {
            return;
        };
        
        checkboxes.filter('.checked').each(function() {
            idStack.push($(this).attr('data-id'));
        });
        if (!idStack.length) {
            return;
        };
        
        if (action.skipconfirm) {
            confirmed = 1;
        }
        else {
            var confirmText = 'Вы действительно хотите выполнить действие "'+action.name+'" ?';
            if (action.confirmText) {
                confirmText = action.confirmText;
            };
            confirmed = confirm(confirmText);
        };
        if (!confirmed) {
            return;
        };
        var data = {
            action: 'multiaction',
            multiaction: action.action,
            id: idStack.join(),
            _ajax: 'json'
        };
        $.ajax({
            type: "POST",
            url: options.url,
            data: data,
            dataType: "json",
            success: function(obj) {
                if (obj.status == 'ok') {
                    $('#middle_right_content').load(options.thispage);
                };
                if (obj.status == 'error') {
                    alert(obj.error);
                    $('#middle_right_content').load(options.thispage);
                };
            }
        });
        return false;
    });

    return this.each(function() {
        //toggle-all checkboxes
        var toggleallcb = wrapper.find('div.list-multiactioncb-all');
        toggleallcb.each(function(){
            var checkbox = $(this);
            checkbox.click(function() {
                toggleallcb.toggleClass('checked');
                var checkboxes = wrapper.find('div.list-multiactioncb');
                if (checkbox.hasClass('checked')) {
                    checkboxes.addClass('checked');
                    checkboxes.closest('tr').addClass('checked');
                }
                else {
                    checkboxes.removeClass('checked');
                    checkboxes.closest('tr').removeClass('checked');
                };
            });
        });
        //row checkboxes
        checkboxes.each(function(){
            var checkbox = $(this);
            checkbox.click(function() {
                checkbox.toggleClass('checked');
                if (checkbox.hasClass('checked')) {
                    checkbox.closest('tr').addClass('checked');
                }
                else {
                    checkbox.closest('tr').removeClass('checked');
                };
            });
        });
    });
};
