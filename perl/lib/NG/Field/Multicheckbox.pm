package NG::Field::Multicheckbox;
use strict;

#TODO: �������� ��������� ��������
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
    $field->{_NEWH}  = {};    #�����������  �������� (��������� �� �����)
    $field->{_DICTH} = {};    #������ ������� (����=�������� = id ��������), ���, ��� �������� �������� _DATAH � _NEWH
    $field->{SELECT_OPTIONS} = [];
    
    $field->{_dict_loaded} = 0;
    $field->{_data_loaded} = 0;
    
    my $options = $field->{OPTIONS} || return $field->set_err("��� ���� $field->{FIELD} ���� multicheckbox �� ������� �������������� ���������");
    return $field->set_err("�������� OPTIONS �� �������� HASHREF") if ref $options ne "HASH";
    
    if ($options->{DICT}) {
        return $field->set_err("�������� �������� DICT ������������ ���� $field->{FIELD} ���� multicheckbox �� �������� ������� �� ���") if ref $options->{DICT} ne "HASH";
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
        
        foreach my $p (@{$options->{VALUES}}) {
            return $field->set_err("�������� ������� VALUES ���� $field->{FIELD} �� �������� �����.") if ref $p ne "HASH";
            my $id = $p->{ID};
            return $field->set_err("� ������ �������� VALUES ���� $field->{FIELD} ����������� �������� ����� ID ") if (!$id && $id != 0);
            $p->{NAME} || return $field->set_err("� ������ �������� VALUES ���� $field->{FIELD} ����������� �������� ����� NAME");
            $field->{_DICTH}->{$id} = $id;
            $field->{SELECT_OPTIONS} = $options->{VALUES};
        };
        $field->{_dict_loaded} = 1;
    }
    else {
        return $field->set_err("����������� ����� ������ �������� DICT ��� VALUES.");
    };
    
    unless ($field->{NOLOADDICT}) {
        return $field->set_err("�������� �������� STORAGE ������������ ���� $field->{FIELD} ���� multicheckbox �� �������� ������� �� ���") if ref $options->{STORAGE} ne "HASH";
        my $storage = $options->{STORAGE};
        
        return $field->set_err("�� ������� ��� ������� (TABLE) � �������� STORAGE ���� $field->{FIELD}") unless $storage->{TABLE};
        return $field->set_err("�� ������� ��� ���� ������ (FIELD) � �������� STORAGE ���� $field->{FIELD}") unless $storage->{FIELD};
        return $field->set_err("�� ������ ��� ����� ����� �������� ������� � ��������� ��������� ��������� (FIELDS_MAP) � �������� STORAGE ���� $field->{FIELD}") unless $storage->{FIELDS_MAP};
        return $field->set_err("�������� FIELDS_MAP � �������� STORAGE ���� $field->{FIELD} �� �������� �����") unless ref $storage->{FIELDS_MAP} eq "HASH";
        return $field->set_err("����������� ����� � ��������� FIELDS_MAP �������� STORAGE ���� $field->{FIELD}") unless scalar keys %{$storage->{FIELDS_MAP}};
    };        
   
    $field->pushErrorTexts({
        NOTHING_CHOOSEN       => "�� ������� ��������.",
    });
    
    $field->{IS_FAKEFIELD}=1;
    return 1;
};

sub _loadDict {
    my $field = shift;
    
    my $options = $field->{OPTIONS};
    return $field->set_err("����������� ������� DICT") unless $options->{DICT};
    my $dict = $options->{DICT};
    
    return $field->set_err('DATA not loaded') unless defined $field->{_DATAH};
    
    my $sql = $dict->{_SQL} or return $field->set_err("NG::Field::Multicheckbox::prepareOutput(): ����������� �������� �������. ������ ������������� ����.");
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
            SELECTED=>((exists $field->{_DATAH}->{$id}) && ($id eq $field->{_DATAH}->{$id}))?1:0,
        };
        $field->{_DICTH}->{$id} = $id;
    };
    $sth->finish();
    
    my $cnt = scalar @result;
    $field->{SIZE} ||= $cnt if $field->{TYPE} eq "multiselect";
    
    $result[int($cnt/2)]->{HALF} = 1 if $cnt > 1;
    
    $field->param('SELECT_OPTIONS',\@result);
    $field->{_dict_loaded} = 1;
    return 1;
};

