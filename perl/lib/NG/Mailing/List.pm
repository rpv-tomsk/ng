package NG::Mailing::List;
use strict;
use NGService;
use NSecure;
use NG::Module::List;
our @ISA = qw(NG::Module::List);

use NG::Mailing;

our %messages = (
    notfound => "�������� �� �������",
    enqueued => "�������� ������� ���������� � �������",
    canceled => "�������� ��������",
    failed   => "���������� ��������� ��������",
    unpaused => "�������� �������� ���������� � �������",
    paused   => "�������� ��������������",
);

my $actions = {
    send    => {name=>'���������'},
    pause   => {name=>'�������������'},
    unpause => {name=>'�����������'},
    cancel  => {name=>'��������'},
    retry0  => {name=>'���������'},
};

our %status = (
    1 => { name=> '�����',           color => 'green',  actions => ['send']             },
    2 => { name=> '� �������',       color => 'orange', actions => ['pause','cancel']   },
    3 => { name=> '�����������',     color => 'blue',   actions => ['pause','cancel']   },
    4 => { name=> '��������������',  color => 'purple', actions => ['unpause','cancel'] },
    5 => { name=> '������',          color => 'red',    actions => []                   },
    6 => { name=> '��� �����������', color => 'red',    actions => ['retry0']           },
    7 => { name=> '��������',        color => 'gray',   actions => []                   },
    8 => { name=> '���������',       color => 'green',  actions => []                   },
);


sub config {
    my $self = shift;
    my $cms  = $self->cms();
    my $q    = $self->q();
    my $status = $q->param("status") || "";
    
    $self->{_table} = "ng_mailing";
    $self->{_recordname} = "��������";
    
    $self->{BEFORE_LIST_TMPL} = "/admin-side/title.tmpl";
    $self->{BEFORE_LIST_DATA} = $messages{$status};
    
    $self->fields(
        {FIELD => 'id',        TYPE => 'id',   NAME => 'ID'},
        {FIELD => 'date_add',  TYPE => 'date', NAME => '����',      IS_NOTNULL => 1},
        {FIELD => 'subject',   TYPE => 'text', NAME => '���������', IS_NOTNULL => 1},
        {FIELD => 'plain_content', TYPE => 'textarea',  NAME => '��������� �������', IS_NOTNULL => 0, },
        {FIELD => 'html_content', TYPE => 'rtf',    NAME => '�����',     IS_NOTNULL => 0,
            OPTIONS => {
                IMG_TABLE     => "ng_mailing_rtf_images",
                IMG_UPLOADDIR => $cms->confParam("Mailer.uploadDir"),
                IMG_TABLE_FIELDS_MAP => {id => "parent_id"},
                CONFIG => "rtfConfig",
            }
        },
        {FIELD => "lettersize",   TYPE => "text", NAME => "������ ������",   IS_NOTNULL => 0},
        {FIELD => "status", TYPE => "text", NAME => "������",   IS_NOTNULL => 0},
        {FIELD => "action", TYPE => "text", NAME => "��������", IS_FAKEFIELD => 1},
    );
    
    $self->listfields([
        {FIELD => "id"},
        {FIELD => "date_add"},
        {FIELD => "subject"},
        {FIELD => "lettersize"},
        {FIELD => "status"},
        {FIELD => "action"},
    ]);
    
    $self->formfields(
        {FIELD => 'id'},
        {FIELD => 'date_add'},
        {FIELD => 'subject'},
        {FIELD => 'html_content'},
        {FIELD => 'plain_content'},
    );
    
    $self->multiactions(
        $NG::Module::List::MULTIACTION_DELETE,
    );
    
    $self->order({DEFAULT=>"DESC", DEFAULTBY=>"DESC", FIELD=>"date_add", ORDER_DESC=>"date_add desc, id desc", ORDER_ASC=>"date_add asc,id asc",}); 
    
    $self->register_action("mailingaction", "mailingAction");
    $self->register_action("testdelivery",  "testDelivery");
    
    $self->{_rowClass} = 'NG::Mailing::List::Row';
}

sub getListSQLFields{
    my $self = shift;
    return $self->SUPER::getListSQLFields(@_) . ",date_add,send_after,date_begin,date_end,progress,total, send_after > now() as in_future";
}

