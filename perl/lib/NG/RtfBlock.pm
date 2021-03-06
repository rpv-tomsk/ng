package NG::RtfBlock;
use strict;

use vars qw(@ISA);
$NG::RtfBlock::VERSION=0.5;

use NG::PageModule 0.5;
@ISA = qw(NG::PageModule);

use NGService;

=head
  ����� ������, ������������ � ng_modules.params:
    rtfconfig - JS ������� ���������������� ����������
    table     - ��� ������� ���������� �������
    imgtable  - ��� ������� ���������� ������� � ������������� ���������
    imgdirmask  - ����� ���� ���������� ������������� ��������
    hassubpages - ������� ����������
    rtffilemask - ����� ����� ����� � ���������
    rtfdir      - ���� ���������� ������ � ���������, ������������ siteRoot
    blockClass  - ����� ����������������� �����
    layout      - ������ ������
    template    - ������ ������
=cut

sub init {
    my $self = shift;
    $self->SUPER::init(@_);
    
    $self->{_table} = $self->moduleParam('table') || "ng_rtfpblocks";
    $self->{_imgtable} = $self->moduleParam('imgtable');
    $self->{_imgtable} = "ng_rtfpblock_images" unless defined $self->{_imgtable};
    $self->{_hassubpages} = $self->moduleParam('hassubpages') || 0;
    $self->{_blockClass} = $self->moduleParam('blockClass');
    $self->{_blockClass} ||= "NG::RtfBlock::Block";
    
    $self->{_rtffilemask} = $self->moduleParam('rtffilemask');
    unless (defined $self->{_rtffilemask}) {
        if ($self->{_hassubpages}) {
            $self->{_rtffilemask} = "html_{page_id}_{subpage}.html";
        }
        else {
            $self->{_rtffilemask} = "html_{page_id}.html";
        };
    };
    $self->{_rtfdir} = $self->moduleParam('rtfdir') || "/static/";
    $self->{_rtfdir} .= '/' unless $self->{_rtfdir} =~ /\/$/;
    $self->{_rtfdir} = '/'.$self->{_rtfdir} unless $self->{_rtfdir} =~ /^\//;
    $self->{_rtfconfig} = $self->moduleParam('rtfconfig');
    
    $self->{_imgdirmask} = $self->moduleParam('imgdirmask');
    $self->{_imgdirmask} ||= "upload/rtf/{page_id}/";
    $self;
};

sub getActiveBlock {
    my $self = shift;
    my $block = { BLOCK => 'CONTENT' };
    my $layout = $self->moduleParam('layout');
    $block->{LAYOUT} = $layout if $layout;
    return $block;
};

sub keys_CONTENT {
    my ($self, $action, $params) = (shift, shift, shift);
    
    my $req = {};
    $req->{pageId}  = $self->getPageId();
    $req->{subpage} = $params->{subpage} || 1;
    
    return {REQUEST=>$req};
};

sub block_CONTENT {
    my ($self,$action,$keys,$params) = (shift,shift,shift,shift);
    
    my $cms = $self->cms();
    
    my ($pageId, $subPage);
    if ($keys && $keys->{REQUEST}) {
        $pageId  = $keys->{REQUEST}->{pageId}; 
        $subPage = $keys->{REQUEST}->{subpage};
    }
    elsif ($params) {  #������ ������� ������, ��. ������.
        $pageId  = $self->getPageId();
        $subPage = $params->{subpage} || 1;
    }
    else {
        #�������� ������������� � ���������� �������, ��. ������.
        my $opts = $self->opts();
        $pageId  = $self->getPageId();
        $subPage = $opts->{subpage} || 1;
    };
    return $cms->error('block CONTENT: pageId value is missing') unless $pageId;
    return $cms->error('block CONTENT: subpage value is missing') unless $subPage;
    my $file = $cms->db()->dbh()->selectrow_array("select r.textfile from ".$self->{_table}." r where r.page_id=? and subpage=?",undef,$pageId,$subPage);
    return $cms->error("Content file name not found in ".(ref $self)."::getBlockContent") unless $file;
    $file = $cms->getSiteRoot().$self->{_rtfdir}.$file if $file;
    #$v = value
    #$e = error text
    my ($v,$e) = loadValueFromFile($file);
    return $cms->error($e) if($e);
    
    my $template = $self->moduleParam('template');
    if ($template) {
        my $tmpl = $cms->gettemplate($template);
        $tmpl->param(
            PAGE    => $self->getPageRow(),
            CONTENT => $v,
        );
        return $cms->output($tmpl);
    };
    return $cms->output($v);
};

sub moduleTabs {
    return [
        {HEADER=>"���������� ��������", URL=>"/"},
    ];
};


sub moduleBlocks {
    my $self = shift;
    return [
        {URL=>"/", BLOCK=>$self->{_blockClass},TYPE=>"moduleBlock"},
    ];
};

