$(document).ready(function(){

$('.icon-item').live('mouseenter',
  function (e) {
    e.preventDefault();
    if ($(this).hasClass('active')){
      $(this).addClass('active-hover');
    }else{
      $(this).addClass('hover');
    }
  });
$('.icon-item').live('mouseleave',
  function (e) {
    e.preventDefault();
    if ($(this).hasClass('active')){
      $(this).removeClass('active-hover');
    }else{
      $(this).removeClass('hover');
    }
  });

var intervalID;
$('.icon-item-smiles').live('click',
  function (e) {
    e.preventDefault();
    var id = $(this).attr('name');
    intervalID=setTimeout(
      function() {
        openSmileContainer(id);
      }, 100);
  });
$('.editor').live('mouseleave',
  function (e) {
    e.preventDefault();
    var id = $(this).find('.icon-item-smiles').attr('name');
    closeSmileContainer(id);
    clearInterval(intervalID);
  });
$('.smiles-container a').live('click', function(e){
  e.preventDefault();
  var id = $(this).parent().parent().parent().attr('id');
  closeSmileContainer(id);
});
$('.icon-item').live('click', function(e){
  e.preventDefault();
  var id = $(this).parent().parent().find('.icon-item-smiles').attr('name');
  closeSmileContainer(id);
});


$('.icon-item').live('click', function(e){
  e.preventDefault();
  //if ($(this).find('span.icon-addLink').length == 1) { alert('Добавить ссылку!'); return false; }
  //if ($(this).find('span.icon-addPicture').length == 1) { alert('Добавить картинку!'); return false; }
      if( $(this).hasClass('active')){
        $(this).removeClass('active').removeClass('active-hover');
      }else{
        //$(this).addClass('active').addClass('active-hover');
      }
});

});

function openSmileContainer(id){
  $('#'+id).slideDown('swing');
}
function closeSmileContainer(id){
  $('#'+id).slideUp('swing');
}



var editors = {};
var editor_sequence = 1;

function editor(textarea, param) {
    this.textarea = textarea;
    this.index = editor_sequence;
    this.options = {
        smileys_path: "/js/forum/editor/smileys/"
    };
    editor_sequence++; 
    if (typeof(param) != "undefined") {
        for (var i in this.options) {
            if (typeof(param[i]) != "undefined") this.options[i] = param[i];
        };
    };
    editors[this.index] = this;
    this.show_panel();
//     $(this.textarea).blur(function() {
//         this.
//     });
};

