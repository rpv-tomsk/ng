package NG::Field;
use strict;
use NSecure;
use NGService;

use Scalar::Util();
use File::Copy;
use File::Path;
use NHtml;

my $converter = undef;
our $DEFAULT_IMAGES_RE  = qr@jpg|jpeg|gif|bmp|png@i;
our $DISABLED_FILES_RE = qr@pl|php|exe|cgi|bat|com|asp@i;

$NG::Field::VERSION = 0.1;

our $classesMap = {
    fkselect        => {CLASS=>"NG::Field::Select", },  #��������, ����������� select
    select          => {CLASS=>"NG::Field::Select", },
    radiobutton     => {CLASS=>"NG::Field::Select", },
    multicheckbox   => {CLASS=>"NG::Field::Multicheckbox"},
    multiselect     => {CLASS=>"NG::Field::Multicheckbox"},
    multivalue      => {CLASS=>"NG::Field::Multicheckbox"},
    mp3file         => {CLASS=>"NG::Field::MP3File"},
    mp3properties   => {CLASS=>"NG::Field::MP3Properties"},
    turing          => {CLASS=>"NG::Field::Turing"},
};

=head
    �������� ��������� ������:
    
    FIELD          - ��� ���� � �������
    TABLE          - ����������� ��� �������� (������) �������, �� ������� �����
                     ���� (table.field) ��� ���������� ������� ������ � List.
                     List ��������� ���� ���� �� ��������� � ��� �������� table.
    QUERY          - ����������� ��� ������������ ����� ���� � SQL-������� SELECT
                     � List ( QUERY => 'othertable.name AS product_name' ). 
                     ����������� �������� TABLE.
    TYPE           - ��� ����, ���������� ��������� ���� � ��������� ����� �������
    NAME           - ��� ���� (��������)
    IS_NOTNULL     - ������� �������������� ��������
    
    TMP_FILENAME    - �������� ��� ������������ �����
    TMP_FILE        - ���� � ���������� �����. ���� ����� ������ ����� �������� �����
    _TMP_FILE_FROM_PARENT   - ���������, ��� ����� �������� ���� � ����� ���������� �� ������������� ����,
                              �������������� ��������� ����������� ��������� - ������������ ���� ����� �����������
                              ���� �� ����, ��� ��� ������� ��������� ������

   FORM:CHECKBOX_FIRST - �������� ������� ����������� ������ � ��������. ������� ��� ���������� ��������� � �������� �����.

   ����������� �����, ������������ � �����:
 
   field->{HIDE}=1         # ���� �� ��������� � �����, �� ����������� �������� �� �����.    ������ �� ����� ����� ��������� � ���������� ��������� ������.
   field->{IS_HIDDEN}=1    # ���� ���������� � ����� ��� hidden ���� (HIDE ����� ���������). ������ �� ����� ����� ��������� � ���������� ��������� ������.
   field->{IS_FAKEFIELD}=1 # ���� �� �������� ����� �������� ������� �����, ���� ������������ � ��������� _load,_insert,_update ��� skip-�
   field->{IS_FKPARENT} =1 # ���� ���������� ����� ��� fkparent
   field->{NEED_LOAD_FOR_UPDATE} = 1 # ��� ������������ ���������� �������� ���� ��� �������� ������ ��������� ������� ��� DBVALUE
   
   OLDDBVALUE - ��������, ����������� �� ��. ������������ � setLoadedValue().
   DBVALUE    - ��������, ����������� �� �� ��� �������������� ��� ���������� � ��.
   VALUE      - ��������, ��������������� �������� �������� DBVALUE 
                (���� �� ������������, ������ ����� �������������� � �������� ����, ���� ������������ $form->print($tmpl)... ���� ��� ����� ���� sub VALUE {}.)
              - ����� DBVALUE � VALUE �������� ���������, � �������� _setValue() � _setDBValue()
   _new       - �������, ��� ������ �����.
=cut
 

sub new {
    my ($class,$config,$parentobj) = (shift,shift,shift);
    
    $config || return $class->set_err("����������� ������������ ������������ ����");
    return $class->set_err("������������ ���� �� �������� HASHREF (".(ref $config)) if ref $config ne "HASH";
    
    return $class->set_err("�� ������� ��� ����") unless $config->{FIELD};
    
    my $fieldclass = "NG::Field";
    # ���� ������ ���������� ����� ���������� ����, �� ������ ���
    if (exists $config->{CLASS}) {
        $fieldclass = $config->{CLASS};
    }
    else {
        return $class->set_err("�� ������ ��� ����")  unless $config->{TYPE};
        
        if ($config->{TYPE} eq "fkparent") {
            $config->{IS_FKPARENT} = 1;
            if (!exists $config->{EDITABLE}) {
                my $options = {};
                $options = $config->{OPTIONS} if (exists $config->{OPTIONS});
                if (exists $options->{TABLE} || exists $options->{QUERY} || exists $config->{SELECT_OPTIONS}) {
                    return $class->set_err("������ �������� ������, �� ����������� ���� EDITABLE");
                };
                $config->{TYPE}= "hidden";
            }
            elsif ($config->{EDITABLE}==1 || $config->{EDITABLE} eq "select") {
                $config->{TYPE}= "select";
            }
            elsif ($config->{EDITABLE} eq "radiobutton") {
                $config->{TYPE}= "radiobutton";
            }
            else {
                return $class->set_err("�������� EDITABLE �����������");
            };
        };
        
        my $type = $config->{TYPE};
        $fieldclass = $classesMap->{$type}->{CLASS} if exists $classesMap->{$type};
        
        # ���� � ������� ���� ���������� � ��� ��� ��� ���� ��������\��������, ������ ���� �����
        my $extended_class = NG::Field->confParam('types', $type."_class");
        $fieldclass = $extended_class if $extended_class;
    };
    
    # ������� ���� ������� ������
    if ($fieldclass && $fieldclass ne $class) {
        unless (UNIVERSAL::can($fieldclass,"can")) {
            eval "use $fieldclass";
            return $class->set_err($@) if ($@);
        };
        unless (UNIVERSAL::can($fieldclass,"new")) {
            return $class->set_err("����� $fieldclass �� �������� ������������ new().");
        };
        return $fieldclass->new($config,$parentobj);
    };
    
    my $field = {};
    %{$field} = %{$config};
    
    bless $field, $class;
    $field->{_parentObj} = $parentobj;
    Scalar::Util::weaken($field->{_parentObj}) if defined $field->{_parentObj};
    $field->init(@_) or return undef;
    $field->setValue($config->{VALUE}) if exists $config->{VALUE};
    return $field; 
};

