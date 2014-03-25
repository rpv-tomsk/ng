package NGService;

use strict;

use NSecure;
use POSIX;
use File::Copy;
use File::Path;
use URI::Escape;

BEGIN
{
	use Exporter();
	use vars qw(
		    @ISA 
		    @EXPORT 
		    %config
	);
	@ISA = qw(Exporter);
	@EXPORT = qw (
                 	   create_page_list
	                   get_file_extension
	                   add_prefix_to_hashref
	                   CGI_hashref
	                   copy_hashref
		       		   copy_hashref_array
                       hashref_array_sql
                       current_date
                       current_datetime
                       extract_year
                       extract_month
                       in_array
                       weekday_name
                       month_name
		     		   get_size_text
	                   compare_date
					   generate_session_id 
                       split_mas_for_column
                       short_text
                       ts
                       loadValueFromFile
                       saveValueToFile
                       array_walk
                       datetime2date
                       getURLWithParams
                       keys_exists
                       value_by_keys
                       create_json
                       trim
                       split_cost
             );
};

sub split_cost {
    my $cost = shift;
    if ($cost =~ /\./) { $cost = sprintf("%.2f", $cost);};
    my ($kop) = $cost =~ /(\.\d*)/;
    $cost =~ s/(\.\d*)//;
    $cost = reverse $cost;
    $cost =~ s/(.{3})/$1 /gi;
    $cost = reverse $cost;
    $cost .= $kop;
    
    return $cost;
};

 sub trim {
    my $string = shift;
    $string =~ s/^\s+|\s+$//;
    return $string;
 };

 sub create_json {
	my ($var, $p) = @_;
	my $t = '';
	if (ref($var) eq 'HASH') {
		$t .= '{'.join(',',map{ 
			my $t;
			if (/^(.+)_wq$/) {
				$t = "\"$1\":".create_json($var->{$_}, 1);
			} else {
				$t = "\"$_\":".create_json($var->{$_}, $p);
			}
			$t
		}keys%$var).'}'
	} elsif (ref($var) eq 'ARRAY') {
		$t .= '['.join(',',map{create_json($_, $p)}@$var).']';
	} else {
		if ($p) {
			$t .= $var;
		} else {
			if ( looks_like_number($var) ) {
				$t .= $var;
			}
            elsif (!defined $var) {
                $t .= "null";
            }
            else {
				$var =~ s/\"/\\\"/g;
				$var =~ s/[\x0a\x0d]{1,2}/\\n/g;
				$t .= "\"$var\"";
			}
		}
	}
	$t	
 }


sub keys_exists {
    my $hash = shift;
    die "not hash reference in hash_exists()" unless (ref $hash eq "HASH");
    my @keys = (@_);
    return 0 unless scalar @keys;
    my @allkeys = ();
    my @tmpkeys = ();
    foreach my $k (@keys) {
        @tmpkeys = split /\./,$k;
        push @allkeys, @tmpkeys;
    };
    undef @tmpkeys;
    
    my $exist = 1;
    foreach my $k (@allkeys) {
        die "not hash reference in hash_exists()" unless (ref $hash eq "HASH");
        if (!exists $hash->{$k}) {
            $exist = 0;
            last;
        };
        $hash = $hash->{$k};
    };
    undef @allkeys;
    return $exist;
};

sub value_by_keys {
    my $hash = shift;
    die "not hash reference in hash_exists()" unless (ref $hash eq "HASH");
    my @keys = (@_);
    return 0 unless scalar @keys;
    my @allkeys = ();
    my @tmpkeys = ();
    foreach my $k (@keys) {
        @tmpkeys = split /\./,$k;
        push @allkeys, @tmpkeys;
    };
    undef @tmpkeys;
    
    foreach my $k (@allkeys) {
        die "not hash reference in hash_exists()" unless (ref $hash eq "HASH");
        return undef if (!exists $hash->{$k});
        $hash = $hash->{$k};
    };
    return $hash;
};

