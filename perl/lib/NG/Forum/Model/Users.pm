package NG::Forum::Model::Users;
use strict;
use NGService;
use NSecure;
use GD;
use base qw(NG::Forum::Object);

sub get_user_info {
    my $self = shift;
    my $user_id = shift;
    my $forum = $self->forum();
    my $user_table = $forum->get_user_table();
    my $id_field = $forum->get_user_field_name("id");
    my $login_field = $forum->get_user_field_name("login");
    my $email_field = $forum->get_user_field_name("email");
    
    my $dbh = $self->dbh();
    my $sql = sprintf("select u.%s as id, u.%s as login,u.%s as email, ud.signature,ud.avatar, ud.messages_cnt from %s u left join forums_users_data ud on (ud.user_id=u.%s) where u.%s=?",
        $id_field, $login_field, $email_field, $user_table, $id_field, $id_field
    );
    my $sth = $dbh->prepare($sql) or die $dbh->errstr();
    $sth->execute($user_id) or die $dbh->errstr();
    my $user_info = $sth->fetchrow_hashref();
    $sth->finish();
    if ($user_info) {
        $user_info->{avatar} = $forum->get_avatars_upload_dir().$user_info->{avatar} if ($user_info->{avatar});
        $user_info->{gravatar} = $forum->get_gravatar_url($user_info->{email});
        $user_info->{status} = $forum->get_user_status($user_info->{messages_cnt});    
    };
    
    return $user_info;
};

sub upload_avatar {
    my $self = shift;
    my $q = $self->q();
    my $forum = $self->forum();
    my $user = $forum->get_user();
    my $profile = $user->get_data_hash();
    my $cms = $self->cms();
    
    my $avatar_file = $q->param("avatar");
    return (0, {empty=>1}) unless $avatar_file;
    
    my $tmp_avatar_file = $q->tmpFileName($avatar_file);
    return (0, {wrong_upload=>1}) if (!-e $tmp_avatar_file || !-s $tmp_avatar_file);
    return (0, {not_image=>1}) unless (is_valid_image($avatar_file));
    
    my $src_image = new GD::Image($tmp_avatar_file);
    return (0, {process=>1}) unless $src_image;
    
    my $dir = $cms->getDocRoot().$forum->get_avatars_upload_dir();
    my $size = $forum->get_avatar_size();
    my ($width, $height) = $src_image->getBounds();
    my ($nwidth, $nheight) = ($width, $height);
    if($width > $height && $width > $size) {
        my $koef = $width / $size;
        $nwidth = int($size);
        $nheight = int($height / $koef);     
    }
    elsif($height >= $width && $height > $size) {
        my $koef = $height / $size;
        $nheight = int($size);
        $nwidth = int($width / $koef);    
    }
    my $dest_image = new GD::Image($nwidth, $nheight);
    $dest_image->copyResized($src_image, 0, 0, 0, 0, $nwidth, $nheight, $width, $height);
    my $old_avatar  = $profile->{avatar};
    my $avatar = sprintf("avatar_%s_%s.jpeg", $profile->{id}, int(rand(10000)));
    my $avatar_handle = undef;
    open($avatar_handle, ">".$dir.$avatar);
    return (0, {process=>1}) unless $avatar_handle;
    binmode $avatar_handle;
    print $avatar_handle $dest_image->jpeg();
    close $avatar_handle;
    unlink $dir.$old_avatar if ($old_avatar);
    return (1, $avatar);                                    
};

sub is_valid_user {
    my $self = shift;
    my $user_id = shift;
    my $forum = $self->forum();
    my $user_table = $forum->get_user_table();
    my $id_field = $forum->get_user_field_name("id");
    
    my $sql = sprintf("select 1 from %s where %s=?", $user_table, $id_field);
    my $dbh = $self->dbh();
    my ($is_valid) = $dbh->selectrow_array($sql, undef, $user_id);
    die $dbh->errstr() if ($dbh->err());
    
    return $is_valid ? 1 : 0;
};

