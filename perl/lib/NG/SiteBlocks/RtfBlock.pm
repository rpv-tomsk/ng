package NG::SiteBlocks::RtfBlock;
use strict;
use NG::Module::Record;
our @ISA = qw(NG::Module::Record);

sub config  {
    my $self = shift;
    my $m = $self->getModuleObj();
    $self->{_table} = $m->{_rtf_table} || "ng_rtfpblocks";
	
    $self->fields(
        {FIELD=>'page_id',  TYPE=>'pageId'},
        {FIELD=>'textfile', TYPE=>'rtffile', NAME=>'Текст',
        	OPTIONS=>{
	        	IMG_TABLE => $m->{_rtf_img_table} || "ng_rtfpblock_images",
	        	IMG_UPLOADDIR => $m->{_rtf_img_uploaddir} || "/upload/rtf/",
	        	FILENAME_MASK => $m->{_rtf_filename_mask} || "html_{page_id}.html",
	        	FILEDIR => $m->{_rtf_dir} || "/static/",
				CONFIG  => $m->{_rtf_config} || "rtf",
        	}
        }
    );
};

1;