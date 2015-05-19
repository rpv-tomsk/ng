package NG::Module::CMS;
use strict;

use base qw(NG::Module);

#TODO: Remove hardcoded SITESTRUCT value to $cms->confParam("CMS.SiteStructModule","") ??

sub keys_BREADCRUMBS {
    my $self = shift;
    
    my $pageRow = $self->getPageRow();
    
    my $req = {};
    $req->{pageId}  = $pageRow->{id};
    $req->{history} = $self->cms->getBreadcrumbs();
    
    return {
        REQUEST=>$req,
        VERSION_KEYS=> [
            {MODULECODE=>'SITESTRUCT', key=>'anypage'},
        ],
    };
};

sub block_BREADCRUMBS {
    my ($self,$action,$keys,$params) = (shift,shift,shift,shift);
    
    my $cms = $self->cms();
    
    return $cms->output("[Parameter 'template' not specified for block ".$self->getModuleCode()."_$action]") unless $params->{template};
    
    my $pageId  = $keys->{REQUEST}->{pageid};
    my $history = $keys->{REQUEST}->{history};
    my $minLevel = $params->{minlevel};

    $minLevel = 0 unless defined $minLevel;
    
    $history = [$history] if $history && ref $history eq "HASH";
    
    my $path = undef;
    my $version = $cms->getKeysVersion(undef,[
        {MODULECODE=>'SITESTRUCT', key=>'anypage'},
    ]);
    if ($version && $version->[0]) {  #Кеширование включено
        $path = $cms->getCacheData($self,{key=>'historyline_path', version=>$version->[0]});
    };
    unless ($path) {
        my $pageRow = $self->getPageRow();
        my $sql = "select id,full_name AS name,url from ng_sitestruct,"
        ." (SELECT max(tree_order) as maxorder FROM ng_sitestruct ngs2 WHERE ngs2.tree_order <= ? AND ngs2.level <= ? AND ngs2.level > ? GROUP BY ngs2.level) o"
        ." WHERE tree_order=o.maxorder ORDER BY tree_order";
        
        $path = $cms->dbh->selectall_arrayref($sql, {'Slice' => {}},$pageRow->{tree_order},$pageRow->{level},$minLevel) or NG::DBIException->throw();
        $cms->setCacheData($self,{key=>'historyline_path', version=>$version->[0]},$path) if $version && $version->[0];
    };
    
    if ($history) {
        push @$path, $_ foreach @$history;
    };
    
    my $tmpl = $cms->gettemplate($params->{template});
    $tmpl->param(
        HISTORY => $path,
    );
    
    return $cms->output($tmpl);
};

2;
