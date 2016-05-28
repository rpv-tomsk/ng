package NG::Field::Multicheckbox;
use strict;

#TODO: readonly
#TODO: ������� ������ ������� ��� / �������� �����
#TODO: �������� ��������� ��������� � ���������� ����������
#TODO: ��������� �� ������ ����������

use NG::Field;
use NGService;
use NSecure;

use Carp;

use vars qw(@ISA);
@ISA = qw(NG::Field);

sub init {
    my $field = shift;
    #$field->{TEMPLATE} ||= "admin-side/common/fields/multicheckbox.tmpl";
    
    if ($field->{TYPE} eq 'multivalue') {
        $field->{TEMPLATE} ||= "admin-side/common/fields/multivalue.tmpl";
    };
    
    $field->SUPER::init(@_) or return undef;
    
    $field->db() or return undef;
    
    $field->{_DATAH} = undef; #��������� ��������, ��� (���� = �������� = id ���������� ��������)
    $field->{_DATAA} = undef; #��������� ��������, ������ id
    $field->{_NEWH}  = undef; #����������� �������� (��������� �� �����)
    $field->{_NEWA}  = undef; #����������� �������� (��������� �� �����), ������ id
    $field->{_DICTA} = undef; #������ �������, ������ ������� (��� ������ multicheckbox)
    $field->{_DICTH} = undef; #������ ������� (����=��������), ���, ��� �������� �������� _DATAH � _NEWH
    
    $field->{_value_id}    = undef;   #��������� �������� ����� �������
    $field->{_value_names} = undef;   #��������� �������� ����� �����������
    $field->{_changed}     = 0;       #������� ��������� ������ ��������� ��������. ����� ���� undef � �������� ������.
    
    $field->{_dict_loaded} = 0;
    $field->{_data_loaded} = 0;
    
    my $options = $field->{OPTIONS} || return $field->set_err("��� ���� $field->{FIELD} �� ������� �������������� ���������");
    return $field->set_err("�������� OPTIONS �� �������� HASHREF") if ref $options ne "HASH";
    
    if ($options->{DICT}) {
        return $field->set_err("�������� �������� DICT ������������ ���� $field->{FIELD} �� �������� ������� �� ���") if ref $options->{DICT} ne "HASH";
        #TODO: ��������� �� ������� VALUES
        my $dict = $options->{DICT};
        $dict->{ID_FIELD}  ||= "id";
        $dict->{NAME_FIELD}||= "name";
        
        if (exists $dict->{PARAMS}) {
            return $field->set_err("�������� �������� PARAMS ������ �������� ���� $field->{FIELD} �� �������� ������� �� ������") if ref $dict->{PARAMS} ne "ARRAY";
            return $field->set_err("������� PARAMS ���������� ��� ��������� WHERE ��� QUERY") unless ($dict->{WHERE} || $dict->{QUERY});
        };
        if ($dict->{QUERY}) {
            return $field->set_err("����� multivalue � ����� DICT.QUERY �� ����������") if $field->{TYPE} eq 'multivalue';
            return $field->set_err("����� DICT.ADDITION � DICT.QUERY �� ����������") if $dict->{ADDITION};
            return $field->set_err("������� QUERY ����������� � ���������� TABLE, WHERE � ORDER") if ($dict->{TABLE} || $dict->{WHERE} || $dict->{ORDER});
            $dict->{_SQL} = $dict->{QUERY};
        }
        else {
            $dict->{TABLE} || return $field->set_err("��� ���� $field->{FIELD} ���� multicheckbox �� ������� ��� ������� �� ����������");
            my $sql="select ".$dict->{ID_FIELD}.",".$dict->{NAME_FIELD}." from ".$dict->{TABLE};
            if ($dict->{WHERE}) {
                return $field->set_err("����� DICT.ADDITION � DICT.WHERE �� ����������") if $dict->{ADDITION};
                $sql .= " where ".$dict->{WHERE};
            };
            if ($dict->{ORDER}) { $sql .= " order by ".$dict->{ORDER}; };
            $dict->{_SQL} = $sql;
        };
    }
    elsif ($options->{VALUES}) {
        return $field->set_err("�������� �������� VALUES ������������ ���� $field->{FIELD} ���� multicheckbox �� �������� ������� �� ������") if ref $options->{VALUES} ne "ARRAY";
        return $field->set_err("����� multivalue � ����� VALUES �� ����������") if $field->{TYPE} eq 'multivalue';
        
        $field->{_DICTA} = [];
        foreach my $p (@{$options->{VALUES}}) {
            return $field->set_err("�������� ������� VALUES ���� $field->{FIELD} �� �������� �����.") if ref $p ne "HASH";
            my $id = $p->{ID};
            return $field->set_err("� ������ �������� VALUES ���� $field->{FIELD} ����������� �������� ����� ID ") if (!$id && $id != 0);
            $p->{NAME} || return $field->set_err("� ������ �������� VALUES ���� $field->{FIELD} ����������� �������� ����� NAME");
            $field->{_DICTH}->{$id} = $p->{NAME};
            push @{$field->{_DICTA}}, {
                ID      => $id,
                NAME    => $p->{NAME},
                DEFAULT => $p->{DEFAULT},
            };
        };
        $field->{_dict_loaded} = 1;
    }
    else {
        return $field->set_err("����������� ����� ������ �������� DICT ��� VALUES.");
    };

    my $storage = $options->{STORAGE};
    if ($storage) {
        return $field->set_err("����������� ������� STORAGE ���� $field->{FIELD}") unless $storage;
        return $field->set_err("�������� �������� STORAGE ������������ ���� $field->{FIELD} �� �������� ������� �� ���") if ref $storage ne "HASH";
        return $field->set_err("�� ������� ��� ������� (TABLE) � �������� STORAGE ���� $field->{FIELD}") unless $storage->{TABLE};
        return $field->set_err("�� ������� ��� ���� ������ (FIELD) � �������� STORAGE ���� $field->{FIELD}") unless $storage->{FIELD};
        return $field->set_err("�� ������ ��� ����� ����� �������� ������� � ��������� ��������� ��������� (FIELDS_MAP) � �������� STORAGE ���� $field->{FIELD}") unless $storage->{FIELDS_MAP};
        return $field->set_err("�������� FIELDS_MAP � �������� STORAGE ���� $field->{FIELD} �� �������� �����") unless ref $storage->{FIELDS_MAP} eq "HASH";
        return $field->set_err("����������� ����� � ��������� FIELDS_MAP �������� STORAGE ���� $field->{FIELD}") unless scalar keys %{$storage->{FIELDS_MAP}};
    }
    else {
        $options->{STORE_FIELD} ||= $field->{FIELD};
    };
    
    $field->pushErrorTexts({
        NOTHING_CHOOSEN       => "{n}: �� ������� �� ������ ��������.",
    });
    
    $field->{HAS_ORDERING} = 0;
    if ($options->{STORE_FIELD} || ($storage && $storage->{ORDER})) {
        $field->{HAS_ORDERING} = (exists $options->{ORDERING})?$options->{ORDERING}:1;
    };
    return 1;
};

