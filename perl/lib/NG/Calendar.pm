package NG::Calendar; 

$NG::Calendar::VERSION = "0.01";

use strict;
use Date::Simple;
use Carp;

my %days_en   = ( 'Mon' => 0, 
               'Tue' => 1, 'Wed' => 2, 
               'Thu' => 3, 'Fri' => 4, 
               'Sat' => 5, 'Sun' => 6  );


my %days_r   = (  'Пн' => 0, 
               'Вт' => 1, 'Ср' => 2, 
               'Чт' => 3, 'Пт' => 4, 
               'Сб' => 5, 'Вс' => 6 );

my %months_r = (  1 => 'Январь', 2  => 'Февраль', 3  => 'Март',
                4 => 'Апрель', 5  => 'Май', 6  => 'Июнь',
                7 => 'Июль', 8  => 'Август', 9  => 'Сентябрь',
               10 => 'Октябрь', 11 => 'Ноябрь', 12 => 'Декабрь' );

my %months_en = (  1 => 'January', 2  => 'February', 3  => 'Marth',
                4 => 'April', 5  => 'May', 6  => 'June',
                7 => 'Jule', 8  => 'August', 9  => 'Semptember',
               10 => 'October', 11 => 'November', 12 => 'December' );



sub new {
  my $self = {};
  bless $self, shift;
  $self->_init(@_);
  return $self;
}

sub _init {
  my $self = shift;
  # Для формирования списка годов    
  $self->{_min_year} = undef;
  $self->{_max_year} = undef;
  
  my $valid_day = Date::Simple->new;
  my $ref = shift;
  if (defined $ref && ref $ref eq 'HASH') {
  
    if ($ref->{english})
    {
        %months_r = %months_en;
        %days_r = %days_en;
    };
  
    my $month = exists $ref->{month} ? $ref->{month} : undef;
    my $year  = exists $ref->{year}  ? $ref->{year}  : undef; 
    my $day   = exists $ref->{day}   ? $ref->{day}   : undef;

    $month ||= $valid_day->month;
    $year  ||= $valid_day->year;
    $day   ||= 1;

    $valid_day = $self->_date_obj($year, $month, $day);
    $valid_day = defined $valid_day ? $valid_day : Date::Simple->new;
   
    #TODO: надо выставлять отдельным методом
    $self->{_min_year} = exists $ref->{min_year} ? $ref->{min_year} : undef;
    $self->{_max_year} = exists $ref->{max_year} ? $ref->{max_year} : undef; 
    
    $self->{_q} = $ref->{q};
  }
  $self->set_date($valid_day->day,$valid_day->month,$valid_day->year);

  # Навигатор месяц влево - месяц вправо
  $self->{'CLASS_NAVIG'} = "calendar-month";
  $self->{'CLASS_NAVIG_LEFT'} = "navig_arrow_left";
  $self->{'CLASS_NAVIG_RIGHT'} = "navig_arrow_right";
  
  $self->{'URL_FMT'} = "?day=%d&month=%m&year=%Y";
  $self->{'URL_NAVIG_FMT'} = "?day=%d&month=%m&year=%Y";
  $self;
}

sub month      { $_[0]->{month}          } # month in numerical format
sub year       { $_[0]->{year}           } # year in YYYY form
sub day	       { $_[0]->{day}		 } # (c) rpv
sub _spacer    { return ""               } # the filler for the first few entries
sub _the_month { @{ $_[0]->{the_month} } } # this is the list of hashrefs.


sub get_month_name { return $months_r{$_[0]->{month}}; };

sub set_last_col {
  my $self = shift;
  $self->{'last_col'} = shift;
}

sub set_date {
  my $self = shift;
  my ($d,$m,$y) = @_;
  
  my $valid_day = $self->_date_obj($y, $m, $d) or croak("set_date: invalid date specified");

  $self->{day} = $valid_day->day;  
  $self->{month} = $valid_day->month;
  $self->{year}  = $valid_day->year;
  #$self->{_date_obj} = $valid_day;  ### this is todo..  
  $self->{the_month} = $self->_days_list($self->{month}, $self->{year});
}

