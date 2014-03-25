package Site::PageModule;
use strict;
use NG::PageModule;
our @ISA = qw(NG::PageModule NGPlugins::Instances);


sub DESTROY {
    my $self = shift;
    #print "Site::PageModule destroyed\n";
    NGPlugins::Instances::DESTROY($self);
    $Site::PageModule::CHECKDESTROY++;
};

$NGPlugins::DESTROYverified{ (__PACKAGE__) } = 1;
$Site::PageModule::CHECKDESTROY = 0;

1;