sub _loadDict {
    my $field = shift;
    
    my $options = $field->{OPTIONS};
    return $field->set_err("����������� ������� DICT") unless $options->{DICT};
    my $dict = $options->{DICT};
    
    return $field->set_err('DATA not loaded') unless defined $field->{_DATAH} || $field->{_new};
    
    my $sql = $dict->{_SQL} or return $field->set_err("NG::Field::Multicheckbox::_loadDict(): ����������� �������� �������. ������ ������������� ����.");
    my @params = ();
    @params = @{$dict->{PARAMS}} if (exists $dict->{PARAMS});
    
    my $dbh = $field->dbh() or return $field->set_err("_loadDict(): ����������� dbh");
    
    my $sth = $dbh->prepare($sql) or return $field->set_err("������ �������� �������� multicheckbox: ".$DBI::errstr);
    $sth->execute(@params) or return $field->set_err($DBI::errstr);
    my @result = ();
    while (my ($id,$name) = $sth->fetchrow()) {
        push @result, {
            ID=>$id,
            NAME=>$name,
        };
        $field->{_DICTH}->{$id} = $name;
    };
    $sth->finish();
    
    my $cnt = scalar @result;
    $field->{SIZE} ||= $cnt if $field->{TYPE} eq "multiselect";
    
    $result[int($cnt/2)]->{HALF} = 1 if $cnt > 1;
    
    $field->{_DICTA} = \@result;
    $field->{_dict_loaded} = 1;
    return 1;
};

