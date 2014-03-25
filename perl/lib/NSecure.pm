package NSecure;

use strict;

# use OtherModules;

BEGIN
{
	use Exporter();
	use vars qw(
		    @ISA 
		    @EXPORT 
	);
	@ISA = qw(Exporter);
	@EXPORT = qw (
			is_valid_id
			is_valid_email
			is_valid_link
			is_valid_domain
			is_valid_referer
			is_int
			is_empty
			is_float
			is_valid_date
			is_valid_timestamp
			is_valid_image
			is_valid_datetime
			looks_like_number
	             );
};

#-------------------------------------

sub looks_like_number {
    my @new = ();
    for my $thing(@_) {
        if (!defined $thing or $thing eq '') {
            push @new, undef;
        }
        else {
            push @new, ($thing =~ /^([+-]?)(?=\d|\.\d)\d*(\.\d*)?([Ee]([+-]?\d+))?$/) ? 1 : 0;
        }
    }
    return (@_ >1) ? @new : $new[0];
}

sub is_valid_id {
	my $number = shift;
	$number = "" if !defined $number;
	$number=~ s/\s//gi;
	return $number=~ /^[1-9]\d*$/;
};

sub is_valid_email {
	my $email = shift;
	$email = "" if !defined $email;
	return $email =~ /^(?:[a-z0-9]+(?:[-.]?[_a-z0-9]+)?@[a-z0-9][a-z0-9\-]*(?:\.?[a-z0-9][a-z0-9\-]*)?\.[a-z]{2,5})$/i;
}

sub is_valid_link {
	my $link = shift;
	$link = "" if !defined $link;
	return $link =~ /^(http|https|ftp)\:\/\/[a-z0-9\-]+(?:\.[a-z0-9\-]+)*\.[a-z]{2,5}(\/.*)*$/i;
	#return $link =~ /^(http|https|ftp)\:\/\//i;
}

sub is_valid_domain {
	my $link = shift;
	$link = "" if !defined $link;
	return $link =~ /^[a-z0-9\-]+(?:\.[a-z0-9\-]+)*\.[a-z]{2,5}/i;
}

sub is_valid_referer {
    my $url = shift;
    return 1 if ( $url =~ m"^(ht|f)tp(s?)\:\/\/[a-zA-Z0-9\-\._]+(\.[a-zA-Z0-9\-\._]+){2,}(\/?)([a-zA-Z0-9\-\.\?\,\'\/\\\+&amp;%\$#_]*)?$"i );
	return 0;
}

sub is_int {
	my $number = shift;
	$number = "" if !defined $number;
	$number=~ s/\s//gi;
	return $number=~ /^\-{0,1}[0-9]\d*$/;
};

sub is_empty {
	my $str = shift;
	$str = "" if !defined $str;
	return $str!~ /\S/;
};

sub is_float {
	my $number = shift;
	$number = "" if !defined $number;
	$number=~ s/\s//gi;
	return $number=~ /^\-{0,1}\d+[\.\,]{0,1}\d*$/;
};

sub is_valid_image {
	my $filename = shift;
	return $filename =~ /\.(jpg|bmp|tiff|jpeg|ico|gif)$/i;
}

#  is_valid_date internal functions from Date::Simple version 1.03
my @days_in_month = (
 [0,31,28,31,30,31,30,31,31,30,31,30,31],
 [0,31,29,31,30,31,30,31,31,30,31,30,31],
);

sub leap_year {
    my $y = shift;
    return (($y%4==0) and ($y%400==0 or $y%100!=0)) || 0;
}

#sub days_in_month ($$) {
#    my ($y,$m) = @_;
#    return $days_in_month[leap_year($y)][$m];
#}

sub validate ($$$) {
    my ($y, $m, $d)= @_;
    # any +ve integral year is valid
    return 0 if (!defined $y || $y != abs int $y);
    return 0 unless defined $m and 1 <= $m and $m <= 12;
    return 0 unless 1 <= $d and $d <= $days_in_month[leap_year($y)][$m];
    return 1;
}

sub is_valid_date {
	my $date = shift;
	#if (defined $date || $date =~ /^(\d{1,2})[\.\-](\d{1,2})[\.\-](\d{4})$/) {
	if (defined $date && $date =~ /^(\d{1,2})\.(\d{1,2})\.(\d{4})$/) {
		#use Date::Simple ();   ## 
		#return Date::Simple->new("$3-$2-$1");
		return validate($3,$2,$1)==1;
	} else {
		return 0;
	};
}

sub is_valid_datetime {
	my $date = shift;
	if (defined $date && $date =~ /^(\d{1,2})\.(\d{1,2})\.(\d{4})\s+(\d{1,2})\:(\d{1,2})(?:\:(\d{1,2}))?$/) {
		return 0 unless (0 <= $4) and ($4  < 24);
		return 0 unless (0 <= $5) and ($5 <= 59);
		return 0 unless (defined $6) and (0 <= $6) and ($6 <= 59);
		return validate($3,$2,$1)==1;
	} else {
		return undef;
	};
}

sub is_valid_timestamp {
	my $date = shift;
	#if (defined $date || $date =~ /^(\d{1,2})[\.\-](\d{1,2})[\.\-](\d{4})$/) {
	if (defined $date && $date =~ /^(\d{1,2})\.(\d{1,2})\.(\d{4}) (\d{1,2})\:(\d{1,2})(?:\:(\d{1,2}))?$/) {
		#use Date::Simple ();   ## 
		#return Date::Simple->new("$3-$2-$1");
		return 0 unless (0 <= $4) and ($4  < 24);
		return 0 unless (0 <= $5) and ($5 <= 59);
		return 0 unless (defined $6) and (0 <= $6) and ($6 <= 59);
		return validate($3,$2,$1)==1;
	} else {
		return undef;
	};
}

return 1;
END{};
