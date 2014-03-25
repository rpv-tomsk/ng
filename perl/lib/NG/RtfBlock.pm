package NG::RtfBlock;
use strict;

use vars qw(@ISA);
$NG::RtfBlock::VERSION=0.5;

use NG::PageModule 0.5;
@ISA = qw(NG::PageModule);

use NGService;

=head
  Ключи модуля, используемые в ng_modules.params:
    rtfconfig - JS функция конфигурирования компоненты
    table     - имя таблицы сохранения записей
    imgtable  - имя таблицы сохранения записей о прикрепленных картинках
    imgdirmask  - маска пути сохранения прикрепленных картинок
    hassubpages - наличие подстраниц
    rtffilemask - маска имени файла с контентом
    rtfdir      - путь сохранения файлов с контентом, относительно siteRoot
    blockClass  - класс администрирования блока
    layout      - лайаут вывода
    template    - шаблон вывода
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

sub getBlockKeys {
    my ($self, $action) = (shift,shift);
   
    my $cms = $self->cms();
    return $cms->error("NG::RtfBlock: invalid getBlockKeys action $action") if $action ne "CONTENT";
   
    my $opts = $self->opts();
   
    my $req = {};
    $req->{pageId}  = $self->getPageId();
    $req->{subpage} = $opts->{subpage} || 1;
    
    return {REQUEST=>$req};
};

sub getBlockContent{
	my ($self,$action,$keys) = (shift,shift,shift);

	my $cms = $self->cms();
    my $opts = $self->opts();
    
    my ($pageId, $subPage);
    
    if ($keys && $keys->{REQUEST}) {
        $pageId  = $keys->{REQUEST}->{pageId}; 
        $subPage = $keys->{REQUEST}->{subpage};
    }
    else {
        $pageId  = $self->getPageId();
        $subPage = $opts->{subpage} || 1;
    };  
    
    if ($action eq "CONTENT") {
     	my $file = $cms->db()->dbh()->selectrow_array("select r.textfile from ".$self->{_table}." r where r.page_id=? and subpage=?",undef,$pageId,$subPage);
        return $cms->error("Content file name not found in ".(ref $self)."::getBlockContent") unless($file);
        $file = $cms->getSiteRoot().$self->{_rtfdir}.$file if $file;
        #$v = value
        #$e = error text
        my ($v,$e) = loadValueFromFile($file);
        return $cms->error($e) if($e);
        my $template = $self->moduleParam('template');
        if ($template) {
            my $tmpl = $cms->gettemplate($template) or return $cms->error();
            $tmpl->param(
                PAGE    => $self->getPageRow(),
                CONTENT => $v,
            );
            return $cms->output($tmpl);
        };
        return $cms->output($v);
    };
	return $cms->error("NG::RtfBlock: invalid getBlockContent action $action");
};

sub moduleTabs {
    return [
        {HEADER=>"Содержимое страницы", URL=>"/"},
    ];
};


sub moduleBlocks {
    my $self = shift;
    return [
        {URL=>"/", BLOCK=>$self->{_blockClass},TYPE=>"moduleBlock"},
    ];
};

sub modulePrivileges {
	return [];
};

1;

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
	
	my $mObj = $self->{_moduleObj};
	
    $self->{_table} = $mObj->{_table};
	
    $self->fields(
        {FIELD=>'page_id',  TYPE=>'pageId'},
	);

	if ($mObj->{_hassubpages}) {
		$self->fields({FIELD=>'subpage',  TYPE=>'subpage', NAME=>'Части страницы:'});
	}
    else {
        $self->fields({FIELD=>'subpage',  TYPE=>'filter',VALUE=>$subp});
    }
	
	$self->fields(
        {FIELD=>'textfile', TYPE=>'rtffile', NAME=>'Текст',
        	OPTIONS=>{
	        	IMG_TABLE => $mObj->{_imgtable},
	        	IMG_UPLOADDIR => $mObj->{_imgdirmask},
	        	FILENAME_MASK => $mObj->{_rtffilemask},
	        	FILEDIR => $mObj->{_rtfdir},
				CONFIG  => $mObj->{_rtfconfig},
        	}
        },
    );
    #TODO: add searchConfig
};



return 1;
