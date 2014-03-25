package NGTuring;

use strict;
use GD::SecurityImage use_magick => 1;
use NG::Module;

use vars qw(@ISA);
@ISA = qw(NG::Module);

=head

#Минимальная конфигурация:
[Turing]
Session = "Turing"

[SessionTuring]
Module = "NG::Session::file"
	
#Полная конфигурация

[Turing]
Session = "Turing"
CacheDir = /web/site.ru/turcache

cookieName = "SESSTURING"
width = 200
height = 60
lines = 0
ptsize = 20
length = 6
lineColor = #000
fontColor = #BEDCFA
bgcolor = #aaaaaa
scramble = 1
font = "/web/ng4/perl/lib/verdanab.ttf"

[SessionTuring]
Module = "NG::Session::file"

=cut
#Дефолтный конфиг параметров модуля
my %conf = (
	length => 6,
	configSection => "Turing",
	cookieName => "SESSTURING",
	expire    => "10m",
	fontColor => "#000",
	lineColor => "#BEDCFA",
);

#Дефолтный конфиг для GD
my %gdConf = (
	width   => 200,
	height  => 60,
	lines   => 0,
	ptsize     => 25 ,#40,
	bgcolor => [ 50, 50, 50],
	scramble   => 1,
	#gd_font => 'giant',
	#font => "/web/ng4/perl/lib/verdanab.ttf",
);

use constant S_SUCCESS  =>  1; #Введенное число верно
use constant S_EXPIRED  => -1; #Сессия устарела
use constant S_INCORRECT=> -2; #Введенное число не верно
use constant S_NOTFOUND => -3; #Сессия устарела и была удалена

my %errors = (
	S_EXPIRED   => "Session expired",
	S_INCORRECT => "Not correct numbers",
);

sub run {
	my $self = shift;
	$self->getTuringImage();
};

sub init {
	my $self = shift;
	$self->SUPER::init(@_);
	
	$self->{_session} = undef;
	
	my %tmpConf = %gdConf;
	$self->{_gdConfig} = \%tmpConf;
	my %tmpConf2 = %conf;
	$self->{_config} = \%tmpConf2;
	$self->config();
		
	
	foreach my $param (qw(width height lines ptsize bgcolor scramble font)) {
		my $v = $self->confParam($self->{_config}->{configSection}.".".$param);
		next unless $v;
		next if exists $gdConf{$param} && exists $self->{_gdConfig}->{$param} && $gdConf{$param} ne $self->{_gdConfig}->{$param};
		$self->{_gdConfig}->{$param} = $v;
	};
		
	foreach my $param (qw(length cookieName lineColor fontColor expire)) {
		my $v = $self->confParam($self->{_config}->{configSection}.".".$param);
		next unless $v;
		next if exists $conf{$param} && exists $self->{_config}->{$param} && $conf{$param} ne $self->{_config}->{$param};
		$self->{_config}->{$param} = $v;
	};
		
	#$self->{_config}->{length} = $self->{_gdConfig}->{rndmax} if exists $self->{_gdConfig}->{rndmax};
	$self->{_gdConfig}->{rndmax} ||= $self->{_config}->{length};
    
    $self->{_sname} = $self->confParam($self->{_config}->{configSection}.".Session");
    unless ($self->{_sname}) {
        die "NGTuring::getSession(): Parameter ".$self->{_config}->{configSection}.".Session is not configured";
    };
    return $self;
};

sub confParam {
    my $self = shift;
    return $self->cms()->confParam(@_);
};

sub config {};

sub _getTS {
    my $self = shift;
    my $meth = shift;
    
    return $self->{_session} if $self->{_session};
    $self->{_sname} or die "Initialised incorrectly";

    my $q = $self->q();
    my $sid = $q->cookie($self->{_config}->{cookieName});
    
    my $sparam = {};
    #самоочистка для надежных хранилищ сессий
    $self->{_session} = $self->cms()->$meth($self->{_sname},$sid,$sparam) or die $self->{_error};  ##TODO: fix
    $self->{_session}->expire() || $self->{_session}->expire($self->{_config}->{expire});
    
    #CGI::Session->new will silently drop old session if it expires and generate new one
    $self->_clearCacheSID($sid) if ($sid && $sid ne $self->{_session}->id());
    $self->_clearCacheDir() if(rand(100)>90); #Самоочистка для ненадежных хранилищ сессий
    
    return $self->{_session};
};