sub get_authorize_user {
    my $self = shift;
    my $q = $self->q();
    my $dbh = $self->dbh();
    my $forum = $self->forum();
    my $cookiename = $forum->get_user_cookiename();
    my $session = $q->cookie($cookiename);

    my $user_id = 0;
    
    if ($session) {
        my $sql = sprintf("select %s as id from %s where %s=?", $forum->get_user_field_name("id"), $forum->get_user_table(), $forum->get_user_field_name("session"));
        ($user_id) = $dbh->selectrow_array($sql, undef, $session);
    };
        
    return $self->get_user_by_id($user_id);
};

sub get_user_by_id {
    my $self = shift;
    my $user_id = shift || 0;
    my $forum = $self->forum();
    my $user_factory = $forum->get_user_factory();
    my $user = $user_factory->get_user($user_id);
    $user->load() if ($user_id);
    return $user;
};

sub set_user_moderate {
    my $self = shift;
    my $user_id = shift;
    my $user = $self->get_user_by_id($user_id);
    if ($user->id()) {
        $user->set("is_moderate", 1);
        $user->save();
    };
};

sub unset_user_unmoderate {
    my $self = shift;
    my $user_id = shift;
    my $user = $self->get_user_by_id($user_id);
    if ($user->id()) {
        $user->set("is_moderate", 0);
        $user->save();
    };
};

sub set_user_ban {
    my $self = shift;
    my $user_id = shift;
    my $user = $self->get_user_by_id($user_id);
    if ($user->id()) {
        $user->set("is_banned", 1);
        $user->save();
    };
};

sub unset_user_ban {
    my $self = shift;
    my $user_id = shift;
    my $user = $self->get_user_by_id($user_id);
    if ($user->id()) {
        $user->set("is_banned", 0);
        $user->save();
    };
};

sub set_user_root {
    my $self = shift;
    my $user_id = shift;
    my $user = $self->get_user_by_id($user_id);
    if ($user->id()) {
        $user->set("is_root", 1);
        $user->save();
    };
};

sub unset_user_moderate {
    my $self = shift;
    my $user_id = shift;
    my $user = $self->get_user_by_id($user_id);
    if ($user->id()) {
        $user->set("is_moderate", 0);
        $user->save();
    };
};

sub unset_user_root {
    my $self = shift;
    my $user_id = shift;
    my $user = $self->get_user_by_id($user_id);
    if ($user->id()) {
        $user->set("is_root", 0);
        $user->save();
    };
};

sub load_user {
    my $self = shift;
    my $user_id = shift;
    
    my $forum = $self->forum();
    my $dbh = $self->dbh();
    
    my $user_table = $forum->get_user_table();
    
    my $sql = sprintf(
        "select %s,%s from %s left join forums_users_data on (forums_users_data.user_id=%s.id) where %s.id=?",
        $forum->get_user_sql_primary_fields(),
        $forum->get_user_sql_data_fields(),
        $user_table,
        $user_table,
        $user_table,
    );
    
    my $user_data = $dbh->selectrow_hashref($sql, undef, $user_id);
    die $dbh->errstr() if ($dbh->err());
    return $user_data;
};

sub login {
    my $self = shift;
    my $login = shift;
    my $password = shift;
    
    my $forum = $self->forum();
    my $dbh = $self->dbh();
    my $cms = $self->cms();
    
    my $table = $forum->get_user_table();
    my $id_field = $forum->get_user_field_name("id");
    my $session_field = $forum->get_user_field_name("session");
    my $authorize_field = $forum->is_authorize_via_email() ? $forum->get_user_field_name("email") : $forum->get_user_field_name("login");
    my $password_field = $forum->get_user_field_name("password");
    my $email_field = $forum->get_user_field_name("email");
    my $cookiename = $forum->get_user_cookiename();
    
    my $filters = $forum->get_valid_user_filters();
    my @filters = keys %$filters;
    
    my $sql = sprintf("select %s as id,%s as session from %s where %s=? and %s=?". (scalar @filters? "and ". join(" and ", map {$_. "=?"} @filters): ""), $id_field, $session_field, $table, $authorize_field, $password_field);
    my ($user_id, $session) = $dbh->selectrow_array($sql, undef, $login, $password, @$filters{@filters});
    
#     my $sql = sprintf("select %s as id,%s as session from %s where %s=? and %s=?", $id_field, $session_field, $table, $authorize_field, $password_field);
#     my ($user_id, $session) = $dbh->selectrow_array($sql, undef, $login, $password);
#     die $dbh->errstr() if ($dbh->err());
    
    return 0 unless $user_id;
    unless ($session) {
        $session = generate_session_id();
        $dbh->do(sprintf("update %s set %s=? where %s=?", $table, $session_field, $id_field), undef, $session, $user_id) or die $dbh->errstr();
    };
    
    $cms->addCookie(-name=>$cookiename, -value=>$session);
    return 1;    
};

