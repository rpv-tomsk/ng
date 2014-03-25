package NG::FilesBlock;
use strict;
use NG::Module;
use vars qw(@ISA);
@ISA = qw(NG::Module);

sub moduleTabs {
	return [
		{HEADER=>"Файлы", URL=>"/"},
    ];
}

sub moduleBlocks {
	return [
		{URL=>"/", BLOCK=>"NG::FilesBlock::List"},
	]
};

sub block_LIST {
	my $self = shift;
	my $dbh = $self->dbh();
	my $pageId = $self->getPageId();
	my @files = ();
	my $sth=$dbh->prepare("select id,name,filename from ng_blockpagefiles where page_id=? order by order_number") or die $DBI::errstr;
	my $template = $self->cms->gettemplate("public/blocks/filesblock_list.tmpl");
	$sth->execute($pageId) or die $DBI::errstr;
	while (my $row = $sth->fetchrow_hashref) {
		$row->{filename} = "/upload/rtf/files/".$row->{filename};
		push @files, $row;			
	};
	$sth->finish();
	$template->param(
		FILES_LIST => \@files
	);
	return $self->cms->output($template);
};

package NG::FilesBlock::List;
use strict;

use NGService;
use NSecure;

use vars qw(@ISA);
use NG::Module::List;
@ISA = qw(NG::Module::List);

sub config {
	my $self = shift;
	$self->tablename('ng_blockpagefiles');
   
    $self->fields(
        {FIELD=>'id',       TYPE=>'id',   NAME=>'Код',IS_NOTNULL=>1},
        {FIELD=>'name',     TYPE=>'text', NAME=>'Название',IS_NOTNULL=>1,WIDTH=>"30%"},
        {FIELD=>'page_id',  TYPE=>'pageId', NAME=>'Имя',IS_NOTNULL=>1,WIDTH=>"30%"},
        {FIELD=>'filename', TYPE=>'file', NAME=>'Прикрепленный файл',IS_NOTNULL=>1,UPLOADDIR=>"/upload/rtf/files/"},
        {FIELD=>'order_number', TYPE=>'posorder', NAME=>'Позиция',IS_NOTNULL=>1}
    );
    # Списковая
    $self->listfields([
        {FIELD=>'_counter_',NAME=>"№"},
        {FIELD=>'name',},
        {FIELD=>'filename'},
    ]);
    # Формовая часть
    $self->formfields(
        {FIELD=>'id'},
        {FIELD=>'name'},
        {FIELD=>'filename'},
    );
  
    $self->order(
        {FIELD=>"name",DEFAULT=>0,ORDER_ASC=>"name",ORDER_DESC=>"name desc",DEFAULTBY=>'DESC', NAME=>"По наименованию"},
    );
    
    $self->{_onpage} = 20;
};

sub prepareData {
	my $self = shift;
	my $form = shift;
	my $action = shift;
	my $file_field = $form->_getfieldhash("filename");
	my $name_field = $form->_getfieldhash("name");
	if(!is_empty($file_field->{'TMP_FILE'})&&(-s $file_field->{'TMP_FILE'})>0) {
		$file_field->{TMP_FILENAME} =~ /([^\.]+?)$/;
		$file_field->{TMP_FILENAME} = int(rand(9999))."_".ts($name_field->{VALUE}).".".$1;
		$file_field->{TMP_FILENAME} =~ s/[^A-Za-z0-9\.\_]/_/gi;
	}; 
	return NG::Block::M_OK;
};

1;