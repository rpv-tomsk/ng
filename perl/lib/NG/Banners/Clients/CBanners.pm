package NG::Banners::Clients::CBanners;
use strict;

use NGService;
use NSecure;
#use Image::ExifTool ':Public';
use Data::Dumper;

use vars qw(@ISA);

sub AdminMode {
    use NG::Module::List;
    @ISA = qw(NG::Module::List);
};


sub getUploadDir
{
 my $self=shift;
 return "upload/banners/";
};
sub config 
{
 my $self = shift;
 $self->tablename('banners');
 # ����� �����
 $self->fields(
               {FIELD=>'id',       TYPE =>'id',       NAME =>'���',                   IS_NOTNULL=>1},
               {FIELD=>'cid',      TYPE =>'fkparent', NAME =>'��� �������',           IS_NOTNULL=>1},
               {FIELD=>'name',     TYPE =>'text',     NAME =>'��������',              IS_NOTNULL=>1, WIDTH=>"70%"},
               {FIELD=>'alt',      TYPE =>'text',     NAME =>'�������������� �����',  IS_NOTNULL=>0},
               {FIELD=>'target',   TYPE =>'text',     NAME =>'������',                IS_NOTNULL=>0},
               {FIELD=>'sizex',    TYPE =>'text',     NAME =>'�� �����������',        IS_NOTNULL=>0, WIDTH=>"15%"},
               {FIELD=>'sizey',    TYPE =>'text',     NAME =>'�� ���������',          IS_NOTNULL=>0, WIDTH=>"15%"},
               {FIELD=>'file',     TYPE =>'image',    NAME =>'���� �������',          IS_NOTNULL=>0, UPLOADDIR=>$self->getUploadDir()},
               {FIELD=>'text',     TYPE =>'textarea', NAME =>'��������� ������',      IS_NOTNULL=>0},
               {FIELD=>'is_flash', TYPE =>'checkbox', NAME =>'����',                  IS_NOTNULL=>0},
               {FIELD=>'is_text',  TYPE =>'checkbox', NAME =>'�����',                 IS_NOTNULL=>0},
               {FIELD=>'moderated',TYPE =>'checkbox', NAME =>'��������� �����������', IS_NOTNULL=>0}
              );
    
    
    #$self->filter(
    #              NAME   => "",
    #              FIELD  => "moderated",
    #              VALUES =>[
    #                        {NAME=>"��� ������", WHERE=>""},
    #                        {NAME=>"�����������",VALUE=>1},
    #                        {NAME=>"�� �����������",VALUE=>0},
    #                       ],
    #              );
    # ���������
    $self->listfields([
                       {FIELD => 'name'},
                       {FIELD => 'sizex'},
                       {FIELD => 'sizey'},
                      ]);
    # �������� �����
    $self->formfields(
                      {FIELD => 'id'},
                      {FIELD => 'name'},
                      {FIELD => 'target'},
                      {FIELD => 'alt'},
                      {FIELD => 'file'},
                      {FIELD => 'text'},
                      {FIELD => 'sizex'},
                      {FIELD => 'sizey'}
                     );
my $url=$self->getBaseURL();
my $cid=is_valid_id($self->q()->param('cid'))?$self->q()->param('cid'):(is_valid_id($self->getParamFromUrl())?$self->getParamFromUrl():0);
$url=$self-> getURLWithParams($url."$cid/cbanners/","id={id}","action=showbanner");
$self->add_links("������",$url,1);
$self->register_action("showbanner","showBanner");                     
};

sub getParamFromUrl
{
 my $self=shift;
 my $url=$self->q()->url(-absolute=>1);
 $url=~/(\d+)$/;
 return $1;
};

sub showBanner
{
 my $self=shift;
 my $action=shift;
 my $is_ajax=shift;
 my $q=$self->q();
 my $id=(is_valid_id($q->param('id')))?$q->param('id'):0;
 my $ref=$q->param('ref');
 my $htmlCode="��������, �� ������ �� ������.";
 my $sql="select id,cid,name,sizex,sizey,target,file,text,is_flash,is_text,alt from banners where id=?"; 
 
 my $sth=$self->db()->dbh()->prepare($sql) or return $self->setError($DBI::errstr);
 $sth->execute($id) or return $self->setError($DBI::errstr); 
 my $result=$sth->fetchrow_hashref();
 $sth->finish();
 
 if(is_valid_id($result->{'id'}))
   {
   	$self->opentemplate("admin-side/common/bannercodeblock.tmpl") or return $self->showError();
   	if(!is_empty($result->{'file'}))
   	  {
   	  	$result->{'webfilename'}="/".$self->getUploadDir().$result->{'file'};
   	  };
    $self->tmpl()->param($result);
    $htmlCode=$self->tmpl()->output();
   };
 $self->opentemplate("admin-side/common/information.tmpl") or return $self->showError();
 $self->tmpl()->param(
                      DATA     =>$htmlCode,
                      KEY_VALUE=>$id,
                      AJAX     =>$is_ajax,
                      REF      =>$ref
                     );
 return $self->output($self->tmpl()->output());  
 
}; 

#��� �������� ���������� ������ ����� ����������
#TODO:: �������� �������� ������������ �������� ������� � �����
sub CheckData
{
 my $self=shift;
 my $form=shift;
 my $action=shift;
 if($form->has_err_msgs())
   {
   	return NG::Module::M_OK;
   };
 my $sizexField=$form->_getfieldhash("sizex");
 my $sizeyField=$form->_getfieldhash("sizey");
 my $textBanner=$form->_getfieldhash("text"); 
 my $fileBanner=$form->_getfieldhash("file");
 if($form->{_new})
   {
    if(is_empty($textBanner->{'VALUE'}) && is_empty($fileBanner->{'TMP_FILENAME'}))
     {
   	  $form->_setfielderror($fileBanner,"�� ������ ������");
     };
   };  
 if(!is_valid_id($sizexField->{'VALUE'}))
   {
   	$form->_setfielderror($sizexField,"�� ��������� ����� ������");
   };
 if(!is_valid_id($sizeyField->{'VALUE'}))
   {
   	$form->_setfielderror($sizeyField,"�� ��������� ����� ������");
   };
 return NG::Module::M_OK;
};

sub PrepareData
{
 my $self=shift;
 my $form=shift;
 my $textBanner=$form->_getfieldhash("text"); 
 my $fileBanner=$form->_getfieldhash("file");
 my $file = $fileBanner->{'TMP_FILENAME'};
 if(!is_empty($fileBanner->{'TMP_FILE'})&&(-s $fileBanner->{'TMP_FILE'})>0)
   {
    my $ext = get_file_extension($file);
    if($ext=~/^swf$/i)
       {
        $form->addfields({FIELD=>"is_flash",TYPE=>"internal",VALUE=>1}); 
       };
   }
 elsif(!is_empty($textBanner->{'VALUE'}))
   {
   	$form->addfields({FIELD=>"is_text",TYPE=>"internal",VALUE=>1}); 
   };  
 return NG::Module::M_OK;
};

return 1;
END{};