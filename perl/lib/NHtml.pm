package NHtml;
use strict;
use DBI qw( looks_like_number );

BEGIN
{
        use Exporter();
        use vars qw(@ISA @EXPORT
		$quote_start_tag
		$quote_end_tag
		$cite_start_tag
		$cite_end_tag
		);
        @ISA = qw(Exporter);
        @EXPORT = qw (
			parse_cite
			parse_quote
			parse_bold
			parse_italic
			get_links
			htmlspecialchars
			unhtmlspecialchars
			nl2br
			nl2p
			parse_bbcodes
			escape_js
			strip_tags
			escape_angle_brackets
            parseBBlink
            trim
                     );
};
$cite_start_tag="";
$cite_end_tag="";

$quote_start_tag="";
$quote_end_tag="";

sub trim
{
    my $text = shift;
    $text =~ s/^\s+|\s+$// if (defined $text);
    return $text; 
};

sub strip_tags {
	my $text = shift;
	return "" if (!defined $text || $text eq "");
	$text =~ s/\<.*?\>//gi;
	return $text;
};

sub parse_quote {
    my $str = shift;   
    my $start = "";
    my $end   = "";
    while (1) {
	if ($str =~ /^(.*?)\[quote\](.*)\[\/quote\](.*?)$/is) {
    	    $start .=  $1.$quote_start_tag;
	    $str   =  $2;
	    $end   =  $quote_end_tag.$3.$end;
	    #if ($2 eq "") { last; };
	} else  {
	    $start .= $str;
	    last;
	}
    };
    return $start.$end;
}

sub escape_angle_brackets {
	my $str = shift;
	return "" if (!defined $str);
	$str =~ s/\</&lt;/gi;
	$str =~ s/\>/&gt;/gi;
	return $str;
};

sub parse_cite {
    my $str = shift;   
    my $start = "";
    my $end   = "";
    while (1) {
	if ($str =~ /^(.*?)\[cite\](.*)\[\/cite\](.*?)$/is) {
    	    $start .=  $1.$quote_start_tag;
	    $str   =  $2;
	    $end   =  $quote_end_tag.$3.$end;
	    #if ($2 eq "") { last; };
	} else  {
	    $start .= $str;
	    last;
	}
    };
    return $start.$end;
}

sub parse_bold {
    my $str = shift;
    my $res = "";
    
    while (1) {    
	if ($str =~ /^(.*?)\[b\](.*?)\[\/b\](.*)$/is) {
		$res.= (defined $1?$1:"");
		$res.= "<b>$2</b>";
		$str = (defined $3?$3:"");
	} else {
		return $res.$str;
		last;
	}
    }
    #Not reachable
    return $str;
}

sub parse_italic {
    my $str = shift;
    my $res = "";
    
    while (1) {    
	if ($str =~ /^(.*?)\[i\](.*?)\[\/i\](.*)$/is) {
		$res.= (defined $1?$1:"");
		$res.= "<i>$2</i>";
		$str = (defined $3?$3:"");
	} else {
		return $res.$str;
		last;
	}
    }
    #Not reachable
    return $str;
}