sub getURLWithParams {
    my $url = shift;
    my @params = @_;
    
    $url .= "&" if ($url =~ /\?\S*[^&]$/);
    $url .= "?" if ($url !~ /\?/);
    
    foreach my $param (@_) {
        next unless $param;
        #die $param;
        my $ref = ref $param;
        if ($ref eq "HASH") {
            foreach my $key (keys %$param) {
                $url .= sprintf("%s=%s&", $key, uri_escape($param->{$key}));        
            };
        }
        else {
            use Carp;
            croak "Incorrect param-value pair \"$param\" in getURLWithParams()" if($param !~ /[^\?\&\=\s]\=[^\?\&\=\s]/);  #TODO: do it more intellectual        
            $url .= $param."&";
        };
    }
    $url =~ s/\&$//;
    return $url;
};

sub ts($) {  
    my %hs=('а'=>'a', 'б'=>'b', 'в'=>'v', 'г'=>'g', 'д'=>'d', 'е'=>'e', 'ё'=>'jo', 'ж'=>'zh', 'з'=>'z', 'и'=>'i', 'й'=>'j', 'к'=>'k', 'л'=>'l', 'м'=>'m', 'н'=>'n',  'о'=>'o', 'п'=>'p', 'р'=>'r', 'с'=>'s', 'т'=>'t' , 'у'=>'u', 'ф'=>'f', 'х'=>'kh', 'ц'=>'c', 'ч'=>'ch', 'ш'=>'sh', 'щ'=>'shh', 'ъ'=>'', 'ы'=>'y', 'ь'=>'',  'э'=>'eh', 'ю'=>'ju', 'я'=>'ja',
            'А'=>'A', 'Б'=>'B', 'В'=>'V', 'Г'=>'G', 'Д'=>'D', 'Е'=>'E', 'Ё'=>'JO', 'Ж'=>'ZH', 'З'=>'Z', 'И'=>'I', 'Й'=>'J', 'К'=>'K', 'Л'=>'L', 'М'=>'M', 'Н'=>'N',  'О'=>'O', 'П'=>'P', 'Р'=>'R', 'С'=>'S', 'Т'=>'T' , 'У'=>'U', 'Ф'=>'F', 'Х'=>'KH', 'Ц'=>'C', 'Ч'=>'CH', 'Ш'=>'SH', 'Щ'=>'Shh', 'Ъ'=>'', 'Ы'=>'Y', 'Ь'=>'',  'Э'=>'EH', 'Ю'=>'JU', 'Я'=>'JA');  
    my $z=shift;  
    foreach my $key (keys %hs) {
        $z =~ s@[$key]@$hs{$key}@gi;
    };
    return $z;
};

sub  short_text
{
 my %args=(@_);
 if(is_empty $args{'str'})
   {
    return undef;
   };
 if(!is_valid_id($args{'len'}))
   {
    return $args{'str'};
   };
 if(is_empty($args{'delimeter'}))
   {
    $args{'delimeter'}=" ";
   };
 if(length($args{'str'})>$args{'len'})
   {
    $args{'str'} = substr($args{'str'},0,(rindex($args{'str'},$args{'delimeter'},$args{'len'})));
    $args{'str'}=~s/[^a-zA-Zа-яА-Я0-9]$//;
    if(!is_empty($args{'end'}))
      {
       $args{'str'}.=$args{'end'};
      };
   };
 return $args{'str'};
};
                                                   

sub array_walk {
	my $arrayref = shift;
	my $subref = shift;
	my @params = (@_);
	die if (!ref $arrayref || ref $arrayref ne 'ARRAY');
	foreach my $el (@{$arrayref}) {
		&$subref($el,@params);
	};
};

sub split_mas_for_column
 {
  my %args=(@_);
  my $cols=$args{cols};
  my $tmp=$args{mas};
  my @mas1=@{$tmp};
  my @mas=(@mas1);
  if(scalar @mas % $cols != 0)
    {
     for(my $i=1;$i<=@mas % $cols;$i++)
        {
         push @mas, {};
        };
    };
  my $count=scalar(@mas);
  my $rows=int(($count-1)/$cols)+1;
  my @res;
  for(my $i=0;$i<$rows;$i++)
     {
      my @tmp;
      for(my $j=0;$j<$cols;$j++)
        {
         my $index=$i*$cols+$j;
         if ($index==$count) {last;}
         push @tmp,$mas[$index];
        };
      my $tmp1;
      $tmp1->{row}=\@tmp;
      push @res,$tmp1;
     };

  return @res;
};
            

