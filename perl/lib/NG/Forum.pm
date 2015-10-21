package NG::Forum;
use strict;
use NG::SiteStruct;
use NG::Forum::Date;
use NSecure;
use NGService;
use URI::Escape;
use base qw(NG::PageModule);
use Data::Dumper;
use Time::HiRes;
use NHtml;
use NG::Forum::BBCodes;
use GD;
use Digest::MD5 qw(md5_hex);
use NMailer;

# use constant DEFAULT_FILE_COUNT=>1;

sub moduleTabs {
    return [
        {URL=>"/", HEADER=>"Структура"},
        {URL=>"/sections/", HEADER=>"Разделы форума"},
    ];
};

sub moduleBlocks {
    return [
        {URL=>"/", BLOCK=>"NG::SiteStruct::Block"},
        {URL=>"/sections/", BLOCK=>"NG::Forum::Admin::Sections", TYPE=>"moduleBlock"},
        {URL=>"/sections/forums/", BLOCK=>"NG::Forum::Admin::Forums", TYPE=>"moduleBlock"},
    ];
};

sub init {
    my $self = shift;
    $self->{_user} = undef;
    $self->{_modules} = {};
    $self->{_cookiename} = "";
    $self->{_user_table_config} = {};
    $self->{_template_dir} = "forum/"; 
    $self->{_layout} = "";
    $self->{_current_url} = undef;
    $self->{_tz} = "0000";
    
    $self->{_themes_onpage} = 10;
    $self->{_themes_onlist} = 10;
    $self->{_messages_onpage} = 10;
    $self->{_messages_onlist} = 10;
    $self->{_pager_onpage} = 10;
    $self->{_pager_onlist} = 10;  
    
    $self->{_editors} = ["text", "extend"];
    $self->{_editor} = 0; 
    
    $self->{_max_file_size} = 1024*1024*1;
    $self->{_max_total_files_size} = 1024*1024*5;
    $self->{_max_files_count} = 6; 
    $self->{_files_upload_dir} = "/upload/forum/messages_files/";
    $self->{_avatars_upload_dir} = "/upload/forum/avatars/";
    $self->{_avatar_size} = 100;
    
    $self->{_user_model_module} = "NG::Forum::Model::Users";
    $self->{_forum_model_module} = "NG::Forum::Model::Forum";
    $self->{_user_factory_module} = "NG::Forum::Users::Factory";
    $self->{_authorize_via_email} = 0;
    $self->{_smileys_dir} = "/js/forum/editor/smileys/";
    
    $self->{_javascript} = [];
    $self->{_css} = [];
    
    $self->{_from_email} = "noreply\@forum.ru";
    
    $self->{_panels} = {
        login=>1,
        reg=>1,
        logout=>1,
        search=>1,
        profile=>1,
        recoverypwd=>1,
        userslist=>1,
        groupsadmin=>1,
        pager=>1,
        banip=>1,
        "index"=>1,
        mailertogroup=>1,
        newmessages=>1,
        activethemes=>1,
        activeusers=>1,
    };
    
    $self->{_benchmark} = 0;
    
    $self->{_user_table_config} = {
        table=>"forums_users",
        id_field=>"id",
        login_field=>"login",
        password_field=>"password",
        email_field=>"email",
        session_field=>"session",
    };
    
    $self->{_external_registration} = 0;
    $self->{_history} = [];
    $self->{_users_status_on} = 1;
    $self->{_users_status_messages_limit} = [0,10,50,100,300,500,1000,2000,5000,10000,100000];
    
    $self->{_forumname} = "forumname";
    
    $self->{_anonymous_must_die} = 0;
    
    $self->{_valid_user_filters} = {};
    $self->{_offline_user_time} = 5; # in minute
    
    $self->settings();
    return $self->SUPER::init(@_);
};

sub settings {};

sub set_valid_user_filters {
    my $self = shift;
    my %args = (@_);
    $self->{_valid_user_filters} = \%args; 
};

sub get_offline_user_time {
    my $self = shift;
    return $self->{_offline_user_time}; 
};

sub get_valid_user_filters {
    my $self = shift;
    return $self->{_valid_user_filters};
};

sub disable_anonymous_users {
    my $self = shift;
    $self->{_anonymous_must_die} = 1;
};

sub is_disabled_anonymous_users {
    my $self = shift;
    return $self->{_anonymous_must_die};
};

sub disable_registration {
    my $self = shift;
    $self->{_external_registration} = 1;
    $self->{_panels}->{reg} = 0;
};

sub set_extends_user {
    my $self = shift;
    my $table = shift;
    my @fields = (@_);
    $self->{_extends_users} = {
        table => $table,
        fields => \@fields
    };
};

sub is_extend_user {
    my $self = shift;
    return defined $self->{_extends_users}? 1: 0;
};

sub get_extends_fields {
    my $self = shift;
    return wantarray? @{$self->{_extends_users}->{fields}}: $self->{_extends_users}->{fields}; 
};

sub get_extends_table {
    my $self = shift;
    return $self->{_extends_users}->{table}; 
};

sub set_forumname {
    my $self = shift;
    $self->{_forumname} = shift;
};

sub get_forumname {
    my $self = shift;
    return $self->{_forumname};
};

sub register_user_access {
    my $self = shift;
    my $user = $self->get_user();
    if ($user->id()) {
        $self->get_forum_model()->register_user_access($user->id());
    };
};

sub on_users_status {
    my $self = shift;
    $self->{_users_status_on} = 1;
};

sub off_users_status {
    my $self = shift;
    $self->{_users_status_on} = 0;
};

sub set_users_status {
    my $self = shift;
    my @limits = (@_);
    $self->{_users_status_messages_limit} = \@limits;
};

sub get_user_status {
    my $self = shift;
    my $messages_count = shift || 0;
    my @messages_limit = sort{$b<=>$a} @{$self->{_users_status_messages_limit}};
    my $index = scalar @messages_limit;
    foreach my $limit (@messages_limit) {
        last if ($messages_count>=$limit);
        $index--;
    };
    $index = 1 unless $index;
    return $self->getResource("FORUM_USERS_STATUS_".$index);
};

sub add_history {
    my ($self, @history) = (@_);
    push @{$self->{_history}}, @history;
};

sub set_from_email {
    my $self = shift;
    $self->{_from_email} = shift;
};

sub get_from_email {
    my $self = shift;
    return $self->{_from_email};
};

sub set_smileys_dir {
    my $self = shift;
    $self->{_smileys_dir} = shift;
};

sub get_smileys_dir {
    my $self = shift;
    return $self->{_smileys_dir};
};

sub enable_benchmark {
    my $self = shift;
    $self->{_benchmark} = 1;    
};

sub set_avatars_upload_dir {
    my $self = shift;
    my $value = shift;
    $self->{_avatars_upload_dir} = $value;
};

sub get_avatars_upload_dir {
    my $self = shift;
    return $self->{_avatars_upload_dir};
};

sub getBlockContent {
    my $self = shift;
    return $self->SUPER::getBlockContent(@_) unless $self->{_benchmark};
    
    my $t1 = Time::HiRes::time();
    my $ret = $self->SUPER::getBlockContent(@_);
    my $t2 = Time::HiRes::time();
    
    my $action = shift;
    print STDERR sprintf("FORUM BECHMARK action %s  - %f sec", $action, $t2-$t1);
    return $ret;
};


#-------------------------------------------------------------- Common functions
sub parse_bb {
    my $self = shift;
    my $text = shift;
    
    $text =~ s/\[\s+(\S+?)(\s*.*?)\]/\<$1 $2\>/gi;
    $text =~ s/\[(\/\S+?)\s+\]/\<$1>/gi;
    
    return $text;
};

sub fix_bb {
    my $self = shift;
    my $text = shift;
    return $text;
};

sub processModulePost {
    my $self = shift;
    my $q = $self->q();
    my $action = $q->param("post_action") || $q->url_param("post_action") || $q->url("action") || $q->url_param("action");
    my $method = "post_".$action;
    
    my $user = $self->get_user();
    if (!$user->id() && $self->is_disabled_anonymous_users() && $action ne "login") {
        return  $self->redirect($self->get_forum_url(). "?action=login");
    };    
    
    
    if ($self->can($method)) {
        return $self->$method();
    };
    return 1;
};

sub disable_panels_login {
    my $self = shift;
    $self->{_panels}->{login} = 0;
};

sub disable_panels_logout {
    my $self = shift;
    $self->{_panels}->{logout} = 0;
};

sub disable_panels_search {
    my $self = shift;
    $self->{_panels}->{search} = 0;
};

sub disable_panels_profile {
    my $self = shift;
    $self->{_panels}->{profile} = 0;
};

sub disable_panels_recoverypwd {
    my $self = shift;
    $self->{_panels}->{recoverypwd} = 0;
};

sub get_gravatar_url {
    my $self = shift;
    my $email = shift;
    $email =~ s/\s//gi;
    my $size = $self->get_avatar_size();
#     my $grav_url = "http://www.gravatar.com/avatar/".md5_hex(lc $email)."?d=".uri_escape($default)."&s=".$size;
    my $grav_url = "http://www.gravatar.com/avatar/".md5_hex(lc $email)."?&s=".$size;
    return $grav_url;
};

sub get_referer {
    my $self = shift;
    my $q = $self->q();
    my $ref = $q->param("ref") || $q->url_param("ref");
    my $current_url = $self->get_current_url();
    $ref = $self->get_forum_url() if (!defined $ref || $ref eq $current_url);
    return $ref;
};

sub get_referer_param {
    my $self = shift;
    my $q = $self->q();
    my $ref = $q->param("ref") || $q->url_param("ref") || $self->get_current_url();
    return sprintf("ref=%s", uri_escape($ref));    
};

sub get_current_referer_param {
    my $self = shift;
    my $q = $self->q();
    my $ref = $self->get_current_url();
    return sprintf("ref=%s", uri_escape($ref));    
};

sub get_panel {
    my $self = shift;
    my $panel = {};
    my $action = $self->q()->param("action") || $self->q()->url_param("action") || "index"; 
    
    foreach my $key (keys %{$self->{_panels}}) {
        if ($self->{_panels}->{$key}) {
            $panel->{$key}->{value} = $key;
            $panel->{$key}->{current} = $action eq $key? 1: 0;
        };
    };
    return $panel;
};

sub set_javascript {
    my $self = shift;
    my @javascript = @_;
    $self->{_javascript} = \@javascript if (scalar @javascript);
};

sub _die {
    my $self = shift;
    die Dumper(@_);
};

sub set_authorize_via_email {
    my $self = shift;
    $self->{_authorize_via_email} = 1;
};

sub is_authorize_via_email {
    my $self = shift;
    return $self->{_authorize_via_email};
};

sub set_max_file_size {
    my $self = shift;
    $self->{_max_file_size} = shift;
};

sub get_max_file_size {
    my $self = shift;
    return $self->{_max_file_size};
};

sub set_max_total_files_size {
    my $self = shift;
    $self->{_max_total_files_size} = shift;
};

sub get_max_total_files_size {
    my $self = shift;
    return $self->{_max_total_files_size};
};

sub set_max_files_count {
    my $self = shift;
    $self->{_max_files_count} = shift;
};

sub get_max_files_count {
    my $self = shift;
    return $self->{_max_files_count};
};

sub set_files_upload_dir {
    my $self = shift;
    $self->{_files_upload_dir} = shift;
};

sub get_files_upload_dir {
    my $self = shift;
    return $self->{_files_upload_dir};
};

sub set_css {
    my $self = shift;
    my @css = @_;
    $self->{_css} = \@css if (scalar @css);
};

sub get_javascript {
    my $self = shift;
    return wantarray ? @{$self->{_javascript}} : $self->{_javascript};
};

sub get_css {
    my $self = shift;
    return wantarray ? @{$self->{_css}} : $self->{_css};
};

sub set_avatar_size {
    my $self = shift;
    my $value = shift;
    $self->{_avatar_size} = $value;
};

sub get_avatar_size {
    my $self = shift;
    return $self->{_avatar_size};
};

sub set_editor {
    my $self = shift;
    my $editor_name = shift || "";
    my $i = 0;
    foreach (@{$self->{_editors}}) {
        if ($_ eq $editor_name) {
            $self->{_editor} = $i;
            last;
        };
        $i++;
    };
};

sub get_editors_list {
    my $self = shift;
    my @editors = @{$self->{_editors}};
    return wantarray ? @editors : \@editors;
};

sub get_current_editor {
    my $self = shift;
    my $user = $self->get_user();
    $self->set_editor($user->get("editor")) if ($user->id());
    return $self->{_editors}->[$self->{_editor}];
};

sub get_page {
    my $self = shift;
    my $pagename = shift || "page";
    my $q = $self->q();
    my $page = $q->param($pagename);
    $page = 1 unless is_valid_id($page);
    return $page;
};

