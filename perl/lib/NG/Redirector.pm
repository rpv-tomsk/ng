package NG::Redirector;
use strict;
use NSecure;

use vars qw(@ISA);
$NG::Redirector::VERSION=0.4;

sub AdminMode {
    use NG::Module::Record 0.4;
    @ISA = qw(NG::Module::Record);
};

sub FaceMode {
	use NG::Face;
	@ISA = qw(NG::Face);
};

sub config  {
    my $self = shift;
    $self->{_table} = "ng_redirector";
    
    $self->fields(
        {FIELD=>'page_id',  TYPE=>'pageId'},
        {FIELD=>'url', TYPE=>'text', NAME=>'URL для перенаправления',IS_NOTNULL=>1},
    );
};

sub Redirect {
	my $self = shift;
	my $pageId = $self->getPageId();
	my $sth = $self->db()->dbh()->prepare("select url from ng_redirector where page_id=?") or return $self->error($DBI::errstr);
	$sth->execute($pageId) or return $self->error($DBI::errstr);
	my ($url) = $sth->fetchrow();
	$sth->finish();
	if (!is_empty($url)) {
		return $self->redirect_url($url);
	};
	return $self->error("No url");
};

sub CheckData {
	my $self = shift;
	my $form = shift;
	my $action = shift;
	my $urlField = $form->_getfieldhash("url");
	if(!is_valid_link($urlField->{'VALUE'})) {
		$urlField->setError("Некорректный url");
	};
	return NG::Block::M_OK;
};

return 1;
