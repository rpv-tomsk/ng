package NG::Module::NotifyEmails;
use strict;

=head
������ ������� ����������������� ������ �����-������� ������ ����������.
=cut

$NG::Module::NotifyEmails::VERSION=0.5;

use NG::Module 0.5;
use vars qw(@ISA);
@ISA = qw(NG::Module);

sub loadEmails {
    my ($class,$mObj,$subcode) = (shift,shift,shift);
    my $cms = $class->cms();
    return $cms->error("NG::Module::NotifyEmails->loadEmails(): missing moduleObj") unless $mObj && UNIVERSAL::can($mObj,"getModuleCode");
    return $cms->error("NG::Module::NotifyEmails->loadEmails(): missing subcode") unless $subcode;
    my $mCode = $mObj->getModuleCode() or return $cms->defError("loadEmails():","�� ���� ���������� ��� ������ ".(ref $mObj));
    my $mails = $cms->dbh->selectall_arrayref('select email from ng_emails where mcode =? and subcode = ?', {Slice=>{}},$mCode,$subcode) or return $cms->error($DBI::errstr);
    my @mails = map {$_->{email}} @$mails;
    return \@mails;
};

package NG::Module::NotifyEmails::Block;
use strict;
use NG::Module::List;
use vars qw(@ISA);

BEGIN {
    @ISA = qw(NG::Module::List);
}

sub config {
    my $self = shift;
    
    my $mObj = $self->getModuleObj();  ## NB: ��� �� NG::Module::NotifyEmails,
                                       ## � ��� ������, ������� �������� �������
    my $opts = $self->opts();

#opts:
#  - subcode - �������������� ������
    
    $self->{_table} = $self->opts('table') || 'ng_emails';
    my $subCode     = $self->opts('subcode');
    
    my @fields = ();
    push @fields, {FIELD=>'id',    TYPE=>'id',     NAME=>'���',IS_NOTNULL=>1};
    push @fields, {FIELD=>'email', TYPE=>'email',   NAME=>'E-Mail',IS_NOTNULL=>1,WIDTH=>"100%"};
    push @fields, {FIELD=>'mcode',  TYPE=>'filter', NAME=>'Filter',IS_NOTNULL=>1,WIDTH=>"100%",VALUE=>$mObj->getModuleCode()};
    #
    my @formfields = ();
    push @formfields, {FIELD=>'id'};
    push @formfields, {FIELD=>'email'};
    
    if ($subCode) {
        push @fields, {FIELD=>'subcode',  TYPE=>'filter', NAME=>'Filter',IS_NOTNULL=>1,WIDTH=>"100%",VALUE=>$subCode};
    }
    else {
        push @fields, {FIELD=>'subcode',  TYPE=>'select', NAME=>'���������',IS_NOTNULL=>1,WIDTH=>"100%",
            OPTIONS => {
                TABLE => 'ng_emails_subcodes',
                ORDER => 'id',
                ID_FIELD=>'subcode',
                WHERE => 'mcode = ?',
                PARAMS => [$mObj->getModuleCode()],
            },
        };
        $self->filter(
            NAME => '������',
            TYPE => 'select',
            LINKEDFIELD => 'subcode',
        );
        push @formfields, {FIELD=>'subcode',TYPE=>'hidden'};
    };
    $self->fields( @fields );
    $self->listfields([
        {FIELD=>'id'},
        {FIELD=>'email'},
    ]);
    $self->formfields( \@formfields );
    $self->{_onpage} = 20;
    $self->{_onlist} = 20;
    $self->order(
        {FIELD=>"email",DEFAULT=>0,ORDER_ASC=>"email",ORDER_DESC=>"email desc",DEFAULTBY=>'DESC'},
        {FIELD=>"id",DEFAULT=>0,ORDER_ASC=>"id",ORDER_DESC=>"id desc",DEFAULTBY=>'DESC'},
    );
#    $self->{_pageBlockMode}=1;
};

=comment

USAGE:

sub moduleTabs {
    return [
        ...
        {HEADER=>"���������� ����������� �",URL=>"/emailA/"},
        {HEADER=>"���������� ����������� �",URL=>"/emailB/"},
        ...
    ];
};

sub moduleBlocks {
    return [
        ...
        #��� ������ ������ � �������� �� �������
        {URL=>"/emailA/", BLOCK=>"NG::Module::NotifyEmails::Block",USE=>'NG::Module::NotifyEmails'},
        ...
        #������������ ������ (������) ������� 
        {URL=>"/emailB/", BLOCK=>"NG::Module::NotifyEmails::Block",USE=>'NG::Module::NotifyEmails',OPTS=>{subcode=>'ANOTIFY'}},
        ...
    ];
};

������������� ������ ������� (�������� ������):

    my $mails = $cms->getObject({CLASS=>"NG::Module::NotifyEmails",METHOD=>"loadEmails"},$self,'ANOTIFY') or return $cms->error();
    if (scalar @$mails) {
        ...
        #������� 1 - ����� ��������� To:
        $nmailer->send(@$mails) or return $cms->error();
        ...
        #������� 2 - ��������� ������ ����������� 
        my $To = ''; $To .= '<'.$_ . '>,' foreach @$mails; $To =~ s/,$//;
        $nmailer->add('To',$To);
        $nmailer->send();
        
        #������� 3 - ��������� ������� ��������� ������
    };
    
    
CREATE TABLE ng_emails (
  id SERIAL,
  email VARCHAR(50) NOT NULL,
  mcode VARCHAR(25) NOT NULL,
  subcode VARCHAR(25) NOT NULL,
  CONSTRAINT ng_emails_idx UNIQUE(email, mcode, subcode),
  CONSTRAINT ng_emails_pkey PRIMARY KEY(id)
) 
WITH (oids = false);

=cut

1;
