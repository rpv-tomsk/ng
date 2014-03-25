package NG::Adminside::Auth;
use strict;

#TODO: log Events !

use NGService;
use POSIX qw(strftime);

use constant COOKIENAME => "ng_session";
use constant C_AUTH_NOCOOKIE => 0;
use constant C_AUTH_OK       => 1;
use constant C_AUTH_EXPIRES  => 2;
use constant C_AUTH_WRONGLOGIN=>4;
use constant C_AUTH_WRONGIP  => 8;
use constant C_SESSION_EXPIRES => 3600;
use constant C_SESSION_UPDATE  => 60;

sub new {
    my $class = shift;
    my $self = {};
    bless $self, $class;
    $self->init(@_) or return undef;
    return $self; 
};

sub init {
    my $self = shift;
    $self->{_auth_status} = undef;
    $self->{_admin} = undef;
    $self;
};

sub Authenticate {
    my $self = shift;
    my $is_ajax = shift || 0;
    
    my $q = $self->q();
    my $dbh = $self->dbh();
    my $cookievalue = $q->cookie(-name=>COOKIENAME) || "";
    
    $self->{_auth_status} = C_AUTH_NOCOOKIE;
    while (1) {
        last unless $cookievalue;
        
        my $sth = $dbh->prepare("select id,login,fio,last_online,last_ip,sessionkey,level,group_id from ng_admins where sessionkey=?") or die $DBI::errstr;
        $sth->execute($cookievalue) or die $DBI::errstr;
        my $admin = $sth->fetchrow_hashref();
        $sth->finish();
        
        if (!defined $admin) {
            $self->{_auth_status} = C_AUTH_NOCOOKIE;
            last;
        };
        if ($admin->{last_ip} ne $q->remote_host()) {
            $self->{_auth_status} = C_AUTH_WRONGIP;
            last;
        };
        my $time = time();
        if ($time-$admin->{last_online} > C_SESSION_EXPIRES) {
            $self->{_auth_status} = C_AUTH_EXPIRES;
            last;
        };
        if ($time-$admin->{last_online} > C_SESSION_UPDATE) {
            $dbh->do("update ng_admins set last_online=? where id = ?",undef,$time,$admin->{id});
        };
        $self->{_admin} = $admin;
        $self->{_auth_status} = C_AUTH_OK;
        last;
    };
    my $url = $q->url(-absolute=>1);
    if ( $url =~ /^\/admin-side\/auth\/([^\/\s]*\/)?/ ) {
        my $subUrl = $1;
        #������������ ��� ����.
        return $self->showPopupLoginForm("������ ��������") if $q->param('showpopup');
        return $self->Logout() if $subUrl eq  "logout/";
        return $self->editAdmin() if $subUrl eq "editadmin/";
        return $self->cms()->notFound() if $subUrl;
        return $self->AuthenticateByLogin($is_ajax);
    };
    #Check if user authenticated
    return $self->showLoginForm($is_ajax) if ($self->{_auth_status} != C_AUTH_OK);
    $self->doObvyazka() unless $is_ajax;
    return NG::Application::M_CONTINUE;
};


sub doObvyazka {
    my $self = shift;
    
    my $c = '<div id="history_left">';
    $c.= '<strong>�������������:</strong><a href="/admin-side/auth/editadmin/" onclick="win = window.open(this.href,"","width=500,height=200,top=100,left=100");return false;" target="_blank">';
    $c.= $self->{_admin}->{fio};
    $c.= '</a></div>';
    
    $self->cms->pushRegion({CONTENT=>$c,REGION=>"HEAD1",WEIGHT=>-100});

    $c = '<div style="float:left;">';
    $c.= '<a href="/admin-side/auth/logout/" onMouseOut="MM_swapImgRestore()" onMouseOver="MM_swapImage("Image3","","/admin-side/img/img_top2_act.gif",1);">';
    $c.= '<img  src="/admin-side/img/img_top2_inact.gif" name="Image3" alt="" width="74" height="43" border="0"></a>';
    $c.= '</div>';
    $self->cms->pushRegion({CONTENT=>$c,REGION=>"HEAD1",WEIGHT=>100});
};

