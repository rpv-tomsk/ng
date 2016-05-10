# NGx CMS (C) 2010 Pavel V. Rochnyack <rochnyack@ngs.ru>.
# This program is distributed under the terms of the
# GNU General Public License, version 2.
#
package NG::Mailer;
use strict;
use vars qw(@ISA);
$NG::Mailer::VERSION=0.5;

use NG::Module 0.5;
@ISA = qw(NG::Module);

use MIME::Lite;
#use Net::SMTP;

sub init {
    my $self = shift;
    
    my $cms = $self->cms();
    
    #Storages for parts - content-alternatives, attachments-parts, headers.
    $self->{_alternatives} = {};
    $self->{_parts} = [];
    $self->{_headers} = undef;
    
    #Resulting data object
    $self->{_dataObj} = undef;
    $self->{imgCache} = {};    #
    $self->{_mObj} = undef;    #Кешированный объект метода доставки

    $self->{_opts} = {};
    $self->{_charset} = $cms->{_charset};
    
    $self->{_gcode} = undef;
    $self->{_gsubcode} = undef;
    $self->{_mcode} = undef;
    
    return $self->SUPER::init(@_);
};

=comment
   Supported $self->{_opts} options:
   - plainEncoding - set Encoding (base64 | quoted-printable | 8bit | 7bit )
   - htmlEncoding  -  --//- 
=cut

sub _newML {
    my $self = shift;
    NG::Mailer::MIMELite->new(Mailer=>$self, @_);
};


sub rset {  #Подготавливает объект к формированию нового письма. Сбрасывается всё, кроме кеша.
    my $self = shift;
    
    $self->{_dataObj} = undef;
    $self->{_alternatives} = {};
    $self->{_parts} = [];
    $self->{_headers} = undef;
};

#Сохраняем выставляемые атрибуты в отдельный  объект. Потом соберем.
sub add {
    my $self = shift;
    
    #No object exists and type is unknown. Save headers..
    $self->{_headers} ||= $self->_newML(Top=>0);
    die "Header 'To' already added" if lc($_[0]) eq "to" and $self->{_headers}->get('To');
    $self->{_headers}->add(@_);
    #Set headers in result set too, if exists.
    $self->{_dataObj}->add(@_) if $self->{_dataObj};
};

sub addPlainPart {
    my $self = shift;
    
    my $cms = $self->cms();

    return $cms->error("addPlainPart(): incorrect usage, no params passed") if (scalar @_ == 0);
    warn "addPlainPart(): PlainText part already exists and will be overwritten." if exists $self->{_alternatives}->{'text/plain'};
    
    my %params = ();
    if (scalar @_ == 1) {
        my $param = shift or return $cms->error("setPlainPart(): incorrect usage, no data passed");
        die "addPlainPart(): Single parameter must be text" if ref $param;
        $params{Data} = $param;
    }
    else {
        %params = @_;
    };
    
    $params{Type} ||= "text/plain; charset=".($params{Charset}||$self->{_charset});
    delete $params{Charset};
    
    $params{Encoding} ||= $self->{_opts}->{plainEncoding};
    $params{Top} = 0;
    
    $self->{_dataObj} = undef;
    $self->{_alternatives}->{'text/plain'} = $self->_newML(%params);
};