sub prepareOutput {
    my $field = shift;
    
    if ($field->{TYPE} eq 'multivalue') { #������ ��������� ��������, ������ ��������� ��������
        warn "Multicheckbox(multivalue): _dict_loaded = 1 warning!" if $field->{_dict_loaded}; #���������� ��� ��������.
        
        my $options = $field->{OPTIONS};
        return $field->set_err("����������� ������� DICT") unless $options->{DICT};
        my $dict = $options->{DICT};
        
        #���������� ��������� �� ���������, ������� ����� ��������� ������ ��������
        my @params = ();
        @params = @{$dict->{PARAMS}} if exists $dict->{PARAMS};
        
        $field->{SELECTED_OPTIONS} = [];
        $field->{SELECTED_ID} = "";
        return 1 if $field->{_new};
        return $field->set_err('DATA(A) not loaded') unless defined $field->{_DATAA};
        return 1 unless scalar @{$field->{_DATAA}};
        
        my $placeholders = "";
        my ($dataIdxs,$i) = ({},0);
        foreach my $id (@{$field->{_DATAA}}) {
            $placeholders.="?,";
            push @params, $id;
            $dataIdxs->{$id} = $i++;
        };
        $placeholders =~s /,$//;
        
        my $sql="SELECT ".$dict->{ID_FIELD}.",".$dict->{NAME_FIELD}." FROM ".$dict->{TABLE}." WHERE ";
        $sql .= $dict->{WHERE}. " AND "  if $dict->{WHERE};
        $sql .= $dict->{ID_FIELD}." IN (".$placeholders.")";
        $sql .= " ORDER BY ".$dict->{ORDER} if $dict->{ORDER};
        
        
        my $dbh = $field->dbh() or return $field->set_err("prepareOutput(): ����������� dbh");
        
        my $sth = $dbh->prepare($sql) or return $field->set_err("������ �������� �������� multicheckbox: ".$DBI::errstr);
        $sth->execute(@params) or return $field->set_err($DBI::errstr);
        
        #������� ���������� ������ ��������� �������� ����� ����:
        #- ��������������� ������� �� ����������� (��������������/�� ��������������)
        #- ��������������� ������� �� ������� ����� (�������������/�� �������������)
        
        my $orderByDict = 1;
        $orderByDict = 0 if $options->{STORAGE} && $options->{STORAGE}->{ORDER};
        
        my @result = ();
        my @ids = ();
        my $dictIdx = 0;
        while (my ($id,$name) = $sth->fetchrow()) {
            my $dataIdx = delete $dataIdxs->{$id};
            $result[($orderByDict?$dictIdx:$dataIdx)] = {ID=>$id,NAME=>$name};
            $dictIdx++;
        };
        $sth->finish();
        
        return $field->set_err("������ �������� multicheckbox: �������� ".join(',', keys %$dataIdxs)." �� ������� � �����������.") if scalar keys %$dataIdxs;
        
        my $value = "";
        $value .= $_->{ID}."," foreach @result;
        $value =~s /,$//;
        
        $field->{SELECTED_OPTIONS} = \@result;
        $field->{SELECTED_ID} = $value;
        
        return 1;
    };
    
    unless ($field->{_dict_loaded}) {
        #������ ������ �������� ����������� ��������
        $field->_loadDict() or return undef;
    };
    return $field->set_err('DATA(H) not loaded') unless defined $field->{_DATAH} || $field->{_new};
    foreach my $elm (@{$field->{_DICTA}}) {
        $elm->{SELECTED} = ((defined $field->{_DATAH} && exists $field->{_DATAH}->{$elm->{ID}})||($field->{_new} && $elm->{DEFAULT}))?1:0,
    };
    $field->{SELECT_OPTIONS} = $field->{_DICTA};
    return 1;
};

