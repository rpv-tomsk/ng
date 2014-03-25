package NG::Field::Select;
use strict;

#TODO: �������� ����� ������ ���� ��� ��������.
#TODO: ����������� check
#TODO: ��������� ����������.
#TODO: selectedName(), setValue() value() ������ ���� ��������� �� ��������.
#TODO: ������� ���������, �������� �� ��������� �������� ��� �������� ����� DISABLED
#TODO: default_null

use NG::Field;
use NHtml;

use vars qw(@ISA);
@ISA = qw(NG::Field);

sub init {
    #TODO: ����������� ���������� �� ������. �������� ����������� ������ ������ ��� ������ �� �����. �������� ������� ���������� �� ���������� ���������� �� ���� � ��� ����� 
    my $field = shift;
    #$field->{TEMPLATE} ||= "admin-side/common/fields/multicheckbox.tmpl";

    $field->{TYPE}= "select" if $field->{TYPE} eq "fkselect"; #NB: ��� ��� ����������� �������� �������������    
    
    $field->SUPER::init(@_) or return undef;
    
    $field->parent() or return 0; ## ������ ������� ����� ��������� ������
    $field->db() or return 0; 
    
    $field->{_dict_loaded} = 0;         #������� ���������
    $field->{_prepared} = 0;            #����������� ��������� ������ �����, �������� ��������� �������� "�� �������"/"�������� ��������"
    $field->{_prepare_adds_option} = 0; #��������� ������ ����� �������� ������� �������������� �������
    $field->{_defoption} = undef;       #�����, ������� ����� ��������� �� ����� option.DEFAULT
    $field->{_selected_option} = undef; #������� ��������� � ������ �����

    my $options = undef;
    if (exists $field->{OPTIONS}) {
        $options = $field->{OPTIONS};
        return $field->set_err("�������� OPTIONS �� �������� HASHREF") if ref $options ne "HASH";
    };

    if (exists $field->{SELECT_OPTIONS}) {
        return $field->set_err("�������� �������� SELECT_OPTIONS ���� $field->{FIELD} �� �������� ������� �� ������") if ref $field->{SELECT_OPTIONS} ne "ARRAY";
        if ($options) {
            return $field->set_err("������� SELECT_OPTIONS ����������� � �������� OPTIONS.QUERY � OPTIONS.TABLE") if exists $options->{QUERY} || exists $options->{TABLE};
        };
        $field->setSelectOptions($field->{SELECT_OPTIONS}) or return undef;
    }
    else {
        $options || return $field->set_err("��� ���� $field->{FIELD} �� ������ �������� ��������� ������ ������ ��������");
        $options->{ID_FIELD}  ||= "id";
        $options->{NAME_FIELD}||= "name";
        if (exists $options->{PARAMS}) {
            return $field->set_err("�������� �������� PARAMS ������������ ���� $field->{FIELD} ���� fkselect �� �������� ������� �� ������") if ref $options->{PARAMS} ne "ARRAY";
            return $field->set_err("������� PARAMS ���������� ��� ��������� WHERE ��� QUERY") unless ($options->{WHERE} || $options->{QUERY});
        };
        if ($options->{QUERY}) {
            return $field->set_err("������� QUERY ����������� � ���������� TABLE, WHERE � ORDER") if ($options->{TABLE} || $options->{WHERE} || $options->{ORDER});
            $options->{_SQL} = $options->{QUERY};
        }
        else {
            $options->{TABLE} || return $field->set_err("��� ���� $field->{FIELD} ���� fkselect �� ������� ��� ������� �� ����������");
            my $sql="select ".$options->{ID_FIELD}.",".(exists($options->{NAME_FIELD_QUERY}) ? $options->{NAME_FIELD_QUERY} : $options->{NAME_FIELD});
            
            $sql.=",".$options->{DISABLE_FIELD} if $options->{DISABLE_FIELD};
            $sql.=",".$options->{DEFAULT_FIELD} if $options->{DEFAULT_FIELD};
            $sql.=",".$options->{PRIVILEGE_FIELD} if $options->{PRIVILEGE_FIELD};
            
            $sql.=" from ".$options->{TABLE};
            if ($options->{WHERE}) { $sql .= " where ".$options->{WHERE};    };
            if ($options->{ORDER}) { $sql .= " order by ".$options->{ORDER}; };
            $options->{_SQL} = $sql;
        };
        $field->{SELECT_OPTIONS} = [];
    };
    
    $field->{NULL_VALUE} = 0 unless exists $field->{NULL_VALUE};
    $field->pushErrorTexts({
        NONEXISTENT_VALUE => "������� �������������� �������� ����������� � ���� \"{n}\"",
        NOT_CHOOSEN       => "�������� ���� \"{n}\" �� �������",
    });
    return 1;
};

