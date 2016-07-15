package NG::Gearman::Application;
use strict;

use NG::Application;
our @ISA = qw/NG::Application/;

sub new {
    my $class = shift;
    my $self = {};
    bless $self, $class;
    $self->init(@_);
    return $self;
};

sub init {
    my $app = shift;
    
    my $DBClass  = $NG::Gearman::Application::config::DB;
    
    my $db = undef;
    if ($DBClass) {
        eval "require $DBClass; 1;" or die $@;
        $db = $DBClass->new();
    };

    my %param = ();  #TODO: DocRoot, TmplDir, CfgDir
    $param{DBObject} = $db;
    $param{SiteRoot} = $NG::Gearman::Application::config::SiteRoot;
    $param{Debug}    = $NG::Gearman::Application::config::Debug;
    
    $app->SUPER::init(%param);
    if ($NG::Gearman::Application::config::openSiteCfg) {
        $app->openConfig() or die $app->getError('Error loading config');
    };
    
    $app;
};

sub GEARMAN_can {
    my ($app, $function) = (shift, shift);
    my $method = "gearman_$function";
    return $app->can($method);
};

sub GEARMAN_run {
    my ($app, $job) = (shift, shift);
    
    my $db = $app->db();
    if ($db) {
        $db->connect() or die $db->errstr();
    };
    
    my $method = "gearman_".$job->{func};
    $app->$method($job);
};

sub GEARMAN_stop {
    my ($app) = (shift);
    return 0;
}

1;