sub _getKey {
    my $field = shift;
    my $storage = shift;
    
    my $parent = $field->parent() or return $field->showError("����������� ������-��������");
    
    my $fields = "";
    my $ph = "";
    my $where = "";
    my @params = ();
    foreach my $key (keys %{$storage->{FIELDS_MAP}}) {
        $where .= "and ".$key ."=?";
        my $f = $storage->{FIELDS_MAP}->{$key} or return $field->showError("���������� �������� ����� ���������� ���� ��� ���� $key.");
        my $fObj = $parent->getField($f) or return $field->showError("���� $f, ��������� ��� ��������� � $key, �� �������.");
        my $v = $fObj->value($f) or return $field->showError("� ��������� c ����� $key ���� $f �����c����� ��������.");
        $fields .= ",".$key;
        $ph .= ",?";
        push @params, $v;
    };
    return $field->showError("����������� ��������� ����") unless $where;
    $where  =~ s/^and//;
    $where = " where ".$where;
    $fields =~ s/^,//;
    $ph =~s /^,//;
    return {WHERE=>$where,PARAMS=>\@params,FIELDS=>$fields,PLHLDRS=>$ph};
};

sub afterLoad {
    my $field = shift;

    my $options = $field->{OPTIONS};
    my $storage = $options->{STORAGE};
    
    unless ($storage) {
        defined $field->{_value_id} or 'afterLoad(): Missing _value_id';
        
        $field->{_DATAH} = {};
        $field->{_DATAA} = [split(/,/,$field->{_value_id})];
        foreach my $id (@{$field->{_DATAA}}) {
            $field->{_DATAH}->{$id} = $id;
        };
        $field->{_data_loaded} = 1;
        return 1;
    };
    
    my $h = $field->_getKey($storage) or return 0;
    my $sql="SELECT ".$storage->{FIELD}." FROM ".$storage->{TABLE}.$h->{WHERE};
    $sql.= " ORDER BY ".$storage->{ORDER} if $storage->{ORDER};
    my $dbh = $field->dbh() or return $field->showError("afterLoad(): ����������� dbh");
    
    my $sth = $dbh->prepare($sql) or return $field->set_err("������ �������� �������� multicheckbox: ".$DBI::errstr);
    $sth->execute(@{$h->{PARAMS}}) or return $field->set_err($DBI::errstr);
    
    $field->{_DATAH} = {};
    $field->{_DATAA} = [];
    while (my ($id) = $sth->fetchrow()) {
        $field->{_DATAH}->{$id} = $id; #������ (��������� ��������), ���
        push @{$field->{_DATAA}}, $id; 
        #return $field->showError("������������ ��������� ��: ���������� �������� ($id), ������������� � ����������� ��������") unless exists $field->{_DICTH}->{$id};
    };
    $sth->finish();
    $field->{_data_loaded} = 1;
    return 1;
};

sub setFormValue {
    my $field = shift;
    
    my $q = $field->parent()->q();
    $field->{_NEWH} = {};
    $field->{_NEWA} = [];
    
    $field->{_value_id}    = undef;
    $field->{_value_names} = undef;
    $field->{_changed}     = undef;   #���������� ���������� ������� ���������/��������� ��������� �� ����� ��������.
    
    if ($field->{TYPE} eq 'multivalue') {
        my $v = $q->param($field->{FIELD})||'';
        foreach my $id (split /,/,$v) {
            $field->{_NEWH}->{$id} = $id;
            push @{$field->{_NEWA}},$id;
        }
        return 1;
    };
    
    foreach my $id ($q->param($field->{FIELD})) {
        $field->{_NEWH}->{$id} = $id;
        push @{$field->{_NEWA}},$id;
    };
    return 1;
};

