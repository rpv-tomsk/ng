package NGPlugins;
use strict;

## See 'Plugins' on CPAN

my $PLUGINS = {};   #All plugins are registered here.
my  %CACHE = ();    #Cache of resulting plugins list for some object/class
our %DESTROYverified = ();  #Classes which has own DESTROY need to be checked.
our %SUPPORTED = ();        #Classes which not use @ISA = qw/NGPlugins::Instances/

$NGPlugins::REAL_START  = 0;
$NGPlugins::START       = 1;
$NGPlugins::AFTER_START = 2;
$NGPlugins::BEFORE_MIDDLE = 3;
$NGPlugins::MIDDLE        = 4;
$NGPlugins::AFTER_MIDDLE  = 5;
$NGPlugins::BEFORE_END    = 6;
$NGPlugins::END           = 7;
$NGPlugins::REAL_END      = 8;

sub registerPlugin {
    shift;  ## Not used.
    my $object = shift or die "NGPlugins->registerPlugin(): No base class or object";
    my $pluginClass = shift or die "NGPlugins->registerPlugin(): No plugin class";;
    my $pos = shift;
    (defined $pos) or $pos = 4;
    
    my $class = ref $object;
    if ( $class ) {
        delete $CACHE{$object};
        if ($object->isa('NGPlugins::Instances')) {
            warn "DESTROY redefined. Check if it calls NGPlugins::Instances::DESTROY(\$self); and ".
                 "add \$NGPlugins::DESTROYverified{ (__PACKAGE__) } = 1; to your BEGIN {}"
                if UNIVERSAL::can($object,'DESTROY') ne UNIVERSAL::can('NGPlugins::Instances','DESTROY')
                   && !$DESTROYverified{$class};
        }
        elsif (exists $SUPPORTED{$class}) {
            #Supported.
        }
        else {
            die "Class $class is not supported by NGPlugins. See NGPlugins programmer manual.";
        };
    }
    else {
        %CACHE = (); #Need to do full clean due to existence of cached values for $instance.
        $class = $object;
    };
    
    my $old = $PLUGINS->{$object} ||=[];
    $PLUGINS->{$object} = [];
    
    my $saveSub = sub {
        my $p = shift;
        push @{$PLUGINS->{$object}},$p;
        while ($p = shift @{$old}) {
            push @{$PLUGINS->{$object}},$p;
        };
    };
    
    if (scalar @{$old}) {
        my $p = shift @{$old};
        my $needPush = 1;
        for (;;) {
            if ($pos == 0 && $p->{POS} == 0) {
                &$saveSub($p);
                die "registerPlugin(): REAL_START can be used only once";
            };
            if ($pos == 8 && $p->{POS} == 8) {
                &$saveSub($p);
                die "registerPlugin(): REAL_END can be used only once";
            };
            if ($p->{CLASS} eq $pluginClass) {
                &$saveSub($p);
                die "Duplicate registration of plugin $pluginClass for $class";
                #warn "Plugin $pluginClass registered twice for class $class with pos ".$p->{POS}. " and $pos " if !$needPush;
                #warn "Attempt to register plugin $pluginClass for class $class pos $pos. Already registered with pos ".$p->{POS} if $needPush;
                #$needPush = 0;
            };
            
            if ( $needPush && $p->{POS} > $pos) {
                push @{$PLUGINS->{$object}},{POS=>$pos, CLASS=>$pluginClass};
                $needPush = 0;
            };
            push @{$PLUGINS->{$object}},$p;
            
            $p  = shift @{$old};
            unless ($p) {
                push @{$PLUGINS->{$object}},{POS=>$pos, CLASS=>$pluginClass} if ($needPush);
                last;
            };
        };
    }
    else {
        push @{$PLUGINS->{$object}},{POS=>$pos, CLASS=>$pluginClass};
    };
};

sub unregPluginsForInstance {
    shift;
    my $object = shift;
    if (ref $object) {
        delete $CACHE{$object};
    }
    else {
        %CACHE = ();
    }
    delete $PLUGINS->{$object};
};

=head
 Usage:
 
 my $iterator = $NGPlugins->iterator('Class','pluginMethod');
 while (@results = &$iterator(@args)) {
 }
=cut

sub iterator  {
    my $self = shift;
    my ($object, $method) = @_;
    die "NGPlugins->iterator(\$class,\$method): No \$class or \$method." unless $object && $method;
    
    my @pl = $self->plugins($object);
    return sub {
        for (;;) {
            my $plugin = shift(@pl) or return ();
            my $f = $plugin->can($method) or next;
            return &$f($plugin, @_);
        };
    };
};

sub invoke {
    my $self = shift;
    my ($object, $method) = (shift,shift);
    die "NGPlugins->invoke(\$class,\$method): No \$class or \$method." unless $object && $method;
    
    my $pl = $self->_getPluginsFor($object);
    
    foreach my $plugin (@$pl) {
        my $f = $plugin->can($method) or next;
        &$f($plugin, @_);
    };
    return 1;
};

sub invokeWhileTrue {
    my $self = shift;
    my ($object, $method) = (shift,shift);
    die "NGPlugins->invokeWhileTrue(\$class,\$method): No \$class or \$method." unless $object && $method;
    
    my $pl = $self->_getPluginsFor($object);
    
    foreach my $plugin (@$pl) {
        my $f = $plugin->can($method) or next;
        my $ret = &$f($plugin, @_);
        return $ret unless $ret;
    };
    return 1;
};

sub plugins {
    my $self = shift;
    my $object = shift or die "NGPlugins->plugins(): No class specified";
    
    my $pl = $self->_getPluginsFor($object);
    return map { $_ } @{$pl};
};

sub _getPluginsFor {
    my $self = shift;
    my $object = shift;
    
    return $CACHE{$object} if exists $CACHE{$object};
    
    my @plugins=();
    my $class = ref $object;
    if ( $class ) { # If is object.
        my %positionPlugins = ();            #$positionPlugins{$pos} = ['plugin1','plugin2'];
        my $addedPlugins = {};
        
        require Class::ISA;
        foreach my $cl ( Class::ISA::self_and_super_path($class), $object ) {
            next if $cl eq "NGPlugins::Instances";
            my $p = $PLUGINS->{$cl} or next;
            push @{$positionPlugins{$_->{POS}}},$_->{CLASS} foreach (@{$p});
        };
        foreach my $pos (sort keys %positionPlugins) {
            foreach (@{$positionPlugins{$pos}}) {
                next if exists $addedPlugins->{$_};
                push @plugins, $_;
                $addedPlugins->{$_} = 1;
            };
        };
    }
    else {
        my $p = $PLUGINS->{$object} or return [];
        @plugins = map { $_->{CLASS} } @{$p};
    };
    foreach my $plugin (@plugins) {
        unless ($plugin->can("can")) {
            eval "use $plugin;";
            die $@ if $@;
        };
    };
    $CACHE{$object} = \@plugins;
};


package NGPlugins::Instances;
use strict;

sub registerPlugin {
    NGPlugins->registerPlugin(@_);
};

sub DESTROY {
    NGPlugins->unregPluginsForInstance(shift);
};

1;