sub visual {
  my $self = shift;
  my $ref  = shift or return;
  ref $ref eq 'HASH' or return;

  my %visual = %{ $ref };
  $self->{'CLASS1'} = $ref->{'CLASS1'};
  $self->{'CLASS2'} = $ref->{'CLASS2'};
  $self->{'CLASS3'} = $ref->{'CLASS3'};
  $self->{'CLASS4'} = $ref->{'CLASS4'};
  if(defined $ref->{'CLASS4W'} && $ref->{'CLASS4W'} ne ''){
     $self->{'CLASS4W'} = $ref->{'CLASS4W'};
  }else{
     $self->{'CLASS4W'} = $ref->{'CLASS4'};
  }
  $self->{'CLASS5'} = $ref->{'CLASS5'};
  $self->{'CLASS6'} = $ref->{'CLASS6'};
  $self->{'CLASS7'} = $ref->{'CLASS7'};
  $self->{'CLASS_WEEK'} = $ref->{'CLASS_WEEK'};
  $self->{'IMBACK'} = $ref->{'IMBACK'};
  $self->{'IMFORW'} = $ref->{'IMFORW'};
  $self->{'CLASS_NODAY'} = $ref->{'CLASS_NODAY'};
  $self->{'CLASS_ACTIVE'}= $ref->{'CLASS_ACTIVE'};

  # Classes for get_month_scroller  
  $self->{'CLASS_NAVIG'}       = $ref->{'CLASS_NAVIG'} if defined $ref->{'CLASS_NAVIG'};
  $self->{'CLASS_NAVIG_LEFT'}  = $ref->{'CLASS_NAVIG_LEFT'} if defined $ref->{'CLASS_NAVIG_LEFT'};
  $self->{'CLASS_NAVIG_RIGHT'} = $ref->{'CLASS_NAVIG_RIGHT'} if defined $ref->{'CLASS_NAVIG_RIGHT'};
}
# 4-4w zagolovki
# 3 vnut table
# 1 vnesh table
# 2 vnesh td 
# td vnut

sub action {
  my $self = shift;
  my $action  = shift or return;
  my $param  = shift;

  $self->{'ACTION'} = $action;
  $self->{'ACTION_PARAM'} = $param;
}


sub daily_info {
  my $self = shift;
  my $ref  = shift or return;
  ref $ref eq 'HASH' or return;
  my $day  = $self->_date_obj($self->year, $self->month, $ref->{'day'}) or return;
  my %info = %{ $ref };
  delete $info{'day'};
  foreach my $day_ref ($self->_the_month) {
    next unless $day_ref && $day_ref->{date}->format() eq $day->format();
    $day_ref->{$_} = $info{$_} foreach keys %info;
    last;
  }
}

sub _row_elem {
  my $self = shift;
  my $ref  = shift or return $self->_spacer;
  return $ref if $ref eq $self->_spacer;
  my $day = exists $ref->{day_link} 
          ? "<A HREF='".$ref->{day_link}."' ".$self->{CLASS7}.">".$ref->{date}->day."</A>"
          : $ref->{date}->day;
  my $elem = $day;	  

#  my $elem = $q->start_table . $q->Tr($q->td($day));
#  my %info = %{ $ref };
#  foreach my $key (keys %info) {
#    next if ($key eq 'date' or $key eq 'day_link');
#    my $method = "_$key";
#    $elem .= $self->can($method) 
#           ? $q->Tr($q->td($self->$method($info{$key})))
#           : $q->Tr($q->td($info{$key}));
#  }
#  $elem .= $q->end_table;

  return $elem;
}

sub _table_row {
  my $self = shift;
  my @week = @_; my @row;
#  push @row, "<div ".$self->{'CLASS_ROW'}." >";
  push @row, $self->_row_elem($_) foreach @week;
#  push @row, "</div>";
  return @row;
}

sub to_html { $_[0]->calendar_month }