sub _loadFKSelect {
    my $field = shift;

    my $options = $field->{OPTIONS};
    my $sql = $options->{_SQL} or return $field->set_err("NG::Field::Select::prepareOutput(): ����������� �������� �������. ������ ������������� ����.");
    my @params = ();
    @params = @{$options->{PARAMS}} if (exists $options->{PARAMS});
    
    my $dbh = $field->dbh() or return $field->showError("_loadFKSelect(): ����������� dbh");
    
    my $sth = $dbh->prepare($sql) or return $field->showError("������ �������� �������� fkselect: ".$DBI::errstr);
    $sth->execute(@params) or return $field->showError($DBI::errstr);
    my @result = ();
    while (my $row = $sth->fetchrow_hashref()) {
        my $o = {};
        $o->{ID} = $row->{$options->{ID_FIELD}};
        $o->{NAME} = $row->{$options->{NAME_FIELD}};
        $o->{DEFAULT} = $row->{$options->{DEFAULT_FIELD}} if $options->{DEFAULT_FIELD};
        $o->{DISABLED} = $row->{$options->{DISABLE_FIELD}} if $options->{DISABLE_FIELD};
        $o->{PRIVILEGE} = $row->{$options->{PRIVILEGE_FIELD}} if $options->{PRIVILEGE_FIELD};
        push @result, $o;
    };
    $sth->finish();
    return $field->setSelectOptions(\@result);
};

sub setSelectOptions {
    my $field = shift;
    my $so    = shift;
    
    return $field->set_err("setSelectOptions(): ������������ �������� ������ ��������.") unless ($so && ref $so eq 'ARRAY');
    
    $field->{_prepared} = 0;
    $field->{_prepare_adds_option} = 0;
    $field->{_selected_option} = undef; #������� ��������� � ������ �����
    $field->{_defoption} = undef;       #�����, ������� ����� ��������� �� ����� option.DEFAULT
    my $seloption = undef;              #�����, ������� ����� ��������� �� ����� option.SELECTED

    my @o = ();
    foreach my $t (@{$so}) {
        return $field->set_err("�������� ������� SELECT_OPTIONS ���� $field->{FIELD} �� �������� �����.") if ref $t ne "HASH";
        return $field->set_err("� �������� ������ �������� SELECT_OPTIONS ���� $field->{FIELD} ����������� �������� ����� ID ") unless exists $t->{ID} && defined $t->{ID};
        return $field->set_err("� �������� ������ �������� SELECT_OPTIONS ���� $field->{FIELD} ����������� �������� ����� NAME") unless exists $t->{NAME} && defined $t->{NAME};
        
        my $p = {};
        $p->{ID} = $t->{ID};
        $p->{NAME} = $t->{NAME};
        $p->{SELECTED} = $t->{SELECTED} if exists $t->{SELECTED};
        $p->{DEFAULT} = $t->{DEFAULT} if exists $t->{DEFAULT};
        $p->{DISABLED} = $t->{DISABLED} if exists $t->{DISABLED};
        $p->{PRIVILEGE} = $t->{PRIVILEGE} if exists $t->{PRIVILEGE};
        
        $field->{_defoption} = $p if exists $p->{DEFAULT} && $p->{DEFAULT};
        $field->{_selected_option} = $p if (exists $field->{VALUE} && $field->{VALUE} eq $p->{ID});
        if (exists $p->{SELECTED} && $p->{SELECTED}) {
            delete $seloption->{SELECTED} if $seloption; # ������, ���� � ������ ��������� ����� � ������ SELECTED
            $seloption = $p;
        };
        push @o, $p;
    };
    if ($seloption) {
        $field->{_selected_option} = $seloption;
        $field->{VALUE} = $seloption->{ID};
        $field->{DBVALUE} = $seloption->{ID};
        $field->{_changed} = 1;
    };
    
    $field->{_selected_option}->{SELECTED}=1 if $field->{_selected_option};
    $field->{SELECT_OPTIONS} = \@o;
    $field->{_dict_loaded} = 1;
    
    return 1;
};