sub get_links {
    my $text=shift;
#    if ($text =~ /\[url (http|ftp|https):\/\/(\S+)\](.*?)\[\/url\]/i) {
#        $text=~ s/\[url (http|ftp|https):\/\/(\S+)\](.*?)\[\/url\]/<a href=\"$1:\/\/$2\" target="blank">$3<\/a>/gi;
#    } else {
#        $text=~ s/(http|ftp|https):\/\/(\S+)/<a href=\"$1:\/\/$2\" target="blank">$1:\/\/$2\<\/a>/gi;
#    }

    my $res = "";
    while (1) {
#        if ($text =~ /(.*?)\[url (http|ftp|https):\/\/(\S+)\](.*?)\[\/url\](.*)/i) {
         if ($text =~ /(.*?)\[url (http|ftp|https):\/\/(.*?)\](.*?)\[\/url\](.*)/si) {
    	    my $start = $1;    	    
    	    $res .= "<a href=\"$2:\/\/$3\" target=\"blank\">$4<\/a>";
    	    $text = $5;
    	    $start=~ s/(http|ftp|https):\/\/([a-z0-9]+(?:\.?[a-z0-9]+)?\.[a-z]{2,5}(\/\S?)?)/<a href=\"$1:\/\/$2\" target=\"blank\">$1:\/\/$2\<\/a>/gi;
    	    $res = (defined $start?$start:"")."$res";
    	} else {
    	    #$text=~ s/(http|ftp|https):\/\/([a-z0-9]+(?:\.?[a-z0-9]+)?\.[a-z]{2,5}(\/\S?)?)/<a href=\"$1:\/\/$2\" target="blank">$1:\/\/$2\<\/a>/gi;
    	    #$text=~ s/(http|ftp|https):\/\/([a-z0-9]+(?:\.?[a-z0-9]+)?\.[a-z]{2,5}(\/\S*)?)/<a href=\"$1:\/\/$2\" target="blank">$1:\/\/$2\<\/a>/gi;
    	    $text=~s/((?:http:\/\/|ftp:\/\/)(?:[:\w~%{}.\/?=&,\#-]+))(?<![.:])/\<a href=\"$1\"\ target=\"_blank\">$1\<\/a>/gi;	
    	    $res .= $text;
    	    last;
    	}
    }
    $text =$res;
    $text=~ s/((?:[a-z0-9]+(?:[-._]?[a-z0-9]+)?@[a-z0-9]+(?:\.?[a-z0-9]+)?\.[a-z]{2,5}))/<a href=\"mailto:$1\">$1<\/a>/gi;
    return $text;
};

sub htmlspecialchars {
	my $str = shift;
	if (!defined $str) { return undef; };
	$str =~ s/\&/&amp;/g;
	$str =~ s/\</&lt;/gi;
	$str =~ s/\>/&gt;/gi;
	$str =~ s/\'/&#039;/g;
	$str =~ s/\"/&quot;/g;
	return $str;
};

sub unhtmlspecialchars {
	my $str = shift;
	if (!defined $str) { return undef; };
	$str =~ s/&amp;/\&/g;
	$str =~ s/&lt;/\</gi;
	$str =~ s/&gt;/\>/gi;
	$str =~ s/&#039;/\'/g;
	$str =~ s/&quot;/\"/g;
	return $str;
};

sub escape_js {
    my ($var) = @_;
    return $var unless defined $var;
    $var =~ s/(["'])/\\$1/g; #"
    $var =~ s/\r/\\r/g;
    $var =~ s/\n/\\n/g;
    return $var;
}

sub nl2br {
	my $str=shift || return undef;
	$str=~ s/\r//gi;
	$str=~ s/\n/<br \/>/gi;
	return $str;
};

sub nl2p {
	my $str=shift;
	$str="<p>".$str;
	$str=~ s/\r//gi;
	$str=~ s/\n/<\/p><p>/gi;
	$str.="</p>";
	return $str;
};

sub nl2li {
	my $str=shift;
	$$str=~ s/\r//gi;
	$str=~ s/\n/<li>/gi;
	return "<ol>".$str."</ol>";
};

sub parse_bbcodes {
	my $str = shift;
	return get_links parse_italic parse_bold htmlspecialchars $str;
}

sub parseBBlink {
    my $link = shift;
    my $ret = {};
    if ($link =~ /^\[a([^\]]+)](.+)\[\/a\]$/) { #"
        my $text = $1;
        $ret->{NAME} = $2;
        while ($text =~ s/\s+([a-zA-Z]+)\=\"([^\"]*)\"//) { #"
            if ($1 eq "href") {
                return undef if (exists $ret->{HREF});
                $ret->{HREF} = $2
            }
            elsif ($1 eq "title") {
                return undef if (exists $ret->{TITLE});
                $ret->{TITLE} = $2
            }
            else {
                return undef;
            };
        };
        return undef if (!exists($ret->{HREF}));
        return $ret;
    }
    else {
        return undef;
    };
};

return 1;
END{};