sub addHTMLPart {
    my $self = shift;

    warn "addHTMLPart(): HTML part already exists and will be overwritten." if exists $self->{_alternatives}->{'text/html'};
    
    my $cms = $self->cms();
    return $cms->error("addHTMLPart(): incorrect usage, no params passed") if (scalar @_ == 0);
    
    my %params = ();
    if (scalar @_ == 1) {
        $params{Data} = shift;
        die "addHTMLPart(): Single parameter must be text" if ref $params{Data};
    }
    else {
        %params = @_;
    };
    (defined( $params{Data} ) + defined( $params{Path} ) + defined( $params{FH} ) == 1 ) or return $cms->error("addHTMLPart(): specify (Data|Path|FH) for HTML content. Add BaseDir for images base dir.");
    
    my $baseDir = delete $params{BaseDir};
    
    $params{Type} ||= "text/html; charset=".($params{Charset}||$self->{_charset});
    delete $params{Charset};
    
    $params{Encoding} ||= $self->{_opts}->{htmlEncoding};
    $params{Top} = 0;
    
    my $contentPart = $self->_newML(%params);
    
    #If BaseDir is empty then nothing to do, exiting...
    $self->{_dataObj} = undef;
    return $self->{_alternatives}->{'text/html'} = $contentPart unless $baseDir;
    
    #Get content for parsing.
    $contentPart->read_now();
    my $text = $contentPart->data();

    my %images = ();
    my $index = 0;
    my $patternImage = sub {
        return '<img'.$_[0].' src="'.$_[1].'"' if $_[1] =~ /^http:\/\//;
        $images{$_[1]} = $index++ unless exists $images{$_[1]};
        return '<img'.$_[0].' src="cid:Image'.$images{$_[1]}.'"';
    }; 
#  {$gabarit=~s/<img ([^<>]*) src\s*=\s*(["']?) ([^"'> ]* )(["']?)/pattern_image_cid($self,$1,$3,$racinePage)/iegx;}
    $text =~ s/<img([^<>]*) src\s*=\s*(["']?)([^"'>]*)(["']?)/&$patternImage($1,$3)/ieg;
    
    #pass it back
    $contentPart->data($text);
    
    #while ($text =~ s/(<img\s.*?src=[\'\"])(.*?)([\'\"].*?>)/&$patternImage($1,$2,$3);image\:$index/si) {
    #};
    #$text =~ s@image\:(\d+)@$images{$1}->{first}cid\:$images{$1}->{Id}$images{$1}->{second}@sgi;
    
    if (scalar keys %images) {
        my $multiPart = $self->{_alternatives}->{'text/html'} = $self->_newML(Top=>0,Type=> "multipart/related");
        $multiPart->attr('Content-type.type','text/html');
        
        $multiPart->attach($contentPart);
        
        foreach my $url (keys %images) {
            my $cid = $images{$url};
            my $fpath = $url;
            $fpath =~ s/\%20/ /g;
            next unless -e $baseDir.$fpath && -r $baseDir.$fpath && -s $baseDir.$fpath;
            $multiPart->attach(
                Type => "AUTO",
                Id   => "Image".$cid,
                Path => $baseDir.$fpath,
                USEImgCache => 1,
            );
        };
    }
    else {
        $self->{_alternatives}->{'text/html'} = $contentPart;
    };
    $self->{_alternatives}->{'text/html'};
};

sub addPart {
    my $self = shift;
    my %params = @_;
    
    my $part = $self->_newML(Top=>0,@_);
    
    my $type = $part->attr('content-type');
    my $cdisp = $part->attr('content-disposition');
    
    $type = $part->attr('content-type.type') if ($type eq 'multipart/related');
    
    if (($type eq 'text/html' || $type eq 'text/plain') && ($cdisp ne 'attachment')) {
        warn "addPart(): $type part already exists and will be overwritten." if exists $self->{_alternatives}->{$type};
        return $self->{_alternatives}->{$type} = $part;
    };
    push @{$self->{_parts}},$part;
    $self->{_dataObj} = undef;
    $part;
};

sub attachFile {
    my $self = shift;
    my $path = shift;
    $path = shift if $path eq "Path";
    
    my $part = $self->_newML(Path=>$path,Type=>'AUTO',Disposition=>'attachment',Top=>0);
    
    push @{$self->{_parts}},$part;
    $self->{_dataObj} = undef;
    $part;
};

