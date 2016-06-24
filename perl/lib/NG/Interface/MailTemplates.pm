package NG::Interface::MailTemplates;
use strict;

use NG::Interface;
our @ISA = qw/NG::Interface/;

$Carp::Internal{'NG::Interface::MailTemplates'}++;

sub validate_mailTemplates {
    my ($iface,$cfg) = (shift,shift);
    
    NG::Exception->throw('NG.INTERNALERROR',"mailTemplates(): incorrect value returned from ".$iface->_package()) unless $cfg && ref $cfg eq "HASH";
    $cfg;
};

sub validate_mailLabels {
    my ($iface,$labels) = (shift,shift);
    NG::Exception->throw('NG.INTERNALERROR',"mailLabels(): incorrect value returned from ".$iface->_package()) unless $labels && ref $labels eq "HASH";
    $labels;
};

sub getTemplateMetadata {
    my ($iface,$code) = (shift,shift);
    
    NG::Exception->throw('NG.INTERNALERROR','Template code not specified.') unless $code;
    
    my $cfg = $iface->safe('mailTemplates');
    NG::Exception->throw('NG.INTERNALERROR',$iface->_package()." has no template $code") unless exists $cfg->{$code};
    $cfg->{$code};
};


1;
