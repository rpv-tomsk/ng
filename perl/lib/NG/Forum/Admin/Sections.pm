package NG::Forum::Admin::Sections;
use strict;
use base qw(NG::Module::List);

sub config {
    my $self = shift;
    $self->tablename("forums_sections");
    
    $self->fields(
        {TYPE=>"id", FIELD=>"id"},
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
    
    $self->add_url_field("name", "/admin-side/pages/".$page_id."/sections/forums/?section_id={id}");
};

sub afterDelete {
    my ($self, $id, $form) = (@_);
    my $dbh = $self->dbh();
    #delete search indexes
    $dbh->do("delete from forums_search_indexes where message_id is not null and message_id in (select m.id from forums_messages m, forums_themes t, forums f where f.section_id=? and t.forum_id=f.id and m.theme_id=t.id)", undef, $id) or $self->error($dbh->errstr());
    $dbh->do("delete from forums_search_indexes where theme_id is not null and theme_id in (select t.id from forums_themes t, forums f where f.section_id=? and t.forum_id=f.id)", undef, $id) or $self->error($dbh->errstr());
    
    #delete messages and files
    $dbh->do("update forums_messages_files  set is_delete=0 where message_id in (select m.id from forums_messages m, forums_themes t, forums f where f.section_id=? and t.forum_id=f.id and m.theme_id=t.id)", undef, $id) or return $self->error($dbh->errstr());
    $dbh->do("delete from forums_messages where theme_id in (select t.id from forums_themes t, forums f where f.section_id=? and t.forum_id=f.id)", undef, $id) or return $self->error($dbh->errstr());

    #delete themes, polls, subscribes and read time info
    $dbh->do("delete from forums_themes_subscribe where theme_id in (select t.id from forums_themes t, forums f where f.section_id=? and t.forum_id=f.id)", undef, $id) or $self->error($dbh->errstr());
    $dbh->do("delete from forums_themes_read where theme_id in (select t.id from forums_themes t, forums f where f.section_id=? and t.forum_id=f.id)", undef, $id) or $self->error($dbh->errstr());
    $dbh->do("delete from forums_themes_polls_variants where poll_id in (select p.id from forums_themes_polls p, forums_themes t, forums f where f.section_id=? and t.forum_id=f.id and p.theme_id=t.id)", undef, $id) or $self->error($dbh->errstr());
    $dbh->do("delete from forums_themes_polls_logs where poll_id in (select p.id from forums_themes_polls p, forums_themes t, forums f where f.section_id=? and t.forum_id=f.id and p.theme_id=t.id)", undef, $id) or $self->error($dbh->errstr());
    $dbh->do("delete from forums_themes_polls where theme_id in (select t.id from forums_themes t, forums f where f.section_id=? and t.forum_id=f.id)", undef, $id) or $self->error($dbh->errstr());    
    $dbh->do("delete from forums_themes where forum_id in (select f.id forums f where f.section_id=?)", undef, $id) or $self->error($dbh->errstr());

    #delete privs
    $dbh->do("delete from forums_groups_privs where section_id=?", undef, $id) or return $self->error($dbh->errstr());

    #delete forums    
    $dbh->do("delete from forums where section_id=?", undef, $id) or $self->error($dbh->errstr());
    
    return 1;
};                             


sub afterInsertUpdate {
    my $self = shift;
    my $form = shift;
    my $action = shift;
    if ($action eq "insert") {
        my $id = $form->getValue("id");
        my $m_obj = $self->getModuleObj();
        my $user_model = $m_obj->get_user_model();
        my $default_group = $user_model->get_default_group_id();
        my $anonymous_group = $user_model->get_anonymous_group_id();
        my $access_priv = $user_model->get_access_priv_name();
        my $write_priv = $user_model->get_write_priv_name();
        $user_model->set_priv_to_forum_section($id, $default_group, $access_priv);
        $user_model->set_priv_to_forum_section($id, $default_group, $write_priv);
        $user_model->set_priv_to_forum_section($id, $anonymous_group, $access_priv);
        $user_model->set_priv_to_forum_section($id, $anonymous_group, $write_priv);
    }; 
    return NG::Block::M_OK;
};

1;