sub rowFunction{
    my $self = shift;
    my $row = shift;
    
    $row->{'_lettersize'} = $row->{'lettersize'};
    $row->{'lettersize'} = get_size_text($row->{'lettersize'});
    
    my $mailingType = $self->dbh->selectrow_hashref("SELECT type_id, lettersize_limit FROM ng_mailing_types WHERE type_id = (SELECT type FROM mailing m WHERE m.id = ?)",undef,$row->{id});
    
    my $overLimit = 0;
    if ($mailingType->{lettersize_limit} && $row->{'_lettersize'} > $mailingType->{lettersize_limit}) {
        $overLimit = 1;
        $row->{'lettersize'} = '<span style="color:red;">'.$row->{'lettersize'}.'</span> > '.get_size_text($mailingType->{lettersize_limit}) if $row->{'lettersize'};
    };
    
    my $statusId = $row->{status};
    $row->{_status} = $row->{status};
    my $dstatus  = $status{$statusId};
    
    return unless $dstatus; #���������� ������..

    my $actionsA = $dstatus->{actions} || [];
    my $actionHTML = "";
    foreach my $act (@$actionsA) {
        next if $act eq 'send' && $overLimit;
        $actionHTML .= '<div style="margin-top:3px;"><a href="?action=mailingAction&mailingAction='.$act.'&id=' . $row->{id} . '"><small>' . $actions->{$act}->{name} . '</small></a></div>'
    };

    my $statusInfo = " ";
    if ($statusId == 2) { # � �������
        if ($row->{total}) {
            $statusInfo .= "�����������: ". $row->{total};
        };
        if ($row->{send_after} ne $row->{date_add} && $row->{in_future}) {
            $statusInfo .= "<br>";
            my $after = $self->db->datetime_from_db($row->{send_after});
            $after =~ s/\:\d+$//;
            $statusInfo .= " �������� ����� $after";
        };
    }
    elsif ($statusId == 3 || $statusId == 4) { # 3 - ����������� / 4 - ��������������
        if ($row->{date_begin}) {
            my $begin = $self->db->datetime_from_db($row->{date_begin});
            $begin =~ s/\:\d+$//;
            $statusInfo .= "������: $begin<br>";
            $statusInfo .= "[".$row->{progress}." �� ".$row->{total}." - ". sprintf("%.2f", 100 * $row->{progress} / $row->{total}) . "%]" if $row->{total};
        };
    }
    elsif ($statusId == 7) {
        $statusInfo .= "[".$row->{progress}." �� ".$row->{total}." - ". sprintf("%.2f", 100 * $row->{progress} / $row->{total}) . "%]"  if $row->{progress} && $row->{total};
    }
    elsif ($statusId == 8) {
        $statusInfo = "�����������: ". $row->{total};
    };
    
    $statusInfo = "<br><small>$statusInfo</small>" if $statusInfo;
    $row->{action} = $actionHTML;
    $row->{status} = '<span style="white-space:nowrap;font-size:11px;color:'.$dstatus->{color}.'">' . $dstatus->{name}. '</span>'.$statusInfo;
}

sub mailingAction {
    my ($self,$action,$ajax) = @_;
    
    my $cms = $self->cms();
    my $q   = $cms->q();
    my $url = $q->url(-absolute => 1);
    
    my $id = int($q->param("id") || 0);
    my $ma = $q->param('mailingAction') || '';

    my $mailing = NG::Mailing::Mailing->load($id);
    return $cms->redirect($url . "?status=notfound") unless $mailing;
    
    my $oldStatus = $mailing->status();
    
    if ($ma eq 'send') {
        $mailing->start();
    }
    elsif ($ma eq 'pause') {
        $mailing->pause();
    }
    elsif ($ma eq 'unpause') {
        $mailing->unpause();
    }
    elsif ($ma eq 'cancel') {
        $mailing->cancel();
    }
    elsif ($ma eq 'retry0') {
        $mailing->retry0();
    };
    
    my $newStatus = $mailing->status();
    
    my $res = 'failed';
    if ($oldStatus == $newStatus) {
        #Noop, action failed
    }
    elsif ($oldStatus == 4) {
        $res = 'unpaused';
    }
    elsif ($newStatus == 2) {
        $res = 'enqueued';
    }
    elsif ($newStatus == 3) {
        $res = 'enqueued'; # ???
    }
    elsif ($newStatus == 4) {
        $res = 'paused';
    }
    elsif ($newStatus == 7) {
        $res = 'canceled';
    };
    
    return $cms->redirect($url . "?status=" . $res);
};