sub get_month_scroller {
  my $self = shift;
  my %args = (@_);
 
  my $month = $self->month;
  my $year  = $self->year;

  my $maxyear = $self->{_max_year};
  my $minyear = $self->{_min_year};
  my $maxmonth = $self->{_max_month};
  my $minmonth = $self->{_min_month};
  
  
  my $enable_prev = 0;
  my $enable_next = 0;
  my $no_limits = 1;

  if (defined $maxyear && defined $maxmonth && defined $minyear && defined $minmonth) {
    $enable_prev=((($month>$minmonth) && ($year==$minyear))||($year>$minyear));
    $enable_next=((($month<$maxmonth) && ($year==$maxyear))||($year<$maxyear));
    $no_limits = 0;
  }

  my $next_date_obj = $self->_date_obj($year,$month,1);
  my $prev_date_obj = $next_date_obj->prev;
  $next_date_obj += Date::Simple::days_in_month($year,$month);

  my $prev_navig_fmt = defined $self->{URL_NAVIG_FMT_PREV}?$self->{URL_NAVIG_FMT_PREV}:$self->{URL_NAVIG_FMT}."&monthmove=back";
  my $next_navig_fmt = defined $self->{URL_NAVIG_FMT_NEXT}?$self->{URL_NAVIG_FMT_NEXT}:$self->{URL_NAVIG_FMT}."&monthmove=fwd";
  
  my $prev_url=$prev_date_obj->format($prev_navig_fmt);
  my $next_url=$next_date_obj->format($next_navig_fmt);
  my $mnth;
  $mnth.="<div class=\"$self->{CLASS_NAVIG}\"\>";
  if    ($no_limits)   { $mnth.= "<a href=\"#\" onclick='document.location.href=\"$prev_url\";'><img src=\"/img/arrow-prew.gif\" width=\"10\" height=\"10\" alt=\"\"></a>";}
  elsif ($enable_prev) { $mnth.= "<a href=\"$prev_url\"><img src=\"/img/arrow-prew.gif\" width=\"10\" height=\"10\" alt=\"\"></a>"; }
  #else                 { $mnth.= "<a href=\"$prev_url\"><img src=\"/img/arrow-prew.gif\" width=\"10\" height=\"10\" alt=\"\"></a>";  }
  $mnth.="<strong>".$months_r{$self->month}." ".$self->year."</strong>";
  if    ($no_limits)   { $mnth.= "<a href=\"#\" onclick='document.location.href=\"$next_url\";'><img src=\"/img/arrow-next.gif\" width=\"10\" height=\"10\" alt=\"\"></a>";  }
  elsif ($enable_next) { $mnth.= "<a href=\"$next_url\"><img src=\"/img/arrow-next.gif\" width=\"10\" height=\"10\" alt=\"\"></a>"; }
  #else                 { $mnth.= "<a href=\"$next_url\"><img src=\"/img/arrow-next.gif\" width=\"10\" height=\"10\" alt=\"\"></a>";  }
  $mnth.="</div>";
  return $mnth;
}

sub get_year_options {
    my $self = shift;
    my %ref = (@_);

    my $year  = $self->year;
  
    my $minyear = exists $ref{minyear} ? $ref{minyear} : $self->{_min_year};
    my $maxyear = exists $ref{maxyear} ? $ref{maxyear} : $self->{_max_year};
  
    if ((!defined $minyear)||($minyear>$year)) {$minyear = $year; };
    if ((!defined $maxyear)||($maxyear<$year)) {$maxyear = $year; };

    my $selects ="";
    for (my $i=$minyear;$i<=$maxyear;$i++) {
        if ($year==$i) {
            $selects.="<option value='$i' selected>$i</option>";
        } else {
            $selects.="<option value='$i'>$i</option>";
        };
    };
    return $selects;
}

sub get_month_options {
    my $self = shift;
    my %args = (@_);

    my $month = $self->month;

    my $selects ="";
    for (my $i=1;$i<=12;$i++) {
        my $name=$i<10?"0".$i:$i;
	if ($i==$month) {
            $selects.="<option value=\"$name\" selected>$months_r{$i}</option>";
        } else {
            $selects.="<option value=\"$name\">$months_r{$i}</option>";
        };
    };
  return $selects;
}

