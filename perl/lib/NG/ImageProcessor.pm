package NG::ImageProcessor;

use strict;
use Image::Magick;
use NG::FileProcessor;
use File::Copy qw();

use vars qw(@ISA);
@ISA = qw(NG::FileProcessor);

# You can set compression quality:
# $NG::ImageProcessor::config::quality = {jpg=>90, png=>7};

sub init {
    my $self = shift;
    $self->SUPER::init(@_);
    $self->{_iobjs} = {};   #Хеш объектов NG::ImageProcessor::ImageMagickImage изображений по коду id.
    $self->{_origfname} = undef; #Оригинальное имя файла
    $self;
};

#  Usage:
#  {METHOD => "setquality",   PARAMS => {jpg=>90, png=>7 }}
sub setquality {
    my $self = shift;
    my $pCtrl = $self->getCtrl();
    my $iObj  = $self->_getIObj(0) or return $pCtrl->error();
    
    $iObj->_setQuality($pCtrl->param());
    return 1;
};

# Usage:
# {METHOD => "im_method",    PARAMS => {im_method=>'OilPaint', radius=>.02}},
sub im_method {
    my $self = shift;
    my $pCtrl = $self->getCtrl();
    my $iObj  = $self->_getIObj(1) or return $pCtrl->error();
    
    my $_params = $pCtrl->param();
    
    my $params = {};
    %{$params} = %{$_params};
    
    delete $params->{id};
    delete $params->{todid};
    my $im_method = delete $params->{im_method} or NG::Exception->throw('NG.INTERNALERROR', "im_method(): I::M method not specified in 'im_method' parameter.");;
    
    #$iObj->can($im_method) or NG::Exception->throw('NG.INTERNALERROR', "im_method(): ImageMagick has no $im_method method.");
    my $e = $iObj->$im_method(%$params);
    NG::Exception->throw('NG.INTERNALERROR', "im_method(): Error $e running $im_method method.") if $e;
    
    1;
};

=comment
sub composite {
    my $self = shift;
    my $pCtrl = $self->getCtrl();
    my $iObj = $self->_getIObj(1) or return $pCtrl->error();
    my $image = $pCtrl->param('image');
    my $position = $pCtrl->param('position');
    return $pCtrl->error('Can\'t find file '.$image) unless (-e $image);
    my $file = Image::Magick->new();
    $file->Read($image);
    
    $iObj->Composite (
        'image'=>$file,
        'gravity'=>$position
    );
    return 1;
};

sub crop_height {
    my $self = shift;
    my $pCtrl = $self->getCtrl();
    my $iObj = $self->_getIObj(1) or return $pCtrl->error();
    my $height = $pCtrl->param("height");
    my ($iwidth,$iheight) = $iObj->Get('columns','rows');
    if ($iheight > $height) {
        my $e = $iObj->Crop(geometry=>$iwidth.'x'.$height.'+0+0');
        return $pCtrl->error("Ошибка обработки изображения : $e") if $e;
    };
    return 1;
};

sub crop_width_center {
    my $self = shift;
    my $pCtrl = $self->getCtrl();
    my $iObj = $self->_getIObj(1) or return $pCtrl->error();
    my $width = $pCtrl->param("width");
    my ($iwidth,$iheight) = $iObj->Get('columns','rows');
    if ($iwidth > $width) {
        my $delta_width = int(($iwidth-$width)/2);
        my $e = $iObj->Crop(geometry=>$width.'x'.$iheight.'+'.$delta_width.'+0');
        return $pCtrl->error("Ошибка обработки изображения : $e") if $e;
    };
    return 1;
};

sub crop_to_center {
    my $self = shift;
    my $pCtrl = $self->getCtrl();
    my $iObj = $self->_getIObj(1) or return $pCtrl->error();
    my $width = $pCtrl->param("width");
    my $height = $pCtrl->param("height");
    my ($iwidth,$iheight) = $iObj->Get('columns','rows');
    my $current_height = $iheight;
    if ($iheight>$height) {
        my $delta = int(($iheight-$height)/2);
        my $e = $iObj->Crop(geometry=>$iwidth.'x'.$height.'+0'.'+'.$delta);
        return $pCtrl->error("Ошибка обработки изображения : $e") if $e;
        $current_height = $height;
    };
    if ($iwidth>$width) {
        my $delta = int(($iwidth-$width)/2);
        my $e = $iObj->Crop(geometry=>$width.'x'.$current_height.'+'.$delta.'+0');
        return $pCtrl->error("Ошибка обработки изображения : $e") if $e;
    };  
    return 1;  
};
=cut

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
    my $iObj = $self->{_iobjs}->{main} = NG::ImageProcessor::ImageMagickImage->new();
    my $err = $iObj->read($value);
    return $pCtrl->error("Ошибка чтения изображения: $err") if $err;
    1;
};

