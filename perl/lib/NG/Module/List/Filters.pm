package NG::Module::List::Filters;

use strict;
use NG::Field;
use NG::Module::List;
use NSecure;
use Data::Dumper;

$NG::Module::List::Filters::VERSION = 0.1;


sub new {
	my $class = shift; # $class,$parent, @_
	my $pObj = shift;
	my %args = (@_);
	
	my $classes = {
		select => $class,
		tabs   => $class,
		calendar => "NG::Module::List::Filters::Calendar",
	};
	
	my $targetClass = $class;
	if (exists $args{TYPE}) {
		die "NG::Module::List::Filters(): invalid TYPE: ".$args{TYPE} unless exists $classes->{$args{TYPE}};
		$targetClass = $classes->{$args{TYPE}};
	};
	return $pObj->cms()->getObject($targetClass, $pObj, @_) if $targetClass ne $class;
	
	my $filter = {};
	bless $filter, $class;
	$filter->{_parentObj} = $pObj;
	$filter->{_config} = \%args;
	$filter->init(@_);
	$filter;
};

sub init {
	my $self = shift;
	my %args = (@_);
	$self->{_elements} = [];
	$self->{_activeElement} = undef;
	$self->{_config}->{FILTER_NAME} ||= 'filter';
	$self->{_config}->{SQL}->{PREFIX} ||= "id" if exists $self->{_config}->{SQL};
	$self->{_config}->{TYPE} ||= "select";
	$self->{_activeValue} = undef;
	$self;
};

sub load {
	my $self = shift;
    my $config = $self->config();
	
    return $self->error("������������ ������������ �������. �� ������ �������� ��������� ������ (VALUES,SQL ��� LINKEDFIELD)") unless ($config->{VALUES} || $config->{SQL} || $config->{LINKEDFIELD});
    return $self->error("������������ ������������ �������. ������������� ������������� ����� SQL � LINKEDFIELD ���������.") if ($config->{SQL} && $config->{LINKEDFIELD});

    my $field = $config->{FIELD};
    
    my $q = $self->parent()->q();
    $self->{_activeValue} = $q->url_param($config->{FILTER_NAME})||"";

    if ($config->{VALUES}) {
        $self->_loadFilterByValues() || return $self->error();
    };
    
    if ($config->{SQL}) {
        return $self->error('������������ ������������. ����������� ����� FIELD.') if (!defined $field);
        $self->_loadFilterBySQL() || return $self->error();
    };
        
    if ($config->{LINKEDFIELD}) {
		$self->_loadFilterByLField() || return $self->error();
    };

    if (!$self->{_activeElement} && scalar @{$self->elements()}) {
        $self->{_activeElement} = ${$self->{_elements}}[0];
		$self->{_activeElement}->{SELECTED} = 1;
    }
    elsif(!$self->{_activeElement}) {
        $self->{_activeElement} = {WHERE=>"1=?",VALUE=>0};
    };
    return 1;
};

sub error {
	my $self = shift;
	my $error = shift;
	$self->parent()->error($error);
	return undef;
};

sub parent {
	my $self = shift;
	return $self->{_parentObj};
};

sub config {
	my $self = shift;
	return $self->{_config};	
};

sub elements {
	#TODO: ���� ����� �� ������ �������������� � �������� �������������.
	#���������� ������������ List->getListFilters, �������� � ������� �����
	#������������ ���, ������� ����� �������������� � �������
	my $self = shift;
	return $self->{_elements};
};

sub fieldValue {
	my $self = shift;
	return {} unless $self->{_activeElement} && $self->{_config}->{LINKEDFIELD};
	return {$self->{_config}->{LINKEDFIELD} => $self->{_activeElement}->{CVALUE}};
};

sub _loadFilterByValues {
	my $self = shift;
	my $config = $self->config();
	
	my $field = $config->{FIELD};
	
	my $pos = 1;
    foreach (@{$config->{VALUES}}) {
        my $name   = $_->{NAME};
        my $where  = $_->{WHERE};
        my $cvalue = undef;
        my $fvalue = "pos".$pos++;
        
        $cvalue = $_->{VALUE} if exists $_->{VALUE};
        
        if (!defined $where) {
            return $self->error('������������ ������������ �������. ����������� ����� FIELD.') if (!defined $field);
            return $self->error('������������ ������������ �������. ����������� ����� VALUE.') if (!defined $cvalue);
            $where = $field."=?";
        }
        
        if ($_->{PRIVILEGE}) {
            next unless $self->parent()->hasPriv($_->{PRIVILEGE});
        }
        
        $cvalue = [] unless exists $_->{VALUE};
        
        my $filter = {
            NAME =>$name,
            VALUE =>$fvalue,
            WHERE => $where,
            CVALUE=> $cvalue,
        };
        if ($fvalue eq $self->{_activeValue}) { #TODO : ���������� ��������
            $filter->{SELECTED} = 1;
            $self->{_activeElement} = $filter;
        };
        push @{$self->{_elements}},$filter;
    };
    return 1;
};