sub get_forum_url {
    my $self = shift;
    my $q = $self->q();
    my $vhost = $q->virtual_host();
    unless (defined $self->{_current_url}) {
        my $pagerow = $self->getPageRow();
        $self->{_current_url} = defined $pagerow ? $pagerow->{url} : "";
    };
    return "http://".$vhost.$self->{_current_url};
};

sub get_current_url {
    my $self = shift;
    my $q = $self->q();
    return $q->url(-query=>1);
};

sub is_post {
    my $self = shift;
    my $q = $self->q();
    my $method = $q->request_method();
    return $method =~ /post/i;
};

sub get_themes_onpage {
    my $self = shift;
    return $self->{_themes_onpage};
};

sub get_themes_onlist {
    my $self = shift;
    return $self->{_themes_onlist};
};

sub get_pager_onpage {
    my $self = shift;
    return $self->{_pager_onpage};
};

sub get_pager_onlist {
    my $self = shift;
    return $self->{_pager_onlist};
};

sub get_messages_onpage {
    my $self = shift;
    return $self->{_messages_onpage};
};

sub get_messages_onlist {
    my $self = shift;
    return $self->{_messages_onlist};
};

sub set_themes_onpage {
    my $self = shift;
    my $value = shift;
    return unless is_valid_id($value); 
    return $self->{_themes_onpage} = $value;
};

sub set_themes_onlist {
    my $self = shift;
    my $value = shift;
    return unless is_valid_id($value);    
    return $self->{_themes_onlist} = $value;
};

sub set_messages_onpage {
    my $self = shift;
    my $value = shift;
    return unless is_valid_id($value);    
    return $self->{_messages_onpage} = $value;
};

sub set_messages_onlist {
    my $self = shift;
    my $value = shift;
    return unless is_valid_id($value);    
    return $self->{_messages_onlist} = $value;
};

sub set_pager_onpage {
    my $self = shift;
    my $value = shift;
    return unless is_valid_id($value);    
    return $self->{_pager_onpage} = $value;
};

sub set_pager_onlist {
    my $self = shift;
    my $value = shift;
    return unless is_valid_id($value);    
    return $self->{_pager_onlist} = $value;
};

sub get_layout {
    my $self = shift;
    return $self->{_layout};
};

sub set_layout {
    my $self = shift;
    my $layout = shift;
    $self->{_layout} = $layout;
};

sub redirect {
    my $self = shift;
    my $url = shift;
    my $cms = $self->cms();
    return $cms->redirect($url);
};

sub redirect_to_ref {
    my $self = shift;
    my $def_url = shift || undef;
    my $ref = $self->get_referer() || $def_url || $self->get_forum_url();
    return $self->redirect($ref);
};

sub output {
    my $self = shift;
    my $content = shift;
    my $headers = shift || undef;
    my $head = shift || undef;
    my $cms = $self->cms();
    
    my $css = $self->get_css();
    my $javascript = $self->get_javascript();
    
    $head = {} unless (defined $head);
    $head->{jslist} = [] unless (exists $head->{jslist});
    $head->{csslist} = [] unless (exists $head->{jslist});
    
    foreach (@$javascript) {
        push @{$head->{jslist}}, $_;
    };
    
    foreach (@$css) {
        push @{$head->{csslist}}, $_;
    };
#         
#     use Data::Dumper;
#     die Dumper($headers, $head);
    return $cms->output($content, $headers, $head);
};

sub get_ip {
    my $self = shift;
    my $q = $self->q();
    my $ip = $q->remote_addr();
    return $ip;
};

sub set_template_dir {
    my $self = shift;
    my $dir = shift || "";
    $self->{_template_dir} = $dir;
};

sub get_template_dir {
    my $self = shift;
    return $self->{_template_dir};
};


sub paginator {
    my $self = shift;
    my %args = (@_);
    
    my $size = $args{size} || 0;
    return {} unless $size;
    my $page = $args{page} || 1;
    my $onpage = $args{onpage} || 20;
    my $onlist = $args{onlist} || 6;
    my $limitpage = $args{limitpage} || 2;
    my $url = $args{url} || "";
    my $pagename = $args{pagename} || "page";
    
    my $pages_count = int(($size-1) / $onpage)+1;
    
    my @pages = ();
    my $paginator = {};
    
    if ($pages_count > 1) {
        
        if ($page>1) {
            $paginator->{prev_url} = getURLWithParams($url, $pagename."=".($page-1));
        };
        
        if ($page<$pages_count) {
            $paginator->{next_url} = getURLWithParams($url, $pagename."=".($page+1));
        };    
        
        $onlist--;
        my $indent_right = int($onlist / 2);
        my $right_border = $page - $indent_right;
        
        my $left_indent = $onlist - ($page - $right_border);
        my $left_border = $page + $left_indent - 1;
        
        if ($left_indent > $pages_count-$page) {
            $right_border = $right_border - ($left_indent - ($pages_count-$page));
        };        

        $right_border = 1 if($right_border < 1);
        $left_border = $pages_count if($left_border>$pages_count);
        
        for (my $i=$right_border; $i<=$left_border; $i++) {
            push @pages, {
                page=>$i,
                current=>($page == $i) ? 1 : 0,
                normal=>($page == $i) ? 0 : 1,
                url=>getURLWithParams($url, $pagename."=".$i),
                skip=>0
            };
        };    
        
        if ($right_border>1) {
            my $start = 1;
            my $end = $start + $limitpage;
            $end = $right_border if($end > $right_border);
            
            my @limit_pages = ();
            
            for (my $i=$start; $i<$end; $i++) {
                push @limit_pages, {
                    page=>$i,
                    current=>($page == $i) ? 1 : 0,
                    normal=>($page == $i) ? 0 : 1,
                    url=>getURLWithParams($url, $pagename."=".$i),
                    skip=>0
                };
            };
            
            push @limit_pages, {
                skip=>1
            } if($end < $right_border);
            
            @pages = (@limit_pages, @pages);        
        };
        
        if ($left_border<$pages_count) {
            my $start = $pages_count;
            my $end = $start - $limitpage;
            $end = $left_border if($end < $left_border);
            
            my @limit_pages = ();
            
            for (my $i=$start; $i>$end; $i--) {
                unshift @limit_pages, {
                    page=>$i,
                    current=>($page == $i) ? 1 : 0,
                    normal=>($page == $i) ? 0 : 1,
                    url=>getURLWithParams($url, $pagename."=".$i),
                    skip=>0
                };
            };
            
            unshift @limit_pages, {
                skip=>1
            } if($end > $left_border);
            
            @pages = (@pages, @limit_pages);        
        }; 
    };    
    
    $paginator->{pages} = \@pages;
    return $paginator;   
};

sub get_processed_input {
    my $self = shift;
    my @fields = @_;
    my $q = $self->q();
    
    my $data = {};
    
    @fields = $q->param() unless scalar @fields;
    
    foreach (@fields) {
        $data->{$_} = escape_angle_brackets($q->param($_));        
    };
    
    return $data;
};

sub gettemplate {
    my $self = shift;
    my $template_file = shift;
    my $cms = $self->cms();
    my $template = $self->SUPER::gettemplate($self->get_template_dir(). $template_file);
    $self->print_to_template($template);
    return $template;
};

sub print_to_template {
    my $self = shift;
    my $template = shift;
    my $user = $self->get_user();
    my $panel = $self->get_panel();
    my $forum_model = $self->get_forum_model();
    $template->param(
        FORUMOBJ=>{
            HISTORY=>$self->{_history},
            USER=>{
                LOGIN=>$user->login(),
                ID=>$user->id(),
                IS_ROOT=>$user->is_root(),
                IS_MODERATE=>$user->is_global_moderate(),
                IS_SECTION_MODERATE=>$user->is_section_moderate()
            },
            EDITOR=>$self->get_current_editor(),
            PANEL=>$panel,
            FORUM_URL=>$self->get_forum_url(),
            CURRENT_URL=>$self->get_current_url(),
            CURRENT_REFERER=>$self->get_current_url(),
            CURRENT_REFPARAM=>$self->get_current_referer_param(),
            REFPARAM=>$self->get_referer_param(),
            SMILEYS_DIR=>$self->get_smileys_dir(),
            NEW_PAGER_MESSAGE=>$forum_model->get_count_unread_pager_messages($user->id()),
            REFERER=>$self->get_referer(),
        },
    );
};

sub is_banned {
    my $self = shift;
    my $user = $self->get_user();
    return 0 if ($user->is_global_moderate());
    return 1 if ($user->is_banned());
    return 1 if ($self->get_forum_model()->ip_is_banned($self->get_ip()));    
    return 0; 
};
#------------------------------------------------------------------------ Module
sub get_user_model {
    my $self = shift;
    return $self->singlenton($self->get_user_model_module());
};

sub get_forum_model {
    my $self = shift;
    return $self->singlenton($self->get_forum_model_module());
};

sub get_user_factory {
    my $self = shift;
    return $self->singlenton($self->get_user_factory_module());
};

sub singlenton {
    my $self = shift;
    my $module = shift;
    my @params = @_;
    my $cms = $self->cms();
    
    return $self->{_modules}->{$module} if (exists $self->{_modules}->{$module});
    my $obj = $cms->getObject($module, $self, @params);
    return $self->{_modules}->{$module} = $obj  if ($obj);
    
    return undef;     
};

sub module {
    my $self = shift;
    my $module = shift;
    my @params = @_;
    my $cms = $self->cms();
    
    my $obj = $cms->getObject($module, $self, @params);
    return $obj;
};

sub set_user_model_module {
    my $self = shift;
    my $module = shift;
    return $self->{_user_model_module} = $module;
};

sub get_user_model_module {
    my $self = shift;
    return $self->{_user_model_module};
};

sub set_forum_model_module {
    my $self = shift;
    my $module = shift;
    return $self->{_forum_model_module} = $module;
};

sub get_forum_model_module {
    my $self = shift;
    return $self->{_forum_model_module};
};

sub set_user_factory_module {
    my $self = shift;
    my $module = shift;
    return $self->{_user_factory_module} = $module;
};

sub get_user_factory_module {
    my $self = shift;
    return $self->{_user_factory_module};
};

#------------------------------------------------------------------ Tz functions
sub set_server_tz {
    my $self = shift;
    my $tz = shift;
    $self->{_tz} = $tz;  
};

sub get_server_tz {
    my $self = shift;
    return $self->{_tz};
};

sub get_tz {
    my $self = shift;
    my $user = $self->get_user();
    
    return $self->get_server_tz() unless $user->id(); # for anonymous show date in local tz
    return $self->get_server_tz() unless $user->tz();
    return $user->tz();
};

sub date_to_db {
    my $self = shift;
    my $value = shift;
    my $db = $self->db();
    return $db->date_to_db($value);
};

sub datetime_to_db {
    my $self = shift;
    my $value = shift;
    my $db = $self->db();
    return $db->datetime_to_db($value);
};

sub date_from_db {
    my $self = shift;
    my $value = shift;
    my $db = $self->db();
    return $db->date_from_db($value);
};

sub datetime_from_db {
    my $self = shift;
    my $value = shift;
    my $db = $self->db();
    $value = $db->datetime_from_db($value);
    return undef unless is_valid_datetime($value);
    my $tz = $self->get_tz();
    return utc_to_tz($value, $tz);
};
#--------------------------------------------------------------- Users functions

sub set_user_table_config {
    my $self = shift;
    my $args = shift;
    
    foreach (keys %{$self->{_user_table_config}}) {
        $self->{_user_table_config}->{$_} = $args->{$_} if (exists $args->{$_})
    };
    $self->{_external_registration} = 1;
    $self->{_panels}->{reg} = 0;
};

sub set_user_cookiename {
    my $self = shift;
    my $cookiename = shift;
    $self->{_cookiename} = $cookiename;
};

sub get_user_cookiename {
    my $self = shift;
    return $self->{_cookiename};
};


sub get_user {
    my $self = shift;
    if (!defined $self->{_user}) {
        my $user_model = $self->get_user_model();
        $self->{_user} = $user_model->get_authorize_user();    
    };
    return $self->{_user};     
};

sub get_user_table {
    my $self = shift;
    return $self->{_user_table_config}->{table};
};

sub get_user_primary_fields {
    return qw(id login password email session);
};

sub get_user_sql_primary_fields {
    my $self = shift;
    my $table = shift || $self->get_user_table();
    my @fields = ();
    foreach my $field ($self->get_user_primary_fields()) {
        my $table_field = $self->get_user_field_name($field);
        next unless $table_field;
        push @fields, sprintf("%s.%s as %s", $table, $table_field, $field);
    };
    return join(",", @fields);
};

sub get_user_data_fields {
    return qw(avatar gravatar is_banned is_root is_moderate signature messages_cnt tz is_subscribe);
};

sub get_user_sql_data_fields {
    my $self = shift;
    my $table = $self->get_user_table();
    my @fields = ();
    return join(",", map {"forums_users_data.".$_} $self->get_user_data_fields());
};

sub get_user_field_name {
    my $self = shift;
    my $field_name = shift;
    return exists $self->{_user_table_config}->{$field_name."_field"} ? $self->{_user_table_config}->{$field_name."_field"} : $field_name;
};

