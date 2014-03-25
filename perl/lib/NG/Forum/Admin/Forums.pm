package NG::Forum::Admin::Forums;
use strict;
use base qw(NG::Module::List);

sub config {
    my $self = shift;
    $self->tablename("forums");
    
    $self->fields(
        {TYPE=>"id", FIELD=>"id"},
        {TYPE=>"fkparent", FIELD=>"section_id"},
        {TYPE=>"text", FIELD=>"name", IS_NOTNULL=>1, NAME=>"Название"},
        {TYPE=>"posorder", FIELD=>"position", IS_NOTNULL=>1, NAME=>"Позиция"},
    );
    
    $self->listfields(
        {FIELD=>"name"}
    );
    
    $self->formfields(
        {FIELD=>"id"},
        {FIELD=>"name"}
    );

    my $page_id = $self->getPageId();
    $self->addTopbarLink({NAME=>"Назад", URL=>"/admin-side/pages/".$page_id."/sections/"});
};


sub afterDelete {
    my ($self, $id, $form) = (@_);
    my $dbh = $self->dbh();
    #delete search indexes
    $dbh->do("delete from forums_search_indexes where message_id is not null and message_id in (select m.id from forums_messages m, forums_themes t where t.forum_id=? and m.theme_id=t.id)", undef, $id) or $self->error($dbh->errstr());
    $dbh->do("delete from forums_search_indexes where theme_id is not null and theme_id in (select t.id from forums_themes t where t.forum_id=?)", undef, $id) or $self->error($dbh->errstr());
    
    #delete messages and files
    $dbh->do("update forums_messages_files  set is_delete=0 where message_id in (select m.id from forums_messages m, forums_themes t where t.forum_id=? and m.theme_id=t.id)", undef, $id) or return $self->error($dbh->errstr());
    $dbh->do("delete from forums_messages where theme_id in (select t.id from forums_themes t where t.forum_id=?)", undef, $id) or return $self->error($dbh->errstr());

    #delete themes, polls, subscribes and read time info
    $dbh->do("delete from forums_themes_subscribe where theme_id in (select t.id from forums_themes t where t.forum_id=?)", undef, $id) or $self->error($dbh->errstr());
    $dbh->do("delete from forums_themes_read where theme_id in (select t.id from forums_themes t where t.forum_id=?)", undef, $id) or $self->error($dbh->errstr());
    $dbh->do("delete from forums_themes_polls_variants where poll_id in (select p.id from forums_themes_polls p, forums_themes t where t.forum_id=? and p.theme_id=t.id)", undef, $id) or $self->error($dbh->errstr());
    $dbh->do("delete from forums_themes_polls_logs where poll_id in (select p.id from forums_themes_polls p, forums_themes t where t.forum_id=? and p.theme_id=t.id)", undef, $id) or $self->error($dbh->errstr());
    $dbh->do("delete from forums_themes_polls where theme_id in (select t.id from forums_themes t where t.forum_id=?)", undef, $id) or $self->error($dbh->errstr());    
    $dbh->do("delete from forums_themes where forum_id=?", undef, $id) or $self->error($dbh->errstr());
    
    #delete privs
#     $dbh->do("delete from forums_groups_privs where forum_id=?", undef, $id) or retur $self->error($dbh->errstr());    
    
    return 1;
};


1;