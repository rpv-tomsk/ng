package NG::SiteModule::FileTimestamp;
use strict;
use NG::Module;
our @ISA = qw(NG::Module);

sub getBlockContent {
    my ($self,$action,$keys,$params) = (shift,shift,shift,shift);
    
    my $cms = $self->cms();
    
    if ($action eq "FILETIMESTAMP") { #Plugin
        my $fName = $self->pluginParam('file') or return $cms->error('Plugin FILETIMESTAMP has no \'file\' parameter');
        
        my @v = stat($cms->getSiteRoot().$fName);
        return $cms->error("Plugin FILETIMESTAMP: file $fName was not found") unless scalar @v;
        
        return $cms->output($v[9]);
    };
    
    my $fName = $self->confParam('File_'.$action) or return $cms->error('Module NG::SiteModule::FileTimestamp : missing value for config file parameter MODULE_'.$self->getModuleCode().'.File_'.$action);

    my @v = stat($cms->getSiteRoot().$fName);
    return $cms->error("Module NG::SiteModule::FileTimestamp : file $fName was not found (Configfile parameter MODULE_".$self->getModuleCode().".File_$action)") unless scalar @v;
    
    return $cms->output($v[9]);
};

1;