sub init {
    my $field = shift;

    $field->{TEMPLATE} ||= $field->{_parentObj}->{_deffieldtemplate} if $field->{_parentObj};
    $field->{TEMPLATE} ||= "admin-side/common/fields.tmpl";
    
    $field->{_loaded} = 0;
    $field->{_changed} = 0;
    $field->{_new} = 0;
    
    $field->{ERRORMSG}   = "";

    my $type = $field->{TYPE} or return $field->set_err("�� ������ ��� ����");
    
    my $hash = $field->{_errorTexts}->{""} = {};  # $hash->{$lang}->{$code}=$text;
    $hash->{NOT_UNIQUE}   = "�������� ���� \"{n}\" �� ���������";
    $hash->{INVALID_EMAIL}= "����� ����������� ����� �����������";
    $hash->{INVALID_URL}  = "������������ URL";
    $hash->{INVALID_DATE} = "�������� ������ ����";
    $hash->{IS_EMPTY}     = "�� ������� �������� ���� \"{n}\"";
    $hash->{MISSING_KEY}  = "�� ������� �������� ��������� ���� {n}";
    $hash->{INVALID_INT}  = "�������� �� �������� ����� ������";
    $hash->{INVALID_NUMBER}="�������� �� �������� ������";
    $hash->{INVALID_CIDR} = "����� ��� ���� ������� �����������";
    $hash->{OUT_OF_RANGE} = "�������� ��������� ��� ���������� ��������";
    $hash->{REGEXP_FORBIDDEN} = "�������� �������� ������������ ��������";
    $hash->{VALUE_TOO_LONG}="��������� ����� ������� ������� ({size} �������� ��� ����������� {limit})";
    
    $hash->{MISSING_FILE}            = "�� ������ ����";
    $hash->{EXTENSION_EXISTS}        = "�������� ������ ����� *.{e}. ����������� ������ ����� ��� ����������.";
    $hash->{EXTENSION_NEEDED}        = "�������� ������ �����. ����� ��� ���������� ���������.";
    $hash->{EXTENSION_FORBIDDEN}     = "����������� ���������� �����: *.{e}";
    $hash->{EXTENSIONLIST_FORBIDDEN} = "����������� ���������� �����: *.{e}. ����������: {el} ���������.";
    $hash->{EXTENSIONLIST_NEEDED}    = "����������� ���������� �����: *.{e}. ����������� {el}.";

    if ($field->isFileField) {
        return $field->set_err("addfields(): UPLOADDIR value not specified for field ".$field->{FIELD}) unless exists $field->{UPLOADDIR};
        $field->{NEED_LOAD_FOR_UPDATE} = 1;
    };
    if ($type eq "id" || $type eq "hidden") {
        #TODO: ����� ���� ����� ����� ��������� ��� IS_ID ��� ���������� �������.
        $field->{IS_HIDDEN} = 1; 
    }
    elsif ($type eq "filter") {
        $field->{HIDE} = 1;
    }
    elsif ($type eq "rtf") {
        $field->{IS_RTF} = 1;
    }
    elsif ($type eq "url") {
        $field->{IS_URL} = 1;
        $field->{LINK_PATTERN} = undef;
        $field->{LINK_URL} = "";
    }
    elsif ($type eq "rtffile") {
        return $field->set_err("�� ������� �������� ����� FILEDIR ��� ���� ".$field->{FIELD}) unless $field->options('FILEDIR');
        $field->{IS_RTF} = 1;
        $field->{NEED_LOAD_FOR_UPDATE} = 1;
    }
    elsif (($type eq "textfile")) {
        return $field->set_err("�� ������� �������� ����� FILEDIR ��� ���� ".$field->{FIELD}) unless $field->options('FILEDIR');
        $field->{IS_TEXTFILE} = 1;
        $field->{NEED_LOAD_FOR_UPDATE} = 1;
    }
    elsif ($type eq "checkbox") {
        if (!exists $field->{CB_VALUE}) { $field->{CB_VALUE} = 1; };
        $field->{IS_CHECKBOX} = 1;
    }
    else {
        my $is_type = uc("IS_".$field->{TYPE});
        $field->{$is_type} = 1;
    };
    return 1;
};

sub getProcessorClass {
    my $self = shift;
    
    # ���� ������ ���������� �����, �� ������ ���
    return $self->{PROCESSOR} if exists $self->{PROCESSOR};
    
    # ���� � ������� ���� ���������� � ��� ��� ��� ���� ��������\��������, ������ ���� �����
    my $class = NG::Field->confParam('types', $self->{TYPE}."_processor");
    return $class if $class;
    
    return "NG::ImageProcessor" if ($self->{TYPE} eq "image");
    return "NG::FileProcessor" if ($self->isFileField());
    return "NG::TextProcessor";
};

sub afterLoad {
    return 1;
};

sub _fileBuildPermalink {
    my $field = shift;
    
    my $link = $field->{OPTIONS}->{PERMALINK_MASK};
    my $p = $field->parent();
    
    if ($link =~ /\{page:url\}/) {
        my $moduleObj = $p->owner()->getModuleObj();
        my $pageUrl = $moduleObj->pageParam('url');
        $link =~ s/\{page:url\}/$pageUrl/gi;
    };
    
    while ($link =~ /\{(.+?)\}/) {
        my $f = $p->getField($1) or die("Field $1 not found for PERMALINK_MASK");
        my $value = $f->value();
        warn "NG::Field::_fileBuildPermalink(): no value for field $1 in PERMALINK_MASK of field $field->{FIELD}" unless $value;
        #TODO: ��� ������������� ����������� ����� ��������� ����� ���� ts:FIELD
        #$value = ts($value);
        #$value =~ s/[^a-zA-Z0-9]/_/gi;
        $link =~ s/\{.+?\}/$value/;
    };
    
    $field->{PERMALINK} = $link;
};

sub prepareOutput {
    my $field = shift;
    
    if ($field->{TYPE} eq 'date') {
        if (exists $field->{OPTIONS}->{DATEPICKER} && !exists $field->{DATEPICKER}) {
            $field->{DATEPICKER} = create_json($field->{OPTIONS}->{DATEPICKER});
        };
    };
    
    if ($field->{TYPE} eq 'file') {
        if (exists $field->{OPTIONS}->{PERMALINK_MASK}) {
            $field->_fileBuildPermalink();
        };
    };
    
    return 1;
};

sub parent {
    my $field = shift;
    return $field->set_err("��� ���� ".$field->{FIELD}. " �� ������ ������-��������") if !$field->{_parentObj} || (ref $field->{_parentObj} eq "");
    return $field->{_parentObj};
};

sub setError {
    my ($field,$errormsg,$mask) = (shift,shift,shift);
    
    my $name = $field->{NAME};
    $name = $field->{FIELD} unless defined $name && $name ne '';
    $errormsg =~ s/{n}/$name/;
    $errormsg =~ s/{f}/$field->{FIELD}/;
    $errormsg =~ s/{t}/$field->{TYPE}/;
    
    if ($mask && ref $mask eq "HASH") {
        foreach my $key (keys %$mask) {
            my $v = $mask->{$key};
            $errormsg =~ s/{$key}/$v/;
        };
    };
    
    $errormsg ||= "";
warn "NG::Field($field->{FIELD})::setError(".ts($errormsg).")";
    $field->{ERRORMSG} = $errormsg;
    return 0;
};

sub set_err {
    my $self = shift;
    my $errstr = shift;
print STDERR "NG::Field(".(ref $self?$self->{FIELD}:"").")::set_err($errstr)\n";
    $NG::Field::errstr = $errstr;
    $self->{ERRORMSG} = $errstr if ref $self;
    return undef;
};

sub error { return shift->{ERRORMSG}; };
*ERROR = \&error;

sub hasError {
    my $field = shift;
    return 1 if $field->{ERRORMSG};
    return 0;
};

sub ajaxError {
    my ($s) = @_;
    { name => $s->{FIELD}, type => $s->{TYPE}, err => $s->error };
}

sub showError {
    my $field = shift;
    my $defMsg = shift;
    
    $field->{ERRORMSG} ||= $defMsg;
    
    return 0;
};

sub _param {
    my $field = shift;
    my $href = shift;
    
    foreach my $key (keys %{$href}) {
        $field->{$key} = $href->{$key};
    }
    return 1;
}

sub param {
    my $field = shift;
    my $ref   = shift;
    
    if (!defined $ref) {
        #���������� ��� ��������� � ���� hashref
        my %tmp = %{$field};
        return \%tmp;
    };
    
    if (ref $ref eq "") {
        unshift(@_,$ref);
        if (scalar @_ == 1) {
            #������
            return $field->{$ref};
        }
        #elsif (scalar @_ % 2 == 0) {
        #}
        else {
            my %param = (@_);
            $field->_param(\%param) or return 0;
        };
    }
    elsif (ref $ref eq 'HASH') {
        $field->_param($ref) or return 0;
    }
    else {
        die "NG::Field::param(): incorrect method call";
    };
    return 1;
};

sub options {
    my $field = shift;
    my $param = shift;
    my $value = shift;
    $field->{OPTIONS} ||= {};
    return $field->{OPTIONS} unless $param;
    unless ($value) {
        return $field->{OPTIONS}->{$param} if exists $field->{OPTIONS}->{$param};
        return undef;
    };
    $field->{OPTIONS}->{$param} = $value;
};

sub isFileField {
    my $self = shift;
    my $type = $self->{TYPE};
    return 1 if ($type eq "file") || ($type eq "image");
    return 0;
}

sub type { return shift->{TYPE}; };