sub _getDataObj {
    my $self = shift;
    
    return $self->{_dataObj} if $self->{_dataObj};
    
    my $hcontent = undef;
    if (scalar keys %{$self->{_alternatives}} > 1) {
        $hcontent = $self->_newML(Top=>0,Type=> "multipart/alternative");
        
        $hcontent->attach($self->{_alternatives}->{'text/plain'}) if $self->{_alternatives}->{'text/plain'};
        $hcontent->attach($self->{_alternatives}->{'text/html'}) if $self->{_alternatives}->{'text/html'};
        #... and some other alternatives, when method addAlternative will arrive
    }
    else {
        my ($type) = keys %{$self->{_alternatives}};
        $hcontent = $self->{_alternatives}->{$type} if $type;
    };
    
    if (scalar @{$self->{_parts}} + defined($hcontent) > 1) {
        my $top = $self->_newML(Type=> "multipart/mixed");
        $top->attach($hcontent);
        map {$top->attach($_)} @{$self->{_parts}};
        $self->{_dataObj} = $top;
    }
    else {
        $self->{_dataObj} = @{$self->{_parts}}[0] || $hcontent;
    };
    
    #die "getDataObj(): no data to send" unless $self->{_dataObj};
    $self->{_dataObj} or return $self->cms->error("getDataObj(): no data to send");
    
    $self->{_dataObj}->top_level(1);
    require Email::Date::Format;
    $self->{_dataObj}->add( 'date', Email::Date::Format::email_date() ) unless $self->{_dataObj}->get( 'date' );
    $self->{_dataObj}->delete('X-Mailer');
    if ($self->{_headers} && $self->{_dataObj}) {
        my %hMap = map {$_->[0]=>1} @{$self->{_dataObj}->{Header}};
        foreach my $k ( @{$self->{_headers}->{Header}}) {
            if (exists $hMap{$k->[0]}) {
                warn "Header ".$k->[0]." from addPart() overrides header from add() which was called earlier";
                next;
            };
            push @{$self->{_dataObj}->{Header}}, $k;
        };
    };
    return $self->{_dataObj};
};

sub setGroupCode {
    my $self = shift;
    $self->{_gcode} = shift;
    $self->{_gsubcode} = undef;
    $self->{_mcode} = undef;
    $self->{_mObj}  = undef;
};

sub _cparam ($$) {
    my $self = shift;
    my $param = shift;
    
    my $v = undef;
    if ($self->{_gcode}) {
        $v = $self->confParam($self->{_gcode}."_".$param);
        $self->{_gsubcode} ||= $self->confParam($self->{_gcode}."_SUBGROUP");
        $self->{_gsubcode} ||= $self->{_gcode};
        $v = $self->confParam($self->{_gsubcode}."_".$param) if !defined $v && ($self->{_gsubcode} ne $self->{_gcode});
    };
    $v = $self->confParam($param) unless defined $v;
    $v;
};

sub _mparam ($) {
    my $self = shift;
    my $param = shift;
    die "_mparam(): Method is not set for NG::Mailer" unless $self->{_mcode};
    return $self->confParam("%".$self->{_mcode}."_".$param);
}

sub send {
    my $self = shift;

    my $cms = $self->cms();
    
    #Get recipients and options...
    my $opts = {};
    $opts = pop(@_) if (@_ && ref($_[-1]));
    
    $self->{_mcode} = $self->_cparam('Method');
    
    my $class = $self->_mparam('Class');
    $class ||= "NG::Mailer::SMTP" if $self->{_mcode} eq "SMTP"; # Fix this in future, when more modules will be ...
    $class ||= "NG::Mailer::File" if $self->{_mcode} eq "File";
    $class or die "No class..."; #fix.
    
    my $d = $self->_getDataObj() or return $cms->error("send(): No data to send");
    
    foreach my $h (qw/From Subject To Cc Bcc/) {
        $d->get($h) and next;
        my $v = $self->_cparam($h) or next;
        $self->add($h,$v);
    };
    
    if (@_) {
        die "send(): has recpients list and To option simultaneously." if $opts->{To};
        $opts->{To} = \@_;
    };
    if ($opts->{To}) {
        $opts->{To} = [$opts->{To}] unless ref $opts->{To};
        ref $opts->{To} eq "ARRAY" or return $cms->error("send(): option To has incorrect type ".ref($opts->{To}));
    }
    else {
        #Scan email content for recpients...
        my @hdr_to = MIME::Lite::extract_only_addrs( scalar $d->get('To') ); ## Only one To: header should exist
        foreach my $field (qw/Cc Bcc/) {
            push @hdr_to, MIME::Lite::extract_only_addrs($_) for $d->get($field);
        };
        $opts->{To} = \@hdr_to;
    };
    @{$opts->{To}} or return $cms->error("send(): No recipients found.");
    $opts->{From} = $d->get('From') unless exists $opts->{From};
    
    my $debug = $self->_cparam('Debug') || 0;
    $debug = 1 if ($debug eq '0' || $debug eq 'cms') && $cms->debug();
    $debug = 0 if $debug eq 'disabled';
    $debug = 1 if $debug ne '0';
    
    if ($debug) {
        my $debugTo = $self->_cparam('DebugTo');
        $debugTo or return $cms->error("send(): Trying to debug e-mail generation, but no DebugTo address found");
        
        my $debugMode = $self->_cparam('DebugMode') || "asis";
        
        if ($debugMode eq "attach-recipients") {
            #First Method. Attach addresses as attachment.
            my $data = "--- Список получателей / E-Mails list ---\r\n";
            map {$data.= $_."\r\n"} @{$opts->{To}};
            $data.= "----------------------------\r\n";
            $self->addPart(Data=>$data,Type=>'text/plain',Filename=>'emailrcpts.txt',Disposition=>'attachment')->attr('content-type.charset','windows-1251');
            $d = $self->_getDataObj();
        }
        elsif ($debugMode eq "attach-message") {
            #Second Method. Attach email as attach.
            my $data = "--- Список получателей / E-Mails list ---\r\n";
            map {$data.= $_."\r\n"} @{$opts->{To}};
            $data.= "----------------------------\r\n\tСодержимое отправляемого письма во вложении.";
            my $top =  $self->_newML(Type=> "multipart/mixed",From=>$opts->{From},To=>$debugTo, Subject=>$d->get('Subject')||"Отладочное письмо");
            my $part1 = $self->_newML(Top=>0,Type=>'text/plain',Data=>$data);
            my $part2 = $self->_newML(Top=>0,Type=>'message/rfc822',Disposition=>'attachment',Filename=>'1.eml',Data=>$d->as_string);
            $part1->attr('content-type.charset','windows-1251');
            $top->attach($part1);
            $top->attach($part2);
            $d = $top;
        };
        $opts->{To} = [$debugTo];  #Не забываем слать отладку только себе.
    };
    
    my $s = $self->{_mObj} ||= $cms->getObject($class,$self);
    $s->send($d,$opts);
};

