package NG::ImageProcessor;

use strict;
use File::Copy;
use Image::Magick;
use NG::FileProcessor;

use vars qw(@ISA);
@ISA = qw(NG::FileProcessor); 

sub init {
    my $self = shift;
    $self->SUPER::init(@_);
    $self->{_iobjs} = {};   #��� �������� I::M ����������� �� ���� id.
    $self->{_ifiles} = {};  #��� ������, ��������������� ������� I::M, ���� ����.
    $self->{_origfname} = undef; #������������ ��� �����
    $self;
};

sub composite {
    my $self = shift;
    my $pCtrl = $self->getCtrl();
    my $iObj = $self->_getIObj(1) or return $pCtrl->error();
    my $image = $pCtrl->paramOrOption('image','IMAGE');
    my $position = $pCtrl->paramOrOption('position','POSITION');
    return $pCtrl->error('Can\'t find file '.$image) unless (-e $image);
    my $file = Image::Magick->new();
    $file->Read($image);
    
    $iObj->Composite (
        'image'=>$file,
        'gravity'=>$position
    );
    $self->_resetIFile();
    return 1;
};

sub crop_height {
    my $self = shift;
    my $pCtrl = $self->getCtrl();
    my $iObj = $self->_getIObj(1) or return $pCtrl->error();
    my $height = $pCtrl->paramOrOption("height","HEIGHT");
    my ($iwidth,$iheight) = $iObj->Get('columns','rows');
    if ($iheight > $height) {
        my $e = $iObj->Crop(geometry=>$iwidth.'x'.$height.'+0+0');
        return $pCtrl->error("������ ��������� ����������� : $e") if $e;
        $self->_resetIFile();
    };
    return 1;
};

sub crop_width_center {
    my $self = shift;
    my $pCtrl = $self->getCtrl();
    my $iObj = $self->_getIObj(1) or return $pCtrl->error();
    my $width = $pCtrl->paramOrOption("width","WIDTH");
    my ($iwidth,$iheight) = $iObj->Get('columns','rows');
    if ($iwidth > $width) {
        my $delta_width = int(($iwidth-$width)/2);
        my $e = $iObj->Crop(geometry=>$width.'x'.$iheight.'+'.$delta_width.'+0');
        return $pCtrl->error("������ ��������� ����������� : $e") if $e;
        $self->_resetIFile();
    };
    return 1;
};

sub crop_to_center {
    my $self = shift;
    my $pCtrl = $self->getCtrl();
    my $iObj = $self->_getIObj(1) or return $pCtrl->error();
    my $width = $pCtrl->paramOrOption("width","WIDTH");
    my $height = $pCtrl->paramOrOption("height","HEIGHT");
    my ($iwidth,$iheight) = $iObj->Get('columns','rows');
    my $current_height = $iheight;
    if ($iheight>$height) {
        my $delta = int(($iheight-$height)/2);
        my $e = $iObj->Crop(geometry=>$iwidth.'x'.$height.'+0'.'+'.$delta);
        return $pCtrl->error("������ ��������� ����������� : $e") if $e;
        $current_height = $height;
        $self->_resetIFile();
    };
    if ($iwidth>$width) {
        my $delta = int(($iwidth-$width)/2);
        my $e = $iObj->Crop(geometry=>$width.'x'.$current_height.'+'.$delta.'+0');
        return $pCtrl->error("������ ��������� ����������� : $e") if $e;
        $self->_resetIFile();
    };  
    return 1;  
};

sub setValue {
    my $self = shift;
    my $value = shift;

    my $pCtrl = $self->getCtrl();
    my $f = $pCtrl->getCurrentField();
    
    $self->{_origfname} = $f->{TMP_FILENAME} if $f;
    
    $value =~ /([^\\\/]+)$/;
    $self->{_origfname} ||= $1;

    $self->SUPER::setValue($value) or return $pCtrl->error();

    return $pCtrl->error("SOURCE not defined") unless $value;
    my $iObj = $self->{_iobjs}->{main} = Image::Magick->new;
    my $err = $iObj->read($value);
    return $pCtrl->error("������ ������ �����������: $err") if $err;
    $self->{_ifiles}->{main} = $value;
    1;
};

#sub _getCurrentId {
#    my $self = shift;
#    my $pCtrl = $self->getCtrl();
#    
#    return $pCtrl->param('id') || 'main';
#};

sub _resetIFile {
    my $self = shift;
    my $pCtrl = $self->getCtrl();
    
    my $toid = $pCtrl->param('toid') || $pCtrl->param('id') || 'main';
    delete $self->{_ifiles}->{$toid};
}

