package NG::Module::List::Row;

use strict;
use NG::Field;
use NGService;
use URI::Escape;

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
	my $self = shift;
	$self->{_row} = shift;
	$self->{_listObj} = shift;
	$self->{_number} = undef;
	$self->{ROW_LINKS} = [];
	$self->{COLUMNS} = [];
	$self->{HCOLUMNS} = {};
};

sub row {
  my $self = shift;
  return $self->{_row};
};
 
sub addColumn {
	my $self = shift;
	my $column = shift;
	return if ($column->{TYPE} eq "posorder");
	push @{$self->{COLUMNS}}, $column unless ($column->{TYPE} eq "hidden" || $column->{HIDE});
	$self->{HCOLUMNS}->{uc($column->{FIELD})} = $column;
};

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

sub buildLinks {
	my $self = shift;
	my $deletelink = $self->list()->getDeleteLink();
	my $extralinks = $self->list()->getExtraLinks();
	foreach my $link (@{$extralinks}) {
		$self->pushLink($link);
	};
	$self->pushLink($deletelink) if ($deletelink);
};

sub getParam {
	my $self = shift;
	my $param = shift;
	return $self->{_row}->{$param};
};

sub getField {
	my $self = shift;
	my $fieldname = shift;
	return $self->{HCOLUMNS}->{uc($fieldname)};
};

sub list {
	my $self = shift;
	return $self->{_listObj};
};

sub number {
	my $self = shift;
	my $number = shift;
	if ($number) {
		$self->{_number} = $number;
	};
	return $self->{_number};
};

sub buildColumnList {
	my $self = shift;
	my $fields = {};
	my $row = $self->{_row};
	#Достаем Значения для селектов
    foreach my $cname (keys %{$self->{HCOLUMNS}}) {
      my $column = $self->{HCOLUMNS}->{$cname};
		if ($column->{TYPE} eq "posorder") { next; };
        if ($column->{URLMASK}) {
            my $baseurl = $self->list()->getBaseURL();
            $column->{URLMASK} =~ s@{baseurl}@$baseurl@;
			$column->{URLMASK} =~ s/\{(.+?)\}/$row->{$1}/gi;
        };
        $column->{URLFIELD} = $column->{URLMASK}; #TODO: изменить в шаблоне имя переменной.
        if ($column->{FIELD} eq "_counter_") {
        	$column->setDBValue($self->number());
			next;
        };
        
		$column->setDBValue($self->getParam($column->{FIELD}));
    };		
};

sub getValue {
	my $self = shift;
	my $fieldname = shift;
	return $self->{HCOLUMNS}->{uc($fieldname)}->value();
};


sub db {
	my $self = shift;
	return $self->list()->db();
};

sub getComposedKeyValue() {
    my $self = shift;
    my $keyValue = "";
    foreach my $cname (keys %{$self->{HCOLUMNS}}) {
        my $field = $self->{HCOLUMNS}->{$cname};
        next unless ($field->{TYPE} eq "id") || ($field->{TYPE} eq "filter");
        return $self->error("Field with type \"id\" or \"filter\" can`t have attribute IS_FAKEFIELD") if ($field->{IS_FAKEFIELD});
        $keyValue .= "_".$field->{VALUE};
    };
	$keyValue =~ s/^_//;
    return $keyValue;
};

sub getDocRoot {
	my $self = shift;
	return $self->list()->getDocRoot();
};

sub getSiteRoot {
	my $self = shift;
	return $self->list()->getSiteRoot();
};

sub highlight {
	my $self = shift;
	$self->{HIGHLIGHT} = 1;
};

return 1;
END{};
