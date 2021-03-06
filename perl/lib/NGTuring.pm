package NGTuring;

use strict;
use NG::Module;

use vars qw(@ISA);
@ISA = qw(NG::Module);

=head

#����������� ������������:
[Turing]
Session = "Turing"

[SessionTuring]
Module = "NG::Session::file"
	
#������ ������������

[Turing]
Session = "Turing"
CacheDir = /web/site.ru/.turcache

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
#font = "/web/ng4/perl/lib/verdanab.ttf"
useNumbers = 1
useLetters = 0

[SessionTuring]
Module = "NG::Session::file"

=cut
#��������� ������ ���������� ������
my %conf = (
	length => 6,
	configSection => "Turing",
	cookieName => "SESSTURING",
	expire    => "10m",
	fontColor => "#000",
	lineColor => "#BEDCFA",
);

#��������� ������ ��� GD
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

use constant S_SUCCESS  =>  1; #��������� ����� �����
use constant S_EXPIRED  => -1; #������ ��������
use constant S_INCORRECT=> -2; #��������� ����� �� �����
use constant S_NOTFOUND => -3; #������ �������� � ���� �������

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
		my $v = $self->confParam($param);
		next unless defined $v;
		next if exists $gdConf{$param} && exists $self->{_gdConfig}->{$param} && $gdConf{$param} ne $self->{_gdConfig}->{$param};
		$self->{_gdConfig}->{$param} = $v;
	};
		
	foreach my $param (qw(length cookieName lineColor fontColor expire)) {
		my $v = $self->confParam($param);
		next unless $v;
		next if exists $conf{$param} && exists $self->{_config}->{$param} && $conf{$param} ne $self->{_config}->{$param};
		$self->{_config}->{$param} = $v;
	};
		
	#$self->{_config}->{length} = $self->{_gdConfig}->{rndmax} if exists $self->{_gdConfig}->{rndmax};
	$self->{_gdConfig}->{rndmax} ||= $self->{_config}->{length};
    
    $self->{_sname} = $self->confParam("Session");
	$self->{_sname} or return $self->cms->error("NGTuring::getSession(): Parameter ".$self->{_config}->{configSection}.".Session is not configured");
	
	$self->{_useGD} = $self->confParam("UseGD", 0);
	if ($self->{_useGD}) {
		eval "use GD::SecurityImage use_gd => 1;";
	}
	else {
		eval "use GD::SecurityImage use_magick => 1";
	};
    return $self->cms()->error($@) if $@;
    return $self;
};