sub _getIObj {
    my $self = shift;
    my $doCopy = shift;
    
    my $pCtrl = $self->getCtrl();
    
    my $id = $pCtrl->param('id') || 'main';
    
    return $pCtrl->error('Изображение с id '.$id.' не сформировано') unless exists $self->{_iobjs}->{$id};
    return $self->{_iobjs}->{$id} unless ($doCopy);

    my $toid = $pCtrl->param('toid') || $id;
    if ($id ne $toid) {
        $self->{_iobjs}->{$toid} = NG::ImageProcessor::ImageMagickImage->new({parent=>$self->{_iobjs}->{$id}});
        return $pCtrl->error("Ошибка клонирования объекта изображения") unless $self->{_iobjs}->{$toid};
    };
    return $self->{_iobjs}->{$toid};
};

sub _setIObj {
    my $self = shift;
    my $iObj = shift;
    
    my $pCtrl = $self->getCtrl();
    my $id = $pCtrl->param('id') || 'main';
    my $toid = $pCtrl->param('toid') || $id;
    
    #die "" unless $self->{_iobjs}->{$toid};
    $self->{_iobjs}->{$toid}->_setIObj($iObj);
};

#Пропорциональное сжатие в целевую ширину. Высота произвольная.
sub towidth {
    my $self = shift;
    my $pCtrl = $self->getCtrl();
    
    my $width = $pCtrl->param('width');
    return $pCtrl->error("towidth(): Отсутствует параметр width") unless defined $width;
    
    my $iObj = $self->_getIObj(1) or return $pCtrl->error();
    
    my ($iwidth,$iheight) = $iObj->Get('base-columns','base-rows');
    my $koef = ($iwidth/$width);
    if ($koef>1) {
        my $e = $iObj->Resize(width=>int($iwidth/$koef),height=>int($iheight/$koef));
        return $pCtrl->error("Ошибка обработки изображения: $e") if $e;
    };
    1;
};

#Пропорциональное сжатие в целевую высоту. Ширина произвольная.
sub toheight {
    my $self = shift;
    my $pCtrl = $self->getCtrl();

    my $height = $pCtrl->param('height');
    return $pCtrl->error("toheight(): Отсутствует параметр height") unless defined $height;
    
    my $iObj = $self->_getIObj(1) or return $pCtrl->error();
    
    my ($iwidth,$iheight) = $iObj->Get('base-columns','base-rows');
    my $koef = ($iheight/$height);
    if ($koef>1) {
        my $err=$iObj->Resize(width=>int($iwidth/$koef),height=>int($iheight/$koef));
        return $pCtrl->error("Ошибка обработки изображения: $err") if $err;
    };
    1;
};

#Сжатие по максимальной стороне с сохранением пропорции, цель - сжать, чтобы вписать в прямоугольник заданного размера
#Размер картинки не обязательно будет width x height.
sub tomaximal {
    my $self = shift;
    my $pCtrl = $self->getCtrl();

    my $width = $pCtrl->param('width');
    return $pCtrl->error("tomaximal(): Отсутствует параметр width") unless defined $width;
    my $height = $pCtrl->param('height');
    return $pCtrl->error("tomaximal(): Отсутствует параметр height") unless defined $height;
    
    my $iObj = $self->_getIObj(1) or return $pCtrl->error();

    my ($iwidth,$iheight) = $iObj->Get('base-columns','base-rows');
    my $koef = ($iwidth/$width)>($iheight/$height) ? $iwidth/$width : $iheight/$height;
    if ($koef>1) {
        my $err=$iObj->Resize(width=>int($iwidth/$koef),height=>int($iheight/$koef));
        return $pCtrl->error("Ошибка обработки изображения: $err") if $err;
    };
    1;
};