sub _getTSession {
    my $self = shift;
    return $self->_getTS("getSession",@_);
};

sub _loadTSession {
    my $self = shift;
    return $self->_getTS("loadSession",@_);
};

sub random {
	my $self = shift;
	my $count = $self->{_config}->{length};
	my $numbers="";
	srand();
	for (my $i=0;$i<$count;$i++) {
		$numbers.=int(rand(9));
	};
	return $numbers;
};

sub resetSession {
	my $self = shift;
	my $session = $self->{_session};
	my $number = $session->param('number');
	$session->clear('number');
    $session->clear('imgfilename');
    $self->_clearCacheSID($session->id());
	$session->flush();
};

sub checkTuringInput {
	my $self = shift;
	my %args=(@_);

	my $session = $self->_loadTSession();
    return S_NOTFOUND if ($session->is_empty()); ##Может быть и если картинку не запросили
    return S_EXPIRED  if ($session->is_expired());

    my $number = $session->param('number');
    $self->resetSession();
    return S_INCORRECT unless $args{number} && $number && $number eq $args{number};
    return S_SUCCESS;
};

sub _getCacheDir {
    my $self = shift;
    my $cacheDir = $self->confParam($self->{_config}->{configSection}.".CacheDir") or return undef;
    $cacheDir .= "/" unless $cacheDir =~ /\/$/;
    return $cacheDir;
};

sub _clearCacheSID {
    my $self = shift;
    my $sid = shift or die "_clearCacheSID: no SID value";
    my $cacheDir = $self->_getCacheDir() or return 1;
    
    my $file = $cacheDir.$sid.".gif";
    return 1 unless -e $file;
    unlink $file or warn "Cannot clean file $file from turing images cache";
    return 1;
};

sub _clearCacheDir {
    my $self = shift;
    my $cacheDir = $self->_getCacheDir() or return 1;
    
    opendir( DIRHANDLE, $cacheDir );
    while ( my $filename = readdir(DIRHANDLE) ) {
        next if $filename =~ /^\.\.?$/;
        next unless $filename =~ /(.+)\.gif$/;
        my $ts = $self->cms()->loadSession($self->{_sname},$1) or die $self->{_error};  ##TODO: fix
        next unless $ts->is_empty();
        unlink $cacheDir.$filename or warn "Cannot clean file $filename from turing images cache";
    };
    closedir( DIRHANDLE );
    return 1;
};

