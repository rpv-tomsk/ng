package NG::Bootstrap;
use strict;
use NG::Exception;
use POSIX qw(strftime);

sub cgi_error {
    my $msg = shift;
    print "Status: 500\n";
    print "Content-Type: text/plain; charset=windows-1251;\n\n";
    print $msg;
    exit;
};

sub importX {
    my $pkg = shift;
    my %param = @_;
    my $class = $param{App};
    my $dbclass = $param{DB};
    
    my $cgi;
    my $db = undef;
    
    $class||= "NG::Application" if $param{PageModule};
    
    cgi_error "No Application specified" if (!defined $class);  #TODO: make message 
    eval "require $class; 1;" or cgi_error $@;                  #TODO: -//-
    if ($dbclass) {
        eval "require $dbclass; 1;" or cgi_error $@;            #TODO: make message
        $db = $dbclass->new();
        $db->connect() or cgi_error $db->errstr();
    };
    
    
    ### CGI/mod_perl version
    use CGI;
    $cgi = CGI->new();
    
    $NG::Bootstrap::is_cgi = 0;
    $NG::Bootstrap::is_modperl = 0;
    $NG::Bootstrap::is_fastcgi = 0;
    $NG::Bootstrap::is_speedycgi = 0;
    
    if (exists $ENV{MOD_PERL}){
        $SIG{'__WARN__'} = sub { print STDERR strftime("[%a %b %d %T %Y]",localtime())." ".$_[0] };
        $NG::Bootstrap::is_modperl = 1;
    }
    else {
        $SIG{'__WARN__'} = sub { print STDERR $_[0] };
        $NG::Bootstrap::is_cgi = 1;
    };
    $param{CGIObject} = $cgi;
    $param{DBObject}  = $db;
    my $app;
    eval {
        $app = $class->new(%param);
        $app->run();  # must do $db->connect();
        #http://www.perlmonks.org/?node_id=891177
        $app->cleanup();
    };
    if ($@) {
        if (my $e = NG::Exception->caught($@)) {
            warn $e->getText();
            if (UNIVERSAL::can('CGI::Carp','can') && $CGI::Carp::WRAP && !$NG::Bootstrap::is_modperl) {
                CGI::Carp::fatalsToBrowser($e->getText());
            }
            else {
                print "Status: 500\n";
                print "Content-Type: text/plain; charset=windows-1251;\n\n";
                print $e->getText();
            };
        }
        else {
            warn $@;
            if (UNIVERSAL::can('CGI::Carp','can') && $CGI::Carp::WRAP && !$NG::Bootstrap::is_modperl) {
                CGI::Carp::fatalsToBrowser($@);
            }
            else {
                print "Status: 500\n";
                print "Content-Type: text/plain; charset=windows-1251;\n\n";
                print $@;
            };
        };
    };
};

sub fcgi_error {
    my $msg = shift;
    
    my $cgi = new CGI::Fast;
    
    print "Status: 500\n";
    print "Content-Type: text/plain; charset=windows-1251;\n\n";
    print $msg;
    exit;
};

sub FastCGI {
    my $pkg = shift;
    my %param = @_;
    my $class = $param{App};
    my $dbclass = $param{DB};
    
    require CGI::Fast;
    
    fcgi_error "No Application specified" if (!defined $class);  #TODO: make message 
    eval "require $class; 1;" or fcgi_error $@;                  #TODO: -//-
    my $db = undef;
    if ($dbclass) { eval "require $dbclass; 1;" or fcgi_error $@; #TODO: make message
        $db = $dbclass->new();
    }; 
    
    $NG::Bootstrap::is_cgi = 0;
    $NG::Bootstrap::is_modperl = 0;
    $NG::Bootstrap::is_fastcgi = 1;
    $NG::Bootstrap::is_speedycgi = 0;

    #local $SIG{__WARN__} = sub { $app->trace($_[0]) };
    #local $SIG{__DIE__} = sub { warn "localDIE"; print @_ };

    $param{DBObject} = $db if $db;
    while (my $cgi = new CGI::Fast) {
        eval {
            if ($db) {
                $db->connect() or die $db->errstr();
            };
            my $app = $class->new( %param, CGIObject => $cgi); #   or die $class->errstr;
            $app->run();  # must do $db->connect();
            $app->cleanup();
        };
        if ($@) {
            if (my $e = NG::Exception->caught($@)) {
                if (UNIVERSAL::can('CGI::Carp','can') && $CGI::Carp::WRAP) {
                    CGI::Carp::fatalsToBrowser($e->getText());
                }
                else {
                    print "Status: 500\n";
                    print "Content-Type: text/plain; charset=windows-1251;\n\n";
                    print $e->getText();
                };
            }
            else {
                if (UNIVERSAL::can('CGI::Carp','can') && $CGI::Carp::WRAP) {
                    CGI::Carp::fatalsToBrowser($@);
                }
                else {
                    print "Status: 500\n";
                    print "Content-Type: text/plain; charset=windows-1251;\n\n";
                    print $@;
                };
            };
        };
    };
};

