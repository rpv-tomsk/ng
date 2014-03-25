package NG::Module::List::Filters::Calendar;

use strict;
use NG::Module::List::Filters;
use vars qw(@ISA);
@ISA = qw(NG::Module::List::Filters);

use NSecure;
use NGService;
use NG::Calendar;
use Date::Simple;

sub init {
	my $self = shift;
	my %args = (@_);
    $self->{_day}   = undef;
    $self->{_month} = undef;
    $self->{_year}  = undef;
	$self->{_calendar} = undef;
    $self;
};

sub load {
    my $self = shift;
    
    return $self->error("List::Filters::Calendar: Отсутствует значение параметра FIELD") unless $self->{_config}->{FIELD};

    my $pObj = $self->parent();
    my $q = $pObj->q();
    
    my $p_day = $q->param("_day")+0;
    my $p_month = $q->param("_month")+0;
    my $p_year = $q->param("_year")+0;

    if ($p_year && $p_month) {
        return $self->error("В параметрах календаря некорректная дата")  if $p_day && !is_valid_date(sprintf("%02d.%02d.%04d",$p_day,$p_month,$p_year));
        return $self->error("В параметрах календаря некорректный месяц") if $p_month<1 || $p_month>12;
        return $self->error("В параметрах календаря некорректный год")   if $p_year != abs int $p_year; 
        $self->{_day} = $p_day if $p_day;
        $self->{_month} = $p_month;
        $self->{_year} = $p_year;
    };
    return 1;
};

sub beforeOutput {
    my $self = shift;
    my $pObj = $self->parent();
    my $config = $self->config();
	my $cms = $pObj->cms();

    #Определяем дату на календаре
    my $current = Date::Simple->new;
    my $day   = $self->{_day}   || $current->day;
    my $month = $self->{_month} || $current->month;
    my $year  = $self->{_year}  || $current->year;
    
    #В ссылках фильтра нужны параметры OrderParam, FKParam и параметры прочих фильтров.
    my @params = ();
	my @db_where = ();
	my @db_params = ();
    foreach my $subf (@{$pObj->{_filters}}) {
        next if $subf eq $self;
        push @params, $subf->getURLParams();
		my $where = $subf->getWhereCondition();
		push @db_where, $where if (!is_empty($where));
		
		my @param = $subf->getWhereParams();
        if (scalar @param && ref $param[0] eq "ARRAY") {
            push @db_params, @{$param[0]};
        }
        else {
            push @db_params,@param;
        };
    };
    
    #Так же надо забрать значение из полей типа фильтр
    foreach my $field (@{$pObj->{_fields}}) {
        next if $field->{TYPE} ne "filter";
        push @db_where, $field->{FIELD}."=?";
        push @db_params, $field->{VALUE};
    };
    my $baseUrl = getURLWithParams($pObj->getBaseURL().$pObj->getSubURL(),$pObj->getOrderParam(),$pObj->getFKParam(),@params);
	my $cal = $cms->getObject("NG::Calendar",{month=>$month,year=>$year,day=>$day});
    $cal->visual({ 
        'CLASS1'      => '',
        'CLASS2'      => '',
        'CLASS3'      => '',
        'CLASS4'      => '',
        'CLASS4W'     => '',
        'CLASS5'      => '',
        'CLASS6'      => '',
        'CLASS7'      => '',
        'CLASS_ACTIVE'=> 'class=current_date',
        'CLASS_NODAY' => '',
        'IMBACK'      => '',
        'IMFORW'      => '',
    });
	$cal->initdbparams(
    	db    => $pObj->db(),
    	table => $pObj->getListSQLTable(),
    	date_field => $config->{FIELD},
		where => join(" and ",@db_where),
		params => \@db_params
    );
    
    my $url_fmt = getURLWithParams($baseUrl,"_year=%Y&_month=%m&_day=%d");
    $cal->{ACTION} = $baseUrl;
    $cal->{URL_FMT} = $url_fmt;
    $cal->{URL_NAVIG_FMT} = $url_fmt; 

    $cal->set_db_minmaxdate();
    $cal->set_db_days(); 
    
    $cal->{FILTER_DESCRIPTION} = "Не выбран";
    if ($self->{_year} && $self->{_month}) {
        if ($self->{_day}) {
            $cal->{FILTER_DESCRIPTION} = "Выбрана дата: ".sprintf("%02d.%02d.%4d",$self->{_day},$self->{_month},$self->{_year});
        }
        else {
            $cal->{FILTER_DESCRIPTION} = "Выбран месяц: ".sprintf("%s %4d",$cal->get_month_name($self->{_month}),$self->{_year});
        };
    };

    my @cparams = ();
    foreach my $p (@params) {
        next if (is_empty($p));
        my ($name,$value) = split /\=/,$p;
        push @cparams, {name=>$name,value=>$value};
    };
    $cal->{CPARAMS} = \@cparams;

    my $next_year = $year;
    my $next_month = $month+1;
    if ($next_month>12) {
        $next_month = 1;
        $next_year++;
    };
    my $prev_year = $year;
    my $prev_month = $month-1;
    if ($prev_month<1) {
        $prev_month = 12;
        $prev_year--;
    };    
    $cal->{NEXT_URL} = getURLWithParams($baseUrl,"_month=".$next_month."&_year=".$next_year);
    $cal->{PREV_URL} = getURLWithParams($baseUrl,"_month=".$prev_month."&_year=".$prev_year);
    $cal->{CURRENT_URL} = getURLWithParams($baseUrl,"_month=".$month."&_year=".$year);
	
	my %calendar = (
        ACTION => $cal->{ACTION},
        HTML => $cal->calendar_month(),
        MONTH_OPTIONS => $cal->get_month_options(),
        YEAR_OPTIONS => $cal->get_year_options(),
        CURRENT_MONTH => $cal->get_month_name($cal->month()),
        CURRENT_YEAR => $cal->year(),
        NEXT_URL => $cal->{NEXT_URL},  
        PREV_URL => $cal->{PREV_URL},
        CURRENT_URL => $cal->{CURRENT_URL},
        FILTER_DESCRIPTION => $cal->{FILTER_DESCRIPTION},
        CPARAMS => $cal->{CPARAMS}
    );
	my $template = $cms->gettemplate("admin-side/common/calendar.tmpl");
    $template->param(
        CALENDAR => \%calendar,
    );
	$cms->pushRegion({CONTENT=>'<div id="calendar_div">'.$template->output().'</div>', REGION=>"LEFT", WEIGHT=>-10});
};