sub setDefaultValue {
    my $field = shift;
    
    #option.DEFAULT ����� ��������� ��� ���������, ��������� � field->{DEFAULT}.
    #���� ��� �� ���� �� ������� - ����������� ����� DEFAULT_FIRST
    
    my $options = $field->{OPTIONS} || {};
    if ($field->{_defoption}) {
        delete $field->{_selected_option}->{SELECTED} if $field->{_selected_option};
        $field->{_selected_option} = $field->{_defoption};
        $field->{_selected_option}->{SELECTED} = 1;
        $field->{VALUE} = $field->{_selected_option}->{ID};
        $field->{DBVALUE} = $field->{_selected_option}->{ID};
        $field->{_changed} = 1;
    }
    elsif (exists $field->{DEFAULT}) {
        $field->setValue($field->{DEFAULT});
    }
    elsif (exists $options->{DEFAULT_FIRST} && $options->{DEFAULT_FIRST} && scalar @{$field->{SELECT_OPTIONS}} > 0) {
        delete $field->{_selected_option}->{SELECTED} if $field->{_selected_option};
        $field->{_selected_option} = @{$field->{SELECT_OPTIONS}}[0];
        $field->{_selected_option}->{SELECTED} = 1;
        $field->{VALUE} = $field->{_selected_option}->{ID};
        $field->{DBVALUE} = $field->{_selected_option}->{ID};
        $field->{_changed} = 1;
    };
};

sub _prepare {
    my $field = shift;
    
    unless ($field->{_dict_loaded}) {
        $field->_loadFKSelect() or return 0;
    };
    return 1 if $field->{_prepared} == 1;
    
    #���� ����� ������:
    #  - ���� ���� ������������: IS_NOTNULL=>1
    #    + ���� �������� �� �� ����, �.�. ����� ����� ���� - ��� ������������� ������ ���������.
    #    + ��� ��������� ������ ��� ����, � ��������� ������ ���������: options.DEFAULT_FIRST=1
    #    + ��� ��������� � ������ ������ options.TEXT_IS_NEW || "�������� ��������" (ID=0)
    #  - ���� ���� �� ������������: IS_NOTNULL=>0
    #    + �������� ������ ������� ��������, ���� ���� options.DEFAULT_FIRST=1
    #    + ��������� ������ ������� options.TEXT_IS_NULL || "�� �������" (ID=0)
    my $options = $field->{OPTIONS} || {};
    
    my $defaultFirst = 0;
    $defaultFirst = 1 if exists $options->{DEFAULT_FIRST} && $options->{DEFAULT_FIRST};

    if (!$field->{_selected_option} && $defaultFirst && scalar @{$field->{SELECT_OPTIONS}}) {
        #NB: �� ���������� �������� ��������� ����� ��� �������� ����, ������ ��� �����������.
        @{$field->{SELECT_OPTIONS}}[0]->{SELECTED} = 1;
    };
    
    #��� ���� �������: $field->{_new}==1
    $field->{_prepare_adds_option} = 0;
    if ($field->{IS_NOTNULL}) {
        my $text = "";
        $text = $options->{TEXT_IS_NEW} if exists $options->{TEXT_IS_NEW} && $options->{TEXT_IS_NEW};
        $text ||= "�������� ��������";
        unless ($field->{_selected_option} || $defaultFirst || (scalar @{$field->{SELECT_OPTIONS}} == 1) || $field->{TYPE} eq "radiobutton") {
            $field->{_prepare_adds_option} = 1;
            unshift @{$field->{SELECT_OPTIONS}},{
                ID   => $field->{NULL_VALUE},
                NAME => $text,
            };
        };
    }
    else {
        my $text = "";
        $text = $options->{TEXT_IS_NULL} if exists $options->{TEXT_IS_NULL} && $options->{TEXT_IS_NULL};
        $text ||= "�� �������";
        $field->{_prepare_adds_option} = 1;
        unshift @{$field->{SELECT_OPTIONS}},{
            ID   => $field->{NULL_VALUE},
            NAME => $text,
        };
    };
    $field->{_prepared} = 1;
    return 1;
};