sub afterSave {
    my ($self,$action) = (shift,shift);
    
    return 1 unless $self->changed();
    
    my $options = $self->{OPTIONS};
    my $storage = $options->{STORAGE} or return 1;

    #������ � ����� ���������, �.�. LIST ������ $form->loadData ����� ����������� $form->update()
    unless ($self->{_dict_loaded}) {
        $self->_loadDict() or return undef;
    };
    
    return $self->set_err('DATA(H) not loaded') unless defined $self->{_DATAH}||$self->{_new};
    return $self->set_err('DATA(A) not loaded') unless defined $self->{_DATAA}||$self->{_new};
    return $self->set_err('NEW(A) not set') unless defined $self->{_NEWA};
    

    my $h = $self->_getKey($storage) or return 0;
    
    my $dbh = $self->dbh() or return $self->showError("afterSave(): ����������� dbh");
    
    if ($storage->{ORDER}) {
        unless ($self->{_new}) {
            return 1 if join(',',@{$self->{_DATAA}}) eq join(',',@{$self->{_NEWA}});
            #������� ��
            $dbh->do("DELETE FROM ".$storage->{TABLE}.$h->{WHERE},undef,@{$h->{PARAMS}}) or return $self->showError($DBI::errstr);
        };
        #��������� � ������ �������
        my $ins_sth = $dbh->prepare("insert into ".$storage->{TABLE}." (".$storage->{FIELD}.",".$storage->{ORDER}.",".$h->{FIELDS}.") values (?,?,".$h->{PLHLDRS}.")");
        my $idx = 1;
        foreach my $id (@{$self->{_NEWA}}) {
            return $self->showError("������������ ���������: ������� �������� ($id), ������������� � ����������� ��������") unless exists $self->{_DICTH}->{$id};
            $ins_sth->execute($id, $idx++, @{$h->{PARAMS}}) or return $self->showError($DBI::errstr);
        };
        return 1;
    };
    
    my $ins_sth = $dbh->prepare("insert into ".$storage->{TABLE}." (".$storage->{FIELD}.",".$h->{FIELDS}.") values (?,".$h->{PLHLDRS}.")");
    my $del_sth = $dbh->prepare("delete from ".$storage->{TABLE}.$h->{WHERE}." and ".$storage->{FIELD}."=?");
    #TODO: �������� ������ �� ����� ?
    foreach my $id (@{$self->{_DATAA}}) {
        return $self->showError("������������ ���������: � �� ���������� �������� ($id), ������������� � ����������� ��������") unless exists $self->{_DICTH}->{$id};
        unless (exists $self->{_NEWH}->{$id} && $self->{_NEWH}->{$id} == $id) {
            $del_sth->execute(@{$h->{PARAMS}},$id) or return $self->showError($DBI::errstr);
        };
    };
    foreach my $id (@{$self->{_NEWA}}) {
        return $self->showError("������������ ���������: ������� �������� ($id), ������������� � ����������� ��������") unless exists $self->{_DICTH}->{$id};
        unless (exists $self->{_DATAH}->{$id}) {
            $ins_sth->execute($id, @{$h->{PARAMS}}) or return $self->showError($DBI::errstr);
        };
    };
    return 1;
};

#sub HAS_ORDERING {
#    my $field = shift;
#    
#    my $options = $field->{OPTIONS} || {};
#    my $storage = $options->{STORAGE} || {};
#    
#    return 0 unless ($options->{STORE_FIELD} || $storage->{ORDER});
#    return $options->{ORDERING} if exists $options->{ORDERING};
#    return 1;
#};

sub getJSSetValue {
    #TODO: implement this method
    return "";
};

sub setValue {
    my $field = shift;
    my $value = shift; # Array of values
    
    die "mchbx: setValue();"
    
    #TODO: implement
};

sub value {
	my $field = shift;
    #TODO: implement
    
    die "mchbx: value()";
    
	return [];          # Array of values
};