editor.prototype.show_panel = function() {
    var ta = $(this.textarea);
    var index = this.index;
    var editor_code = '<div class="textEditorControls">' +
                      '<span class="icons-group">' +
                      '<a href="#" class="icon-item" title="Bold Trigger" editor="'+index+'" action="bold"><span class="icon-bold">Bold Trigger</span></a>' +
                      '<a href="#" class="icon-item" title="Italic Trigger" editor="'+index+'" action="italic"><span class="icon-italic">Italic Trigger</span></a>' +
                      '<a href="#" class="icon-item" title="Underline Trigger" editor="'+index+'" action="underline"><span class="icon-underline">Underline Trigger</span></a>' +
                      '</span>' +
                      '<span class="icons-group">' +
                      '<a href="#" class="icon-item" title="Add Link Trigger" editor="'+index+'" action="add_link"><span class="icon-addLink">Add Link Trigger</span></a>' +
                      '<a href="#" class="icon-item" title="Add Picture Trigger" editor="'+index+'" action="add_image"><span class="icon-addPicture">Add Picture Trigger</span></a>' +
                      '</span>' +
                      '<span class="icons-group">' +
                      '<a href="#" class="icon-item" title="Add Quote Trigger" editor="'+index+'" action="cite"><span class="icon-quotation">Add Quote Trigger</span></a>' +
                      '</span>' +
                      '<span class="icons-group">' +
                      '<a href="#" class="icon-item icon-item-smiles" name="smileContainer1" title="Add Link Trigger"><span class="icon-smile">Add Smile Trigger<img src="'+this.options.smileys_path+'11.gif" width="20px" height="20px"></span></a>' +
                      '<div class="smiles-container" id="smileContainer1">' +
                      '<ul>' +
                      '<li><a href="#" editor="'+index+'" smiley="1"><img src="'+this.options.smileys_path+'11.gif" alt="O=)" width="27px" height="23px" /></a></li>' +
                      '<li><a href="#" editor="'+index+'" smiley="1"><img src="'+this.options.smileys_path+'12.gif" alt=":-)" width="20px" height="24px" /></a></li>' +
                      '<li><a href="#" editor="'+index+'" smiley="1"><img src="'+this.options.smileys_path+'13.gif" alt=":-(" width="20px" height="24px" /></a></li>' +
                      '<li><a href="#" editor="'+index+'" smiley="1"><img src="'+this.options.smileys_path+'14.gif" alt=";-)" width="20px" height="20px" /></a></li>' +
                      '<li><a href="#" editor="'+index+'" smiley="1"><img src="'+this.options.smileys_path+'15.gif" alt=":-P" width="18px" height="18px" /></a></li>' +
                      '<li><a href="#" editor="'+index+'" smiley="1"><img src="'+this.options.smileys_path+'16.gif" alt="8-)" width="21px" height="21px" /></a></li>' +
                      '<li><a href="#" editor="'+index+'" smiley="1"><img src="'+this.options.smileys_path+'17.gif" alt=":-D" width="20px" height="20px" /></a></li>' +
                      '<li><a href="#" editor="'+index+'" smiley="1"><img src="'+this.options.smileys_path+'18.gif" alt=":-[" width="25px" height="25px" /></a></li>' +
                      '<li><a href="#" editor="'+index+'" smiley="1"><img src="'+this.options.smileys_path+'19.gif" alt="=-O" width="20px" height="20px" /></a></li>' +
                      '<li><a href="#" editor="'+index+'" smiley="1"><img src="'+this.options.smileys_path+'20.gif" alt=":-*" width="34px" height="23px" /></a></li>' +
                      '<li><a href="#" editor="'+index+'" smiley="1"><img src="'+this.options.smileys_path+'21.gif" alt=":\'(" width="31px" height="22px" /></a></li>' +
                      '<li><a href="#" editor="'+index+'" smiley="1"><img src="'+this.options.smileys_path+'22.gif" alt=":-X" width="22px" height="26px" /></a></li>' +
                      '<li><a href="#" editor="'+index+'" smiley="1"><img src="'+this.options.smileys_path+'23.gif" alt=">:o" width="36px" height="27px" /></a></li>' +
                      '<li><a href="#" editor="'+index+'" smiley="1"><img src="'+this.options.smileys_path+'24.gif" alt=":-|" width="29px" height="23px" /></a></li>' +
                      '<li><a href="#" editor="'+index+'" smiley="1"><img src="'+this.options.smileys_path+'25.gif" alt=":-/" width="28px" height="28px" /></a></li>' +
                      '<li><a href="#" editor="'+index+'" smiley="1"><img src="'+this.options.smileys_path+'26.gif" alt="*JOKINGLY*" width="25px" height="25px" /></a></li>' +
                      '<li><a href="#" editor="'+index+'" smiley="1"><img src="'+this.options.smileys_path+'27.gif" alt="]:->" width="39px" height="34px" /></a></li>' +
                      '<li><a href="#" editor="'+index+'" smiley="1"><img src="'+this.options.smileys_path+'28.gif" alt="[:-}" width="28px" height="25px" /></a></li>' +
                      '<li><a href="#" editor="'+index+'" smiley="1"><img src="'+this.options.smileys_path+'29.gif" alt="*KISSED*" width="23px" height="26px" /></a></li>' +
                      '<li><a href="#" editor="'+index+'" smiley="1"><img src="'+this.options.smileys_path+'30.gif" alt=":-!" width="21px" height="21px" /></a></li>' +
                      '<li><a href="#" editor="'+index+'" smiley="1"><img src="'+this.options.smileys_path+'31.gif" alt="*TIRED*" width="26px" height="22px" /></a></li>' +
                      '<li><a href="#" editor="'+index+'" smiley="1"><img src="'+this.options.smileys_path+'32.gif" alt="*STOP*" width="36px" height="23px" /></a></li>' +
                      '<li><a href="#" editor="'+index+'" smiley="1"><img src="'+this.options.smileys_path+'33.gif" alt="*KISSING*" width="47px" height="24px" /></a></li>' +
                      '<li><a href="#" editor="'+index+'" smiley="1"><img src="'+this.options.smileys_path+'34.gif" alt="@}->--" width="30px" height="26px" /></a></li>' +
                      '<li><a href="#" editor="'+index+'" smiley="1"><img src="'+this.options.smileys_path+'35.gif" alt="*THUMBS UP*" width="26px" height="23px" /></a></li>' +
                      '<li><a href="#" editor="'+index+'" smiley="1"><img src="'+this.options.smileys_path+'36.gif" alt="*DRINK*" width="51px" height="28px" /></a></li>' +
                      '<li><a href="#" editor="'+index+'" smiley="1"><img src="'+this.options.smileys_path+'37.gif" alt="*IN LOVE*" width="20px" height="20px" /></a></li>' +
                      '<li><a href="#" editor="'+index+'" smiley="1"><img src="'+this.options.smileys_path+'38.gif" alt="@=" width="28px" height="24px" /></a></li>' +
                      '<li><a href="#" editor="'+index+'" smiley="1"><img src="'+this.options.smileys_path+'39.gif" alt="*HELP*" width="30px" height="33px" /></a></li>' +
                      '<li><a href="#" editor="'+index+'" smiley="1"><img src="'+this.options.smileys_path+'40.gif" alt="\\m/" width="35px" height="26px" /></a></li>' +
                      '<li><a href="#" editor="'+index+'" smiley="1"><img src="'+this.options.smileys_path+'41.gif" alt="%)" width="20px" height="24px" /></a></li>' +
                      '<li><a href="#" editor="'+index+'" smiley="1"><img src="'+this.options.smileys_path+'42.gif" alt="*OK*" width="40px" height="26px" /></a></li>' +
                      '<li><a href="#" editor="'+index+'" smiley="1"><img src="'+this.options.smileys_path+'43.gif" alt="*WASSUP*,*SUP*" width="28px" height="25px" /></a></li>' +
                      '<li><a href="#" editor="'+index+'" smiley="1"><img src="'+this.options.smileys_path+'44.gif" alt="*SORRY*" width="24px" height="22px" /></a></li>' +
                      '<li><a href="#" editor="'+index+'" smiley="1"><img src="'+this.options.smileys_path+'45.gif" alt="*BRAVO*" width="40px" height="27px" /></a></li>' +
                      '<li><a href="#" editor="'+index+'" smiley="1"><img src="'+this.options.smileys_path+'46.gif" alt="*ROFL*" width="29px" height="25px" /></a></li>' +
                      '<li><a href="#" editor="'+index+'" smiley="1"><img src="'+this.options.smileys_path+'47.gif" alt="*PARDON*" width="36px" height="26px" /></a></li>' +
                      '<li><a href="#" editor="'+index+'" smiley="1"><img src="'+this.options.smileys_path+'48.gif" alt="*NO*" width="36px" height="26px" /></a></li>' +
                      '<li><a href="#" editor="'+index+'" smiley="1"><img src="'+this.options.smileys_path+'49.gif" alt="*CRAZY*" width="20px" height="27px" /></a></li>' +
                      '<li><a href="#" editor="'+index+'" smiley="1"><img src="'+this.options.smileys_path+'50.gif" alt="*DONT_KNOW*" width="32px" height="20px" /></a></li>' +
                      '<li><a href="#" editor="'+index+'" smiley="1"><img src="'+this.options.smileys_path+'51.gif" alt="*DANCE*" width="39px" height="26px" /></a></li>' +
                      '<li><a href="#" editor="'+index+'" smiley="1"><img src="'+this.options.smileys_path+'52.gif" alt="*YAHOO*" width="42px" height="27px" /></a></li>' +
                      '<li><a href="#" editor="'+index+'" smiley="1"><img src="'+this.options.smileys_path+'53.gif" alt="*HI*" width="43px" height="27px" /></a></li>' +
                      '<li><a href="#" editor="'+index+'" smiley="1"><img src="'+this.options.smileys_path+'54.gif" alt="*BYE*" width="29px" height="24px" /></a></li>' +
                      '<li><a href="#" editor="'+index+'" smiley="1"><img src="'+this.options.smileys_path+'55.gif" alt="*YES*" width="20px" height="24px" /></a></li>' +
                      '<li><a href="#" editor="'+index+'" smiley="1"><img src="'+this.options.smileys_path+'56.gif" alt=";D" width="27px" height="24px" /></a></li>' +
                      '<li><a href="#" editor="'+index+'" smiley="1"><img src="'+this.options.smileys_path+'57.gif" alt="*WALL*" width="51px" height="26px" /></a></li>' +
                      '<li><a href="#" editor="'+index+'" smiley="1"><img src="'+this.options.smileys_path+'58.gif" alt="*WRITE*" width="36px" height="26px" /></a></li>' +
                      '<li><a href="#" editor="'+index+'" smiley="1"><img src="'+this.options.smileys_path+'59.gif" alt="*SCRATCH*" width="27px" height="24px" /></a></li>' +
                      '</ul>' +
                      '</div>' +
                      '</span>' +
                      '</div>';
    var editor = $(editor_code);
    var width = ta.css("width");
    editor.css("width", width);
    editor.insertBefore(ta);

    $('.textEditorControls a[editor="'+index+'"]').click(function(e) {
        e.preventDefault();
        var elem = $(this);
        var action = elem.attr("action");
        if (action) {
            editor_action(action, elem.attr("editor"));
        };
    });
    
    $('.textEditorControls a[smiley="1"]').click(function(e) {
        e.preventDefault();
        var smiley = $(this).find("img").attr("alt");
        var index = $(this).attr("editor");
        editor_smiley(index, smiley);
    });
};                            