sub prepareOutput {
    my $field = shift;
    $field->_prepare() or return 0;
    return 1;
};

sub _setDBValue {
    my $field = shift;
	my $value = shift;
	
	$field->{DBVALUE} = $value;
	$field->{VALUE} = $value;
    $field->{_selected_option}=undef;
    foreach my $opt (@{$field->{SELECT_OPTIONS}}) {
        delete $opt->{SELECTED};
        if (defined $value && $opt->{ID} eq $value) {
            $opt->{'SELECTED'}=1;
            #$field->{VALUE} = $opt->{NAME};
            $field->{_selected_option} = $opt;
        };
    };
    return 1;
};

sub _setValue {
	my $field = shift;
	my $value = shift;
	
    $field->{VALUE} = $value;
    $field->{DBVALUE} = $value;

    $field->{_selected_option}=undef;
    foreach my $f (@{$field->{SELECT_OPTIONS}}) {
        delete $f->{SELECTED};
        if (defined $value && $f->{ID} eq $value) {
            $f->{SELECTED} = 1;
            $field->{_selected_option} = $f;
        };
    };
    
    $field->{_changed} = 1;
    return 1;
};

sub value {
    #TODO: ��������� ��������� NG::Field::value()
	my $field = shift;
	return $field->{VALUE};
};

sub dbValue {
    my $field = shift;
    return $field->{DBVALUE};
};

sub _getSOFromDB {
    my $field = shift;

    my $options = $field->{OPTIONS};
    my $sql = $options->{_SQL} or return $field->set_err("NG::Field::Select::selectedName(): ����������� �������� �������. ������ ������������� ����.");
    
    my @params = ();
    @params = @{$options->{PARAMS}} if (exists $options->{PARAMS});
    
    $sql = "select s.* from ($sql) s where s.".$options->{ID_FIELD}."=?";
    push @params, $field->{VALUE};

    my $dbh = $field->dbh() or return $field->showError("_loadFKSelect(): ����������� dbh");        
    my $sth = $dbh->prepare($sql) or return $field->showError("������ �������� �������� fkselect: ".$DBI::errstr);
    $sth->execute(@params) or return $field->showError($DBI::errstr);
    my $row = $sth->fetchrow_hashref() or return undef;
    $sth->finish();
    
    my $so = {};
    $so->{ID} = $row->{$options->{ID_FIELD}};
    $so->{NAME} = $row->{$options->{NAME_FIELD}};
    $so->{DEFAULT} = $row->{$options->{DEFAULT_FIELD}} if $options->{DEFAULT_FIELD};
    $so->{DISABLED} = $row->{$options->{DISABLE_FIELD}} if $options->{DISABLE_FIELD};
    $so->{PRIVILEGE} = $row->{$options->{PRIVILEGE_FIELD}} if $options->{PRIVILEGE_FIELD};
    return $so;
};

