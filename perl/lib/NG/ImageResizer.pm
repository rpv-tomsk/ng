package NG::ImageResizer;
use strict;
use NG::PageModule;
our @ISA = qw(NG::PageModule);

use File::Path;
use Fcntl qw(:flock :DEFAULT);

our $config = undef;

sub getConfig {
    return $config;
}

sub getProcessorClass {
    return "NG::ImageProcessor";
};

sub run {
    my $self = shift;
    
    my $cms = $self->cms();
    my $q   = $cms->q();
    
    my $url = $q->url(-absolute=>1);
    my $baseUrl = $self->moduleParam('base');
    $baseUrl =~ s/^\///;
    
    my $cfg = $self->getConfig();
    
    NG::Exception->throw('NG.INTERNALERROR','No base configured') unless $baseUrl;
    NG::Exception->throw('NG.INTERNALERROR','Module not configured') unless $cfg;
    NG::Exception->throw('NG.INTERNALERROR','URL request does not match base') unless $url =~ s/^\/$baseUrl//;
    
    NG::Exception->throw('NG.INTERNALERROR','Unable to split reques URL') unless $url =~ s/^([^\/]+)\/([^\/]+)\///;
    my ($groupName,$sizeName) = ($1,$2);
    
    my $group = $cfg->{$groupName};
    my $size  = $group->{SIZES}->{$sizeName};
    
    NG::Exception->throw('NG.INTERNALERROR',"Group not found") unless $group;
    NG::Exception->throw('NG.INTERNALERROR',"Size not found")  unless $size;
    NG::Exception->throw('NG.INTERNALERROR',"Security error")  if  $url =~ /\.\./ || $url =~ /\<|\>/;
    NG::Exception->throw('NG.INTERNALERROR',"SOURCE not configured") unless $group->{SOURCE};
    NG::Exception->throw('NG.INTERNALERROR',"STEPS or METHOD not configured") unless $size->{METHOD} || $size->{STEPS};
    
    my $sourceFile = $cms->getDocRoot().$group->{SOURCE}.$url;
    my $targetFile   = $cms->getDocRoot().$baseUrl.$groupName.'/'.$sizeName.'/'.$url;
    
    return $cms->exit("Source image ".($NG::Application::DEBUG?$group->{SOURCE}.$url:'')." was not found.",{-status=>'404 Not found'}) unless -f $sourceFile;
    return $cms->exit('', {-location=>'/'.$baseUrl.$groupName.'/'.$sizeName.'/'.$url}) if -f $targetFile;
    
    #Файла нет, будем делать.
    
    my $targetDir = $targetFile;
    $targetDir=~s@[^\/]+$@@; #вырезаем текст после последнего слеша
    
    #проверим наличие целевого каталога, при необходимости создадим
    unless (-d $targetDir) {
        eval { mkpath($targetDir); };
        if ($@) {
            $@ =~ /(.*) at/s;
            NG::Exception->throw('NG.INTERNALERROR',"Unable to create directory: '$1'");
        };
    };
    
    #Сделаем блокировку.
    my $lock_fh;
    unless ( sysopen( $lock_fh, $targetFile.'.lock', O_WRONLY | O_CREAT) ) {
        NG::Exception->throw('NG.INTERNALERROR',"Unable to create lock file: '$!'");
    };
    flock($lock_fh, LOCK_EX) or NG::Exception->throw('NG.INTERNALERROR',"Cannot lock file: '$!'");
    
    if (-f $targetFile) {
        close($lock_fh);
        unlink($targetFile.'.lock');
        return $cms->exit('', {-location=>'/'.$baseUrl.$groupName.'/'.$sizeName.'/'.$url});
    };
    
    my $procClass = $self->getProcessorClass();
    NG::Exception->throw('NG.INTERNALERROR',"Unable to getProcessorClass") unless $procClass;
    
    my $pCtrl = $cms->getObject("NG::Controller",{
        PCLASS  => $procClass,
        STEPS   => $size->{STEPS} || [{METHOD=>$size->{METHOD},PARAMS=>$size->{PARAMS}}],
    });
    $pCtrl->process($sourceFile);
    if ($group->{DEBUG} || $size->{DEBUG}) {
        close($lock_fh);
        ($targetFile =~ /.*\.([^\.]*?)$/) or NG::Exception->throw('NG.INTERNALERROR', 'Unable to get image extension url');
        my $ext = lc($1);
        $ext = 'jpeg' if $ext eq 'jpg';
        my ($blob,$type) = $pCtrl->getResult(force=>$ext);
        binmode STDOUT;
        return $self->cms()->exit($blob,{-type=>"image/$type"});
    };
    $pCtrl->saveResult($targetFile);
    
    close($lock_fh);
    unlink($targetFile.'.lock');
    #return $cms->output("FILE $url GROUP $groupName SIZE = $sizeName CACHEDFILE $targetFile");
    return $cms->exit('', {-location=>'/'.$baseUrl.$groupName.'/'.$sizeName.'/'.$url});
};

1;
