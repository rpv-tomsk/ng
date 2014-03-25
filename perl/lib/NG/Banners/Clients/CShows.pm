package NG::Banners::Clients::CShows;
use strict;

use NGService;
use NSecure;
use Data::Dumper;

use vars qw(@ISA);

sub AdminMode {
    use NG::Module::List;
    @ISA = qw(NG::Module::List);
};

sub getParamFromUrl
{
 my $self=shift;
 my $url=$self->q()->url(-absolute=>1);
 $url=~/(\d+)/;
 return $1;
};

sub config 
{
 my $self = shift;
 $self->tablename('banners_shows');
 # ����� �����
 my $cid=is_valid_id($self->q()->param('cid'))?$self->q()->param('cid'):(is_valid_id($self->getParamFromUrl())?$self->getParamFromUrl():0);
 $self->fields(
               {FIELD=>'id',       TYPE =>'id',       NAME =>'���',                IS_NOTNULL=>1},
               {FIELD=>'cid',      TYPE =>'fkparent', NAME =>'��� �������',        IS_NOTNULL=>1},
               {FIELD=>'sdate',    TYPE =>'date',     NAME =>'������'},
               {FIELD=>'edate',    TYPE =>'date',     NAME =>'�����'},
               {FIELD=>'bid',      TYPE =>'fkselect', 
               	                   NAME =>'������',     
               	                   OPTIONS=>{ 
               	                             TABLE      =>"banners",
               	                             ID_FIELD   =>"id",
               	                             NAME_FIELD =>"name",
               	                             PARAMS     =>[
               	                                           $cid,
               	                                          ],
               	                             WHERE      =>"cid=? and moderated=1",
               	                             ORDER      =>"name",
               	                            },
               	                   IS_NOTNULL=>1},
               
               {FIELD=>'pid',      TYPE   =>'fkselect', 
               	                   NAME   =>'�����',     
               	                   OPTIONS=>{ 
               	                             TABLE      =>"clients_places",
               	                             ID_FIELD   =>"id",
               	                             NAME_FIELD =>"name",
               	                             #{WHERE     =>"cid=$cid"},
               	                             #{ORDER     =>"name"},
               	                             QUERY      =>"select bp.id as id,bp.name as name from clients_places cp,banner_places bp where cp.cid = $cid and cp.pid=bp.id order by name",
               	                            },
               	                   IS_NOTNULL=>1},	
               {FIELD=>'def', TYPE =>'checkbox', NAME =>'������ �� ���������',  IS_NOTNULL=>0},	                                               
               {FIELD=>'is_show', TYPE =>'checkbox', NAME =>'����������',           DEFAULT=>1,   IS_NOTNULL=>0}
               #{FIELD=>'name',     TYPE =>'text',     NAME =>'��������',           IS_NOTNULL=>1},
               #{FIELD=>'alt',      TYPE =>'text',     NAME =>'������������� �����',IS_NOTNULL=>0},
               #{FIELD=>'sizex',    TYPE =>'text',     NAME =>'�� �����������',     IS_NOTNULL=>0},
               #{FIELD=>'sizey',    TYPE =>'text',     NAME =>'�� ���������',       IS_NOTNULL=>0},
               #{FIELD=>'file',     TYPE =>'file',     NAME =>'���� �������',       IS_NOTNULL=>0, UPLOADDIR=>"upload/banners/"},
               #{FIELD=>'text',     TYPE =>'textarea', NAME =>'��������� ������',   IS_NOTNULL=>0},
               #{FIELD=>'is_flash', TYPE =>'checkbox', NAME =>'����',               IS_NOTNULL=>0},
               #{FIELD=>'is_text',  TYPE =>'checkbox', NAME =>'�����',              IS_NOTNULL=>0}
              );
    
    # ���������
    $self->listfields([
                       {FIELD => 'bid'},
                       {FIELD => 'pid'},
                       {FIELD => 'sdate'},
                       {FIELD => 'edate'},
                       #{FIELD => 'sizey'},
                      ]);
    # �������� �����
    $self->formfields(
                      {FIELD => 'id'},
                      {FIELD => 'bid'},
                      {FIELD => 'pid'},
                      {FIELD => 'sdate'},
                      {FIELD => 'edate'},
                      {FIELD => 'def'},
                      {FIELD => 'is_show'},
                      #{FIELD => 'alt'},
                      #{FIELD => 'text'},
                      #{FIELD => 'file'}
                     );
};
#������� ������� ��������(������ �� ����) ��� ���������� ����������� ������
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
    	my $prefix="bs.";
    	if($field->{'FIELD'} eq "bid") #"����" ����� ���
    	  {
    	   $prefix="b.name as ";
    	  }
    	elsif($field->{'FIELD'} eq "pid") #"����" ����� ���
    	  {
    	   $prefix="bp.name as ";
    	  };  
    	$fields .= ",".$prefix.$field->{FIELD};
    	$field->{IS_POSORDER} = 1 if ($field->{TYPE} eq "posorder");
        $field->{ORDER} = getURLWithParams($field->{ORDER},$self->getFilterParam()) if ($field->{ORDER});
    };
    if ($idfound == 0)
      {
       $fields .= ","."bs.".$self->{_idname}; # ���� �������� ���� �� �������
      };
    $fields =~ s/^,//;
    $self->{_shlistFields} = $fields;
    return @columns;
};

sub processFKFields {
    my $self = shift;

    #�� ������ ������� ����� ����� ������������ ����� ?
    #����� �� �� ���� �� ����������� � ����������� ������ ? - ������ ��� �������� �����������. ���� ���� - ������������ �����.
    #����� ��� ������� ��� ������ ����� ����� �� _listfields
    my $fkparam = "";
    foreach my $field (@{$self->{_fields}}) {
        if ($field->{TYPE} eq "fkparent") {
            $self->setFKParentValue($field) || return $self->showError();
            my $param_value = $field->{VALUE};
            $fkparam .= $field->{FIELD}."=".$param_value."&";
            $self->pushWhereCondition("bs.".$field->{FIELD}."=?",$param_value);
        };
        if ($field->{TYPE} eq "filter") {
            my $param_value = $field->{VALUE};
            return $self->error("Value not specified for FK field \"".$field->{FIELD}."\"") unless $param_value;
            $self->pushWhereCondition($field->{FIELD}."=?",$param_value);
        }
    };
    $fkparam =~ s/\&$//;
    $self->{_shlistFKParam} = $fkparam;
    return NG::Module::M_OK;
};

sub getListSQLTable {
    my $self = shift;
    return $self->{_table}." bs,banner_places bp,banners b";
};

sub getListSQLWhere {
    my $self = shift;
    my $where = "";
    foreach (@{$self->{_shlistWhere}}) {
        $where .= " and (".$_->{SQL}.")";
    };
    $where =~ s/and\ //;
    $where.="and bs.pid=bp.id and b.id=bs.bid";
    return $where;
};
return 1;
END{};