sub generate_session_id 
{
  my $length =shift||32;
  my @simbols = ( 0..9, 'a'..'z', 'A'..'Z');
  my $key = join("", @simbols[ map {rand @simbols }( 1..$length) ] );
  return $key;
};

#---------------------------------------
sub compare_date #dd.mm.yyyy
{
	my $date1=shift;
	my $date2=shift;
	if(!is_valid_date($date1) || !is_valid_date($date2))
	  {
	  	return 2;
	  };
	$date1=~/(\d{2})\.(\d{2})\.(\d{4})/;
	my $tmp1=$3.$2.$1;  
	$date2=~/(\d{2})\.(\d{2})\.(\d{4})/;
	my $tmp2=$3.$2.$1;
	if ($tmp1 eq $tmp2){
        return 0;
	}
	elsif($tmp1>$tmp2) {
        return -1; 
	}
	elsif($tmp1<$tmp2) {
        return 1;
	}
	else {
        return 2;
	};        
};
#---------------------------------------
sub get_size_text {
    my $size = shift;
    if ($size<1) { return ""; };
    if ($size<= 9999) { return sprintf("%d байт",$size); };
    if ($size<= 1022976) { return sprintf("%d Кб",$size/1024); };
    if ($size<= 1047527424) { return sprintf("%.2f Mб",$size/1048576); };
    return sprintf("%.2f Гб",$size/1073741824);
}

sub weekday_name {
	my $day = shift;
	my $case = shift || 0;
	$case += 0;
	$day += 0;
	my @days = (
		["понедельник"],
		["вторник"],
		["среда"],
		["четверг"],
		["пятница"],
		["суббота"],
		["воскресенье"]
	);
	if ($day>0 && $day<=7) {
		return $days[$day-1][$case];
	} else {
		return "";
	};
};

sub month_name {
	my $month = shift;
	my $case = shift || 0;
	$case += 0;
	$month += 0;
	my @months = (
		["январь","января"],
		["февраль","февраля"],
		["март","марта"],
		["апрель","апреля"],
		["май","мая"],
		["июнь","июня"],
		["июль","июля"],
		["август","августа"],
		["сентябрь","сентября"],
		["октябрь","октября"],
		["ноябрь","ноября"],
		["декабрь","декабря"]
	);
	if ($month>0 && $month<=12) {
		return $months[$month-1][$case];
	} else {
		return "";
	};	
};

sub in_array {
	my $el = shift;
	my $arrref = shift;
	my @array = @{$arrref};
	foreach my $array (@array) {
		if ($el == $array) {
			return 1;
		};
	};
	return 0;
};

