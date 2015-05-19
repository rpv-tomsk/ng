package NG::MLListSite;

use strict;

use NGService;
use NSecure;
use NG::MLListSingle;
use NG::Rtf;
use Data::Dumper;
use vars qw(@ISA);
@ISA = qw(NG::MLListSingle);

use constant PATH_TO_HTML_FILES => "/htdocs/pages/";

sub getFilenameFromUrl {
    my $filename = shift;
    $filename =~ s/\//\_/gi;
    $filename =~ s/^_+//;
    $filename =~ s/_+$//;
    $filename = "mainpage" if (is_empty($filename));
    $filename .= ".tmpl";
    return $filename;
}

sub config {
};

sub init {
	my $self = shift;
	$self->SUPER::init(@_);
    $self->{_tree_table} = "ng_sitestruct";
	$self->addTreeCatalogFields ([	
		{NAME=>"Полное название",FIELD=>"full_name",TYPE=>"text",IS_NOTNULL=>0},
		{NAME=>"URL suffix",FIELD=>"url",TYPE=>"text"},
		{NAME=>"Шаблон страницы",FIELD=>"template_id",TYPE=>"hidden"},
		{NAME=>"file",FIELD=>"data_file",TYPE=>"hidden"},
		{NAME=>"Конечная нода",FIELD=>"is_reg",TYPE=>"checkbox"},
		{NAME=>"Не добавлять в меню",FIELD=>"notinmenu",TYPE=>"checkbox"},
	]);    
	$self->catalog_formfields("full_name,url,template_id,notinmenu,is_reg,data_file");
	$self->catalog_editfields("full_name,url,notinmenu,is_reg");
    $self->tablename('notable');
    $self->addfields({TYPE=>'id', NAME=>'Код',FIELD=>'id',IS_NOTNULL=>1});	
    
    $self->addCatalogExtraLink("Контент","?action=editcontentform&id={id}",1);
    $self->register_ajaxaction("editcontentform","editContentForm");
    $self->register_ajaxaction("editcontent","editContent");
    $self->register_action('saveimage',"saveImage");
    $self->{_component_image_url} = "";
};

sub saveImage {
	my $self = shift;
	my $q = $self->q();
	my $parent_id=Rtf_get_parent_id($q);
	my $tree = $self->_createTreeObject();
	my $node=$tree->loadNode($parent_id) or die "No node found"; #если нет такой ноды просто умереть
	my $uploadfile=Rtf_get_filename($q);
	if(!defined $uploadfile) {
		Rtf_send_alert(Rtf_get_error());
		exit;
	};
	my $file_name="image$parent_id".time(); #.".".$ext;
	$file_name=Rtf_save_image($self->{_siteroot}."/htdocs/images/",$file_name,$q);
	if(!defined $file_name) {
		Rtf_send_alert("Ошибка загрузки файла");
		exit;
	};
	my $dbh=$self->{_db}->dbh();
	$dbh->do("insert into $tree->{_dbtable}_rtf (page_id,file) values(?,?)",undef,$parent_id,$file_name);  
	Rtf_send_filename("/images/".$file_name);
	exit();  	
};


sub getTemplateId {
	#
};

sub formSettings {
	my $self = shift;
	my $action = shift;
	my $form = shift;
	if ($action eq "insertcatalogform") {
		$form->param("url",$form->getParam("id"));
	};
	
	if ($action eq "updatecatalogform") {
		my $url = $form->getParam("url");
		$url =~ /([^\/]*)\/$/;
		$form->param("url",$1);
	};
};

sub editContentForm {
	my $self = shift;
	my $q = $self->q();
	my $dbh = $self->db()->dbh();
	$self->set_header_nocache();
	my $id = is_valid_id($q->param('id'))?$q->param('id'):undef;
	$self->opentemplate("admin-side/common/universalform.tmpl") || return $self->showError();
	if (defined $id) {
		my $sth = $dbh->prepare("select data_file,template_id,level from $self->{_tree_table} where id=?") or die $DBI::errstr;
		$sth->execute($id) or die $DBI::errstr;
		my ($data_file,$template_id,$level) = $sth->fetchrow();
		$sth->finish();
		my ($css_file,$styles_list);
		if (is_valid_id($template_id)) {
			$sth = $dbh->prepare("select css_file,styles_list from ng_templates where id=?") or die $DBI::errstr;
			$sth->execute($template_id) or die $DBI::errstr;
			($css_file,$styles_list) = $sth->fetchrow();
			$sth->finish();
		};
		
  		my $page_content = Rtf_load_html($self->{_siteroot}.PATH_TO_HTML_FILES.$data_file);
  		
#  		$self->tmpl()->param(
#			langs => $self->getLangs(),
#			current_lang => $self->getLangLetter(),
# 	   		EDIT_PAGE    =>1,
#	   		NODE_ID      =>$id,
# 	   		PAGE_CONTENT =>$page_content,
# 	   		IMAGE_URL => $self->{_component_image_url},
# 	   		STYLES_LIST => $styles_list,
# 	   		CSS_FILE => $css_file,
# 	   		SELECTED_NODE_CANADDPOSITIONS => $self->_canAddPositions($id,$level),
# 	   		SELECTED_NODE_ID => $id
#		);
#		undef ($self->{_tree_object});
    	my $form = NG::Form->new(
	        FORM_URL  => $self->q()->url(),
			KEY_FIELD => "id", # TODO 
    	    DOCROOT   => $self->{_docroot},
	        CGIObject => $self->{_q},
		);
		#$form->setnew();
		$form->param("id",$id);
    	$form->{_ajax} = 1;
		$form->{_form_action} = "editcontent";
    	$form->addfields({TYPE=>"rtf",NAME=>"Контент",FIELD=>"page_content",IS_NOTNULL=>0,CSS_FILE => $css_file,STYLES_LIST => $styles_list,IMAGE_HANDLER => $self->{_component_image_url}});
    	$form->param("page_content",$page_content);
    	$form->{_container} = "catalogdiv".$id;
    	$form->print_to_template($self->tmpl());
	};
	$self->print_template();					
};

