package NG::Face;
use strict;

use NG::Application; # Суть NG::CMS

use vars qw(@ISA);
@ISA = qw(NG::Application);

=head
sub subpagesBlock {
	my $self = shift;
	my $data = $self->db()->dbh()->selectall_arrayref("select id,full_name,url from ng_sitestruct where parent_id = ? and active=1 order by tree_order",{Slice=>{}},$self->getPageId()) or return $self->showError($DBI::errstr);
	$self->tmpl()->param( SUBPAGES=>$data);
	return $self->ok();
}

sub setHistory {
	my $self=shift;
	my $historyLine=shift;
	my $pageParams=$self->getPageParams();
	if(!defined $historyLine) {
		my $sql="select id,full_name,url from ng_sitestruct,(select max(tree_order) as maxorder from ng_sitestruct where tree_order <=? and level <=? group by level) o where tree_order=maxorder and level>0 order by tree_order";
		my $sth=$self->db()->dbh()->prepare($sql) or return $self->setError($DBI::errstr);
		$sth->execute($pageParams->{'tree_order'},$pageParams->{'level'});
	    my @tmp=();
		while(my $row=$sth->fetchrow_hashref()) {
			push @tmp,{name=>$row->{'full_name'},url=>$row->{'url'}};
		};
		$sth->finish();
		$historyLine=\@tmp;      
	};
	$pageParams->{'history'}=$historyLine;
	return $self->ok();
};

sub pushHistory {
	my $self = shift;
	my $elem = shift;
	my $pageParams = $self->getPageParams();
	$pageParams->{history} ||= [];
	push @{$pageParams->{history}}, $elem;
};
=cut

sub run {
    my $cms=shift;

	$cms->openConfig() || return $cms->showError();
    
    my $url = $cms->q()->url(-absolute=>1);
    my ($ret,$subsiteId) = $cms->findSubsite($url); #or return; # 302 или Error
	
	return $cms->processResponse($ret) unless $ret eq NG::Application::M_OK;
    
    #if ($url =~ m@/admin-side/@) {
    #    
    #};

	#Система статистики: TODO: заменить на отдельный спец вызов
	my $counterClass = $cms->confParam("Site.CounterClass","");
	my $counterObj = undef;
	if ($counterClass) {
        $counterObj = $cms->getObject($counterClass) or return $cms->showError();
	};
    
=head
    while (1) {
        $ret = $cms->findPageRowByURL($url,$subsiteId); ## Юзает subsiteId, выставляет {_pageRow}. Может возникнуть 404 или Error
        last unless $ret == NG::Application::M_OK;
    
        $ret = $cms->runPageController($cms->pageParam('module'));
        
        last;
    };
=cut
    
	$ret = $cms->processRequest($url,$subsiteId);
	
#warn "ret $ret";    

#print STDERR "FOUND ROW: ".$row->{id}. " m: ".$row->{module}." t: ".$row->{template};
    #return $cms->runPageController($row->{module},$row->{template});

    

    #if ($ret == NG::Application::M_404) {
    #    $cms->header(-status=>404);
    #    print "Наша клевая страница не найдена";
    #    return 1;
    #    $ret = $cms->output("Наша клевая ит д ")
    #};

    if ($counterObj) {
        $counterObj->countPage($ret) or $counterObj->showError();
    };

    return $cms->processResponse($ret);

    #my $url = "/news/";
    #if ($url =~ /\/news/) {
    #    $cms->runPageController("SBI::News",'news/main.tmpl');
    #}

};

return 1;
END{};