sub _getIObj {
    my $self = shift;
    my $doCopy = shift;
    
    my $pCtrl = $self->getCtrl();
    
    my $id = $pCtrl->param('id') || 'main';
    
    return $pCtrl->error('����������� � id '.$id.' �� ������������') unless exists $self->{_iobjs}->{$id};
    return $self->{_iobjs}->{$id} unless ($doCopy);

    my $toid = $pCtrl->param('toid') || $id;
    if ($id ne $toid) {
        $self->{_iobjs}->{$toid} = $self->{_iobjs}->{$id}->Clone();
        return $pCtrl->error("������ ������������ ������� �����������") unless $self->{_iobjs}->{$toid};
        delete $self->{_ifiles}->{$toid};
        $self->{_ifiles}->{$toid} = $self->{_ifiles}->{$id} if $self->{_ifiles}->{$id};
    };
    return $self->{_iobjs}->{$toid};
};

sub _setIObj {
    my $self = shift;
    my $iObj = shift;
    
    my $pCtrl = $self->getCtrl();
    my $id = $pCtrl->param('id') || 'main';
    my $toid = $pCtrl->param('toid') || $id;
    
    $self->{_iobjs}->{$toid} = $iObj;
    delete $self->{_ifiles}->{$toid};
};

sub towidth {
    my $self = shift;
    my $pCtrl = $self->getCtrl();
    
    my $width = $pCtrl->paramOrOption('width','WIDTH');
    return $pCtrl->error("����������� ����� WIDTH ��� ���������� ������ towidth") unless defined $width;
    
    my $iObj = $self->_getIObj(1) or return $pCtrl->error();
    
    my ($iwidth,$iheight) = $iObj->Get('base-columns','base-rows');
    my $koef = ($iwidth/$width);
    if ($koef>1) {
        $self->_resetIFile();
        my $e = $iObj->Resize(width=>int($iwidth/$koef),height=>int($iheight/$koef));
        return $pCtrl->error("������ ��������� �����������: $e") if $e;
    };
    1;
};

sub toheight {
    my $self = shift;
    my $pCtrl = $self->getCtrl();

    my $height = $pCtrl->paramOrOption('height','HEIGHT');
    return $pCtrl->error("����������� ����� HEIGHT ��� ���������� ������ toheight") unless defined $height;
    
    my $iObj = $self->_getIObj(1) or return $pCtrl->error();
    
    my ($iwidth,$iheight) = $iObj->Get('base-columns','base-rows');
    my $koef = ($iheight/$height);
    if ($koef>1) {
        $self->_resetIFile();
        my $err=$iObj->Resize(width=>int($iwidth/$koef),height=>int($iheight/$koef));
        return $pCtrl->error("������ ��������� �����������: $err") if $err;
    };
    1;
};

sub tomaximal {
    my $self = shift;
    my $pCtrl = $self->getCtrl();

    my $width = $pCtrl->paramOrOption('width','WIDTH');
    return $pCtrl->error("����������� ����� WIDTH ��� ���������� ������ tomaximal") unless defined $width;
    my $height = $pCtrl->paramOrOption('height','HEIGHT');
    return $pCtrl->error("����������� ����� HEIGHT ��� ���������� ������ tomaximal") unless defined $height;
    
    my $iObj = $self->_getIObj(1) or return $pCtrl->error();

    my ($iwidth,$iheight) = $iObj->Get('base-columns','base-rows');
    my $koef = ($iwidth/$width)>($iheight/$height) ? $iwidth/$width : $iheight/$height;
    if ($koef>1) {
        $self->_resetIFile();
        my $err=$iObj->Resize(width=>int($iwidth/$koef),height=>int($iheight/$koef));
        return $pCtrl->error("������ ��������� �����������: $err") if $err;
    };
    1;
};

sub tominimal { #������� � ����� �� ����������� ������� � ����������� ���������. �.�. ������ ���� ������ crop �� ������������ �������.
    my $self = shift;
    my $pCtrl = $self->getCtrl();
    
    my $width = $pCtrl->paramOrOption('width','WIDTH');
    return $pCtrl->error("����������� ����� WIDTH ��� ���������� ������ tominimal") unless defined $width;
    my $height = $pCtrl->paramOrOption('height','HEIGHT');
    return $pCtrl->error("����������� ����� HEIGHT ��� ���������� ������ tominimal") unless defined $height;

    my $iObj = $self->_getIObj(1) or return $pCtrl->error();
    
    my ($iwidth,$iheight) = $iObj->Get('base-columns','base-rows');
    my $koef = ($iwidth/$width)<($iheight/$height) ? $iwidth/$width : $iheight/$height;
    if ($koef>1) {
        $self->_resetIFile();
        my $err=$iObj->Resize(width=>int($iwidth/$koef),height=>int($iheight/$koef));
        return $pCtrl->error("������ ��������� �����������: $err") if $err;
    };
    1;
};