package NG::Mailer::SMTP;
use strict;
use Scalar::Util();

sub new {
    my $class = shift;
    my $self = {};
    bless $self,$class;
    $self->{Mailer} = shift;
    $self->{SMTP} = undef;
    
    Scalar::Util::weaken($self->{Mailer});
    
    $self;
};

sub _connect {
    my $self = shift;
    
    #require Net::SMTP;
    use Net::SMTP;
    
    my $cms = $self->cms();
    my $m   = $self->{Mailer};
    
    my %p = ();
    foreach my $h (qw/Host Hello Port LocalAddr LocalPort Timeout ExactAddresses Debug/) {
        my $v = $m->_mparam($h) or next;
        $p{$h} = $v;
    };
    $p{Host}||="localhost";
    my $smtp = $self->{SMTP} = Net::SMTP->new(%p) or return $cms->error("SMTP: Failed to connect to server: ".$!);
    
    %p = ();
    foreach my $h (qw/NoAuth AuthUser AuthPass/) {
        my $v = $m->_mparam($h) or next;
        $p{$h} = $v;
    };
    if (defined $p{AuthUser} && defined $p{AuthPass} and !$p{NoAuth}) {
        $smtp->supports('AUTH') or                return $cms->error("SMTP: AUTH not supported");
        $smtp->auth($p{AuthUser},$p{AuthPass}) or return $cms->error("SMTP: AUTH failed: ".$!." ".$smtp->message);
    };
    $smtp;
};

sub send {
    my ($self,$data,$opts) = (@_);   #$opts - To, From, Notify SkipBad ORcpt

    my $cms = $self->cms();
    
    $opts->{From} or return $cms->error("SMTP: No 'From' option found.");
    ($opts->{To} && ref ($opts->{To}) eq "ARRAY" && @{$opts->{To}}) or return $cms->error("SMTP: No 'To' option found.");
    
    my $smtp = $self->{SMTP};
    
    my $cached = 0;
    if ($smtp) {
        $cached = 1;
    }
    else {
        $smtp = $self->_connect();
        return $cms->error() unless $smtp;
    };
    
    while (1) {
        my $ret = $smtp->mail($opts->{From});
        last if $ret;
        if ($cached && ($smtp->code() eq '000')) {
            warn "NG::Mailer::SMTP: Lost cached connection";
            $smtp = $self->_connect();
            return $cms->error() unless $smtp;
            $cached = 0;
            next;
        }
        return $cms->error("SMTP: MAIL failed: ".$!." ".$smtp->message." ".$smtp->code);
    };
    
    my %p = ();
    %p = map { exists $opts->{$_} ? ( $_ => $opts->{$_} ) : () } qw/Notify SkipBad ORcpt/;
    $p{Notify} = ['NEVER'] unless exists $p{Notify};
    $p{SkipBad} = 1 unless exists $p{SkipBad};
    $smtp->recipient(@{$opts->{To}}, \%p)  or return $cms->error("SMTP: recipient() failed: ".$!." ".$smtp->message);
    
    $smtp->data()                 or return $cms->error("SMTP: DATA failed: ".$!." ".$smtp->message);
    $smtp->datasend($data->as_string); #<- this is the best...
    #$data->print_for_smtp($smtp);
    $smtp->dataend()              or return $cms->error("SMTP: dataend() failed: ".$!." ".$smtp->message);
    return 1;
};