#-------------------------------------------------------------------- Controller
sub getActiveBlock {
    my $self = shift;
    my $q = $self->q();
    my $action = $q->param("action") || $q->url_param("action") || "index";
    my $is_ajax = $q->param("_ajax") ? 1: 0;
    
    my $layout = $is_ajax ? "" : $self->get_layout();
    $self->register_user_access();

    if ($self->is_banned()) {
        return {BLOCK=>"banpage", LAYOUT=>$layout};
    };
    
    my $user = $self->get_user();
    if (!$user->id() && $self->is_disabled_anonymous_users() && $action ne "login") {
        return  {BLOCK=>"login", LAYOUT=>$self->get_layout()};
    };
    
    if ($user->id() && is_empty($user->login())) {
        return {BLOCK=>"enterlogin", LAYOUT=>$layout};
    };    
    
    return {BLOCK=>$action, LAYOUT=>$layout};
};

sub block_index {
    my $self = shift;
    my $cms = $self->cms();
    my $user = $self->get_user();
    my $forum_model = $self->get_forum_model();
    
    my @forums_sections = $forum_model->get_main_forums();

#     my $forum_url = $self->get_forum_url();
#     $self->add_history(
#         {name=>$self->getResource("HISTORY_ROOT"), url=>$forum_url},
#     );
    my $template = $self->gettemplate("main.tmpl") or return $cms->error();
    $template->param(
        FORUMS_SECTIONS=>\@forums_sections
    );
    
    return $self->output($template);
};

sub block_deletefile {
    my $self = shift;
    my $user = $self->get_user();    
    my $q = $self->q();
    my $forum_model = $self->get_forum_model();
    my $cms = $self->cms();
    
    my $id = $q->param("id")+0;
    my $file = $forum_model->get_message_file($id);
    return $cms->notFound() unless $file;
    my $message = $forum_model->get_message($file->{message_id});
    return $cms->notFound() unless $message; 
    
    return $self->noaccess() if ($user->can_moderate($message->{section_id}) && $user->id() != $message->{author_user_id});
    return $self->noaccess() if (!$user->id());
    
    $forum_model->delete_message_file($file);
    return $self->redirect_to_ref($self->get_forum_url());
             
};

sub block_closetheme {
    my $self = shift;
    my $q = $self->q();
    my $cms = $self->cms();
    my $theme_id = $q->param("theme_id")+0;
    
    my $forum_model = $self->get_forum_model();
    my $user = $self->get_user();
    my $theme = $forum_model->get_theme($theme_id);
    
    return $cms->notFound() unless $theme;
    return $self->noaccess() unless $user->can_moderate($theme->{section_id});
    
    $forum_model->close_theme($theme_id);
    return $self->redirect_to_ref();
};

sub block_opentheme {
    my $self = shift;
    my $q = $self->q();
    my $cms = $self->cms();
    my $theme_id = $q->param("theme_id")+0;
    
    my $forum_model = $self->get_forum_model();
    my $user = $self->get_user();
    my $theme = $forum_model->get_theme($theme_id);
    
    return $cms->notFound() unless $theme;
    return $self->noaccess() unless $user->can_moderate($theme->{section_id});
    
    $forum_model->open_theme($theme->{id});
    return $self->redirect_to_ref();
};

sub block_profile {
    my $self = shift;
    my $cms = $self->cms();
    my $user = $self->get_user();
    return $cms->notFound() unless $user->id();
    my $q = $self->q();
    my $profile = $user->get_data_hash();
    my $forum_url = $self->get_forum_url();
    my $user_model = $self->get_user_model();
    my $errors = {};
    my @extends = ();
    @extends = $self->get_user_model()->get_extends_data($user->id()) if($self->is_extend_user());
    
    if ($self->is_post()) {
        my $formaction = $q->param("formaction");
        my $cgi = $self->get_processed_input();
        
        if ($formaction eq "change") {
            $errors->{password} = 1 if ($cgi->{password} ne $profile->{password});
            $errors->{retype_password} = 1 if (!is_empty($cgi->{new_password}) && $cgi->{new_password} ne $cgi->{retype_password});
            $errors->{email} = 1 if (!is_valid_email($cgi->{email}));
            $errors->{email_duplicate} = 1 if (!scalar keys %$errors && $user_model->has_email_duplicate($cgi->{email}, $profile->{id}));
            
            $profile->{password} = $cgi->{new_password} if (!is_empty($cgi->{new_password}) && !scalar keys %$errors);
            $profile->{email} = $cgi->{email};
            $user->set_data_hash($profile);
            $user->save();            
        }; 
        
        if ($formaction eq "avatar") {
            my $dir = $cms->getDocRoot().$self->get_avatars_upload_dir();
            if ($q->param("deleteavatar")) {
                unlink $dir.$profile->{avatar} if ($profile->{avatar});
                $profile->{avatar} = undef;
            }
            else {
                my ($ret, $res) = $user_model->upload_avatar();
                if ($ret) {
                    $profile->{avatar} = $res;
                }
                else {
                    $res->{avatar} = $res;
                };                          
            };
            $user->set_data_hash($profile);
            $user->save();            
        };
        
        if ($formaction eq "tz") {
            $profile->{tz} = $cgi->{tz};
            $user->set_data_hash($profile);
            $user->save();                
        };                           
        
        if ($formaction eq "other") {
            $profile->{signature} = $cgi->{signature};
            $profile->{is_subscribe} = $cgi->{is_subscribe}? 1: 0;
            $user->set_data_hash($profile);
            $user->save();            
        };
        
        if ($formaction eq "extend" && $self->is_extend_user()) {
            foreach (@extends) {
                $_->{error} = 1 if ($_->{notnull} && is_empty($cgi->{$_->{name}}));
            };
            $self->get_user_model->save_extends_data($user->id(), $cgi);
        };
        
        if (!scalar keys %$errors) {
            return $self->redirect(getURLWithParams($forum_url, {
                action=>"profile"
            }));
        };        
    };
    
    
    
    my $template = $self->gettemplate("profile.tmpl") or return $cms->error();
    my @zones = $user_model->get_utc_zones();
    $template->param(
        PROFILE=>$profile,
        ERRORS=>$errors,
        AVATARS_UPLOAD_DIR=>$self->get_avatars_upload_dir(),
        ZONES=>\@zones,
        EXTENDS=>\@extends
    );
    return $self->output($template);
};

sub block_showthemes {
    my $self = shift;
    my $cms = $self->cms();
    my $q = $self->q();
    my $user = $self->get_user();
    my $user_model = $self->get_user_model();
    my $forum_model = $self->get_forum_model();
    
    my $forum_id = $q->param("forum_id");
    my $forum = $forum_model->get_forum($forum_id);
    return $cms->notFound() unless $forum;
    return $self->noaccess() unless $user->can_access($forum->{section_id});
    return $self->block_banpage() if ($forum_model->user_is_banned_on_section($user->id(), $forum->{section_id}));
    
    my $forum_url = $self->get_forum_url();
    my $section = $forum_model->get_section($forum->{section_id});    
    $self->add_history(
        {name=>$self->getResource("HISTORY_ROOT"), url=>$forum_url},
        {name=>$section->{name}, url=>getURLWithParams($forum_url, {action=>"showforums", section_id=>$section->{id}})},
        {name=>$forum->{name}, url=>getURLWithParams($forum_url, {action=>"showthemes", forum_id=>$forum->{id}})},
    );    
    
    my $template = $self->gettemplate("themes.tmpl") or return $cms->error();
    
    my $page = $self->get_page();
    my $onpage = $self->get_themes_onpage();
    my $onlist = $self->get_themes_onlist();
    
    my @themes = $forum_model->get_themes_list($forum->{id}, ($page-1)*$onpage, $onpage);
    my @attached_themes = $forum_model->get_attached_themes();
    my $paginator = $self->paginator(size=>$forum_model->get_themes_count($forum->{id}), page=>$page, onpage=>$onpage, onlist=>$onlist, url=>getURLWithParams("?", "forum_id=".$forum->{id}, "action=showthemes"));

    foreach my $theme (@themes, @attached_themes) {
        $theme->{create_date} = $self->datetime_from_db($theme->{create_date});
        $theme->{lastupdate_date} = $self->datetime_from_db($theme->{lastupdate_date}); 
    };
    
    $template->param(
        FORUM=>$forum,
        THEMES=>\@themes,
        ATTACHED_THEMES=>\@attached_themes,
        PAGINATOR=>$paginator,
        BACKURL=>$forum_url
    );
    return $self->output($template);
};

# TODO opa

sub post_addgroup {
    my $self = shift;
    my $q = $self->q();
    my $cgi = $self->get_processed_input();
    my $name = $cgi->{name};
    my $user_model = $self->get_user_model();
    my $forum_url = $self->get_forum_url();

    if (!is_empty($name)) {
        $user_model->add_group($name);
        return $self->redirect(getURLWithParams(
            $forum_url, {
                action=>"groupsadmin"
            }
        ));
    }
    else {
        $self->setStash("ADDGROUP", {
            ERRORS=>{name=>1}
        });
    };
    
    return 1;
};

sub post_vote {
    my $self = shift;
    my $q = $self->q();
    my $cms = $self->cms();
    my $theme_id = $q->param("theme_id")+0;
    my $user = $self->get_user();
    my $forum_model = $self->get_forum_model();
    
    my $theme = $forum_model->get_theme($theme_id);
    return $cms->notFound() unless ($theme); 
    return $self->post_noaccess() unless ($user->can_write($theme->{section_id}));

    my $forum_url = $self->get_forum_url();
    my $redirect_url = getURLWithParams($forum_url, {
        action=>"showmessages",
        theme_id=>$theme->{id}
    });
    
    my $poll = $forum_model->get_poll_by_theme($theme_id);
    return $self->redirect_to_ref($redirect_url) unless $poll;
    return $self->redirect_to_ref($redirect_url) unless $forum_model->can_vote_to_poll($poll->{id}, $user->id());
    my @variants = $q->param("variants");

    $forum_model->vote_to_poll($poll->{id}, $user->id(), @variants);
    
    return $self->redirect_to_ref($redirect_url);
};