sub logout {
    my $self = shift;
    my $cms = $self->cms();
    my $forum = $self->forum();
    my $cookiename = $forum->get_user_cookiename();
    $cms->addCookie(-name=>$cookiename, -value=>'');
};

sub has_email_duplicate {
    my $self = shift;
    my $email = shift;
    my $user_id = shift || 0;
    my $dbh = $self->dbh();
    my $forum = $self->forum();
    
    my $user_table = $forum->get_user_table();
    my $id_field = $forum->get_user_field_name("id");
    my $email_field = $forum->get_user_field_name("email");
    
    my $sql = sprintf("select 1 from %s where %s=? and %s<>?", $user_table, $email_field, $id_field);
    my ($is_duplicate) = $dbh->selectrow_array($sql, undef, $email, $user_id);
    die $dbh->errstr() if ($dbh->err());
    return  $is_duplicate ? 1 : 0;
};

sub has_login_duplicate {
    my $self = shift;
    my $login = shift;
    my $user_id = shift || 0;
    my $dbh = $self->dbh();
    my $forum = $self->forum();
    
    my $user_table = $forum->get_user_table();
    my $id_field = $forum->get_user_field_name("id");
    my $login_field = $forum->get_user_field_name("login");
    
    my $sql = sprintf("select 1 from %s where %s=? and %s<>?", $user_table, $login_field, $id_field);
    my ($is_duplicate) = $dbh->selectrow_array($sql, undef, $login, $user_id);
    die $dbh->errstr() if ($dbh->err());
    return  $is_duplicate ? 1 : 0;
};

sub save_user {
    my $self = shift;
    my $user = shift;
    
    my $forum = $self->forum();
    my $dbh = $self->dbh();
    my $db = $self->db();
    
    my $table = $forum->get_user_table();
    my $id_field = $forum->get_user_field_name("id");
    my $login_field = $forum->get_user_field_name("login");
    my $password_field = $forum->get_user_field_name("password");
    my $session_field = $forum->get_user_field_name("session");
    my $email_field = $forum->get_user_field_name("email");
    
    my @data_fields = $forum->get_user_data_fields();
    
   
    if ($user->{id}) {
        my $sql = sprintf("update %s set %s=?,%s=?,%s=? where %s=?", $table, $login_field, $email_field, $password_field, $id_field);
        $dbh->do($sql, undef, @$user{qw(login email password id)}) or die $dbh->errstr();
    }
    else {
        my $sql = sprintf("insert into %s (%s,%s,%s,%s) values(?,?,?,?)", $table, $id_field, $login_field, $password_field, $email_field);
        $user->{id} = $db->get_id($table);
        $dbh->do($sql, undef, @$user{qw(id login password email)}) or die $dbh->errstr();
    };

    my ($has_user_data) = $dbh->selectrow_array("select 1 from forums_users_data where user_id=?", undef, $user->{id});
    die $dbh->errstr() if ($dbh->err());
    if ($has_user_data) {
        $dbh->do(sprintf("update forums_users_data set %s where user_id=?", join(",", map {$_."=?"} @data_fields)), undef, @$user{@data_fields}, $user->{id}) or die $dbh->errstr();
    }
    else {
        $dbh->do(sprintf("insert into forums_users_data(user_id,%s) values(?,%s)", join(",", @data_fields), join(",", map {"?"} @data_fields)), undef, $user->{id}, @$user{@data_fields}) or die $dbh->errstr();
    };
        
};

#-------------------------------------------------------------- Rights And Groups
sub get_anonymous_group_id {
    return -1;
};

sub get_default_group_id {
    return -2;
};