sub prepareOutput {
    my $field = shift;
    
    my $options = $field->{OPTIONS};
    return $field->set_err("����������� ������� DICT") unless $options->{DICT};
    my $dict = $options->{DICT};
    
    if ($field->{TYPE} eq 'multivalue') {
        #���������� ��������� �� ���������, ������� ����� ��������� ������ ��������
        my @params = ();
        @params = @{$dict->{PARAMS}} if exists $dict->{PARAMS};
        
        return $field->set_err('DATA(A) not loaded') unless defined $field->{_DATAA};
        
        my $placeholders = "";
        foreach my $id (@{$field->{_DATAA}}) {
            $placeholders.="?,";
            push @params, $id;
        };
        $placeholders =~s /,$//;
        
        my $sql="SELECT ".$dict->{ID_FIELD}.",".$dict->{NAME_FIELD}." FROM ".$dict->{TABLE}." WHERE ";
        $sql .= $dict->{WHERE}. " AND "  if $dict->{WHERE};
        $sql .= $dict->{ID_FIELD}." IN (".$placeholders.")";
        $sql .= " ORDER BY ".$dict->{ORDER} if $dict->{ORDER};
        
        
        my $dbh = $field->dbh() or return $field->set_err("_loadDict(): ����������� dbh");
        
        my $sth = $dbh->prepare($sql) or return $field->set_err("������ �������� �������� multicheckbox: ".$DBI::errstr);
        $sth->execute(@params) or return $field->set_err($DBI::errstr);
        my @result = ();
        my $value  = "";
        while (my ($id,$name) = $sth->fetchrow()) {
            push @result, {
                ID=>$id,
                NAME=>$name,
            };
            $value .= $id.',';
        };
        $sth->finish();
        $value =~s /,$//;
        
        $field->{SELECTED_OPTIONS} = \@result;
        $field->{SELECTED_ID} = $value;
        
        return 1;
    };
    
    unless ($field->{_dict_loaded}) {
        $field->_loadDict() or return undef;
    };
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
    my $storage = $options->{STORAGE} or return $field->showError("afterLoad(): ����������� ����� STORAGE");
    
    my $h = $field->_getKey($storage) or return 0;
    my $sql="select ".$storage->{FIELD}." from ".$storage->{TABLE}.$h->{WHERE};
    my $dbh = $field->dbh() or return $field->showError("afterLoad(): ����������� dbh");
    
    my $sth = $dbh->prepare($sql) or return $field->set_err("������ �������� �������� multicheckbox: ".$DBI::errstr);
    $sth->execute(@{$h->{PARAMS}}) or return $field->set_err($DBI::errstr);
    
    $field->{_DATAH} = {};
    $field->{_DATAA} = [];
    while (my ($id) = $sth->fetchrow()) {
        $field->{_DATAH}->{$id} = $id; #������ (��������� ��������), ���
        push @{$field->{_DATAA}}, $id; 
        #return $field->showError("������������ ��������� ��: ���������� �������� ($id), ������������� � ����������� ��������") unless exists $field->{_DICTH}->{$id} && $id == $field->{_DICTH}->{$id};
    };
    $sth->finish();
    $field->{_data_loaded} = 1;
    return 1;
};

sub setFormValue {
    my $field = shift;
    
    my $q = $field->parent()->q();
    
    if ($field->{TYPE} eq 'multivalue') {
        $field->{_NEWH} = {};
        foreach my $id (split /,/,$q->param($field->{FIELD})){
            $field->{_NEWH}->{$id} = $id;
        }
        return 1;
    };
    
    $field->{_NEWH} = {};
    foreach my $id ($q->param($field->{FIELD})) {
        $field->{_NEWH}->{$id} = $id;
    };
    return 1;
};