#урезаем в рамку по минимальной стороне с сохранением пропорции. Т.е. дальше надо делать crop по максимальной стороне.
sub tominimal {
    my $self = shift;
    my $pCtrl = $self->getCtrl();
    
    my $width = $pCtrl->param('width');
    return $pCtrl->error("tominimal(): Отсутствует параметр width") unless defined $width;
    my $height = $pCtrl->param('height');
    return $pCtrl->error("tominimal(): Отсутствует параметр height") unless defined $height;

    my $iObj = $self->_getIObj(1) or return $pCtrl->error();
    
    my ($iwidth,$iheight) = $iObj->Get('base-columns','base-rows');
    my $koef = ($iwidth/$width)<($iheight/$height) ? $iwidth/$width : $iheight/$height;
    if ($koef>1) {
        my $err=$iObj->Resize(width=>int($iwidth/$koef),height=>int($iheight/$koef));
        return $pCtrl->error("Ошибка обработки изображения: $err") if $err;
    };
    1;
};

sub torectangle {
    my $self = shift;
    my $pCtrl = $self->getCtrl();

    my $width = $pCtrl->param('width');
    return $pCtrl->error("torectangle(): Отсутствует параметр width") unless defined $width;
    my $height = $pCtrl->param('height');
    return $pCtrl->error("torectangle(): Отсутствует параметр height") unless defined $height;

    my $iObj = $self->_getIObj(1) or return $pCtrl->error();

    my ($iwidth,$iheight) = $iObj->Get('base-columns','base-rows');
    return 1 if ($iwidth == $width) && ($iheight == $height);
    my $koef = undef;
    if ($pCtrl->param('crop')) {
        $koef = ($iwidth/$width)<($iheight/$height) ? $iwidth/$width : $iheight/$height;
    }
    else {
        $koef = ($iwidth/$width)>($iheight/$height) ? $iwidth/$width : $iheight/$height;
    };
    my $err=$iObj->Resize(width=>int($iwidth/$koef)+1,height=>int($iheight/$koef)+1);
    return  "Ошибка обработки изображения: $err" if $err;

    ## Blank image
    my $pp = Image::Magick->new;
    $pp->Set(size=>$width.'x'.$height);
    my $bg = $pCtrl->param('background');
    $bg ||= 'xc:white';
    $pp->ReadImage($bg);
    ## Compose
#TODO: add param for gravity
    $pp->Composite(image=>$iObj->image(),gravity=>'Center');
    
    $self->_setIObj($pp);
    $iObj = undef;
    1;
};

sub savesize {
    my $self = shift;
    my $pCtrl = $self->getCtrl();
    my $iObj = $self->_getIObj(0) or return $pCtrl->error();
    my $fieldName = $pCtrl->param('field');
    return $pCtrl->error("savesize(): Отсутствует параметр field") unless defined $fieldName;
    my $mask = $pCtrl->param('mask') || "{w}x{h}";
    my ($iwidth,$iheight) = $iObj->Get('columns','rows');
    $mask =~ s/\{w\}/$iwidth/gi;
    $mask =~ s/\{h\}/$iheight/gi;
    my $field = $pCtrl->getField($fieldName) or return $pCtrl->error("no field $fieldName");
    $field->setValue($mask);
    return 1;
}

sub saveResult {
    my ($self,$dest) = (shift,shift);

    my $pCtrl = $self->getCtrl();
    
    my $iObj = $self->{_iobjs}->{main} or return $pCtrl->error("No IOBJ");
    
    $dest =~ /.*\.([^\.]*?)$/;
    my $ext = $1;

    my $err = $iObj->Write($dest.'.tmp.'.$ext);
    return $pCtrl->error("Ошибка записи изображения $dest: $err") if $err;

    File::Copy::move($dest.".tmp.".$ext,$dest) or return $pCtrl->error("Error on move file in afterProcess: ".$!);
    return 1;
};

sub getResult {
    my($self, @args) = @_;
    my %opt  = @args % 2 ? () : @args;
    
    my $iObj = $self->{_iobjs}->{main} or NG::Exception->throw('NG.INTERNALERROR', 'Unable to get IOBJ');
    $iObj->{_iobj}->Set(magick=>$opt{force}) if $opt{force};
    
    my $type = $iObj->{_iobj}->Get('magick') or NG::Exception->throw('NG.INTERNALERROR', 'Unable to determine image type');
    if ($iObj->{_quality}) {
        if ($type eq 'jpeg' && exists $iObj->{_quality}->{jpg}) {
            $iObj->{_iobj}->Set(quality=>$iObj->{_quality}->{jpg});
        }
        elsif ($type eq 'png' && exists $iObj->{_quality}->{png}) {
            $iObj->{_iobj}->Set(quality=>$iObj->{_quality}->{png});
        };
    };
    return $iObj->{_iobj}->ImageToBlob,$type;
    return ('blob', $type);
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

    my $field = $pCtrl->getField($fName) or return $pCtrl->error("Поле $fName не найдено");


    my $dest = $field->parent()->getDocRoot() or return $pCtrl->error("Can`t getDocRoot()");
    $dest.= $field->{UPLOADDIR} or return $pCtrl->error("Field $fName has no UPLOADDIR");
    
    $field->{TMP_FILENAME} = $self->{_origfname};
    $field->genNewFileName() or return $pCtrl->error("Field $fName getNewFilename() metod returns no data");
    my $newDBV = $field->dbValue() or return $pCtrl->error("Field $fName dbValue() metod returns no data");
    $dest .= $newDBV;
    
    my $iObj = $self->_getIObj(0) or return $pCtrl->error();
    my $err = $iObj->Write($dest);
    return $pCtrl->error("Ошибка записи изображения $dest: $err") if $err;
    
    $field->setDBValue($newDBV);
    
    1;
};