sub dbFields {
    my ($field,$action) = (shift,shift);
    
    my $options = $field->{OPTIONS};
    
    my @fields = ();
    push @fields, $options->{STORE_FIELD} if $options->{STORE_FIELD};
    push @fields, $options->{STORE_NAME}  if $options->{STORE_NAME};
    return @fields;
};

sub dbValue {
    my ($self,$dbField) = (shift,shift);
    
    my $options = $self->{OPTIONS};
    return $self->{_value_id}    if defined $self->{_value_id}    && $options->{STORE_FIELD} && $options->{STORE_FIELD} eq $dbField;
    return $self->{_value_names} if defined $self->{_value_names} && $options->{STORE_NAME}  && $options->{STORE_NAME}  eq $dbField;
    
    die "mchbx: dbValue(): - do not know how to get dbValue for $dbField";
};

sub check {
    my $self = shift;
    if ($self->{IS_NOTNULL}) {
        if ($self->{_NEWA}) {
            #��� ����� setFormValue() �� ������� ������ �� ����.
            return $self->setErrorByCode("NOTHING_CHOOSEN") unless scalar @{$self->{_NEWA}};
            
            #��������, ��� ��� ��������� �������� ���������� � �����������
            return $self->_process();
        }
        elsif ($self->{_data_loaded}) {
            #������ setFormValue() �� ����, �� ���� �������� ������ �� ���������. ��������.
            return $self->setErrorByCode("NOTHING_CHOOSEN") unless scalar @{$self->{_DATAA}};
        };
        #�� ���� �� �������� ������ �� ���������, �� ����������� �������� �� �����. ��������� ������.
    };
    return $self->process();
};

sub process {
    my $self = shift;
    return 1 if defined $self->{_changed};
    return $self->_process();
};

sub _process {
    my $self = shift;
    
    unless (@{$self->{_NEWA}}) {
        $self->{_value_id}    = '';
        $self->{_value_names} = '';
        $self->{_changed}     = 1;
        $self->{_changed}     = 0 if $self->{_new};
        return 1;
    };
    
    unless ($self->{_dict_loaded}) {
        $self->_loadDict() or return undef;
    };
    
    my @names;
    foreach my $id (@{$self->{_NEWA}}) {
        return $self->showError("������������ ���������: ������� �������� ($id), ������������� � ����������� ��������") unless exists $self->{_DICTH}->{$id};
        push @names, $self->{_DICTH}->{$id};
    };
    
    my $options = $self->{OPTIONS};
    my $ns = $options->{STORE_NAME_SEPARATOR};
    $ns = ',' unless defined $ns;
    
    $self->{_value_id}    = join(',',@{$self->{_NEWA}});
    $self->{_value_names} = join($ns,@names);
    
    $self->{_changed} = 0;
    $self->{_changed} = 1 if $self->{_new} or join(',',@{$self->{_DATAA}}) ne join(',',@{$self->{_NEWA}});

    return 1;
};

sub selectedValuesCnt {
    my $self = shift;
    die '' unless $self->{_NEWA};
    return scalar @{$self->{_NEWA}};
};

sub changed {
    my $self = shift;
    die '_changed value is undefined' unless defined $self->{_changed};
    $self->{_changed};
};

sub clean {
    #TODO: implement ?
};

sub setLoadedValue {
    my ($self,$row) = (shift,shift);
    
    my $options = $self->{OPTIONS};
    $self->{_value_id} = $row->{$options->{STORE_FIELD}} || '' if $options->{STORE_FIELD};
    
    return 1; #�������� ��� ����� ������� �� $form.
}; 

sub beforeSave { return 1; };

sub beforeDelete {
    my $field = shift;

    my $options = $field->{OPTIONS};
    my $storage = $options->{STORAGE} or return 1;
    my $h = $field->_getKey($storage) or return 0;
    my $dbh = $field->dbh() or return $field->showError("beforeDelete(): ����������� dbh");
    my $sth = $dbh->do("DELETE FROM ".$storage->{TABLE}.$h->{WHERE},undef,@{$h->{PARAMS}}) or return $field->set_err("beforeDelete(): ������ �������� ��������: ".$DBI::errstr);
    return 1;
};