sub DESTROY {
    my $self = shift;
    
    $self->{SMTP}->quit() if $self->{SMTP};
};

package NG::Mailer::File;
use strict;
use Scalar::Util();

sub new {
    my $class = shift;
    my $self = {};
    bless $self,$class;
    $self->{Mailer} = shift;
    
    Scalar::Util::weaken($self->{Mailer});
    
    $self;
};

sub send {
    my ($self,$data,$opts) = (@_);
    
    my $cms = $self->cms();
    my $m   = $self->{Mailer};
    
    my %p = ();
    foreach my $h (qw/OutputDir OutputFile MessageOnly/) {
        my $v = $m->_mparam($h) or next;
        $p{$h} = $v;
    };
    
    if ($p{OutputFile}) {
        #
    }
    elsif ($p{OutputDir}) {
        $p{OutputFile} = $p{OutputDir};
        $p{OutputFile} =~ s@\/$@@;
        $p{OutputFile} .= "/".int(time);
    }
    else {
        return $cms->error("NG::Mailer::File->send(): Need OutputDir or OutputFile");
    };

    local *FILE;
    open FILE, ">>".$p{OutputFile} or return $cms->error("NG::Mailer::File->send(): open ".$p{OutputFile}." failed: $!\n");
    unless ($p{MessageOnly}) {
        eval "require Data::Dumper";
        print FILE "--- Options ---\r\n";
        print FILE Data::Dumper::Dumper($opts);
        print FILE "--- Message ---\r\n";
    }
    $data->print( \*FILE );
    close FILE;
    return 1;
};

package NG::Mailer::MIMELite;
use MIME::Lite;
use vars qw(@ISA);
@ISA = qw(MIME::Lite);

use Scalar::Util();

sub build {
    my $self = shift;
    my %params = @_;
    
    if (my $mailer = delete $params{Mailer}) {
        ref($self) or $self = $self->new;
        $self->{Mailer} = $mailer;
        Scalar::Util::weaken($self->{Mailer}); ###NEEDED!!!
    };
    if ($params{USEImgCache}) {
        $self->{USEImgCache} = 1;
    };
    $self->SUPER::build(%params);
};

sub encode {
    my $self = shift;
    my $text = shift;
    return $text unless $text =~ /[\x80-\xFF]/g;
    my $charset = $self->{Mailer}->{_charset};

    #The form is: "=?charset?encoding?encoded text?=".  (RFC2047)
    
    #Quoted-Printable encoding
    #require MIME::QuotedPrint;
    #$text="=?$charset?Q?".MIME::QuotedPrint::encode_qp($text);
    #$text =~ s/=\n$//;
    #$text =~ s/=\n/\?=\n=\?$charset\?Q\?/g;

    #Base64 encoding
    $text="=?$charset?B?".MIME::Base64::encode($text);
    #$text="=?$charset?B?".MIME::Lite::encode_base64($text); what about to use M:L method and do not depend on MIME::Base64???
    $text =~ s/\n$//;
    $text =~ s/\n/\?=\n=\?$charset\?B\?/g;
    
    $text .= "?=";
    return $text;
};