sub _loadFilterBySQL {
	my $self = shift;
	my $config = $self->config();
    my $field = $config->{FIELD};
    my $prefix = $config->{SQL}->{PREFIX};	
	
	my $idF   = $config->{SQL}->{ID_FIELD} || "id";
    my $nameF = $config->{SQL}->{NAME_FIELD} || "name";
    my $query = $config->{SQL}->{QUERY};
    
    if (!defined $query) {
        my $table = $config->{SQL}->{TABLE} || return $self->error('� ������������ ������� ���������� ������� ���� SQL.TABLE ���� SQL.QUERY ��� ��������� �������� �������.');
        $query = "select $idF,$nameF from $table ";
        $query .= " where "   .$config->{SQL}->{WHERE} if (exists $config->{SQL}->{WHERE});
        $query .= " order by ".$config->{SQL}->{ORDER} if (exists $config->{SQL}->{ORDER});
    }
    else {
    	return $self->error("������������ SQL-������� �� ������������ ������������� �������� QUERY � TABLE,WHERE,ORDER") if (exists $config->{SQL}->{WHERE} || exists $config->{SQL}->{ORDER});
    };
    
    my @params=();
    # TODO: �������� �������� ���� � ����� ��������� �� ������� ������������
    if (exists $config->{SQL}->{PARAMS}) {
        return $self->error("�������� ��������� PARAMS ������������ ������� �� �������� ������� �� ������") if ref $config->{PARAMS} ne "ARRAY";
        @params = @{$config->{SQL}->{PARAMS}};
    };
    
    my $sth = $self->parent()->dbh()->prepare($query) or return $self->error($DBI::errstr);
    $sth->execute(@params) or return $self->error($DBI::errstr);
    while (my $row=$sth->fetchrow_hashref()) {
        my $id   = $row->{$idF}   || return $self->error("�� ������� �������� ���� ID_FIELD ($idF) ��� ���������� �������");
        my $name = $row->{$nameF} || return $self->error("�� ������� �������� ���� NAME_FIELD ($nameF) ��� ���������� �������");
        
        my $filter = {
            NAME =>$name,
            VALUE => $prefix.$id,
            WHERE => "$field=?",
            CVALUE => $id,
        };
        if ($prefix.$id eq $self->{_activeValue}) { #TODO
            $filter->{SELECTED} = 1;
            $self->{_activeElement} = $filter;
        };
        
        push @{$self->{_elements}},$filter;
    };
    $sth->finish();
    return 1;
};


sub _loadFilterByLField {
	my $self = shift;
	my $config = $self->config();
	
	my $fieldName = $config->{LINKEDFIELD};
	my $lfield = $self->parent()->getField($fieldName) || return $self->error("����������� ���� ������� ($fieldName) �� �������.");

	if ($lfield->{TYPE} eq "fkselect" || $lfield->{TYPE} eq "select" || $lfield->{TYPE} eq "radiobutton") {
        #TODO: � ������� �������� ����� ����� ���������� �� isa("NG::Field::Select") ?
        #NB: C����� lfield �� getField �� �������� ��������, ������� isa �� ������� :)
        my %n = %$lfield;
        my $fObj = NG::Field->new(\%n, $self->parent());
        return $self->error("������ c������� ������� ������������ ���� $fieldName: ". $NG::Field::errstr) unless $fObj;
        
        my $so = $fObj->selectOptions();
		#TODO: ��������� ������, ���������� � ����
        return $self->error("�������� SELECT_OPTIONS ���� $fieldName �� �������� ������� �� ������") unless ref $so eq "ARRAY";
        
#        my $pmask = $fObj->options('PRIVILEGEMASK');
        foreach my $o (@{$so}) {
            my $id = $o->{ID};
#print STDERR $id;
            return $self->error('����������� ��� ������ � ������� �������� SELECT_OPTIONS ���� $fieldName') if (!is_valid_id($id) && $id != 0);
=head
            if ($pmask) {
                my $privilege = $pmask;
                $privilege =~ s@\{id\}@$id@;
                next unless $self->parent()->hasPriv($privilege);
            }
=cut
            my $filter = {
                NAME  => $o->{NAME},
                VALUE => "lf".$id,
                WHERE => "$fieldName=?",
                CVALUE => $id,
            };
            if ("lf".$id eq $self->{_activeValue}) { #TODO
                $filter->{SELECTED} = 1;
                $self->{_activeElement} = $filter;
            };
            push @{$self->{_elements}},$filter;
        };
	}
	else {
		return $self->error("����������� ���� �����, �������� �� fkselect � select ��� �� ��������������."); 
	};
    return 1;
}

sub type {
	my $self = shift;
	return $self->{_config}->{TYPE};
};

sub name {
	my $self = shift;
	return $self->{_config}->{NAME};
};

sub useForm {
	my $self = shift;
	return 1 if $self->{_config}->{TYPE} ne "tabs";
	return 0;
};

sub getWhereParams {
    my $self = shift;
    return ($self->{_activeElement}->{CVALUE});
};

sub getWhereCondition {
    my $self = shift;
    return $self->{_activeElement}->{WHERE};
};

sub getURLParams {
    my $self = shift;
    my $config = $self->config();
    return $config->{FILTER_NAME}."=".$self->{_activeElement}->{VALUE};
};

sub beforeOutput {
	
};

return 1;

END {};