#--------------------------------------
sub create_page_list {
    my %args=(@_); 
    my $size=$args{size};  if ($size==0){$size=1;}  # Число записей
    my $page=$args{page};			    # Текущая страница
    my $urlMask = (exists($args{'urlmask'})) ? $args{'urlmask'} : '';
    my $el_on_page=$args{onpage};		    # Число записей на странице
    my $page_display=$args{page_display}||$args{onlist};	    # Отображать число ссылок
   
    my $url = $args{url} || "?";
    if ($url =~ /\/$/) {
	$url=$url."?";
    } else {
	if (($url !~ /\&$/) && ($url !~ /\?$/)) { $url=$url."&"; };
    } 
    my $page_name = $args{page_name} || "page";
    
    my $page_count=int(($size-1)/$el_on_page)+1;
 #   my $npd=int(($page-1)/$page_display);
 #   my $fp=$npd*$page_display+1;
 #   my $ep=($npd+1)*$page_display;
 #   if ($ep>$page_count){$ep=$page_count;}

    my $half_page_display=int($page_display/2);

    my $fp = $page-$half_page_display;
    my $ep = $page+$half_page_display;

    if ($fp<1) {
        $fp=1;
        if ($fp+$page_display<=$page_count) { $ep=$fp+$page_display; } else {$ep = $page_count; };
    };
    if ($ep>$page_count) {
        $ep=$page_count;
        if ($ep-$page_display>=1) { $fp = $ep-$page_display; } else { $fp = 1; };
    };    

    my @pages;
	if ($fp>1) {
	    my $tmp;
        $tmp->{PAGE_NAME}=$page_name;
	    $tmp->{PAGE}=$fp-1;
	    $tmp->{PREV_LIST}=1;
		$tmp->{URL}=$url;
		if($urlMask) {
                      $tmp->{PAGEURL} = $urlMask;
		      $tmp->{PAGEURL} =~ s/{page}/$tmp->{PAGE}/;
		}
		else {
		    $tmp->{PAGEURL}=$url.$page_name."=".$tmp->{PAGE};
	        };	    
	    push @pages, $tmp;
	}
    if ($page>1) {
            my $tmp;
            $tmp->{PAGE_NAME}=$page_name;
            $tmp->{PAGE}=$page-1;
            $tmp->{IS_PREV}=1;
	        $tmp->{URL}=$url;
            if($urlMask) {
                $tmp->{PAGEURL} = $urlMask;
	        $tmp->{PAGEURL} =~ s/{page}/$tmp->{PAGE}/;
	    }
	    else {
	        $tmp->{PAGEURL}=$url.$page_name."=".$tmp->{PAGE};
	    };	    
            push @pages, $tmp;
    };
    for (my $i=$fp;$i<=$ep;$i++) {
            my $tmp;
            $tmp->{PAGE}=$i;
            if (defined $page && $page==$i) {
	         $tmp->{CURRENT}=1;
	    } else {
		 $tmp->{NORMAL}=1;
	    };
            $tmp->{PAGE_NAME}=$page_name;
            $tmp->{URL}=$url;
	    if($urlMask) {
                $tmp->{PAGEURL} = $urlMask;
                $tmp->{PAGEURL} =~ s/{page}/$tmp->{PAGE}/;
            }
	    else {
	        $tmp->{PAGEURL}=$url.$page_name."=".$tmp->{PAGE};
	    };	    
            push @pages, $tmp;
    };
    if ($page<$page_count) {
            my $tmp;
            $tmp->{PAGE_NAME}=$page_name;
            $tmp->{PAGE}=$page+1;
            $tmp->{IS_NEXT}=1;
    	    $tmp->{URL}=$url;
    	    if($urlMask) {
                $tmp->{PAGEURL} = $urlMask;
	        $tmp->{PAGEURL} =~ s/{page}/$tmp->{PAGE}/;
	    }
	    else {
	        $tmp->{PAGEURL}=$url.$page_name."=".$tmp->{PAGE};
	    };	    
    	    push @pages, $tmp;
    };
	if ($ep<$page_count) {
	    my $tmp;
            $tmp->{PAGE_NAME}=$page_name;
	    $tmp->{PAGE}=$ep+1;
	    $tmp->{NEXT_LIST}=1;
            $tmp->{URL}=$url;
            if($urlMask) {
                $tmp->{PAGEURL} = $urlMask;
	        $tmp->{PAGEURL} =~ s/{page}/$tmp->{PAGE}/;
	    }
	    else {
	        $tmp->{PAGEURL}=$url.$page_name."=".$tmp->{PAGE};
	    };	    
	    push @pages, $tmp;
	}

    if (scalar (@pages)==1){return ();}
    foreach (@pages) {
	$_->{IS_NEXT} = 0 unless ($_->{IS_NEXT});
	$_->{IS_PREV} = 0 unless ($_->{IS_PREV});
	$_->{NORMAL} = 0 unless ($_->{NORMAL});
	$_->{CURRENT} = 0 unless ($_->{CURRENT});
    };
    return @pages;
};

#--------------------------------------
sub get_file_extension {
	my $file = shift;
	if ( $file =~ /.*\.([^\.]*?)$/ ) {
            return $1;
        }
    return undef;
};

#--------------------------------------          
sub add_prefix_to_hashref
{
	my $hashref = shift;
	my $prefix = shift;
	my @keys = keys %{$hashref};
	foreach my $key (@keys)
	{
		$hashref->{$prefix.$key}=$hashref->{$key};
		delete $hashref->{$key};
	};
};
#--------------------------------------
sub CGI_hashref
{
	my $q = shift;
	my @params = $q->param();
	my $hashref = undef;
	map {$hashref->{$_} = $q->param($_);} @params;
	return $hashref;
};

#--------------------------------------
sub copy_hashref
{
	my $hashref = shift;
	my $hashref_res = {};
	my @keys = keys %{$hashref};
	foreach my $key (@keys)
	{
		$hashref_res->{$key} = $hashref->{$key};
	};
	return $hashref_res;	
};
         
