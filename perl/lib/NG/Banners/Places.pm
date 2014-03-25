package NG::Banners::Places;
use strict;

use NGService;
use NSecure;
use NHtml;
use Data::Dumper;

use vars qw(@ISA);

sub AdminMode
{
 use NG::Module::List;
 @ISA = qw(NG::Module::List);
};

sub config
{
 my $self=shift;
 $self->tablename('banner_places');
 # ����� �����
 $self->fields(
               {FIELD=>'id',          TYPE=>'id',       NAME=>'���',        IS_NOTNULL=>1},
               {FIELD=>'name',        TYPE=>'text',     NAME=>'��������',   IS_NOTNULL=>1, WIDTH=>'80%'},
               {FIELD=>'sizex',       TYPE=>'text',     NAME=>'������',     IS_NOTNULL=>1, WIDTH=>'10%'},
               {FIELD=>'sizey',       TYPE=>'text',     NAME=>'������',     IS_NOTNULL=>1, WIDTH=>'10%'},
               {FIELD=>'description', TYPE=>'textarea', NAME=>'����������', IS_NOTNULL=>0}
              );
 # ���������
 $self->listfields([
                    {FIELD => 'name'},
                    {FIELD => 'sizex'},
                    {FIELD => 'sizey'}
                   ]);
 # �������� �����
 $self->formfields(
                   {FIELD => 'id'},
                   {FIELD => 'name'},
                   {FIELD => 'sizex'},
                   {FIELD => 'sizey'},
                   {FIELD => 'description'}
                   );
 $self->order("name");
 #�������������� ������ �� ��� ���������� ����� 
 my $url=$self->getBaseURL();
 $url=$self-> getURLWithParams($url,"id={id}","action=showcode");
 $self->add_links("���",$url,1);
 $self->register_action('showcode',"showCode");
};

sub getProcessUrl
{
 my $self=shift;
 #���������� ������������� url �� �������� ��������� ���������� ���������� �����
 return "/getb/";
};

sub showCode
{
 my $self=shift;
 my $action=shift;
 my $is_ajax=shift;
 my $q=$self->q();
 my $id=(is_valid_id($q->param('id')))?$q->param('id'):0;
 my $ref=$q->param('ref');
 #����� ������ � ��� ������ ������ ������� ������ � ��������
 my $sql="select id,sizex,sizey from banner_places where id=?";
 my $sth=$self->db()->dbh()->prepare($sql) or return $self->setError($DBI::errstr);
 $sth->execute($id) or return $self->setError($DBI::errstr);
 my $result=$sth->fetchrow_hashref();
 $sth->finish();
 my $placeCode="��������, �� ������ ��������� ����� �� �������";
 #id ������ ������(�� ������� ���� ����� ��������� ����� ���� � ����)
 if(is_valid_id($result->{'id'}))
   {
    $self->opentemplate('admin-side/common/bannerplacecode.tmpl') or return $self->showError();
    $self->tmpl()->param(
                         ID      => $result->{'id'},
                         SIZEX   => $result->{'sizex'},
                         SIZEY   => $result->{'sizey'},
                         WEBPATH => $self->getProcessUrl()                        
                        );	
    $placeCode=nl2br(htmlspecialchars($self->tmpl()->output()));
   };
 $self->opentemplate("admin-side/common/information.tmpl") or return $self->showError();
 $self->tmpl()->param(
                      DATA     =>$placeCode,
                      KEY_VALUE=>$id,
                      AJAX     =>$is_ajax,
                      REF      =>$ref
                     );
 return $self->output($self->tmpl()->output());  
};

sub CheckData
{
 my $self=shift;
 my $form=shift;
 my $action=shift;
 #� ����� ��� ���� ��������� ������ � ������� ���������� �������� �������
 if($form->has_err_msgs())
   {
   	return NG::Module::M_OK;
   };
 my $sizexField=$form->_getfieldhash("sizex");
 my $sizeyField=$form->_getfieldhash("sizey");
 if(!is_valid_id($sizexField->{'VALUE'}))
   {
   	$form->_setfielderror($sizexField,"�� ��������� ����� ������");
   };
 if(!is_valid_id($sizeyField->{'VALUE'}))
   {
   	$form -> _setfielderror($sizeyField,"�� ��������� ����� ������");
   };
 return NG::Module::M_OK;
};

return 1;
END{};