sub _setDBValue {
    my $self = shift;
    my $value = shift;
    
    if ($self->{TYPE} eq "date") {
        $self->{VALUE} = $self->db()->date_from_db($value);
        $self->{DBVALUE} = $value;
    }
    elsif ($self->{TYPE} eq "checkbox") {
        $self->{CHECKED} = ($value eq $self->{CB_VALUE})?1:0;
        $self->{VALUE}   = $value;
        $self->{DBVALUE} = $value;
    }
    elsif ($self->{TYPE} eq "datetime") {
        $self->{VALUE} = $self->db()->datetime_from_db($value);
        $self->{DBVALUE} = $value;
    }
    elsif ($self->{TYPE} eq "inttimestamp") {
        use POSIX qw/strftime/;
        my $format = "%d.%m.%Y %T";
        $format = $self->{FORMAT} if exists $self->{FORMAT}; ## options->FORMAT ?
        $self->{VALUE} = strftime($format,localtime($value));
        $self->{DBVALUE} = $value;
    }
    elsif ($self->{TYPE} eq "url") {
        my $link = parseBBlink($value);
        if (!defined $link) {
            $self->{LINK_URL} = $value;
        }
        else {
            $self->{LINK_URL} = $link->{HREF};
            $self->{LINK_PATTERN} = $link;
        };
        $self->{VALUE}   = $value;
        $self->{DBVALUE} = $value;
    }
    elsif ($self->isFileField()) {
        $self->{DBVALUE} = undef;
        if ($value) {
            $self->{VALUE}   = $self->cms()->getDocRoot().$self->{UPLOADDIR}.$value;
            $self->{DBVALUE} = $value;
        };
    }
    elsif ($self->{TYPE} eq "rtffile" || $self->{TYPE} eq "textfile") {
        return $self->setError("Can`t load data from file: OPTIONS.FILEDIR is not specified for field {f} (type: {t}).") if is_empty($self->{OPTIONS}->{FILEDIR});
        if ($value) {
            $self->{DBVALUE} = $value;
            #���� ���� �����������, ������� ������ ���� �������.
            #����� ������ ��� � ���� ���� - ������ �������.
            unless (-f $self->cms()->getSiteRoot().$self->{OPTIONS}->{FILEDIR}.$value) {
                my ($v,$e) = saveValueToFile('',$self->cms()->getSiteRoot().$self->{OPTIONS}->{FILEDIR}.$value);
                return $self->setError("������ ������������� ����� ������ ���� {f}: ".$e) unless defined $v;
                $self->{VALUE} = '';
                return 1;
            };
            my ($v,$e) = loadValueFromFile($self->cms()->getSiteRoot().$self->{OPTIONS}->{FILEDIR}.$value);
            return $self->setError("������ ������ ����� � ������� ���� {f}: ".$e) unless defined $v;
            $self->{VALUE} = $v;
        };
    }
    else {
        $self->{DBVALUE} = $value;
        $self->{VALUE} = $value;
    };
    return 1;
};

sub setDBValue {
=head
    ����� ��� ��������� �������. ������ ������ ��� �����, 
    ��� ����� �����������, ���� ��� ����������� ������� ����� �������� setDBValue().
    
    ��������������: ���������� ��������, ������� ������ ���� �������� � �� ��� ���������. 
                    � ���������� ���������� ������ ������������ ���������� VALUE.
                    ������������ DBVALUE ����� ���� ���������� ������� process() ����
=cut
    my $self = shift;
    my $value = shift;
    
    my $ret = $self->_setDBValue($value,@_);
    if ($ret) {
        $self->{_changed}=1;
    };
    return $ret;
};

#
# ��������� ���������� ��������� �������, ����������� �� ��.
# �������� ��� ���� �������, ���������� �� ��.
# �������� ����� ������� ������������ ��������� ������� dbFields() �� ���� ����� �����.
#
sub setLoadedValue {
    my $self = shift;
    my $row  = shift;
    
    unless (exists $row->{$self->{FIELD}}) {
        return 1 if $self->{IS_FAKEFIELD};
        return $self->setError("setLoadedValue(): ����������� ������ ��� ���� {f}");
    };
    my $value = $row->{$self->{FIELD}};
    
    my $ret = $self->_setDBValue($value,@_);
    if ($ret) {
        $self->{OLDDBVALUE} = $value;
        $self->{_loaded}=1;
        $self->{_changed}=0;
    };
    return $ret;
};

sub _setValue {
    my ($field,$value) = (shift,shift);
    
    if ($field->{TYPE} eq "checkbox") {
        $field->{CHECKED}=0;
        $value = 0 unless defined $value;
        if ($value ne $field->{CB_VALUE}) {
            $value = 0;
        }
        else {
            $field->{CHECKED}=1;
        };
        $field->{VALUE} = $value;
        $field->{DBVALUE} = $value;
    }
    elsif ($field->{TYPE} eq "date") {
        $field->{VALUE} = $value;
        $field->{DBVALUE} = $field->db()->date_to_db($field->{VALUE});
    }
    elsif ($field->{TYPE} eq "datetime") {
        $field->{VALUE} = $value;
        $field->{DBVALUE} = $field->db()->datetime_to_db($field->{VALUE});
    }
    elsif ($field->isFileField()) {
        if (!is_empty($value) && -e $value) {
            if (!$field->{TMP_FILENAME}) {
                ($field->{TMP_FILENAME}) = $value =~ /([^\\\/]*)$/; 
            };
            $field->{VALUE} = $value;
            delete $field->{DBVALUE}; #DBVALUE ����������� � ������ ������ dbValue(), �.�. ���������� �������� ������ �����
        }
        else {
            $field->{VALUE} = "";
            $field->{DBVALUE} = undef;
        };
    }
    elsif (($field->{TYPE} eq "number") || ($field->{TYPE} eq "int")) {
        $field->{VALUE} = $value;
        $field->{VALUE} = undef if defined $value && $value eq "";
        $field->{DBVALUE} = $field->{VALUE};
    }
    elsif ($field->{TYPE} eq 'rtffile' || $field->{TYPE} eq 'textfile') {
        $field->{VALUE} = $value;
    }
    else {
        $field->{VALUE} = $value;
        $field->{DBVALUE} = $value;
    };
    return 1;
};

sub setValue {
    my $field = shift;
    $field->_setValue(@_) or return 0;
    $field->{_changed} = 1;
    return 1;
};

sub setDefaultValue {
	my $field = shift;
	$field->setValue($field->{DEFAULT}) if (exists $field->{DEFAULT});
};

sub _convert {
    $converter ||= $NG::Application::cms->getObject("Text::Iconv","utf-8","cp1251") or die "NG::Field::_convert(): can`t use Text::Iconv module";
    $converter->convert($_[0]);
};

sub setFormValue {
    my $field = shift;
    
    my $q = $field->parent()->q();
    
    my ($contentType, $is_utf8) = ($q->content_type()||"",0);

    $is_utf8++ if $contentType =~ /utf\-?8/i; # application/x-www-form-urlencoded; charset=UTF-8
    $is_utf8++ if $q->http('X-Requested-With') && $q->http('X-Requested-With') eq "XMLHttpRequest";
    
    my $value = $q->param($field->{FIELD});
    $value = 0 if !defined $value && $field->{TYPE} eq 'checkbox'; #Browsers do not send unchecked checkboxes at all.

    return 1 unless defined $value;
    $value = ($is_utf8) ? _convert($value) : $value;

    if ($field->{ESCAPE} && $field->{ESCAPE} eq "HTML") {
        $value = htmlspecialchars($value);
    };
    
    if ($field->isFileField()) {
        $field->{DBVALUE} = undef unless exists $field->{DBVALUE};
        return 1 if is_empty($value);
        return 1 unless -e $value;
        $field->setTmpFile($q->tmpFileName($value),$value);
        return 1;
    };
#print STDERR $field->{FIELD}." - ".$value;
    $field->setValue($value);
    $field->{_changed} = 0 if $field->{READONLY};
};

sub setTmpFile {
    my $field = shift;
    my $tmpfile  = shift;
    my $filename = shift;  # �� ������������. ���� �� ������, �� ��� ������������ �� ��������� ������ setValue($tmpfile)
    
    close($filename) if $filename && ref $filename;
    $filename =~ s/.*?([^\\\/]+)$/$1/ if $filename;
    
    $field->{TMP_FILENAME} = $filename; # �������� ��� �����.
    $field->{TMP_FILE} = $tmpfile;      # ��� ���������� �������� ������ ���� � ��������� ������.
                                        # ���� ���� �� ���������, ���� � ���� ���������� ������ � VALUE
    $field->setValue($tmpfile);
};

sub value {
    my $field = shift;
    return $field->{VALUE};
};
*VALUE = \&value;

#Accesssor for new H:T:C
sub field { return shift->{FIELD} };