sub block_showmessages {
    my $self = shift;
    my $cms = $self->cms();
    my $q = $self->q();
    my $user = $self->get_user();
    my $user_model = $self->get_user_model();
    my $forum_model = $self->get_forum_model();
    my $forum_url = $self->get_forum_url();
    
    my $theme_id = $q->param("theme_id")+0;
    my $theme = $forum_model->get_theme($theme_id);
    
    return $cms->notFound() unless $theme;
    return $self->noaccess() unless $user->can_access($theme->{section_id});
    return $self->block_banpage() if ($forum_model->user_is_banned_on_section($user->id(), $theme->{section_id}));
    
    my $message_id = $q->param("message_id")+0;
    my $message = $forum_model->get_message($message_id);

    
    my $has_moderate = $user->can_moderate($theme->{section_id});
    $theme->{CAN_CLOSE} = $has_moderate ? 1 : 0;
    $theme->{CAN_EDIT} = $has_moderate ? 1 : 0;
    $theme->{CAN_DELETE} = $has_moderate ? 1 : 0;
    $theme->{HAS_MODERATE_ACTION} = $theme->{CAN_DELETE} || $theme->{CAN_EDIT} || $theme->{CAN_CLOSE};
    
    
#     my $max_filecount = $self->get_max_files_count();
    
    
    my $page = $self->get_page();
    my $count = $forum_model->get_messages_count($theme->{id});
    my $onpage = $self->get_messages_onpage();
    my $onlist = $self->get_messages_onlist();
    if ($message && $message->{theme_id} == $theme->{id}) {
        my $position = $forum_model->get_message_position($message->{id});
        $page = int(($position-1)/$onpage) + 1;        
    };    
    if ($q->param("lastmessage")) {
        $page = int(($count-1)/$onpage) + 1;
    };
    
    my $avatar_dir = $self->get_avatars_upload_dir();
    my @messages = $forum_model->get_messages_list($theme->{id}, ($page-1)*$onpage, $onpage);
    foreach (@messages) {
        $_->{cite_message} = $_->{message};
        $_->{message} = nl2br($_->{message});
        $_->{message} = NG::Forum::BBCodes::parse_bb($_->{message});
        $_->{message} = $self->smileys($_->{message});
        $_->{create_date} = $self->datetime_from_db($_->{create_date});
        $_->{update_date} = $self->datetime_from_db($_->{update_date});
        $_->{status} = $self->get_user_status($_->{messages_cnt});
        $_->{avatar} = $avatar_dir.$_->{avatar} if ($_->{avatar});
        $_->{gravatar} = $self->get_gravatar_url($_->{email}) if ($_->{email});
        $_->{signature} = nl2br($_->{signature});
        $_->{CAN_EDIT} = $has_moderate ? 1 : 0;
        $_->{CAN_DELETE} = $has_moderate ? 1 : 0;
        $_->{CAN_CLOSE} =  $has_moderate ? 1 : 0;
        $_->{HAS_MODERATE_ACTION} = $_->{CAN_DELETE} || $_->{CAN_EDIT} || $_->{CAN_CLOSE};
    };
    my $messages_files = $forum_model->get_messages_files($theme->{id}, ($page-1)*$onpage, $onpage);
    
    
    foreach my $message (@messages) {
        $message->{files} = $messages_files->{$message->{id}};
    };
    
    my $paginator = $self->paginator(size=>$count, page=>$page, onpage=>$onpage, onlist=>$onlist, url=>getURLWithParams("?", "theme_id=".$theme->{id}, "action=showmessages"));
    
    my $poll = $forum_model->get_poll_by_theme($theme->{id});
    my $can_vote = 0;
    if ($poll) {
        $can_vote = $forum_model->can_vote_to_poll($poll->{id}, $user->id());
    };
    $forum_model->set_theme_read($user->id(), $theme->{id});
    
    my $forum = $forum_model->get_forum($theme->{forum_id});
    my $section = $forum_model->get_section($forum->{section_id});
    $self->add_history(
        {name=>$self->getResource("HISTORY_ROOT"), url=>$forum_url},
        {name=>$section->{name}, url=>getURLWithParams($forum_url, {action=>"showforums", section_id=>$section->{id}})},
        {name=>$forum->{name}, url=>getURLWithParams($forum_url, {action=>"showthemes", forum_id=>$forum->{id}})},
        {name=>$theme->{name}, url=>getURLWithParams($forum_url, {action=>"showmessages", theme_id=>$theme->{id}})},
    );    
    
    my $template = $self->gettemplate("messages.tmpl") or return $cms->error();
    $template->param(
        MESSAGES=>\@messages,
        THEME=>$theme,
        SECTION=>$section,
        FORUM=>$forum,
        PAGINATOR=>$paginator,
        BACKURL=>getURLWithParams($forum_url, {action=>"showthemes", forum_id=>$forum->{id}}),
        CAN_ADD_MESSAGE=>(($user->can_write($theme->{section_id}) && !$theme->{is_close}) ? 1: 0),
        ESCAPE_CURRENT_URL=>uri_escape($self->get_current_url()),
#         MAX_FILECOUNT=>$max_filecount,
        POLL=>$poll,
        CAN_VOTE=>$can_vote,
        IS_SUBSCRIBE=>$forum_model->is_subscribe_theme($user->id(), $theme_id)
    );
    
    my $addmessage_data = $self->getStash("ADDMESSAGE", undef);
#     unless (defined $addmessage_data) {
#         $addmessage_data->{files} = [];
#         my $filecount = DEFAULT_FILE_COUNT>$max_filecount ? $max_filecount: DEFAULT_FILE_COUNT;
#         for (my $i=0; $i<$filecount; $i++) {
#             push @{$addmessage_data->{files}}, undef;
#         };
#     };
    $addmessage_data->{form}->{theme_id} = $theme_id unless ($addmessage_data->{form}->{theme_id});
#     $addmessage_data->{can_addfile} = (scalar @{$addmessage_data->{files}}<$max_filecount) ? 1: 0;
    $addmessage_data->{form}->{session_id} = generate_session_id() unless ($addmessage_data->{form}->{session_id});
    
    $template->param(
        ADDMESSAGE=>$addmessage_data,
    );
    
    return $self->output($template, undef, {meta=>{keywords=>$theme->{name}, description=>$theme->{name}}});
};

sub block_unsubscribetheme {
    my $self = shift;
    my $user = $self->get_user();
    my $q = $self->q();
    my $theme_id = $q->param("theme_id")+0;
    my $forum_model = $self->get_forum_model();
    my $theme = $forum_model->get_theme($theme_id);
    my $cms = $self->cms();
    my $from_theme = $q->param("fromtheme");
    
    my $refparam = $self->get_referer();
    
    if (!$user->id() || !$theme) {
        my $template = $self->gettemplate("unsubscribe_error.tmpl") or return $cms->error();
        $template->param(
            USER_ERROR=>(!$user->id() ? 1 : 0),
            THEME_ERROR=>(!$theme ? 1 : 0),
            BACKURL=>$refparam
        );
        return $self->output($template);
    };
    
    $forum_model->unsubscribe_theme($user->id(), $theme_id);
    my $template = $self->gettemplate("unsubscribe.tmpl") or return $cms->error();
    $template->param(
        THEME=>$theme,
        BACKURL=>$refparam
    );
    return $self->output($template);
};

sub block_unsubscribeallthemes {
    my $self = shift;
    my $user = $self->get_user();
    my $q = $self->q();
    my $forum_model = $self->get_forum_model();
    my $cms = $self->cms();
    my $refparam = $self->get_referer();
    
    if (!$user->id()) {
        my $template = $self->gettemplate("unsubscribe_error.tmpl") or return $cms->error();
        $template->param(
            USER_ERROR=>1,
            BACKURL=>$refparam,
        );
        return $self->output($template);
    };    
    
    $forum_model->unsubscribe_all_themes($user->id());
    my $template = $self->gettemplate("unsubscribeall.tmpl") or return $cms->error();
    $template->param(
        BACKURL=>$refparam
    );
    return $self->output($template);
};

sub block_deletegroup {
    my $self = shift;
    
    my $user = $self->get_user();
    return $self->noaccess() unless ($user->is_global_moderate());
        
    my $q = $self->q();
    my $group_id = $q->param("id")+0;
    my $user_model = $self->get_user_model();
    $user_model->delete_group($group_id);
    return $self->redirect_to_ref();
};

sub block_editgroup {
    my $self = shift;
    
    my $user = $self->get_user();
    return $self->noaccess() unless ($user->is_global_moderate());
    my $user_model = $self->get_user_model();
    my $q = $self->q();
    my $cms = $self->cms();
    my $group_id = $q->param("id")+0;
    
    my $template = $self->gettemplate("editgroup.tmpl") or return $cms->error();
    my $editgroup_data = $self->setStash("EDITGROUP");
    unless ($self->is_post()) {
        $editgroup_data->{form} = $user_model->get_group($group_id);
    };
    
    $template->param(
        EDITGROUP=>$editgroup_data
    );
    
    return $self->output($template);
};

sub post_editgroup {
    my $self = shift;
    my $user = $self->get_user();
    return $self->post_noaccess() unless ($user->is_global_moderate());
    
    my $q = $self->q();
    my $cgi = $self->get_processed_input();
    
    my $errors = {};
    $errors->{id} = 1 unless (is_valid_id($cgi->{id}));
    $errors->{name} = 1 if (is_empty($cgi->{name}));
    unless (scalar keys %$errors) {
        my $user_model = $self->get_user_model();
        my $forum_url = $self->get_forum_url();
        $user_model->update_group($cgi);
        return $self->redirect(getURLWithParams(
            $forum_url,
            {
                action=>"groupsadmin"
            }
        ));
    };
    
    $self->setStash("EDITGROUP", {
        form=>$cgi,
        errors=>$errors    
    });
    
    return 1;      
};

sub block_reg {
    my $self = shift;
    my $cms = $self->cms();
    return $cms->notFound() if ($self->{_external_registration});
    my $user = $self->get_user();
    my $forum_url = $self->get_forum_url();
    return $self->redirect($forum_url) if ($user->id());
    
    my $user_model = $self->get_user_model();
    my $errors = {};
    my $cgi = $self->get_processed_input();
    
    if ($self->is_post()) {
        $errors->{empty_email} = 1 if (is_empty($cgi->{email}));
        $errors->{not_valid_email} = 1 if (!is_valid_email($cgi->{email}));
        $errors->{not_unique_email} = 1 if ($user_model->has_email_duplicate($cgi->{email}));
        
        $errors->{empty_login} = 1 if (is_empty($cgi->{login}));
        $errors->{not_unique_login} = 1 if ($user_model->has_login_duplicate($cgi->{login}));
        
        $errors->{empty_password} = 1 if (is_empty($cgi->{password}));
        $errors->{not_equale_password} = 1 if ($cgi->{password} ne $cgi->{retype_password});

        unless (scalar keys %$errors) {
            $user_model->reg({
                email=>$cgi->{email},
                login=>$cgi->{login},
                password=>$cgi->{password}
            });
            return $self->redirect($self->get_forum_url(), {action=>"regok"});
        };
    };
    
    my $template = $self->gettemplate("reg.tmpl") or return $cms->error();
    $template->param(
        CGI=>$cgi,
        ERRORS=>$errors,
    );
    
    return $self->output($template);
};

sub block_groupsadmin {
    my $self = shift;
    my $user = $self->get_user();
    return $self->noaccess() unless ($user->is_global_moderate());
    my $cms = $self->cms();
    
    my $user_model = $self->get_user_model();
    my @groups = $user_model->get_all_group_list();
    my $template = $self->gettemplate("groupsadmin.tmpl") or return $cms->error();
    
    $template->param(
        GROUPS=>\@groups
    );
    
    my $addgroup_data = $self->getStash("ADDGROUP");
    $template->param(
        ADDGROUP=>$addgroup_data
    );
    
    return $self->output($template);
};

sub block_changeprivs {
    my $self = shift;
    my $user = $self->get_user();
    return $self->noaccess() unless ($user->is_global_moderate());
    
    my $q = $self->q();
    my $cms = $self->cms();
    my $group_id = $q->param("id")+0;
    my $user_model = $self->get_user_model();
    return $cms->notFound() unless ($user_model->is_valid_group_id($group_id));
    my $group = $user_model->get_group($group_id);
    
    my $access_priv = $user_model->get_access_priv_name();
    my $write_priv = $user_model->get_write_priv_name();
    my $moderate_priv = $user_model->get_moderate_priv_name();
    my $forum_url = $self->get_forum_url();
    
    my @privs = $user_model->get_group_privs($group_id);
    if ($self->is_post()) {
        my $forum_url = $self->get_forum_url();
        my %access = map {$_=>1} $q->param($access_priv);
        my %write = map {$_=>1} $q->param($write_priv);
        my %moderate = map {$_=>1} $q->param($moderate_priv);
        foreach my $section (@privs) {
            $section->{privs}->{access} = exists $access{$section->{id}} ? 1 : 0;
            $section->{privs}->{write} = exists $write{$section->{id}} ? 1 : 0;
            $section->{privs}->{moderate} = exists $moderate{$section->{id}} ? 1 : 0;
        };
        $user_model->set_group_privs($group_id, @privs);
        return $self->redirect(getURLWithParams(
            $forum_url,
            {
                action=>"groupsadmin"
            }
        ));
    };
    
    
    my $template = $self->gettemplate("changeprivs.tmpl") or return $cms->error();
    
    $template->param(
        PRIVILEGES=>\@privs,
        GROUP=>$group,
        BACKURL=>getURLWithParams($forum_url, {action=>"groupsadmin"})
    );

    return $self->output($template);
};

sub block_banpage {
    my $self = shift;
    my $cms = $self->cms();
    my $template = $self->gettemplate("banpage.tmpl") or return $cms->error();
    return $self->output($template); 
};

sub block_login {
    my $self = shift;
    my $cms = $self->cms();
    my $login_data = $self->getStash("LOGINDATA");
    my $template = $self->gettemplate("login.tmpl") or return $cms->error();
    
    $template->param(
        VIA_EMAIL=>$self->is_authorize_via_email(),
        LOGINDATA=>$login_data
    );
    
    return $self->output($template);
};

sub post_login {
    my $self = shift;
    my $q = $self->q();
    my $user_model = $self->get_user_model();
    my $login = $q->param("login");
    my $password = $q->param("password");
    my $is_login = $user_model->login($login, $password);
    my $forum_url = $self->get_forum_url();
    unless ($is_login) {
        $self->setStash("LOGINDATA", {error=>1}) ;
        return 1;
    }
    else {
        return $self->redirect($forum_url);
    };
};

sub block_sectionlist {
    my $self = shift;
    my $user = $self->get_user();
    return $self->noaccess() if (!$user->is_root() && !$user->is_moderate());
    
    my $cms = $self->cms();
    my $forum_model = $self->get_forum_model();
    
    my @sections_list = $forum_model->get_sections_list();
    
    my $template = $self->gettemplate("sections.tmpl") or return $cms->error();
    $template->param(
        SECTIONS_LIST=>\@sections_list
    );     
    
    return $self->output($template);
};

sub block_forumslist {
    my $self = shift;
    my $user = $self->get_user();
    return $self->noaccess() if (!$user->is_root() && !$user->is_moderate());
    
    my $cms = $self->cms();
    my $q = $self->q();
    my $forum_model = $self->get_forum_model();
    
    my $section_id = $q->param("section_id")+0;
    my $section = $forum_model->get_section($section_id);
    return $cms->notFound() unless $section;
    
    my @forums_list = $forum_model->get_forums_list($section->{id});    
    
    my $template = $self->gettemplate("forums.tmpl") or return $cms->error();
    $template->param(
        FORUMS_LIST=>\@forums_list
    );     
    
    return $self->output($template);
};