package NG::RtfBlock::Block;

use strict;
use vars qw(@ISA);
use NG::Module::Record 0.5;

BEGIN {
    @ISA = qw(NG::Module::Record);
};

sub config  {
    my $self = shift;
    
    my $opts = $self->opts();
    my $subp = $opts->{subpage} || 1;
    
    my $mObj;
    if ($opts->{modulecode}) {
        $mObj = $self->cms->getModuleByCode($opts->{modulecode});
    }
    else {
        $mObj = $self->{_moduleObj};
    };
    
    $self->{_table} = $mObj->{_table};
    
    $self->fields(
        {FIELD=>'page_id',  TYPE=>'pageId'},
    );
    
    if ($mObj->{_hassubpages}) {
        $self->fields({FIELD=>'subpage',  TYPE=>'subpage', NAME=>'����� ��������:'});
    }
    else {
        $self->fields({FIELD=>'subpage',  TYPE=>'filter', VALUE=>$subp});
    }
    
    $self->fields(
        {FIELD=>'textfile', TYPE=>'rtffile', NAME=>'�����',
            OPTIONS=>{
                IMG_TABLE => $mObj->{_imgtable},
                IMG_UPLOADDIR => $mObj->{_imgdirmask},
                FILENAME_MASK => $mObj->{_rtffilemask},
                FILEDIR => $mObj->{_rtfdir},
                CONFIG  => $mObj->{_rtfconfig},
            }
        },
    );
    my $mCode = $self->opts->{modulecode};
    unless ($mCode) {
        $mCode = $self->{_moduleObj}->getModuleCode();
    };
    $self->updateKeysVersion([
        {MODULECODE=>$mCode, key=>'rtfblock', pageId=>'{page_id}', subpage=>'{subpage}'},
        {MODULECODE=>$mCode, key=>'rtfblock'},
    ]);
    #TODO: add searchConfig
};

sub _handleCMSCache {
    my ($self,$form,$action) = (shift,shift,shift);
    
    $self->SUPER::_handleCMSCache($form, $action);
    
    my $pageId = $form->getParam('page_id');
    my $subpage = $form->getParam('subpage');
    
    my $mCode = $self->opts->{modulecode};
    unless ($mCode) {
        $mCode = $self->{_moduleObj}->getModuleCode();
    };
    
    $self->cms->expireCacheContent(undef,[
        {MODULECODE => $mCode, BLOCK=>'CONTENT', REQUEST => {pageId => $pageId, subpage => $subpage}},
    ]);
    
    return 1;
};

return 1;

=head

������ ����������� ���������� ����� � ������ �����


sub getActiveBlock {

    if ($CONDITION)  {
        #
        # � ������ ������� ����� ������ ���������� ���������� ��������� ��������.
        # �������������� ������ �� ������ ������ RTF / ���� CONTENT.
        return {CODE=>'RTF_CONTENT',LAYOUT=>'public/textpageLayout.tmpl'} if $url =~ /^${bUrl}terms\/$/;

        # ���������� ���� CONTENT ���� ����� ������������ �� NG::RtfBlock
        return {BLOCK => "CONTENT", PARAMS=>{subpage=>2}} if ... ;

        # ��� ����������� ��� ��������������� �� ������ ������/���� ����� �������� �
        # ������������ getActiveBlock() �������� ����
        # PARAMS => {subpage => 1}, ������� ����� �������� � getBlockKeys()/getBlockContent().
        #
        # ����� �������� ���� KEYS => {REQUEST => {pageId=>$self->getPageId(), subpage => XXX}  }
        # getBlockKeys() ��� ����� ����� � ���� ������ ���������� �� ����� (��� �����).
    }
}

sub moduleTabs{
    return [
        ...
        {HEADER=>"�������� ������", URL=>"/agreement/"},
        ...
    ];
};

sub moduleBlocks{
    return [
        ...
        # modulecode ����� ��� ��������, � ����� ������ ����� ������������, � ����� ��� ����������� ������ � �����.
        # (����������� ���������� NG::RtfBlock::Block
        {URL=>"/agreement/", BLOCK=>'NG::RtfBlock::Block', USE=>'NG::RtfBlock', OPTS=>{subpage=>1,modulecode=>'RTF'}},
        ...
        
        #TODO: ������������ �� ������ subpage, �� � pageId...
    ];
};

��������� ��������:

    #������������ ������� - subpage=>2 ���� ���������� ��-�������.
    my $mObj = $cms->getModuleByCode('RTF',{PAGEPARAMS=>$self->getPageRow(), subpage=>2});
    my $r = $mObj->getBlockContent('CONTENT');
    return $r unless $r && $r->is_output;
    $tmplObj->param(TEXT=>$r->getOutput());
    
    #����� ���������� �������:
    my $r = $mObj->getBlockContent('CONTENT',undef,{subpage=>2});
=cut