sub showLoginForm {
    my $self = shift;
    my $is_ajax = shift;
    
    my $cms = $self->cms();
    my $q = $self->q();
    
    if ($is_ajax) {
        return $cms->output(
            "<script>"
            ."var win = window.parent?window.parent:window;"
            ."win.open('/admin-side/auth/?showpopup=1','','height=200,width=400,top=200,left=200');"
            ."</script>"
        );
    };
    
    my $url = undef;
    if ( $q->request_method() eq "POST" ) {
        $url = $q->param('url');
    }
    else {
        $url = $q->url(-full=>1, -query=>1);
    };
    
    my $tmpl = $cms->gettemplate("admin-side/common/loginform.tmpl") || return $self->showError();
    #TODO: �������� ��������� 
    $tmpl->param(
        MESSAGE =>  $self->_statusText(),
        IS_AJAX =>  0,
        URL     =>  $url,
        LOGIN   =>  $q->param('ng_login') || "",
        TITLE   =>  $cms->confParam('CMS.SiteName','����')." :: �����������",
    );
    return $cms->output($tmpl,-nocache=>1);
};

sub showPopupLoginForm {
    my $self = shift;
    my $message = shift || "";
    
    my $cms = $self->cms();
    my $q = $self->q();
    my $login = $q->param('ng_login') || "";
    
    my $tmpl = $cms->gettemplate("admin-side/common/popuploginform.tmpl") || return $self->showError();
    $tmpl->param(
        MESSAGE=>$message,
        IS_AJAX=>1,
        LOGIN=>$login,
        TITLE=> $self->confParam('CMS.SiteName','����')." :: �����������",
    );
    return $cms->output($tmpl,-nocache=>1);
};

sub AuthenticateByLogin {
    my $self = shift;
    my $is_ajax = shift;
    
    my $q = $self->q();
    my $dbh = $self->dbh();
    my $cms = $self->cms();
    
    while (1) {
        last unless $q->request_method() eq "POST";
        my $login    = $q->param('ng_login') || "";
        my $password = $q->param('ng_password') || "";
        
        $self->{_auth_status} = C_AUTH_WRONGLOGIN;
        last unless $login && $password;
            
        my $sth = $dbh->prepare("select id,login,fio,last_online,sessionkey from ng_admins where login=? and password=?") or die $DBI::errstr;
        $sth->execute($login,$password) or die $DBI::errstr;
        my $admin = $sth->fetchrow_hashref() or return;
        $sth->finish();
    
        #if ($admin->{sessionkey}) {
        #    $self->_makeLogEvent($self,{operation=>"����� �� �������",log_time=>strftime("%d.%m.%Y %T",localtime($admin->{last_online})),module_name=>"�������"});
        #};
        $admin->{sessionkey} = generate_session_id();
        $admin->{last_online} = time();
        $dbh->do("update ng_admins set sessionkey=?,last_online=?,last_ip=? where id=?",undef,$admin->{sessionkey},$admin->{last_online},$q->remote_host(),$admin->{id}) or die $DBI::errstr;
        $cms->addCookie(-name=>COOKIENAME,-value=>$admin->{sessionkey},-domain=>$q->virtual_host(),-path=>'/admin-side/');
        $self->{_auth_status} = C_AUTH_OK;
        #$self->_makeLogEvent($self,{operation=>"���� � �������",module_name=>"�������"});
        $self->{_admin} = $admin;
        
        if ($is_ajax) {
            return $cms->output("<script type='text/javascript'>window.close();</script>",-nocache=>1);
        }
        else {
            my $url = $q->param('url')?$q->param('url'):"/admin-side/";
            return $cms->redirect($url); ## TODO: redirect to url from form
        };
        last;  #Not Reachable
    };
    return $self->showLoginForm($is_ajax);
};

sub Logout {
    my $self = shift;
    my $cms = $self->cms();
    my $dbh = $cms->dbh();
    my $q = $cms->q();
    my $cookievalue = $q->cookie(-name=>COOKIENAME) || "";
    
    if ($cookievalue) {
        my $sth = $dbh->prepare("update ng_admins set sessionkey='' where sessionkey=?") or die $DBI::errstr;
        $sth->execute($cookievalue) or die $DBI::errstr;
        $sth->finish();
    };
    
    $cms->addCookie(
        -name=>COOKIENAME,
        -value=>"",
        -domain=>$q->virtual_host(),
        -expires=>'-1d',
        -path=>'/admin-side/',
    );
    #$self->_makeLogEvent($self,{operation=>"����� �� �������",module_name=>"�������"});
    return $cms->redirect("/admin-side/");
}