sub calendar_month {
  my $self = shift;
  my @seq  = $self->_the_month;
  my $cal  = "\n<table ". $self->{CLASS3}.">\n";
    $cal .= "\t<tr>\n";	   
    foreach (sort { $days_r{$a} <=> $days_r{$b} } keys %days_r){
	if($days_r{$_} eq $days_r{'Sat'} || $days_r{$_} eq $days_r{'Sun'}){
	    $cal .= "\t\t<th ".$self->{CLASS4W}.">$_</th>\n" ;
	}else{
	    $cal .= "\t\t<th ".$self->{CLASS4}.">$_</th>\n" ;
	}
    }
    $cal .= "\t</tr>\n";	   

  while (@seq) {
    my @week_row = $self->_table_row(splice @seq, 0, 7);

    my $current_week = 0;

    foreach my $tmps (@week_row){ # подсветка недели
	if ($tmps eq "") {
	    next;
	}
        if ((defined $self->{day})&&($tmps eq $self->{day} || $tmps=~ />$self->{day}</)) {
            $current_week = 1;
        }
    }

    if ($current_week == 1){
        $cal .= "\t<tr ".$self->{CLASS_WEEK}.">\n";
    }else{
        $cal .= "\t<tr>\n";
    }

#    if ((defined $self->{day})) {
#        $cal .= "\t<tr ".$self->{CLASS_WEEK}.">\n";
#    } else {
#        $cal .= "\t<tr>\n";
#    }

    foreach my $tmps (@week_row){
	if ($tmps eq "") {
	    $cal .= "\t\t<td ".$self->{CLASS_NODAY}."></td>\n";
	    next;
	}
        if ((defined $self->{day})&&($tmps eq $self->{day} || $tmps=~ />$self->{day}</)) {
    	    $cal .= "\t\t<td ".$self->{CLASS_ACTIVE}.">$tmps</td>\n";
    	} else {
    	    $cal .= "\t\t<td ".$self->{CLASS5}.">$tmps</td>\n";
	}
    }
    if (scalar(@week_row)<7) {
	for (my $i=scalar(@week_row);$i<7;$i++) {
	 $cal.="<td ".$self->{CLASS_NODAY}.">&nbsp;</td>\n"
	};
    }
    $cal .= "\t</tr>\n";
  }
  $cal .= "\n</table>\n";
  #$cal = "\n<table ". $self->{CLASS1}.">\n\t<tr>\n\t\t<td ".$self->{CLASS2}."></td>\n\t</tr>\n\t<tr>\n\t\t<td>$cal</td>\n\t</tr>\n</table>";
  #die $cal;
  return $cal;
}