sub searchIndexValue {
    my $field = shift;
    
    my $type = $field->type();
    return unhtmlspecialchars strip_tags $field->{VALUE} if $type eq 'rtffile' || $type eq 'rtf';
    die 'NG::Field::searchIndexValue(): Unable to index checkbox' if $type eq 'checkbox';
    return $field->{VALUE};
};

sub REQUIRED {return shift->{IS_NOTNULL}; };
sub NAME {return shift->{NAME}; };

sub genNewFileName {
    my $field = shift;
    
    my $fname = $field->options("FILENAME_MASK");
    my $ext = "html";
    
    if ($field->isFileField()) {
        die 'NG::Field->genNewFileName(): Missing TMP_FILENAME value. Unable to get file extension.' if is_empty($field->{TMP_FILENAME});
        $ext = get_file_extension($field->{TMP_FILENAME}) || "";
        $field->{TMP_FILENAME} =~ /([^\\\/]+?)\.?$ext$/;
        my $ts = ts($1);
        $ts =~ s/[^a-zA-Z0-9]/_/gi;
        $fname ||= "{f}_{k}_{r}{e}" if $field->{TYPE} eq 'image';
        $fname ||= "{t}_{f}_{k}_{r}{e}";
        
        $fname =~ s@\{t\}@$ts@;
    }
    else {
        $fname ||= "{f}_{k}{e}";
    };
    
    my $p = $field->parent();
    
    my $fieldName = $field->{FIELD};
    $fname =~ s@\{f\}@$fieldName@;
    my $key = $p->getComposedKeyValue();
    $fname =~ s@\{k\}@$key@;
    my $rand = int(rand(9999));
    $fname =~ s@\{r\}@$rand@;
    $ext = ".".$ext if $ext;
    $fname =~ s@\{e\}@$ext@;
      
    while ($fname =~ /\{(.+?)\}/) {
        my $f = $p->getField($1) or die("Field $1 not found for FILENAME_MASK");
        my $value = $f->value();
        warn "NG::Field::dbValue(): no value for field $1 in FILENAME_MASK of field $fieldName" unless $value;
        $value = ts($value);
        $value =~ s/[^a-zA-Z0-9]/_/gi;
        $fname =~ s/\{.+?\}/$value/;
    };
    $field->{DBVALUE} = $fname;
};

#���������� ������ ����� �������, ����������� ��� ���������� �������� ������
#��������:
# - load   - �������� ��������
# - insert - ������� ����� ������ � �������
# - update - ���������� ������ � �������
sub dbFields {
    my ($field,$action) = (shift,shift);
    return () if $field->{IS_FAKEFIELD};
    return () if ($action eq 'insert' || $action eq 'update') && ! ($field->{TYPE} eq "id" || $field->{TYPE} eq "filter") && ! $field->changed();
    my $dbField = $field->{FIELD};
    if ($action eq 'load') {
        return ($field->{QUERY}) if exists $field->{QUERY};
        return ($field->{TABLE}.'.'.$field->{FIELD}) if exists $field->{TABLE};
    };
    return ($field->{FIELD});
};

#���������� �������� ��� ���������� � ������� / ��� ������������� � �������� �������
#
# $dbField ��������, ���� ���� ���������� (insert/update) �����, � ��������� ������� (� �� ����������) - undef
sub dbValue {
    my ($field,$dbField) = (shift,shift);
    die "Not implemented" if $dbField && $dbField ne $field->{FIELD};
    
    my $type = $field->type();
    
    if ($type eq "rtffile" || $type eq "textfile" || $field->isFileField()) {
        $field->genNewFileName() unless exists $field->{DBVALUE};
    };
    
    die 'NG::Field::dbValue(): DBVALUE not built for field '.$field->{FIELD} unless exists $field->{DBVALUE};
    die 'NG::Field::dbValue(): Can`t find value for key field '.$field->{FIELD} if $type eq "id" && !$field->{DBVALUE};

    return $field->{DBVALUE};
};

sub oldDBValue {
    my $field=shift;
    die 'NG::Field::oldDBValue(): OLDDBVALUE not loaded!' unless exists $field->{OLDDBVALUE};
    return $field->{OLDDBVALUE};
};

sub checkFileType {
    my $field = shift;
    
    if (is_empty($field->{VALUE})) {
        return $field->setErrorByCode("MISSING_FILE") if $field->{_new} == 1 && $field->{IS_NOTNULL};
        return 1;
    };
    #TODO: ����� �� ��������� ����� ����������� ��������? ��� ����� ���� ������������ _loaded
    return 1 if $field->{_loaded} && !$field->changed();
    
    my $filename = $field->{TMP_FILENAME};
    $filename ||= $1 if ($field->{VALUE} =~ /([^\\\/]*)$/); 

    my $ext = get_file_extension($filename);
    
    my $allowed_re = $field->options("ALLOWED_EXT");
    
    if (defined $allowed_re && !$allowed_re && $ext) {
        return $field->setErrorByCode("EXTENSION_EXISTS",{e=>$ext});
    };
    
    if ($field->type() eq "image") {
        $allowed_re ||= $DEFAULT_IMAGES_RE;
    };
    
    my $exts = "";
    if (ref $allowed_re eq "Regexp") {
        #
    }
    elsif (ref $allowed_re) {
        return $field->setError("������������ �������� ����� ALLOWED_EXT");
    }
    elsif ($allowed_re) {
        my @aext = split /\|/, $allowed_re;
        foreach (@aext) {
            $exts .= " *.$_" if $_ =~ /[a-zA-Z0-9_-]+/;
        };
        $allowed_re = qr@$allowed_re@i;
    };
    
    if ($allowed_re && $ext !~ $allowed_re) {
        if (!$ext) {
            #+��������� ���������� �� ������ if $exts
            #��������� ����������
            if ($exts) {
                return $field->setErrorByCode("EXTENSIONLIST_NEEDED",{el=>$exts,e=>""});
            }
            else {
                return $field->setErrorByCode("EXTENSION_NEEDED");
            };
        }
        else {
            if ($exts) {
                return $field->setErrorByCode("EXTENSIONLIST_NEEDED",{el=>$exts,e=>$ext});
            }
            else {
                return $field->setErrorByCode("EXTENSION_FORBIDDEN",{e=>$ext});
            }
        };
    };
    
    my $disabled_re  = $field->options("DISABLED_EXT");
    
    if (defined $disabled_re && !$disabled_re && !$ext) {
        return $field->setErrorByCode("EXTENSION_NEEDED");
    };

    if (ref $disabled_re eq "Regexp") {
        #
    }
    elsif (ref $disabled_re) {
        return $field->setError("������������ �������� ����� DISABLED_EXT");
    }
    elsif ($disabled_re) {
        my @aext = split /\|/, $disabled_re;
        foreach (@aext) {
            $exts .= " *.$_" if $_ =~ /[a-zA-Z0-9_-]+/;
        };
        $disabled_re = qr@$disabled_re@i;
    };
    
    if ($disabled_re && $ext =~ $disabled_re) {
        if (!$ext) {
            return $field->setErrorByCode("EXTENSION_NEEDED");
        }
        elsif ($exts) {
            return $field->setErrorByCode("EXTENSIONLIST_FORBIDDEN",{el=>$exts,e=>$ext});
        }
        else {
            return $field->setErrorByCode("EXTENSION_FORBIDDEN",{e=>$ext});
        };
    };
    
    if ($ext =~ $DISABLED_FILES_RE) {
        return $field->setErrorByCode("EXTENSION_FORBIDDEN",{e=>$ext});
    };
    return 1;
};

=head TODO ?
sub getMessageByCode {
    my $field = shift;
    my $code  = shift;
    
    return "";
};
=cut

sub getErrorByCode {
    my $field = shift;
    my $code  = shift;
    
=comment
{f} - $field->{FIELD}
{n} - $field->{NAME}
    
--- �������� ��������
{e}  - extension
{el} - extension list

=cut
    my $form = $field->parent(); # ��� ����� ���� � Row
    my $lang = $form->getLang();
    
    my $text = $form->getFieldErrorText($field->{FIELD},$code);
    return $text if $text;
    
    my $hash = $field->{_errorTexts};
    return $hash->{$lang}->{$code} if exists $hash->{$lang} && exists $hash->{$lang}->{$code};
    return $hash->{""}->{$code} if exists $hash->{""} && exists $hash->{""}->{$code};

    $text = $field->getErrorByCode('UNKNOWN_ERROR_CODE') unless $code eq "UNKNOWN_ERROR_CODE";
    return $text if $code eq "UNKNOWN_ERROR_CODE";
    $text ||= "Unknown error code {code}";
    $text =~ s/{code}/$code/;
    return $text;
};