editor.prototype.do_bold = function() {
    this.replace_selection_with_tag("B");
};

editor.prototype.do_italic = function() {
    this.replace_selection_with_tag("I");
};

editor.prototype.do_cite = function() {
    this.replace_selection_with_tag("CITE");
};

editor.prototype.do_underline = function() {
    this.replace_selection_with_tag("U");
};

editor.prototype.do_add_link = function() {
    var url = prompt("URL", "http://");
    if (url) {
        this.replace_selection_with_tag("LINK", {HREF: url});
    };
};

editor.prototype.do_add_image = function() {
    var url = prompt("Image URL", "http://");
    if (url) {
        this.replace_selection_with_tag("IMAGE", {SRC: url}, 1);
    };
};

editor.prototype.add_text = function(text) {
    var ta = $(this.textarea);
    var start_selection = this.textarea.selectionStart;
    var end_selection = this.textarea.selectionEnd;
    var value = ta.val();   
    var str1 = value.substr(0, start_selection);
    var str3 = value.substr(end_selection);
    ta.val(str1 + text + str3);         
};

editor.prototype.replace_selection_with_tag = function(tag, params, without_close_tag) {
    var ta = $(this.textarea);
    var str1="";
    var str2="";
    var str3="";
    var value="";
    var start_selection = 0;
    var end_selection = 0;
    
//     if (window.getSelection) {
//         str2 = window.getSelection().toString();
//     } else if (document.getSelection) {
//         str2 = document.getSelection();
//     } else if (document.selection) {
//         str2 = document.selection.createRange().text;
//     }      
    if (typeof(this.textarea.selectionStart) != "undefined") {
        start_selection = this.textarea.selectionStart;
        end_selection = this.textarea.selectionEnd;
    };    
    value = ta.val();
    str1 = value.substr(0, start_selection);
    str2 = value.substr(start_selection, (end_selection-start_selection));
    str3 = value.substr(end_selection);
    var params_string = "";
    
    if (typeof params != undefined) {
        for (var param in params) {
            params_string = " "+param+"=\""+params[param]+"\"";    
        };
    };
    
    if (typeof without_close_tag != undefined && without_close_tag == 1) {
        ta.val(str1 + "["+tag+params_string+"/]"+str2+str3);
    }
    else {
        ta.val(str1 + "["+tag+params_string+"]"+str2+"[/"+tag+"]"+str3);
    };
    ta.focus();
};

function editor_action(action, index) {
    var editor = editors[index];
    if (editor) {
        
        if (action == "bold") {
            editor.do_bold();
        }
        else if (action == "italic") {
            editor.do_italic();
        }
        else if (action == "underline") {
            editor.do_underline();
        }
        else if (action == "cite") {
            editor.do_cite();
        }
        else if (action == "add_link") {
            editor.do_add_link();
        }
        else if (action == "add_image") {
            editor.do_add_image();
        };
    };
};


function editor_smiley (index, smiley) {
    var editor = editors[index];
    editor.add_text(smiley);    
};