sub getFieldActions {
    my $self = shift;
    return [
        {ACTION=>"autocomplete", METHOD=>"doAutocomplete"},
        {ACTION=>"addrecord",    METHOD=>"addRecord"},
    ];
};

sub doAutocomplete {
    my $field = shift;
    my $is_ajax = shift;
    
    my $form = $field->parent();
    my $cms  = $field->cms();
    
    #��������� ������
    use Encode;
    my $term = $field->q()->param("term") || "";
    Encode::from_to($term, "utf-8", "windows-1251");
    
    $term =~s/\s$//;
    $term =~s/^\s//;
    $term =~ s/ +/ /;
    
    return $cms->outputJSON([]) unless length($term) >= 3;
    
    #��� ��������� ��������
    my $values = $field->q()->param("values") || "";
    my @vals = split(/,/,$values);
    my $n = scalar(@vals);

    my $options = $field->{OPTIONS};
    return $field->set_err("����������� ������� DICT") unless $options->{DICT};
    my $dict = $options->{DICT};
    
    my @params = ();
    @params = @{$dict->{PARAMS}} if exists $dict->{PARAMS};
    
    my $sql="SELECT ".$dict->{ID_FIELD}.",".$dict->{NAME_FIELD}." FROM ".$dict->{TABLE}." WHERE ";
    $sql .= $dict->{ID_FIELD}." NOT IN (".join(",", ("?") x $n).") AND " if $n;
    $sql .= $dict->{NAME_FIELD}." ILIKE ?";
    $sql .= " AND (".$dict->{WHERE}. ")"  if $dict->{WHERE};
    $sql .= " ORDER BY ".$dict->{ORDER} if $dict->{ORDER};
    #$sql .= " LIMIT $options->{LIMIT}" if($options->{LIMIT}); #TODO:
    
    push @vals,'%'.$term.'%';
    
    my $dbh = $field->dbh() or return $field->set_err("doAutocomplete(): ����������� dbh");
    
    my $sth = $dbh->prepare($sql) or return $field->set_err("������ �������� �������� multicheckbox: ".$DBI::errstr);
    $sth->execute(@vals,@params) or return $field->set_err($DBI::errstr);
    my @result = ();
    while (my ($id,$name) = $sth->fetchrow()) {
        push @result, {
            id   => $id,
            label=> $name,
        };
    };
    $sth->finish();
    return create_json(\@result);
};

sub addRecord{
    my $field = shift;
    
    my $cms = $field->cms();
    my $q   = $field->q();
    my $db  = $field->db();
    my $dbh = $field->dbh();
    
    my $options = $field->{OPTIONS};
    my $dict = $options->{DICT};
    return create_json({error=>"����������� ������� DICT"}) unless $dict;
    return create_json({error=>"���������� ����������� ���������"}) unless $dict->{ADDITION};
    return create_json({error=>'���������� �������� � ������� � �������� WHERE �� ��������������'}) if $dict->{WHERE};
    
    my $text = $q->param("value") || "";
    $text = Encode::decode("utf-8", $text);
    $text = Encode::encode("windows-1251", $text);
    $text =~s/\s+$//;
    $text =~s/^\s+//;
    $text =~ s/ +/ /g;
    
    return create_json({error=>'����������� �������� �� �������'}) unless $text && !is_empty($text);
    
    my $sql= "select ".$dict->{ID_FIELD}." as id,".$dict->{NAME_FIELD}." as label FROM ".$dict->{TABLE}." WHERE ".$dict->{NAME_FIELD}." ILIKE ?";
    my $sth=$dbh->prepare($sql) or return create_json({error=>"������ ��: ".$DBI::errstr});
    $sth->execute('%'.$text.'%')  or return create_json({error=>"������ ��: ".$DBI::errstr});
    my $row1=$sth->fetchrow_hashref();
    if ($row1) {
        my $row2=$sth->fetchrow_hashref();
        return create_json({error=>'� ����������� ������� ��������� �������, ���������� "'.$text.'"'}) if $row2;
    };
    return create_json({id=>$row1->{id},label=>$row1->{label}}) if $row1;
    
    my $id = $db->get_id($dict->{TABLE},$dict->{ID_FIELD});
    return create_json({error=>"������ �� ��� ��������� ���� ����� ������: ".$DBI::errstr}) unless $id;
    $dbh->do("INSERT INTO ".$dict->{TABLE}." (".$dict->{ID_FIELD}.",".$dict->{NAME_FIELD}.") VALUES (?,?)",undef,$id,$text) or return create_json({error=>"������ �� ��� ������� ������: ".$DBI::errstr});
    return create_json({id=>$id,label=>$text});
};