sub add {
    ## Method to do russian characters encoding in some of mail headers
    my $self = shift;
    my $tag = lc(shift);
    my $value =shift;
  
    if (
        ($tag eq "from")||
        ($tag eq "to")||
        ($tag eq "cc")||
        ($tag eq "bcc")||
        ($tag eq "sender")||
        ($tag eq "reply-to")
        ) {
        my @vals = ((ref($value) and (ref($value) eq 'ARRAY'))?@{$value}:($value.''));
      
        foreach my $value (@vals) {
            $value =~ s/(.*?)((?:<[a-z0-9]+(?:[-._]?[a-z0-9]+)*@[a-z0-9]+(?:\.?[a-z0-9]+[-_]*)*\.[a-z]{2,5}>))/encode($self,$1)." ".$2/ei;
            #Mail::Address is bad thing...
            #my ($email) = Mail::Address->parse($value);
            #$email->[0] = b64encode($email->phrase());
            #$value = $email->format();
            #$value = b64encode($value);
        }
        return $self->SUPER::add($tag,\@vals);
    };
    if ($tag eq "subject") {
        $value = encode($self,$value);
        return $self->SUPER::add($tag,$value);
    };
    return $self->SUPER::add($tag,$value);
};

sub attach {
    my $self = shift;
    die "Please don`t use attach-to-singlepart hack." if ( $self->{Attrs}->{'content-type'} !~ m{^(multipart|message)/}i );
    $self->{Mailer}->{_dataObj} = undef;
        
    if (@_ == 1) {
        my $new = $self->SUPER::attach(@_);
        die unless $new->{Mailer}; #Single param is object, object should already have Mailer.
        return $new;
    };
    
    my %params = @_;
    
    my $new = undef;
    if ($params{USEImgCache}) {
        die "Path is missing" unless $params{Path};
        my $cached = $self->{Mailer}->{imgCache}->{$params{Path}};
        if ($cached) {
            if ($cached->{Id} eq $params{Id}) {
                $new = $cached->{Part};
            }
            else {
                warn "!!! Cached part Id mismatch";
            };
        };
    };
    
    if ($new) {
        my $validate = $self->SUPER::attach($new);
        die "!!! Attach changed part!!!" unless $validate eq $new;
    }
    else {
        $new = $self->SUPER::attach(Mailer=>$self->{Mailer}, @_);
        if ($params{USEImgCache}) {
            $self->{Mailer}->{imgCache}->{$params{Path}} = {Id=>$params{Id}, Part => $new};
        };
    };
    $new;
};

sub print_simple_body {
    my ( $self, $out, $is_smtp ) = @_;
    
    $is_smtp ||= 0;
    if ( $self->{USEImgCache} ) {
        if ( $self->{'PreparedBody'.$is_smtp} ) {
            $out->print( $self->{'PreparedBody'.$is_smtp} );
        }
        else {
            my $buf  = "";
            my $io   = ( wrap MIME::Lite::IO_Scalar \$buf);
            $self->SUPER::print_simple_body($io,$is_smtp);
            $self->{'PreparedBody'.$is_smtp} = $buf;
            $out->print( $buf );
        };
        return 1;
    };
    $self->SUPER::print_simple_body($out,$is_smtp);
};

return 1;