sub noaccess {
    my $self = shift;
    my $cms = $self->cms();
    my $template = $self->gettemplate("noaccess.tmpl") or return $cms->error();
    return $self->output($template);
};

sub block_recoverypwd {
    my $self = shift;
    my $cms = $self->cms();
    my $errors = {};
    my $q = $self->q();
    my $forum_url = $self->get_forum_url();
    
    if ($self->is_post()) {
        my $login = $q->param("login");
        my $email = $q->param("email");
        my $user_model = $self->get_user_model();
        if (!is_empty($login)) {
            if ($user_model->recovery_pwd_by_login($login)) {
                return $self->redirect(getURLWithParams($forum_url, {
                    action=>"recoverypwdok"
                }));
            };
            $errors->{noresult} = 1;
        }
        elsif(!is_empty($email)) {
            if ($user_model->recovery_pwd_by_email($email)) {
                return $self->redirect(getURLWithParams($forum_url, {
                    action=>"recoverypwdok"
                }));
            };
            $errors->{noresult} = 1;
        }
        else {
            $errors->{all_empty} = 1;
        };
    };
    
    my $template = $self->gettemplate("recoverypwd.tmpl") or return $cms->error();
    $template->param(
        ERRORS=>$errors
    );
    return $self->output($template);
};

sub block_recoverypwdok {
    my $self = shift;
    my $cms = $self->cms();
    my $template = $self->gettemplate("recoverypwdok.tmpl") or return $cms->error();
    return $self->output($template); 
};

sub block_userslist {
    my $self = shift;
    my $q = $self->q();
    my $cms = $self->cms();
    my $search = $q->param("search") || "";
    
    my $template = $self->gettemplate("userslist.tmpl") or return $cms->error();
    my $user_model = $self->get_user_model();
    my $forum_url = $self->get_forum_url();
    my @users = ();
    my $paginator = undef;
    
    unless (is_empty($search)) {
        @users = $user_model->search_users($search);
        $template->param(
            IS_SEARCH=>1
        );
    }
    else {
        my $page = $self->get_page();
        $paginator = $self->paginator(size=>$user_model->get_users_count(), page=>$page, onpage=>20, onlist=>10, url=>getURLWithParams($forum_url, {action=>"userslist"}));
        @users =  $user_model->get_users_list(($page-1)*20, 20);
    };
    
    $template->param(
        USERS=>\@users,
        PAGINATOR=>$paginator,
        SEARCH=>$search
    );
    return $self->output($template);    
};

sub block_showusergroups {
    my $self = shift;
    my $user = $self->get_user();
    return $self->noaccess() unless ($user->is_global_moderate());
    my $cms = $self->cms();
    my $q = $self->q();
    my $user_id = $q->param("user_id")+0;
    my $user_model = $self->get_user_model();

    
    if ($self->is_post()) {
        my @groups = $q->param("group");
        $user_model->set_user_groups($user_id, @groups);
        return $self->redirect_to_ref();
    };
    
    
    my @groups = $user_model->get_group_list();
    my @user_groups = $user_model->get_user_group_list($user_id);
    
    my %user_groups = map {$_->{id}=>1} @user_groups;
    foreach (@groups) {
        $_->{checked} = exists $user_groups{$_->{id}}? 1: 0; 
    };
    

    my $template = $self->gettemplate("usergroups.tmpl") or return $cms->error();
    
    $template->param(
        GROUPS=>\@groups,
        USER_ID=>$user_id,
        BACKURL=>getURLWithParams($self->get_forum_url(), {action=>"userslist"})
    );                                                      
    
    return $self->output($template);
};

sub block_moderate {
    my $self = shift;
    my $user = $self->get_user();
    return $self->noaccess() unless ($user->is_moderate());
    my $q = $self->q();
    my $user_id = $q->param("user_id")+0;
    my $user_model = $self->get_user_model();
    $user_model->set_user_moderate($user_id);
    return $self->redirect_to_ref();    
};

sub block_unmoderate {
    my $self = shift;
    my $q = $self->q();
    my $user = $self->get_user();
    return $self->noaccess() unless ($user->is_global_moderate());
    my $user_id = $q->param("user_id")+0;
    my $user_model = $self->get_user_model();
    if ($user_id != $user->id()) {
        $user_model->unset_user_moderate($user_id);
    };
    return $self->redirect_to_ref();    
};

sub block_logout {
    my $self = shift;
    my $user_model = $self->get_user_model();
    my $forum_url = $self->get_forum_url();
    $user_model->logout();
    return $self->redirect($forum_url); 
};

sub block_pager {
    my $self = shift;
    my $user = $self->get_user();
    return $self->noaccess() unless $user->id();
    my $q = $self->q();
    my $forum_model = $self->get_forum_model();
    my $page = $self->get_page();
    my $onpage = $self->get_pager_onpage();
    my $onlist = $self->get_pager_onlist();
    my $cms = $self->cms();
    
    my $in = $q->param("out") ? 0 : 1;
    my @messages = ();
    my $count = 0;
    
    if ($in) {
        @messages = $forum_model->get_pager_in($user->id());
        $count = $forum_model->get_pager_in_count($user->id());
    }
    else {
        @messages = $forum_model->get_pager_out($user->id());
        $count = $forum_model->get_pager_out_count($user->id());
    };
    
    foreach (@messages) {
        $_->{create_date} = $self->datetime_from_db($_->{create_date});
    };
    
    my $paginator = $self->paginator(size=>$count, page=>$page, onpage=>$onpage, onlist=>$onlist, 
        url=>getURLWithParams("?", {
            action=>"pager",
            out=>($in ? 0 : 1)
        })
    );
    
    $forum_model->set_pager_read($user->id());
    
    my $template = $self->gettemplate("pagers.tmpl") or return $cms->error();
    $template->param(
        MESSAGES=>\@messages,
        PAGINATOR=>$paginator,
        IN=>$in,
    );
    
    $self->output($template);
};

sub block_pagerfull {
    my $self = shift;
    my $user = $self->get_user();
    return $self->noaccess() unless $user->id();
    my $q = $self->q();
    my $id = $q->param("id")+0;
    my $cms = $self->cms();
    
    my $forum_model = $self->get_forum_model();
    my $pager = $forum_model->get_pager_full($id, $user->id());
    $pager->{out} = $pager->{sender_user_id} == $user->id()? 1: 0;
    my $forum_url = $self->get_forum_url();
    my $backurl = getURLWithParams($forum_url, {
        action=>"pager",
        out=>$pager->{out}
    }); 
    if ($pager) {
        $pager->{message} = NG::Forum::BBCodes::parse_bb($pager->{message});
        $pager->{message} = $self->smileys($pager->{message});
        $pager->{create_date} = $self->datetime_from_db($pager->{create_date});
    };
    my $template = $self->gettemplate("pagerfull.tmpl") or return $cms->error();
    $template->param(
        PAGER=>$pager,
        BACKURL=>$backurl
    );
    return $self->output($template);
};

sub block_subscribetheme {
    my $self = shift;
    my $q = $self->q();
    my $theme_id = $q->param("theme_id")+0;
    my $user = $self->get_user();
    if ($user->id()) {
        $self->get_forum_model()->subscribe_theme($user->id(), $theme_id);
    };
    return $self->redirect_to_ref(); 
};

sub block_showuserinfo {
    my $self = shift;
    my $q = $self->q();
    my $user_id = $q->param("user_id")+0;
    my $user = $self->get_user();
    my $cms = $self->cms();
    
    my $user_model = $self->get_user_model();
    my $user_info = $user_model->get_user_info($user_id);
    
    my $can_add = $user->id() && $user;
    my @extends = ();
    @extends = $user_model->get_extends_data($user_id) if($self->is_extend_user());
    foreach (@extends) {
        $_->{value} = nl2br($_->{value}) if ($_->{type_textarea});
    };
    
    my $template = $self->gettemplate("showuserinfo.tmpl") or return $cms->error();
    $template->param(
        USERINFO=>$user_info,
        CAN_ADD=>$can_add,
        EXTENDS=>\@extends,
        IS_ONLINE=>$self->get_forum_model()->is_online_user($user_id)
    );
    return $self->output($template);
};

sub post_pageradd {
    my $self = shift;
    my $q = $self->q();
    my $cgi = $self->get_processed_input();
    my $user_model = $self->get_user_model();
    my $forum_model = $self->get_forum_model();
    my $user_id = $q->param("user_id")+0;
    my $user = $self->get_user();
    my $can_add = $user->id() && $user_model->is_valid_user($user_id) && !is_empty($cgi->{message});
    if ($can_add) {
        $forum_model->add_pager({
            sender_user_id=>$user->id(),
            recipient_user_id=>$user_id,
            header=>$cgi->{header},
            message=>$cgi->{message}
        });
    };
    
    return $self->redirect_to_ref();
};

sub block_deletepager {
    my $self = shift;
    my $user = $self->get_user();
    return $self->noaccess() unless $user->id();
    
    my $q = $self->q();
    my $pager_id = $q->param("id")+0;
    my $forum_model = $self->get_forum_model();
    $forum_model->delete_pager($pager_id, $user->id()); 
    return $self->redirect_to_ref();
};

sub block_addtheme {
    my $self = shift;
    my $cms = $self->cms();
    my $template = $self->gettemplate("forum_theme_add.tmpl") or return $cms->error();
    my $q = $self->q();
    my $forum_id = $q->param("forum_id")+0;
    my $forum_url = $self->get_forum_url();
    my $user = $self->get_user();    
    
    my $forum = $self->get_forum_model()->get_forum($forum_id);
    return $cms->notFound() unless $forum;
    return $self->noaccess() unless ($user->can_write($forum->{section_id}));
    
#     my $max_filecount = $self->get_max_files_count();
    my $addtheme_data = $self->getStash("ADDTHEME", undef) ;
#     unless (defined $addtheme_data) {
#         $addtheme_data->{files} = [];
#         my $filecount = DEFAULT_FILE_COUNT>$max_filecount ? $max_filecount: DEFAULT_FILE_COUNT;
#         for (my $i=0; $i<$filecount; $i++) {
#             push @{$addtheme_data->{files}}, undef;
#         };
#     };
#     $addtheme_data->{can_addfile} = (scalar @{$addtheme_data->{files}}<$max_filecount) ? 1: 0;
    $addtheme_data->{form}->{forum_id} = $forum_id unless ($addtheme_data->{form}->{forum_id});
    $addtheme_data->{form}->{session_id} = generate_session_id() unless ($addtheme_data->{form}->{session_id});
    
    
    $template->param(
        ADDTHEME=>$addtheme_data,
#         MAX_FILECOUNT=>$max_filecount,
        BACKURL=>getURLWithParams($forum_url, {
            action=>"showthemes",
            forum_id=>$addtheme_data->{form}->{forum_id}
        })
    );
    
    return $self->output($template);
};

