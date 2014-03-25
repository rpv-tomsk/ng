package NG::Sitetemplates;
use strict;

use NG::Application::List;
use NGService;
use NSecure;
use NG::Form;
use Data::Dumper;
use vars qw(@ISA);
@ISA = qw(NG::Application::List);

sub config {
    my $self = shift;
    $self->tablename('ng_templates');
    $self->addfields({TYPE=>'id', NAME=>'Код',FIELD=>'id',IS_NOTNULL=>1});
    $self->addfields({TYPE=>'text', NAME=>'Наименование шаблона',FIELD=>'name',IS_NOTNULL=>1,WIDTH=>"80%"});
    $self->addfields({TYPE=>'text', NAME=>'Относительный путь к файлу',FIELD=>'file',IS_NOTNULL=>1,WIDTH=>"20%"});
    $self->listfields('id','name','file');
    $self->formfields('id','name','file');
    $self->{_onpage} = 10;
    $self->add_links("Блоки","/admin-side/templates/?template_id={id}&action=showblocks",1);
    $self->register_ajaxaction("showblocks","showBlocks");
    $self->register_ajaxaction("addblocks","addBlocks");
    $self->register_ajaxaction("showpopupblocks","showPopupBlocks");
}


sub addBlocks {
	my $self = shift;
	my $action = shift;
	my $q = $self->q();
	my $dbh = $self->db()->dbh();
	my $template_id = $q->param('template_id');
	my $block_id = $q->param('block_id');
	my $sth = undef;
	if (is_valid_id($template_id) && is_valid_id($block_id)) {
		$sth = $dbh->prepare("select count(*) from ng_template_blocks where template_id=? && block_id=?") or die $DBI::errstr;
		$sth->execute($template_id,$block_id) or die $DBI::errstr;
		my ($size) = $sth->fetchrow_hashref();
		$sth->finish();
		if (!$size) {
			$dbh->do("insert into ng_template_blocks(template_id,block_id) values(?,?)",undef,$template_id,$block_id) or die $DBI::errstr;
		};
	};
	$self->set_header_nocache();
	print "<script type='text/javascript'>window.parent.ajax_url('/admin-side/templates/?template_id=".$template_id."&action=showblocks');window.location.href='/admin-side/templates/?template_id=".$template_id."&action=showpopupblocks';</script>";
	return ;
};

sub showPopupBlocks {
	my $self = shift;
	my $action = shift;
	my $q = $self->q();
	my $dbh = $self->db()->dbh();
	my @data = ();
	my $sth = undef;
	$self->opentemplate("admin-side/ng_popupblocks.tmpl") || return $self->showError();
	my $template_id = $q->param('template_id');
	if (is_valid_id($template_id)) {
		$sth = $dbh->prepare("select id,name from ng_blocks where id not in (select block_id from ng_template_blocks where template_id=?)") or die $DBI::errstr;
		$sth->execute($template_id) or die $DBI::errstr;
		while (my $row = $sth->fetchrow_hashref()) {
			push @data, $row;
		};
	};
	$self->tmpl()->param(
		blocks => \@data,
		template_id => $template_id
	);
	$sth->finish();
	$self->set_header_nocache();
	$self->print_template();
};

sub showBlocks {
	my $self = shift;
	my $action = shift;
	my $q = $self->q();
	my $dbh = $self->db()->dbh();
	my $template_id = $q->param('template_id');
	my @data = ();
	my $sth = undef;
	
	$self->opentemplate("admin-side/ng_templates_blocks.tmpl")  || return $self->showError();
	if (is_valid_id($template_id)) {
		$sth = $dbh->prepare('select b.name,b.id from ng_template_blocks tb, ng_blocks b where tb.template_id=? and tb.block_id=b.id') or die $DBI::errsrt;
		$sth->execute($template_id) or die $DBI::errstr;
		while (my $row = $sth->fetchrow_hashref()) {
			push @data,$row;
		};
		$sth->finish();
		$self->tmpl()->param(
			blocks => \@data,
			template_id => $template_id
		);
	};
	
	$self->set_header_nocache();
	$self->print_template();	
};

return 1;
END{};