sub selectedName {
    my $field = shift;
    
    if ($field->{_selected_option}) {
        return $field->{_selected_option}->{NAME};
    };
    
    if ($field->{_dict_loaded}) {
        #die "NG::Field::Select::selectedName(): Dictionary loaded but no selected option exists";
        return "[no dict]";
    };
    
    return "" unless $field->{VALUE};
    my $so = $field->_getSOFromDB();
    $field->{_selected_option} = $so if $so;
    return "" unless $field->{_selected_option};
    return $field->{_selected_option}->{NAME};
};
*SELECTEDNAME = \&selectedName;

sub selectOptions {
	my $field = shift;

    if ($field->{_dict_loaded}==0) {
        $field->_loadFKSelect() or return undef;
    };
    if ($field->{_prepare_adds_option} == 1) {
        $field->{_prepared} = 0;
        $field->{_prepare_adds_option} = 0;
        shift @{$field->{SELECT_OPTIONS}};
    };
    return $field->{SELECT_OPTIONS};
};

sub getJSSetValue {
    my $field = shift;
    
    my $fd = $field->{FIELD};
    my $value = escape_js $field->{VALUE};
    my $key_value = $field->parent()->getComposedKeyValue();
    
    $field->_prepare() or return "alert('".$field->error()."');";
    
    if ($field->{TYPE} eq "radiobutton") {
        my $update = "parent.document.getElementById('$fd$key_value').innerHTML='';\n";
        foreach my $option (@{$field->{SELECT_OPTIONS}}) {
            $update .= "e = document.createElement('input'); e.type='radio';";
            $update .= "e.name='".$field->{FIELD}."';";
            $update .= "e.value='".(escape_js $option->{ID})."';";
            $update .= "e.checked=true;\n" if $option->{SELECTED};
            $update .= "e.disabled=true;\n" if $option->{DISABLED};
            
            $update .= "parent.document.getElementById('$fd$key_value').appendChild(e);";
            $update .= "t = document.createTextNode('".(escape_js $option->{NAME})."');";
            $update .= "parent.document.getElementById('$fd$key_value').appendChild(t);";
            $update .= "e = document.createElement('br');";
            $update .= "parent.document.getElementById('$fd$key_value').appendChild(e);";
        };
        return $update;
    }
    elsif ($field->{TYPE} eq "select") {
        my $i = 0;
        my $update = "parent.document.getElementById('$fd$key_value').options.length=0;\n";
        foreach my $option (@{$field->{SELECT_OPTIONS}}) {
            $update .= "o = new Option('".(escape_js $option->{NAME})."','".(escape_js $option->{ID})."',false,".($option->{SELECTED}?"true":"false").");\n";
            $update .= "o.disabled=true;\n" if $option->{DISABLED};
            $update .= "parent.document.getElementById('$fd$key_value').options[$i]= o;\n";
            $i++;
        };
        $update .= "parent.document.getElementById('$fd$key_value').value='$value';\n";
        return $update;
    }
    else {
        return "alert('Unknown field type ".$field->{TYPE}." in NG::Field::Select::getAjaxSetValue()')";
    };
    
};


sub check {
    my $field = shift;
    
    unless ($field->{_selected_option}) {
        if ($field->{VALUE} && !$field->{_dict_loaded}) {
            #Dict not loaded, try to load SO
            my $so = $field->_getSOFromDB();
            $field->{_selected_option} = $so if $so;
        };
    };
    
    unless ($field->{_selected_option}) {
        my $nullValue = $field->{NULL_VALUE};
        if ($field->{VALUE} && $field->{VALUE} ne $nullValue) {
            return $field->setErrorByCode("NONEXISTENT_VALUE");
        };
        if ($field->{IS_NOTNULL} && $field->{VALUE} eq $nullValue) {
            return $field->setErrorByCode("NOT_CHOOSEN");
        };
    };
    return $field->SUPER::check(@_);
};