=head
    Usage sample:

    my $nmailer = $cms->getModuleByCode('MAILER') or return $cms->error();
    $nmailer->setGroupCode('FAQ');
    
    #Common headers can be set via add(TAG,VALUE) as in MIME::Lite add();
    #Well-known headers will be encoded if needed.
    
    $nmailer->add("from",'faq@my-cool-site.rf');
    $nmailer->add("to",'unknown@nowhere.rf');
    $nmailer->add("cc",'unknown@nowhere.rf');
    $nmailer->add("bcc",'unknown@nowhere.rf');
    $nmailer->add("Subject",'My Cool Subject');
    $nmailer->add("Subject",'Поступила новая заявка с сайта');
    
    Text can be added via addPlainPart((TEXT|PARAMHASH));
    PARAMHASH description is like  MIME::Lite::build() with additional
              key Charset added.
    
    HTML can be added via addHTMLPart((HTML|PARAMHASH))
    PARAMHASH description is like  MIME::Lite::build() with additional
              keys  Charset and BaseDir added.
    addHTMLPart() will try to parse html and attach images when BaseDir
              specified
    
    Both of these can be added via addPart() with Type=>text/(plain|html)
    when Disposition ne "attacment".
    
    $nmailer->addPlainPart("Добрый день!\nВ раздел \"Вопрос-ответ\" ".
                           "сайта \"Nikolas Group\" поступил вопрос.\n");
    $nmailer->addPlainPart(Data=>$plainTextData, Encoding=>'base64');
    
    $nmailer->addHTMLPart("Simple <b>HTML</b>");
    $nmailer->addHTMLPart(Data=>"<img src=\"/img/log.jpg\"><b>Обращение:</b>\n"
                         .$message."<br><b>Контактная информация:</b>\n"
                         .$contact,
                         BaseDir=> '/web/site/htdocs',  #Ugggh, absolute path....
                         Encoding=>'base64'
                        );
    
    #Other parts, will become attachments, unless Type !~ /^text\/(html|plain)$/ and Disposition ne 'attachment'
    #//Hmmm... After writing this I begin to understand M-Soft (O-Express) MIME vision... 
    $nmailer->addPart(
        Type     => 'AUTO',
        Path     => '/web/site/htdocs/upload/13109_big_8061.jpg',
        #Filename => 'logo.gif',
        Disposition => 'attachment'
    );
    
    #Simple method to attach files:
    
    $nmailer->attachFile($absolutePath);
    
    #Use this when you are too lazy to do addPart(TYPE=>"AUTO", Path=>$path, Disposition=>'Attachment').
    #No support for Type and so on...
    
    #Most cool method is send().
    
    $nmailer->send() or return $cms->error();
    $nmailer->send('mail@mycompany.com') or return $cms->error();
    $nmailer->send(@emails) or return $cms->error();
    $nmailer->send(@emails, $opts) or return $cms->error();
    $nmailer->send($opts) or return $cms->error();
    
    $opts is HASHREF. It is passed to sender object directly.
    Well-known keys are From and To.
    
    When recipients-list is not passed as first arg or $opts->{To},
    then send() will try to get it from to,cc,bcc headers.
    $opts->{From} behaviour the same.
    
    Please don`t use both recipients-list as first arg and as To key.
    
    That`s all.

    Configuration sample:
    
    [MODULE_MAILER]
    Debug=cms    ; (cms|enable|disable)|(0|1).  'cms' is default,reading value from global. 
                 ; 'enable|disable' - force action.
                 ;  0 eq 'cms'. 1 eq 'enable' - for 'admin-friendly' behaviour
    DebugTo      ; some email-s.
    DebugMode    ; (asis,attach-recipients, attach-message)
    ForceMethod  ; For debugging.
    
    ; Default params
    Method=SMTP  ; Common mail delivery type
    From         ; Common from
    To           ; Common to, for a-s/ this is enougth
    Subject      ; Common subject
    Cc           ;
    Bcc          ;
    Notify       ; DSN request.  NEVER or combination of SUCCESS, FAILURE, DELAY (rfc1891)
    PKCS7Sign    ; future features....
    
    ;
    FAQ_Method
    FAQ_From
    FAQ_To
    FAQ_Subject
    FAQ_Notify
    FAQ_PKCS7Sign
    FAQ_SUBGROUP=COMMON1  ; Поискать неопределенные параметры в некоей общей группе, перед применением дефолтных
    
    ;
    NEWS_Method
    NEWS_From
    NEWS_To
    NEWS_Subject
    FAQ_PKCS7Sign
    FAQ_SUBGROUP=COMMON1
    ;
    COMMON1_CC="sda@nikolas.ru"               ; Хочу получать всю почту.
    ;
    ;Пример настройки отправки части почты на другой сервер
    MAILING_Method=MAILING
    %MAILING_Class=NG::Mailer::SMTP
    %MAILING_Host=mail3-lists.nikolas.ru
    %MAILING_Port=225
    %MAILING_Hello=buy.fabrikagrezkhv.ru

    ; SMTP mail delivery type
    %SMTP_Class=NG:Mailer::SMTP
    %SMTP_Host=mail.areainter.net,mail.polden.info
    %SMTP_Hello
    %SMTP_Port
    %SMTP_LocalAddr
    %SMTP_LocalPort
    %SMTP_Timeout
    %SMTP_ExactAddresses
    %SMTP_Debug
    
    ;FILE mail delivery type
    %File_Class=NG::Mailer::File
    %File_OutputDir=/some/writable/dir     ; store each mail into this dir, timestamp as filename
    %File_OutputFile=/some/writable/file   ; output all mail into this file, rewriting existing
    %File_MessageOnly=                     ; skip options dumping
=cut