sub get_privs_for_user {
    my $self = shift;
    my $user_id = shift;
    my $dbh = $self->dbh();    
    my $group_id = $user_id ? $self->get_default_group_id(): $self->get_anonymous_group_id();
    my $privs = $dbh->selectall_arrayref("select r.section_id,r.priv from forums_groups_privs r where group_id in (select group_id from forums_users_groups_links l where l.user_id=? union select ". $group_id. ")", {Slice=>{}}, $user_id);
    die $dbh->errstr() if ($dbh->err());
    my $priv_hash = {};
    foreach (@$privs) {
        $priv_hash->{$_->{section_id}}->{$_->{priv}} = 1;
    };
    return $priv_hash;
};

sub get_moderate_priv_name {
    return "moderate";
};

sub get_write_priv_name {
    return "write";
};

sub get_access_priv_name {
    return "access";
};

sub get_users_count {
    my $self = shift;
    my $dbh = $self->dbh();
    my $forum = $self->forum();
    my $user_table = $forum->get_user_table();
    my $sql = sprintf("select count(1) from %s", $user_table);
    my ($count) = $dbh->selectrow_array($sql);
    die $dbh->errstr() if ($dbh->err());
    return $count;
};

sub search_users {
    my $self = shift;
    my $search = shift;
    my $dbh = $self->dbh();
    my $forum = $self->forum();
    my $db = $self->db();
    
    $search = "%".$search."%";
    
    my $user_table = $forum->get_user_table();
    my $id_field = $forum->get_user_field_name("id");
    my $login_field = $forum->get_user_field_name("login");
    
    my $sql = "";
    if($db->isa("NG::DBI::Postgres")) {
        $sql = sprintf("select u.%s as id,u.%s as login,ud.is_banned,ud.is_moderate from %s u left join forums_users_data ud on (u.%s=ud.user_id) where u.%s ilike ? order by u.%s", $id_field, $login_field, $user_table, $id_field, $login_field, $login_field);
    }
    elsif($db->isa("NG::DBI::Mysql")) {
        $sql = sprintf("select u.%s as id,u.%s as login,ud.is_banned,ud.is_moderate from %s u left join forums_users_data ud on (u.%s=ud.user_id) where u.%s like ? order by u.%s", $id_field, $login_field, $user_table, $id_field, $login_field, $login_field);
    };
    
    my @users = ();
    my $sth = $dbh->prepare($sql) or die $dbh->errstr();
    $sth->execute($search) or die $dbh->errstr();
    while (my $row = $sth->fetchrow_hashref()) {
        push @users, $row;
    };
    $sth->finish();
    
    return wantarray? @users: \@users;
};


sub get_users_list {
    my $self = shift;
    my $offset = shift;
    my $limit = shift;
    my $dbh = $self->dbh();
    my $forum = $self->forum();
    my $db = $self->db();
    
    my $user_table = $forum->get_user_table();
    my $id_field = $forum->get_user_field_name("id");
    my $login_field = $forum->get_user_field_name("login");
    
    my $sql = sprintf("select u.%s as id,u.%s as login,ud.is_banned,ud.is_moderate from %s u left join forums_users_data ud on (u.%s=ud.user_id) order by u.%s", $id_field, $login_field, $user_table, $id_field, $login_field);
    $sql = $db->sqllimit($sql, $offset, $limit);
    
    my @users = ();
    my $sth = $dbh->prepare($sql) or die $dbh->errstr();
    $sth->execute() or die $dbh->errstr();
    while (my $row = $sth->fetchrow_hashref()) {
        push @users, $row;
    };
    $sth->finish();
    
    return wantarray? @users: \@users;
};

sub get_group_list {
    my $self = shift;
    my $dbh = $self->dbh();
    my @groups = (); 
    my $sth = $dbh->prepare("select id,name from forums_groups order by name asc") or die $dbh->errstr();
    $sth->execute() or die $dbh->errstr();
    while (my $row = $sth->fetchrow_hashref()) {
        push @groups, $row;
    };
    $sth->finish();
    
    return wantarray ? @groups : \@groups;
};

sub get_all_group_list {
    my $self = shift;
    my $dbh = $self->dbh();
    my $default_group_id = $self->get_default_group_id();
    my $anonymous_group_id = $self->get_anonymous_group_id();
    my @groups = (
        {id=>$default_group_id, default=>1},
        {id=>$anonymous_group_id, anonymous=>1},
    ); 
    my $sth = $dbh->prepare("select id,name from forums_groups order by name asc") or die $dbh->errstr();
    $sth->execute() or die $dbh->errstr();
    while (my $row = $sth->fetchrow_hashref()) {
        push @groups, $row;
    };
    $sth->finish();
    
    return wantarray ? @groups : \@groups;
};