sub post_addtheme {
    my $self = shift;
    my $cms = $self->cms();
    my $cgi = $self->get_processed_input();
    my $forum_url = $self->get_forum_url();
    my $forum_model = $self->get_forum_model();
    my $user = $self->get_user();
    my $forum = $forum_model->get_forum($cgi->{forum_id});
    
    return $self->post_noaccess() unless ($user->can_write($forum->{section_id}));
    return $self->block_banpage() if ($forum_model->user_is_banned_on_section($user->id(), $forum->{section_id}));
    
#     #Получаем информацию о залитых файлах
#     my @files = map {$forum_model->get_message_file_info($_)} grep {/message_file/} keys %$cgi;
#     
#     #Если файловых полей(даже пустых) из формы пришло меньше то увеличиваем их количество
#     if (scalar @files<DEFAULT_FILE_COUNT) {
#         my $add_items = DEFAULT_FILE_COUNT - scalar @files;
#         for (my $i; $i<$add_items;$i++) {
#             push @files, undef;
#         };
#     };    
    
    my $form = {};
    my $errors = {};

    $form->{addfiles} = $cgi->{addfiles};
    $form->{multichoice} = $cgi->{multichoice};
    $form->{forum_id} = $cgi->{forum_id};
    $form->{name} = $cgi->{name};
    $form->{author} = $cgi->{author};
    $form->{message} = $cgi->{message};
    $form->{pollvariants} = undef;
    
    my $addtheme_data = {};
    
    my %pollvariants = ();
    my $max_variant_number = 0;
    foreach my $key (grep {/poll_variant_\d+/} keys %$cgi) {
        my ($num) = $key =~ /poll_variant_(\d+)/; 
        $pollvariants{$num} = $cgi->{$key};            
    };
    if (scalar keys %pollvariants) {
        $form->{pollvariants} = [];
        foreach (sort keys %pollvariants) {
            push @{$form->{pollvariants}}, {id=>$_, value=>$pollvariants{$_}};
            $max_variant_number = $_;
        };
    };
    if ($cgi->{formaction} eq "addpollvariant") {
        unless ($max_variant_number) {
            $form->{pollvariants} = [] ;
            push @{$form->{pollvariants}}, {id=>++$max_variant_number, value=>""};
        };
        push @{$form->{pollvariants}}, {id=>++$max_variant_number, value=>""};
    }
    elsif ($cgi->{formaction} eq "preview") {
        $addtheme_data->{preview} = $cgi->{message};
        $addtheme_data->{preview} = nl2br($addtheme_data->{preview});
        $addtheme_data->{preview} = NG::Forum::BBCodes::parse_bb($addtheme_data->{preview});
        $addtheme_data->{preview} = $self->smileys($addtheme_data->{preview});         
    }
#     elsif ($cgi->{formaction} eq "addfile") {
#         #Увеличиваем количество файловых полей
#         if (scalar @files < $self->get_max_files_count()) {
#             push @files, undef;
#         };
#     }    
    elsif ($cgi->{deletepollvariant}) {
        my $delete_poll_variant_id = $cgi->{deletepollvariant}+0;
        if (defined $form->{pollvariants}) {
            @{$form->{pollvariants}} = grep {!($_->{id} == $delete_poll_variant_id)} @{$form->{pollvariants}}; 
        };
    }
    else {
    
        my $forum_data = {};
        foreach (qw(forum_id name message author forum_id)) {
            $forum_data->{$_} = $form->{$_};
        };
        $forum_data->{forum_id} = 0 unless is_valid_id($forum_data->{forum_id});
        my $forum = $forum_model->get_forum($forum_data->{forum_id});

        $errors->{forum_id} = 1 unless $forum;
        $errors->{name} = 1 if (is_empty($forum_data->{name}));
        $errors->{message} = 1 if (is_empty($forum_data->{message})); 
        
#         my $max_file_size = $self->get_max_file_size();
#         my $max_total_files_size = $self->get_max_total_files_size();
#         my $max_files_count = $self->get_max_files_count();
#         
#         my $total_size = 0;
#         my $files_count = 0;
#         foreach (@files) {
#             next unless defined $_;
#             $total_size += $_->{size};
#             $files_count++;
#             $_->{size_error} = 0;
#             if ($_->{size}>$max_file_size) {
#                 $_->{size_error} = 1;
#                 $errors->{file_size_error} = 1;
#             };
#             my $ext = get_file_extension($_->{filename}); 
#             if ($ext !~ /txt|jpg|jpeg|gif|png|txt|doc|rtf|xls/i) {
#                  $errors->{file_type_error} = 1;
#             };
#         };
#         $errors->{max_files_count} = 1 if ($files_count > $max_files_count);
#         $errors->{max_files_size} = 1 if ($total_size > $max_total_files_size);        

        unless (scalar keys %$errors) {
            my ($theme_id, $message_id) = $forum_model->add_theme($forum_data);
            if ($form->{pollvariants} && $theme_id) {
                my $poll_data = {};
                $poll_data->{theme_id} = $theme_id;
                $poll_data->{multichoice} = $cgi->{multichoice} ? 1 : 0;
                $poll_data->{name} = $cgi->{name};
                foreach my $v (@{$form->{pollvariants}}) {
                    push @{$poll_data->{variants}}, $v->{value} unless is_empty($v->{value});            
                };
                my $poll_id = $forum_model->add_theme_poll($poll_data);
            };
            
#             if (scalar @files) {
#                 $forum_model->upload_message_files($message_id, @files);
#             };            
            if ($cgi->{addfiles}) {
                return $self->redirect(
                    getURLWithParams($forum_url, {
                        message_id=>$message_id,
                        action=>"addfiles",
                    })
                );
            };            
            return $self->redirect(getURLWithParams($forum_url, {theme_id=>$theme_id, action=>"showmessages", lastmessage=>1}));
        };     
    }        
    
    $addtheme_data->{form} = $form;
    $addtheme_data->{errors} = $errors;
#     $addtheme_data->{files} =  \@files;
    $self->setStash("ADDTHEME", $addtheme_data);
    return 1;
};

sub block_showforums {
    my $self = shift;
    my $q = $self->q();
    my $section_id = $q->param("section_id")+0;
    my $forum_model = $self->get_forum_model();
    my $section = $forum_model->get_section($section_id);
    my $cms = $self->cms();
    
    return $cms->notFound() unless $section;
    my $forums = $forum_model->get_forums_list($section_id);
    
    my $forum_url = $self->get_forum_url();
    $self->add_history(
        {name=>$self->getResource("HISTORY_ROOT"), url=>$forum_url},
        {name=>$section->{name}, url=>getURLWithParams($forum_url, {action=>"showforums", section_id=>$section->{id}})},
    );    
    
    my $template = $self->gettemplate("forums.tmpl") or return $cms->error();
    $template->param(
        FORUMS=>$forums,
        SECTION=>$section
    );
    
    return $self->output($template);
};

sub post_addmessage {
    my $self = shift;
    my $cms = $self->cms();
    my $forum_url = $self->get_forum_url();
    my $cgi = $self->get_processed_input();
    my $errors = {};
    my $form = {};
    my $forum_model = $self->get_forum_model();
    my $addmessage_data = {};
    my $user = $self->get_user();
    
    $cgi->{theme_id} = $cgi->{theme_id} + 0;
    my $theme = $forum_model->get_theme($cgi->{theme_id});
    return $cms->notFound() unless $theme;
    return $self->post_noaccess() if (!$theme || !$user->can_write($theme->{section_id}) || $theme->{is_close});
    return $self->block_banpage() if ($forum_model->user_is_banned_on_section($user->id(), $theme->{section_id}));
    
#     #Получаем информацию о залитых файлах
#     my @files = map {$forum_model->get_message_file_info($_)} grep {/message_file/} keys %$cgi;
#     my @uploaded_files = $forum_model->get_uploaded_files($cgi->{session_id});
#     
#     #Если файловых полей(даже пустых) из формы пришло меньше то увеличиваем их количество
#     if (scalar @files<DEFAULT_FILE_COUNT) {
#         my $add_items = DEFAULT_FILE_COUNT - scalar @files;
#         for (my $i; $i<$add_items;$i++) {
#             push @files, undef;
#         };
#     };

    #Поля для заполнения формы
    foreach (qw(theme_id header message)) {
        $form->{$_} = $cgi->{$_};
    };
    
    $form->{addfiles} = $cgi->{addfiles};
    if ($cgi->{formaction} eq "preview") {
        $addmessage_data->{preview} = $cgi->{message};
        $addmessage_data->{preview} = nl2br($addmessage_data->{preview});
        $addmessage_data->{preview} = NG::Forum::BBCodes::parse_bb($addmessage_data->{preview});
        $addmessage_data->{preview} = $self->smileys($addmessage_data->{preview});        
    }
    elsif ($cgi->{formaction} eq "form") {
        # Это для возвращения к заполнению формы из preview
    }
#     elsif ($cgi->{formaction} eq "addfile") {
#         #Увеличиваем количество файловых полей
#         if (scalar @files < $self->get_max_files_count()) {
#             push @files, undef;
#         };
#     }
    else {                     
        #Проверка и выставление ошибок
        $form->{theme_id} = 0 unless (is_valid_id($form->{theme_id}));
        my $theme = $forum_model->get_theme($form->{theme_id});
        $errors->{theme_id} = 1 unless $theme;   
        $errors->{message} = 1 if (is_empty($form->{message}));
        
#         my $max_file_size = $self->get_max_file_size();
#         my $max_total_files_size = $self->get_max_total_files_size();
#         my $max_files_count = $self->get_max_files_count();
#         
#         my $total_size = 0;
#         my $files_count = 0;
#         foreach (@files) {
#             next unless defined $_;
#             $total_size += $_->{size};
#             $files_count++;
#             $_->{size_error} = 0;
#             if ($_->{size}>$max_file_size) {
#                 $_->{size_error} = 1;
#                 $errors->{file_size_error} = 1;
#             };
#             my $ext = get_file_extension($_->{filename}); 
#             if ($ext !~ /txt|jpg|jpeg|gif|png|txt|doc|rtf|xls/i) {
#                  $errors->{file_type_error} = 1;
#             };            
#         };
#         $errors->{max_files_count} = 1 if ($files_count > $max_files_count);
#         $errors->{max_files_size} = 1 if ($total_size > $max_total_files_size);
        
        unless (scalar keys %$errors) {
            #Сообствено добавление
            my $message_id = $forum_model->add_message($form);
#             if (scalar @files) {
#                 $forum_model->upload_message_files($message_id, @files);
#             };
            if ($cgi->{addfiles}) {
                return $self->redirect(
                    getURLWithParams($forum_url, {
                        message_id=>$message_id,
                        action=>"addfiles",
                    })
                );
            };
            return $self->redirect(
                getURLWithParams($forum_url, {
                    theme_id=>$form->{theme_id},
                    action=>"showmessages",
                    lastmessage=>1
                })
            );
        };        
    };
    
    $addmessage_data->{form} = $form;
    $addmessage_data->{errors} = $errors;
#     $addmessage_data->{files} =  \@files;
    $self->setStash("ADDMESSAGE", $addmessage_data);
    return 1;
};

sub block_editmessage {
    my $self = shift;
    my $cms = $self->cms();
    my $q = $self->q();
    my $user = $self->get_user();
    my $forum_model = $self->get_forum_model();
    my $message_id = $q->param("id")+0;
    my $message = $forum_model->get_message($message_id, 1);
    return $cms->notFound() unless $message;
    return $self->noaccess() unless ($user->can_moderate($message->{section_id}));
    
    my $editmessage_data = undef;
    if ($self->is_post()) {
        $editmessage_data = $self->getStash("EDITMESSAGE");
    }
    else {
        $editmessage_data->{form} = {
            id=>$message->{id},
            message=>$message->{message}
        };
    };
    
    my @files = $forum_model->get_message_files($message->{id});
    
    my $template = $self->gettemplate("forum_message_edit.tmpl") or return $cms->error();
    my $referer = $self->get_referer();
    $template->param(
        REFERER=>$referer,
        BACKURL=>$referer,
        EDITMESSAGE=>$editmessage_data,
        FILES=>\@files,
        ESCAPE_CURRENT_URL=>uri_escape($self->get_current_url())
    );
    return $self->output($template);
};

sub post_editmessage {
    my $self = shift;
    my $cms = $self->cms();
    my $cgi = $self->get_processed_input();
    my $forum_model = $self->get_forum_model();
    my $user = $self->get_user();
    
    $cgi->{id} = $cgi->{id} + 0;
    
    my $message = $forum_model->get_message($cgi->{id});
    return $cms->notFound() unless ($message);
    return $self->post_noaccess() if (!$user->can_moderate($message->{section_id})); 
    
    my $editmessage_data = {
        form=>{
            id=>$cgi->{id},
            message=>$cgi->{message}
        }
    };
    
    if ($cgi->{formaction} eq "preview") {
        $editmessage_data->{preview} = $cgi->{message};
        $editmessage_data->{preview} = nl2br($editmessage_data->{preview});
        $editmessage_data->{preview} = NG::Forum::BBCodes::parse_bb($editmessage_data->{preview});
        $editmessage_data->{preview} = $self->smileys($editmessage_data->{preview});        
    }
    elsif ($cgi->{formaction} eq "form") {

    }
    else {
        $forum_model->update_message($cgi);
        return $self->redirect($self->get_referer());
    };
    
    $self->setStash("EDITMESSAGE", $editmessage_data);
    
    return 1;
};

sub block_rss {
    my $self = shift;
};

sub block_deletetheme {
    my $self = shift;
    my $q = $self->q();
    my $cms = $self->cms();
    my $user = $self->get_user();
    my $theme_id = $q->param("theme_id")+0;
    my $forum_model = $self->get_forum_model();
    my $theme = $forum_model->get_theme($theme_id);
    return $cms->notFound() unless $theme;
    return $self->noaccess() unless $user->can_moderate($theme->{section_id});    
    $forum_model->delete_theme($theme_id);
    return $self->redirect(getURLWithParams($self->get_forum_url(), {
        action=>"showthemes",
        forum_id=>$theme->{forum_id}
    }));
};

sub block_deletemessage {
    my $self = shift;
    my $q = $self->q();
    my $cms = $self->cms();
    my $user = $self->get_user();
    my $message_id = $q->param("id")+0;
    my $forum_model = $self->get_forum_model();
    my $message = $forum_model->get_message($message_id);
    return $cms->notFound() unless $message;
    return $self->noaccess() unless $user->can_moderate($message->{section_id});    
    $forum_model->delete_message($message->{id});
    return $self->redirect_to_ref();
};

sub block_edittheme {
    my $self = shift;
    my $cms = $self->cms();
    my $user = $self->get_user();
    my $q = $self->q();
    my $id = $q->param("id") + 0;
    my $forum_model = $self->get_forum_model();
    my $theme = $forum_model->get_theme($id);
    
    return $cms->notFound() unless $theme; 
    return $self->post_noaccess() if (!$user->can_moderate($theme->{section_id}));
        
    my $template = $self->gettemplate("forum_theme_edit.tmpl") or return $cms->error();
    
    my $edittheme_data = {};
    if ($self->is_post()) {
        $edittheme_data = $self->getStash("EDITTHEME", {});
    }
    else {
        $theme->{name} = $theme->{name};
        $edittheme_data->{form} = $theme;
    };
    
    my  $referer = $self->get_referer();
    $template->param(
        EDITTHEME=>$edittheme_data,
        REFERER=>$referer,
        BACKURL=>$referer
    );
    
    return $self->output($template);
};

