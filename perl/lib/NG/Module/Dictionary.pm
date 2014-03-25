package NG::Module::Dictionary;
use strict;

=head
  Модуль универсального администрирования справочников
  
  Ключи модуля, используемые в ng_modules.params:
    table     - имя таблицы сохранения записей
    tab      - имя вкладки 
    hasPosition - есть поле position
    
    table_1
    tab_1
    hasPosition_1
=cut

$NG::Module::Dictionary::VERSION=0.5;

use NG::Module 0.5;
our @ISA = qw(NG::Module);

sub init {
    my $self = shift;
    $self->SUPER::init(@_);
    
    $self->{_table} = $self->moduleParam('table') or return $self->cms->error("Отсутствует параметр table в записи регистрации модуля ng_modules");
    
    my @x = ();
    my @y = ();
    push @x, {URL=>'/', HEADER=>$self->moduleParam('tab')||"Справочник"};
    push @y, {URL=>'/', BLOCK=>'NG::Module::Dictionary::Block', OPTS=>{
        hasPosition=>$self->moduleParam("hasPosition"),
        table=>$self->moduleParam("table"),
    }};

    my $i = 0;
    my $k = 1;
    while (1) {
        $i++;
        my $table = $self->moduleParam("table_$i") or last;
        push @x, {URL=>"/$i/", HEADER=>$self->moduleParam("tab_$i")||"Справочник $i"};
        push @y, {URL=>"/$i/", BLOCK=>'NG::Module::Dictionary::Block', OPTS=>{
            hasPosition=>$self->moduleParam("hasPosition_$i"),
            table=>$self->moduleParam("table_$i"),
            },
        };
        die "Something went wrong in this code." if ($k++ > 100);
    };
    $self->{_tabs} = \@x;
    $self->{_blocks} = \@y;
    $self;
};

sub moduleTabs {
    my $self = shift;
    return $self->{_tabs};
};

sub moduleBlocks {
    my $self = shift;
    return $self->{_blocks};
};

package NG::Module::Dictionary::Block;
use strict;
use NG::Module::List;

our @ISA = qw(NG::Module::List);

sub config {
    my $self = shift;
    
    my $mObj = $self->getModuleObj();
    
    $self->{_table} = $self->opts('table');
    
    $self->fields(
        {FIELD=>'id', TYPE=>'id'},
        {FIELD=>'name', TYPE=>'text', IS_NOTNULL=>1, NAME=>'Название',WIDTH=>"100%"},
    );
    $self->fields(
        {FIELD=>'position', TYPE=>'posorder', NAME=>'Позиция'},
    ) if $self->opts('hasPosition');
    
    $self->formfields(
        {FIELD=>'id'},
        {FIELD=>'name'}
    );
    $self->listfields(
        {FIELD=>'name'}
    );
};

1;