sub add_group {
    my $self = shift;
    my $name = shift;
    my $dbh = $self->dbh();
    my $db = $self->db();
    my $id = $db->get_id("forums_groups");
    $dbh->do("insert into forums_groups(id, name) values(?,?)", undef, $id, $name) or die $dbh->errstr();
};

sub update_group {
    my $self = shift;
    my $group = shift;
    my $dbh = $self->dbh();
    $dbh->do("update forums_groups set name=? where id=?", undef, $group->{name}, $group->{id}) or die $dbh->errstr();
};

sub delete_group {
    my $self = shift;
    my $group_id = shift;
    my $dbh = $self->dbh();
    my $default_group_id = $self->get_default_group_id();
    my $anonymous_group_id = $self->get_anonymous_group_id();
    
    if ($group_id!=$default_group_id && $group_id!=$anonymous_group_id) {
        $dbh->do("delete from forums_groups where id=?", undef, $group_id) or die $dbh->errstr();
        $dbh->do("delete from forums_users_groups_links where group_id=?", undef, $group_id) or die $dbh->errstr();
        $dbh->do("delete from forums_groups_privs where group_id=?", undef, $group_id) or die $dbh->errstr();
    };
};

sub get_group {
    my $self = shift;
    my $id = shift;
    my $dbh = $self->dbh();
    my $row = $dbh->selectrow_hashref("select id,name from forums_groups where id=?", undef, $id);
    die $dbh->errstr() if ($dbh->err());
    unless ($row) {
        my $default_group_id = $self->get_default_group_id();
        my $anonymous_group_id = $self->get_anonymous_group_id();
        if ($id == $default_group_id) {
            $row = {id=>$id, name=>$self->forum()->getResource("TEXT_DEFAULT_GROUP_NAME")};
        }
        elsif ($id = $anonymous_group_id) {
            $row = {id=>$id, name=>$self->forum()->getResource("TEXT_ANONYMOUS_GROUP_NAME")};
        };
    };
    return $row;
};

sub get_user_group_list {
    my $self = shift;
    my $user_id = shift;
    my $dbh = $self->dbh();
    my @groups = ();
    my $sth = $dbh->prepare("select id,name from forums_groups g, forums_users_groups_links l where l.user_id=? and l.group_id=g.id order by name") or die $dbh->errstr();
    $sth->execute($user_id) or die $dbh->errstr();
    while (my $row = $sth->fetchrow_hashref()) {
        push @groups, $row;
    };
    $sth->finish();
    
    return wantarray ? @groups : \@groups;
};

sub set_user_groups {
    my $self = shift;
    my $user_id = shift;
    my %groups = map {$_=>1} @_;
    
    my $dbh = $self->dbh();
    $dbh->do("delete from forums_users_groups_links where user_id=?", undef, $user_id) or die $dbh->errstr();
    my @groups = $self->get_group_list();
    my $sth = $dbh->prepare("insert into forums_users_groups_links (user_id, group_id) values(?,?)") or die $dbh->errstr();
    foreach (@groups) {
        if (exists $groups{$_->{id}}) {
            $sth->execute($user_id, $_->{id}) or die $dbh->errstr();
        };
    };
    $sth->finish();
};