sub post_edittheme {
    my $self = shift;
    my $cms = $self->cms();
    my $cgi = $self->get_processed_input();
    my $user = $self->get_user();
    my $forum_model = $self->get_forum_model();

    my $theme = $forum_model->get_theme($cgi->{id});
    return $cms->notFound() unless $theme;
    return $self->noaccess() unless ($user->can_write($theme->{section_id}));    

    my $forum_url = $self->get_forum_url();    
    my $errors = {};
    my $edittheme_data = {};
    
    foreach my $key (qw(id forum_id name)) {
        $theme->{$key} = $cgi->{$key};
    };

    $errors->{id} = 1 if (!is_valid_id($theme->{id}));
    $errors->{name} = 1 if (is_empty($theme->{name}));
    unless (scalar keys %$errors) {
        $forum_model->update_theme($theme);
        return $self->redirect($self->get_referer());
    };      
  
    
    $edittheme_data->{form} = $theme;
    $edittheme_data->{errors} = $errors;

    $self->setStash("EDITTHEME", $edittheme_data);
    return 1;
};

sub block_movetheme {
    my $self = shift;
    my $q = $self->q();
    my $user = $self->get_user();
    my $forum_model = $self->get_forum_model();
    my $cms = $self->cms();
    
    my $theme_id = $q->param("id")+0;
    my $theme = $forum_model->get_theme($theme_id);
    
    return $cms->notFound() unless $theme;
    return $self->noaccess() unless $user->can_moderate($theme->{section_id});    
    
    my $referer = $self->get_referer();
    my $move = $q->param("move") ? 1 : 0;
    my $errors = {};    

    if ($move) {
        my $forum_id = $q->param("forum_id")+0;
        my $forum = $forum_model->get_forum($forum_id);
        $errors->{noforum} = 1 unless $forum;
        $errors->{noaccess} = 1 if ($forum && !$user->can_moderate($forum->{section_id}));
        unless (scalar keys %$errors) {
            $theme->{forum_id} = $forum->{id};
            $forum_model->update_theme($theme);
            return $self->redirect($referer);
        };
    };
    
    my @forums_sections = $forum_model->get_forums_structure($theme->{forum_id});
    foreach my $section (@forums_sections) {
        $section->{count} = 0 unless $user->can_moderate($section->{id});
    };
    
    my $template = $self->gettemplate("forum_theme_move.tmpl") or return $cms->error();
    
    $template->param(
        REFERER=>$referer,
        BACKURL=>$referer,
        FORUMS_SECTIONS=>\@forums_sections,
        THEME=>$theme,
        ERRORS=>$errors
    );
    
    return $self->output($template);
};

sub post_noaccess {
    my $self = shift;
    my $forum_url = $self->get_forum_url();
    my $referer = $self->get_referer();
    return $self->redirect(getURLWithParams($forum_url, {
        action=>"noaccess",
        "ref"=>$referer
    }));
};

sub block_search {
    my $self = shift;
    my $cms = $self->cms();
    my $user = $self->get_user();
    my $forum_model = $self->get_forum_model();
    my $template = $self->gettemplate("search.tmpl") or return $cms->error();
    
    my @days = $forum_model->get_search_days_select_options();
    my @forums_sections = $forum_model->get_search_forum_structure();
    # Удаляем записи которые не доступны текущему пользователю
    foreach my $section (@forums_sections) {
        $section->{show} = 0 unless $user->can_access($section->{id});
    };
    
    $template->param(
        FORUMS_SECTIONS=>\@forums_sections,
        DAYS=>\@days
    );
    
    return $self->output($template);
};

sub post_dosearch {
    my $self = shift;
    my $q = $self->q();
    my $forum_model = $self->get_forum_model();
    my @forums = $q->param("forums");
    
    my $search_session = $forum_model->search(
        keywords         => scalar $q->param("search"),
        search_in_theme  => (scalar $q->param("search_only_in_theme"))?1:0,
        search_all_words => (scalar $q->param("search_all_words"))?1:0,
        search_in_day    => (scalar $q->param("search_in_day")?(scalar $q->param("search_in_day")):0),
        forums=>\@forums,    
    );
    
    my $url = $self->get_forum_url();
    if ($search_session) {
        $url = getURLWithParams($url, {
            action=>"showsearch",
            session=>$search_session
        });
    }
    else {
        $url = getURLWithParams($url, {
            action=>"search_not_found"
        });
    };
    
    return $self->redirect($url);
};

sub block_search_not_found {
    my $self = shift;
    my $cms = $self->cms();
    my $template = $self->gettemplate("search_not_found.tmpl") or return $cms->error();
    return $self->output($template);
};

sub block_regok {
    my $self = shift;
    my $cms = $self->cms();
    return $cms->notFound() if ($self->{_external_registration});
    
    my $template = $self->gettemplate("regok") or return $cms->error();
    return $self->output($template);
};

sub block_showsearch {
    my $self = shift;
    my $q = $self->q();
    my $session = $q->param("session");
    
    my $cms = $self->cms();
    my $forum_url = $self->get_forum_url();
    my $onpage = $self->get_messages_onpage();
    my $onlist = $self->get_messages_onlist();
    my $page = $self->get_page();
    my $forum_model = $self->get_forum_model();
    
    my $search_session = $forum_model->get_search_session($session);
    return $self->unexists_search_session() unless $search_session;
    
    
    my @results = $forum_model->get_search_results($session, ($page-1)*$onpage, $onpage);
    my $count = $forum_model->get_search_results_count($session);
    my $paginator = $self->paginator(size=>$count, page=>$page, onpage=>$onpage, onlist=>$onlist, url=>getURLWithParams($forum_url, {session=>$session, action=>"showsearch"}));

    my $template = $self->gettemplate("search_results.tmpl") or return $cms->error();
    $template->param(
        RESULTS=>\@results,
        PAGINATOR=>$paginator,
        SESSION=>$search_session
    );
    
    return $self->output($template);
};

sub unexists_search_session {
    my $self = shift;
    my $cms = $self->cms();
    my $template = $self->gettemplate("unexists_search_session.tmpl") or return $cms->error();
    return $self->output($template);
};

sub block_noaccess {
    my $self = shift;
    return $self->noaccess();
};

sub byte_to_text {
    my $self = shift;
    my $size = shift;
    
    my $text = "";

    my %cap = (
        BYTE=>1, 
        KILO=>1024,
        MEGA=>1024*1024,
        GIGA=>1024*1024*1024, 
        TERA=>1024*1024*1024*1024
    );
    
    foreach (qw(TERA GIGA MEGA KILO BYTE)) {
        if ($size>=$cap{$_}) {
            $text = sprintf("%.2f %s", $size/$cap{$_}, $self->getResource("TEXT_SIZE_UNITS_".$_));
            last;
        };
    };   
    
    return $text;
};

sub smileys {
    my $self = shift;
    my $text = shift;
    
    my %smiley_images = (
        "O=)"=>"11.gif",        
        ":-)"=>"12.gif",
        ":-("=>"13.gif",    
        ";-)"=>"14.gif",
        ":-P"=>"15.gif",
        "8-)"=>"16.gif",
        ":-D"=>"17.gif",
        ":-["=>"18.gif",
        "=-O"=>"19.gif",
        ":-*"=>"20.gif",
        ":\\'("=>"21.gif",
        ":-X"=>"22.gif",
        ">:o"=>"23.gif",
        ":-|"=>"24.gif",
        ":-/"=>"25.gif",
        "*JOKINGLY*"=>"26.gif",
        "]:->"=>"27.gif",
        "[:-}"=>"28.gif",
        "*KISSED*"=>"29.gif", 
        ":-!"=>"30.gif",
        "*TIRED*"=>"31.gif",
        "*STOP*"=>"32.gif",
        "*KISSING*"=>"33.gif",
        "@}->--"=>"34.gif",
        "*THUMBS UP*"=>"35.gif",
        "*DRINK*"=>"36.gif",
        "*IN LOVE*"=>"37.gif",
        "@="=>"38.gif",
        "*HELP*"=>"39.gif",
        "\\m/"=>"40.gif",
        "%)"=>"41.gif",
        "*OK*"=>"42.gif",
        "*WASSUP*"=>"43.gif",
        "*SORRY*"=>"44.gif",
        "*BRAVO*"=>"45.gif",
        "*ROFL*"=>"46.gif",
        "*PARDON*"=>"47.gif", 
        "*NO*"=>"48.gif",
        "*CRAZY*"=>"49.gif",
        "*DONT_KNOW*"=>"50.gif",
        "*DANCE*"=>"51.gif",
        "*YAHOO*"=>"52.gif",
        "*HI*"=>"53.gif",
        "*BYE*"=>"54.gif",
        "*YES*"=>"55.gif",
        ";D"=>"56.gif",
        "*WALL*"=>"57.gif",
        "*WRITE*"=>"58.gif",
        "*SCRATCH*"=>"59.gif",
    );
    
    my $smileys_dir = $self->get_smileys_dir();
    foreach my $key (keys %smiley_images) {
        my $regexp = $key;
        $regexp = escape_angle_brackets($regexp);
        $regexp =~ s/([^a-zA-Z0-9])/\\$1/gi;
        my $smiley = sprintf("<img src=\"%s%s\">", $smileys_dir, $smiley_images{$key});
        $text =~ s/$regexp/$smiley/gmi;
    };
    
    return $text;
};

sub block_ipban {
    my $self = shift;
    my $user = $self->get_user();
    return $self->noaccess() unless $user->is_global_moderate();
    my $message_id = $self->q()->param("message_id")+0;
    my $message = $self->get_forum_model()->get_message($message_id);
    $self->get_forum_model()->ban_ip($message->{ip});
    return $self->redirect_to_ref(); 
};

sub block_userban {
    my $self = shift;
    my $user = $self->get_user();
    my $cms = $self->cms();
    my $user_id = $self->q()->param("user_id")+0;
    my $section_id = $self->q()->param("section_id")+0;
    
    my $section = $self->get_forum_model()->get_section($section_id);
    return $cms->notFound() unless $section;
    return $self->noaccess() unless $user->can_moderate($section->{id});
    my $user_ban = $self->get_user_model()->get_user_by_id($user_id);
    if ($user_ban->id() && !$user_ban->can_moderate($section->{id})) {
        $self->get_forum_model()->ban_user_on_section($user_id, $section->{id});
    };
    return $self->redirect_to_ref(); 
};

sub block_userunban {
    my $self = shift;
    my $cms = $self->cms();
    my $user = $self->get_user();
    my $user_id = $self->q()->param("user_id")+0;
    my $section_id = $self->q()->param("section_id")+0;
    
    my $section = $self->get_forum_model()->get_section($section_id);
    return $cms->notFound() unless $section;
    return $self->noaccess() unless $user->can_moderate($section->{id});
    $self->get_forum_model()->unban_user_on_section($user_id, $section->{id});
    return $self->redirect_to_ref();
};

sub block_forumban {
    my $self = shift;
    my $q = $self->q();
    my $user = $self->get_user();
    return $self->noaccess() unless ($user->is_global_moderate());
    my $user_id = $q->param("user_id")+0;
    my $user_model = $self->get_user_model();
    $user_model->set_user_ban($user_id);
    return $self->redirect_to_ref();    
};

sub block_forumunban {
    my $self = shift;
    my $q = $self->q();
    my $user = $self->get_user();
    return $self->noaccess() unless ($user->is_global_moderate());
    my $user_id = $q->param("user_id")+0;
    my $user_model = $self->get_user_model();
    $user_model->unset_user_ban($user_id);
    return $self->redirect_to_ref();    
};

sub block_banip {
    my $self = shift;
    my $user = $self->get_user();
    return $self->noaccess() unless ($user->is_global_moderate());
    my $cms = $self->cms();
    
    my $ip = $self->q()->param("ip");
    $ip =~ s/\s//g;
    my $notvalid_ip = 0;
    if ($self->q()->param("do") eq "unban") {
        if($ip =~ /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/) {
            $self->get_forum_model()->unban_ip($ip);
            return $self->redirect(getURLWithParams($self->get_forum_url(), {
                action=>"banip",
                ip=>$ip,
                unbansuccess=>1
            }));
        }
        else {
            $notvalid_ip = 1;
        };        
    }
    elsif($self->q()->param("do") eq "ban") {
        if($ip =~ /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/) {
            $self->get_forum_model()->ban_ip($ip);
            return $self->redirect(getURLWithParams($self->get_forum_url(), {
                action=>"banip",
                ip=>$ip,
                bansuccess=>1
            }));
        }
        else {
            $notvalid_ip = 1;
        };         
    };

    
    my $template = $self->gettemplate("banip.tmpl") or return $cms->error();
    my $banned_ip = $self->get_forum_model()->get_banned_ip();
    $template->param(
        IPS=>$banned_ip,
        IP=>$ip,
        NOTVALID_IP=>$notvalid_ip,
        UNBANSUCCESS=>$self->q()->param("unbansuccess")? 1: 0,
        BANSUCCESS=>$self->q()->param("bansuccess")? 1: 0,
    );
    return $self->output($template);
};

