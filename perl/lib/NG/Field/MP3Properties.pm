package NG::Field::MP3Properties;
use strict;
use NG::Field;
use vars qw(@ISA);
@ISA = qw(NG::Field);
use Image::ExifTool ':Public';

sub init {
    my $field = shift;
    $field->{TYPE} = "text";    
    $field->SUPER::init(@_) or return undef;
    return 1;
};

sub copyMP3Duration {
    my $self = shift;
    my $parent = shift;
    return $self->setError("Поле-родитель ".$parent->{FIELD}." не является файловым полем") unless ($parent->isFileField());
    return $self->setError("В файловом поле ".$parent->{FIELD}." прикреплен не mp3 файл") if ($parent->{TMP_FILENAME} !~ /\.mp3$/);
    my $file = $parent->value();
	my $info = ImageInfo($file);
	$info->{'Duration'} =~ s/[^1-9\:]//gi;
	my ($second,$minute,$hour) = reverse (split (/\:/,$info->{'Duration'}));
    $self->setValue($hour*3600+$minute*60+$second);
    return 1;
};

return 1;