sub setErrorByCode {
    my $field = shift;
    my $code  = shift;
    my $mask  = shift;

    my $e = $field->getErrorByCode($code);
    return $field->setError($e,$mask);
};

sub pushErrorTexts {
    my $field = shift;
    my $hash = shift; #$hash->{$lang}->{$code} = $text or $hash->{$code} = $text
    
    return $field->setError("pushErrorTexts(): Hash parameter is not HASHREF") unless ref $hash eq "HASH";
    
    my $e = $field->{_errorTexts};
    
    my $m = 0;  # 1->with lang 2->w/o lang
    foreach my $key (keys %$hash) {
        my $s = $hash->{$key};
        if (ref $s eq "HASH") {
            #$key is $lang
            return $field->setError("pushErrorTexts(): Hash parameter contains mixed language definition style") if $m == 2;
            $m = 1;
            foreach my $code (keys %$s) {
                warn "pushErrorTexts(): error code $code is overriden in class ".(ref $field) if exists $e->{$key} && exists $e->{$key}->{$code};
                $e->{$key}->{$code} = $s->{$code};
            };
        }
        else {
            #$key is $code
            return $field->setError("pushErrorTexts(): Hash parameter contains mixed language definition style") if $m == 1;
            $m = 2;
            warn "pushErrorTexts(): error code $key is overriden in class ".(ref $field) if exists $e->{""} && exists $e->{""}->{$key};
            $field->{_errorTexts}->{""}->{$key} = $s;
        };
    };
    return 1;
};

sub check {
    my $field = shift;
    
    my $type  = $field->{TYPE};
    my $value = $field->{VALUE};

    if ($field->isFileField()) {
        return $field->checkFileType();
    };
        
    #TODO: � ����� �� ������� ��������� ������������ ����� �������� � ������ ?
    if (($field->{UNIQUE}) && !is_empty($field->dbValue())) {
        my $dbh = $field->dbh() or return $field->showError("check(): ����������� �������� dbh");
        my $parent = $field->parent() or return $field->showError("check(): ����������� �������� parent()");
        my $table = $parent->{_table} or return $field->setError("����������� ��� ������� ��� �������� ������������");
        
        return $field->showError("check(): � �������-�������� ����������� ����� fields()") unless $parent->can("fields");
        my $fields = $parent->fields();
        return $field->showError("check(): ����� fields() �������� ������ �� ARRAYREF") unless ref $fields eq "ARRAY";

        my $keyWhere = "";
        my @keyValues = ();
        foreach my $tmpfield (@{$fields}) {
            next unless $tmpfield->type() eq "id";
            
            return $field->setError("��� �������� ������������ {f} �� ������� �������� ��������� ���� ".$tmpfield->{FIELD}) if (is_empty($tmpfield->{VALUE}));
            
            $keyWhere .=  $tmpfield->{FIELD}."<>? and";
            push @keyValues, $tmpfield->dbValue();
        };
        unless ($keyWhere) {
            return $field->setError("��� �������� ������������ �������� ���� \"{n}\" �� ������� �������� ����");
        };
        $keyWhere =~ s/and$//;

        my $sameWhere  = "";
        my @sameValues  = ();
        my $parentFieldsList = (ref $field->{UNIQUE} eq "ARRAY")?$field->{UNIQUE}:[];
        foreach my $pfName (@{$parentFieldsList}) {
            my $tmpfield = $parent->getField($pfName) or return $field->setError("���� $pfName, ��������� � ����� UNIQUE, �� �������");
            return $field->setError("����������� ������������ �������� ���� � ����� UNIQUE") if ($tmpfield->type() eq "id");
            #TODO: is_empty() ��������� value() � � ������� ��������� dbValue()
            return $field->setError("��� �������� ������������ �� ������� �������� ���� \"$tmpfield->{FIELD}\"") if(is_empty($tmpfield->value()));
            $sameWhere .=  $tmpfield->{FIELD}."=? and ";
            push @sameValues, $tmpfield->dbValue();
        };
        $sameWhere .= $field->{FIELD}."=?";
        push @sameValues, $field->dbValue();
        
        my $sth = $dbh->prepare("select ".$field->{FIELD}." from $table where ($keyWhere) and ($sameWhere)") or return $field->setError($DBI::errstr);
        $sth->execute(@keyValues,@sameValues) or return $field->setError($DBI::errstr);
        my $row = $sth->fetchrow_hashref();
        $sth->finish();
        return $field->setErrorByCode("NOT_UNIQUE") if ($row);
    };

    #������ ��� ������ �������. ������ - ����������� ����.
    die "�� ������� �������� ���� \"".$field->{FIELD}."\" ���� filter" if (($type eq "filter") && is_empty($value));
    
    if (($type eq "id") && !is_valid_id($value)) {
        return $field->setErrorByCode("MISSING_KEY");
    };
    
    if (($type eq "email") && ($value) && (!is_valid_email($value)))  {
        return $field->setErrorByCode("INVALID_EMAIL");
    };
    
    if ($field->{IS_NOTNULL} && is_empty($value)) {
        return $field->setErrorByCode("IS_EMPTY");
    };
    
    if ($type eq "url" && !is_empty($value)){
        if (is_valid_link($value)){
            return 1;
        }
        elsif (my $ret = parseBBlink($value)) { #"
            return $field->setErrorByCode("INVALID_URL") if (!is_valid_link($ret->{HREF}));
        }
        else {
            return $field->setErrorByCode("INVALID_URL");
        };
    };
    
    if ($type eq "date" && !is_empty($value) && !is_valid_date($value)) {
        return $field->setErrorByCode("INVALID_DATE");
    };
    
    if ($type eq "datetime" && !is_empty($value) && !is_valid_datetime($value)) {
        return $field->setErrorByCode("INVALID_DATE");
    };
    
    if ($type eq "int" && $value && !is_int($value)) {
        return $field->setErrorByCode("INVALID_INT");
    };
    if ($type eq "number" && $value && !is_float($value)) {
        return $field->setErrorByCode("INVALID_NUMBER");
    };
    if (($type eq "number" || $type eq "int") && defined $value && ((exists $field->{MIN} && $value < $field->{MIN}) || (exists $field->{MAX} && $value > $field->{MAX}))) {
        return $field->setErrorByCode("OUT_OF_RANGE");
    }; 
    if ($type eq "cidr" && $value && !is_valid_cidr($value)) {
        return $field->setErrorByCode("INVALID_CIDR");
    };
    if ($value && $field->{OPTIONS}->{REGEXP}) {
        my $re = $field->{OPTIONS}->{REGEXP};
        return $field->setError("������������ �������� ����� REGEXP") unless ref $re eq "Regexp";
        if ($value !~ $re ) {
            return $field->setError($field->{OPTIONS}->{REGEXP_MESSAGE}) if $field->{OPTIONS}->{REGEXP_MESSAGE};
            return $field->setErrorByCode("REGEXP_FORBIDDEN");
        };
    };
    if ($value && exists $field->{LENGTH} && $type =~ /^((?:rtf|text)(?:file)?|textarea)?$/ && length($value) > $field->{LENGTH}) {
        return $field->setErrorByCode("VALUE_TOO_LONG", {size=>length($value),limit=>$field->{LENGTH}});
    }
    return 1;
};

sub getChilds {
    my $self = shift;
    
    return [] unless exists $self->{CHILDS};
    NG::Exception->throw('NG.INTERNALERROR','�������� CHILDS �� �������� ������� �� ������') unless ref $self->{CHILDS} eq "ARRAY";
    
    my $childs = [];
    foreach my $ch (@{$self->{CHILDS}}) {
        if (ref $ch eq "HASH") {
            NG::Exception->throw('NG.INTERNALERROR','����������� �������� FIELD � �������� ������������ ����') unless exists $ch->{FIELD};
            push @{$childs}, $ch;
        }
        else {
            push @{$childs},{FIELD=>$ch};
        };
    };
    return $childs;
};