sub afterSave {
    my $self = shift;

    unless ($self->{_dict_loaded}) {
        $self->_loadDict() or return undef;
    };
    
    return $self->set_err('DATA(H) not loaded') unless defined $self->{_DATAH};
    return $self->set_err('DATA(A) not loaded') unless defined $self->{_DATAA};
    
    my $options = $self->{OPTIONS};
    my $storage = $options->{STORAGE} or return $self->showError("afterSave(): ����������� ����� STORAGE");
    my $h = $self->_getKey($storage) or return 0;
    
    my $dbh = $self->dbh() or return $self->showError("afterSave(): ����������� dbh");
    
    my $ins_sth = $dbh->prepare("insert into ".$storage->{TABLE}." (".$storage->{FIELD}.",".$h->{FIELDS}.") values (?,".$h->{PLHLDRS}.")");
    my $del_sth = $dbh->prepare("delete from ".$storage->{TABLE}.$h->{WHERE}." and ".$storage->{FIELD}."=?");
    #TODO: �������� ������ �� ����� ?
    foreach my $id (@{$self->{_DATAA}}) {
        return $self->showError("������������ ���������: � �� ���������� �������� ($id), ������������� � ����������� ��������") unless exists $self->{_DICTH}->{$id} && $id == $self->{_DICTH}->{$id};
        unless (exists $self->{_NEWH}->{$id} && $self->{_NEWH}->{$id} == $id) {
            $del_sth->execute(@{$h->{PARAMS}},$id) or return $self->showError($DBI::errstr);
        };
    };
    foreach my $id (keys %{$self->{_NEWH}}) {
        return $self->showError("������������ ���������: ������� �������� ($id), ������������� � ����������� ��������") unless exists $self->{_DICTH}->{$id} && $id == $self->{_DICTH}->{$id};
        unless (exists $self->{_DATAH}->{$id} && $self->{_DATAH}->{$id} == $id) {
            $ins_sth->execute($id, @{$h->{PARAMS}}) or return $self->showError($DBI::errstr);
        };
    };
    return 1;
};

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

sub dbValue {
    croak "mchbx: dbValue();"
};

sub check {
    my $self = shift;
    
    return 1 unless $self->{IS_NOTNULL};
    return 1 if scalar keys %{$self->{_NEWH}};
    return $self->setErrorByCode("NOTHING_CHOOSEN");
};

sub clean {
    #TODO: implement ?
};

sub beforeSave {
	my $self = shift;
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
    
    my $dbh = $field->dbh() or return $field->set_err("_loadDict(): ����������� dbh");
    
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
    $text =~s/\s$//;
    $text =~s/^\s//;
    $text =~ s/ +/ /;
    
    return create_json({error=>'����������� �������� �� �������'}) unless $text && !is_empty($text);
    
    my $sql= "select ".$dict->{ID_FIELD}." as id,".$dict->{NAME_FIELD}." as label FROM ".$dict->{TABLE}." WHERE ".$dict->{NAME_FIELD}." ILIKE ?";
    my $sth=$dbh->prepare($sql) or return create_json({error=>"������ ��: ".$DBI::errstr});
    $sth->execute('%'.$text.'%')  or return create_json({error=>"������ ��: ".$DBI::errstr});
    my $row1=$sth->fetchrow_hashref();
    my $row2=$sth->fetchrow_hashref();
    
    return create_json({error=>'� ����������� ������� ��������� �������, ���������� "'.$text.'"'}) if $row2;
    return create_json({id=>$row1->{id},label=>$row1->{label}}) if $row1;
    
    my $id = $db->get_id($dict->{TABLE},$dict->{TABLE}."_id");
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
    FIELD => "some_name",      # ������������ � ������� ���������� ��������������� �����
    TYPE  => "multicheckbox",  # multicheckbox | multiselect |multivalue
                
                multivalue - ����������� �����. ��������� ������, �������� �������� - ����� ������� � ����� ���� HTTP �������
                
    NAME  => "�������� �����",
    IS_NOTNULL => [0|1],       # �������������� ������ ���� ������ ��������
    
    SIZE => 12,                # ������ ������ multiselect
    
    OPTIONS => {
        # I - SQL part
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
        # II - configured part
        VALUES => [
            {ID=>1,NAME=>"Name_Id1"},
            {ID=>2,NAME=>"Name_Id2",DEFAULT=>1},  #TODO: default
            {ID=>3,NAME=>"Name_Id3"},
        ],
        
        STORAGE => {
            TABLE => "table",
            FIELD => "dict_id",
            FIELDS_MAP => {storage_field1=>'record_field1',storage_field2=>'record_field2',},
        },
        ## + ����� �������� �������� ������� ��������� - ����� ��� ������ �� ������������
        ## + �������� ����� ������������ � ������������� ���������� ��������� ��������
    },
}
=cut
