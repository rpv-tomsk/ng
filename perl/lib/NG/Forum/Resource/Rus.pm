package NG::Forum::Resource::Rus;
use strict;

sub init_resource {
    return {
        PAGINATOR_PREV_PAGE => '���������� ��������',
        PAGINATOR_NEXT_PAGE => '��������� ��������',
        
        TEXT_THEMES_COUNT=>"����",
        TEXT_MESSAGES_COUNT=>"���������",
        TEXT_LAST_MESSAGE=>"��������� ���������",
        TEXT_NO_THEMES=>"��� ���",
        TEXT_ADDTHEME=>"������� ����",
        
        TEXT_ADDTHEME_AUTHOR=>"���� ���",
        TEXT_ADDTHEME_NAME=>"����",
        TEXT_ADDTHEME_MESSAGE=>"���������",
        TEXT_ADDTHEME_SUBMIT=>"��������",
        TEXT_ADDTHEME_PREVIEW=>"������������",
        TEXT_ADDTHEME_ADDPOLL=>"���� �����",
        TEXT_ADDTHEME_POLLMULTICHOICE=>"����� ���������� ���������",
        TEXT_ADDTHEME_ADDFILES=>"� ���� ���������� �����",
        TEXT_ADDTHEME_DELETEVARIANT=>"�������",
        TEXT_ADDTHEME_CREATEPOLL=>"������� ����� � ����",
        TEXT_ADDTHEME_ADDPOLLVARIANT=>"�������� ������� ������",
        TEXT_ADDTHEME_VARIANT=>"������� ������",
        TEXT_ADDTHEME_BACK=>"��������� � ����������",
        ERROR_ADDTHEME_NAME=>"������� �������� ����",
        ERROR_ADDTHEME_MESSAGE=>"������� ���������",
        ERROR_ADDTHEME_FORUM_ID=>"����� ���� �� ��������� �������� ����, �� ����������",
        
        TEXT_ADDMESSAGE=>"�������� ���������",
        TEXT_ADDMESSAGE_AUTHOR=>"���� ���",
        TEXT_ADDMESSAGE_HEADER=>"���������",
        TEXT_ADDMESSAGE_MESSAGE=>"���������",
        TEXT_ADDMESSAGE_SUBMIT=>"��������",
        TEXT_ADDMESSAGE_PREVIEW=>"������������",
        TEXT_ADDMESSAGE_BACK=>"��������� � ����������",
        TEXT_ADDMESSAGE_FILE=>"����",
        TEXT_ADDMESSAGE_ADDFILE=>"�������� ��� ����",
        TEXT_ADDMESSAGE_ADDFILES=>"� ���� ���������� �����",
        ERROR_ADDMESSAGE_MESSAGE=>"������� ���������",
        ERROR_ADDMESSAGE_THEME_ID=>"���� ���� �� ��������� �������� ���������, �� ���������� ��� �������",
        ERROR_ADDMESSAGE_MAX_FILES_COUNT=>"�� ��������� ������������ ���������� ���������� ������",
        ERROR_ADDMESSAGE_MAX_FILES_SIZE=>"�� ��������� ����� ������������ ������ ���� ���������� ������",
        ERROR_ADDMESSAGE_MAX_FILE_SIZE=>"���� ��� ��������� ������ ��������� ������ ����������� �����",
        ERROR_ADDMESSAGE_FILE_TYPE_ERROR=>"���� �� ���������� ������ ����� �� �������������� ���",
        
        FORUM_PANEL_PROFILE=>"�������",
        FORUM_PANEL_LOGIN=>"�����",
        FORUM_PANEL_LOGOUT=>"�����",
        FORUM_PANEL_SEARCH=>"�����",
        FORUM_PANEL_RECOVERYPWD=>"������������ ������",
        FORUM_PANEL_USERSLIST=>"������ �������������",
        FORUM_PANEL_GROUPSADMIN=>"����������������� �����",
        FORUM_PANEL_PAGER=>"�������",
        FORUM_PANEL_REG=>"�����������",
        FORUM_PANEL_INDEX=>"�����",
        FORUM_PANEL_BANIP=>"���� �� IP",
        FORUM_PANEL_MAILERTOGROUP=>"�������� �������",
        FORUM_PANEL_NEWMESSAGES=>"����� ���������",
        FORUM_PANEL_ACTIVETHEMES=>"�������� ����������",
        FORUM_PANEL_ACTIVEUSERS=>"�������� ������������",
        
        TEXTFORUM_AUTH=>"�����������",
        TEXT_FORUM_LOGIN=>"�����",
        ERROR_FORUM_AUTH=>"������ �����������",
        
        TEXT_ATTACHED_THEMES=>"������������� ����",
        
        TEXT_CLOSE_THEME=>"������� ����",
        TEXT_OPEN_THEME=>"������� ����",
        TEXT_EDIT_THEME=>"������������� ����",
        TEXT_MOVE_THEME=>"��������� ����",
        TEXT_DELETE_THEME=>"������� ����",
        
        TEXT_EDITTHEME_SUBMIT=>"�������������",
        TEXT_EDITTHEME_PREVIEW=>"������������",
        TEXT_EDITTHEME_BACK=>"��������� � ��������������",  
        TEXT_EDITTHEME_NAME=>"��������",      
        
        TEXT_FORUM_DELETETHEME_CONFIRMATION=>"�� ������������� ������ ������� ����",
        TEXT_MOVETHEME_MOVE=>"���������",
        TEXT_MOVETHEME=>"������� ����",
        
        TEXT_MOVETHEME_ERROR_NOFORUM=>"�� ��������� ��������� ���� � �������������� �����",
        TEXT_MOVETHEME_ERROR_NOACCESS=>"� ��� ��� ���� ���������� ���� � ���� �����",
        TEXT_EDIT_MESSAGE=>"������������� ���������",
        TEXT_DELETE_MESSAGE=>"������� ���������",
        TEXT_FORUM_DELETEMESSAGE_CONFIRMATION=>"�� ������������� ������ ������� ���������",
        
        ERROR_EDITMESSAGE_ID=>"����������� ���������",
        ERROR_EDITMESSAGE_MESSAGE=>"������� ���������",
        TEXT_EDITMESSAGE=>"�������������� ���������",
        TEXT_EDITMESSAGE_MESSAGE=>"���������",
        TEXT_EDITMESSAGE_SUBMIT=>"�������������",
        TEXT_EDITMESSAGE_BACK=>"��������� � ��������������",
        TEXT_EDITMESSAGE_PREVIEW=>"������������",
        TEXT_EDITMESSAGE_DELETEFILE=>"������� ����",
        
        TEXT_DELETEFILE_CONFIRM=>"�� ������������� ������� ������� ����",
        TEXT_USERSSEARCH=>"����� ������������",
        TEXT_BACK_TO_USERSLIST=>"������� � ������ �������������",
        TEXT_SET_USERBAN=>"�������� ������������",
        TEXT_UNSET_USERBAN=>"��������� ������������",
        
        TEXT_SET_MODERATE=>"������� �����������",
        TEXT_UNSET_MODERATE=>"������ �������������� �����",
        TEXT_USERS_GROUPS=>"������ �������������",
        TEXT_USER_BAN_FORUM=>"������ ���������� �������",
        TEXT_USER_EDIT_SUBSCRIBE=>"������������� ��������",
        
        TEXT_DEFAULT_GROUP_NAME=>"������������",
        TEXT_ANONYMOUS_GROUP_NAME=>"��������� ������������",
        TEXT_NOGROUPS=>"��� �����",
        
        TEXT_DELETE_GROUP=>"������� ������",
        TEXT_CONFIRM_DELETE_GROUP=>"�� ������������� ������ ������� ������",
        TEXT_EDIT_GROUP=>"����������� ������",
        TEXT_CHANGE_GROUP_PRIVS=>"���������� ����������",
        TEXT_ADDGROUP_NAME=>"������",
        TEXT_ADDGROUP=>"�������� ������",
        ERROR_ADDGROUP_NAME=>"������� �������� ������",
        
        TEXT_EDITGROUP=>"������������� ������",
        TEXT_EDITGROUP_NAME=>"������",
        ERROR_EDITGROUP_NAME=>"������� �������� ������",
        ERROR_EDITGROUP_ID=>"����������� ������",
        
        TEXT_ACCESS_PRIV_NAME=>"������ � ������",
        TEXT_WRITE_PRIV_NAME=>"������ � ������",
        TEXT_MODERATE_PRIV_NAME=>"��������� ������",
        
        TEXT_SETPRIVILEGES=>"���������� �����",
        
        TEXT_PROFILE_CHANGE_PASSWORD_AND_EMAIL=>"������� ������ ��� Email",
        TEXT_PROFILE_CURRENT_PASSWORD=>"������� ������",
        TEXT_PROFILE_NEW_PASSWORD=>"����� ������",
        TEXT_PROFILE_RETYPE_PASSWORD=>"������������� ������",
        TEXT_PROFILE_EMAIL=>"Email",
        TEXT_PROFILE_CHANGE=>"���������",  
        TEXT_PROFILE_CHANGE_AVATAR=>"�������� ������",
        TEXT_PROFILE_DELETE_AVATAR=>"������� ������",
        TEXT_PROFILE_CHANGE_OTHER=>"������ ���������",
        TEXT_PROFILE_SIGNATURE=>"�������",
        TEXT_RPOFILE_CHANGE_ZONES=>"�������� ��������� ����",
        TEXT_PROFILE_ZONE=>"��������� ����",
        TEXT_PROFILE_IS_SUBSCRIBE=>"�������� ����������� � ����� ��������� � ������������ ��������",
        TEXT_PROFILE_EXTEND=>"�������������� ������",
        TEXT_PROFILE_EXTEND_BUTTON=>"���������",
        ERROR_PROFILE_PASSWORD=>"�������� ������� ������",      
        ERROR_PROFILE_RETYPE_PASSWORD=>"����� ������ � ������������� �� ���������",
        ERROR_PROFILE_EMAIL=>"������������ Email",
        ERROR_PROFILE_EMAIL_DUPLICATE=>"������ Email ��� ��������������� � ������� � ����������� ������� ������������",
        ERROR_PROFILE_AVATAR_EMPTY=>"�� ������ ����",
        ERROR_PROFILE_AVATAR_NOT_IMAGE=>"���������� ���� �� �������� ������������",
        ERROR_PROFILE_AVATAR_WRONG_UPLOAD=>"������ ��� ������� �����",
        ERROR_PROFILE_AVATAR_PROCESS=>"������ ��� ��������� �������",
        ERROR_PROFILE_EXTEND=>"������� ��������",
        
        ERROR_USERS_NOT_FOUND=>"������������ �� �������",
        
        TEXT_RECOVERYPWD_LOGIN=>"�����",
        TEXT_RECOVERYPWD_EMAIL=>"Email",
        TEXT_RECOVERYPWD=>"������������ ������",
        TEXT_RECOVERYPWD_INSTRUCTION=>"��� �������������� ������ ������ ������� ����� ��� ������",
        TEXT_RECOVERYPWD_OKMESSAGE=>"�� email ��������� ���� ��� ����������� ������ ��� ������",
        
        EMAIL_RECOVERYPWD_HELLO=>"���������",
        EMAIL_RECOVERYPWD_SUBJECT=>"��� ������ ��� ������� �� ",
        EMAIL_RECOVERYPWD_REQUEST=>"�� ������ ������� �������� ������ ��� ������� � ������",
        ERROR_RECOVERYPWD_ALL_EMPTY=>"������� email ��� ����� ��� �������������� ������",
        ERROR_RECOVERYPWD_NORESULT=>"��� ������ ������������",
        EMAIL_RECOVERYPWD_LOGIN=>"�����",
        EMAIL_RECOVERYPWD_PASSWORD=>"������",
        EMAIL_RECOVERYPWD_REGARDS=>"� ���������� �����������, ������������� ������.",
        
        TEXT_PAGER_CONFIRM_DELETE=>"�� ������������� ������ ������� ���������",
        TEXT_PAGER_DELETE=>"�������",
        TEXT_PAGER_IN=>"��������",
        TEXT_PAGER_OUT=>"���������",
        TEXT_PAGER_ADD=>"��������",
        TEXT_PAGER_EMAIL_SUBJECT=>"����������� � ������ ���������",
        TEXT_PAGER_EMAIL_HELLO=>"�����������",
        TEXT_PAGER_EMAIL_TEXT=>"��� ������ ����� ������ ���������",
        TEXT_PAGER_EMAIL_SEE=>"�� ������ �������� ��� ���������, ������� �� ��������� ������",
        TEXT_PAGER_EMAIL_FROM=>"�� ����",
        TEXT_PAGER_EMAIL_MESSAGE=>"���������",
        TEXT_PAGER_HEADER=>"���������",
        TEXT_PAGER_MESSAGE=>"���������",
        TEXT_PAGER_NO_THEME=>"��� ����",
        TEXT_PAGER=>"�������",
        
        TEXT_REG_EMAIL=>"Email",
        TEXT_REG_LOGIN=>"�����",
        TEXT_REG_PASSWORD=>"������",
        TEXT_REG_RETYPE_PASSWORD=>"����������� ������",
        TEXT_REG=>"����������������",
        TEXT_REG_ALL_FIELDS_REQUERED=>"��� ���� ����������� ��� ����������",
        TEXT_REG_ERROR_EMPTY_EMAIL=>"������� email",
        TEXT_REG_ERROR_NOT_VALID_EMAIL=>"������������ email",
        TEXT_REG_ERROR_NOT_UNIQUE_EMAIL=>"����� email ��� ����������� ������� ������������",
        TEXT_REG_ERROR_EMPTY_LOGIN=>"������� �����",
        TEXT_REG_ERROR_NOT_UNIQUE_LOGIN=>"����� ����� ��� ����������� ������� ������������",
        TEXT_REG_ERROR_EMPTY_PASSWORD=>"������� ������",
        TEXT_REG_ERROR_NOT_EQUALE_PASSWORD=>"������ �� ����������",
        TEXT_REG_OK=>"����������� ������ �������",
        
        TEXT_POLL_VOTE=>"����������",
        
        TEXT_SEARCH_HEADER=>"�����",
        TEXT_SEARCH_BUTTON=>"������",
        TEXT_SEARCH_ONLY_IN_THEME=>"������ ������ � ��������� ���",
        TEXT_SEARCH_ALLWORDS=>"������ ��� �����",
        TEXT_SEARCH_IN_DAY=>"������ �� ��������� ���",
        
        TEXT_SEARCH_ALL=>"�� ��� �����",
        TEXT_SEARCH_TODAY=>"�� �������",
        TEXT_SEARCH_LAST_3_DAYS=>"��������� 3 ���",
        TEXT_SEARCH_LAST_WEEK=>"��������� ������",
        TEXT_SEARCH_LAST_2_WEEKS=>"��������� 2 ������",
        TEXT_SEARCH_LAST_MONTH=>"�� ��������� �����",
        
        TEXT_SEARCH_ALL_FORUMS=>"������ �����",
        TEXT_SEARCH_SELECTFORUM=>"�������� ���� ��� ������",
        TEXT_SEARCH_RESULT=>"���������� ������ �� �������",
        
        TEXT_SEARCH_NOT_FOUND=>"����� �� ��� �����������",
        TEXT_UNEXISTS_SEARCH_SESSION=>"����������� ��� ���������� ��������� ������",

        
        TEXT_FILE_SIZE=>"������ �����",
        TEXT_DOWNLOAD=>"�������",
        TEXT_SIZE_UNITS_BYTE=>"����",
        TEXT_SIZE_UNITS_KILO=>"��",
        TEXT_SIZE_UNITS_MEGA=>"��",
        TEXT_SIZE_UNITS_GIGA=>"��",
        TEXT_SIZE_UNITS_TERA=>"��",
        
        TEXT_USER_BAN=>"���",
        TEXT_USER_TOBAN=>"��������",
        TEXT_USER_USER=>"������������",
        TEXT_USER_MODERATOR=>"���������",
        
        TEXT_USER_GROUPS_LIST=>"������ ���� �������������",
        TEXT_ADD_GROUP=>"��������",
        TEXT_DELETE_GROUP=>"�������",
        TEXT_AVALAIBLE_GROUPS=>"��������� ������",
        TEXT_USER_GROUPS=>"������ ������������",
        TEXT_SAVE=>"���������",
        TEXT_SET_USER_GROUPS=>"���������� ����� ������������",
        
        TEXT_THEME_SUBSCRIBE_DEAR=>"���������",
        TEXT_THEME_SUBSCRIBE_SUBSCRIBED_THEME=>"������ ��� ������� � ����, �� ������� �� ���������",
        TEXT_THEME_SUBSCRIBE_SUBSCRIBED_THEME_MODERATE=>"������ ���  ������� � ����",
        TEXT_THEME_SUBSCRIBE_THEME_URL=>"��� ���� ����������� �� ������",
        TEXT_THEME_SUBSCRIBE_MESSAGE_POST=>"����� ���������, ������� ���� ������ ��� ���������",
        TEXT_THEME_SUBSCRIBE_UNSUBSCRIBE_THEME=>"����� ���������� �� ���� ����, �������� ������:",
        TEXT_THEME_SUBSCRIBE_UNSUBSCRIBE_ALL_THEMES=>"����� ���������� �� ���� ���, �������� ������:",
        TEXT_THEME_SUBSCRIBE=>"����������� �� ����",
        TEXT_THEME_UNSUBSCRIBE=>"���������� �� ����",
        
        THEME_SUBSCRIBE_SUBJECT=>"����� ��������� � ����",
        TEXT_UNSUBSCRIBE_THEME_SUCCESS=>"�� ���������� �� ����",
        TEXT_UNSUBSCRIBE_ALL_THEMES_SUCCESS=>"�� ���������� �� ���� ���",
        TEXT_UNSUBSCRIBE_USER_ERROR=>"�� �� ������������",
        TEXT_UNSUBSCRIBE_THEME_ERROR=>"�� ������������ ����",
        
        TEXT_BACK_TO_FORUM=>"��������� �� �����",
        
        TEXT_CHANGE_GROUP_PRIVS=>"���������� ���������� ������",
        TEXT_CHANGE_GROUP_PRIVS_GROUP=>"������",
        TEXT_CHANGER_GROUPS_PRIVS_FORUM_NAME=>"������������ ������",
        
        TEXT_USER_PROFILE=>"������� ������������",
        TEXT_USER_PROFILE_MESSAGES_COUNT=>"���������� ���������",
        
        TEXT_LOGIN_EMAIL=>"Email",
        TEXT_LOGIN_PASSWORD=>"������",
        TEXT_LOGIN_LOGIN=>"�����",
        TEXT_FORUM_AUTH=>"�����������",
        
        TEXT_USER_INFO_SEND_PM=>"��������� ������������ ���������",
        TEXT_NOACCESS=>"��� ������� �� ������ ��������",
        
        CREATE_THEME=>"������� ����",
        
        BACK_TO_PAGER=>"��������� � �������",
        BACK_TO_USERGROUPS=>"��������� � ������ �����",
        BACK_TO_THEMES=>"��������� � ������ ���",
        BACK_TO_FORUMS=>"��������� � ������ �������",
        BACK_TO_THEME=>"��������� � ����",
        BACK_TO_USERSLIST=>"��������� � ����� �������������",
        
        FORUM_INFO=>"����������",
        FORUM_INFO_USERS=>"����� �������������",
        FORUM_INFO_TOTAL=>"�����",
        FORUM_INFO_MESSAGES_IN=>"��������� �",
        FORUM_INFO_THEMES_IN=>"����� �",
        FORUM_INFO_FORUMS=>"��������",
        
        FORUM_LATEST_THEMES=>"��������� ����",
        HISTORY_ROOT=>"�����",
        
        BAN_TO_IP=>"�������� IP",
        BAN_TO_USER=>"�������� ������������ � ���� �������",
        BAN_TO_FORUM=>"�������� �� ���� ������",
        
        UNBANIP=>"��������� IP",
        BANIP=>"�������� IP",
        BANIP_IP=>"������� IP",
        UNBANIP_BUTTON=>"���������",
        BANIP_BUTTON=>"��������",
        BANIP_UNBANSUCCESS=>"���������� IP-������",
        BANIP_BANSUCCESS=>"������� IP-������",
        BANIP_NOTVALID_IP=>"������ ������������ IP",
        
        BANFORUMS=>"���� �� �������",
        BANFORUMS_UNBAN=>"����� ���",
        BANFORUMS_LIST=>"������ ��������",
        BANFORUMS_LOGIN=>"�����",
        BANFORUMS_EMAIL=>"Email",
        BANFORUMS_USERINFO=>"������ ������������",
        
        EDITUSERSIGNATURE=>"������������� �������",
        EDITUSERSIGNATURE_SIGNATURE=>"�������",
        EDITUSERSIGNATURE_BUTTON=>"�������������",
        
        COMPLAIN_TO_MESSAGE=>"������������ �� ���������",
        
        ENTERLOGIN=>"������� �����",
        ENTERLOGIN_LOGIN=>"�����",
        ENTERLOGIN_BUTTON=>"���������",
        ENTERLOGIN_ERROR_EMPTY_LOGIN=>"������� �����",
        ENTERLOGIN_ERROR_IS_DUPLICATE=>"����� ����� ��� ���������������",
        
        COMPLAIN_MESSAGE_EMAIL_SUBJECT=>"������ �� ���������",
        COMPLAIN_MESSAGE_EMAIL_FROM_USER=>"�� ������������",
        COMPLAIN_MESSAGE_EMAIL_COMPLAIN_TO=>"��������� ������ �� ��������� �",
        
        FORUM_USERS_STATUS_1=>"������",
        FORUM_USERS_STATUS_2=>"�������",
        FORUM_USERS_STATUS_3=>"�����������",
        FORUM_USERS_STATUS_4=>"�������",
        FORUM_USERS_STATUS_5=>"��������",
        FORUM_USERS_STATUS_6=>"�������",
        FORUM_USERS_STATUS_7=>"���� ���",
        FORUM_USERS_STATUS_8=>"������� �� �����",
        FORUM_USERS_STATUS_9=>"�������, � �������� ����� ���������� �������",
        FORUM_USERS_STATUS_10=>"�������, � �������� ����� ����� ���������� �������",
        FORUM_USERS_STATUS_11=>"����",
        
        USER_STATUS=>"������",
        USER_MESSAGES_CNT=>"���������",
        
        MAILERTOGROUP=>"�������� ��������� �������",
        MAILERTOGROUP_NOGROUP=>"��� �����",
        MAILERTOGROUP_MESSAGE=>"���������",
        MAILERTOGROUP_BUTTON=>"��������",
        MAILERTOGROUP_MAIL_SUBJECT=>"��������",
        MAILERTOGROUP_ERROR_EMPTY_MESSAGE=>"������� ���������",
        MAILERTOGROUP_ERROR_NOGROUPS=>"�������� ������",
        
        EDITSUBSCRIBE_DELETE=>"�������� �� ����",
        EDITSUBSCRIBE=>"������������� �������� �� ����",
        
        THEMETOEMAIL=>"��������� ���������� �� email",
        THEMETOEMAIL_EMAIL=>"Email",
        THEMETOEMAIL_EMAIL_SUBJECT=>"�� <username> - c����� �� ���� � ������ <forum>",
        THEMETOEMAIL_EMAIL_USERNAME=>"������������",
        THEMETOEMAIL_EMAIL_SEND_LINK=>"�������� ��� ������ �� ����",
        THEMETOEMAIL_EMAIL_IN_FORUM=>"� ������",
        THEMETOEMAIL_SUCCESS=>"Email ���������",
        PRINTTHEME=>"������ ��� ������",
        
        NEWMESSAGES=>"����� ���������",
        
        ACTIVETHEMES=>"�������� ����",
        ACTIVETHEMES_DAYCOUNT=>"�������� ���������� ����",
        ACTIVETHEMES_BUTTON=>"�������",
        
        ACTIVEUSERS=>"�������� ������������",
        ACTIVEUSERS_DAYCOUNT=>"�������� ���������� ����",
        ACTIVEUSERS_BUTTON=>"�������",
        
        ADDFILES=>"���������� ������",
        ADDFILES_MAX_FILES_COUNT=>"������������ ���������� ������",
        ADDFILES_MAX_FILE_SIZE=>"������������ ������ �����",
        ADDFILES_MAX_TOTAL_FILES_SIZE=>"������������ ��������� ������ ������",
        ADDFILES_ANONYOUS_DENIED=>"��������� ������������� ������� ������ ���������",
        ADDFILES_MOREFILES_DENIED=>"������ ������ �������� ������",
        ADDFILES_BUTTON=>"���������",
        ADDFILES_GOTO_MESSAGE=>"������� � ���������",
        
        PREVIEW_MESSAGE=>"������������ ���������",
        USER_ONLINE => "Online",
        USER_OFFLINE => "Offline",
        DOCITE => "����������",
    };    
};

sub new {
    my $class = shift;
    my $obj = {};
    bless $obj,$class;
    $obj->{_resource} = $obj->init_resource();
    return $obj; 
};

sub getResource {
    my $self = shift;
    my $name = shift or return undef;
    return $self->{_resource}->{$name} if (exists $self->{_resource}->{$name});
    return undef;
};


1;