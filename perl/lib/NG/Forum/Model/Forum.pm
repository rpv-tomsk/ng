package NG::Forum::Model::Forum;
use strict;
use base qw(NG::Forum::Object);
use NG::Forum::Date;
use NGService;
use File::Basename;
use File::Copy;
use NSecure;

use constant SEARCH_ALL=>0;
use constant SEARCH_TODAY=>1;
use constant SEARCH_LAST_3_DAYS=>2;
use constant SEARCH_LAST_WEEK=>3;
use constant SEARCH_LAST_2_WEEK=>4;
use constant SEARCH_LAST_MONTH=>5;

sub get_main_forums {
    my $self = shift;
    my $dbh = $self->dbh();
    my $forum = $self->forum();
    my $user = $forum->get_user();
    
    my @forums_sections = ();
    my $section = undef;
    
    my $sth = $dbh->prepare("select f.id, f.section_id, fs.name as section_name, f.name,f.last_theme_id, ft.name as last_theme_name,f.messages_cnt,f.themes_cnt,fm.author as last_message_user,fm.author_user_id as last_message_user_id,fm.create_date as last_message_date from forums_sections fs,forums f left join forums_themes ft on (f.last_theme_id=ft.id) left join forums_messages fm on (ft.last_message_id=fm.id) where f.section_id=fs.id order by fs.position, f.position") or die $dbh->errstr();
    $sth->execute() or die $dbh->errstr();
    while (my $row = $sth->fetchrow_hashref()) {
        if (!defined $section || $section->{id} != $row->{section_id}) {
            push @forums_sections, {id=>$row->{section_id}, name=>$row->{section_name}};
            $section = $forums_sections[$#forums_sections];
        };
        $row->{last_message_date} = $forum->datetime_from_db($row->{last_message_date});
        push @{$section->{forums}}, $row;
    };
    $sth->finish();
    
    return wantarray ? @forums_sections : \@forums_sections;
};   

sub get_themes_list {
    my $self = shift;
    my $forum_id = shift;
    my $offset = shift || 0;
    my $limit = shift || 0;
    
    my $forum = $self->forum();
    my $user = $forum->get_user();
    my $dbh = $self->dbh();
    my $db = $self->db();
    
    my @themes = ();
    my $user_table = $forum->get_user_table();
    my $user_field_id = $forum->get_user_field_name("id");

    my $sql = "select ft.id, ft.is_close, ft.name, ft.is_close, ft.create_date, ft.lastupdate_date, ft.author, ft.author_user_id, ft.messages_cnt, fm.header as message_header, fm.message, fm.author as message_author, fm.author_user_id as message_author_user_id, (select 1 from forums_themes_read r where r.user_id=? and r.theme_id=ft.id and r.read_time>=ft.lastupdate_date limit 1) as is_read from forums_themes ft left join forums_messages fm on (ft.last_message_id=fm.id) where ft.forum_id=? and ft.is_attach=0 order by ft.lastupdate_date desc";    
    $sql = $db->sqllimit($sql, $offset, $limit) if ($limit || $offset);
    
    my $sth = $dbh->prepare($sql) or die $dbh->errstr();
    $sth->execute($user->id(), $forum_id) or die $dbh->errstr();
    while (my $row = $sth->fetchrow_hashref()) {
        push @themes, $row;    
    };
    $sth->finish();
    
    return wantarray ? @themes : \@themes;
};

sub get_latest_themes {
    my $self = shift;
    my $count = shift || 0;
    
    my $forum = $self->forum();
    my $user = $forum->get_user();
    my $dbh = $self->dbh();
    my $db = $self->db();
    
    my @themes = ();
    my $user_table = $forum->get_user_table();
    my $user_field_id = $forum->get_user_field_name("id");
    
    my $sql = $db->sqllimit("select ft.id, ft.is_close, ft.name, ft.is_close, ft.create_date, ft.lastupdate_date, ft.author, ft.author_user_id, ft.messages_cnt, fm.header as message_header, fm.message, fm.author as message_author, fm.author_user_id as message_author_user_id, (select 1 from forums_themes_read r where r.user_id=? and r.theme_id=ft.id and r.read_time>ft.lastupdate_date limit 1) as is_read from forums_themes ft left join forums_messages fm on (ft.last_message_id=fm.id) order by ft.lastupdate_date desc", 0, $count);
    
    my $sth = $dbh->prepare($sql) or die $dbh->errstr();
    $sth->execute($user->id()) or die $dbh->errstr();
    while (my $row = $sth->fetchrow_hashref()) {
        push @themes, $row;    
    };
    $sth->finish();
    
    return wantarray ? @themes : \@themes;
};

sub get_themes_count {
    my $self = shift;
    my $forum_id = shift;
    
    my $dbh = $self->dbh();
    my ($count) = $dbh->selectrow_array("select count(1) from forums_themes where forum_id=?", undef, $forum_id);
    die $dbh->errstr() if ($dbh->err());
    
    return $count;
};

sub get_all_themes_count {
    my $self = shift;
    
    my $dbh = $self->dbh();
    my ($count) = $dbh->selectrow_array("select count(1) from forums_themes");
    die $dbh->errstr() if ($dbh->err());
    
    return $count;
};

sub get_all_forums_count {
    my $self = shift;
    
    my $dbh = $self->dbh();
    my ($count) = $dbh->selectrow_array("select count(1) from forums");
    die $dbh->errstr() if ($dbh->err());
    
    return $count;
};

sub get_attached_themes {
    my $self = shift;
    my $forum_id = shift;
    my $forum = $self->forum();
    my $user = $forum->get_user();
    my $dbh = $self->dbh();
    
    my @themes = ();
    my $user_table = $forum->get_user_table();
    my $user_field_id = $forum->get_user_field_name("id");
    
    my $sql = sprintf(
        "select ft.id, ft.name, ft.is_close, ft.create_date, ft.lastupdate_date, ft.author, ft.author_user_id, fm.header as message_header, fm.message, fm.author as message_author, fm.author_user_id as message_author_user_id, (select 1 from forums_themes_read r where r.user_id=? and r.theme_id=ft.id and r.read_time>ft.lastupdate_date limit 1) as is_read from forums_themes ft left join forums_messages fm on (ft.author_user_id=fm.id) left join %s fu on (fm.author_user_id=fu.%s) where ft.forum_id=? and ft.is_attach=1 order by ft.lastupdate_date desc",
        $user_table,
        $user_field_id
    );
    
    my $sth = $dbh->prepare($sql) or die $dbh->errstr();
    $sth->execute($user->id(), $forum_id) or die $dbh->errstr();
    while (my $row = $sth->fetchrow_hashref()) {
        $row->{create_date} = $forum->datetime_from_db($row->{create_date});
        $row->{lastupdate_date} = $forum->datetime_from_db($row->{lastupdate_date});
        push @themes, $row;    
    };
    $sth->finish();
    
    return wantarray ? @themes : \@themes;
};

sub get_messages_list {
    my $self = shift;
    my $theme_id = shift;
    my $offset = shift || 0;
    my $limit = shift || 0;
    
    my $dbh = $self->dbh();
    my $db = $self->db();
    my $forum = $self->forum();
    
    my @messages = ();
    my $user_table = $forum->get_user_table();
    my $user_field_id = $forum->get_user_field_name("id");
    my $user_field_login = $forum->get_user_field_name("login");
    my $user_field_email = $forum->get_user_field_name("email");
    
    my $sql = sprintf(
        "select fm.id, fm.header, fm.create_date, fm.update_date, fm.message, fm.author,fm.author_user_id, ud.avatar, ud.signature,u.%s as email,ud.messages_cnt from forums_messages fm left join %s u on (fm.author_user_id=u.%s) left join forums_users_data ud on (u.%s=ud.user_id) where fm.theme_id=? order by fm.create_date asc",
        $user_field_email, $user_table, $user_field_id, $user_field_id
    );
    $sql = $db->sqllimit($sql, $offset, $limit) if ($limit || $offset);
    
    my $offline_time = $self->forum()->get_offline_user_time();
    my $current_datetime = $db->datetime_to_db(utc_current_datetime());
        
    if ($db->isa("NG::DBI::Postgres")) {
        $sql = sprintf("select m.*, (%s) as is_online from (%s) m", $db->sqllimit("select 1 from forums_users_last_access where user_id=m.author_user_id and access_time + interval '". $offline_time." minute' > ?", 0, 1), $sql);
    }
    else {
        $sql = sprintf("select m.*, (%s) as is_online from (%s) m", $db->sqllimit("select 1 from forums_users_last_access where user_id=m.author_user_id and access_time + interval ". $offline_time." minute > ?", 0, 1), $sql);
    }    
    
    my $sth = $dbh->prepare($sql) or die $dbh->errstr();
    $sth->execute($current_datetime, $theme_id) or die $dbh->errstr();
    while (my $row = $sth->fetchrow_hashref()) {
        push @messages, $row;    
    };
    $sth->finish();
    
    return wantarray ? @messages : \@messages;        
};

sub get_messages_files {
    my $self = shift;
    my $theme_id = shift;
    my $offset = shift;
    my $limit = shift;
    
    my $db = $self->db();
    my $dbh = $self->dbh();
    
    my $sql = $db->sqllimit("select id from forums_messages where theme_id=? order by create_date desc", $offset, $limit);
    $sql = sprintf("select fmf.id,fmf.message_id,fmf.create_date,fmf.delete_date,fmf.filename,fmf.ext,fmf.mimetype,fmf.size,fmf.filename,fmf.file from forums_messages_files fmf,(%s) fm where fmf.message_id=fm.id and (fmf.delete_date is null or fmf.delete_date>=?) and fmf.is_delete=0 order by fmf.id", $sql);

    my @files = ();
    my $messages = {};
    my $sth = $dbh->prepare($sql) or die $dbh->errstr();
    $sth->execute($theme_id, utc_current_datetime()) or die $dbh->errstr();
    while (my $row = $sth->fetchrow_hashref()) {
        $messages->{$row->{message_id}} = [] unless exists($messages->{$row->{message_id}});
        push @{$messages->{$row->{message_id}}}, $row;
        push @files, $row;
    };
    $sth->finish();
    $self->_message_files_split(\@files);
    return $messages;      
};

sub get_messages_count {
    my $self = shift;
    my $theme_id = shift;
    
    my $dbh = $self->dbh();
    my ($count) = $dbh->selectrow_array("select count(1) from forums_messages where theme_id=?", undef, $theme_id);
    die $dbh->errstr() if ($dbh->err());
    
    return $count;
};

sub get_all_messages_count {
    my $self = shift;
    my $dbh = $self->dbh();
    my ($count) = $dbh->selectrow_array("select count(1) from forums_messages");
    die $dbh->errstr() if ($dbh->err());
    
    return $count;
};

sub get_sections_list {
    my $self = shift;
    my $dbh = $self->dbh();
    
    my @sections = ();
    
    my $sth = $dbh->prepare("select id,name from forums_sections order by position") or die $dbh->errstr();
    $sth->execute() or die $dbh->errstr();
    while (my $row = $sth->fethrow_hashref()) {
        push @sections, $row;
    };
    $sth->finish();
    
    return wantarray ? @sections : \@sections;
};

sub get_forums_list {
    my $self = shift;
    my $section_id = shift;
    my $dbh = $self->dbh();
    my $forum = $self->forum();
    
    my @forums = ();
    
    my $sth = $dbh->prepare("select f.id,f.name,f.last_theme_id, ft.name as last_theme_name,f.messages_cnt,f.themes_cnt,fm.author as last_message_user,fm.author_user_id as last_message_user_id,fm.create_date as last_message_date from forums f left join forums_themes ft on (f.last_theme_id=ft.id) left join forums_messages fm on (ft.last_message_id=fm.id) where f.section_id=? order by f.position") or die $dbh->errstr();
    $sth->execute($section_id) or die $dbh->errstr();
    while (my $row = $sth->fetchrow_hashref()) {
        $row->{last_message_date} = $forum->datetime_from_db($row->{last_message_date});
        push @forums, $row;
    };
    $sth->finish();
    
    return wantarray ? @forums : \@forums;
};

sub get_message {
    my $self = shift;
    my $message_id = shift;
    my $is_full = shift || 0;
    my $dbh = $self->dbh();
    my $forum = $self->forum();
    my $fields = $is_full ? "m.*" : "m.id,m.theme_id,m.author,m.author_user_id,m.create_date,m.update_date,m.header,m.ip";
    my $message = $dbh->selectrow_hashref("select ".$fields.",f.id as forum_id,s.id as section_id from forums_messages m, forums_themes t, forums f, forums_sections s where m.id=? and m.theme_id=t.id and t.forum_id=f.id and f.section_id=s.id", undef, $message_id);
    die $dbh->errstr() if ($dbh->err());
    
    if ($message) {
        $message->{create_date} = $forum->datetime_from_db($message->{create_date});
        $message->{update_date} = $forum->datetime_from_db($message->{update_date});
    };
    
    return $message;
};

sub get_theme {
    my $self = shift;
    my $theme_id = shift;
    my $dbh = $self->dbh();
    my $forum = $self->forum();
    my $theme = $dbh->selectrow_hashref("select t.*,s.id as section_id from forums_themes t, forums f, forums_sections s where t.id=? and t.forum_id=f.id and f.section_id=s.id", undef, $theme_id);
    die $dbh->errstr() if ($dbh->err());
    if ($theme) {
        $theme->{create_date} = $forum->datetime_from_db($theme->{create_date});
        $theme->{lastupdate_date} = $forum->datetime_from_db($theme->{lastupdate_date});
    };    
    return $theme;
};

sub get_forum {
    my $self = shift;
    my $forum_id = shift;
    my $dbh = $self->dbh();
    my $forum = $dbh->selectrow_hashref("select f.* from forums f,forums_sections s where f.id=? and f.section_id=s.id", undef, $forum_id);
    die $dbh->errstr() if ($dbh->err());
    return $forum;
};


sub get_section {
    my $self = shift;
    my $section_id = shift;
    my $dbh = $self->dbh();
    my $section = $dbh->selectrow_hashref("select * from forums_sections where id=?", undef, $section_id);
    die $dbh->errstr() if ($dbh->err());
    return $section;
};

sub get_forums_structure {
    my $self = shift;
    my $forum_id = shift || 0;
    
    my @forums = ();
    my $dbh = $self->dbh();
    my $sth = $dbh->prepare("select f.id,f.section_id,f.name,fs.name as section_name from forums_sections fs, forums f where f.section_id=fs.id order by fs.position,f.position") or die $dbh->errstr();
    $sth->execute() or die $dbh->errstr();
    my $last_section = undef;
    while (my $row = $sth->fetchrow_hashref()) {
        $row->{current} = $row->{id} == $forum_id ? 1: 0;
        if (!defined $last_section || $last_section->{id} != $row->{section_id}) {
            $last_section = {id=>$row->{section_id}, name=>$row->{section_name}, count=>0, forums=>[]};
            push @forums, $last_section;
        };
        
        push @{$last_section->{forums}}, {id=>$row->{id}, name=>$row->{name}};
        $last_section->{count}++;
    };
    $sth->finish();
    return wantarray ? @forums : \@forums;
};

sub add_message {
    my $self = shift;
    my $data = shift;
    
    my $forum = $self->forum();
    my $user = $forum->get_user();
    my $db = $self->db();
    my $dbh = $self->dbh();

    $data->{author_user_id} = $user->id();
    $data->{author} ||= $user->login();
    $data->{create_date} ||= $db->datetime_to_db(utc_current_datetime());
    $data->{update_date} ||= $data->{create_date};
    $data->{ip} = $forum->get_ip();
    $data->{id} = $db->get_id("forums_messages");
    
    my @fields = qw(id theme_id author create_date update_date message author_user_id header ip);
    my $sql = sprintf("insert into %s (%s) values(%s)", "forums_messages", join(",", @fields), join(",", map {"?"} @fields));
    $dbh->do($sql, undef , @$data{@fields}) or die $dbh->errstr();
    
    $dbh->do("update forums_themes set last_message_id=?, messages_cnt=messages_cnt+1,lastupdate_date=? where id=?", undef, $data->{id}, $data->{create_date}, $data->{theme_id}) or die $dbh->errstr();
    $dbh->do("update forums set last_theme_id=?, messages_cnt=messages_cnt+1 where id in (select forum_id from forums_themes where id=?)", undef, $data->{theme_id}, $data->{theme_id}) or die $dbh->errstr();
    
    my $message_cnt = $user->get("messages_cnt") || 0;
    $user->set("messages_cnt", $message_cnt+1);
    $user->save();
    
    $self->message_search_index($data->{id}, $data->{message});
    $self->send_themes_subscribe($data->{theme_id}, $data->{author_user_id}, $data->{author}, $data->{message});
            
    return $data->{id};     
};

sub unsubscribe_theme {
    my $self = shift;
    my $user_id = shift;
    my $theme_id = shift;
    my $dbh = $self->dbh();
    $dbh->do("delete from forums_themes_subscribe where user_id=? and theme_id=?", undef, $user_id, $theme_id) or die $dbh->errstr();
};

sub ubsubscribe_all_themes {
    my $self = shift;
    my $user_id = shift;
    my $dbh = $self->dbh();
    $dbh->do("delete from forums_themes_subscribe where user_id=?", undef, $user_id) or die $dbh->errstr();
};

sub add_theme_poll {
    my $self = shift;
    my $data = shift;
    
    my $dbh = $self->dbh();
    my $db = $self->db();
    
    if (defined $data->{variants} && ref $data->{variants} eq "ARRAY" && scalar @{$data->{variants}}) {
        $data->{id} = $db->get_id("forums_themes_polls");
        $dbh->do("insert into forums_themes_polls(id,theme_id,name,multichoice) values(?,?,?,?)", undef, @$data{qw(id theme_id name multichoice)}) or die $dbh->errstr();
        foreach (@{$data->{variants}}) {
            $dbh->do("insert into forums_themes_polls_variants(id,poll_id,name) values(?,?,?)", undef, $db->get_id("forums_themes_polls_variants"), $data->{id}, $_) or die $dbh->errstr();
        };
        return $data->{id};     
    };
    return 0;
};

sub add_theme{
    my $self = shift;
    my $data = shift;
    
    my $forum = $self->forum();
    my $user = $forum->get_user();
    my $db = $self->db();
    my $dbh = $self->dbh();
    
    $data->{author_user_id} = $user->id();
    $data->{author} ||= $user->login();
    $data->{create_date} = $db->datetime_to_db(utc_current_datetime());
    $data->{lastupdate_date} = $data->{create_date};
    $data->{id} = $db->get_id("forums_themes");    

    my @fields = qw(id name forum_id author create_date lastupdate_date author_user_id);
    my $sql = sprintf("insert into %s (%s) values(%s)", "forums_themes", join(",", @fields), join(",", map {"?"} @fields)); 
    $dbh->do($sql, undef , @$data{@fields}) or die $dbh->errstr();
    $dbh->do("update forums set themes_cnt=themes_cnt+1 where id=?", undef, $data->{forum_id}) or die $dbh->errstr();
    
    my $message_data = {};
    $message_data->{theme_id} = $data->{id};
    $message_data->{author} = $data->{author};
    $message_data->{header} = $data->{name};
    $message_data->{message} = $data->{message};
    $self->theme_search_index($data->{id}, $data->{name});
    my ($message_id) = $self->add_message($message_data);
    
    
    return wantarray ? ($data->{id}, $message_id) : $data->{id};
};

sub add_forum {
    my $self = shift;
    my $data = shift;
    
    my $dbh = $self->dbh();
    my $db = $self->db();
    
    $data->{id} = $db->get_id("forums");
    $data->{position} = $data->{id};
    
    $dbh->do("insert into forums(id,section_id,name,position) values(?,?,?,?)", undef, @$data{qw(id section_id name position)}) or die $dbh->errstr();
    
    return $data->{id};
};

sub add_section {
    my $self = shift;
    my $data = shift;
    
    my $dbh = $self->dbh();
    my $db = $self->db();
    
    $data->{id} = $db->get_id("forums_sections");
    $data->{position} = $data->{id};
    
    $dbh->do("insert into forums_sections(id,name,position) values(?,?,?)", undef, @$data{qw(id name position)}) or die $dbh->errstr();
    return $data->{id};
}

sub add_message_file {
    my $self = shift;
#     my $message = $self->
};

sub get_message_file_info {
    my $self = shift;
    my $field_name = shift;
    my $q = $self->q();
    
    my $filename = $q->param($field_name);
    return undef unless $filename;
    my $tmp_filename = $q->tmpFileName($filename);
    return undef unless $tmp_filename;
    return undef unless (-e $tmp_filename);
    return undef unless (-s $tmp_filename);
    
    $filename = ts(basename($filename));
    my $size = -s $tmp_filename;
    my $ext = get_file_extension($filename);
    
    my $file = {
        size=>$size,
        ext=>$ext,
        tmpfile=>$tmp_filename,
        filename=>$filename
    };
    
    return $file;
};

sub get_uploaded_files {
    my $self = shift;
    return wantarray ? () : [];
};

sub upload_message_files {
    my $self = shift;
    my $message_id = shift;
    my @files = (@_);
    my $forum = $self->forum();
    my $cms = $self->cms();
    return undef unless (scalar @files);

    my $dir = $cms->getDocRoot().$forum->get_files_upload_dir();
    my $dbh = $self->dbh();
    my $db = $self->db();
    my $create_date = $db->datetime_to_db(utc_current_datetime());
    my @return = ();

    foreach (@files) {
        next unless defined $_;
        my $filename = $_->{filename};
        my $id = $db->get_id("forums_messages_files");
        $filename = sprintf("%d_%d_%s", int(rand()*10000), $message_id, $filename);
        File::Copy::move($_->{tmpfile}, $dir.$filename);
        chmod 0755, $dir.$filename;
        $dbh->do("insert into forums_messages_files(id,message_id,create_date,filename,size,ext,file) values(?,?,?,?,?,?,?)", undef, $id, $message_id, $create_date, $_->{filename}, $_->{size}, $_->{ext}, $filename) or die $dbh->errstr();
        
        push @return, $id;
    };
    
    return \@return;
};

sub moveup_section {
    my $self = shift;
    my $section_id = shift;
    $self->_move("forums_section", $section_id, "up");
};

sub movedown_section {
    my $self = shift;
    my $section_id = shift;
    $self->_move("forums_section", $section_id, "down");
};

sub moveup_forum {
    my $self = shift;
    my $forum_id = shift;
    $self->_move("forums", $forum_id, "up", {keys=>["section_id"]});
};

sub movedown_forum {
    my $self = shift;
    my $forum_id = shift;
    $self->_move("forums", $forum_id, "down", {keys=>["section_id"]});
};

sub _move {
    my $self = shift;
    my $table = shift || die "No table in move function";
    my $id_value = shift || die "No id value in move function";
    my $direction = shift || die "No direction in move function";
    die "Wrong direction in move function" if ($direction ne "up" && $direction ne "down");
    my $config = shift || {};
    
    my $position_field = $config->{position_field} || "position";
    my $id_field = $config->{id_field} || "id";
    my $keys = $config->{keys} || [];
    
    my $dbh = $self->dbh();
    my $db = $self->db();

        
    my $keys_fields = "";
    my $where = "";
    foreach (@$keys) {
        $where .= " and ". $_. "=?";
        $keys_fields .= ",". $_;
    };
     
    
    my ($current_position_sql) = sprinft("select %s%s from %s where %s=?", $position_field, $keys_fields, $table, $id_field);
    my $other_position_sql = "";
    if ($direction eq "up") {
        $other_position_sql = sprintf("select %s,%s from %s where %s<? %s order by %s desc", $id_field, $position_field, $table, $position_field, $where, $position_field);
    }
    else {
        $other_position_sql = sprintf("select %s,%s from %s where %s<? %s order by %s asc", $id_field, $position_field, $table, $position_field, $where, $position_field);
    };
    $other_position_sql = $db->sqllimit($other_position_sql, 0 ,1);
    
    my ($position, @values)  = $dbh->selectrow_array($current_position_sql, undef, $id_value);
    die $dbh->errstr() if ($dbh->err());
    if ($position) {
        my ($other_id, $other_position) = $dbh->selectrow_array($other_position_sql, undef, $position, @values);
        die $dbh->errstr() if ($dbh->err());
        if ($other_id) {
            my $update_sql = sprintf("update %s set %s=? where %s=?", $table, $position_field, $id_field);
            $dbh->do($update_sql, undef, $other_position, $id_value) or die $dbh->errstr();
            $dbh->do($update_sql, undef, $position, $other_id) or die $dbh->errstr();                
        };
    };    
};

sub _message_files_split {
    my $self = shift;
    my $files = shift;
    my $forum = $self->forum();
    
    my $dir = $forum->get_files_upload_dir();
    if (ref $files && ref $files eq "HASH") {
        $files->{create_date} = $forum->datetime_from_db($files->{create_date});
        $files->{delete_date} = $forum->datetime_from_db($files->{delete_date});
        $files->{file} = $dir.$files->{file};  
        $files->{size_text} = $forum->byte_to_text($files->{size});      
    }
    elsif (ref $files && ref $files eq "ARRAY") {
        foreach (@$files) {
            $_->{create_date} = $forum->datetime_from_db($_->{create_date});
            $_->{delete_date} = $forum->datetime_from_db($_->{delete_date});
            $_->{file} = $dir.$_->{file};  
            $_->{size_text} = $forum->byte_to_text($_->{size});      
        };    
    };
    
}; 

sub get_message_files {
    my $self = shift;
    my $message_id = shift;
    my $forum = $self->forum();
    my @files = ();
    my $dbh = $self->dbh();
    my $sth = $dbh->prepare("select id, message_id, create_date, delete_date, filename, size, ext, mimetype, file from forums_messages_files where message_id=? and (delete_date is null or delete_date>=?) order by id") or die $dbh->errstr();
    $sth->execute($message_id, utc_current_datetime()) or die $dbh->errstr();
    while (my $row = $sth->fetchrow_hashref()) {
        push @files, $row;
    };
    $sth->finish();
    $self->_message_files_split(\@files);
    return wantarray ? @files: \@files;
};

sub update_message {
    my $self = shift;
    my $data = shift;
    my $dbh = $self->dbh();
    my $db = $self->db();
    $data->{update_date} ||= $db->datetime_to_db(utc_current_datetime());
    $dbh->do("update forums_messages set message=?, update_date=? where id=?", undef, @$data{qw(message update_date id)}) or die $dbh->errstr();
};

sub get_message_file {
    my $self = shift;
    my $id = shift;
    my $dbh = $self->dbh();
    my $forum = $self->forum();
    
    my $file = $dbh->selectrow_hashref("select * from forums_messages_files where id=?", undef, $id);
    die $dbh->errstr() if ($dbh->err());
    if (defined $file) {
        $self->_message_files_split($file);
    };
    
    return $file;
};

sub update_theme {
    my $self = shift;
    my $theme = shift;
    my $dbh = $self->dbh();
    
    if ($theme->{forum_id}) {
        my ($old_forum_id) = $dbh->selectrow_array("select forum_id from forums_themes where id=?", undef, $theme->{id}) or die $dbh->errstr();
        $dbh->do("update forums_themes set forum_id=?,name=? where id=?", undef, @$theme{qw(forum_id name id)}) or die $dbh->errstr();
        
        if ($old_forum_id != $theme->{forum_id}) {
            my $db_theme = $self->get_theme($theme->{id});
            $dbh->do("update forums set themes_cnt=themes_cnt-1, messages_cnt=messages_cnt-? where id=?", undef, $db_theme->{messages_cnt}, $old_forum_id) or die $dbh->errstr();
            $dbh->do("update forums set themes_cnt=themes_cnt+1, messages_cnt=messages_cnt+? where id=?", undef, $db_theme->{messages_cnt}, $old_forum_id) or die $dbh->errstr();
        };    
    }
    else {
        $dbh->do("update forums_themes set name=? where id=?", undef, @$theme{qw(name id)}) or die $dbh->errstr();
    };
    
    
};

sub update_forum {
    my $self = shift;
    my $data = shift;
    my $dbh = $self->dbh();
    $dbh->do("update forums set name=? where id=?", undef, @$data{name id}) or die $dbh->errstr();
};

sub update_section {
    my $self = shift;
    my $data = shift;
    my $dbh = $self->dbh();
    $dbh->do("update forums_sections set name=? where id=?", undef, @$data{name id}) or die $dbh->errstr();
};

sub delete_message_file {
    my $self = shift;
    my $file = shift;
    my $cms = $self->cms();
    my $dbh = $self->dbh();
    # На вход подается или id файла или hashref загруженный get_message_file
                   
    if (!ref $file) {
        $file = $self->get_message_file($file);
    };                         
    
    $dbh->do("delete from forums_messages_files where id=?", undef, $file->{id}) or die $dbh->errstr();
    unlink $cms->getDocRoot().$file->{file};
};

sub delete_message_files {
    my $self = shift;
    my $message_id = shift;
    my $dbh = $self->dbh();
    $dbh->do("update forums_messages_files set is_delete=1 where message_id=?", undef, $message_id) or die $dbh->errstr();
#     my @files = $self->get_message_files($message_id);
#     foreach (@files) {
#         $self->delete_message_file($_);
#     };
};

sub delete_message_files_by_theme {
    my $self = shift;
    my $theme_id = shift;
    my $dbh = $self->dbh();
    $dbh->do("update forums_messages_files set is_delete=1 where message_id in (select id from forums_messages where theme_id=?)", undef, $theme_id) or die $dbh->errstr();
};

sub delete_message {
    my $self = shift;
    my $id_value = shift;
    my $dbh = $self->dbh();
    my $db = $self->db();
    my $message = $self->get_message($id_value);
    if ($message) {
    
        $self->delete_message_files($message->{id});
        $self->delete_message_search_index($message->{id});    
    
        $dbh->do("delete from forums_messages where id=?", undef, $id_value) or die $dbh->errstr();
        $dbh->do("update forums_themes set messages_cnt=messages_cnt-1 where id= ?", undef, $message->{theme_id}) or die $dbh->errstr();
        $dbh->do("update forums set messages_cnt=messages_cnt-1 where id=?", undef, $message->{forum_id}) or die $dbh->errstr();
        my $theme = $self->get_theme($message->{theme_id});
        if ($theme && $theme->{last_message_id} == $message->{id}) {
            my $last_message = $dbh->selectrow_hashref($db->sqllimit("select id,create_date from forums_messages where theme_id=? order by create_date desc", 0 ,1), undef, $theme->{id});
            die $dbh->errstr if ($dbh->err());
            $dbh->do("update forums_themes t set last_message_id=?, lastupdate_date=? where id=?", undef, $last_message->{id}, $last_message->{create_date}, $theme->{id}) or die $dbh->errstr();
        };

    };
};

sub delete_theme {
    my $self = shift;
    my $id_value = shift;
    my $dbh = $self->dbh();
    my $db = $self->db();
    my $theme = $self->get_theme($id_value);
    
    if ($theme) {
        $dbh->do("update forums set themes_cnt=themes_cnt-1,messages_cnt=messages_cnt-? where id=?", undef, $theme->{messages_cnt}, $theme->{forum_id}) or die $dbh->errstr();
        my $forum = $self->get_forum($theme->{forum_id});

        $self->delete_message_files_by_theme($theme->{id});
        $self->delete_theme_search_index($theme->{id});
        
        $dbh->do("delete from forums_themes_polls_variants where poll_id in (select id from forums_themes_polls where theme_id=?)", undef, $theme->{id}) or die $dbh->errstr();
        $dbh->do("delete from forums_themes_polls_logs where poll_id in (select id from forums_themes_polls where theme_id=?)", undef, $theme->{id}) or die $dbh->errstr();
        $dbh->do("delete from forums_themes_polls where theme_id=?", undef, $theme->{id}) or die $dbh->errstr();
        $dbh->do("delete from forums_messages where theme_id=?", undef, $theme->{id}) or die $dbh->errstr();
        $dbh->do("delete from forums_themes where id=?", undef, $theme->{id}) or die $dbh->errstr();
        $dbh->do("delete from forums_themes_subscribe where theme_id=?", undef, $theme->{id}) or die $dbh->errstr();
        
        if ($forum && $theme->{id} == $forum->{last_theme_id}) {
            my $last_theme_sql = $db->sqllimit("select id from forums_themes where forum_id=? order by lastupdate_date desc", 0 ,1);
            $dbh->do(sprintf("update forums set last_theme_id=(%s) where id=?", $last_theme_sql), undef, $forum->{id}, $forum->{id}) or die $dbh->errstr();
        };
    };
};

sub delete_forum{
    my $self = shift;
    my $id_value = shift;
    my $dbh = $self->dbh();
    $dbh->do("delete from forums where id=?", undef, $id_value) or die $dbh->errstr();
};

sub delete_section{
    my $self = shift;
    my $id_value = shift;
    my $dbh = $self->dbh();
    $dbh->do("delete from forums_sections where id=?", undef, $id_value) or die $dbh->errstr();
};

sub close_theme {
    my $self = shift;
    my $theme_id = shift;
    my $dbh = $self->dbh();
    $dbh->do("update forums_themes set is_close=1 where id=?", undef, $theme_id) or die $dbh->errstr();
};

sub open_theme {
    my $self = shift;
    my $theme_id = shift;
    my $dbh = $self->dbh();
    $dbh->do("update forums_themes set is_close=0 where id=?", undef, $theme_id) or die $dbh->errstr();
};


#---------------- PAGER

sub get_pager_in {
    my $self = shift;
    my $user_id = shift;
    
    my $forum = $self->forum();
    my $user_table = $forum->get_user_table();
    my $id_field = $forum->get_user_field_name("id");
    my $login_field = $forum->get_user_field_name("login");
    
    my $dbh = $self->dbh();
    my $sql = sprintf("select u.%s as login, p.id, p.header, p.create_date, p.sender_user_id as user_id from forums_pagers p, %s u where p.recipient_user_id=? and u.%s=p.sender_user_id and p.recipient_delete<>1  order by p.create_date desc ",
        $login_field, $user_table, $id_field
    );
    
    my @pagers = ();
    my $sth = $dbh->prepare($sql) or die $dbh->errstr();
    $sth->execute($user_id) or die $dbh->errstr();
    while (my $row = $sth->fetchrow_hashref()) {
        push @pagers, $row;
    };
    $sth->finish();
    
    return wantarray ? @pagers : \@pagers;
};

sub get_pager_out {
    my $self = shift;
    my $user_id = shift;
    
    my $forum = $self->forum();
    my $user_table = $forum->get_user_table();
    my $id_field = $forum->get_user_field_name("id");
    my $login_field = $forum->get_user_field_name("login");
    
    my $dbh = $self->dbh();
    my $sql = sprintf("select u.%s as login, p.id, p.create_date,p.header, p.recipient_user_id as user_id  from forums_pagers p, %s u where p.sender_user_id=? and u.%s=p.recipient_user_id and p.sender_delete<>1  order by p.create_date desc",
        $login_field, $user_table, $id_field
    );
    
    my @pagers = ();
    my $sth = $dbh->prepare($sql) or die $dbh->errstr();
    $sth->execute($user_id) or die $dbh->errstr();
    while (my $row = $sth->fetchrow_hashref()) {
        push @pagers, $row;
    };
    $sth->finish();
    
    return wantarray ? @pagers : \@pagers;
};

sub get_pager_in_count {
    my $self = shift;
    my $user_id = shift;
    
    my $dbh = $self->dbh();
    my ($count) = $dbh->selectrow_array("select count(id) from forums_pagers where recipient_user_id=? and recipient_delete<>1", undef, $user_id);
    die $dbh->errstr() if ($dbh->err());
    
    return $count;
};

sub get_pager_out_count {
    my $self = shift;
    my $user_id = shift;
    
    my $dbh = $self->dbh();
    my ($count) = $dbh->selectrow_array("select count(id) from forums_pagers where sender_user_id=? and sender_delete<>1", undef, $user_id);
    die $dbh->errstr() if ($dbh->err());
    
    return $count;
};

sub delete_pager {
    my $self = shift;
    my $pager_id = shift;
    my $user_id = shift;
    
    my $dbh = $self->dbh();
    my $pager = $dbh->selectrow_hashref("select id, recipient_user_id, sender_user_id, recipient_delete, sender_delete from forums_pagers where id=?", undef, $pager_id);
    die $dbh->errstr() if ($dbh->err());

    if ($pager) {
        $pager->{recipient_delete} = 1 if (!$pager->{recipient_delete} && $pager->{recipient_user_id} == $user_id);
        $pager->{sender_delete} = 1 if (!$pager->{sender_delete} && $pager->{sender_user_id} == $user_id);
    };
    
    if ($pager->{recipient_delete} && $pager->{sender_delete}) {
        $dbh->do("delete from forums_pagers where id=?", undef, $pager_id) or die $dbh->errstr();
    };
    
    $dbh->do("update forums_pagers set recipient_delete=?, sender_delete=? where id=?", undef, $pager->{recipient_delete}, $pager->{sender_delete}, $pager_id) or die $dbh->errstr();
};

sub add_pager {
    my $self = shift;
    my $pager = shift;
    my $db = $self->db();
    my $dbh = $self->dbh();
    my $q = $self->q();
    my $cms = $self->cms();
    
    $pager->{create_date} ||= $db->datetime_to_db(utc_current_datetime());
    if ($pager->{sender_user_id} != $pager->{recipient_user_id}) {
        $pager->{id} ||= $db->get_id("forums_pagers");
        my @fields = qw(id create_date recipient_user_id sender_user_id message header);
        
        $dbh->do("insert into forums_pagers(".join(",", @fields).") values(".join(",", (map {"?"} @fields)).")", undef,
            @$pager{@fields}
        ) or die $dbh->errstr();
        
        my $forum = $self->forum();
        my $user_table = $forum->get_user_table();
        my $id_field = $forum->get_user_field_name("id");
        my $email_field = $forum->get_user_field_name("email");
        my $login_field = $forum->get_user_field_name("login");
        my $user = $dbh->selectrow_hashref(sprintf("select %s as id,%s as email,%s as login from %s where %s=?", $id_field, $email_field, $login_field, $user_table, $id_field), undef, $pager->{recipient_user_id});
        die $dbh->errstr() if ($dbh->err());
        my ($sender_login) = $dbh->selectrow_array(sprintf("select %s from %s where %s=?", $login_field, $user_table, $id_field), undef, $pager->{sender_user_id});
        die $dbh->errstr() if ($dbh->err());
        
        my $template = $forum->gettemplate("mail/pager.tmpl") or die $cms->error();
        $template->param(
            USER_NAME=>$user->{login},
            USERNAME_WHO_SENT_PM=>$sender_login,
            MESSAGE=>$pager->{message},
            PAGER_URL=>getURLWithParams($forum->get_forum_url(), {action=>"pager"})
        );
        $forum->_send_email(
            to=>$user->{email},
            subject=>$forum->getResource("TEXT_PAGER_EMAIL_SUBJECT"),
            plain=>$template->output()
        );
    };
            
    return $pager->{id};
};

sub set_pager_read {
    my $self = shift;
    my $user_id = shift;
    my $db = $self->db();
    my $dbh = $self->dbh();
    my $readtime = $db->datetime_to_db(utc_current_datetime());
    $dbh->do("insert into forums_pager_read(user_id, readtime) values(?, ?)", undef, $user_id, $readtime) or die $dbh->errstr();
};

sub get_count_unread_pager_messages {
    my $self = shift;
    my $user_id = shift;
    my $count  = 0;
    return $count unless ($user_id);
    my $dbh = $self->dbh();
    my $db = $self->db();
    my ($readtime) = $dbh->selectrow_array("select max(readtime) from forums_pager_read where user_id=?", undef, $user_id);
    die $dbh->errstr() if ($dbh->err());
    if ($readtime) {    
        ($count) = $dbh->selectrow_array("select count(1) from forums_pagers where recipient_delete<>1 and recipient_user_id=? and create_date>?", undef, $user_id, $readtime);
    }
    else {
        ($count) = $dbh->selectrow_array("select count(1) from forums_pagers where recipient_delete<>1 and recipient_user_id=?", undef, $user_id);
    };
    die $dbh->errstr() if ($dbh->err());
    return $count; 
};

sub get_pager_full {
    my $self = shift;
    my $id = shift;
    my $user_id = shift;
    my $dbh = $self->dbh();
    my $forum = $self->forum();
    my $user_table = $forum->get_user_table();
    my $login_field = $forum->get_user_field_name("login");
    my $id_field = $forum->get_user_field_name("id");
    my $sql = sprintf("select p.id,p.create_date,p.recipient_user_id,p.sender_user_id,p.message,p.header,u.%s as recipient_login,u1.%s as sender_login from forums_pagers p left join %s u on (u.%s=recipient_user_id) left join %s u1 on (u1.%s=sender_user_id) where p.id=? and ((p.recipient_user_id=? and p.recipient_delete<>1) or (p.sender_user_id=? and p.sender_delete<>1))", $login_field, $login_field, $user_table, $id_field, $user_table, $id_field);
    my $pager = $dbh->selectrow_hashref($sql, undef, $id, $user_id, $user_id);
    die $dbh->errstr() if ($dbh->err());
    
    return $pager;
};

sub set_theme_read {
    my $self = shift;
    my $user_id = shift;
    my $theme_id = shift;
    my $read_time = shift || utc_current_datetime();
    
    my $dbh = $self->dbh();
    my $db = $self->db();
    $dbh->do("insert into forums_themes_read(theme_id, user_id, read_time) values(?,?,?)", undef, $theme_id, $user_id, $db->datetime_to_db($read_time)) or die $dbh->errstr();
};

sub get_poll_by_theme {
    my $self = shift;
    my $theme_id = shift;
    my $poll = undef;
    my $dbh = $self->dbh();
    my $sth = $dbh->prepare("select p.id as poll_id, p.name as poll_name, p.multichoice, p.vote_cnt as poll_vote_cnt, v.id, v.name, v.vote_cnt from forums_themes_polls p, forums_themes_polls_variants v where p.theme_id=? and p.id=v.poll_id order by v.id asc") or die $dbh->errstr();
    $sth->execute($theme_id) or die $dbh->errstr();
    while (my $row = $sth->fetchrow_hashref()) {
        unless (defined $poll) {
            $poll = {
                id=>$row->{poll_id},
                name=>$row->{poll_name},
                multichoice=>$row->{multichoice},
                vote_cnt=>$row->{poll_vote_cnt},
                variants=>[]
            };
        };
        $row->{percent} = $row->{poll_vote_cnt} ? sprintf("%.2f", ($row->{vote_cnt}*100)/$row->{poll_vote_cnt}) : 0;
        $row->{show_percent} = int($row->{percent}); 
        push @{$poll->{variants}}, $row;
    };
    $sth->finish();
    return $poll;
};

sub can_vote_to_poll {
    my $self = shift;
    my $poll_id = shift;
    my $user_id = shift;
    
    return 0 unless $user_id;
    my $dbh = $self->dbh();
    my ($has_vote) = $dbh->selectrow_array("select 1 from forums_themes_polls_logs where poll_id=? and user_id=?", undef, $poll_id, $user_id);
    die $dbh->errstr() if ($dbh->err());
    return $has_vote ? 0 : 1;
};

sub vote_to_poll {
    my $self = shift;
    my $poll_id = shift;
    my $user_id = shift;
    my @variants = (@_);

    my $dbh = $self->dbh();
    my $db = $self->db();
    
    my $poll = $dbh->selectrow_hashref("select id,multichoice from forums_themes_polls where id=?", undef, $poll_id);
    die $dbh->errstr() if ($dbh->err());
    return 1 unless $poll;

    my $variants = $dbh->selectall_hashref("select id from forums_themes_polls_variants where poll_id=?", [qw(id)], undef, $poll_id);
    die $dbh->errstr() if ($dbh->err());
    my $current_datetime = $db->datetime_to_db(utc_current_datetime());
    my $sth_update_vote = $dbh->prepare("update forums_themes_polls_variants set vote_cnt=vote_cnt+1 where id=?") or die $dbh->errstr();
    my $vote_count = 0;
    if (scalar @variants) {
        foreach my $v (@variants) {
            if (exists $variants->{$v}) {
                $sth_update_vote->execute($v);
                $vote_count++;
                last unless ($poll->{multichoice});    
            };
        };
        if ($vote_count) {
            $dbh->do("insert into forums_themes_polls_logs (poll_id, user_id, vote_date) values(?, ?, ?)", undef, $poll_id, $user_id, $current_datetime) or die $dbh->errstr();
            $dbh->do("update forums_themes_polls set vote_cnt=vote_cnt+? where id=?", undef, $vote_count, $poll_id) or die $dbh->errstr();
        };
    };
};

sub message_search_index {
    my $self = shift;
    my $message_id = shift;
    $self->_forum_search_index(undef, $message_id, @_);
};

sub theme_search_index {
    my $self = shift;
    my $theme_id = shift;
    $self->_forum_search_index($theme_id, undef, @_);
};

sub delete_theme_search_index {
    my $self = shift;
    my $theme_id = shift;
    my $dbh = $self->dbh();
    $dbh->do("delete from forums_search_indexes where theme_id=?", undef, $theme_id) or die $dbh->errstr();
    $dbh->do("delete from forums_search_indexes where message_id in (select id from forums_messages where theme_id=?)", undef, $theme_id) or die $dbh->errstr();
};

sub delete_message_search_index {
    my $self = shift;
    my $message_id = shift;
    my $dbh = $self->dbh();
    $dbh->do("delete from forums_search_indexes where message_id=?", undef, $message_id) or die $dbh->errstr(); 
};

sub _forum_search_index($$$@) {
    my $self = shift;
    my $theme_id = shift;
    my $message_id = shift;
    my @text = (@_);
    
    my $dbh = $self->dbh();
    my $db = $self->db();
    
    my ($id) = undef;
    
    ($id) = $dbh->selectrow_array("select id from forums_search_indexes where message_id=?", undef, $message_id) if ($message_id);
    die $dbh->errstr() if ($dbh->err());
    ($id) = $dbh->selectrow_array("select id from forums_search_indexes where theme_id=?", undef, $message_id) if ($theme_id);
    die $dbh->errstr() if ($dbh->err());
    
    my $text = join(" ", @text);
    my $current_timestamp =  $db->datetime_to_db(utc_current_datetime());

    if (!$id && defined $message_id) {
        $dbh->do("update forums_search_indexes set index_date=? where theme_id in (select theme_id from forums_messages where id=?)", undef, $current_timestamp, $message_id) or die $dbh->errstr();
    };
    
    if ($db->isa("NG::DBI::Postgres")) {
        if ($id) {
            $dbh->do("update forums_search_indexes set search_index=to_tsvector(?,?) where id=?", undef, $db->{_search_config}, $text, $id) or die $dbh->errstr();
        }
        else {
            $id = $db->get_id("forums_search_indexes");
            $dbh->do("insert into forums_search_indexes(id, message_id, theme_id, search_index, index_date) values(?, ?, ?, to_tsvector(?,?), ?)", undef, $id, $message_id, $theme_id, $db->{_search_config}, $text, $current_timestamp) or die $dbh->errstr();
        };        
    }
    elsif ($db->isa("NG::DBI::Mysql")) {
        if ($id) {
            $dbh->do("update forums_search_indexes set search_index=? where id=?", undef, $text, $id) or die $dbh->errstr();
        }
        else {
            $id = $db->get_id("forums_search_indexes");
            $dbh->do("insert into forums_search_indexes(id, message_id, theme_id, search_index, index_date) values(?, ?, ?, ?, ?)", undef, $id, $message_id, $theme_id, $text, $current_timestamp) or die $dbh->errstr();
        };
    };
    
};

sub _create_search_session {
    my $self = shift;
    my $keywords = shift;
    my $db = $self->db();
    my $dbh = $self->dbh();
    my $id = $db->get_id("forums_search_sessions");
    $dbh->do("insert into forums_search_sessions (id, session_date, keywords) values(?, ?, ?)", undef, $id, $db->datetime_to_db(utc_current_datetime()), $keywords) or die $dbh->errstr();
    return $id;
};

sub get_search_session {
    my $self = shift;
    my $search_session = shift;
    my $dbh = $self->dbh();
    my $session = $dbh->selectrow_hashref("select id,keywords from forums_search_sessions where id=?", undef, $search_session);
    die $dbh->errstr() if ($dbh->err());
    
    return $session;
};

sub search {
    my $self = shift;
    my %params = (@_);
    
    my $keywords = $params{keywords};
    my $search_in_theme = $params{search_in_theme} ? 1 : 0;
    my $search_all_words = $params{search_all_words} ? 1 : 0;
    my $search_in_day = $params{search_in_day}+0;
    my $forums = $params{forums};
    my $dbh = $self->dbh();
    
    return undef if (is_empty($keywords));
    
    $keywords =~ s/^\s+//;
    $keywords =~ s/\s+$//;
    my @keywords = split /\s+/, $keywords;
    
    my @where = ();
    my @values = ();
    
    my $db = $self->db();
    if ($db->isa("NG::DBI::Postgres")) {
        if ($search_all_words) {
            push @where, "search_index @@ to_tsquery(?, ?)";
            push @values, $db->{_search_config};
            push @values, join(" & ", @keywords);
        }
        else {
            push @where, "search_index @@ to_tsquery(?, ?)";
            push @values, $db->{_search_config};
            push @values, join(" | ", @keywords);
        };
    }
    elsif ($db->isa("NG::DBI::Mysql")) {
        if ($search_all_words) {
            my $keywords_params = "+".$keywords;
            $keywords_params =~ s/\s/ +/g;
            
            push @where, "match(fs.search_index) against(? in boolean mode)";
            push @values, $keywords_params;
        }
        else {
            push @where, "match(fs.search_index) against(? in boolean mode)";
            push @values, $keywords;
        };
    };
    
    if ($search_in_theme) {
        push @where, "fs.theme_id is not null";
    };
    
    my $condition_date = $self->_date_limit_search($search_in_day);
    push @where, $condition_date if ($condition_date);
    
    my $search_session = $self->_create_search_session($keywords);
    
    my $sql = sprintf("select fs.id,coalesce(fs.theme_id,m.theme_id) as theme_id,fs.message_id,fs.index_date from forums_search_indexes fs left join forums_messages m on (m.id=fs.message_id) ".(scalar @where ? "where %s" : ""), join (" and ", @where));
    $sql = sprintf("select fs.message_id,fs.theme_id, f.id as forum_id, s.id as section_id from (%s) fs, forums_themes t, forums f, forums_sections s where fs.theme_id=t.id and t.forum_id=f.id and f.section_id=s.id order by fs.index_date desc", $sql);
    if ($self->_prepare_forums_condition_for_search($search_session, @$forums)) {
        $sql = sprintf("select fs.* from (%s) fs, forums_search_sessions_sections_and_forums t where ((fs.forum_id=t.forum_id and t.forum_id is not null) or (fs.section_id=t.section_id and t.section_id is not null)) and t.session_id=?", $sql);
        push @values, $search_session;
    };
        
    my ($count) = $dbh->selectrow_array(sprintf("select count(1) from (%s) t", $sql), undef, @values);
    die $dbh->errstr() if ($dbh->err());
    return undef unless $count;
    
    
    $sql = sprintf("insert into forums_search_results (session_id, message_id,theme_id,forum_id,section_id) (select ?, message_id, theme_id, forum_id, section_id from (%s) t)", $sql);
    $dbh->do($sql, undef, $search_session, @values) or die $dbh->errstr();
    
    return $search_session;
};

sub _prepare_forums_condition_for_search {
    my $self = shift;
    my $search_session = shift;
    my @forums = (@_);
    
    my $dbh = $self->dbh();
    my %sections = ();
    my %forums = ();
    my $need_where = 0;
    
    foreach (@forums) {
        if ($_ =~ /s_(\d+)/) {
            $need_where = 1;
            $sections{$1} = 1;
        };
        if ($_ =~ /f_(\d+)/) {
            $need_where = 1;
            $forums{$1} = 1;
        };
    };

    return 0 unless $need_where;
    
    my $sth = $dbh->prepare("insert into forums_search_sessions_sections_and_forums(session_id, section_id, forum_id) values(?, ?, ?)") or die $dbh->errstr();
    foreach (keys %sections) {
        $sth->execute($search_session, $_, undef) or die $dbh->errstr();
    };
    foreach (keys %forums) {
        $sth->execute($search_session, undef, $_) or die $dbh->errstr();
    }; 
    
    return 1;
};

sub _date_limit_search {
    my $self = shift;
    my $limit = shift;
    my $db = $self->db();
    
    my $condition = "";
    my $current_datetime = $db->datetime_to_db(utc_current_datetime());
    
    if ($db->isa("NG::DBI::Postgres")) {
        if ($limit == SEARCH_TODAY) {
        }
        elsif ($limit == SEARCH_LAST_3_DAYS) {
        }
        elsif ($limit == SEARCH_LAST_WEEK) {
        }
        elsif ($limit == SEARCH_LAST_2_WEEK) {
        }
        elsif ($limit == SEARCH_LAST_MONTH) {
        };
    }
    elsif ($db->isa("NG::DBI::Mysql")) {
        if ($limit == SEARCH_TODAY) {
            return sprintf("date(fs.index_date) = date('%s')", $current_datetime);
        }
        elsif ($limit == SEARCH_LAST_3_DAYS) {
            return sprintf("date_add(date(fs.index_date), INTERVAL 3 DAY) >= date('%s')", $current_datetime);
        }
        elsif ($limit == SEARCH_LAST_WEEK) {
            return sprintf("date_add(date(fs.index_date), INTERVAL 7 DAY) >= date('%s')", $current_datetime);
        }
        elsif ($limit == SEARCH_LAST_2_WEEK) {
            return sprintf("date_add(date(fs.index_date), INTERVAL 14 DAY) >= date('%s')", $current_datetime);
        }
        elsif ($limit == SEARCH_LAST_MONTH) {
            return sprintf("date_add(date(fs.index_date), INTERVAL 1 MONTH) >= date('%s')", $current_datetime);
        };    
    };
    
    return $condition;
};

sub get_search_days_select_options {
    my $self = shift;
    my $limit = shift || 0;
    my $forum = $self->forum();
    
    my @result = ();
    push @result, {id=>SEARCH_ALL, name=>$forum->getResource("TEXT_SEARCH_ALL")};
    push @result, {id=>SEARCH_TODAY, name=>$forum->getResource("TEXT_SEARCH_TODAY")};
    push @result, {id=>SEARCH_LAST_3_DAYS, name=>$forum->getResource("TEXT_SEARCH_LAST_3_DAYS")};
    push @result, {id=>SEARCH_LAST_WEEK, name=>$forum->getResource("TEXT_SEARCH_LAST_WEEK")};
    push @result, {id=>SEARCH_LAST_2_WEEK, name=>$forum->getResource("TEXT_SEARCH_LAST_2_WEEKS")};
    push @result, {id=>SEARCH_LAST_MONTH, name=>$forum->getResource("TEXT_SEARCH_LAST_MONTH")};
    
    foreach (@result) {
        $_->{current} = ($_->{id} == $limit)? 1: 0; 
    };
    
    return wantarray? @result: \@result; 
};


sub get_search_forum_structure {
    my $self = shift;
    my $dbh = $self->dbh();
    
    my @result = ();
    my $sth = $dbh->prepare("select fs.id as section_id, fs.name as section_name, f.id, f.name from forums_sections fs, forums f where f.section_id=fs.id order by fs.position, f.position") or die $dbh->errstr();
    $sth->execute() or die $dbh->errstr();
    my $section = undef;
    while (my $row = $sth->fetchrow_hashref()) {
        if (!defined $section || $row->{section_id}!=$section->{id}) {
            $section = {
                id=>$row->{section_id},
                name=>$row->{section_name},
                forums=>[],
            };
            push @result, $section;    
        };
        push @{$section->{forums}}, {id=>$row->{id}, name=>$row->{name}};
        $section->{show}++;
    };
    $sth->finish();

    return wantarray? @result: \@result;
};

sub get_search_results {
    my $self = shift;
    my $search_session = shift;
    my $offset = shift;
    my $limit = shift;
    
    my $forum = $self->forum();
    my $user = $forum->get_user();
    my $user_model = $forum->get_user_model();
    my $dbh = $self->dbh();
    my $db = $self->db();
    
    my @result = ();
    my $sth = undef;  
    if ($user->is_global_moderate()) {
        $sth = $dbh->prepare($db->sqllimit("select sr.id,sr.section_id,sr.forum_id,sr.message_id,sr.theme_id,t.name as theme, m.message as message from forums_search_results sr left join forums_themes t on (sr.theme_id=t.id) left join forums_messages m on (sr.message_id=m.id) where sr.session_id=? order by id asc", $offset, $limit)) or die $dbh->errstr();
        $sth->execute($search_session);
    }
    else {
        my $user_id = $user->id();
        my $default_group_id = $user_id ? $user_model->get_default_group_id() : $user_model->get_anonymous_group_id();
        $sth = $dbh->prepare($db->sqllimit("select sr.id,sr.section_id,sr.forum_id,sr.message_id,sr.theme_id,t.name as theme, m.message as message from (select sr.id,sr.section_id,sr.forum_id,sr.message_id,sr.theme_id from forums_search_results sr, (select group_id, section_id from forums_groups_privs group by group_id, section_id) gp  where sr.session_id=? and sr.section_id=gp.section_id and gp.group_id in (select group_id from forums_users_groups_links where user_id=? union select ". $default_group_id. ")) sr left join forums_themes t on (sr.theme_id=t.id) left join forums_messages m on (sr.message_id=m.id) order by id asc", $offset, $limit)) or die $dbh->errstr();
        $sth->execute($search_session, $user_id) or die $dbh->errstr();
    };    
    
    while (my $row = $sth->fetchrow_hashref()) {
        push @result, $row;
    };
    $sth->finish();
    
    return wantarray ? @result : \@result;
};

sub get_search_results_count {
    my $self = shift;
    my $search_session = shift;
    
    my $forum = $self->forum();
    my $user = $forum->get_user();
    my $user_model = $forum->get_user_model();
    my $dbh = $self->dbh();
    
    my $count = 0;
    if ($user->is_global_moderate()) {
        ($count) = $dbh->selectrow_array("select count(1) from forums_search_results where session_id=?", undef, $search_session);
    }
    else {
        my $user_id = $user->id();
        my $default_group_id = $user_id ? $user_model->get_default_group_id() : $user_model->get_anonymous_group_id();
        ($count) = $dbh->selectrow_array("select count(1) from forums_search_results sr, forums_groups_privs gp  where sr.session_id=? and sr.section_id=gp.section_id and ((gp.group_id in (select group_id from forums_users_groups_links where user_id=?) or gp.group_id=?))", undef, $search_session, $user_id, $default_group_id);
    };
    die $dbh->errstr() if ($dbh->err());
    
    return $count;
};

sub subscribe_theme {
    my $self = shift;
    my $user_id = shift;
    my $theme_id = shift;
    my $dbh = $self->dbh();
    
    $dbh->do("insert into forums_themes_subscribe(user_id, theme_id) values(?, ?)", undef, $user_id, $theme_id) or die $dbh->errstr();
};

sub is_subscribe_theme {
    my $self = shift;
    my $user_id = shift;
    my $theme_id = shift;
    my $dbh = $self->dbh();
    my ($is) = $dbh->selectrow_array("select 1 from forums_themes_subscribe where theme_id=? and user_id=?", undef, $theme_id, $user_id);
    die $dbh->errstr() if ($dbh->err());
    
    return $is ? 1 : 0;
};

sub send_themes_subscribe {
    my $self = shift;
    my $theme_id = shift;
    my $author_id = shift;
    my $author = shift;
    my $message = shift;
    
    my $theme = $self->get_theme($theme_id);
    return 1 unless $theme;  
    my $dbh = $self->dbh();
    my $forum = $self->forum();
    my $cms = $self->cms();
    my $q = $self->q();
    
    my $forum_url = $forum->get_forum_url();
    
    my $user_table = $forum->get_user_table();
    my $email_field = $forum->get_user_field_name("email");
    my $login_field = $forum->get_user_field_name("login");
    my $id_field = $forum->get_user_field_name("id");
    
    my $sql = sprintf("select u.%s as email, u.%s as login,fts.user_id, t.name from forums_themes_subscribe fts, %s u,forums_themes t where fts.theme_id=? and u.%s=fts.user_id and t.id=fts.theme_id", $email_field, $login_field, $user_table, $id_field);
    my @result = ();
    my $template = $forum->gettemplate("mail/theme_subscribe.tmpl") or die $cms->error();
    my $sth = $dbh->prepare($sql) or die $dbh->errstr();
    $sth->execute($theme->{id}) or die $dbh->errstr();
    
    my $theme_url = getURLWithParams($forum_url, {action=>"showmessages", theme_id=>$theme->{id}, lastmessage=>1});
    my $unsubscribe_theme_url = getURLWithParams($forum_url, {action=>"unsubscribetheme", theme_id=>$theme->{id}});
    my $unsubscribe_all_themes_url = getURLWithParams($forum_url, {action=>"unsubscribeallthemes"});
    my @banned_users = $self->get_banned_users_for_forum_section($theme->{section_id});
    my %banned_users = map {$_=>1} @banned_users;
    
    while (my $row = $sth->fetchrow_hashref()) {
        next if (exists $banned_users{$row->{user_id}});
        next if ($row->{user_id} == $author_id);
        $template->param(
            USER_NAME=>$row->{login},
            ANSWER_USER=>$author,
            THEME=>$theme->{name},
            MESSAGE=>$message,
            THEME_URL=>$theme_url,
            UNSUBSCRIBE_THEME_URL=>$unsubscribe_theme_url,
            UNSUBSCRIBE_ALL_THEMES_URL=>$unsubscribe_all_themes_url,
        );
        
        $forum->_send_email(
            to=>$theme->{email},
            subject=>$forum->getResource("THEME_SUBSCRIBE_SUBJECT")." ".$theme->{name},
            plain=>$template->output()
        );
    };
    $sth->finish();
    
    my @moderate_emails = $self->get_subscribed_moderate_emails_for_forum_section($theme->{section_id});
    $template = $forum->gettemplate("mail/moderate_theme_subscribe.tmpl") or die $cms->error();
    $template->param(
        ANSWER_USER=>$author,
        THEME=>$theme->{name},
        MESSAGE=>$message,
        THEME_URL=>$theme_url,
    );
    $forum->_send_email(
        to=>\@moderate_emails,
        subject=>$forum->getResource("THEME_SUBSCRIBE_SUBJECT")." ".$theme->{name},
        plain=>$template->output()
    );        
};

sub ban_ip {
    my $self = shift;
    my $ip = shift;
    $ip =~ s/\s*//gi;
    my $dbh = $self->dbh();
    
    my ($has) = $dbh->selectrow_array("select 1 from forums_ip_bans where ip=?", undef, $ip);
    die $dbh->errstr() if ($dbh->err());
    
    $dbh->do("insert into forums_ip_bans (ip) values(?)", undef, $ip) unless $has;
};

sub unban_ip {
    my $self = shift;
    my $ip = shift;
    $ip =~ s/\s*//gi;
    my $dbh = $self->dbh();
    $dbh->do("delete from forums_ip_bans where ip=?", undef, $ip) or die $dbh->errstr();
};

sub ban_user_on_section {
    my $self = shift;
    my $user_id = shift;
    my $section_id = shift;
    my $dbh = $self->dbh();

    my ($has) = $dbh->selectrow_array("select 1 from forums_users_bans where user_id=? and section_id=?", undef, $user_id, $section_id);
    die $dbh->errstr() if ($dbh->err());
    $dbh->do("insert into forums_users_bans (user_id, section_id) values(?,?)", undef, $user_id, $section_id) unless $has;
};

sub unban_user_on_section {
    my $self = shift;
    my $user_id = shift;
    my $section_id = shift;
    my $dbh = $self->dbh();
    $dbh->do("delete from forums_users_bans where user_id=? and section_id=?", undef, $user_id, $section_id) or die $dbh->errstr();    
};

sub ip_is_banned {
    my $self = shift;
    my $ip = shift;
    my $dbh = $self->dbh();
    my ($has) = $dbh->selectrow_array("select 1 from forums_ip_bans where ip=?", undef, $ip);
    die $dbh->errstr() if ($dbh->err());
    return $has ? 1: 0;
};

sub user_is_banned_on_section {
    my $self = shift;
    my $user_id = shift;
    my $section_id = shift;
    my $dbh = $self->dbh();
    my ($has) = $dbh->selectrow_array("select 1 from forums_users_bans where user_id=? and section_id=?", undef, $user_id, $section_id);
    die $dbh->errstr() if ($dbh->err());
    return $has ? 1: 0;
};

sub get_sections_where_user_banned {
    my $self = shift;
    my $user_id = shift;
    my $dbh = $self->dbh();

    my @result = ();    
    my $sth = $dbh->prepare("select fs.name,fs.id from forums_users_bans ub, forums_sections fs where ub.user_id=? and fs.id=ub.section_id order by fs.position") or die $dbh->errstr();
    $sth->execute($user_id) or die $dbh->errstr();
    while (my $row = $sth->fetchrow_hashref()) {
        push @result, $row;
    };
    $sth->finish();
    return wantarray ? @result : \@result;     
};

sub complain_to_message {
    my $self = shift;
    my $message_id = shift;
    my $cms = $self->cms();
    my $message = $self->get_message($message_id);
    my $forum = $self->forum();
    my $dbh = $self->dbh();
    if ($message) {
        my $user = $forum->get_user();
        my $template = $forum->gettemplate("mail/complain_message.tmpl") or die $cms->error();
        $template->param(
            MESSAGE_LINK=>getURLWithParams($forum->get_forum_url(), {
                action=>"showmessages",
                theme_id=>$message->{theme_id},
                message_id=>$message->{id}
            })."#message".$message->{id},
            MESSAGE_ID=>$message->{id},
            USER_NAME=>$user->login()
        );
        my $emails = $self->get_moderate_emails_for_forum_section($message->{section_id});
        $forum->_send_email(
            to=>$emails,
            subject=>$forum->getResource("COMPLAIN_MESSAGE_EMAIL_SUBJECT"),
            plain=>$template->output()
        ); 
    };
};

sub get_banned_users_for_forum_section {
    my $self = shift;
    my $section_id = shift;
    my $forum = $self->forum();
    my $user_table = $forum->get_user_table();
    my $id_field = $forum->get_user_field_name("id");
    my $dbh = $self->dbh();
    my $sql = sprintf("select u.%s from %s u,(select ud.user_id from forums_users_data ud where ud.is_root<>1 and ud.is_moderate<>1 and ud.is_banned=1 union select distinct user_id from forums_users_bans ub where ub.section_id=?) ud where ud.user_id=u.%s", $id_field, $user_table, $id_field);
    my @result = ();
    my $sth = $dbh->prepare($sql) or die $dbh->errstr();
    $sth->execute($section_id) or die $dbh->errstr();
    while (my $row = $sth->fetchrow()) {
        push @result, $row;
    };
    $sth->finish();
    return wantarray ? @result: \@result;
    
};

sub get_moderate_emails_for_forum_section {
    my $self = shift;
    my $section_id = shift;
    my $forum = $self->forum();
    my $user_table = $forum->get_user_table();
    my $id_field = $forum->get_user_field_name("id");
    my $email_field = $forum->get_user_field_name("email");
    my $priv_name = $forum->get_user_model()->get_moderate_priv_name();
    my $dbh = $self->dbh();
    my $sql = sprintf("select u.%s from %s u,(select ud.user_id from forums_users_data ud where ud.is_root=1 or ud.is_moderate=1 union select distinct ugl.user_id from forums_groups_privs gp,forums_users_groups_links ugl where gp.priv=? and gp.group_id=ugl.group_id and gp.section_id=?) u1 where u1.user_id=u.%s", $email_field, $user_table, $id_field);
    my @result = ();
    my $sth = $dbh->prepare($sql) or die $dbh->errstr();
    $sth->execute($priv_name, $section_id) or die $dbh->errstr();
    while (my $row = $sth->fetchrow()) {
        push @result, $row;
    };
    $sth->finish();
    return wantarray ? @result: \@result;
};

sub get_subscribed_moderate_emails_for_forum_section {
    my $self = shift;
    my $section_id = shift;
    my $forum = $self->forum();
    my $user_table = $forum->get_user_table();
    my $id_field = $forum->get_user_field_name("id");
    my $email_field = $forum->get_user_field_name("email");
    my $priv_name = $forum->get_user_model()->get_moderate_priv_name();
    my $dbh = $self->dbh();
    my $sql = sprintf("select u.%s from %s u,(select ud.user_id from forums_users_data ud where ud.is_root=1 or ud.is_moderate=1 union select distinct ugl.user_id from forums_groups_privs gp,forums_users_groups_links ugl where gp.priv=? and gp.group_id=ugl.group_id and gp.section_id=?) u1, forums_users_data ud where u1.user_id=u.%s and ud.is_subscribe=1 and u.%s=ud.user_id", $email_field, $user_table, $id_field, $id_field);
    my @result = ();
    my $sth = $dbh->prepare($sql) or die $dbh->errstr();
    $sth->execute($priv_name, $section_id) or die $dbh->errstr();
    while (my $row = $sth->fetchrow()) {
        push @result, $row;
    };
    $sth->finish();
    return wantarray ? @result: \@result;
};

sub get_message_position {
    my $self = shift;
    my $message_id = shift;
    my $dbh = $self->dbh();
    
    my ($position) = $dbh->selectrow_array("select count(1) from forums_messages m1, forums_messages m2 where m1.id=? and m1.theme_id=m2.theme_id and m2.create_date<m1.create_date", undef, $message_id);
    die $dbh->errstr() if ($dbh->err());
    $position = 0 unless defined $position;
    $position++;
    return $position;
};

sub register_user_access {
    my $self = shift;
    my $user_id = shift;
    my $dbh = $self->dbh();
    $dbh->do("insert into forums_users_last_access(user_id, access_time) values(?, ?)", undef, $user_id, $self->db()->datetime_to_db(utc_current_datetime())) or die $dbh->errstr();
};

sub is_online_user {
    my $self = shift;
    my $user_id = shift;
    my $dbh = $self->dbh();
    my $db = $self->db();
    my $is_online = 0;
    my $offline_time = $self->forum()->get_offline_user_time();
    my $sql = "";
    if ($db->isa("NG::DBI::Postgres")) {
        $sql = "select 1 from forums_users_last_access where user_id=? and access_time + interval '". $offline_time." minute' >= ?";
    }
    else {
        $sql = "select 1 from forums_users_last_access where user_id=? and access_time + interval ". $offline_time." minute >= ?";
    }
    $sql = $db->sqllimit($sql ,0, 1);
    ($is_online) = $dbh->selectrow_array($sql, undef, $user_id, $db->datetime_to_db(utc_current_datetime()));
    die $dbh->errstr() if ($dbh->err());
    return $is_online;
}

sub mailer_to_groups {
    my $self = shift;
    my %args = @_;
    my $message = ${$args{message}};
    my @groups = @{$args{groups}};
    
    return undef if (is_empty($message) || !scalar @groups);

    my $forum = $self->forum();
    my $id_field = $forum->get_user_field_name("id");
    my $email_field = $forum->get_user_field_name("email");
    my $user_table = $forum->get_user_table();
    my @emails = ();
    my $dbh = $self->dbh();
    my $sql = sprintf("select distinct u.%s from forums_users_groups_links gl, %s u where gl.group_id in (%s) and gl.user_id=u.%s", $email_field, $user_table, join(",", @groups), $id_field);
    my $sth = $dbh->prepare($sql) or die $dbh->errstr();
    $sth->execute() or die $dbh->errstr();
    while (my $row = $sth->fetchrow()) {
        push @emails, $row;
    }; 
    $sth->finish();
    
    $forum->_send_email(
        to=>\@emails,
        subject=>$forum->getResource("MAILERTOGROUP_MAIL_SUBJECT"),
        plain=>$message
    );
    
};

sub get_user_subscribe {
    my $self = shift;
    my $user_id = shift;
    my $dbh = $self->dbh();
    
    my $subscribe = $dbh->selectall_arrayref("select t.id, t.name from forums_themes_subscribe s, forums_themes t where s.user_id=? and s.theme_id=t.id order by t.name", {Slice=>{}}, $user_id);
    die $dbh->errstr() if ($dbh->err());
    
    return wantarray? @$subscribe: $subscribe;
};

sub delete_subscribe {
    my $self = shift;
    my $user_id = shift;
    my $theme_id = shift;
    my $dbh = $self->dbh();
    $dbh->do("delete from forums_themes_subscribe where user_id=? and theme_id=?", undef, $user_id, $theme_id) or die $dbh->errstr();
    
};

sub get_banned_ip {
    my $self = shift;
    my $dbh = $self->dbh();
    my $result = $dbh->selectall_arrayref("select id,ip from forums_ip_bans order by id desc", {Slice=>{}});
    die $dbh->errstr() if ($dbh->err());
    return wantarray? @$result: $result;
};

sub send_theme_to_email {
    my $self = shift;
    my $theme_id = shift;
    my $email = shift;
    my $cms = $self->cms();

    my $forum = $self->forum();
    my $user = $forum->get_user();
    my $template = $forum->gettemplate("mail/themetoemail.tmpl") or die $cms->error();
    my $subject = $forum->getResource("THEMETOEMAIL_EMAIL_SUBJECT");
    
    my $username = $user->login();
    my $forumname = $forum->get_forumname();
    $subject =~ s/\<username\>/$username/;
    $subject =~ s/\<forum\>/$forumname/;
    my $theme = $self->get_theme($theme_id);
    $template->param(
        USERNAME=>$username,
        THEMENAME=>$theme->{name},
        FORUMNAME=>$forumname,
        THEMELINK=>getURLWithParams($forum->get_forum_url(), {
            action=>"showmessages",
            theme_id=>$theme->{id}
        })
    ); 
    $forum->_send_email(
        to=>$email,
        subject=>$subject,
        plain=>$template->output()
    ); 
};

sub get_unread_themes {
    my $self = shift;
    my $user_id = shift;
    my $dbh = $self->dbh();
    
    my $themes = $dbh->selectall_arrayref("select t.id,t.author_user_id,t.lastupdate_date,t.author,s.name as section_name,s.id as section_id,t.name from forums_themes t,(select distinct t.id from forums_themes_read tr, forums_themes t where t.lastupdate_date>tr.read_time and tr.user_id=? and tr.theme_id=t.id	union select t.id from  forums_themes t where t.id not in (select tr.theme_id from forums_themes_read tr where tr.user_id=?)) tr, forums f, forums_sections s where tr.id=t.id and t.forum_id=f.id and f.section_id=s.id order by s.position,f.position,t.lastupdate_date desc", {Slice=>{}}, $user_id, $user_id);
    die $dbh->errstr() if ($dbh->err());
    return wantarray? @$themes: $themes;
};

sub get_active_themes {
    my $self = shift;
    my $day = shift;
    $day = 1 unless is_valid_id($day);
    my $db = $self->db();
    my $current_datetime = $db->datetime_to_db(utc_current_datetime());
    my $sth = undef;
    my $dbh = $self->dbh();
    my $themes = [];
    if ($db->isa("NG::DBI::Postgres")) {
        $sth = $dbh->prepare("select t.id,t.name,t.lastupdate_date,t.author_user_id,t.author from forums_themes t where t.lastupdate_date+interval '". $day. " day' >= ? order by t.lastupdate_date desc") or die $dbh->errstr();
        $sth->execute($current_datetime) or die $dbh->errstr();        
    }
    elsif ($db->isa("NG::DBI::Mysql")) {
        $sth = $dbh->prepare("select t.id,t.name,t.lastupdate_date,t.author_user_id,t.author from forums_themes t where t.lastupdate_date+interval ? day >= ? order by t.lastupdate_date desc") or die $dbh->errstr();
        $sth->execute($day, $current_datetime) or die $dbh->errstr();
    };
    while (my $row = $sth->fetchrow_hashref()) {
        push @$themes, $row;
    }; 
    
    return wantarray? @$themes: $themes;
};

sub get_active_users {
    my $self = shift;
    my $day = shift;
    $day = 1 unless is_valid_id($day);
    my $db = $self->db();
    my $current_datetime = $db->datetime_to_db(utc_current_datetime());
    my $sth = undef;
    my $dbh = $self->dbh();
    my $users = [];
    if ($db->isa("NG::DBI::Postgres")) {
        $sth = $dbh->prepare("select distinct m.author_user_id as id, m.author as login, t.name as theme, m.theme_id, m.create_date  from forums_messages m,forums_themes t where m.create_date+interval '". $day. " days' >= ? and m.author_user_id is not null and m.author_user_id>0 and t.id=m.theme_id order by m.author") or die $dbh->errstr();
        $sth->execute($current_datetime) or die $dbh->errstr();        
    }
    elsif ($db->isa("NG::DBI::Mysql")) {
        $sth = $dbh->prepare("select distinct m.author_user_id as id, m.author as login, t.name as theme, m.theme_id, m.create_date from forums_messages m,forums_themes t where m.create_date+interval ? day >= ? and m.author_user_id is not null and m.author_user_id>0 and t.id=m.theme_id order by m.author") or die $dbh->errstr();
        $sth->execute($day, $current_datetime) or die $dbh->errstr();
    };
    my $forum = $self->forum();
    while (my $row = $sth->fetchrow_hashref()) {
        $row->{create_date} = $forum->datetime_from_db($row->{create_date});
        push @$users, $row;
    }; 
    
    return wantarray? @$users: $users;
};

1; 