sub processChilds {
    my $self = shift;
    
    my $convMethods = {
        'image_image' => '_image2image',    #����������� ���������� (�������) ��� ��������� ��������� ����������� ���������� ������������ (������������!)
        'file_image'  => '',                #�� ������������ ������������
        'image_file'  => '',                #�� ������������ ������������
        'file_file'   => '_file2file',      #�� �������� �����, CHILDS ������������ ������ ��� ��������.
    };

    return 1 unless exists $self->{CHILDS};
    
    my $childs = $self->getChilds();
    return $self->showError() unless $childs;
    
    foreach my $ch (@{$childs}) {
        my $chName = $ch->{FIELD};
        my $child = $self->parent()->getField($chName) or NG::Exception->throw('NG.INTERNALERROR', "����������� ���� $chName �� �������");
        
        my $convMethod = $ch->{METHOD};
        if (!defined $convMethod) {
            $convMethod = $convMethods->{$self->type()."_".$child->type()};
        };
        
        next unless defined $convMethod;
        next if $convMethod eq '';
        
        NG::Exception->throw('NG.INTERNALERROR', "����� ".ref($child)." ���� ".$child->{FIELD}." �� �������� ������ ".$convMethod." ��� ����������� ������ �� ���� ".$self."(".ref($self).")") unless $child->can($convMethod);
        $child->$convMethod($self,$ch) or NG::Exception->throw('NG.INTERNALERROR',"������ ����������� �������� �� ".$self->{FIELD}." ������������ ���� ".$child->{FIELD}." :".$child->error());
    };
    return 1;
};

=head
    #Example 1.  ���������� ������������, ��� �������� �� �����
    
    {FIELD=>'smallimage', TYPE=>'image',    NAME=>'�����������',UPLOADDIR=>"/some/dir", IS_NOTNULL=>1,
        OPTIONS=>{WIDTH=>120,METHOD=>"towidth"},
        CHILDS=> [{FIELD=>"bigimage"}],
    },
    {FIELD=>'bigimage',   TYPE=>'image',    NAME=>'�����������',UPLOADDIR=>"/some/dir", HIDE=>1,
        OPTIONS=>{WIDTH=>400,METHOD=>"towidth"}
    },
    
    1. ����� �������� �������� ������ � smallimage, ��������� bigimage ����� �������� HIDE=>1
    2. ���������� ����������� ���� ���������� ����� � ���� bigimage (��������� ����� ��������� ����� ��������� ��������� ����������)
       ���������� ����������� ���������� ����� ���� � ����� � ������ processChilds (����� ���������� � ������� ���� �����, � ���������� "��������")
    3. ��������� ������ ����� beforeSave. ��� ����� ���� image ��� �������� � ��������� ��������� � ���������� OPTIONS.METHOD, ���������� ���������
       ���������� ����� � ������� ����� ������� �������
    4. ���������� ���������� ������ ����� � ��
    
    #Example 2. ��������� ������ �������� ��������
    {FIELD=>'image',   TYPE=>'image',  NAME=>'�����������',UPLOADDIR=>"/some/dir",
        CHILDS=> [
            {FIELD=>"imgsize", METHOD=>"imgSize"},
            {FIELD=>"filesize", METHOD=>"fileSize"},
        ],
        OPTIONS=>{WIDTH=>400,METHOD=>"towidth"}
    },
    {FIELD=>'imgsize',  TYPE=>'text',  NAME=>'�������� ������', HIDE=>1, CLASS=>"NG::CoolField"
    },
    
    ������������ ���������� ������������ �������� �������� � ������� ������������� �����,
    ��������� ������ beforeSave ����������� ����� ������� PROCESS
    
    1. ����� �������� �������� ������ � image, ��������� imgsize ����� �������� HIDE=>1
    2. � ���� imgsize ���������� ����� ������ imgSize � ���������� ����-��������. ����� NG::CoolField ������ �������� ����������� �����������, �����
       ������ ����������� ������ ����������� �� ����-��������. � ����������� �������� ����������� ����������� ������������� ������� Image::Magick
       ������������� ���� ��� ��������� ��������� ������ � �������� - ��������.
    3. ��������� ������ ����� beforeSave. ��� ����� ���� image ��� �������� � ��������� ��������� � ���������� OPTIONS.METHOD, ���������� ���������
       ���������� ����� � ������� ����� ������� �������.
    4. ���������� ���������� ������ ����� � �� 

    #Example 3. ��������� ������� ������������
    {FIELD=>'image',   TYPE=>'image',  NAME=>'�����������',UPLOADDIR=>"/some/dir", EARLY_PROCESS=>1,
        CHILDS=> [
            {FIELD=>"imgsize", METHOD=>"imgSize"},
            {FIELD=>"filesize", METHOD=>"fileSize"},
        ],
        OPTIONS=>{WIDTH=>400,METHOD=>"towidth"}
    },
    {FIELD=>'proxy',  TYPE=>'image'}
    {FIELD=>'imgsize',  TYPE=>'text',  NAME=>'�������� ������', HIDE=>1, CLASS=>"NG::CoolField"
    },
   
    # ��� �� �����������.  

=cut

sub _image2image {
    my ($self,$parent) = (shift,shift);
    
    #Parent field changed. Use existing file as source. It must be copied, not moved.
    my $v = $parent->value();
    if ($v) {
        $self->{_TMP_FILE_FROM_PARENT} = 1; #Special flag
        $self->{TMP_FILENAME} = $parent->{TMP_FILENAME};
        $self->setValue($v);
        $self->genNewFileName();
    }
    else {
        $self->clean();
    };
    return 1;
};

sub _file2file {
    my ($self,$parent) = (shift,shift);
    #Parent field changed.
    $self->clean();
    1;
};

sub _setValueFromField {
    my ($self,$parent) = (shift,shift);
    $self->setValue($parent->value());
    return 1;
};

## ��������� ����� �����������
sub process {
    my $self = shift;
    
    return 1 unless $self->changed();
    
    my $options = $self->{OPTIONS};
    unless ($options && ($options->{STEPS} || $options->{METHOD})) {
        return 1 unless $self->isFileField();
        return 1 unless $self->{_TMP_FILE_FROM_PARENT};
        
        my $newDbV = $self->dbValue();
        die 'Internal error' unless $newDbV;
        
        my $source = $self->value();
        my $dest = $self->cms()->getDocRoot().$self->{UPLOADDIR}.$newDbV;
        $self->_makeTargetDir($dest) or return 0;
        
        if ($source ne $dest) {
            copy($source,$dest) or return $self->setError("������ ����������� �����: ".$!);
            $self->setDBValue($newDbV);
            my $mask = umask();
            $mask = 0777 &~ $mask;
            chmod $mask, $dest;
        };
        return 1;
    };
    
    my $procClass = $self->getProcessorClass() or return $self->showError("������ ������ ������ getProcessorClass(). ����� �� ��������� ����� ������.");
    
    my $cms = $self->cms();
    my $pCtrl = $cms->getObject("NG::Controller",{
        PCLASS  => $procClass,
        STEPS   => $options->{STEPS} || [{METHOD=>$options->{METHOD},PARAMS=>$options->{PARAMS}}],
        FIELD   => $self,
        FORM    => $self->parent(),
    });
    
    if ($self->isFileField()) {
        my $newDbV = $self->dbValue();
        die 'Internal error' unless $newDbV;
        
        my $source = $self->value();
        my $dest = $self->cms()->getDocRoot().$self->{UPLOADDIR}.$newDbV;
        $self->_makeTargetDir($dest) or return 0;
        
        $pCtrl->process($source);
        $pCtrl->saveResult($dest);
        $self->setDBValue($newDbV);
    }
    else {
        my $value = $self->value();
        $pCtrl->process($value);
        $self->setValue($pCtrl->getResult());
    };
    return 1;
};

#���������� �������, ���� �� �������� �������� ���� �������
#���������� ��� $dbField ��� ����������� ������������� ������ ������� processChilds(), process(), clean()
sub changed {
    my ($field,$dbField) = (shift,shift);
    die "Not implemented" if $dbField && $dbField ne $field->{FIELD};

    return 1 if $field->{_changed};
    return 0;
};

