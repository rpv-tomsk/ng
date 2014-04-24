package NG::Authlib::DigestMD5;
use strict;
use Digest::MD5 qw(md5_hex);
use NGService;

sub buildHash {
    my ($class,$user,$password,$config,$existingHash) = (shift,shift,shift,shift,shift);
    
    die unless $user->{user_id};
    
    my $salt = undef;
    if ($existingHash) {
        ($salt) = split /:/, $existingHash;
    };
    
    unless ($salt) {
        $salt = generate_session_id(4);
        $salt = substr( $salt, 0, 4 );
    };
    
    exists $config->{prefix} or NG::Exception->throw('NG.INTERNALERROR',__PACKAGE__.'::buildHash(): Missing prefix');
    my $prefix = $config->{prefix} || "";
    $salt.":".Digest::MD5::md5_hex($prefix.$user->{user_id}.$password.$salt);
};

1;