1;


=head
    �������� ����������������
    
    #TODO: �������� "����" ������� ����� ���������� ������������ ������ ���������, �� ������ � ��.
    # �.�. �������� ����� ����� ������ �������� � ��������� ���������� ������, ������ ��� ��� ����� �� ������ � ����� (������� ���������� - colorscount>0)
{
    FIELD => "some_name",      # ������������ � ������� ���������� ��������������� �����. �� �������� ������� ���� � ���� ������ �� �������������.
    TYPE  => "multicheckbox",  # multicheckbox | multiselect |multivalue
                
                multivalue - ����������� �����. ��������� ������, �������� �������� - ����� ������� � ����� ���� HTTP �������
                
    NAME  => "�������� �����",
    IS_NOTNULL => [0|1],       # �������������� ������ ���� ������ ��������
    
    SIZE => 12,                # ������ ������ multiselect
    
    OPTIONS => {
        #### �������� �������
        # I - ������� � ���� ������� ��, ����������� SQL-��������
        DICT=>{
            ID_FIELD=>"id",     # �� ��������� id
            NAME_FIELD=>"name", # �� ��������� name
            
            DEFAULT_FIELD=>"defa", # TODO: default
            
            QUERY => "",        # SQL-������
            
            TABLE => "",        # ... ��� �������
            WHERE => "",        # ��� where
            ORDER => "",        # ��� order by
            
            PARAMS=> [],        # ��������� ��� QUERY ��� TABLE
            
            ADDITION  => 1,         #��������� ��������� ���������� (����������� � ������ multivalue)
            
            #TODO: �������� ������� ����������� ��������
        },
        # II - �������, ������ �������� � ������������
        VALUES => [
            {ID=>1,NAME=>"Name_Id1"},
            {ID=>2,NAME=>"Name_Id2",DEFAULT=>1},  #TODO: default
            {ID=>3,NAME=>"Name_Id3"},
        ],
        #### �������� ���������� ��������
        #���������� ��������� �������� � ������� ��������� ������-��-������
        STORAGE => {
            TABLE => "table",             #��� ������� �����
            FIELD => "dict_id",           #��� ���� ��� ���������� ID ��������� ��������
            FIELDS_MAP => {               #����� ������������� ����� �������� ������� � ������� �����
                storage_field1=>'record_field1',   #���� ����� => ���� �������� �������
                storage_field2=>'record_field2',
            },
            ORDER => 'order_field',       #��� ���� ��� ���������� ������� ��������� �������� � multivalue
        },
        #���������� ��������� �������� � ���� �������� �������, � ���� ������ �����, ����������� �������
        STORE_FIELD => "movie_actor_id",   #��� ���� � �������� �������. ���� STORAGE �����������, �� STORE_FIELD ��-��������� ����� FIELD
        
        #���������� ��������� �������� � ���� �������� �������, � ���� ������ �������� � ������������
        STORE_NAME  => "movie_actor_text", #��� ���� � �������� �������
        STORE_NAME_SEPARATOR => ", "       #����������� ����������� ��������
        ORDERING => (0|1),                 #���������/��������� ������ ���������� ��� ������������� STORE_FIELD ��� STORAGE.ORDER. Default=1
        
        ## + ����� �������� �������� ������� ��������� - ����� ��� ������ �� ������������
        ## + �������� ����� ������������ � ������������� ���������� ��������� ��������
    },
}
=cut
