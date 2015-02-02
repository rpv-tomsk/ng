package NG::Banners::Clients::CPlaces;
use strict;

use NGService;
use NSecure;
use Data::Dumper;

use vars qw(@ISA);


sub AdminMode {
    use NG::Module::List;
    @ISA = qw(NG::Module::List);
};
#TODO:: ��� �������� ����������� ����� - ������� ��� ������ ������� ��������� � ���� ������ 
#? :: ��� ��������� ���������� ����� ��� ������ � �������� ���� ������ ���������� ����� �� ��������� � �������� �������
sub config 
{
 my $self = shift;
 my $cid=is_valid_id($self->q()->param('cid'))?$self->q()->param('cid'):0;
 #$self->setSubmodules(
 #                     [
 #                      {URL=>"banners",MODULE=>"NG::Banners::Clients::CBanners"},
 #                     ]
 #                    );
 #���������� ���� � ������������ ���������
 #$self->setTabs(
 #               #{HEADER=>"�������",TABURL=>"",NOAJAX=>1},
 #               {HEADER=>"��������� ����� �������",TABURL=>"places",PARAMS=>["cid=$cid"]},
 #               {HEADER=>"������� �������",TABURL=>"cbanners",PARAMS=>["cid=$cid"]},
 #              );                     
 
 $self->tablename('clients_places');
 # ����� �����
 $self->fields(
               {FIELD=>'id',       TYPE =>'id',       NAME =>'���',            IS_NOTNULL=>1},
               {FIELD=>'cid',      TYPE =>'fkparent', NAME =>'��� �������',    IS_NOTNULL=>1},
               {FIELD=>'pid',      TYPE =>'fkselect', 
               	                   NAME =>'��������� �����',     
               	                   OPTIONS=>{ 
               	                             TABLE      =>"banner_places",
               	                             ID_FIELD   =>"id",
               	                             NAME_FIELD =>"name",
               	                             WHERE      =>"1=1",
               	                             ORDER      =>"name"
               	                            },
               	                   IS_NOTNULL=>1},
               {FIELD=>'name',     TYPE =>'text',       NAME =>'��������',     IS_NOTNULL=>1},
               {FIELD=>'sdate',    TYPE =>'date',       NAME =>'������',       IS_NOTNULL=>1},
               {FIELD=>'edate',    TYPE =>'date',       NAME =>'�����',        IS_NOTNULL=>1},
              );
    # ���������
    $self->listfields([
                       {FIELD => 'name'},
                       {FIELD => 'sdate'},
                       {FIELD => 'edate'}
                      ]);
    # �������� �����
    $self->formfields(
                      {FIELD => 'id'},
                      {FIELD => 'pid'},
                      {FIELD => 'sdate'},
                      {FIELD => 'edate'}
                     );
    #$self->{_onpage}=1;
    #$self->order("name");
    #$self->order(
    #    {FIELD=>"name",DEFAULT=>0,ORDER_ASC=>"name",ORDER_DESC=>"name desc",DEFAULTBY=>'DESC', NAME=>"�� ������������"},
    #    {FIELD=>"id",  DEFAULT=>1,ORDER_ASC=>"id",  ORDER_DESC=>"id desc",  DEFAULTBY=>'DESC', NAME=>"�� ����"},
    #);
    
    #$self->{_onpage} = 20;
	#$self->set_privilege("CAN_ADMINS"); 
};

sub getListColumns {
    my $self = shift;
    # ���������� ������-������ ������������� �����. ��� ���� ������������ ��������� ���� ��������� ����.
    my @columns=();
    my $fields = "";
    my $idfound = 0;
    foreach my $field (@{$self->{_listfields}}) {
        $idfound = 1 if ($field->{TYPE} eq "id");
        push @columns,$field unless ($field->{TYPE} eq "hidden");  # �� �������� � ������ �� �����������
        next if ($field->{FIELD} eq "_counter_");                  ## �� �������� � ������ �� �������
    	#��������� ��������
    	if($field->{TYPE} eq "id")
    	  {
    	   $fields .= ","."clients_places.".$field->{FIELD};
    	  }
    	else
    	  {
    	   $fields .= ",".$field->{FIELD};
    	  };  
        $field->{ORDER} = getURLWithParams($field->{ORDER},$self->getFilterParam()) if ($field->{ORDER});
    };
    $fields .= ","."clients_places.".$self->{_idname} if ($idfound == 0); # ���� �������� ���� �� �������
    $fields =~ s/^,//;
    $self->{_shlistFields} = $fields;
    return @columns;
};

sub getListSQLTable {
    my $self = shift;
    return $self->{_table}.",banner_places";
};

sub getListSQLWhere {
    my $self = shift;
    my $where = "";
    foreach (@{$self->{_shlistWhere}}) {
        $where .= " and (".$_->{SQL}.")";
    };
    $where =~ s/and\ //;
    $where.=" and banner_places.id=clients_places.pid";
    return $where;
};

sub checkData
{
 my $self=shift;
 my $form=shift;
 my $action=shift;
 
 if($form->has_err_msgs())
   {
   	return NG::Module::M_OK;
   };
 my $sdateField=$form->_getfieldhash('sdate');
 my $edateField=$form->_getfieldhash('edate');
 my $fkField=$form->_getfieldhash('cid');
 my $placeField=$form->_getfieldhash('pid');
 my $sDate=$self->db()->date_to_db($sdateField->{'VALUE'});
 my $eDate=$self->db()->date_to_db($edateField->{'VALUE'});
 if($sDate gt $eDate)
   {
   	$form->_setfielderror($sdateField,"���� ������ ������ ������ ��� ���� ���������"); 
   	return NG::Module::M_OK;
   };
 my $sql="select count(*) from clients_places where ((sdate<? and edate>?) or (sdate<? and edate>?) or (sdate>? and edate<?)) and pid=? and id<>?";
 my $sth=$self->db()->dbh()->prepare($sql) or return $self->setError($DBI::errstr);
 $sth->execute($sDate,$sDate,$eDate,$eDate,$sDate,$eDate,$placeField->{'VALUE'},$self->getKeyValue()) or return $self->setError($DBI::errstr);
 my $tmp=$sth->fetchrow();
 $sth->finish();
 if($tmp)
   {
    $form->_setfielderror($sdateField,"� ��������� ���������� ������� ����� ������"); 
   };
 return NG::Module::M_OK;
};
return 1;
END{};