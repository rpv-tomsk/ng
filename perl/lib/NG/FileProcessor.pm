package NG::FileProcessor;

use strict;
use File::Copy;
use NGService;

$NG::FileProcessor::VERSION=0.1;

sub new {
    my $class = shift;
    my $self = {};
    bless $self, $class;
    $self->init(@_);    
    $self; 
};

sub init {
    my $self = shift;
    $self->{_ctrl} = shift;
    $self->{_value} = undef;
    $self;
};
 

sub getCtrl {
    my $self = shift;
    return $self->{_ctrl};
};

sub setValue {
    my $self = shift;
    my $value = shift;
    
    $self->{_value} = $value;
    1;
};

sub copyFileExtension {
    my $self = shift;
    my $pCtrl = $self->getCtrl();
    
    my $fName = $pCtrl->param('field') or return $pCtrl->error("saveToField(): no field param configured");
    my $field = $pCtrl->getField($fName) or return $pCtrl->error();
    
    my $ext = get_file_extension($pCtrl->getCurrentField()->{TMP_FILENAME});
    $field->setValue($ext);
    return 1;
};

sub copyFileSize {
    my $self = shift;
    my $pCtrl = $self->getCtrl();
        
    my $fName = $pCtrl->param('field') or return $pCtrl->error("saveToField(): no field param configured");
    my $field = $pCtrl->getField($fName) or return $pCtrl->error();        
        
    my $file = $self->{_value};
    my $size = 0;
    $size = -s $file if $file;
    $field->setValue($size);
    return 1;
};


sub copyFileSizeText {
    my $self = shift;
    my $pCtrl = $self->getCtrl();
        
    my $fName = $pCtrl->param('field') or return $pCtrl->error("saveToField(): no field param configured");
    my $field = $pCtrl->getField($fName) or return $pCtrl->error();        
        
    my $file = $self->{_value};
    my $size = 0;
    $size = -s $file if $file;
    $field->setValue(get_size_text($size));
    return 1;
};

sub copyFileName {
    my $self = shift;
    my $pCtrl = $self->getCtrl();
        
    my $fName = $pCtrl->param('field') or return $pCtrl->error("saveToField(): no field param configured");
    my $field = $pCtrl->getField($fName) or return $pCtrl->error();        
        
    my $filename = $pCtrl->getCurrentField()->{TMP_FILENAME} || "";
    $field->setValue($filename);
    return 1;
};

sub afterProcess {
    my $self = shift;
    my $dest = shift;

    my $pCtrl = $self->getCtrl();
    if ($self->{_value} ne $dest) {
        move($self->{_value},$dest) or return $pCtrl->error("Error on move file in afterProcess: ".$!);
    };
    my $mask = umask();
    $mask = 0777 &~ $mask;
    chmod $mask, $dest;
    return 1;
};

sub getResult {
    die "getResult() on FileProcessor can`t be used";
};

1;
