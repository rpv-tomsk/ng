package NG::Module::List::Row;

use strict;
use NG::Field;
use NGService;

use vars qw(@ISA);
BEGIN {};

sub new {
    my $class = shift;
    my $obj = {};
    bless $obj, $class;
    $obj->init(@_);
    return $obj;
};

sub init {
    my ($self,$params) = (shift,shift);
    
    $self->{ROW}      = $params->{DATA};       # ��� ������
    $self->{_listObj} = $params->{LISTOBJ};
    $self->{_index}   = $params->{INDEX};      # ������ ������ � �������
    my $id            = $params->{ID};         # ID ������ ������
    
    $self->{ROW_LINKS} = [];     #������ ������ �������� �� �������
    $self->{COLUMNS} = [];       #������ �������� �����
    $self->{HFIELDS} = {};       #��� �������� NG::Field
    
    $self->{KEY_VALUE} = "_$id";  #������������ � ������� 
    $self->{ID_VALUE} = $id;      #� ��� ����� ��� �������
    
    foreach my $field (@{$self->{_listObj}->{_listfields}}) {
        my $c = NG::Field->new($field,$self) or die $NG::Field::errstr;
        $self->_addColumn($c);
    };
    
    $self->buildLinks();
    
    #�������� HTML ����� �������� ���� ��������
    foreach my $t (@{$self->{COLUMNS}}) {
        $t->{HTML} = $t->{FIELD}->getListCellHTML();
    };
};

#�����, ������������ � �������������� �������
 
sub _addColumn {
    my ($self, $field) = (shift,shift);
    return if ($field->{TYPE} eq "posorder");
    
    $self->{HFIELDS}->{uc($field->{FIELD})} = $field;
    
    if ($field->{FIELD} eq "_counter_") {
        $field->setDBValue($self->number());
    }
    else {
        $field->setDBValue($self->getParam($field->{FIELD}));
    };
    
    unless ($field->{TYPE} eq "hidden" || $field->{HIDE}) {
        push @{$self->{COLUMNS}}, {
            FIELD => $field,
            CUSTOM_TEMPLATE => $field->{CUSTOM_TEMPLATE},
        };
    };
};

#�����, ������������ � �������������� �������
sub pushLink {
    my $self = shift;
    my $tmplink = shift;
    my $link = undef;
    %{$link} = %{$tmplink};
    
    while ($link->{URL} =~ /\{(.+?)\}/i) {
        my $value = $self->getParam($1);
        $link->{URL} =~ s/\{(.+?)\}/$value/i;
    };
    
    if (($link->{URL} =~ /^\?/ || $link->{URL} !~ /^\//) && $link->{URL} !~ /^[a-zA-Z0-9]+\:\/\//) {
        $link->{URL} = $self->list()->getBaseURL().$self->list()->getSubURL().$link->{URL};
    };
    
    $link->{URL} = getURLWithParams($link->{URL},"ref=".$self->list()->buildRefCurrentUrl());
    if ($link->{AJAX}) {
        $link->{AJAX_URL} = getURLWithParams($link->{URL},"_ajax=1","rand=".int(rand(10000)));
    };
    push @{$self->{ROW_LINKS}}, $link;
}; 

#�����, ������������� � �������������� �������
sub buildLinks {
    my $self = shift;
    my $deletelink = $self->list()->getDeleteLink();
    my $extralinks = $self->list()->getExtraLinks();
    foreach my $link (@{$extralinks}) {
        $self->pushLink($link);
    };
    $self->pushLink($deletelink) if ($deletelink);
};

#������, ������������ � �������������� �������
sub getParam {
    my $self = shift;
    my $param = shift;
    return $self->{ROW}->{$param};
};

sub getField {
    my $self = shift;
    my $fieldname = shift;
    return $self->{HFIELDS}->{uc($fieldname)};
};

sub getValue {
    my $self = shift;
    my $fieldname = shift;
    return $self->{HFIELDS}->{uc($fieldname)}->value();
};

sub row {
    my $self = shift;
    return $self->{ROW};
};

sub list {
    my $self = shift;
    return $self->{_listObj};
};

sub db {
    my $self = shift;
    return $self->{_listObj}->db();
};

sub getDocRoot {
    my $self = shift;
    return $self->{_listObj}->getDocRoot();
};

sub getSiteRoot {
    my $self = shift;
    return $self->{_listObj}->getSiteRoot();
};

sub highlight {
    my $self = shift;
    $self->{HIGHLIGHT} = 1;
};

return 1;
END{};
