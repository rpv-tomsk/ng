package NG::Redirect;

use NG::PageModule;
use vars qw(@ISA);
@ISA = qw(NG::PageModule);

sub moduleTabs{
    return [{HEADER=>"Структура",URL=>"/"}]; 
};

sub moduleBlocks {
    return [{URL=>"/",BLOCK=>"NG::SiteStruct::Block"}];
};

sub getActiveBlock {
    my $self = shift;
    my $cms = $self->cms();
    my $page_id = $self->getPageId();
    my ($url) = $self->dbh->selectrow_array("select url from ng_sitestruct where parent_id=? and disabled=0 order by tree_order",undef,$page_id);
    unless ($url) {
        return $cms->notFound();
    };
    return $cms->redirect($url);
};

1;
