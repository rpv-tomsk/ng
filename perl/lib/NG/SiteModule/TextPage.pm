package NG::SiteModule::TextPage;
use strict;
use NG::PageModule;
use NG::SiteStruct;
our @ISA = qw(NG::PageModule);

sub moduleTabs
{
    return [
        {'URL'=>'/','HEADER'=>'Структура'},
        {'URL'=>'/rtf/','HEADER'=>'Содержимое'}
    ];
};

sub moduleBlocks
{
    return [
        {'URL'=>'/','BLOCK'=>'NG::SiteStruct::Block'},
        {'URL'=>'/rtf/','BLOCK'=>'NG::SiteBlocks::RtfBlock'},
    ];
};


sub getUploadFilesDir
{
    return '/upload/rtf/files/';
};

sub initialisePage
{
    my $self = shift;
    my $dbh = $self->dbh();
    my $cms = $self->cms();
    my $page_row = $self->getPageRow();
    my $filename = 'html_'.$page_row->{id}.'.html';
    my $file = $cms->getSiteRoot().'/static/'.$filename;
    
    my $fh = undef;
    open($fh,'>'.$file) or return $cms->error('Can\'t create file'.$file);
    close($fh);
        
    $dbh->do("insert into ng_rtfpblocks (page_id,subpage,textfile) values(?,?,?)",undef,$page_row->{id},1,$filename) or return $cms->error($DBI::errstr);
    
    return 1;
};

sub getActiveBlock {
    return {'BLOCK'=>'CONTENT'};
};

sub block_CONTENT {
    my $self = shift;
    my $cms = $self->cms();
    my $page_row = $self->getPageRow();
    my $dbh = $self->dbh();
    my ($textfile,$pagename) = $dbh->selectrow_array('select textfile,full_name from ng_rtfpblocks r,ng_sitestruct s where r.page_id=? and s.id=r.page_id',undef,$page_row->{'id'});
    $textfile = $cms->getSiteRoot().'/static/'.$textfile if ($textfile);
    my $template = $self->gettemplate('public/textpage/textpage.tmpl');
    $template->param(
        'TEXTFILE' => $textfile,
        'PAGENAME' => $pagename
    );
    return $cms->output($template);
};

1;