sub torectangle {
    my $self = shift;
    my $pCtrl = $self->getCtrl();

    my $width = $pCtrl->paramOrOption('width','WIDTH');
    return $pCtrl->error("����������� ����� WIDTH ��� ���������� ������ torectangle") unless defined $width;
    my $height = $pCtrl->paramOrOption('height','HEIGHT');
    return $pCtrl->error("����������� ����� HEIGHT ��� ���������� ������ torectangle") unless defined $height;

    my $iObj = $self->_getIObj(1) or return $pCtrl->error();

    my ($iwidth,$iheight) = $iObj->Get('base-columns','base-rows');
    return 1 if ($iwidth == $width) && ($iheight == $height);
    my $koef = undef;
    if ($pCtrl->paramOrOption('crop','CROP')) {
        $koef = ($iwidth/$width)<($iheight/$height) ? $iwidth/$width : $iheight/$height;
    }
    else {
        $koef = ($iwidth/$width)>($iheight/$height) ? $iwidth/$width : $iheight/$height;
    };
    my $err=$iObj->Resize(width=>int($iwidth/$koef)+1,height=>int($iheight/$koef)+1);
    return  "������ ��������� �����������: $err" if $err;

    ## Blank image
    my $pp = Image::Magick->new;
    $pp->Set(size=>$width.'x'.$height);
    my $bg = $pCtrl->paramOrOption('background','BACKGROUND');
    $bg ||= 'xc:white';
    $pp->ReadImage($bg);
    ## Compose
#TODO: add param for gravity
    $pp->Composite(image=>$iObj,gravity=>'Center');
    
    $self->_setIObj($pp);
    $iObj = undef;
    1;
};

sub savesize {
    my $self = shift;
    my $pCtrl = $self->getCtrl();
    my $iObj = $self->_getIObj(0) or return $pCtrl->error();
    my $field = $pCtrl->paramOrOption('field','FIELD');
    return $pCtrl->error("����������� ����� FIELD ��� ���������� ������ savesize") unless defined $field;
    my $mask = $pCtrl->paramOrOption('mask','MASK') || "{w}x{h}";
    my ($iwidth,$iheight) = $iObj->Get('columns','rows');
    $mask =~ s/\{w\}/$iwidth/gi;
    $mask =~ s/\{h\}/$iheight/gi;
    my $field = $pCtrl->getField($field) or return $pCtrl->error("no field $field");
    $field->setValue($mask);
    return 1;
}

sub afterProcess {
    my $self = shift;
    my $dest = shift;

    my $pCtrl = $self->getCtrl();
    if ($self->{_ifiles}->{main}) {
        copy($self->{_ifiles}->{main},$dest) or return $self->setError("������ ����������� �����������: ".$!);
    }
    else {
        my $iObj = $self->{_iobjs}->{main} or return $pCtrl->error("No IOBJ");
        my $err = $iObj->Write($dest);
        return $pCtrl->error("������ ������ ����������� $dest: $err") if $err;
    };
    my $mask = umask();
    $mask = 0777 &~ $mask;
    chmod $mask, $dest;
    return 1;
};


=head

sub ... {
    ...
    if ($field && $field->isFileField()) {
        $pObj->AFTER($field->dbValue());
    }
    else {
        my $v = $pObj->AFTER();
        
        if ($field) {
            $field->setValue($v);
        };
        
    };
    ...
};
=cut


sub saveToField {
    my $self = shift;
    my $pCtrl = $self->getCtrl();
    
    my $fName = $pCtrl->param('field') or return $pCtrl->error("saveToField(): no field param configured");

    my $field = $pCtrl->getField($fName) or return $pCtrl->error("���� $fName �� �������");


    my $dest = $field->parent()->getDocRoot() or return $pCtrl->error("Can`t getDocRoot()");
    $dest.= $field->{UPLOADDIR} or return $pCtrl->error("Field $fName has no UPLOADDIR");
    
    $field->{TMP_FILENAME} = $self->{_origfname};
    $field->genNewFileName() or return $pCtrl->error("Field $fName getNewFilename() metod returns no data");
    my $newDBV = $field->dbValue() or return $pCtrl->error("Field $fName dbValue() metod returns no data");
    $dest .= $newDBV;
    
    
    my $id = $pCtrl->param('id') || 'main';
    if ($self->{_ifiles}->{$id}) {
        copy($self->{_ifiles}->{$id},$dest) or return $self->setError("������ ����������� �����������: ".$!);
    }
    else {
        my $iObj = $self->_getIObj(0) or return $pCtrl->error();
        my $err = $iObj->Write($dest);
        return $pCtrl->error("������ ������ ����������� $dest: $err") if $err;
    };
    
    $field->setDBValue($newDBV);
    
    my $mask = umask();
    $mask = 0777 &~ $mask;
    chmod $mask, $dest;
    
    1;
};