#sub import {
#    my ($pkg, %param) = @_;
#
#    # use 'App' parameter, or MT_APP from the environment
#    my $class = $param{App} || $ENV{MT_APP};
#
#    if ($class) {
#        # When running under FastCGI, the initial invocation of the
#        # script has a bare environment. We can use this to test
#        # for FastCGI.
#        my $not_fast_cgi = 0;
#        $not_fast_cgi ||= exists $ENV{$_}
#            for qw(HTTP_HOST GATEWAY_INTERFACE SCRIPT_FILENAME SCRIPT_URL);
#         my $fast_cgi = defined $param{FastCGI} ? $param{FastCGI} : (!$not_fast_cgi);
#         if ($fast_cgi) {
#             eval 'require CGI::Fast;';
#             $fast_cgi = 0 if $@;
#         }
#
#        # ready to run now... run inside an eval block so we can gracefully
#        # die if something bad happens
#        my $app;
#        eval {
#            require MT;
#            eval "require $class; 1;" or die $@;
#            if ($fast_cgi) {
#                $ENV{FAST_CGI} = 1;
#                while (my $cgi = new CGI::Fast) {
#                    $app = $class->new( %param, CGIObject => $cgi )
#                        or die $class->errstr;
#                    local $SIG{__WARN__} = sub { $app->trace($_[0]) };
#                    MT->set_instance($app);
#                    $app->init_request(CGIObject => $cgi);
#                    $app->run;
#                }
#            } else {
#                $app = $class->new( %param ) or die $class->errstr;
#                local $SIG{__WARN__} = sub { $app->trace($_[0]) };
#                $app->run;
#            }
#        };
#        if (my $err = $@) {
#            my $charset = 'utf-8';
#            eval {
#                my $cfg = MT::ConfigMgr->instance;  #this is needed
#                $app ||= MT->instance;
#                my $c = $app->find_config;
#                $app->{cfg}->read_config($c);
#                $charset = $app->{cfg}->PublishCharset;
#            };
#            if ($app && UNIVERSAL::isa($app, 'MT::App')) {
#                eval {
#                    my %param = ( error => $err );
#                    if ($err =~ m/Bad ObjectDriver/) {
#                        $param{error_database_connection} = 1;
#                    } elsif ($err =~ m/Bad CGIPath/) {
#                        $param{error_cgi_path} = 1;
#                    } elsif ($err =~ m/Missing configuration file/) {
#                        $param{error_config_file} = 1;
#                    }
#                    my $page = $app->build_page('error.tmpl', \%param)
#                        or die $app->errstr;
#                    print "Content-Type: text/html; charset=$charset\n\n";
#                    print $page;
#                    exit;
#                };
#                $err = $@;
#            } else {
#                if ($err =~ m/Missing configuration file/) {
#                    my $host = $ENV{SERVER_NAME} || $ENV{HTTP_HOST};
#                    $host =~ s/:\d+//;
#                    my $port = $ENV{SERVER_PORT};
#                    my $uri = $ENV{REQUEST_URI} || $ENV{SCRIPT_NAME};
#                    if ($uri =~ m/(\/mt\.(f?cgi|f?pl)(\?.*)?)$/) {
#                        my $script = $1;
#                        my $ext = $2;
#
#                        if (-f File::Spec->catfile($ENV{MT_HOME}, "mt-wizard.$ext")) {
#                            $uri =~ s/\Q$script\E//;
#                            $uri .= '/mt-wizard.' . $ext;
#
#                            my $prot = $port == 443 ? 'https' : 'http';
#                            my $cgipath = "$prot://$host";
#                            $cgipath .= ":$port"
#                                unless $port == 443 or $port == 80;
#                            $cgipath .= $uri;
#                            print "Status: 302 Moved\n";
#                            print "Location: " . $cgipath . "\n\n";
#                            exit;
#                        }
#                    }
#                }
#                print "Content-Type: text/plain; charset=$charset\n\n";
#                print $app ? $app->translate("Got an error: [_1]", $app->translate($err)) : "Got an error: $err\n";
#            }
#        }
#    }
#}

1;
