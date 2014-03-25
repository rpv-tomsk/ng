function newsConfig(tparams)
{
  tparams['content_css']="/style/rtf.css",
  tparams['theme_advanced_styles']="light=light",
  tparams['theme_advanced_buttons1']="newdocument,styleselect,formatselect,justifyleft,justifycenter,justifyright,justifyfull,bullist,numlist,undo,redo,link,unlink,image,code,removeformat";
  tparams['template_external_list_url']="/admin-side/js/templates_list.js";   
  tparams['theme_advanced_buttons2']="tablecontrols,template";
  tinyMCE.init(tparams);
};