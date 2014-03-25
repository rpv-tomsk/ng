package NG::Forum::Resource::Rus;
use strict;

sub init_resource {
    return {
        PAGINATOR_PREV_PAGE => 'Предыдущая страница',
        PAGINATOR_NEXT_PAGE => 'Следующая страница',
        
        TEXT_THEMES_COUNT=>"Темы",
        TEXT_MESSAGES_COUNT=>"Сообщения",
        TEXT_LAST_MESSAGE=>"Последнее сообщение",
        TEXT_NO_THEMES=>"Нет тем",
        TEXT_ADDTHEME=>"Создать тему",
        
        TEXT_ADDTHEME_AUTHOR=>"Ваше имя",
        TEXT_ADDTHEME_NAME=>"Тема",
        TEXT_ADDTHEME_MESSAGE=>"Сообщение",
        TEXT_ADDTHEME_SUBMIT=>"Добавить",
        TEXT_ADDTHEME_PREVIEW=>"Предпросмотр",
        TEXT_ADDTHEME_ADDPOLL=>"Тема опрос",
        TEXT_ADDTHEME_POLLMULTICHOICE=>"Выбор нескольких вариантов",
        TEXT_ADDTHEME_ADDFILES=>"Я хочу прикрепить файлы",
        TEXT_ADDTHEME_DELETEVARIANT=>"Удалить",
        TEXT_ADDTHEME_CREATEPOLL=>"Создать опрос в теме",
        TEXT_ADDTHEME_ADDPOLLVARIANT=>"Добавить вариант ответа",
        TEXT_ADDTHEME_VARIANT=>"Вариант ответа",
        TEXT_ADDTHEME_BACK=>"Вернуться к добавлению",
        ERROR_ADDTHEME_NAME=>"Введите название темы",
        ERROR_ADDTHEME_MESSAGE=>"Введите сообщение",
        ERROR_ADDTHEME_FORUM_ID=>"Форум куда вы пытаетесь добавить тему, не существует",
        
        TEXT_ADDMESSAGE=>"Добавить сообщение",
        TEXT_ADDMESSAGE_AUTHOR=>"Ваше имя",
        TEXT_ADDMESSAGE_HEADER=>"Заголовок",
        TEXT_ADDMESSAGE_MESSAGE=>"Сообщение",
        TEXT_ADDMESSAGE_SUBMIT=>"Добавить",
        TEXT_ADDMESSAGE_PREVIEW=>"Предпросмотр",
        TEXT_ADDMESSAGE_BACK=>"Вернуться к добавлению",
        TEXT_ADDMESSAGE_FILE=>"Файл",
        TEXT_ADDMESSAGE_ADDFILE=>"Добавить еще файл",
        TEXT_ADDMESSAGE_ADDFILES=>"Я хочу прикрепить файлы",
        ERROR_ADDMESSAGE_MESSAGE=>"Введите сообщение",
        ERROR_ADDMESSAGE_THEME_ID=>"Тема куда вы пытаетесь добавить сообщение, не существует или закрыта",
        ERROR_ADDMESSAGE_MAX_FILES_COUNT=>"Вы привысили максимальное количество заливаемых файлов",
        ERROR_ADDMESSAGE_MAX_FILES_SIZE=>"Вы привысили общий максимальный размер всех заливаемых файлов",
        ERROR_ADDMESSAGE_MAX_FILE_SIZE=>"Один или несколько файлов превысили размер заливаевого файла",
        ERROR_ADDMESSAGE_FILE_TYPE_ERROR=>"Один из заливаемых файлов имеет не соответсвующий тип",
        
        FORUM_PANEL_PROFILE=>"Профиль",
        FORUM_PANEL_LOGIN=>"Войти",
        FORUM_PANEL_LOGOUT=>"Выход",
        FORUM_PANEL_SEARCH=>"Поиск",
        FORUM_PANEL_RECOVERYPWD=>"Восстановить пароль",
        FORUM_PANEL_USERSLIST=>"Список пользователей",
        FORUM_PANEL_GROUPSADMIN=>"Администрирование групп",
        FORUM_PANEL_PAGER=>"Пейджер",
        FORUM_PANEL_REG=>"Регистрация",
        FORUM_PANEL_INDEX=>"Форум",
        FORUM_PANEL_BANIP=>"Баны по IP",
        FORUM_PANEL_MAILERTOGROUP=>"Написать группам",
        FORUM_PANEL_NEWMESSAGES=>"Новые сообщения",
        FORUM_PANEL_ACTIVETHEMES=>"Активные обсуждения",
        FORUM_PANEL_ACTIVEUSERS=>"Активные пользователи",
        
        TEXTFORUM_AUTH=>"Авторизация",
        TEXT_FORUM_LOGIN=>"Войти",
        ERROR_FORUM_AUTH=>"Ошибка авторизации",
        
        TEXT_ATTACHED_THEMES=>"Прикрепленные темы",
        
        TEXT_CLOSE_THEME=>"Закрыть тему",
        TEXT_OPEN_THEME=>"Открыть тему",
        TEXT_EDIT_THEME=>"Редактировать тему",
        TEXT_MOVE_THEME=>"Перенести тему",
        TEXT_DELETE_THEME=>"Удалить тему",
        
        TEXT_EDITTHEME_SUBMIT=>"Редактировать",
        TEXT_EDITTHEME_PREVIEW=>"Предпросмотр",
        TEXT_EDITTHEME_BACK=>"Вернуться к редактированию",  
        TEXT_EDITTHEME_NAME=>"Название",      
        
        TEXT_FORUM_DELETETHEME_CONFIRMATION=>"Вы действительно хотите удалить тему",
        TEXT_MOVETHEME_MOVE=>"Перенести",
        TEXT_MOVETHEME=>"Перенос темы",
        
        TEXT_MOVETHEME_ERROR_NOFORUM=>"Вы пытаетесь перенести тему в несуществующий форум",
        TEXT_MOVETHEME_ERROR_NOACCESS=>"У вас нет прав переносить тему в этот форум",
        TEXT_EDIT_MESSAGE=>"Редактировать сообщение",
        TEXT_DELETE_MESSAGE=>"Удалить сообщение",
        TEXT_FORUM_DELETEMESSAGE_CONFIRMATION=>"Вы действительно хотите удалить сообщения",
        
        ERROR_EDITMESSAGE_ID=>"Неизвестное сообщение",
        ERROR_EDITMESSAGE_MESSAGE=>"Введите сообщение",
        TEXT_EDITMESSAGE=>"Редактирование сообщения",
        TEXT_EDITMESSAGE_MESSAGE=>"Сообщение",
        TEXT_EDITMESSAGE_SUBMIT=>"Редактировать",
        TEXT_EDITMESSAGE_BACK=>"Вернуться к редактированию",
        TEXT_EDITMESSAGE_PREVIEW=>"Предпросмотр",
        TEXT_EDITMESSAGE_DELETEFILE=>"Удалить файл",
        
        TEXT_DELETEFILE_CONFIRM=>"Вы действительно желаете удалить файл",
        TEXT_USERSSEARCH=>"Найти пользователя",
        TEXT_BACK_TO_USERSLIST=>"Вернуть к списку пользователей",
        TEXT_SET_USERBAN=>"Забанить пользователя",
        TEXT_UNSET_USERBAN=>"Разбанить пользователя",
        
        TEXT_SET_MODERATE=>"Сделать модератором",
        TEXT_UNSET_MODERATE=>"Убрать модератороские права",
        TEXT_USERS_GROUPS=>"Группы пользователей",
        TEXT_USER_BAN_FORUM=>"Список забанненых форумов",
        TEXT_USER_EDIT_SUBSCRIBE=>"Редактировать подписку",
        
        TEXT_DEFAULT_GROUP_NAME=>"Пользователи",
        TEXT_ANONYMOUS_GROUP_NAME=>"Анонимные пользователи",
        TEXT_NOGROUPS=>"Нет групп",
        
        TEXT_DELETE_GROUP=>"Удалить группу",
        TEXT_CONFIRM_DELETE_GROUP=>"Вы действительно хотите удалить группу",
        TEXT_EDIT_GROUP=>"Редактирова группу",
        TEXT_CHANGE_GROUP_PRIVS=>"Назначение привелегий",
        TEXT_ADDGROUP_NAME=>"Группа",
        TEXT_ADDGROUP=>"Добавить группу",
        ERROR_ADDGROUP_NAME=>"Введите название группы",
        
        TEXT_EDITGROUP=>"Редактировать группу",
        TEXT_EDITGROUP_NAME=>"Группа",
        ERROR_EDITGROUP_NAME=>"Введите название группы",
        ERROR_EDITGROUP_ID=>"Неизвестная группа",
        
        TEXT_ACCESS_PRIV_NAME=>"Доступ к форуму",
        TEXT_WRITE_PRIV_NAME=>"Писать в форуме",
        TEXT_MODERATE_PRIV_NAME=>"Модерация форума",
        
        TEXT_SETPRIVILEGES=>"Установить права",
        
        TEXT_PROFILE_CHANGE_PASSWORD_AND_EMAIL=>"Сменить пароль или Email",
        TEXT_PROFILE_CURRENT_PASSWORD=>"Текущий пароль",
        TEXT_PROFILE_NEW_PASSWORD=>"Новый пароль",
        TEXT_PROFILE_RETYPE_PASSWORD=>"Подтверждение пароля",
        TEXT_PROFILE_EMAIL=>"Email",
        TEXT_PROFILE_CHANGE=>"Сохранить",  
        TEXT_PROFILE_CHANGE_AVATAR=>"Изменить аватар",
        TEXT_PROFILE_DELETE_AVATAR=>"Удалить аватар",
        TEXT_PROFILE_CHANGE_OTHER=>"Другие настройки",
        TEXT_PROFILE_SIGNATURE=>"Подпись",
        TEXT_RPOFILE_CHANGE_ZONES=>"Изменить временную зону",
        TEXT_PROFILE_ZONE=>"Временная зона",
        TEXT_PROFILE_IS_SUBSCRIBE=>"Получать уведомления о новых сообщения в модерируемых разделах",
        TEXT_PROFILE_EXTEND=>"Дополнительные данные",
        TEXT_PROFILE_EXTEND_BUTTON=>"Сохранить",
        ERROR_PROFILE_PASSWORD=>"Неверный текущий пароль",      
        ERROR_PROFILE_RETYPE_PASSWORD=>"Новый пароль и подтвержденый не совпадают",
        ERROR_PROFILE_EMAIL=>"Некорректный Email",
        ERROR_PROFILE_EMAIL_DUPLICATE=>"Данный Email уже зарегестрирован в системе и принадлежит другому пользователю",
        ERROR_PROFILE_AVATAR_EMPTY=>"Не выбран файл",
        ERROR_PROFILE_AVATAR_NOT_IMAGE=>"Заливаемый файл не является изображением",
        ERROR_PROFILE_AVATAR_WRONG_UPLOAD=>"Ошибка при заливке файла",
        ERROR_PROFILE_AVATAR_PROCESS=>"Ошибка при обработке аватара",
        ERROR_PROFILE_EXTEND=>"Введите значение",
        
        ERROR_USERS_NOT_FOUND=>"Пользователи не найдены",
        
        TEXT_RECOVERYPWD_LOGIN=>"Логин",
        TEXT_RECOVERYPWD_EMAIL=>"Email",
        TEXT_RECOVERYPWD=>"Восстановить пароль",
        TEXT_RECOVERYPWD_INSTRUCTION=>"Для восстановления вашего пароль введите логин или пароль",
        TEXT_RECOVERYPWD_OKMESSAGE=>"На email указанный Вами при регистрации выслан ваш пароль",
        
        EMAIL_RECOVERYPWD_HELLO=>"Уважаемый",
        EMAIL_RECOVERYPWD_SUBJECT=>"Ваш пароль для доступа на ",
        EMAIL_RECOVERYPWD_REQUEST=>"По вашему запросу высылаем пароль для доступа к форуму",
        ERROR_RECOVERYPWD_ALL_EMPTY=>"Введите email или логин для восстановления пароля",
        ERROR_RECOVERYPWD_NORESULT=>"Нет такого пользователя",
        EMAIL_RECOVERYPWD_LOGIN=>"Логин",
        EMAIL_RECOVERYPWD_PASSWORD=>"Пароль",
        EMAIL_RECOVERYPWD_REGARDS=>"С наилучшими пожеланиями, администрация форума.",
        
        TEXT_PAGER_CONFIRM_DELETE=>"Вы действительно хотите удалить сообщение",
        TEXT_PAGER_DELETE=>"Удалить",
        TEXT_PAGER_IN=>"Входящие",
        TEXT_PAGER_OUT=>"Исходящие",
        TEXT_PAGER_ADD=>"Отослать",
        TEXT_PAGER_EMAIL_SUBJECT=>"Уведомление о личном сообщение",
        TEXT_PAGER_EMAIL_HELLO=>"Здраствуйте",
        TEXT_PAGER_EMAIL_TEXT=>"Вам пришло новое личное сообщение",
        TEXT_PAGER_EMAIL_SEE=>"Вы можете ответить это сообщение, перейдя по следующей ссылке",
        TEXT_PAGER_EMAIL_FROM=>"От кого",
        TEXT_PAGER_EMAIL_MESSAGE=>"Сообщение",
        TEXT_PAGER_HEADER=>"Заголовок",
        TEXT_PAGER_MESSAGE=>"Сообщение",
        TEXT_PAGER_NO_THEME=>"Без темы",
        TEXT_PAGER=>"Пейджер",
        
        TEXT_REG_EMAIL=>"Email",
        TEXT_REG_LOGIN=>"Логин",
        TEXT_REG_PASSWORD=>"Пароль",
        TEXT_REG_RETYPE_PASSWORD=>"Подтвердите пароль",
        TEXT_REG=>"Регистрироваться",
        TEXT_REG_ALL_FIELDS_REQUERED=>"Все поля обязательны для заполнения",
        TEXT_REG_ERROR_EMPTY_EMAIL=>"Введите email",
        TEXT_REG_ERROR_NOT_VALID_EMAIL=>"Некорректный email",
        TEXT_REG_ERROR_NOT_UNIQUE_EMAIL=>"Такой email уже принадлежит другому пользователю",
        TEXT_REG_ERROR_EMPTY_LOGIN=>"Введите логин",
        TEXT_REG_ERROR_NOT_UNIQUE_LOGIN=>"Такой логин уже принадлежит другому пользователю",
        TEXT_REG_ERROR_EMPTY_PASSWORD=>"Введите пароль",
        TEXT_REG_ERROR_NOT_EQUALE_PASSWORD=>"Пароли не совпадаюты",
        TEXT_REG_OK=>"Регистрация прошла успешно",
        
        TEXT_POLL_VOTE=>"Голосовать",
        
        TEXT_SEARCH_HEADER=>"Поиск",
        TEXT_SEARCH_BUTTON=>"Искать",
        TEXT_SEARCH_ONLY_IN_THEME=>"Искать только в названиях тем",
        TEXT_SEARCH_ALLWORDS=>"Искать все слова",
        TEXT_SEARCH_IN_DAY=>"Искать за последние дни",
        
        TEXT_SEARCH_ALL=>"За все время",
        TEXT_SEARCH_TODAY=>"За сегодня",
        TEXT_SEARCH_LAST_3_DAYS=>"Последние 3 дня",
        TEXT_SEARCH_LAST_WEEK=>"Последняя неделя",
        TEXT_SEARCH_LAST_2_WEEKS=>"Последние 2 недели",
        TEXT_SEARCH_LAST_MONTH=>"За последний месяц",
        
        TEXT_SEARCH_ALL_FORUMS=>"Искать везде",
        TEXT_SEARCH_SELECTFORUM=>"Выберите темы для форума",
        TEXT_SEARCH_RESULT=>"Результаты поиска по запросу",
        
        TEXT_SEARCH_NOT_FOUND=>"Поиск не дал результатов",
        TEXT_UNEXISTS_SEARCH_SESSION=>"Неизвестная или устаревшая поисковая сессия",

        
        TEXT_FILE_SIZE=>"Размер файла",
        TEXT_DOWNLOAD=>"Скачать",
        TEXT_SIZE_UNITS_BYTE=>"байт",
        TEXT_SIZE_UNITS_KILO=>"Кб",
        TEXT_SIZE_UNITS_MEGA=>"Мб",
        TEXT_SIZE_UNITS_GIGA=>"Гб",
        TEXT_SIZE_UNITS_TERA=>"Тб",
        
        TEXT_USER_BAN=>"Бан",
        TEXT_USER_TOBAN=>"Забанить",
        TEXT_USER_USER=>"Пользователь",
        TEXT_USER_MODERATOR=>"Модератор",
        
        TEXT_USER_GROUPS_LIST=>"Список груп пользователей",
        TEXT_ADD_GROUP=>"Добавить",
        TEXT_DELETE_GROUP=>"Удалить",
        TEXT_AVALAIBLE_GROUPS=>"Доступные группы",
        TEXT_USER_GROUPS=>"Группы пользователя",
        TEXT_SAVE=>"Сохранить",
        TEXT_SET_USER_GROUPS=>"Назначение групп пользователю",
        
        TEXT_THEME_SUBSCRIBE_DEAR=>"Уважаемый",
        TEXT_THEME_SUBSCRIBE_SUBSCRIBED_THEME=>"только что написал в теме, на которую вы подписаны",
        TEXT_THEME_SUBSCRIBE_SUBSCRIBED_THEME_MODERATE=>"только что  написал в теме",
        TEXT_THEME_SUBSCRIBE_THEME_URL=>"Эта тема расположена по адресу",
        TEXT_THEME_SUBSCRIBE_MESSAGE_POST=>"Текст сообщения, которое было только что размещено",
        TEXT_THEME_SUBSCRIBE_UNSUBSCRIBE_THEME=>"Чтобы отписаться от этой темы, откройте ссылку:",
        TEXT_THEME_SUBSCRIBE_UNSUBSCRIBE_ALL_THEMES=>"Чтобы отписаться от ВСЕХ тем, откройте ссылку:",
        TEXT_THEME_SUBSCRIBE=>"Подписаться на тему",
        TEXT_THEME_UNSUBSCRIBE=>"Отписаться от темы",
        
        THEME_SUBSCRIBE_SUBJECT=>"Новое сообщение в теме",
        TEXT_UNSUBSCRIBE_THEME_SUCCESS=>"Вы отписались от темы",
        TEXT_UNSUBSCRIBE_ALL_THEMES_SUCCESS=>"Вы отписались от всех тем",
        TEXT_UNSUBSCRIBE_USER_ERROR=>"Вы не авторизованы",
        TEXT_UNSUBSCRIBE_THEME_ERROR=>"Не существующая тема",
        
        TEXT_BACK_TO_FORUM=>"Вернуться на форум",
        
        TEXT_CHANGE_GROUP_PRIVS=>"Назначение привелегий группе",
        TEXT_CHANGE_GROUP_PRIVS_GROUP=>"Группа",
        TEXT_CHANGER_GROUPS_PRIVS_FORUM_NAME=>"Наименование форума",
        
        TEXT_USER_PROFILE=>"Профиль пользователя",
        TEXT_USER_PROFILE_MESSAGES_COUNT=>"Количество сообщений",
        
        TEXT_LOGIN_EMAIL=>"Email",
        TEXT_LOGIN_PASSWORD=>"Пароль",
        TEXT_LOGIN_LOGIN=>"Логин",
        TEXT_FORUM_AUTH=>"Авторизация",
        
        TEXT_USER_INFO_SEND_PM=>"Отправить пользователю сообщение",
        TEXT_NOACCESS=>"Нет доступа на данную страницу",
        
        CREATE_THEME=>"Создать тему",
        
        BACK_TO_PAGER=>"Вернуться к пейджер",
        BACK_TO_USERGROUPS=>"Вернуться к списку групп",
        BACK_TO_THEMES=>"Вернуться к списку тем",
        BACK_TO_FORUMS=>"Вернуться к списку форумов",
        BACK_TO_THEME=>"Вернуться в тему",
        BACK_TO_USERSLIST=>"Вернуться к спику пользователей",
        
        FORUM_INFO=>"Информация",
        FORUM_INFO_USERS=>"Всего пользователей",
        FORUM_INFO_TOTAL=>"Всего",
        FORUM_INFO_MESSAGES_IN=>"сообщений в",
        FORUM_INFO_THEMES_IN=>"темах в",
        FORUM_INFO_FORUMS=>"разделах",
        
        FORUM_LATEST_THEMES=>"Последние темы",
        HISTORY_ROOT=>"Форум",
        
        BAN_TO_IP=>"Забанить IP",
        BAN_TO_USER=>"Забанить пользователя в этом разделе",
        BAN_TO_FORUM=>"Забанить на всем форуме",
        
        UNBANIP=>"Разбанить IP",
        BANIP=>"Забанить IP",
        BANIP_IP=>"Введите IP",
        UNBANIP_BUTTON=>"Разбанить",
        BANIP_BUTTON=>"Забанить",
        BANIP_UNBANSUCCESS=>"Разбананен IP-адресс",
        BANIP_BANSUCCESS=>"Забанен IP-адресс",
        BANIP_NOTVALID_IP=>"Введен некорректный IP",
        
        BANFORUMS=>"Баны на форумах",
        BANFORUMS_UNBAN=>"Снять бан",
        BANFORUMS_LIST=>"Список разделов",
        BANFORUMS_LOGIN=>"Логин",
        BANFORUMS_EMAIL=>"Email",
        BANFORUMS_USERINFO=>"Данные пользователя",
        
        EDITUSERSIGNATURE=>"Редактировать подпись",
        EDITUSERSIGNATURE_SIGNATURE=>"Подпись",
        EDITUSERSIGNATURE_BUTTON=>"Редактировать",
        
        COMPLAIN_TO_MESSAGE=>"Пожаловаться на сообщение",
        
        ENTERLOGIN=>"Введите логин",
        ENTERLOGIN_LOGIN=>"Логин",
        ENTERLOGIN_BUTTON=>"Сохранить",
        ENTERLOGIN_ERROR_EMPTY_LOGIN=>"Введите логин",
        ENTERLOGIN_ERROR_IS_DUPLICATE=>"Такой логин уже зарегистрирован",
        
        COMPLAIN_MESSAGE_EMAIL_SUBJECT=>"Жалоба на сообщение",
        COMPLAIN_MESSAGE_EMAIL_FROM_USER=>"От пользователя",
        COMPLAIN_MESSAGE_EMAIL_COMPLAIN_TO=>"поступила жалоба на сообщение №",
        
        FORUM_USERS_STATUS_1=>"Молчун",
        FORUM_USERS_STATUS_2=>"Новичок",
        FORUM_USERS_STATUS_3=>"Прижившийся",
        FORUM_USERS_STATUS_4=>"Опытный",
        FORUM_USERS_STATUS_5=>"Старожил",
        FORUM_USERS_STATUS_6=>"Древний",
        FORUM_USERS_STATUS_7=>"Ваще Дед",
        FORUM_USERS_STATUS_8=>"Столько не живут",
        FORUM_USERS_STATUS_9=>"Человек, у которого много свободного времени",
        FORUM_USERS_STATUS_10=>"Человек, у которого очень много свободного времени",
        FORUM_USERS_STATUS_11=>"Овощ",
        
        USER_STATUS=>"Статус",
        USER_MESSAGES_CNT=>"Сообщений",
        
        MAILERTOGROUP=>"Написать сообщения группам",
        MAILERTOGROUP_NOGROUP=>"Нет групп",
        MAILERTOGROUP_MESSAGE=>"Сообщений",
        MAILERTOGROUP_BUTTON=>"Отослать",
        MAILERTOGROUP_MAIL_SUBJECT=>"Рассылка",
        MAILERTOGROUP_ERROR_EMPTY_MESSAGE=>"Введите сообщение",
        MAILERTOGROUP_ERROR_NOGROUPS=>"Выберите группу",
        
        EDITSUBSCRIBE_DELETE=>"Отписать от темы",
        EDITSUBSCRIBE=>"Редактировать подписку на темы",
        
        THEMETOEMAIL=>"Отправить обсуждение на email",
        THEMETOEMAIL_EMAIL=>"Email",
        THEMETOEMAIL_EMAIL_SUBJECT=>"От <username> - cсылка на тему в форуме <forum>",
        THEMETOEMAIL_EMAIL_USERNAME=>"Пользователь",
        THEMETOEMAIL_EMAIL_SEND_LINK=>"отправил вам ссылку на тему",
        THEMETOEMAIL_EMAIL_IN_FORUM=>"в форуме",
        THEMETOEMAIL_SUCCESS=>"Email отправлен",
        PRINTTHEME=>"Версия для печати",
        
        NEWMESSAGES=>"Новые сообщения",
        
        ACTIVETHEMES=>"Активные темы",
        ACTIVETHEMES_DAYCOUNT=>"Выберите количество дней",
        ACTIVETHEMES_BUTTON=>"Выбрать",
        
        ACTIVEUSERS=>"Активные пользователи",
        ACTIVEUSERS_DAYCOUNT=>"Выберите количество дней",
        ACTIVEUSERS_BUTTON=>"Выбрать",
        
        ADDFILES=>"Добавление файлов",
        ADDFILES_MAX_FILES_COUNT=>"Максимальное количество файлов",
        ADDFILES_MAX_FILE_SIZE=>"Максимальный размер файла",
        ADDFILES_MAX_TOTAL_FILES_SIZE=>"Максимальный суммарный размер файлов",
        ADDFILES_ANONYOUS_DENIED=>"Анонимным пользователям заливка фалйов запрещена",
        ADDFILES_MOREFILES_DENIED=>"Нельзя больше добавить файлов",
        ADDFILES_BUTTON=>"Загрузить",
        ADDFILES_GOTO_MESSAGE=>"Перейти к сообщению",
        
        PREVIEW_MESSAGE=>"Предпросмотр сообщения",
        USER_ONLINE => "Online",
        USER_OFFLINE => "Offline",
        DOCITE => "Цитировать",
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