sub set_group_privs {
    my $self = shift;
    my $group_id = shift;
    my $dbh = $self->dbh();
    
    my $moderate_priv = $self->get_moderate_priv_name();
    my $write_priv = $self->get_write_priv_name();
    my $access_priv = $self->get_access_priv_name();
    
    my %privs_synonym = (
        "moderate"=>$moderate_priv,
        "write"=>$write_priv,
        "access"=>$access_priv,
    );    
    
    my @privs = ();
    if (ref $_[0] eq "ARRAY") {
        @privs = @{$_[0]};
    }
    else {
        @privs = (@_);
    };
    my $insert_sth = $dbh->prepare("insert into forums_groups_privs(group_id, section_id, priv) values(?,?,?)") or die $dbh->errstr();
    my $delete_sth = $dbh->prepare("delete from forums_groups_privs where group_id=? and section_id=? and priv=?") or die $dbh->errstr();
    my $privs = $dbh->selectall_hashref("select section_id, group_id, priv from forums_groups_privs where group_id=?", [qw(group_id section_id priv)], undef, $group_id);
    die $dbh->errstr() if ($dbh->err());

    foreach my $section (@privs) {
        foreach my $key (keys %{$section->{privs}}) {
            if ($section->{privs}->{$key} && !exists $privs->{$group_id}->{$section->{id}}->{$privs_synonym{$key}}) {
                $insert_sth->execute($group_id, $section->{id}, $privs_synonym{$key}) or die $dbh->errstr();
            }
            elsif (!$section->{privs}->{$key} && exists $privs->{$group_id}->{$section->{id}}->{$privs_synonym{$key}}) {
                $delete_sth->execute($group_id, $section->{id}, $privs_synonym{$key}) or die $dbh->errstr();
            };
        };    
    };
    
    $insert_sth->finish();
    $delete_sth->finish();
};

sub set_priv_to_forum_section {
    my $self = shift;
    my $section_id = shift;
    my $group_id = shift;
    my $priv = shift;
    my $dbh = $self->dbh();
    my ($has_priv) = $dbh->selectrow_array("select 1 from forums_groups_privs where group_id=? and section_id=? and priv=?", undef, $group_id, $section_id, $priv);
    die $dbh->errstr() if ($dbh->err());
    
    unless ($has_priv) {
        $dbh->do("insert into forums_groups_privs (group_id, section_id, priv) values(?,?,?)", undef, $group_id, $section_id, $priv) or die $dbh->errstr();
    }; 
};

sub get_group_privs {
    my $self = shift;
    my $group_id = shift;
    my $dbh = $self->dbh();

    my $moderate_priv = $self->get_moderate_priv_name();
    my $write_priv = $self->get_write_priv_name();
    my $access_priv = $self->get_access_priv_name();
    
    my %privs_synonym = (
        $moderate_priv=>"moderate",
        $write_priv=>"write",
        $access_priv=>"access",
    );
    
    my @privs = ();
    my $sth = $dbh->prepare("select f.id,f.name,g.priv from forums_sections f left join forums_groups_privs g on (f.id=g.section_id and g.group_id=?) order by f.position") or die $dbh->errstr();
    $sth->execute($group_id) or die $dbh->errstr();
    my $section = undef;
    while (my $row = $sth->fetchrow_hashref()) {
        if (!defined $section || $section->{id} != $row->{id}) {
            $section = {id=>$row->{id}, name=>$row->{name}, privs=>{}};
            foreach (qw(access moderate write)) {
                $section->{privs}->{$_} = 0;
            };            
            push @privs, $section;
        };
        $section->{privs}->{$privs_synonym{$row->{priv}}} = 1 if (exists $privs_synonym{$row->{priv}}); 
    };
    $sth->finish();
    
    
    return wantarray ? @privs : \@privs;
};

sub is_valid_group_id {
    my $self = shift;
    my $group_id = shift;
    my $default_group_id = $self->get_default_group_id();
    my $anonymous_group_id = $self->get_anonymous_group_id();
    my $dbh = $self->dbh();
    my ($has) = $dbh->selectrow_array("select 1 from forums_groups where id=?", undef, $group_id);
    die $dbh->errstr() if ($dbh->err());
    
    return (($has || $group_id==$default_group_id || $group_id==$anonymous_group_id) ? 1 : 0);
};

sub recovery_pwd_by_login {
    my $self = shift;
    my $login = shift;
    my $dbh = $self->dbh();
    my $forum = $self->forum();
    
    my $user_table = $forum->get_user_table();
    my $email_field = $forum->get_user_field_name("email");
    my $password_field = $forum->get_user_field_name("password");
    my $login_field = $forum->get_user_field_name("login");
    
    my $sql = sprintf("select u.%s, u.%s, u.%s from %s u where u.%s=?", $login_field, $email_field, $password_field, $user_table, $login_field);
    my ($user_login, $user_email, $password) = $dbh->selectrow_array($sql, undef, $login);
    die $dbh->errstr() if ($dbh->err());
    
    if ($user_email) {
        $self->_send_recovery_pwd($user_login, $user_email, $password);
        return 1;
    };
    
    return 0;
};