sub get_month_hash {
    my $self = shift;
    my $last_col = $self->{'last_col'};
    my @seq  = $self->_the_month;
    my %month;
    my $week_num = 0;
    my $week_counter = 0;
    my $day_counter = 0;

    my $cal  = "\n<table ". $self->{CLASS3}.">\n";
#  $cal .= "\t<tr>\n";	   
    foreach (sort { $days_r{$a} <=> $days_r{$b} } keys %days_r){
        if($days_r{$_} eq $days_r{'Sat'} || $days_r{$_} eq $days_r{'Sun'}){
          push @{$month{'header'}}, $_;
        }
    }
#  $cal .= "\t</tr>\n";	   

    while (@seq) {
        my @week_row = $self->_table_row(splice @seq, 0, 7);

        my $current_week = 0;
        $day_counter = 0;

        # формируем дни недели 
        foreach my $tmps (@week_row){
            if ($tmps eq "") {
                $month{'weeks'}[$week_counter]{'days'}[$day_counter]={ is_empty => 1 };
#                $cal .= "\t\t<td ".$self->{CLASS_NODAY}."></td>\n";
                $day_counter++;
                next;
            }
            if ((defined $self->{day})&&($tmps eq $self->{day} || $tmps=~ />$self->{day}</)) {
                $month{'weeks'}[$week_counter]{'days'}[$day_counter]={ day => $tmps, active => 1 };
                $month{'weeks'}[$week_counter]{'current_week'} = 1;
#                $cal .= "\t\t<td ".$self->{CLASS_ACTIVE}.">$tmps</td>\n";
            } else {
                $month{'weeks'}[$week_counter]{'days'}[$day_counter]={ day => $tmps };
            }
            $day_counter++;
        }
        if (scalar(@week_row)<7) {
            for (my $i=scalar(@week_row);$i<7;$i++) {
                $month{'weeks'}[$week_counter]{'days'}[$i]={ is_empty => 1 };
#                $cal.="<td ".$self->{CLASS_NODAY}.">&nbsp;</td>\n"
            };
#            $day_counter++;
        }

        if ($self->{'last_col'}){
            $month{'weeks'}[$week_counter]{'days'}[7]={ day => $self->{'last_col'} };
        }

        $week_counter++;
    }
#    $cal .= "\n</table>\n";
#$cal = "\n<table ". $self->{CLASS1}.">\n\t<tr>\n\t\t<td ".$self->{CLASS2}."></td>\n\t</tr>\n\t<tr>\n\t\t<td>$cal</td>\n\t</tr>\n</table>";
#die $cal;
    return \%month;
}

sub _generate_months {
  my ($class, $year, $ref) = @_;
  my @year;
  for my $month  (1 .. 12) {
    my $cal = $class->new({ 'month' => $month, 'year'  => $year });
    if (defined $ref->{$month}) {
      my %links = %{ $ref->{$month} };
      foreach my $day (keys %links) {
        $cal->daily_info({ 'day'      => $day,
                           'day_link' => $links{$day},
        });
      }
    }
    push @year, $cal;
  }
  return @year;
}

=comment
sub calendar_year {
  my ($class, $ref) = @_;
  my $year = $ref->{year};
  my $when = defined $year 
           ? Date::Simple->new($year, 1, 1)
           : Date::Simple->new;
     $when = defined $when ? $when : Date::Simple->new;
  $year = $when->year;
  my @year = $class->_generate_months($year, $ref);
  my $year_string;
  my $q = CGI->new;
  while (@year) {
    my @qrtr = map { $_->calendar_month } splice @year, 0, 3;
    s/$year//g for @qrtr;
    $year_string .= $q->start_table . $q->Tr($q->td({valign => 'top'}, [@qrtr])) 
                 .  $q->end_table   . $q->br;
  }
  my $pic = defined $ref->{'pin_up'} ? $ref->{'pin_up'} : "";
  $pic = $q->Tr($q->td({ align => 'center' }, $q->img({ src  => $pic }))) if $pic; 
  $year_string = $q->start_table . $pic . $q->th($year)
               . $q->Tr($q->td($year_string)) 
               . $q->end_table;
  return $year_string;
}
=cut

sub _date_obj { Date::Simple->new($_[1], $_[2], $_[3]) }

# here is the format of what is returned from this call. Let us say a list of 
# hashrefs, so that I can tag lots of things in with it. Ick, I know, but this
# is just a messing-about at the mo. And a hashref, mmmm, makes me think of 
# an object is needed here. A Day object if I thieved an idea from somewhere else.

sub _days_list {
  my $self = shift;
  my ($month, $year) = @_;
  my $start = $self->_date_obj($year, $month, 1);
  my $end   = $start + 31;
     $end   = $self->_date_obj($end->year, $end->month, 1);
  my $tmp=$start->day_of_week();
  if($tmp==0)
    {
     $tmp=7;
    };
  my @seq   = map $self->_spacer, (2 .. $tmp);

  push @seq, { 'date' => $start++ } while ($start < $end);
  #die $seq[0]->{'date'}->month;
  return \@seq;
}

#
#  DB functions
#