sub _statusText {
    my $self = shift;
    my $status = $self->{_auth_status};
    return "�� ������������." if ($status == C_AUTH_OK);
    return "������ ��������." if ($status == C_AUTH_EXPIRES);
    return "" if ($status == C_AUTH_NOCOOKIE)||($status == C_AUTH_WRONGIP);
    return "��� ������������ ��� ������ �������." if ($status == C_AUTH_WRONGLOGIN);
};

sub editAdmin {
    my $self = shift;
    
    my $cms = $self->cms();
    my $dbh = $cms->dbh();
    my $q = $cms->q();
    
    my $ref = $q->param("ref") || $q->url(-absolute=>1);
    my $is_ajax = $q->param("_ajax");
    
    my $admin = $self->{_admin} or return $self->showError("�� ������������.");
    
    my $action = $q->url_param("action") || "";
    my $form = $self->getObject("NG::Form",
        FORM_URL  => $self->q()->url()."?action=editadmin",
        KEY_FIELD => "id",
        DB        => $self->db(),
        TABLE     => "ng_admins",
        DOCROOT   => $self->{_docroot},
        CGIObject => $q,
        REF       => $ref,
    );

    $form->setTitle('������ �������������� '.$admin->{fio}." (".$admin->{login}.")");

    if ($admin->{level} == 0) {
        $form->addfields([
            {FIELD=>"id",NAME=>"id",TYPE=>"id",VALUE=>$admin->{id}},
            {FIELD=>"fio",NAME=>"���",TYPE=>"text",IS_NOTNULL=>1},
        ]);
    } else {
        $form->addfields(
            {FIELD=>"id",NAME=>"",TYPE=>"id",VALUE=>$admin->{id}},
        );
    };
    
    if ($action eq "editadmin") {
        $form->addfields([
            {FIELD=>'password', TYPE=>'password',NAME=>'������', },
            {FIELD=>'password_repeat', TYPE=>'password',NAME=>'����������� ������', },
        ]);
        $form->setFormValues();
        $form->StandartCheck();
        
        if (is_empty($form->getParam("password")) && is_empty($form->getParam("password_repeat"))) {
            $form->deletefield("password");
        }
        else {
            $form->pusherror("password","��������� ������ �� ���������") if ($form->getParam("password") ne $form->getParam("password_repeat"));
        };
        
        if (!$form->has_err_msgs()) {
            $form->deletefield("password_repeat");
            $form->updateData();
            if ($is_ajax == 1) {
                return $self->output("<script type='text/javascript'>parent.document.location='".$q->url()."?ok=1"."';</script>", -nocache=>1);
            }
            else {
                return $self->redirect($q->url()."?ok=1");
            };
        } else {
            if ($is_ajax) {
                return $self->output(
                    "<script type='text/javascript'>parent.document.getElementById('updated').innerHTML='';</script>"
                    .$form->ajax_showerrors(),
                    -nocache=>1,
                );
            };
        };
    } else {
        $form->loadData() or return $self->error($form->getError());
        $form->addfields([
            {FIELD=>'password', TYPE=>'password',NAME=>'������',},
            {FIELD=>'password_repeat', TYPE=>'password',NAME=>'����������� ������', },
        ]);
    };

    my $tmpl = $self->gettemplate("admin-side/common/universalform.tmpl");
    $form->print($tmpl);
    my $formhtml = $tmpl->output();
    
    $tmpl = $self->gettemplate("admin-side/admin/adminedit.tmpl");
    my $updated = 0;
    $updated = 1 if $q->param("ok") && $q->param("ok")==1;
    $tmpl->param(
        FORM=>$formhtml,
        UPDATED=> $updated,
    );
    return $self->output($tmpl);
};


#XXX NEED TO REVIEW METHODS BELOW

sub getAdminId {
    my $self = shift;
    die "getAdminId(): variable '_admin' not initialised" unless exists $self->{_admin};
    return $self->{_admin}->{id};
};

1;
