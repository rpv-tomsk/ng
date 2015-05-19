package NG::RtfView;

use strict;

use NG::Application;
use NGService;
use NSecure;
use Data::Dumper;
use NG::Rtf;
use NG::Form;
use NHtml;
use vars qw(@ISA);
@ISA = qw(NG::Application);


sub init {
	my $self = shift;
	$self->SUPER::init(@_);
	$self->{_table} = "variables";
	$self->{_variable_name} = "";
	$self->register_action("","showComponent");
	$self->register_action("updatevariable","updateVariable");
	$self->register_action("saveimage","saveImage");
};

sub config {
};

sub getVariable {
	my $self = shift;
	my $sth = $self->db()->dbh()->prepare("select value from ".$self->table()." where code=?") or die $DBI::errstr;
	$sth->execute($self->var());
	my ($variable) = $sth->fetchrow();
	$sth->finish();
	return $variable;
};

sub setVariable {
	my $self = shift;
	my $value = $self->q()->param('value');
	my $dbh = $self->db()->dbh();
	
	my $sth = $dbh->prepare("select count(*) from ".$self->table()." where code=?") or die $DBI::errstr;
	$sth->execute($self->var());
	my ($count) = $sth->fetchrow();
	$sth->finish();
	
	if ($count > 0) {
		$dbh->do("update ".$self->table()." set value=? where code=?",undef,$value,$self->var()) or die $DBI::errstr;
	} else {
		$dbh->do("insert into ".$self->table()."(code,value) values(?,?)",undef,$self->var(),$value) or die $DBI::errstr;
	};
};

sub table {
	my $self = shift;
	my $table = shift;
	if ($table) {
		$self->{_table} = $table;
	};
	return $self->{_table};
};

sub var {
	my $self = shift;
	my $var = shift;
	if ($var) {
		$self->{_variable_name} = $var;
	};
	return $self->{_variable_name};
};

sub saveImage {
	my $self = shift;
	my $q = $self->q();
	my $uploadfile=Rtf_get_filename($q);
	if(!defined $uploadfile) {
		Rtf_send_alert(Rtf_get_error());
		exit;
	};
	my $file_name="image".int(rand(1000)).time(); #.".".$ext;
	$file_name=Rtf_save_image($self->{_siteroot}."/htdocs/images/",$file_name,$q);
	if(!defined $file_name) {
		Rtf_send_alert("Ошибка загрузки файла");
		exit;
	};
	Rtf_send_filename("/images/".$file_name);
};

sub showComponent {
	my $self = shift;
	my $form_html = $self->getFormHTML();
	$self->opentemplate("admin-side/admincomponent.tmpl") || return $self->showError();
	$self->tmpl()->param(
		form => $form_html
	);
	
	$self->AdminMenuTree();
	$self->set_header_nocache();
	$self->print_template();
};

sub updateVariable {
	my $self = shift;
	$self->setVariable();
	$self->redirect_to_referer_or("");
};

sub getFormHTML {
	my $self = shift;
	
	my $form = NG::Form->new(
		FORM_ACTION => "updatevariable",
		NEW => 1,
	);
	$form->addfields(TYPE=>"rtf",NAME=>"Текст",FIELD=>"value",FILE_HANDLER=>$self->q()->url(-absolute=>1));
	$form->param("id",0);
	$form->param("value",$self->getVariable());
	$self->opentemplate("admin-side/common/universalform.tmpl") || return $self->showError();
	return $form->print_to_template($self->tmpl());
};

sub run {
    my $self = shift;
       
    if ($self->{_table} eq "") {
    	$self->set_header_nocache();
        print "NG::RtfView: tablename not specified";
        return;
    }
    if ($self->{_variable_name} eq "") {
    	$self->set_header_nocache();
        print "NG::RtfView: Variable identifier  not specified";
        return;
    }

    return $self->run_actions();
};


return 1;
END{};