sub beforeSave {
    my ($self,$action) = (shift,shift);
    
    if ($self->isFileField()) {
        return 1 unless $self->changed();
        return $self->setError("���������� �������� ���� {f} �� ���������, ���������� ���� �� ����� ������") unless $self->{_loaded} || ($action eq "insert");
        return $self->setError("�� ������� �������� ����� UPLOADDIR ��� ���� {f}") unless $self->{UPLOADDIR};

        my $uplDir = $self->cms()->getDocRoot().$self->{UPLOADDIR};
        
        my $file = $self->value();     #���� � �����, �������� ������ ��� ��������.
        my $newDbV = $self->dbValue(); #����� �������� dbValue, ���� ���� �����
        
        if ($file && $newDbV && $file ne $uplDir.$newDbV) {
            my $target = $uplDir.$newDbV;
            
            $self->_makeTargetDir($target) or return 0;
            
            move($file,$target) or return $self->setError("������ ����������� �����: ".$!);
            $self->setDBValue($newDbV); #���������� ����� �������� $field->{VALUE}, ���� ��� ���������.
            delete $self->{TMP_FILE} if $self->{TMP_FILE} eq $file;

            my $mask = umask();
            $mask = 0777 &~ $mask;
            chmod $mask, $target;
        };
        
        my $oldDbV = $self->{OLDDBVALUE};
        $self->_unlink($oldDbV) if ($oldDbV && $oldDbV ne $newDbV);
    }
    elsif ($self->{TYPE} eq "rtffile" || $self->{TYPE} eq "textfile") {
        my $dbv = $self->dbValue();
        return $self->setError("����������� ��� ����� ��� ���������� ������ ���� {f} (���: {t}).") unless $dbv;
        my ($v,$e) = saveValueToFile($self->{VALUE},$self->cms()->getSiteRoot().$self->{OPTIONS}->{FILEDIR}.$dbv);
        return $self->setError("������ ���������� ������ ���� {f}: ".$e) unless defined $v;
    };
    return 1;
};

sub afterSave {
    my ($self,$action) = (shift,shift);
    return 1;
};

sub beforeDelete {
    my $field = shift;
    
    my $type = $field->{TYPE};
    if ($field->isFileField() && !$field->{IS_FAKEFIELD}) {
        return $field->setError("�� ������� �������� ����� UPLOADDIR ��� ���� {f}") unless $field->{UPLOADDIR};
        return $field->setError("�������� ��������� ���� {f} �� ���������") unless $field->{_loaded};
        my $dbv = $field->dbValue();
        $field->_unlink($dbv) if $dbv;
    };
    if ($type eq "rtffile" || $type eq "textfile") {
        my $filedir = $field->options('FILEDIR') or return $field->setError("�� ������� ����� FILEDIR");
        return $field->setError("�������� ��������� ���� {f} �� ���������") unless $field->{_loaded};
        my $dbv = $field->dbValue();
        unlink $field->cms()->getSiteRoot().$filedir.$dbv if $dbv;
    };
    if ($type eq "rtf" || $type eq "rtffile") {
        #�������� ������������� ��������
        my $options = $field->{OPTIONS};
        next unless $options->{IMG_TABLE}; #���� IMG_TABLE �� �������, ������� ��� ������� �������� � ����������� ���� �� �������������
        return $field->setError("�� ������� �������� ����� IMG_UPLOADDIR") unless $options->{IMG_UPLOADDIR};
        
        my @params = ();
        my @fields = ();
        my $form = $field->parent();
        my $fieldsMap = $options->{IMG_TABLE_FIELDS_MAP} || {};

        #TODO: ���������� ��������� � �������� ����� �����
        foreach my $tmpfield (@{$form->{_keyfields}}) {
            my $name = $tmpfield->{FIELD};
            $name = $fieldsMap->{$name} if exists $fieldsMap->{$name};
            next unless $name;
            push @params, $tmpfield->{VALUE};
            push @fields, $name;
        };
    
        foreach my $key (keys %{$options->{IMG_TABLE_EXTRAKEY}}) {
            push @params, $options->{IMG_TABLE_EXTRAKEY}->{$key};
            push @fields, $key;
        };
    
        return $field->setError("�� ������� �������� ���� �������� �������� � ��������� ������") unless scalar @fields;
        $options->{IMG_TABLE_FILENAME_FIELD} ||= "filename"; #TODO: ������� �������� ����� � ���� ����� 
        my $sql = "select ".$options->{IMG_TABLE_FILENAME_FIELD}." from ".$options->{IMG_TABLE}." where ".join("=? and ",@fields)."=?";
    
        my $sth = $field->dbh()->prepare($sql) or return $field->setError($DBI::errstr);
        $sth->execute(@params) or return $field->setError($DBI::errstr);
        while (my ($filename) = $sth->fetchrow()) {
            unlink $form->getDocRoot().$options->{IMG_UPLOADDIR}.$filename;
        };
        $sth->finish();
        $field->dbh()->do("delete from ".$options->{IMG_TABLE}." where ".join("=? and ",@fields)."=?",undef,@params) or return $field->setError($DBI::errstr);
    };
    return 1;
};

sub afterDelete {
    my $field = shift;
    return 1;
};

sub getJSSetValue {
    my $field = shift;

    if (($field->{TYPE} eq "id") || ($field->{TYPE} eq "filter") || ($field->{TYPE} eq "file") ||($field->{TYPE} eq "image") ||($field->{TYPE} eq "checkbox")) {
        return ""; #TODO: ����������� ���������� ����������� ��������
    };
    
    my $fd = $field->{FIELD};
    my $value = escape_js $field->{VALUE};
    my $key_value = $field->parent()->getComposedKeyValue();
    $value = "" unless defined $value;
    return "parent.document.getElementById('$fd$key_value').value='$value';\n";
};

sub getJSShowError {
    my $field = shift;
    my $key_value = $field->parent()->getComposedKeyValue();
    my $fd = $field->{FIELD};
    my $em = escape_js $field->error();
    
    if ( $field->{IS_HIDDEN} || $field->{HIDE} ) {
        return (undef,$em);
    };
    
    my $error = "";
    if ($em) {
        $error .= "parent.document.getElementById('error_$fd$key_value').innerHTML='$em';";
        $error .= "parent.document.getElementById('error_$fd$key_value').style.display='block';\n";
    }
    else {
        $error .= "parent.document.getElementById('error_$fd$key_value').innerHTML='';";
        $error .= "parent.document.getElementById('error_$fd$key_value').style.display='none';\n";
    };
    return $error;
};

sub _makeTargetDir {
    my ($self, $target) = (shift,shift);
    
    my $targetDir = $target;
    $targetDir=~s@[^\/]+$@@; #�������� ����� ����� ���������� �����

    eval { mkpath($targetDir); };
    if ($@) {
        $@ =~ /(.*)at/s;
        return $self->setError("������ ��� �������� ����������: $1");
    };
    return 1;
};

sub _unlink {
    my ($field,$dbValue) = (shift,shift);
    
    die "Missing UPLOADDIR" unless $field->{UPLOADDIR};
    die "Missing DBValue" unless $dbValue;
    
    if ($field->{TYPE} eq 'image' && $field->{OPTIONS}->{IMGRESIZER}) {
        my $resizer = $field->{OPTIONS}->{IMGRESIZER};
        
        if ($resizer =~ /^([^\/]+)(\/\S+\/\S+)?$/) {
            my $module = $field->cms()->getModuleInstance($1);
            $module->deleteFromCache($field->{UPLOADDIR},$dbValue);
        }
        else {
            die "Wrong IMGRESIZER option";
        };
    };
    
    unlink $field->cms()->getDocRoot().$field->{UPLOADDIR}.$dbValue or warn "Could not unlink $field->{UPLOADDIR}$dbValue: $!";
};

sub clean {
    my $self = shift;
    
    if ($self->isFileField()) {
        die 'NG::Field::clean(): OLDDBVALUE not loaded!' unless exists $self->{OLDDBVALUE} || $self->{_new};
        my $oldDbV = $self->{OLDDBVALUE};
        
        $self->_unlink($oldDbV) if $oldDbV;
        return $self->setValue('');
    };
    return $self->setValue(undef) if !$self->{IS_NOTNULL};
    return $self->setValue(0) if ($self->{TYPE} eq "number" || $self->{TYPE} eq "int");
    return $self->setValue("");
};


sub ASHASH {
  my $self = shift;
  my %h = %{$self};
  return \%h;
}