sub recovery_pwd_by_email {
    my $self = shift;
    my $email = shift;
    my $dbh = $self->dbh();
    my $forum = $self->forum();
    
    my $user_table = $forum->get_user_table();
    my $email_field = $forum->get_user_field_name("email");
    my $password_field = $forum->get_user_field_name("password");
    my $login_field = $forum->get_user_field_name("login");
    
    my $sql = sprintf("select u.%s, u.%s, u.%s from %s u where u.%s=?", $login_field, $email_field, $password_field, $user_table, $email_field);
    my ($user_login, $user_email, $password) = $dbh->selectrow_array($sql, undef, $email);
    die $dbh->errstr() if ($dbh->err());
    if ($user_email) {
        $self->_send_recovery_pwd($user_login, $user_email, $password);
        return 1;
    };
    
    return 0;
};

sub _send_recovery_pwd {
    my $self = shift;
    my $user_login = shift;
    my $user_email = shift;
    my $password = shift;
    my $forum = $self->forum();
    my $cms = $self->cms();
    
    my $q = $self->q();
    my $vhost = $q->virtual_host();
    my $forum_url = $forum->get_forum_url();
    
    my $template = $forum->gettemplate("mail/recoverypwd.tmpl") or die $cms->getError();
    $template->param(
        user_email=>$user_email,
        user_login=>$user_login,
        user_password=>$password,
        forum_url=>$forum_url,
        auth_via_email=>$forum->is_authorize_via_email(),
    );
    
    $forum->_send_email(
        to=>$user_email,
        subject=>$forum->getResource("EMAIL_RECOVERYPWD_SUBJECT")." ".$forum_url,
        plain=>$template->output()
    );
};

sub get_utc_zones {
    my $self = shift;
    my $forum = $self->forum();
    my $zone = shift || $forum->get_tz();
    my @zones = (-12..13);
    my @result = ();
    foreach (@zones) {
        my $value = sprintf("%s%02d00", ($_<0? "-": "+"), abs($_));
        push @result, {zone=>$_, value=>$value, current=>($value==$zone ? 1 : 0)};
    };
    return wantarray ? @result : \@result;    
}; 

sub reg {
    my $self = shift;
    my $newuser = shift;
    $self->save_user($newuser);    
};                             

sub is_section_moderate {
    my $self = shift;
    my $user_id = shift;
    my $priv = $self->get_moderate_priv_name();
    my $dbh = $self->dbh();    
    my ($has) = $dbh->selectrow_array("select 1 from forums_users_groups_links ug, forums_groups_privs gp where ug.user_id=? and ug.group_id=gp.group_id and gp.priv=?", undef, $user_id, $priv);
    die $dbh->errstr() if ($dbh->err());
    return $has? 1: 0;
};

sub get_extends_data {
    my $self = shift;
    my $user_id = shift;
    my $dbh = $self->dbh();
    my $forum = $self->forum();
    my $table = $forum->get_extends_table();
    my @fields = $forum->get_extends_fields();
    my $data = $dbh->selectrow_hashref("select * from ".$table." where user_id=?", undef, $user_id);
    die $dbh->errstr() if ($dbh->err());
    foreach (@fields) {
        $_->{value} = $data->{$_->{name}};
        $_->{"type_".$_->{type}} = 1;
    };
    return wantarray? @fields: \@fields;
};

sub save_extends_data {
    my $self = shift;
    my $user_id = shift;
    my $data = shift;
    my $forum = $self->forum();
    my $table = $forum->get_extends_table();
    my @fields = $forum->get_extends_fields();
    my $dbh = $self->dbh();

    my $sql = "";
    my ($has) = $dbh->selectrow_array("select 1 from ".$table." where user_id=?", undef, $user_id);
    die $dbh->errstr() if ($dbh->err());
    if ($has) {
        $sql = sprintf ("update %s set %s where user_id=?", $table, join(",", map {$_->{name}."=?"} @fields));
    }
    else {
       $sql = sprintf ("insert into %s (%s,user_id) values(%s,?)", $table, join(",", map {$_->{name}} @fields), join(",", map {"?"} @fields));
    };
    my @values = map {$data->{$_->{name}}} @fields;
    push @values, $user_id;
    $dbh->do($sql, undef, @values) or die $dbh->errstr();    
};

1;