sub block_showbanforums {
    my $self = shift;
    my $user = $self->get_user();
    return $self->noaccess() unless ($user->is_global_moderate());
    my $cms = $self->cms();
    
    my $user_id = $self->q()->param("user_id")+0;
    my $sections = $self->get_forum_model()->get_sections_where_user_banned($user_id);
    foreach (@$sections) {
        $_->{is_show} = $user->can_moderate($_->{section_id}) ? 1 : 0;    
    };
    my $user_info = $self->get_user_model()->get_user_info($user_id);
    
    my $template = $self->gettemplate("showbanforums.tmpl") or return $cms->error();
    $template->param(
        USERINFO=>$user_info,
        SECTIONS=>$sections,
        BACKURL=>getURLWithParams($self->get_forum_url(), {action=>"userslist"})
    );
    return $self->output($template);
};

sub block_editusersignature {
    my $self = shift;
    my $user = $self->get_user();
    return $self->noaccess() unless ($user->is_global_moderate());
    my $cms = $self->cms();
    
    my $user_id = $self->q()->param("user_id")+0;
    my $user_edit = $self->get_user_model()->get_user_by_id($user_id);
    
    if ($self->is_post()) {
        if ($user_edit->id()) { 
            my $cgi = $self->get_processed_input();
            $user_edit->set("signature", $cgi->{signature});
            $user_edit->save();
        };
        return $self->redirect_to_ref();
    };
    
    my $template = $self->gettemplate("editusersignature.tmpl") or return $cms->error();
    $template->param(
        USER_ID=>$user_id,
        SIGNATURE=>$user_edit->get("signature"),
        BACKURL=>$self->get_referer()
    );
    return $self->output($template);
};

sub block_complaintomessage {
    my $self = shift;
    my $user = $self->get_user();
    my $cms = $self->cms();
    return $self->noaccess() unless ($user->id());
    my $message_id = $self->q()->param("message_id")+0;
    my $message = $self->get_forum_model()->get_message($message_id);
    return $cms->notFound() unless $message;
    $self->get_forum_model()->complain_to_message($message->{id});
    return $self->redirect_to_ref();
};

sub block_enterlogin {
    my $self = shift;
    my $cms = $self->cms();
    my $user = $self->get_user();
    return $self->redirect($self->get_forum_url()) unless $user->id();
    return $self->redirect($self->get_forum_url()) if($user->login());
    
    my $errors = {};
    
    if ($self->is_post()) {
        my $cgi = $self->get_processed_input();
        $errors->{empty_login} = 1 if (is_empty($cgi->{login}));
        $errors->{is_duplicate} = 1 if ($self->get_user_model()->has_login_duplicate($cgi->{login}, $user->id()));
        unless (scalar keys %$errors) {
            $user->set("login", $cgi->{login});
            $user->save();
            return $self->redirect($self->get_forum_url());
        };            
    };
    
    my $template = $self->gettemplate("enterlogin.tmpl") or return $cms->error();
    $template->param(
        ERRORS=>$errors
    );
    return $self->output($template);
};

sub _send_email {
    my $self = shift;
    my %args = @_;
    my @emails = ();
    my $ref = ref $args{to};
    if ($ref eq "ARRAY") {
        @emails = @{$args{to}}
    }
    elsif (!$ref) {
        push @emails, $args{to};
    };
    return 1 unless scalar @emails;
    my $nmailer = NMailer->mynew();
    $nmailer->add("subject", $args{subject});
    $nmailer->add("to", $emails[0]);
    $nmailer->add("from", $self->get_from_email());
    $nmailer->set_plain_part($args{plain});
    $nmailer->set_html_part($args{html}) if ($args{html});
    $nmailer->send_to_list(@emails);
};

sub block_mailertogroup {
    my $self = shift;
    my $user = $self->get_user();
    return $self->noaccess() unless $user->is_global_moderate();
    my $cms = $self->cms();
    my $q = $self->q();
    my $message = undef;
    my @groups = ();

    my $errors = {};    
    if ($self->is_post()) {
        $message = $q->param("message");
        @groups =  $q->param('group_id');
        $errors->{empty_message} = 1 if (is_empty($message));
        $errors->{nogroups} = 1 unless scalar @groups;
        unless (scalar keys %$errors) {
            $self->get_forum_model()->mailer_to_groups(
                message=>\$message,
                groups=>\@groups
            );
            return $self->redirect(getURLWithParams($self->get_forum_url(), {action=>"mailertogroup"}));
        };
    };
    
    my $template = $self->gettemplate("mailertogroup.tmpl") or return $cms->error();
    my $groups = $self->get_user_model()->get_group_list();
    my %groups = map {$_=>1} @groups;
    foreach (@$groups) {
        $_->{checked} = exists $groups{$_->{id}}? 1: 0;
    };
    $template->param(
        GROUPS=>$groups,
        ERROR=>$errors,
        MESSAGE=>$message,
    );
    return $self->output($template);
};

sub block_editsubscribe {
    my $self = shift;
    my $user = $self->get_user();
    return $self->noaccess() unless $user->is_global_moderate();
    my $user_id = $self->q()->param("user_id")+0;
    my $cms = $self->cms();
    
    my $subscribe = $self->get_forum_model()->get_user_subscribe($user_id);
    my $template = $self->gettemplate("editsubscribe.tmpl") or return $cms->error();
    $template->param(
        SUBSCRIBE=>$subscribe,
        BACKURL=>getURLWithParams($self->get_forum_url(), {action=>"userslist"}),
        USER_ID=>$user_id
    );
    return $self->output($template); 
};

sub block_deletesubscribe {
    my $self = shift;
    my $user = $self->get_user();
    return $self->noaccess() unless $user->is_global_moderate();
    my $user_id = $self->q()->param("user_id")+0;
    my $theme_id = $self->q()->param("theme_id")+0;
    $self->get_forum_model()->delete_subscribe($user_id, $theme_id);
    return $self->redirect_to_ref();
};

sub block_themetoemail {
    my $self = shift;
    my $cms = $self->cms();
    my $user = $self->get_user();
    return $self->noaccess() unless $user->id();
    my $theme_id = $self->q()->param("theme_id")+0;
    my $theme = $self->get_forum_model()->get_theme($theme_id);
    return $cms->notFound() unless $theme;
    
    if ($self->q()->param("do") eq "send") {
        my $email = $self->q()->param("email");
        $self->get_forum_model()->send_theme_to_email($theme_id, $email);
        return $self->redirect(getURLWithParams(
            $self->get_forum_url(),
            {
                action=>"themetoemail",
                theme_id=>$theme->{id},
                success=>1,
                "ref"=>$self->get_referer()
            }
        ));
    };
                                                 
    my $template = $self->gettemplate("themetoemail.tmpl") or return $cms->error();
    $template->param(
        THEME=>$theme,
        SUCCESS=>($self->q()->param("success")? 1: 0),
        BACKURL=>$self->get_referer()
    );
    return $self->output($template);
};

sub block_printtheme {
    my $self = shift;
    my $theme_id = $self->q()->param("theme_id")+0;
    my $theme = $self->get_forum_model()->get_theme($theme_id);
    return $self->cms()->notFound() unless $theme;
    
    my $messages = $self->get_forum_model()->get_messages_list($theme->{id});
    my $forum = $self->get_forum_model()->get_forum($theme->{forum_id});
    my $section = $self->get_forum_model()->get_section($theme->{section_id});
    my $forum_url = $self->get_forum_url();
    $self->add_history(
        {name=>$self->getResource("HISTORY_ROOT"), url=>$forum_url},
        {name=>$section->{name}, url=>getURLWithParams($forum_url, {action=>"showforums", section_id=>$section->{id}})},
        {name=>$forum->{name}, url=>getURLWithParams($forum_url, {action=>"showthemes", forum_id=>$forum->{id}})},
        {name=>$theme->{name}, url=>getURLWithParams($forum_url, {action=>"showmessages", theme_id=>$theme->{id}})},
    );     
    
    foreach (@$messages) {
        $_->{message} = nl2br($_->{message});
        $_->{message} = NG::Forum::BBCodes::parse_bb($_->{message});
        $_->{message} = $self->smileys($_->{message});
        $_->{create_date} = $self->datetime_from_db($_->{create_date});
        $_->{update_date} = $self->datetime_from_db($_->{update_date});
    };
    my $template = $self->gettemplate("printtheme.tmpl") or return $self->cms()->error();
    $template->param(
        MESSAGES=>$messages,
        THEME=>$theme
    );
    return $self->output($template);
};

sub block_newmessages {
    my $self = shift;
    my $user = $self->get_user();
#     return $self->noaccess() unless $user->is_section_moderate();
    
    my $template = $self->gettemplate("newmessages.tmpl") or return $self->cms()->error();
    my $themes = $self->get_forum_model()->get_unread_themes($user->id());
    foreach (@$themes) {
        $_->{lastupdate_date} = $self->datetime_from_db($_->{lastupdate_date}) if ($_->{show});
    };
    $template->param(
        THEMES=>$themes
    );
    return $self->output($template);
};

sub block_activethemes {
    my $self = shift;
    my $user = $self->get_user();
#     return $self->noaccess() unless $user->is_global_moderate();
    my $day = $self->q()->param("day")+0;
    my $themes = $self->get_forum_model()->get_active_themes($day);
    foreach (@$themes) {
        $_->{lastupdate_date} = $self->datetime_from_db($_->{lastupdate_date});
    };
    my $template = $self->gettemplate("activethemes.tmpl") or return $self->cms()->error();
    $template->param(
        THEMES=>$themes,
        "DAY".$day=>1
    );
    return $self->output($template);
};

sub block_activeusers {
    my $self = shift;
    my $user = $self->get_user();
    return $self->noaccess() unless $user->is_global_moderate();
    my $day = $self->q()->param("day")+0;
    my $users = $self->get_forum_model()->get_active_users($day);
    my $template = $self->gettemplate("activeusers.tmpl") or return $self->cms()->error();
    $template->param(
        USERS=>$users,
        "DAY".$day=>1
    );
    return $self->output($template);
};

sub block_addfiles {
    my $self = shift;
    my $message_id = $self->q()->param("message_id");
    my $message = $self->get_forum_model()->get_message($message_id);
    my $user = $self->get_user();
    my $cgi = $self->get_processed_input();
    return $self->cms()->notFound() unless ($message);
    my $message_url = getURLWithParams($self->get_forum_url(), {
            action=>"showmessages",
            theme_id=>$message->{theme_id},
            message_id=>$message->{id},
    })."#message".$message->{id};
    return $self->redirect($message_url) if ($message->{author_user_id} != $user->id());
    
    my @files = $self->get_forum_model()->get_message_files($message_id);
    my $max_files_count = $self->get_max_files_count();
    my $max_file_size = $self->get_max_file_size();
    my $max_total_files_size = $self->get_max_total_files_size();

    my $files_count = scalar @files;     
    my $total_size = 0;
    
    if ($self->is_post) {
        my @files_uploaded = map {$self->get_forum_model->get_message_file_info($_)} grep {/file_/} keys %$cgi;
        my @files_to_save = ();
        foreach (@files_uploaded) {
            next unless $_;
            next if ($_->{size}>$max_file_size);
            $total_size += $_->{size};
            $files_count++;
            next if ($total_size>$max_total_files_size);
            next if ($files_count>$max_files_count);
            
            push @files_to_save, $_;
        };
        $self->get_forum_model->upload_message_files($message->{id}, @files_to_save);
        
        return $self->redirect(getURLWithParams(
            $self->get_forum_url,
            {
                action=>"addfiles",
                message_id=>$message->{id}
            }
        ));
    };
    
    my $newfiles_count = $max_files_count - scalar @files;
    
    my @empty = ();
    while ($newfiles_count) {
        unshift @empty, $newfiles_count;
        $newfiles_count--;
    };
    my $template = $self->gettemplate("addfiles.tmpl") or return $self->cms()->error();
    foreach (@files) {
        $_->{size} = $self->byte_to_text($_->{size});
    };
    $template->param(
        FILES=>\@files,
        EMPTY=>\@empty,
        MESSAGE_URL=>$message_url,
        MESSAGE_ID=>$message->{id},
        MESSAGEURL=>$message_url,
        MAX_FILES_COUNT=>$max_files_count,
        MAX_FILE_SIZE=>$self->byte_to_text($max_file_size),
        MAX_TOTAL_FILES_SIZE=>$self->byte_to_text($max_total_files_size)
    );
    return $self->output($template)
};


1;