#���������� HTML, ��������� � ����
sub getListCellHTML {
    my $field = shift;
    
    my ($type,$fName) = ($field->{TYPE},$field->{FIELD});
    
    if ($type eq 'image') {
        my $link = "";
        if ($field->{DBVALUE}) {
            my $resizer = $field->{OPTIONS}->{IMGRESIZER};
            if ($resizer && $resizer =~ /^(\S+)\/(\S+)\/(\S+)$/) {
                my ($code,$group,$size) = ($1,$2,$3);
                
                my $module = $field->cms()->getModuleInstance($code);
                $link = $module->getBaseURL() or return "[ERROR]";
                $link .= "$group/$size/".$field->{DBVALUE};
            }
            else {
                $link = $field->{UPLOADDIR}.$field->{DBVALUE};
            };
        };
        
        return "<div><img src='$link'".($field->{LIST_WIDTH}?' width="'.$field->{LIST_WIDTH}.'"':'').($field->{LIST_WIDTH}?' height="'.$field->{LIST_HEIGHT}.'"':'')."></div>" if $link;
        return '';
    }
    elsif ($type eq 'checkbox') {
        my ($clickable,$checked) = ('','');
        $clickable = 'clickable' if $field->{CLICKABLE};
        $checked   = 'checked'   if $field->{CHECKED};
        
        my $parent = $field->parent();
        my $id     = $parent->{ID_VALUE};
        
        return "<center>"
        ."<div class='list-checkbox $clickable $checked' data-field='$fName' data-id='$id'></div>"
        ."</center>";
    }
    elsif ($field->isFileField) {
        my $link = "";
        $link = $field->{UPLOADDIR}.$field->{DBVALUE} if $field->{DBVALUE};
        
        return "<a href='$link'>��������</a>" if $link;
        return '�����������';
    }
    else {
        my ($url,$title) = ($field->{URLMASK},$field->{TITLE}||'');
        
        if ($url) {
            my $parent  = $field->parent();
            my $baseurl = $parent->list()->getBaseURL();
            my $row     = $parent->{ROW};
            $url =~ s@{baseurl}@$baseurl@;
            $url =~ s/\{(.+?)\}/$row->{$1}/gi;
        };
        
        my $ret = '';
        $ret .= $url?"<a href='$url' title='$title'>":'<p>';
        $ret .= $field->{VALUE};
        $ret .= $url?"</a>":'</p>';
        return $ret;
    }
};

sub getListHeaderCell {
    my $field = shift;
    my ($type) = ($field->{TYPE});
    
    my $class = '';
    $class =  'center'   if $type eq 'checkbox';
    $class =  'posorder' if $type eq 'posorder';
    return {
        NAME  => $field->{NAME},
        CLASS => $class,
        TEMPLATE => $field->{HEADER_TEMPLATE}, #BW compat
        WIDTH    => $field->{WIDTH},
    };
};

sub getFieldActions {
    my $self = shift;
    
=head
   ������������ ��������: ������ �����, ������ ��� �������� ���������:
   ACTION - ��� �����, ������� ������������ � ������� ���� � ���� FIELD_ACTION
   METHOD - ��� ������ ������ ����, ������� ��������� �������
   NEED_LOAD_FOR_UPDATE - �������������� ����, ����������������
                          ���� NEED_LOAD_FOR_UPDATE ���� � ������
                          ��������� ������� ����� (�� �����������, �������� ������ ����� ����������� ����� �� ������������)
=cut
    
    if ($self->{TYPE} eq "rtf" || $self->{TYPE} eq "rtffile") {
        return [
            {ACTION=>"uploadimage", METHOD=>"uploadRtfImage",NEED_LOAD_FOR_UPDATE=>0},
        ];
    }
    elsif ($self->isFileField()) {
        return [
            {ACTION=>"deletefile", METHOD=>"deleteFile"},
        ];
    }
    else {
        return [];
    };
};

sub uploadRtfImage {
    my $field = shift;
    my $is_ajax = shift;

    return $field->setError("��������� ���� �� �������� ����� ���� rtf ��� rtffile.") unless ($field->{TYPE} eq "rtf" || $field->{TYPE} eq "rtffile");
    return $field->setError("uploadRtfImage() ����� ���������� ������ ��� ajax-�����.") unless $is_ajax;

    eval "use NG::RtfImage 0.4;";
    my $options = $field->{OPTIONS} or return NG::RtfImage->getErrorJS("�� ������ �������� OPTIONS");
    my $uploaddir = $options->{IMG_UPLOADDIR} or return NG::RtfImage->getErrorJS("�� ������� ����� IMG_UPLOADDIR");
    
    ## ���������� ����������� ���������� {} � IMG_UPLOADDIR
    
    #TODO: �������� �������� ������� ������ � ���������� ��������� ������
    #���. ����� ������ ����� �� ����, ��������� ���������� �������� � ��� �� ����������� ������.
    #�������: ��������� ������� �������� � ��� �� ��������� �������. 
    
    my $keyMap = {};
    my $form = $field->parent();
    #TODO: ���������� ��������� � �������� ����� �����
    foreach my $field (@{$form->{_keyfields}}) {
        return $field->setError("Field with type \"id\" or \"filter\" can`t have attribute IS_FAKEFIELD") if ($field->{IS_FAKEFIELD});
        return NG::RtfImage->getErrorJS("�� ������� �������� ��������� ���� $field->{FIELD}") if (is_empty($field->{VALUE}));
        $keyMap->{$field->{FIELD}} = $field->{VALUE};
    };
    $uploaddir =~ s/\{(.+?)\}/$keyMap->{$1}/gi;

    my $RI = NG::RtfImage->new(
        CGIObject=>$form->q(),
        DOCROOT=>$form->{_docroot},
        SUBDIR=>$uploaddir,                           ## �� ������������, �� ����� ������������, ��������.
        FIELDNAME=>'userfile',                        ## �� ������������ ��������.
    );

    if ($RI->moveUploadedFile()) {                    ## ����� ����������� �������� �����, ������ ��������� ��� �����
        if (!is_empty $options->{IMG_TABLE}) {
            my $idField       = $options->{IMG_TABLE_ID_FIELD}       || "id";
            my $filenameField = $options->{IMG_TABLE_FILENAME_FIELD} || "filename";
            my $file_name = $RI->filename();
	    
			my $id = $field->db()->get_id($options->{IMG_TABLE});
			return $RI->getErrorJS("������ �������� ������ � ��: ".$field->db()->errstr()) unless $id;
            my @params = ();
            my $sql = "insert into ".$options->{IMG_TABLE}." ($idField,$filenameField";
            my $fieldsMap = $options->{IMG_TABLE_FIELDS_MAP} || {};
            #TODO: ����������� ��������, ����� ��� ����� �� fieldsMap ���� ������������
            foreach my $name ( keys %{$keyMap} ) {
                my $name1 = $name;
                $name1 = $fieldsMap->{$name} if exists $fieldsMap->{$name};
                next unless $name1;
                $sql .= ",".$name1;
                push @params, $keyMap->{$name};
            };
            
            foreach my $key (keys %{$options->{IMG_TABLE_EXTRAKEY}}) {
                $sql .= ",".$key;
                push @params, $options->{IMG_TABLE_EXTRAKEY}->{$key};
            };
            return $RI->getErrorJS("�� ������� �������� ���� �������� ����������� �������� � ������") unless scalar @params;
            
            $sql .= ") values (?,?";
            $sql .= ",?" x scalar(@params);
            $sql .= ")";
            
            unshift @params, $file_name;
            unshift @params, $id;
            
            $field->dbh()->do($sql,undef,@params) or return $RI->getErrorJS("������ �������� ������ � ��: ($sql) ".$DBI::errstr);
        };
        return $RI->getFileNameJS();
    }
    else {
        $RI->cleanUploadedFile();           ## ������� ��������� ����
        return $RI->getErrorJS();           ## �������� �� ������.
    };
};

sub deleteFile {
    my $field = shift;
    my $is_ajax = shift;
    
    my $ret = eval {
        $field->parent()->cleanField($field);
    };
    if (my $exc = $@) {
        my $excMsg  = "";
        if (NG::Exception->caught($exc)) {
            my $excCode = $exc->code();
            $excMsg  = $exc->message()." (".$excCode.")";
        }
        elsif (ref $exc){
            $excMsg = "����������� ���������� ������ ".(ref $exc);
        }
        else {
            $excMsg = $exc;
        };
        return $field->error($excMsg);
    };
    
    if ($ret && $is_ajax) {
        return "<!-- -->"; #STUB
    };
    return $ret;
};

return 1;
END{};