sub parse_db_date {
  my $self = shift;
  my $date = shift;
  $date = $self->{_db}->date_from_db($date);
  if ($date =~/^(\d{1,2})\.(\d{1,2})\.(\d{4})$/) { return ($1,$2,$3); };
  croak "Incorrect date format";
}

sub initdbparams {
  my $self = shift;
  my %args = (@_);
  
  $self->{_db}   = exists $args{db}   ? $args{db}   : croak("initdbparams: dbh not defined");
  $self->{_dbh} = $self->{_db}->dbh();
  $self->{_dbtable} = exists $args{table} ? $args{table} : croak("initdbparams: table not defined");
  $self->{_dbdate_field} = exists $args{date_field} ? $args{date_field} : croak("initdbparams: date_field not defined");
  $self->{_dbwhere} = exists $args{where} ? $args{where} : "";
  $self->{_dbparams} = exists $args{params} ? $args{params} : [];
  die "initdbparams(): params key is not ARRAYREF" if (ref $self->{_dbparams} ne "ARRAY");
}

sub set_db_minmaxdate {
  my $self = shift;
  #Параметры подключения к БД
  my $dbh = $self->{_dbh};
  my $table = $self->{_dbtable};
  my $field = $self->{_dbdate_field};
  my $where = $self->{_dbwhere};
  my @params = @{$self->{_dbparams}};
  # Находим минимальную и максимальную даты
  my $sql="select min($field) as mindate,max($field) as maxdate from $table ".(($where)?" where $where":"");
  my $sth=$dbh->prepare($sql) or die $DBI::errstr;
  $sth->execute(@params) or die $DBI::errstr;
  my($mindate,$maxdate)=$sth->fetchrow();
  $sth->finish();
 
  if (!defined $mindate || $mindate eq "")
    {
     $self->{_min_year} = undef;
     $self->{_max_year} = undef;
     $self->{_min_month} = undef;
     $self->{_max_month} = undef;
     $self->{_min_day} = undef;
     $self->{_max_day} = undef;
     return undef;
    };  
  
  my ($minday,$minmonth,$minyear) = $self->parse_db_date($mindate);
  my ($maxday,$maxmonth,$maxyear) = $self->parse_db_date($maxdate);
  
  #Сохраним значения для дальнейшего использования... TODO: надо бы переделать интерфейс:)
  $self->{_min_year} = $minyear;
  $self->{_max_year} = $maxyear;
  $self->{_min_month} = $minmonth;
  $self->{_max_month} = $maxmonth;
  $self->{_min_day} = $minday;
  $self->{_max_day} = $maxday;
}

sub set_db_days {   # Находим дни, на которые выводить активные ссылки
  my $self = shift;
  #Параметры подключения к БД
  my $dbh = $self->{_dbh};
  my $table = $self->{_dbtable};
  my $field = $self->{_dbdate_field};
  my $where = $self->{_dbwhere};
  my $strftime_fmt = "%d.%m.%Y";
  my @params = @{$self->{_dbparams}};
  
  my $fmt = $self->{'URL_FMT'};
  
  my $month = $self->month;
  my $year  = $self->year;
  # Высчитываем границы периода 
  my $next_date = $self->_date_obj($year,$month,1) or die "Invalid date";
  my $prev_date = $next_date->prev;
  $next_date += Date::Simple::days_in_month($year,$month);
  #делаем запрос  
  my $sql="select distinct $field as day from $table where $field>? and $field<? ".(($where)?" and $where":"");
  my $sth=$dbh->prepare_cached($sql) or die $DBI::errstr;
  $sth->execute($self->{_db}->date_to_db($prev_date->format($strftime_fmt)),$self->{_db}->date_to_db($next_date->format($strftime_fmt)),@params) or die $DBI::errstr;
  while(my ($date) = $sth->fetchrow_array()) {
    my ($d,$m,$y) = $self->parse_db_date($date);
    my $valid_date = Date::Simple->new($y,$m,$d) or die "Invalid date";
    $self->daily_info({ 'day'      => $valid_date->day,
                        'day_link' => $valid_date->format($fmt),
                     }
    );
  };
  $sth->finish();  
}