=comment
    step2       = saveToFile         #сохраняем картинку с идентификатором small в некий файл
    step2_id    = "small"
    step2_dir   = "/some/dir"        #если директория не совпадает с директорией UPLOADDIR исходного поля
    step2_mask  = "{f}_small.{e}"    #маска... маски совпадают с тем что есть в NG::Field
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
    
    my $iObj = $self->_getIObj(0) or return $pCtrl->error();
    my $err = $iObj->Write($dest);
    return $pCtrl->error("Ошибка записи изображения $dest: $err") if $err;

    1;
};

package NG::ImageProcessor::ImageMagickImage;
use strict;
use Carp;
use File::Copy qw();

my $RO_METHODS = {'Get'=>1,'Clone'=>1};

sub new {
    my $class = shift;
    my $opts  = shift;
    
    my $self = {};
    bless $self,$class;
    
    if ($opts->{parent}) {
        $self->{_iobj} = $opts->{parent}->Clone();
        return undef unless $self->{_iobj};
        $self->{_ifile} = $opts->{parent}->{_ifile};
        $self->{_quality} = $opts->{parent}->{_quality};
    }
    else {
        $self->{_iobj} = Image::Magick->new;  #Объект
        $self->{_ifile} = undef;              #Файл на диске, соотв. объекту, если есть. Очищается при изменении объекта.
        $self->{_quality} = $NG::ImageProcessor::config::quality;   #Хеш коэффициентов, ключи: jpg,png
    };
    
    return $self;
};

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
    
    return "Не указано имя файла для сохранения " unless $dest;
    
    if ($self->{_ifile}) {
        File::Copy::copy($self->{_ifile},$dest) or return "Ошибка копирования изображения: ".$!;
    }
    else {
        my %p;
        $p{filename} = $dest;
        if ($self->{_quality}) {
            ($dest =~ /.*\.([^\.]*?)$/) or NG::Exception->throw('NG.INTERNALERROR', 'Write(): unable to get extension from filename');
            my $ext = lc($1);
            if (($ext eq 'jpg' || $ext eq 'jpeg') && exists $self->{_quality}->{jpg}) {
                $p{quality}=$self->{_quality}->{jpg};
            }
            elsif ($ext eq 'png' && exists $self->{_quality}->{png}) {
                $p{quality}=$self->{_quality}->{png};
            };
        };
        my $e = $self->{_iobj}->Write(%p);
        return $e if $e;
    };
    my $mask = umask();
    $mask = 0777 &~ $mask;
    chmod $mask, $dest;
    0;
};

sub _setIObj {
    my $self = shift;
    my $iObj = shift;
    $self->{_iobj}  = $iObj;
    $self->{_ifile} = undef;
};

sub _setQuality {
    my ($self, $quality) = (shift,shift);
    $self->{_quality} = $quality;
};

sub image {
    my $self = shift;
    return $self->{_iobj};
};

sub updated {
    my $self = shift;
    $self->{_ifile} = undef;
}

our $AUTOLOAD;
sub AUTOLOAD {
    my $self=shift;
    my $pkg = ref $self;
    $AUTOLOAD =~ s/$pkg\:\://;
    
    my $rw = 1;
    $rw = 0 if $RO_METHODS->{$AUTOLOAD};
    $rw = 0 if ($AUTOLOAD eq "Set") && ($_[0] eq "quality");
    
    $self->{_ifile} = undef if $rw;
    
    return $self->{_iobj}->$AUTOLOAD(@_) if $self->{_iobj}->can($AUTOLOAD);
    croak('Can\'t locate object method "'.$AUTOLOAD.'" via Image::Magick');
};

sub DESTROY {};

1;