sub getTuringImage {
	my $self = shift;
	my $q=$self->q();	
    
	my $session = $self->_getTSession();
    my $sid = $session->id();
    
    my %headers = ();
    $headers{-type}   = "image/gif";
    $headers{-expires}= '-1d';
    $headers{-cookie} = $q->cookie(-name => $self->{_config}->{cookieName},-value => $sid);
    
    my $cacheDir = $self->_getCacheDir();
    if ($cacheDir) {
        die "NGTuring: CacheDir $cacheDir is not writeable" unless -w $cacheDir;
        my $fname = $session->param('imgfilename');
        
        my $rand = $q->param('keywords') || "";
        #TODO: ограничить $rand значением длинной в 20 символов
        #Если rand-а нет, значит идет обычный запрос,
        #отдаем файл из кеша независимо от сессионного rand
        if ($rand && ($session->param('rand') || "") ne $rand) {
            $session->param('rand',$rand);
            $self->_clearCacheSID($session->id());
            $fname = "";
        };
        
        if ($fname && -r $cacheDir.$fname) {
            my $ftime = POSIX::strftime('%a, %d %b %Y %T GMT', gmtime((stat $cacheDir.$fname)[9]));
            
            my $ims = $q->http("If-Modified-Since");
            if ($ims && $ims eq $ftime) {
                print $q->header(-status=>304);
                $session->flush();
                return 1;
            };
            $headers{"-Last-modified"} = $ftime;
            
            binmode STDOUT;
            print $q->header(%headers);
            
            open (FH, "<".$cacheDir.$fname);
            my $buf;
            while (read(FH,$buf,512)) {
                print $buf;
            };
            close(FH);
            
            $session->flush();
            return 1;
        }
        else {
            warn "File not found or not readable in turing images cache: ".$fname if $fname;
            $session->clear('rand') unless $rand; #File not found and no ?random. clear random in session
        };
    };

	my $numbers = $self->random();
	
    my $proc = *GD::SecurityImage::Magick::insert_text;
	*GD::SecurityImage::Magick::insert_text =  \&insert_textX;
	my $image = GD::SecurityImage->new( %{$self->{_gdConfig}});

	$image->random($numbers);
    $image->create(ttf => 'default', $self->{_config}->{fontColor}, $self->{_config}->{lineColor});
    $image->particle(400);

	my ($image_data) = $image->out(force => 'gif' , compress => 9);

    if ($cacheDir) {
        my $fname = $sid.".gif";
        open (FH, ">".$cacheDir.$fname);
        print FH $image_data;
        close(FH);
        $session->param('imgfilename',$fname);
        
        $headers{"-Last-modified"} = POSIX::strftime('%a, %d %b %Y %T GMT', gmtime((stat $cacheDir.$fname)[9]));
    };

	*GD::SecurityImage::Magick::insert_text =  $proc;
	$session->param('number', $image->random_str); ## new value
	$session->flush();
    
	binmode STDOUT;
	print $q->header(%headers);
	print $image_data;
};

## GD::SecurityImage functions replacement

use constant XPPEM        => 0; # character width 
use constant YPPEM        => 1; # character height
use constant ASCENDER     => 2; # ascender
use constant DESCENDER    => 3; # descender
use constant WIDTH        => 4; # text width
use constant HEIGHT       => 5; # text height
use constant MAXADVANCE   => 6; # maximum horizontal advance
# object
use constant ANGLE        => -2;
use constant CHAR         => -1;



sub insert_textX {
    # Draw text using Image::Magick
    my $self   = shift;
    my $method = shift; # not needed with Image::Magick (always use ttf)
    my $key    = $self->{_RANDOM_NUMBER_}; # random string
    my $info   = sub {
        $self->{image}->QueryFontMetrics(
           font      => $self->{font},
           text      => shift,
           pointsize => $self->{ptsize},
           rotate    => shift,
        )
    };
    my %same   = (
       font      => $self->{font},
       encoding  => 'UTF-8',
       pointsize => $self->{ptsize},
       #strokewidth    => 2,
       antialias => 0,
       stroke    => $self->cconvert( $self->{_COLOR_}{text} ),
       fill      => "transparent",
       #fill      => $self->cconvert( $self->{_COLOR_}{text} ),
    );

        my $space = [$info->(' ',0), 0, ' ']; # get " " parameters
        my @randomy;
        my $sy    = $space->[ASCENDER] || 1;
        push(@randomy,  $_, - $_) foreach $sy/2, $sy/4, $sy/8;
        my @char;
        foreach ( split //, $key ) {
			my $ra = $self->random_angle;
           push @char, [$info->($_,$ra), $ra, $_];
        }
        my $total = 0;
           $total += $_->[WIDTH] foreach @char;
           
        my $barw = ($self->{width}-$total)/(scalar(@char)+1);
        $barw=0 if ($barw<0);
        my $x = abs($char[0]->[WIDTH]);
           
        foreach my $magick (@char) {
            $total -= $magick->[WIDTH] * 2;
            $self->{image}->Annotate(
               text   => $magick->[CHAR],
               x      =>  $x, #($self->{width}  - $total - $magick->[WIDTH]   ) / 2,
               y      => (($self->{height}          + $magick->[ASCENDER]) / 2) + $randomy[int rand @randomy],
               rotate => $magick->[ANGLE],
               %same,
            );
            $x += $magick->[WIDTH] + $barw;
        }
    return;
}

1;
END{};
 