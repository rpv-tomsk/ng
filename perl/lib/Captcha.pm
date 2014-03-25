
 package Captcha;
 
 use strict;
 use Exporter;

 use GD;
 use Digest::MD5;
 
 our $VERSION    = 1.00;
 our @ISA        = qw(Exporter);
 
 our @EXPORT = qw/
		&create_captcha
		&get_captcha
		&generate_new_captcha
		&get_captcha_code
	/;
	
 my $u = 'u';
 
 sub generate_new_captcha
 {
	my $code = shift;
	my $session = $u->cms->getCookiedSession;	
	my $imgKey = 'captcha_'.$code;
	my $length = $code;
	$code = join '', map { ''.int(rand(9)) } (1..$length);
	$session->param($imgKey, $code);
	my $files = $session->param($imgKey.'_file');	
	my $k = {};
	my $files_ = read_index_file();
	foreach my $filePath(split ',', $files)
	{
		if (-e $filePath)
		{
			unlink $filePath;
			delete $files_->{$filePath};
		}
		else
		{
			$k->{$filePath} ++;
		}
	}
	write_index_file($files_);
	$session->param($imgKey.'_file', join(',', keys%$k) );
	$session->flush();
 }
 
 sub get_captcha_code
 {
	my $code = shift;
	my $session = $u->cms->getCookiedSession;		
	my $imgKey = 'captcha_'.$code;
	return $session->param($imgKey); 
 }
 my $_indexFile;
 sub get_index_file_name
 {
	unless ($_indexFile)
	{
		$_indexFile = $u->cms->{_docroot} . $u->cms->confParam('Captcha.imagesPath') . '/index';
	}
	return $_indexFile;
 }

 sub read_index_file
 {
	my $indexFile = get_index_file_name();
	my $files = {};
	if (open my $fh, $indexFile)
	{
		binmode $fh; 
		local $/ = undef; 
		my $body = <$fh>; 
		close $fh;
		my @a = split ',', $body;
		while (@a)
		{
			my $fn = shift @a;
			my $mtime = shift @a;
			$files->{$fn} = $mtime;
		}
	}
	return $files;
 }
 
 sub write_index_file
 {
	my ($files) = @_;
	my $indexFile = get_index_file_name();
	open OUT, ">".$indexFile;
	binmode OUT; 
	local $/ = undef; 
	print OUT join(',', map { ( $_, $files->{$_} ) } keys%$files );
	close OUT;
 }
 
 sub insert_new_file
 {
	my ($filePath) = @_;
	my $files = read_index_file();
	$files->{$filePath} = ((stat($filePath))[9]);
	write_index_file($files);	
 } 
 
 sub get_captcha
 {
	my $code = shift;
	my $width  = shift || 170;
	my $height = shift || 30;
	my $fontSize = shift || 14;
	my $rc = shift;
	my $needLines = shift;
	
	if ( 1 && (int(rand(20)) eq '1') )
	{
		# cleanup olders
		my $files = read_index_file();
		my $ctime = time;
		foreach my $key (keys%$files)
		{
			if ( ($files->{$key} + 60 * 15) < $ctime )
			{
				unlink $key;
				delete $files->{$key};
			}
		}
		write_index_file($files);
	}
	
	my $session = $u->cms->getCookiedSession;	
	
	my $imgKey = 'captcha_'.$code;
	my $length = $code;
	$code = $session->param($imgKey);
	unless (length $code)
	{
		$code = join '', map { ''.int(rand(9)) } (1..$length);
	}
	$session->param($imgKey, $code);
	
	my $imagesPath = $u->cms->confParam('Captcha.imagesPath') . '/';
	
	my $id = Digest::MD5::md5_hex($code.$width.$height.$fontSize.$rc.$needLines);
	
	my $filePath = $imagesPath.$id.'.png';
	unless (-e $u->cms->{_docroot} . $filePath)
	{
		my $im = create_captcha($code, $width, $height, $fontSize, $rc, $needLines);
		open my $out, ">" . $u->cms->{_docroot} . $filePath; 
		local $/ = undef; 
		binmode $out; 
		print $out $im->png; 
		close $out;
		insert_new_file($u->cms->{_docroot} . $filePath);
	}
	my $files = $session->param($imgKey.'_file');
	my $k = {};
	foreach my $a (split ',',$files)
	{
		$k->{$a} ++;
	}
	$k->{$u->cms->{_docroot} . $filePath}++;
	$session->param($imgKey.'_file', join(',', keys%$k) );
	$session->flush();
	return $filePath;
	
 }

 sub create_captcha
 {
	my $code = shift;
	my $width  = shift || 170;
	my $height = shift || 30;
	my $fontSize = shift || 14;
	my $randomColor = shift;
	my $needLines = shift;
	
    my $im = new GD::Image($width, $height);

    #my $white = $im->colorAllocate(255, 255, 255);
	my $white = $im->colorAllocate(235, 235, 235);
    my $black = $im->colorAllocate(0, 0, 0);

    $im->rectangle(0, 0, $width-1, $height-1, $black);

	my $cr = int(rand(3));

	my $lc = $u->cms->confParam('Captcha.linesColor');
	my $lll;
	if (length $lc)
	{
		my ($r, $g, $b) = $lc =~ /^\#(..)(..)(..)/;
		$lll = $im->colorAllocate(hex($r), hex($g), hex($b));
	}

    if ( $needLines )
	{
		for (1..110)
		{
			my @c;
			for(0..2)
			{
				if ($_ eq $cr) { push @c, 255 }
				else { push @c, int(rand(80)) + 170 }
			}

			$cr++; $cr=0 if $cr eq 3;
			my $color = $im->colorAllocate(@c);

			my $x = int(rand($width - 12))+1;
			my $y = int(rand($height - 12))+1;
			my ($xx, $yy);
			if (rand(20) > 10)
			{
				$xx = 10;
				$yy = int(rand(10));
			}
			else
			{
				$yy = 10;
				$xx = int(rand(10));
			}
			if ($lll)
			{
				$im->setStyle($lll);
			}
			else
			{
				$im->setStyle($color);
			}
			$im->line($x, $y, $x+$xx, $y+$yy, gdStyled);
		}
	}
	
    my $x  = 16;
    my @a  = (-1,-0.5,0,0.5,1);
    my @yo = (-6,-4,0,+1,+2);
	
	#my 
	#0B2D3A
	
	# my $latColor = $im->colorAllocate(18, 55, 68);
	my $latColor = $im->colorAllocate(50, 85, 97);

	my $cc = $u->cms->confParam('Captcha.color');
	if (length $cc)
	{
		$randomColor = undef;
		my ($r, $g, $b) = $cc =~ /^\#(..)(..)(..)/;
		$latColor = $im->colorAllocate(hex($r), hex($g), hex($b));
	}
	
    for my $lnum (1..length($code))
    {		
		my @c;
		if ($randomColor)
		{
			for my $iter (0..2)
			{
				if ($iter eq $cr) { push @c, 255 }
				else { push @c, int(rand(180)) }
			}
			$cr++; $cr=0 if $cr eq 3;
		}
		my $color;
		if ($randomColor)
		{
			$color = $im->colorAllocate(@c);
		}
		else
		{
			$color = $latColor;
		}
		my $char = substr($code, $lnum-1,1);
		my $i = int(rand(5));
		$im->stringFT(
			$color,
			$u->cms->confParam('Captcha.fontPath'),
			$fontSize,
			$a[$i],
			$x,
			23 + $yo[$i],
			$char
		);
		$x += 27;
    }
	return $im	
 }
 
 1;