sub checkBeforeDelete {
    my ($list,$id) = (shift,shift);
    
    my $dbh = $list->dbh();
    
    my $mailing = $dbh->selectrow_hashref("select id,status from ng_mailing where id = ?", undef, $id);
    return $list->error("�������� �� �������") unless $mailing;
    return $list->error("�������� ��������� � �������  ��������! �������� ����������.") if $mailing->{status} == 2;
    return $list->error("�������� ��������� � �������� ��������! �������� ����������.") if $mailing->{status} == 3;
    
    return NG::Block::M_OK;
};

sub beforeDelete {
    my ($list,$id) = (shift,shift);
    
    $list->dbh()->do("DELETE FROM mailing_recipients WHERE mailing_id = ?", undef, $id);
    
    return NG::Block::M_OK;
};

sub afterInsertUpdate {
    my ($list,$form,$fa) = (shift,shift,shift);
    
    my $cms = $list->cms();
    my $id = $form->getValue('id');
    
    my $mailing = NG::Mailing::Mailing->load($id);
    return $cms->error('Unable to load Mailing') unless $mailing;
    
    $mailing->updateLetterSize();
    return 1;
};

sub testDelivery {
    my ($self,$action,$is_ajax) = (shift,shift,shift);
    
    my $cms   = $self->cms();
    my $dbh   = $self->dbh();
    my $q     = $self->q();
    my $myurl  = $q->url();
    my $method = $q->request_method();
    
    my $ref    = $q->param('ref') || ""; #TODO: �������� �� �������
    
    my $id = $q->param('id') || 0;
    return $self->error('�� ������ ��� ��������') unless is_valid_id($id);
    
    my $rcpt = $q->param('recipients');
    
    my $errorMsg = "";
    if ($method eq "POST") {
        while (1) {
            unless ($rcpt) {
                $errorMsg = "�� ������� ����������";
                last;
            };
            $rcpt =~ s/\s+$//;
            $rcpt =~ s/^\s+//;
            
            my @lines = split /\r?\n/, $rcpt;
            my @rcpt;
            foreach (@lines) {
                $_ =~ s/\s+$//;
                $_ =~ s/^\s+//;
                next unless $_;
                unless (is_valid_email($_)) {
                    $errorMsg = "�������� E-Mail";
                    last;
                };
                push @rcpt, $_;
            };
            
            #���������� ���������, ������ �������� ��������
            my $mailing = NG::Mailing::Mailing->load($id);
            unless ($mailing) {
                $errorMsg = 'Unable to load Mailing';
                last;
            };
            $mailing->testDeilver(\@rcpt);
            
            # ������ ���������� �������� � �������
            if ($is_ajax) {
                #TODO: ����������� �������� ��������� ref
                #return $self->output("<script type='text/javascript'>parent.ajax_url('$myurl?action=showanswers&poll_id=$poll_id&_ajax=1','formb_$poll_id');</script>");
                return $self->output("<script type='text/javascript'>alert('�������� ��������� ����������!');parent.clear_block('formb_$id');</script>");
            }
            else {
                #return $self->redirect("$myurl?action=showanswers&poll_id=$poll_id&ref=".uri_escape($ref));
                return $self->redirect($ref);
            };
            
            last;
        };
        
        if ($is_ajax) {
            return $self->output("<script type='text/javascript'>parent.ge('error_testdelivery_$id').innerHTML='$errorMsg';</script>");
        };
    };
    
    $self->opentemplate("admin-side/common/mailing/testdeliveryform.tmpl") || return $self->showError();
    my $tmpl = $self->template();
    $tmpl->param(
        MAILING_ID => $id,
        ERRORMSG   => $errorMsg,
        RCPT       => $rcpt,
        IS_AJAX    => $is_ajax,
        URL        => $myurl,
        REF        => $ref,
    );
    return $self->output($tmpl->output());
};

package NG::Mailing::List::Row;
use strict;
use base qw(NG::Module::List::Row);


sub buildLinks {
    my $self = shift;
    my $deletelink = $self->list()->getDeleteLink();
    my $extralinks = $self->list()->getExtraLinks();
    
    my $status = $self->getParam('_status');
    
    return if $status == 2; #� �������
    return if $status == 3; #�����������
    
    $self->pushLink({NAME => "��������� ��������",  URL => '?action=testdelivery&id={id}', AJAX=>1}) if $status == 1;
    
    foreach my $link (@{$extralinks}) {
        $self->pushLink($link);
    };
    $self->pushLink($deletelink) if ($deletelink);
};


return 1;
