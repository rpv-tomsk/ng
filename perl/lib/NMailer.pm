package NMailer;
use strict;

use MIME::Lite;
use Net::SMTP;
use MIME::Types;

use vars qw(@ISA $server $charset);
@ISA = qw(MIME::Lite);

$server = "localhost";
$charset = "windows-1251";

  
sub mynew { #Avoid MIME::Lite:new internal usage conflict
  my $self=shift;
  my $type = shift;  # multipart/related  multipart/mixed multipart/alternative
  
  if (!defined $type) {
	$type = "multipart/alternative";
  };
  
  my %params = ();
  if ($type) {
	$params{Type} = $type;
  };

  my $obj = MIME::Lite->new(%params);
  bless ($obj);
  $obj->{_has_plain_part} = 0;
  $obj->{_has_html_part} = 0;
  
  return $obj;
};

#sub param {
#	my $self = shift;
#	my $first = shift;
#	my $type = ref $first;
#	if (!scalar(@_)){
#		croak ("Single reference arg must be hash-ref") unless $type eq 'HASH' or (ref($first) and UNIVERSAL::isa($first,'HASH'));
#		push (@_,%$first);
#	} else {
#		unshift(@_,$first);
#	};
#	@{$self->{params}} = (@{$self->{params}},@_);
#};

sub b64encode {
  my $text = shift;
  $text="=?$charset?B?".MIME::Base64::encode($text);
  $text =~ s/\n$//g;
  $text =~ s/\n/\?=\n=\?$charset\?B\?/g;
  $text .= "?=";
  return $text;
};

sub set_plain_part {
    my $self = shift;
    my $text = shift;
    
    if ($self->{_has_plain_part}) { die "set_plain_part: Plain part already exists!"; };
    if ($self->{_has_html_part})  { die "set_plain_part: Plain part must be attached before html plart!"; };
    
    if (!defined $text)           { die "set_plain_part: \$text not defined"; };
    
    $self->attach(
	Type => "text/plain; charset=$charset",
    	Data => $text,
	#    Encoding =>'base64', #Optional
    );	  
}

sub set_html_part {
    my $self = shift;
    my $text = shift;
    my $basedir = shift;

    if ($self->{_has_html_part}) { die "set_html_part: HTML part already exists!"; };

    die "set_html_part: Incorrect object Content-Type" if ( $self->attr('content-type') !~ /^(multipart)/);

  my @images = ();
  my $index = 0;
  while ($text =~ s/(<img\s.*?src=[\'\"])(.*?)([\'\"].*?>)/image\:$index/si) {
    my $image  = { 
      first=>$1,
      url=>$2,
      second=>$3,
      Id=>"image".$index,
    };
    push @images,$image;    
    $index++;
  };
  $text =~ s/image\:(\d+)/$images[$1]->{first}cid\:$images[$1]->{Id}$images[$1]->{second}/sgi;
  
  $self->attach(
    Type => "text/html; charset=$charset",
    Data => $text,
#    Encoding =>'base64', #Optional
  );
  foreach my $image (@images) {
      if ($image->{url} !~ /^http/) {
        my $filename = $image->{url};
        if ($filename =~ /[\\\/](.*)$/) {
          $filename = $1;
        }
        my ($mimetype) = MIME::Types::by_suffix($filename);
        if ($mimetype !~ /^\S+\/\S+$/) {$mimetype = "application/octet-stream"; };
	$self->attach(
          Type => $mimetype,
          Id   => $image->{Id},
          Path => $basedir.$image->{url},
          Filename=>$filename,
          Disposition=>"attachment",
	);
    };
  }
}

sub add {
  ## Overloaded method to do russian characters encoding in some of mail headers
  my $self = shift;
  my $tag = lc(shift);
  my $value =shift;
  
  if (
    ($tag eq "from")||
    ($tag eq "to")||
    ($tag eq "cc")||
    ($tag eq "bcc")||
    ($tag eq "sender")||
    ($tag eq "reply-to")) {
      my @vals = ((ref($value) and (ref($value) eq 'ARRAY'))
		  ?@{$value}
		  :($value.''));
      
      foreach my $value (@vals) {
        $value =~ s/(.*?)((?:<[a-z0-9]+(?:[-._]?[a-z0-9]+)*@[a-z0-9]+(?:\.?[a-z0-9]+[-_]*)*\.[a-z]{2,5}>))/b64encode($1)." ".$2/ei;
	#Mail::Address is bad thing...
	#my ($email) = Mail::Address->parse($value);
	#$email->[0] = b64encode($email->phrase());
	#$value = $email->format();
	#$value = b64encode($value);
      }
      return $self->SUPER::add($tag,\@vals);
  }
  
  if ($tag eq "subject") {
    $value = b64encode $value;
    return $self->SUPER::add($tag,$value);
  }
  return $self->SUPER::add($tag,$value);
}

sub send_to_list {
  my $self = shift;
  my @recipients = (@_);
  
  #if (ref($msg) ne "MIME::Lite") { die "Error: \$msg has wrong type:".ref($msg).", MIME::Lite object expected!"; };
  
  my $from = $self->get('From');
  
  require Net::SMTP;
  my $smtp = Net::SMTP->new($server);
  $smtp->mail($from); #mail from
  $smtp->recipient(@recipients, { Notify => ['NEVER'], SkipBad => 1 });  # Good
  $smtp->data();
  $smtp->datasend($self->as_string);
  $smtp->dataend();
  $smtp->quit;
};

return 1;
END{};