=comment
    step2       = saveToFile         #��������� �������� � ��������������� small � ����� ����
    step2_id    = "small"
    step2_dir   = "/some/dir"        #���� ���������� �� ��������� � ����������� UPLOADDIR ��������� ����
    step2_mask  = "{f}_small.{e}"    #�����... ����� ��������� � ��� ��� ���� � NG::Field
=cut

sub saveToFile {
    my $self = shift;
    my $pCtrl = $self->getCtrl();
    my $cms = $self->cms();
    my $dir = $pCtrl->param("dir");
    my $mask = $pCtrl->param("mask");
    
    if ($dir =~ /\{siteroot\}/) {
        $dir =~ s/\{siteroot\}/$cms->getSiteRoot()/;
    };

    if ($dir =~ /\{docroot\}/) {
        $dir =~ s/\{docroot\}/$cms->getDocRoot()/;
    };


    if ($mask) {
        my $field = $pCtrl->getCurrentField();
        
        my $fieldName = $field->{FIELD};
        $mask =~ s@\{f\}@$fieldName@;
        
        my $key = $field->parent()->getComposedKeyValue();
        $mask =~ s@\{k\}@$key@;
        
        my $rand = int(rand(9999));
        $mask =~ s@\{r\}@$rand@;
        
#         
#         $ext = ".".$ext if $ext;
#         $mask =~ s@\{e\}@$ext@;    
    }
    else {
        $mask = "";
    };

    my $dest = $dir.$mask;
    
    my $id = $pCtrl->param('id') || 'main';
    if ($self->{_ifiles}->{$id}) {
        copy($self->{_ifiles}->{$id},$dest) or return $self->setError("������ ����������� �����������: ".$!);
    }
    else {
        my $iObj = $self->_getIObj(0) or return $pCtrl->error();
        my $err = $iObj->Write($dest);
        return $pCtrl->error("������ ������ ����������� $dest: $err") if $err;
    };
    
    my $mask = umask();
    $mask = 0777 &~ $mask;
    chmod $mask, $dest;
    
    1;
};
    
=head

    my $options = $self->{OPTIONS};
    
    my $method = $options->{METHOD};
    my $e = "";
    
    elsif ($method){
        return $self->setError("����������� ����� $method � ������ ��������� ����");
    }
    else {
        return $self->ProcessFile();
    };
    

    return 1;


sub ProcessFile {
    my $self = shift;
    
    my $mask = umask();
    $mask = 0777 &~ $mask;
    my $dirfile = $self->parent()->getDocRoot().$self->{UPLOADDIR}.$self->dbValue();
    #TODO: ��, � ��� ����� ���� $self->value() ������ ���� � ��������������� �����, ������ $dirfile ?
    if ($self->value() ne $dirfile) {
        copy($self->value(),$dirfile) or return $self->setError("������ ����������� �����: ".$!);
    };
    chmod $mask, $dirfile;
    return 1;
    };
=cut

package NG::ImageProcessor::ImageMagickImage;
use strict;
use Carp;

my $RO_METHODS = {'Get'=>1};

sub new {
    my $class = shift;
    
    my $self = {};
    bless $self,$class;
    
    $self->{_iobj} = Image::Magick->new;  #������
    $self->{_ifile} = undef;              #���� �� �����, �����. �������, ���� ����. ��������� ��� ��������� �������.
    
    return $self;
}

sub read {
    my $self = shift;
    my $file = shift;
    
    my $e = $self->{_iobj}->read($file);
    return $e if $e;
    $self->{_ifile} = $file;
    0;
};

sub Write {
    my $self = shift;
    my $dest = shift;
    
    if ($self->{_ifile}) {
        copy($self->{_ifile},$dest) or return ("������ ����������� �����������: ".$!);
    }
    else {
        my $e = $self->{_iobj}->Write($dest);
        return $e if $e;
    };
    my $mask = umask();
    $mask = 0777 &~ $mask;
    chmod $mask, $dest;
    0;
};

our $AUTOLOAD;
sub AUTOLOAD {
    my $self=shift;
    my $pkg = ref $self;
    $AUTOLOAD =~ s/$pkg\:\://;
    
    $self->{_ifile} = undef unless $RO_METHODS->{$AUTOLOAD};
    
    return $self->{_iobj}->$AUTOLOAD(@_) if $self->{_iobj}->can($AUTOLOAD);
    croak('Can\'t locate object method "'.$AUTOLOAD.'" via Image::Magick');
};


1;
