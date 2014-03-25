package NG::Siteblocks;
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
    $self->tablename('ng_blocks');
    $self->addfields({TYPE=>'id', NAME=>'Код',FIELD=>'id',IS_NOTNULL=>1});
    $self->addfields({TYPE=>'text', NAME=>'Название блока',FIELD=>'name',IS_NOTNULL=>1,WIDTH=>"30%"});
    $self->addfields({TYPE=>'text', NAME=>'Имя переменной',FIELD=>'var_name',IS_NOTNULL=>1,WIDTH=>"20%"});
    $self->addfields({TYPE=>'text', NAME=>'Обработчик',FIELD=>'process_func',IS_NOTNULL=>0,WIDTH=>"40%"});
    $self->addfields({TYPE=>'text', NAME=>'Файл шаблона',FIELD=>'template',IS_NOTNULL=>0,WIDTH=>"30%"});
    $self->addfields({TYPE=>'checkbox', NAME=>'Активный',FIELD=>'is_active',CB_VALUE=>1});
    $self->addfields({TYPE=>'hidden', NAME=>'group_id',FIELD=>'group_id',IS_NOTNULL=>0,WIDTH=>"20%"});
    $self->list('name','template','process_func','var_name');
    $self->form('id','name','template','process_func','var_name','is_active','group_id');
    $self->{_onpage} = 20;
    $self->add_links("Альтернативы блока","/admin-side/blocks/?group_id={id}&action=showotherblocks",1);
    $self->register_ajaxaction("showotherblocks","showOtherBlocks");
    $self->register_ajaxaction("addotherblocks","addOtherBlocks");    
    $self->register_ajaxaction("updateotherblocks","updateOtherBlocks");
    $self->register_ajaxaction("deleteotherblocks","deleteOtherBlocks");
    $self->set_condition("group_id=id");
}

sub PrepareData {
    my $self = shift;
    my $form = shift;
    my $action = shift;
    $self->SUPER::PrepareData($form,$action);
    if ($action eq "insert" or $action eq "ajaxinsert") {
    	$self->q()->param('group_id',$self->q()->param('id'));
    };
};

sub showOtherBlocks {
	my $self = shift;
	my $action = shift;
	my $q = $self->q();
	my $dbh = $self->db()->dbh();
	my $group_id = $q->param('group_id');
	$self->opentemplate("admin-side/ng_blocks.tmpl") || return $self->showError();
	my $template = $self->tmpl();
	my $sth = $dbh->prepare("select id,name,process_func,template,var_name,is_active from ng_blocks where group_id=? and id<>group_id order by id") or die $DBI::errstr;
	$sth->execute($group_id);
	my @result = ();
	while (my $row = $sth->fetchrow_hashref()) {
		push @result, $row;
	};
	$sth->finish();
	
	$sth = $dbh->prepare("select var_name from ng_blocks where id=?") or die $DBI::errstr;
	$sth->execute($group_id) or die $DBI::errstr;
	my ($var_name) = $sth->fetchrow();
	$sth->finish();
	$template->param(
		GROUP_ID => $group_id,
		BLOCKS => \@result,
		VAR_NAME => $var_name
	);
    $self->set_header_nocache();
    $self->print_template();
};

sub addOtherBlocks{
	my $self = shift;
	my $action = shift;
	my $q = $self->q();
	my $dbh = $self->db()->dbh();
	
	my $group_id = $q->param('group_id');
	my $process_func = $q->param('process_func');
	my $var_name = $q->param('var_name');
	my $name = $q->param('name');
	my $is_active = $q->param('is_active')?1:0;
	
	if (!is_empty($process_func) && !is_empty($name) && is_valid_id($group_id)) {
		$dbh->do("insert into ng_blocks (process_func,var_name,group_id,is_active,name) values(?,?,?,?,?)",undef,$process_func,$var_name,$group_id,$is_active,$name) or die $DBI::errstr;
	};
	$self->set_header_nocache();
	print "<script type='text/javascript'>parent.ajax_url('/admin-side/blocks/?group_id=".$group_id."&action=showotherblocks','formb".$group_id."');</script>";
};

sub updateOtherBlocks {
	my $self = shift;
	my $action = shift;
	my $q = $self->q();
	my $dbh = $self->db()->dbh();
	my @params = $q->param();
	my $upd_sth = $dbh->prepare("update ng_blocks set process_func=?,is_active=?,name=? where id=?") or die $DBI::errstr;
	my $gid_sth = $dbh->prepare("select group_id from ng_blocks where id=?") or die $DBI::errstr;
	my $gid = undef;
	foreach my $param (@params) {
        if ($param =~ /process_func_([1-9]\d*)/) {
            my $id = $1;
            if (!$gid) {
                $gid_sth->execute($id);
                ($gid) = $gid_sth->fetchrow();
            };
            my $process_func = $q->param('process_func_'.$id);
            my $name = $q->param('name_'.$id);
            my $is_active = $q->param('is_active_'.$id)?1:0;
            $upd_sth->execute($process_func,$is_active,$name,$id) or die $DBI::errstr;
        };
	};
	$upd_sth->finish();
	$gid_sth->finish();
	$self->set_header_nocache();
	print "<script type='text/javascript'>parent.ajax_url('/admin-side/blocks/?group_id=".$gid."&action=showotherblocks','formb".$gid."');</script>";
};

sub deleteOtherBlocks {
	my $self = shift;
	my $q = $self->q();
	my $id = $q->param('id');
	my $dbh = $self->db()->dbh();
	my $gid = undef;
	if (is_valid_id($id)) {
		my $sth = $dbh->prepare("select group_id from ng_blocks where id=?") or die $DBI::errstr;
		$sth->execute($id) or die $DBI::errstr;
		($gid) = $sth->fetchrow();
		$sth->finish();
		$dbh->do("delete from ng_blocks where id=?",undef,$id) or die $DBI::errstr;
	};
	$self->set_header_nocache();
	print "<script type='text/javascript'>parent.ajax_url('/admin-side/blocks/?group_id=".$gid."&action=showotherblocks','formb".$gid."');</script>";
};

return 1;
END{};