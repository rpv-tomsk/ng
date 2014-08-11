package NG::RtfImage;
use strict;
use NSecure;
use NGService;
use NHtml;
use File::Copy;
use File::Path;
use URI::Escape;

$NG::RtfImage::VERSION = 0.4;

sub new {
    my $class = shift;
    my $self = {};
    bless $self, $class;
    $self->init(@_);    
    return $self; 
}

sub init {
    my $self=shift;
    my %ref = (@_);
    
    $self->{_q}       = $ref{CGIObject} || die  "NG::RtfImage::new(): CGIObject parameter is missing"; 
    $self->{_docroot} = $ref{DOCROOT}   || die  "NG::RtfImage::new(): DOCROOT parameter is missing"; 
    $self->{_subdir}  = $ref{SUBDIR}    || "";
    $self->{_fieldname}=$ref{FIELDNAME} || "userfile";
    
    $self->{_docroot} .= "/"  unless ($self->{_docroot} =~ s/[\/\\]$/\//);
    
    if ($self->{_subdir}) {
        $self->{_subdir}  =~ s/^[\/\\]//;
        $self->{_subdir} .= "/"  unless ($self->{_subdir} =~ s/[\/\\]$/\//);
    };
    
    $self->{_error} = "";
    
    return $self;
}

sub q         {return shift->{_q};        };
sub docroot   {return shift->{_docroot};  };
sub subdir    {return shift->{_subdir};   };
sub fieldname {return shift->{_fieldname};};
sub filename  {return shift->{_filename}; };

sub error {
    my $self = shift;
    $self->{_error} = shift;
    return 0;
}

sub moveUploadedFile {
    my $self = shift;
    my $filename = shift; ## Если пусто - значит рандом

    my $original_filename = $self->q()->param($self->fieldname());    
    if (is_empty $filename) {
        if ($original_filename =~ /([^\\\/]+)$/) {
            $filename = int(rand(1000))."_".ts($1);
        };
    };
	#$filename = translite($filename); #TODO: Доделать приведение имени файла в латинский регистр.
    my $tmpfilename = $self->q()->tmpFileName($original_filename) or return $self->error("Файл не выбран");
    return $self->error("Не верный формат файла") if (!is_valid_image($original_filename));
    
    my $uploadfile = $self->docroot().$self->subdir().$filename;
    return $self->error("Файл с таким именем уже существует") if (-e $uploadfile && -s $uploadfile);

    eval { mkpath($self->docroot().$self->subdir()); };
    if ($@) {
        $@ =~ /(.*)at/s;
        return $self->error("Ошибка при создании директории: $1");
    }
    return $self->error("Недостаточно привилегий для записи файла в директорию ".$self->subdir()) unless -w $self->docroot().$self->subdir();

    my $mask = umask();
    $mask = 0777 &~ $mask;
    close($original_filename);
    move($tmpfilename, $uploadfile) or return $self->error("Error on file move: ".$!);
    chmod $mask, $uploadfile;
    $self->{_filename} = $filename;
    return 1;
};

sub cleanUploadedFile {
    my $self = shift;
    my $original_filename = $self->q()->param($self->fieldname());
    my $tmpfilename = $self->q()->tmpFileName($original_filename);
    unlink $tmpfilename;
    return 1;
};

sub getFileNameJS {
    my $self = shift;
    my $f = $self->getFileName();
    $f = escape_js $f;
    $f =~ s/%/%25/g;
    return  "<script>parent.document.getElementById('src').value='$f';parent.ImageDialog.showPreviewImage('$f');</script>";
};

sub getFileName {
    my $self = shift;
    return "/".$self->subdir().$self->filename();
};

sub getErrorJS {
    my $self = shift;
    my $error = shift;
    $error = $self->getError() if (ref $self && !defined $error);
    return "<script>alert('".escape_js($error)."');</script>";
};

sub getError {
    my $self = shift;
    return $self->{_error};
};


return 1;
END{};