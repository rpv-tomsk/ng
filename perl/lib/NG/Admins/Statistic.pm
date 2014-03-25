package NG::Admins::Statistic;
use strict;

use NGService;
use NSecure;
use NG::Module;
use NG::Admins;
use NG::DBlist;
use NG::Calendar;
use POSIX;

use vars qw(@ISA);

sub AdminMode {
    use NG::Module;
    @ISA = qw(NG::Module);	
};

sub getModuleTabs {
	return [
		{HEADER=>"Статистика",URL=>"/"},
	];
};

sub moduleAction {
    my $self = shift;
    my $is_ajax = shift;
	    
	my $q = $self->q();
	my $app = $self->app();
	my $dbh = $self->db()->dbh();

    my $action = $q->url_param('action') || $q->param('action') || "";
	my $page = $q->param('page');
    my $full_stat = $q->param('full_stat') || 0;

	my $day   = $q->param('day');   $day   ||=0; $day+=0;   $day   = undef if !is_valid_id($day); 
	my $month = $q->param('month'); $month ||=0; $month+=0; $month = undef if (!is_valid_id($month) || $month > 12);
	my $year  = $q->param('year');  $year  ||=0; $year+=0;  $year  = undef if !is_valid_id($year); 
    
    my $date = $year . "-" . $month . "-" . $day;

    my $onpage = 225;
    my $onlist = 225;
    my $pages;
    my $pages_stat;
    my $where;
    my $cal_where;

    my $class_week;
    my $class_month;

	my $current_date = $self->db()->date_to_db(strftime("%d.%m.%Y",localtime()));

    if ($action eq '' and ($month != 0) and ($year != 0) and ($day eq '')){
        $action = 'pages_stat_monthly';
        $date   = $self->db()->date_to_db("1.".$month.".".$year);
        $day    = 1; 
    } elsif ($action eq ''){
        $action = 'pages_stat_daily';
        $date   = $current_date;
        $day    = strftime("%d",localtime()); 
        $month  = strftime("%m",localtime()); 
        $year   = strftime("%Y",localtime()); 
    }

    if ($action eq 'pages_stat_daily'){

        $where = "date = ?";

        if ($full_stat == 0){
            $where .= " and ((is_param = FALSE) OR (url = '/'))";
        }

        my $dblist = NG::DBlist->new(
                db     => $self->db(),
                table  => "counter_daily",
                fields => "url, title, page_hits, section_hits, s_section_hits, 
                page_hosts, section_hosts, s_section_hosts, tomsk_page_hits, 
                tomsk_section_hits, tomsk_s_section_hits, tomsk_page_hosts, tomsk_section_hosts, 
                tomsk_s_section_hosts",
                order  => "order by url asc",
                page   => $page,
                onpage => $onpage,
                onlist => $onlist,
                where  => $where
                );

        $dblist->open($date) or die $DBI::errstr;
        $pages_stat = $dblist->data();
        $pages = $dblist->pages();
    }

    if ($action eq 'pages_stat_weekly'){

        $where = "week=(extract (WEEK from date ?))";

        if ($full_stat == 0){
            $where .= " and ((is_param = FALSE) OR (url = '/'))";
        }

        $class_week='class=current-day';

        my $dblist = NG::DBlist->new(
                db     => $self->db(),
                table  => "counter_weekly",
                fields => "url, title, page_hits, section_hits, s_section_hits, 
                page_hosts, section_hosts, s_section_hosts, tomsk_page_hits, 
                tomsk_section_hits, tomsk_s_section_hits, tomsk_page_hosts, tomsk_section_hosts, 
                tomsk_s_section_hosts",
                order  => "order by url asc",
                page   => $page,
                onpage => $onpage,
                onlist => $onlist,
                where  => $where
                );

        $dblist->open($date);
        $pages_stat = $dblist->data();
        $pages = $dblist->pages();
    }

    if ($action eq 'pages_stat_monthly'){

        $where = "month=(extract (MONTH from date ?))";

        if ($full_stat == 0){
            $where .= " and ((is_param = FALSE) OR (url = '/'))";
        }

        $class_month='class=current-day';

        my $dblist = NG::DBlist->new(
                db     => $self->db(),
                table  => "counter_monthly",
                fields => "url, title, page_hits, section_hits, s_section_hits, 
                page_hosts, section_hosts, s_section_hosts, tomsk_page_hits, 
                tomsk_section_hits, tomsk_s_section_hits, tomsk_page_hosts, tomsk_section_hosts, 
                tomsk_s_section_hosts",
                order  => "order by url asc",
                page   => $page,
                onpage => $onpage,
                onlist => $onlist,
                where  => $where
                );

        $dblist->open($date);
        $pages_stat = $dblist->data();
        $pages = $dblist->pages();
    }

    # строим календарь

	my $url_fmt=$self->{'_current_url'}."?year=%Y&month=%m&day=%d&action=$action";
	my $cal=NG::Calendar->new({month=>$month,year=>$year,day=>$day});
	$cal->visual({ 
		'CLASS1'      => '',
		'CLASS2'      => '',
		'CLASS3'      => '', # вся таблица
		'CLASS4'      => '',
		'CLASS4W'     => '',
		'CLASS5'      => $class_month, # все дни
		'CLASS6'      => '',
		'CLASS7'      => '',
		'CLASS_WEEK'  => $class_week, # подсветка строки недели
		'CLASS_ACTIVE'=> 'class=current-day',
		'CLASS_NODAY' => 'class=another-month',
		'IMBACK'      => '',
		'IMFORW'      => '',
	});
	$cal->{URL_FMT} = $url_fmt;
    $cal->{URL_NAVIG_FMT} = $self->{'_current_url'}."?year=%Y&month=%m&action=$action";

    if ($full_stat){
        $cal_where = undef;
    }else{
        $cal_where = "is_param = FALSE";
    }

    $cal->initdbparams(
            db=>$self->db(),
            table=>"counter_daily",
            where=>$cal_where,
            date_field=>"date",
            db_date_fmt=>"yyyy-mm-dd", # dd-mm-yyyy yyyy-mm-dd dd.mm.yyyy
            );
    $cal->set_db_minmaxdate();
    $cal->set_db_days();
	$cal->set_last_col("month=1");

#use Data::Dumper;
#die Dumper($cal->get_month_hash());
    my $month_hash=$cal->get_month_hash();

	## вывод в шаблон.
	$self->opentemplate("admin-side/statistic/statistic.tmpl") or return $self->showError();
	my $template = $self->template();

    $template->param(
            PAGES_STAT      => $pages_stat,
            PAGES           => $pages,
            ACTION          => $action,
            MONTH           => $month,
            DAY             => $day,
            YEAR            => $year,
            FULL_STAT       => $full_stat,
            CALENDAR        => $cal->calendar_month,
            MONTH_weeks     => $month_hash->{'weeks'},
            YEAR_OPTIONS    => $cal->get_year_options(),
            MONTH_OPTIONS   => $cal->get_month_options(),
            CALENDAR_ACTION => $action,
            MONTHSCROLLER   => $cal->get_month_scroller(),
    );

    return $self->output($self->tmpl()->output()); 		
}; 

return 1;