sub getURLParams {
    my $self = shift;
    
    my $params = "";
    if ($self->{_year} && $self->{_month}) {
        $params =  "_day=".$self->{_day}."&" if ($self->{_day});
        $params .= "_month=".$self->{_month}."&_year=".$self->{_year};
    };
    return $params;
};

sub getWhereParams {
    my $self = shift;
    
    if ($self->{_year} && $self->{_month}) {
        my $db = $self->parent()->db();
        my $dObj = Date::Simple->new($self->{_year},$self->{_month}, $self->{_day} || 1);
        if ($self->{_day}) {
            return ($db->date_to_db($dObj->format("%d.%m.%Y")),
            $db->date_to_db($dObj->next->format("%d.%m.%Y")));
        }
        else {
            return ($db->date_to_db($dObj->format("%d.%m.%Y")),
            $db->date_to_db(($dObj + Date::Simple::days_in_month($self->{_year},$self->{_month}))->format("%d.%m.%Y")));
        };
    };
    return ();
};

sub getWhereCondition {
    my $self = shift;
    if ($self->{_year} && $self->{_month}) {
        my $config = $self->config();
        return $config->{FIELD}.">=? and ". $config->{FIELD}." <?";
    };
    return "";
};

sub fieldValue {
	my $self = shift;
	return {} unless $self->{_year} && $self->{_month} && $self->{_day};
	return {$self->{_config}->{FIELD} => $self->{_day}.".".$self->{_month}.".".$self->{_year}};
};

sub useForm {
    return 0;
};

return 1;