#-------------------------------------
sub copy_hashref_array
{
	my $arrayref = shift;
	my $field = shift;
	my $value = shift;
	my @array = @{$arrayref};
	my @data = ();
	for (my $i=0;$i<=$#array;$i++)
	{
		my $res = copy_hashref($array[$i]);
		if (defined $field && $res->{$field}==$value)
		{
			$res->{current} = 1;
		};
		push @data, $res;
	};
	return @data;
};

sub hashref_array_sql {
	my $fields = shift;
	my $data = shift;
	return () if (is_empty($fields));
	my @data = ();
	my @fields = split /\,/,$fields;
	for (my $i=0;$i<=$#fields;$i++)	{
		push @data, $data->{$fields[$i]};			
	};
	return @data;
};

sub datetime2date {
	my $datetime = shift;
	if (defined $datetime && $datetime =~ /^(\d{1,2})\.(\d{1,2})\.(\d{4})\s+(\d{1,2})\:(\d{1,2})(?:\:(\d{1,2}))?$/) {
		return undef unless (0 <= $4) and ($4  < 24);
		return undef unless (0 <= $5) and ($5 <= 59);
		return undef unless (defined $6) and (0 <= $6) and ($6 <= 59);
		if (NSecure::validate($3,$2,$1)) {
			return "$1.$2.$3";
		};
	};
	return undef;
}

sub current_datetime {
	my $time = shift || time(); 
	return strftime("%d.%m.%Y %H:%M:%S",localtime($time));	
};

sub current_date {
	my $time = shift || time(); 
	return strftime("%d.%m.%Y",localtime($time));	
};

sub extract_year {
	my $date = shift;
	if ($date =~/^(\d{1,2})\.(\d{1,2})\.(\d{4})$/) { return $3; } else { die "Incorrect date format"; }
}

sub extract_month {
	my $date = shift;
	if ($date =~/^(\d{1,2})\.(\d{1,2})\.(\d{4})$/) { return $2; } else { die "Incorrect date format"; }
}

use Fcntl qw( :DEFAULT );
my $Fetch_Flags = O_RDONLY | O_BINARY;
my $Store_Flags = O_WRONLY | O_CREAT | O_TRUNC | O_BINARY;

sub loadValueFromFile {
    my $file = shift;
    
    my $buf = "";
    my $read_fh;
    unless ( sysopen( $read_fh, $file, $Fetch_Flags ) ) {
        return wantarray?(undef, "Can't open file: $!"):undef;
    };
    my $size_left = -s $read_fh;
    while (1) {
        my $read_cnt = sysread( $read_fh, $buf, $size_left, length $buf );
        if ( defined $read_cnt ) {
            last if $read_cnt == 0;
            $size_left -= $read_cnt;
            last if $size_left <= 0;
        }
        else {
            warn "read_file '$file' - sysread: $!";
            return wantarray?(undef, "Error reading file: $!"):undef;
        };
    };
    close ($read_fh);
    return $buf;
}

sub saveValueToFile {
    my $data = shift;
    my $file = shift;
    my $dir = $file;
    if ($dir =~ /[\/\\]$/) {
        return wantarray?(undef,"Не указано имя файла"):undef;
    }
    $dir =~ s/([^\/\\]+)$//;
    eval { mkpath($dir); };
    if ($@) {
        $@ =~ /(.*)at/s;
        return wantarray?(undef,"Ошибка при создании директории: $1"):undef;
    }
    unless (-w $dir) {
        return wantarray?(undef,"Недостаточно привилегий для записи файла в директорию"):undef;
    }
    
    my $write_fh;
    unless ( sysopen( $write_fh, $file, $Store_Flags ) ) {
        #croak "write_file '$file' - sysopen: $!";
        return wantarray?(undef,"Can't write file: $!"):undef;
    }
    my $size_left = length($data);
    my $offset    = 0;
    do {
        my $write_cnt = syswrite( $write_fh, $data, $size_left, $offset );
        unless ( defined $write_cnt ) {
            die "write_file '$file' - syswrite: $!";
        }
        $size_left -= $write_cnt;
        $offset += $write_cnt;
    } while ( $size_left > 0 );
    close ($write_fh);
    return 1;
}



return 1;
END{};
