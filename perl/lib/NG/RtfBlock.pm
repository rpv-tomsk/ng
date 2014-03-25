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
=cut

sub init {
	my $self = shift;
	$self->SUPER::init(@_);
	
	$self->{_table} = $self->moduleParam('table') || "ng_rtfpblocks";
	$self->{_imgtable} = $self->moduleParam('imgtable');
    $self->{_imgtable} = "ng_rtfpblock_images" unless defined $self->{_imgtable};
	$self->{_hassubpages} = $self->moduleParam('hassubpages') || 0;
	$self->{_blockClass} = "NG::RtfBlock::Block";
    
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

	return {
		BLOCK => "CONTENT",
	};
};

sub getBlockContent{
	my $self = shift;
    my $action = shift;

	my $cms = $self->cms();
    
    if ($action eq "CONTENT") {
     	my $file = $cms->db()->dbh()->selectrow_array("select r.textfile from ".$self->{_table}." r where r.page_id=?",undef,$self->getPageId());
        return $cms->error("Content file name not found in ".(ref $self)."::getBlockContent") unless($file);
        $file = $cms->getSiteRoot().$self->{_rtfdir}.$file if $file;
        #$v = value
        #$e = error text
        my ($v,$e) = loadValueFromFile($file);
        return $cms->error($e) if($e);
        return $cms->output($v);
    }
	return $cms->error("NG::RtfBlock: invalid getBlockContent action $action");
};

sub getAdminBlock {
	my $self = shift;
	return $self->{_blockClass};
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
	
	my $mObj = $self->{_moduleObj};
	
    $self->{_table} = $mObj->{_table};
	
    $self->fields(
        {FIELD=>'page_id',  TYPE=>'pageId'},
	);

	if ($mObj->{_hassubpages}) {
		$self->fields({FIELD=>'subpage',  TYPE=>'subpage', NAME=>'Части страницы:'});
	};
	
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
};



return 1;
