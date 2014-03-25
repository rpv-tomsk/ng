package NG::Forum::BBCodes;
use strict;
use constant WITHOUT_CLOSE_TAG=>1;

sub _parse_code {
    my $text = shift;
    my $bb_code = shift;
    my $tag = shift;
    my $without_close_tag = shift || 0;
    
    my $reg = "";
    
    if ($without_close_tag) {
        $text =~ s/\[$bb_code(.*?)\/\]/<$tag $1\/>/gis;
    }
    else {
        $reg = sprintf('^(.*?)\[%s(.*?)\](.*?)\[\/%s\](.*)$', $bb_code, $bb_code);
    	while ($text =~ /$reg/is) {
            my $str_pre = defined $1? $1: "";
            my $attr = defined $2? $2: "";
            my $content = defined $3? $3: "";
            my $str_post = defined $4? $4: "";
            
            $text = sprintf("%s<%s %s bbcode=\"1\">%s</%s>%s", $str_pre, $tag, $attr, $content, $tag, $str_post);
    	};
    }
    return $text;   
};

sub parse_bold {
    my $text = shift;
    return _parse_code($text, "b", "b");
};

sub parse_italic {
    my $text = shift;
    return _parse_code($text, "i", "i");
};

sub parse_cite {
    my $text = shift;
    return _parse_code($text, "cite", "cite");
};

sub parse_underline {
    my $text = shift;
    return _parse_code($text, "u", "u");
};

sub parse_link {
    my $text = shift;
    return _parse_code($text, "link", "a");
};

sub parse_image {
    my $text = shift;
    $text =~ s/\[image\s+src="(.*?)".*?\]/<a href="$1" target="_blank" bbcode="1">Image<\/a>/gis;
    return $text;
#     return _parse_code($text, "image", "img", WITHOUT_CLOSE_TAG);
};

sub parse_bb {
    my $text = shift;
    return parse_cite(parse_bold(parse_italic(parse_underline(parse_link(parse_image($text))))));
};

1;