sub confParam {
    my ($self, $param) = (shift, shift);
    $param = $self->{_config}->{configSection}.".".$param;
    return $self->cms()->confParam($param, @_);
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
    #����������� ��� �������� �������� ������
    $self->{_session} = $self->cms()->$meth($self->{_sname},$sid,$sparam) or die $self->cms()->getError();
    $self->{_session}->expire() || $self->{_session}->expire($self->{_config}->{expire});
    
    #CGI::Session->new will silently drop old session if it expires and generate new one
    $self->_clearCacheSID($sid) if ($sid && $sid ne $self->{_session}->id());
    $self->_clearCacheDir() if(rand(100)>90); #����������� ��� ���������� �������� ������
    
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
    
    my @characters = ();
    
    push @characters, (
        "1","2","3","4","5","6","7","8","9","0"
    ) if $self->confParam('useNumbers', 1);
    
    push @characters, (
        "A","B","C","D","E","F","G","H","I","J",
        "K","L","M","N","O","P","Q","R","S","T",
        "U","V","W","X","Y","Z"
    ) if $self->confParam('useLetters', 0);
    
    my $length = scalar @characters;
    
    my $numbers="";
    srand();
    for (my $i=0; $i < $count; $i++) {
        $numbers .= $characters[rand($length)];
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
    return S_NOTFOUND if ($session->is_empty()); ##����� ���� � ���� �������� �� ���������
    return S_EXPIRED  if ($session->is_expired());

    my $number = $session->param('number');
    $self->resetSession();
warn "$number ".$args{number};
    return S_INCORRECT unless $args{number} && $number && $number eq uc($args{number});
    return S_SUCCESS;
};

sub _getCacheDir {
    my $self = shift;
    my $cacheDir = $self->confParam("CacheDir") or return undef;
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
        #TODO: ���������� $rand ��������� ������� � 20 ��������
        #���� rand-� ���, ������ ���� ������� ������,
        #������ ���� �� ���� ���������� �� ����������� rand
        if ($rand && ($session->param('rand') || "") ne $rand) {
            $session->param('rand',$rand);
            $self->_clearCacheSID($session->id());
            $fname = "";
        };
        
        if ($fname && -r $cacheDir.$fname) {
            my $ftime = POSIX::strftime('%a, %d %b %Y %T GMT', gmtime((stat $cacheDir.$fname)[9]));
            
            my $ims = $q->http("If-Modified-Since");
            if ($ims && $ims eq $ftime) {
                $session->flush();
                return $self->cms()->exit("",-status=>304);
            };
            $headers{"-Last-modified"} = $ftime;
            
            binmode STDOUT;
            
            open (FH, "<".$cacheDir.$fname);
            my $buf;
            my $image_data = undef;
            while (read(FH,$buf,512)) {
                $image_data.=$buf;
            };
            close(FH);
            
            $session->flush();
            return $self->cms()->exit($image_data,\%headers);
        }
        else {
            warn "File not found or not readable in turing images cache: ".$fname if $fname;
            $session->clear('rand') unless $rand; #File not found and no ?random. clear random in session
        };
    };

	my $numbers = $self->random();
	
	no warnings 'redefine';
	local *GD::SecurityImage::Magick::insert_text =  \&insert_textX unless $self->{_useGD};
	my $image = GD::SecurityImage->new( %{$self->{_gdConfig}});
    
    unless ($self->{_useGD}) {
        my $bgc = $self->{_gdConfig}->{bgcolor};
        if (ref $bgc || $bgc ne "transparent"){
            my $bg = $image->cconvert( $bgc );
            
            $image->{image}  = Image::Magick->new;
            $image->{image}->Set(  size=> "$image->{width}x$image->{height}" );
            $image->{image}->Read( 'xc:' . $bg );
            $image->{image}->Set(  background => $bg );
        };
    };

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

	$session->param('number', $image->random_str); ## new value
	$session->flush();
    
	binmode STDOUT;
	return $self->cms()->exit($image_data,\%headers);
};

## GD::SecurityImage functions replacement

#QueryFontMetrics.
use constant XPPEM        => 0; # character width 
use constant YPPEM        => 1; # character height
use constant ASCENDER     => 2; # ascender
use constant DESCENDER    => 3; # descender
use constant WIDTH        => 4; # text width
use constant HEIGHT       => 5; # text height
use constant MAXADVANCE   => 6; # maximum horizontal advance
                                # * bounds.x1
                                # * bounds.y1
                                # * bounds.x2
                                # * bounds.y2
                                # * origin.x
                                # * origin.y
# object
use constant ANGLE        => -2;
use constant CHAR         => -1;

sub insert_textX {
    # Draw text using Image::Magick
    my $self   = shift;
    my $method = shift; # not needed with Image::Magick (always use ttf)
    my $key    = $self->{_RANDOM_NUMBER_}; # random string
    my $info   = sub {
        my %p = ();
        $p{font} = $self->{font};
        $p{text} = shift;
        $p{pointsize} = $self->{ptsize};
        $p{rotate} = shift;
        $self->{image}->QueryFontMetrics(%p);
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

    my @char;
    foreach ( split //, $key ) {
        my $ra = $self->random_angle || 0;
        push @char, [$info->($_,$ra), $ra, $_];
    }
    my $total = 0;
       $total += abs($_->[WIDTH]) foreach @char;
    
    my $barw = ($self->{width}-$total)/(scalar(@char)+1);
    $barw=0 if ($barw<0);
        
    my $x = $barw;
    
    my @randomy; #  Variants of shift by height, in fractions of free space
    push(@randomy, $_, -$_) foreach 2,3,4,6,8;
    
    foreach my $magick (@char) {
        $total -= $magick->[WIDTH] * 2;
        my $rr = int rand @randomy;
        $self->{image}->Annotate(
           text   => $magick->[CHAR],
           x      =>  $x, #($self->{width}  - $total - $magick->[WIDTH]   ) / 2,
           y      => (($self->{height} + $magick->[ASCENDER]) / 2) + ($self->{height} - $magick->[ASCENDER])/$randomy[$rr] - 2,
           rotate => $magick->[ANGLE],
           %same,
        );
        $x += $magick->[WIDTH] + $barw;
    };
    return;
}

1;
END{};
 
