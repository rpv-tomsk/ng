package NG::Banners::BannersList;
use strict;

use NGService;
use NSecure;
use Data::Dumper;

use vars qw(@ISA);

sub AdminMode
{
 use NG::Module::List;
 @ISA = qw(NG::Module::List);
};

sub config
{
 my $self=shift;
 $self->tablename('banners');
 # ����� �����
 $self->fields(
               {FIELD=>'id',          TYPE=>'id',       NAME=>'���',        IS_NOTNULL=>1},
               {FIELD=>'name',        TYPE=>'text',     NAME=>'��������',   IS_NOTNULL=>1, WIDTH=>'100%'},
               #{FIELD=>'size_x',      TYPE=>'text',     NAME=>'������',     IS_NOTNULL=>1, WIDTH=>'10%'},
               #{FIELD=>'size_y',      TYPE=>'text',     NAME=>'������',     IS_NOTNULL=>1, WIDTH=>'10%'},
               #{FIELD=>'description', TYPE=>'textarea', NAME=>'����������', IS_NOTNULL=>0}
              );
 # ���������
 $self->listfields([
                    {FIELD => 'name'},
                   # {FIELD => 'size_x'},
                   # {FIELD => 'size_y'}
                   ]);
 # �������� �����
 $self->formfields(
                   {FIELD => 'id'},
                   {FIELD => 'name'},
                   #{FIELD => 'size_x'},
                   #{FIELD => 'size_y'},
                   #{FIELD => 'description'}
                   );
 #$self->{_onpage}=1;
 $self->order("name");
 #$self->setSubmodules(
 #                      [
 #                       {URL=>"places",MODULE=>"NG::Banners::Places"},
 #                      ]
 #                     );
 #���������� ���� � ������������ ���������
 #$self->setTabs(
 #               {HEADER=>"��������� �����",TABURL=>""}
 #              );                     
};

return 1;
END{};