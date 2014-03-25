package NG::Banners::Clients;
use strict;

use NG::Form 0.4;
use NG::DBlist 0.4;
#use NG::Module 0.4;
use NSecure;
use NGService;

$Banners::Clients::VERSION=0.0000001;
use vars qw(@ISA);

#sub AdminMode
#{
# use NG::Module;
# @ISA = qw(NG::Module);
#};

sub AdminMode 
{
 use NG::Module::List;
 @ISA = qw(NG::Module::List);
};

sub config
{
 my $self=shift;
	$self->tablename('banner_clients');
    #$self->{'_additional_url'}="client";
    # Общая часть
    $self->fields(
                  {FIELD=>'id',     TYPE=>'id',   NAME=>'Код',      IS_NOTNULL=>1},
                  {FIELD=>'name',   TYPE=>'text', NAME=>'Название', IS_NOTNULL=>1, WIDTH=>'100%'},
                 );
    # Списковая
    $self->listfields([
                       {FIELD => 'name'},
                      ]);
    # Формовая часть
    $self->formfields(
                      {FIELD => 'id'},
                      {FIELD => 'name'},
                     );
    #$self->{_onpage}=1;
    $self->order("name");
    $self->add_url_field('name',$self->getBaseURL().'{id}/places/?cid={id}');#patch :)
 
    $self->setSubmodules(
                         [
                          {URL=>"places",MODULE=>"NG::Banners::Clients::CPlaces"},
                          {URL=>"cbanners",MODULE=>"NG::Banners::Clients::CBanners"},
                          {URL=>"shows",MODULE=>"NG::Banners::Clients::CShows" }
                         ]
                        );
 my $cid=is_valid_id($self->q()->param('cid'))?$self->q()->param('cid'):(is_valid_id($self->getParamFromUrl())?$self->getParamFromUrl():0);
                     
 if(is_valid_id($cid))
   {
    $self->setTabs(
                   {HEADER=>"Баннерные места клиента",TABURL=>"$cid/places",PARAMS=>["cid=$cid"]},
                   {HEADER=>"Баннера клиента",TABURL=>"$cid/cbanners",PARAMS=>["cid=$cid"]},
                   {HEADER=>"Показы баннеров",TABURL=>"$cid/shows",PARAMS=>["cid=$cid"]},
                  );  
   };
};

sub getParamFromUrl
{
 my $self=shift;
 my $url=$self->q()->url(-absolute=>1);
 $url=~/(\d+)$/;
 return $1;
};

sub getSubModuleName {
    my $self = shift;
    my $url=$self->q()->url(-absolute=>1);
    my $myBaseUrl = $self->getBaseURL();
    
    foreach my $subm (@{$self->{_submodules}}) {
        my $mUrl =$subm->{URL};
        $mUrl .= "/" if $mUrl !~ /\/$/;
        if ( $url =~ /^$myBaseUrl(\d+)\/$mUrl/ ) {
            return $subm->{MODULE};
        };
    };
    return "";
};

return 1;
END{};