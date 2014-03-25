package NG::Forum::Users;
use strict;
use base qw(NG::Forum::Object);

sub init {
    my $self = shift;
    my $user_id = shift || undef;
    my $forum = $self->forum();
    $self->{_user_id} = $user_id;
    $self->{_is_loaded} = 0;
    $self->{_is_section_moderate} = undef;
    $self->{_user_data} = {};
    $self->{_user_data}->{$_} = undef for ($forum->get_user_primary_fields(), $forum->get_user_data_fields());
    $self->{_user_data}->{id} = $user_id if ($user_id);
};

sub id {
    my $self = shift;
    return $self->get("id");
};

sub login {
    my $self = shift;
    return $self->get("login");
};

sub password {
    my $self = shift;
    return $self->get("password");
};

sub email {
    my $self = shift;
    return $self->get("email");
};

sub session {
    my $self = shift;
    return $self->get("session");
};


sub is_root {
    my $self = shift;
    return $self->get("is_root") ? 1: 0;
};

sub is_moderate {
    my $self = shift;
    return $self->get("is_moderate") ? 1: 0;
};

sub is_banned {
    my $self = shift;
    return $self->get("is_banned");
};

sub load {
    my $self = shift;
    unless ($self->{_is_loaded} && $self->{_user_id}) {
        my $forum = $self->forum();
        my $model = $forum->get_user_model();
        my $data = $model->load_user($self->{_user_id});
        if ($data) {
            foreach (keys %{$self->{_user_data}}) {
                $self->{_user_data}->{$_} = $data->{$_};        
            };
            $self->{_is_loaded} = 1;
        };

    };    
};

sub get {
    my $self = shift;
    my $field = shift;
    return exists $self->{_user_data}->{$field}? $self->{_user_data}->{$field}: undef;
};

sub set {
    my $self = shift;
    my $field = shift;
    my $value = shift;
    
    if (exists $self->{_user_data}->{$field}) {
        $self->{_user_id} = $value if ($field eq "id");
        $self->{_user_data}->{$field} = $value;
    };
};

sub can_access {
    my $self = shift;
    my $section_id = shift;
    my $forum = $self->forum();
    my $user_model = $forum->get_user_model();
    my $access_priv = $user_model->get_access_priv_name();
    my $write_priv = $user_model->get_write_priv_name();
    my $moderate_priv = $user_model->get_moderate_priv_name(); 
    return $self->_check_priv($access_priv, $section_id) || $self->_check_priv($write_priv, $section_id) || $self->_check_priv($moderate_priv, $section_id);
};

sub can_write {
    my $self = shift;
    my $section_id = shift;
    my $forum = $self->forum();
    my $user_model = $forum->get_user_model();    
    my $write_priv = $user_model->get_write_priv_name();
    my $moderate_priv = $user_model->get_moderate_priv_name();    
    return $self->_check_priv($write_priv, $section_id) || $self->_check_priv($moderate_priv, $section_id);
};

sub can_moderate {
    my $self = shift;
    my $section_id = shift;
    my $forum = $self->forum();
    my $user_model = $forum->get_user_model();    
    my $moderate_priv = $user_model->get_moderate_priv_name();    
    return $self->_check_priv($moderate_priv, $section_id);
};

sub _check_priv {
    my $self = shift;
    my $priv = shift;
    my $section_id = shift;
    
    return 1 if ($self->is_root() || $self->is_moderate());

    if (!exists $self->{_privs} || !defined $self->{_privs}) {
        my $forum = $self->forum();
        my $user_model = $forum->get_user_model();    
        $self->{_privs} = $user_model->get_privs_for_user($self->id());
    };
    return exists $self->{_privs}->{$section_id} && exists $self->{_privs}->{$section_id}->{$priv} ? 1 : 0; 
};

sub save {
    my $self = shift;
    if ($self->{_user_id}) {
        my $forum = $self->forum();
        my $user_model = $forum->get_user_model();
        $user_model->save_user($self->get_data_hash());
    };
};

sub tz {
    my $self = shift;
    return $self->get("tz");
};

sub print_to_template {
    my $self = shift;
    my $template = shift;
    my $variable_name = shift || "FORUM_USER";
    
    $template->param(
        $variable_name=>{
            ID=>$self->id(),
            LOGIN=>$self->login(),
        }
    );
};

sub get_data_hash {
    my $self = shift;
    my %data = %{$self->{_user_data}};
    return \%data;
};

sub set_data_hash {
    my $self = shift;
    my $data = shift;
    foreach (keys %{$self->{_user_data}}) {
        $self->set($_, $data->{$_});
    };
};

sub is_global_moderate {
    my $self = shift;
    return $self->is_moderate() || $self->is_root() ? 1 : 0;
};

sub is_section_moderate {
    my $self = shift;
    unless (defined $self->{_is_section_moderate}) {
        if ($self->is_global_moderate()) {
            $self->{_is_section_moderate} = 1;
        }
        elsif ($self->id()) {
            $self->{_is_section_moderate} = $self->forum()->get_user_model()->is_section_moderate($self->id());
        }
        else {
            $self->{_is_section_moderate} = 0;
        };    
    };
    return $self->{_is_section_moderate};
};

1;