1;


=head

�������� ����������������
{
    FIELD => "some_name",      # ������������ � ������� ���������� ��������������� �����
    TYPE  => "select",         # select | radiobutton
    NAME  => "���������",
    IS_NOTNULL => [0|1],       # �������������� ������ ���� ������ ��������
    DEFAULT => 12,             # ����� �� ������ ����� � ������ DEFAULT ���
                               # �� ���� DEFAULT_FIELD ����������� ����� ���������.
	
    #��������� �� ������ SELECTED ����� �������������� �������� VALUE, ������� ������� �� ������ ������ setSelectOptions
    SELECT_OPTIONS => [        # ������ ��������� ������ ��� select
        {NAME=>"�������� ���� ������",ID=>"0"},
        {NAME=>"�����������",ID=>"1"},
        {NAME=>"�������",ID=>"2"},
        {NAME=>"�����",ID=>"3"},
        {NAME=>"�������",ID=>"4"},
        {NAME=>"�������",ID=>"5"},
        {NAME=>"�������",ID=>"6"},
        {NAME=>"�����������",ID=>"7",PRIVILEGE=>"SUNDAY_PRIVILEGE",DEFAULT=>1,DISABLED=1,SELECTED=>1},
    ],
    
    #����� ���� OPTIONS, ������������� �� ����� �������� ()
    #���� ����� ������:
    #  - ���� ���� ������������: IS_NOTNULL=>1
    #    + ���� �������� �� �� ����, �.�. ����� ����� ���� - ��� ������������� ������ ���������.
    #    + ��� ��������� ������ ��� ����, � ��������� ������ ���������: options.DEFAULT_FIRST=1
    #    + ��� ��������� � ������ ������ options.TEXT_IS_NEW || "�������� ��������" (ID=0)
    #  - ���� ���� �� ������������: IS_NOTNULL=>0
    #    + �������� ������ ������� ��������, ���� ���� options.DEFAULT_FIRST=1
    #    + ��������� ������ ������� options.TEXT_IS_NULL || "�� �������" (ID=0)
    OPTIONS => {
        TEXT_IS_NEW => "�������� ���� ������",
        TEXT_IS_NULL => "���� ������ �� ������",
        DEFAULT_FIRST => 1, # � ������� �� ��������� DEFAULT, �� ���� ����� ��� �������.
    },                      # ������ ������ �� �����������.
    
    #����� ���� OPTIONS, ������������� �� �������� ���������� �� �������� ������ ������
    OPTIONS => {
        PRIVILEGE_FIELD => "privilege",      #��������� ���������� �� ������� �� ������� ���������
        PRIVILEGEMASK   => "CATEGORY_{id}",  #��� ������������� ������
        FULL_PRIVILEGE  => "ALL_CATEGORY",   #������������ ����� ����� ���� ���������� ������� �������
    },
    
    #����� ���� OPTIONS, ������������� �� �������� ������ ��� ��������� ������ ��������
    OPTIONS => {
        #����� �����, �� ������� ��������� ��������.
        ID_FIELD=>"id",     # �� ��������� id
        NAME_FIELD=>"name", # �� ��������� name
        DEFAULT_FIELD=>"is_def",
        DISABLE_FIELD=>"is_disa",
        
        
        #�������� ������ - ������ 
        QUERY => "",        # SQL-������
        
        #�������� ������ - �������
        TABLE => "category",    # ... ��� �������
        WHERE => "id>2",        # ��� where
        ORDER => "name",        # ��� order by
        
        PARAMS=> [],        # ��������� ��� QUERY ��� TABLE
    },
}
=cut