sub editContent {
	my $self = shift;
	my $q = $self->q();
	my $dbh = $self->db()->dbh();
	my $id = is_valid_id($q->param('id'))?$q->param('id'):undef;
	if ($id) {
		my $sth = $dbh->prepare("select data_file,url from $self->{_tree_table} where id=?") or die $DBI::errstr;
		$sth->execute($id) or die $DBI::errstr;
		my ($data_file,$url) = $sth->fetchrow();
		$sth->finish();
		if (is_empty($data_file)) {
			$data_file = getFilenameFromUrl($url);
			$dbh->do("update $self->{_tree_table} set data_file=? where id=?",undef,$data_file,$id) or die $DBI::errstr;
		};
		Rtf_save_html($self->{_siteroot}.PATH_TO_HTML_FILES.$data_file,$q->param('page_content')) if ($data_file);		
	};
	$self->redirect_to_referer_or("");
};

sub CatalogPrepareData {
	my $self = shift;
	my $action = shift;
	my $form = shift;
	my $dbh = $self->db()->dbh();
	my $sth = undef;
	my $url = "";

	if ($action eq "insertcatalog") {
		$form->param("template_id",$self->getTemplateId());
		$sth = $dbh->prepare("select url from ".$self->{_tree_table}." where id=?") or die $DBI::errstr;
		$sth->execute($form->getParam("parent_id")) or die $DBI::errstr;
	} elsif ($action eq "updatecatalog") {
		$sth = $dbh->prepare("select s1.url as url from ".$self->{_tree_table}." s1,".$self->{_tree_table}." s2 where s1.id=s2.parent_id and s2.id=?") or die $DBI::errstr;
		$sth->execute($form->getParam("id")) or die $DBI::errstr;
	};
	
	($url) = $sth->fetchrow();
	$sth->finish();
	
	my $fieldurl = $form->getParam("url");
	$form->param("url",$url.$fieldurl."/");
	$form->param("data_file",getFilenameFromUrl($url.$fieldurl."/")) if ($action eq "insertcatalog");
};

sub beforeDeleteCatalog {
	my $self  = shift;
	my $q = $self->q();
	my $id = $q->param("id");
	if (is_valid_id($id)) {
		my $sth = $self->db()->dbh()->prepare("select data_file from ".$self->{_tree_table}." where id=?") or die $DBI::errstr;
		$sth->execute($id) or die $DBI::errstr;
		my ($data_file) = $sth->fetchrow();
		$sth->finish();
		unlink $self->{_siteroot}.PATH_TO_HTML_FILES.$data_file;
	};
};


sub afterInsertUpdateCatalog {
	my $self = shift;
	my $action = shift;
	my $form = shift;
	my $q = $self->q();
	my $dbh = $self->db()->dbh();
	my $id = is_valid_id($q->param("id"))?$q->param("id"):undef;
	my $parent_id = $form->getParam("parent_id");
	my $url = $form->getParam("url");
	
	if (!defined $id) {return undef;};
	
	if ($action eq "insertcatalog") {
		my $sth = $dbh->prepare("select url from $self->{_tree_table} where id=?") or die $DBI::errstr;
		$sth->execute($id) or die $DBI::errstr;
		($url) = $sth->fetchrow();
		$sth->finish();
		my $filename = getFilenameFromUrl($url);
		Rtf_save_html($self->{_siteroot}.PATH_TO_HTML_FILES.$filename,"");
	};
	
	if ($action eq "updatecatalog") {
		my $tree = $self->_createTreeObject();
		$tree->{_fields} .= ",url,data_file";
		$tree->loadtree($id);
   		my $sth_ = $tree->{_db}->dbh()->prepare("update ".$tree->{_dbtable}." set url=? where id=?") or die $DBI::errstr;
   		my $sth_f = $tree->{_db}->dbh()->prepare("update ".$tree->{_dbtable}." set data_file=? where id=?") or die $DBI::errstr;
   		$tree->traverse(
   			sub {
   				my $_tree = shift;
   				my $value = $_tree->getNodeValue();
   				my $parent = $_tree->getParent();
   				if ($_tree->{_id} != $id) {
   					my $parent_value = $parent->getNodeValue();
    				my $parent_url = $parent_value->{url};
   					$value->{url} =~ s/.*\/([^\/]+\/)$/$parent_url$1/;
   					$sth_->execute($value->{url},$_tree->{_id}) or die $DBI::errstr;
   				};
   				if (!is_empty($value->{data_file})) {
					my $filename = getFilenameFromUrl($value->{url});
					rename $self->{_siteroot}.PATH_TO_HTML_FILES.$value->{data_file},$self->{_siteroot}.PATH_TO_HTML_FILES.$filename;
    				$sth_f->execute($filename,$_tree->{_id});
    			};
	    	}
    	);
    	$sth_->finish();
    	$sth_f->finish()		   		
	};
	
};