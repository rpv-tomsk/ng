package NG::Module::Record;
use strict;

use NGService;
use NSecure;
use NG::Form 0.4;
use NG::Block 0.5;
use NG::Module::Record::Event;
use NHtml;

use vars qw(@ISA);
@ISA = qw(NG::Block);

$NG::Module::Record::VERSION = 0.5;



sub init {
    my $self = shift;
    $self->SUPER::init(@_);
    $self->{_formtemplate} = "admin-side/common/universalrecord.tmpl";
    $self->{_uploaddir} = "upload/pages/";
    $self->{_fields} = [];                          # ������ ����� ���� �������������� ������� ����� �������
    $self->{_table} = "";              # ��� ������� � ���������� ������
    $self->{_searchconfig} = undef;
    
    #����� ������ ������
    $self->{_pageBlockMode} = 0;
    $self->{_linkBlockMode} = 0;
    $self->{_templateBlockMode} = 0;
    $self->{_fieldsAnalysed} = 0;
    $self->{_subpageField} = undef;
    $self->{_initialised}  = undef;
    $self->{_contentKey} = undef;
    $self->{_has_pageLangId} = 0;
    
    $self->{_formStructure} = undef;
    
    $self->register_action('',"showPageBlock");
    $self->register_action('formaction',"showPageBlock");
    $self;
};

sub config {
    my $self = shift;
    die "� ������ ".(ref $self). " ����������� ���������������� ����� config()";
};

sub formStructure {
    my $self = shift;
    $self->{_formStructure} = shift;
};

sub _getForm {
    my $self = shift;
    my $is_ajax = shift;
    
    use URI::Escape;
    my $u = $self->q()->url(-query=>1); # ������� URL, ��� ����� AJAX/noAJAX, ��� �������� � �������� �������� ����� ��������
    $u =~ s/_ajax=1//; 
    
    return $self->error("������ � ������������ ������: ����������� ��� �������") unless $self->{_table};
    
    my $form = NG::Form->new(
        #FORM_URL    => $self->q()->url()."?action=update",
        FORM_URL    => $self->getBaseURL()."?action=formaction&random=".rand(),
        CGIObject   => $self->q(),
        DB          => $self->db(),
        TABLE       => $self->{_table},
        DOCROOT     => $self->getDocRoot(),
        SITEROOT    => $self->getSiteRoot(),
        REF         => $u,
    );
    $self->_analyseFieldTypes() or return $self->showError();
    $form->addfields($self->{_fields});
    $form->{_ajax} = $is_ajax;
    
    $form->setStructure($self->{_formStructure}) if $self->{_formStructure};
    
    return $form;
};

sub showPageBlock  {
    my $self = shift;
    my $action = shift;
    my $is_ajax = shift;

    my $q = $self->q();
    my $dbh  = $self->db()->dbh();
    
    my $form = $self->_getForm($is_ajax) or return $self->showError();
    my $initialised = $self->initialised();

    my $subpageField = $self->{_subpageField}; 
    
    my $url = $q->url(-absolute=>1);
    my @subpages = ();
    if ($initialised && defined $subpageField) {
        
        my $subpage = $q->param($subpageField->{FIELD});
        
        # ��������� ����� �������. ������ �������� � ��������� ����� ����� ����� �� �� �����.
        # ���� �� �� ������ �� ����� ����� ���� ���� subpage,������ ������� ���.
        my $where  = "";
        my @keys = ();
        
        foreach my $field (@{$self->{_fields}}) {
            next if ($field == $subpageField);
            if ($field->{TYPE} eq "id" || $field->{TYPE} eq "filter") {
                $where .= " ".$field->{FIELD}."=? and";
                die "Can`t find value for key field \"$field->{FIELD}\"" unless $field->{VALUE};
                push @keys,$field->{VALUE};
            };
        };
        return $self->error("������ � ������������ ������: ����������� �������� ����") unless $where;
        $where  =~ s/and$//;    
        
        #����������� ������ �������
        my $sth = $dbh->prepare("select $subpageField->{FIELD} from $self->{_table} where $where order by $subpageField->{FIELD}") or die $DBI::errstr;
        $sth->execute(@keys);
        my $found = 0;
        while (my $v = $sth->fetchrow()) {
            $subpage ||= $v;
            $found = 1 if ($v == $subpage);
            push @subpages,{
                SUBPAGE=>$v,
                URL=>$url."?".$subpageField->{FIELD}."=$v",
                AJAX_URL=>$url."?".$subpageField->{FIELD}."=$v&_ajax=1",
            };
        };
        $sth->finish();
        return $self->error("��������� ����������� �� ����������") unless $found;
        $subpageField->{VALUE} = $subpage if $subpageField;
    };
    if (!$initialised && defined $subpageField) {
        push @subpages,{
            SUBPAGE=>1,
            URL=>$url."?".$subpageField->{FIELD}."=1",
            AJAX_URL=>$url."?".$subpageField->{FIELD}."=1&_ajax=1",
        };
        $subpageField->{VALUE} = 1;
    };
    
    if ($action eq "") {
        if ($initialised) {
            $form->loadData() or return $self->error($form->getError());
        };
        $self->afterFormLoadData($form) or return $self->cms()->error();
        $self->opentemplate($self->{_formtemplate}) || return $self->showError();
        $form->print($self->tmpl());
        $self->tmpl()->param(
            SUBPAGES=>\@subpages,
            SUBPAGES_NAME=>$subpageField->{NAME},
        ) if $subpageField;
        return $self->output($self->tmpl()->output());  
    }
    elsif ($action eq "formaction") {
        my $fa = $q->param('formaction') || $q->url_param('formaction') || "";
        
        if ($fa eq "update") {
            if ($initialised) {
                $form->loadData() or return $self->error($form->getError());
            };
            $form->setFormValues();
            $self->afterSetFormValues($form) or return $self->cms()->error();
            $form->modeInsert() unless $initialised;
            $form->StandartCheck();
            $self->checkData($form,$action) or return $self->showError();
            
            if ($form->has_err_msgs()) {
                $form->cleanUploadedFiles();
                if ($is_ajax) {
                    return $self->output($form->ajax_showerrors());
                }
                else {
                    $self->opentemplate($self->{_formtemplate}) || return $self->showError();
                    $form->print($self->tmpl());
                    $self->tmpl()->param(
                        SUBPAGES=>\@subpages,
                    );                
                    return $self->output($self->tmpl()->output());
                };
            };
            
           
            
            if ($initialised) {
            
                my $ref = $q->param('ref');
                my ($u, $p) = split /\?/, $ref;
                my @params = ();
                foreach my $pair (split /&/, $p) {
                    my ($n, $v) = split /=/, $pair;
                    next if ($n eq 'rand');
                    push @params, $n.'='.$v;
                };
                push @params, 'rand='.int(rand(1000));
                $ref = $u.'?'.join('&', @params);            
            
                $self->beforeUpdate($form) or return $self->showError();
                $form->updateData() or return $self->error($form->getError());
                $self->afterUpdate($form) or return $self->showError();
                $self->_reindexContent($form) or return $self->showError();
                $self->_makeEvent("update",{});
                $self->_makeLogEvent({operation=>"���������� ����������"});
                return $self->redirect($ref);
            } else {
                $self->beforeInsert($form) or return $self->showError();
                $form->insertData() or return $self->error($form->getError());
                $self->afterInsert($form) or return $self->showError();
                $self->_reindexContent($form) or return $self->showError();
                $self->_makeEvent("insert",{});
                $self->_makeLogEvent({operation=>"���������� ����������"});
                return $self->redirectToNextNIBlock();
            };
        }
        elsif ($fa) {
            #������������ ����� �����.
            my $ret = $form->doFormAction($fa, $is_ajax);
            
            if ($is_ajax) {
                return $self->output($ret);
            }
            else {
                $ret || return $self->showError($form->getError());
            };
        }
        else {
            return $self->showError('No formaction specified for action=formaction.');
        };
    }
    else {
        return $self->showError('Invalid action. Wrong actions configuration.');
    };
};

sub searchConfig {
    my $self = shift;
    $self->{_searchconfig} = shift;
}

sub checkData {
	my $self = shift;
	my $form = shift;
    my $action = shift;
	# Method for override
    return NG::Block::M_OK;
};

# Methods for override
sub beforeInsert { my $self = shift; my $form = shift; return NG::Block::M_OK; };
sub afterInsert  { my $self = shift; my $form = shift; return NG::Block::M_OK; };
sub beforeUpdate { my $self = shift; my $form = shift; return NG::Block::M_OK; };
sub afterUpdate  { my $self = shift; my $form = shift; return NG::Block::M_OK; };
sub afterFormLoadData  { return NG::Block::M_OK; };
sub afterSetFormValues { return NG::Block::M_OK; };

sub getReference {
    my $self = shift;
    my $form = shift;
    my $q = $self->q();
    my $ref = $q->param('ref');
    
    my ($u, $p) = split /\?/, $ref;
    my @params = ();
    foreach my $pair (split /&/, $p) {
        my ($n, $v) = split /=/, $pair;
        next if ($n eq 'rand');
        push @params, $n.'='.$v;
    };
    push @params, 'rand='.int(rand(1000));
    $ref = $u.'?'.join('&', @params);
    return $ref;
};


sub _pushFields {
    my $self = shift;
    my $array = shift;

   	my $ref = $_[0]; 
	if (!defined $ref) { die "Parameter not specified in \$NG::Module::List->$array()."; }; #TODO: fix msg
    
	if (ref $ref eq 'HASH') {
		foreach my $tmp (@_) {
            push @{$self->{$array}}, $tmp;
		};
	}
	elsif (ref $ref eq 'ARRAY') {
		foreach my $tmp (@{$ref}) {
            if (ref $tmp ne "HASH") { die "Invalid type" }; #TODO: fix msg
			push @{$self->{$array}}, $tmp;
		};
	}
    else {
        die "NG::Module::List->fields(): invalid parameter type."; #TODO: fix msg
    };
};

sub fields { shift->_pushFields('_fields',@_); };

sub canEditPageBlock {
    my $self = shift;
    $self->_analyseFieldTypes() or return $self->showError();
    return $self->{_pageBlockMode};
};

sub canEditLinkBlock {
    my $self = shift;
    $self->_analyseFieldTypes() or return $self->showError();
    return $self->{_linkBlockMode};
};

sub isLangLinked {
    my $self = shift;
    $self->_analyseFieldTypes() or return $self->showError();
    return $self->{_has_pageLangId};
};

sub initPageBlock {
    my $self = shift;
    $self->_analyseFieldTypes() or return $self->showError();
    return $self->error("������ ".(ref $self)." �� ������������ ������ � ������ ������ ��������.") unless $self->{_pageBlockMode};
    return $self->_initBlock();
};

sub initLinkBlock {
    my $self = shift;
    $self->_analyseFieldTypes() or return $self->showError();
    return $self->error() unless $self->{_linkBlockMode};
    return $self->error("������ ".(ref $self)." �� ������������ ������ � ������ ������ ������ �������.") unless $self->{_linkBlockMode};
    return $self->_initBlock();
};

sub _initBlock {
    my $self = shift;
    
    my $hasNNFields = 0;
    foreach my $field (@{$self->{_fields}}) {
        next if ($field->{TYPE} eq "id" || $field->{TYPE} eq "filter");
        $field->{VALUE} = $field->{DEFAULT};
        if ($field->{IS_NOTNULL} && !$field->{DEFAULT}) {
            $hasNNFields = 1;
            last;
        };
    };
    return $self->needInitLater() if $hasNNFields;

    $self->{_subpageField}->{VALUE} = 1 if $self->{_subpageField};
    my $form = $self->_getForm(0) or return $self->showError();
    
    $form->modeInsert();
    $form->StandartCheck();
    $self->checkData($form,"update") or return $self->showError();

    if ($form->has_err_msgs()) {
        return $self->needInitLater();
    }
    $self->BeforeInsert($form) or return $self->showError();
    $form->insertData() or return $self->error($form->getError());
    $self->AfterInsert($form) or return $self->showError();
    
    return NG::Block::M_OK;
}

sub initialised {
    my $self=shift;
    
    return $self->{_initialised} if defined $self->{_initialised};
    
    $self->_analyseFieldTypes() or return $self->showError();
    
    my $where  = "";
    my @keys = ();
    
    foreach my $field (@{$self->{_fields}}) {
        next if ($self->{_subpageField} && $field == $self->{_subpageField});
        if ($field->{TYPE} eq "id" || $field->{TYPE} eq "filter") {
            $where .= " ".$field->{FIELD}."=? and";
            die "Can`t find value for key field \"$field->{FIELD}\"" unless $field->{VALUE};
            push @keys,$field->{VALUE};
        };
    };
    #return $self->error("������ � ������������ ������: ����������� �������� ����") unless $where;
    die "Configuration error: keyfields missing. Module: ".(ref $self) unless $where;
    $where  =~ s/and$//;    
    
    #����������� ������ �������
    my $sth = $self->db()->dbh()->prepare("select 1 from $self->{_table} where $where ") or die $DBI::errstr;
    $sth->execute(@keys);
    my $exists = $sth->fetchrow();
    $sth->finish();

    $self->{_initialised} = 0;
    $self->{_initialised} = 1 if defined $exists;

    return $self->{_initialised};
};


sub getPageBlockContentFilename {
    my $self = shift;
    my $pageId = $self->getPageId();
    my $blockId = $self->getBlockId();

    return $self->{_uploaddir}."page-".$pageId."_".$blockId.".html";
};

sub getPageBlockContentDir {
    my $self = shift;
    return $self->app()->{_docroot}.$self->getPageBlockContentDirWeb();
};

sub getPageBlockContentDirWeb {
    my $self = shift;
    my $pageId = $self->getPageId();
    my $blockId = $self->getBlockId;

    return "/".$self->{_uploaddir}.$pageId."_".$blockId."/";
};

sub adminBlock {
    my $self = shift;
    my $is_ajax = shift;
    return $self->run_actions($is_ajax);
};

sub pageBlockAction {
    my $self    = shift;
	my $is_ajax = shift;
    return $self->run_actions($is_ajax);
}

sub blockAction {
    my $self    = shift;
	my $is_ajax = shift;
    return $self->run_actions($is_ajax);
}


sub destroyPageBlock {
    my $self = shift;
    $self->_analyseFieldTypes() or return $self->showError();
    return $self->error("������ ".(ref $self)." �� ������������ ������ � ������ ������ ��������.") unless $self->{_pageBlockMode};
    return $self->_destroyBlock();

}

sub destroyLinkBlock {
    my $self = shift;
    $self->_analyseFieldTypes() or return $self->showError();
    return $self->error() unless $self->{_linkBlockMode};
    return $self->error("������ ".(ref $self)." �� ������������ ������ � ������ ������ ������ �������.") unless $self->{_linkBlockMode};
    return $self->_destroyBlock();
}

sub _destroyBlock {
    my $self = shift;
    my $dbh = $self->db()->dbh();
    
    my $form = $self->_getForm(0) or return $self->showError();
    
    my $subpageField = $self->{_subpageField}; 
    
    if (defined $subpageField) {
        my $where  = "";
        my @keys = ();
        foreach my $field (@{$self->{_fields}}) {
            next if ($field == $subpageField);
            if ($field->{TYPE} eq "id" || $field->{TYPE} eq "filter") {
                $where .= " ".$field->{FIELD}."=? and";
                die "Can`t find value for key field \"$field->{FIELD}\"" unless $field->{VALUE};
                push @keys,$field->{VALUE};
            };
        };
        return $self->error("������ � ������������ ������: ����������� �������� ����") unless $where;
        $where  =~ s/and$//;    
        
        #����������� ������ �������
        my $sth = $dbh->prepare("select $subpageField->{FIELD} from $self->{_table} where $where order by $subpageField->{FIELD}") or return $self->showerror($DBI::errstr);
        $sth->execute(@keys) or return $self->showerror($DBI::errstr);

        while (my $v = $sth->fetchrow()) {
            $subpageField->{VALUE} = $v;
            $form->Delete() or return $self->error($form->getError());
        };
        $sth->finish();
    }
    else {
        $form->Delete() or return $self->error($form->getError());
    };
    return NG::Block::M_OK;
};

sub getContentKey {
    my $self = shift;
    $self->_analyseFieldTypes() or return $self->showError();
    return $self->{_contentKey};
}

##����� ������ ������
sub _analyseFieldTypes {
    my $self = shift;
    
    return NG::Block::M_OK if ($self->{_fieldsAnalysed} == 1);
    $self->{_fieldsAnalysed} = 1;
    
    my ($has_pageId, $has_blockId, $has_tmplId) = (0,0,0);
    my ($has_pageLinkId,$has_pageLangId,$has_subsiteId, $has_parentPageId,$has_parentLinkId) = (0,0,0,0,0);
    
    foreach my $field (@{$self->{_fields}}) {
        if ($field->{TYPE} eq "subpage") {
            $self->{_subpageField} = $field;
            $field->{TYPE} = "id";
            next;
        };
        if ($field->{TYPE} eq "pageId") {
            $field->{VALUE} = $self->getPageId();
            $self->{_contentKey}.= $field->{TYPE}."=".$field->{VALUE};
            $field->{TYPE} = "filter";
            $has_pageId = 1;
            next;
        };
=comment
        if ($field->{TYPE} eq "blockId") {
            $field->{VALUE} = $self->getBlockId() or return $self->error("�������� ��� ���� ���� blockId �� �������, �������� ������ ������ � ������ ������ ��������.");
            $self->{_contentKey}.= $field->{TYPE}."=".$field->{VALUE};
            $field->{TYPE} = "filter";
            $has_blockId = 1;
            next;
        };
=cut
        if ($field->{TYPE} eq "pageLinkId") {
            $field->{VALUE} = $self->getPageLinkId();
            $self->{_contentKey}.= $field->{TYPE}."=".$field->{VALUE};
            $field->{TYPE} = "filter";
            $has_pageLinkId  = 1;
            next;
        };
        if ($field->{TYPE} eq "pageLangId") {
            $field->{VALUE} = $self->getPageLangId();
            $self->{_contentKey}.= $field->{TYPE}."=".$field->{VALUE};
            $field->{TYPE} = "filter";
            $has_pageLangId = 1;
            $self->{_has_pageLangId} = 1;
            next;
        };
        if ($field->{TYPE} eq "subsiteId") {
            $field->{VALUE} = $self->getSubsiteId();
            $self->{_contentKey}.= $field->{TYPE}."=".$field->{VALUE};
            $field->{TYPE} = "filter";
            $has_subsiteId = 1;
            next;
        };
        if ($field->{TYPE} eq "parentPageId") {
            $field->{VALUE} = $self->getParentPageId();
            $self->{_contentKey}.= $field->{TYPE}."=".$field->{VALUE};
            $field->{TYPE} = "filter";
            $has_parentPageId = 1;
            next;
        }
        if ($field->{TYPE} eq "parentLinkId") {
            $field->{VALUE} = $self->getParentLinkId();
            $self->{_contentKey}.= $field->{TYPE}."=".$field->{VALUE};
            $field->{TYPE} = "filter";            
            $has_parentLinkId = 1;
            next;
        };
        if ($field->{TYPE} eq "templateId") {
            #TODO: �� �� ������ ����������� ��� �������� ��� ���������� ������� ���� ���� rtf[file] ���� ����������� ����� �������
            die ("Fields with type \"templateId\" is not supported yet by NG::Module::Record.");
            #... ?
            $has_tmplId  = 1;
            next;
        };
=comment
        if ($field->{TYPE} eq "rtf" || $field->{TYPE} eq "rtffile") {
            $field->{OPTIONS} ||= {};
            my $options = $field->{OPTIONS}; 
            
            my $config = $options->{CONFIG};
            
            #TODO: �� �� ������ ����������� ��� �������� ���� ����������� ����� �������
            # �������� ������� ����� �� ������� �����
            my $dbh  = $self->db()->dbh();
            # ����� ������� ����� �� �������, ���� ��������� ��� rtf ����� � ������� �� ������ ����� ������ � ������ ������ � ������������
            
            my $blockId = $self->getBlockId();
            if ($blockId && !$config) {
                ($config) = $dbh->selectrow_array("select rtfconfig from ng_templates where id=(select template_id from ng_blocks where id=?)",undef,$blockId);
            }
            
            # ���� �� ���������� ������� �� ������� �����, �� �������� ������� ����� �� ������� ��������
            if (!$config) {
                ($config) = $dbh->selectrow_array("select rtfconfig from ng_templates where id=(select template_id from ng_sitestruct where id=?)",undef,$self->getPageId());                
            }
            $options->{CONFIG} = $config;
        };
=cut
    };
    
    #�������� ����� ������ ����� ������� �� ������� ��������, ������� ��������� ��������� ���� ��� �������� ������ ��� �������
    $self->{_pageBlockMode} = 1 if ($has_pageId || $has_parentPageId);
    $self->{_linkBlockMode} = 1 if ($has_pageLinkId || $has_pageLangId || $has_subsiteId ||  $has_parentLinkId);
    $self->{_templateBlockMode} = 1 if ($has_tmplId);

    return $self->error("������ � ������������ ������ ".(ref $self)." - ������������� ������ � ������ ����� ������� � ����� �������� ����������.")
        if (($self->{_pageBlockMode} || $self->{_linkBlockMode}) && $self->{_templateBlockMode});    # � ������, ��� ����� ��������� ���� ����� ������.
    return $self->error("������ � ������������ ������ ".(ref $self)." - ������������� pageId ��� parentPageId ��������� ������������� ����� ����������� �������.")
        if ($self->{_pageBlockMode} && $self->{_linkBlockMode});
    # ������������� ������������� subsiteId && pageLangId �� ���������, ���� � �������.
    return $self->error("������ � ������������ ������ ".(ref $self)." - ������������� subsiteId ��������� ������������� pageLinkId � parentLinkId.")
        if ($has_subsiteId && ($has_pageLinkId || $has_parentLinkId));
        
    return NG::Block::M_OK;
}

sub _reindexContent {
    my $self = shift;
    my $form = shift;
    
    my $cms = $self->cms();
    
    if (defined $self->{_searchconfig}) {
        my $suffix = $self->getIndexSuffixFromFormAndMask($form,$self->{_searchconfig}->{SUFFIXMASK});
        return $cms->showError() if ($cms->getError() ne "");
        
        my $mObj = $self->getModuleObj();
        return $self->error("moduleObj ".ref($mObj)." has no updateSearchIndex() method") unless $mObj->can("updateSearchIndex");
        return $mObj->updateSearchIndex($suffix);
    };
    1;
};

sub getBlockIndex {
    my $self = shift;
    my $suffix = shift;
    
    return $self->showError("getBlockIndexes(): ������ ������ _analyseFieldTypes()") if ($self->_analyseFieldTypes() != NG::Block::M_OK); #;-) �� ����� �������������� ���� �����.
    #return $self->error("������������ ������ ".(ref $self)." �� ��������������� ������ � ������ ����� ��������.") unless ($self->{_pageBlockMode}==1 || $self->{_linkBlockMode}==1);
    
    my $dbh = $self->db()->dbh();
    my $sc = $self->{_searchconfig} or return {};
    $sc->{SUFFIXMASK} ||= "";

    return {} unless $self->isMaskMatchSuffix($sc->{SUFFIXMASK},$suffix);
    return $self->error("��������� �������� ��������� ������� � ������������ ������") unless defined $sc->{CATEGORY};
    
    my $rFunc = undef;  #�����, �������� ������, ���� ����� �������� RFUNC.

    if (exists $sc->{CLASSES}) {
        return $self->error('C������� CLASSES � ������������ ������ �� �������� HASHREF.') if (ref($sc->{CLASSES}) ne 'HASH');
        return $self->error('_getIndexes(): ���������� �������� ������� � �������� CLASSES � ������������ ������.') unless scalar keys %{$sc->{CLASSES}};
        return $self->error('_getIndexes(): ������������� ������������� CLASSES � RFUNC � ������������ ������ �����������.') if exists $sc->{RFUNC};
        return $self->error('_getIndexes(): ��� �������� ��������� RFUNC ������������� ��������� RFUNCFIELDS ����������.') if exists $sc->{RFUNCFIELDS};
    }
    elsif (exists $sc->{RFUNC}) {
        $sc->{CLASSES} = {};
        $rFunc = $sc->{RFUNC};
        return $self->error("_getIndexes(): ����� �� �������� ������ $rFunc, ���������� � ��������� FILTER.RFUNC") unless $self->can($rFunc);
        return $self->error('_getIndexes(): � ������������ ������ ���������� �������� RFUNCFIELDS - �������� ������ ����� ��� ������� RFUNC.') unless $sc->{RFUNCFIELDS};
    }
    else {
        return $self->error('_getIndexes(): ��� �������� ��������� RFUNC ������������� ��������� RFUNCFIELDS ����������.') if exists $sc->{RFUNCFIELDS};
        if (exists $sc->{DATAINDEXFIELDS}) {
            return $self->error('������������ �������� �������� DATAINDEXFIELDS � ������������ ������') if (ref($sc->{DATAINDEXFIELDS}) ne 'ARRAY');
            $sc->{CLASSES} = {};
            foreach my $t (@{$sc->{DATAINDEXFIELDS}}) {
                return $self->error('� ������ ����� �������� DATAINDEXFIELDS ����������� ��� ����') unless $t->{FIELD};
                return $self->error('� ������ ����� �������� DATAINDEXFIELDS ����������� ��� ������') unless $t->{CLASS};
                $sc->{CLASSES}->{$t->{CLASS}} ||= [];
                push @{$sc->{CLASSES}->{$t->{CLASS}}}, {FIELD=>$t->{FIELD}};
            }
            if ($sc->{PAGEINDEXFIELDS}) {
                return $self->error('������������ �������� �������� PAGEINDEXFIELDS � ������������ ������') if (ref($sc->{PAGEINDEXFIELDS}) ne 'ARRAY');
                foreach my $t (@{$sc->{PAGEINDEXFIELDS}}) {
                    return $self->error('� ������ ����� �������� PAGEINDEXFIELDS ����������� ��� ����') unless $t->{FIELD};
                    return $self->error('� ������ ����� �������� PAGEINDEXFIELDS ����������� ��� ������') unless $t->{CLASS};
                    $sc->{CLASSES}->{$t->{CLASS}} ||= [];
                    push @{$sc->{CLASSES}->{$t->{CLASS}}}, {PFIELD=>$t->{FIELD}};
                }
            }
        }
        else {
            return $self->error('�� ������� �������� CLASSES ��� RFUNC � ������������ ������');
        }
    }

    #��������� �������� ����� �������
    my $keys = undef;
    if (defined $sc->{KEYS}) {
        $keys = $sc->{KEYS}
    }
    else {
        if ($self->{_pageBlockMode}==1) {
            $keys=[];
            push @{$keys}, "pageid";
        }
        elsif ($self->{_linkBlockMode}==1) {
            $keys=[];
            push @{$keys}, "linkid";
            push @{$keys}, "langid" if ($self->{_has_pageLangId});
        }
        else {
            #������ ����� ��������, � ������ ������ �� �������. ������� ��� �� �����.
        };
    };

    my $index = {};
    $index->{KEYS} = $keys;
    $index->{CATEGORY} = $sc->{CATEGORY};
    $index->{SUFFIX} = $suffix;

    #�������� �������� �������� ����� �� ��������
    my $keyValues = $self->getKeyValuesFromSuffixAndMask($suffix,$sc->{SUFFIXMASK});

    my $where = "";
    my $whereParam = [];

    my $fieldObjs = {};
    #��������� �������� ���� �������
    foreach my $field (@{$self->{_fields}}) {
        unless (exists $keyValues->{$field->{FIELD}}) {
            next if ($field->{TYPE} ne "filter");
            $where .= $field->{FIELD}."=? and ";
            push @{$whereParam}, $field->{VALUE};
            next;
        };
        my $v = $keyValues->{$field->{FIELD}};
        if ($field->{TYPE} eq "id") {
            $where .= $field->{FIELD}."=? and ";
            push @{$whereParam}, $v;
        }
        elsif ($field->{TYPE} eq "fkparent") {
            $where .= $field->{FIELD}."=? and ";
            push @{$whereParam}, $v;
        }
        else {
            return $self->error("���� $field �� �������� fkparent ��� id. �������� ����� �� �������� �� ����� ���� ������������");
        };
        #��������� � ������ ����� ����, ��������� � ��������.
        #�� �������� ����� ����������� � ������������, ������������ ��� �������� ������������ ��������.
        $fieldObjs->{$field->{FIELD}} = 1;
        delete $keyValues->{$field->{FIELD}};
    };
    return $self->showError("�����, ���������� �� ��������, �� ������������ � ������ ������� ������:". join(' ',keys %{$keyValues})) if (scalar keys %{$keyValues});

    #������������ �������
    #�������� ������ ��������� ����� �� �������
    my $filterRFunc=undef;
    my $filterFValues = {};
    if ($sc->{FILTER}) {
        my $filters;
        if (ref ($sc->{FILTER}) eq "ARRAY") {
            $filters = $sc->{FILTER};
        }
        elsif (ref ($sc->{FILTER}) eq "HASH") {
            $filters = [$sc->{FILTER}];
        }
        else {
            return $self->error('������������ �������� �������� FILTER � ������������ ������');
        }
        foreach my $filter (@{$filters}) {
            if (exists $filter->{FUNC}) {
                my $fn = $filter->{FUNC};
     
                return $self->showError("_getIndexes(): ����� �� �������� ������ $fn, ���������� � ��������� FILTER.FUNC") unless $self->can($fn);
                $self->setError("");
                my $v = undef;
                eval {
                    $v = $self->$fn($suffix);
                };
                return $self->showError("_getIndexes(): ����� ������ $fn, ���������� � ��������� FILTER.FUNC, ��������� ������ $@") if $@;
                unless ($v) {
                    my $e = $self->getError();
                    return $self->showError("_getIndexes(): ����� ������ $fn, ���������� � ��������� FILTER.FUNC, ��������� ������ $e") if $e;
                    return $index;
                };
            }
            elsif (exists $filter->{RFUNC}) {
                return $self->showError("_getIndexes(): �������� ������������� ������ ������ ��������� FILTER.RFUNC.") if $filterRFunc;
                $filterRFunc = $filter->{RFUNC};
                return $self->showError("_getIndexes(): ����� �� �������� ������ $filterRFunc, ���������� � ��������� FILTER.RFUNC") unless $self->can($filterRFunc);
            }
            elsif (exists $filter->{FIELD}) {
                my $fname = $filter->{FIELD} or return $self->showError("_getIndexes(): �� ������� ��� ���� � ��������� FILTER.FIELD ������������ ��������������� ������.");
                if (exists $filter->{VALUE}) {
                    return $self->showError("_getIndexes(): ��� ������� �� ���� $fname �������� ��������� VALUE ����� ������������ ��� ".(ref $filter->{VALUE})) if ref $filter->{VALUE};
                    $where .= $fname."=? and ";
                    push @{$whereParam}, $filter->{VALUE};
                }
                elsif (exists $filter->{VALUES}) {
                    #�������� ���� � ������ �����������, ��� ����������� �������� ��������.
                    $fieldObjs->{$fname}= 1;
                    $filterFValues->{$fname}= $filter->{VALUES};
                }
                else {
                    return $self->showError("_getIndexes(): �� ������� ����������� �������� ������� ���� $fname � ��������� FILTER.FIELD ������������ ��������������� ������.")
                }
            }
            elsif (exists $filter->{WHERE}) {
                $where .= $filter->{WHERE}." and ";
                if (!defined $filter->{PARAMS}) {
                    #
                }
                elsif (ref $filter->{PARAMS} eq 'ARRAY') {
                    foreach (@{$filter->{PARAMS}}) {
                        push @{$whereParam}, $_;
                    };
                }
                else {
                    push @{$whereParam}, $filter->{PARAMS};
                };
            }
            else {
                return $self->showError("_getIndexes(): ����������� ��� ������� � ��������� FIELD");
            };
        };
    };

    # ������������ ������
    # ��������� ������ �����, �� ������ ������� ����� ������� ������
    # �������� ���������� �������/������
    my $clFuncValues = {};
    my $pFieldValues = {}; # ������ �������� ��������� ����� �� ������� ��������
    my $pFields      = {}; # ������ ����� ������� ��������, ������� �� ������� � �������� ���� ��������
    my $pRow = $self->getPageRow();
    foreach my $class (keys %{$sc->{CLASSES}}) {
        my $ccfg = $sc->{CLASSES}->{$class};
        if (ref ($ccfg) eq "ARRAY") {
            #
        }
        elsif (ref ($ccfg) eq "HASH") {
            $ccfg = [$ccfg];
            $sc->{CLASSES}->{$class} = $ccfg;
        }
        else {
            return $self->error('������������ �������� ������ $class � �������� CLASSES � ������������ ������');
        };
        
        foreach my $param (@{$ccfg}) {
            if (exists $param->{FIELD}) {
                my $fname = $param->{FIELD} or return $self->showError("_getIndexes(): �� ������� ��� ���� � ��������� CLASSES.$class.FIELD ������������ ��������������� ������.");
                $fieldObjs->{$fname} = 1;
            }
            elsif (exists $param->{PFIELD}) {
                return $self->showError("_getIndexes(): �� ������� ��� ���� �������� � ��������� CLASSES.$class.PFIELD ������������ ��������������� ������.") unless $param->{PFIELD};
                if (exists $pRow->{$param->{PFIELD}}) {
                    $pFieldValues->{$param->{PFIELD}} = $pRow->{$param->{PFIELD}};
                }
                else {
                    $pFields->{$param->{PFIELD}} = 1;
                };
            }
            elsif (exists $param->{TEXT}) {
                #
            }
            elsif (exists $param->{RFUNC}) {
                return $self->showError("_getIndexes(): ����� �� �������� ������ ".$param->{RFUNC}.", ���������� � ��������� CLASSES.$class.RFUNC") unless $self->can($param->{RFUNC});
            }
            elsif (exists $param->{FUNC}) {
                my $fn = $param->{FUNC};
                return $self->error("_getIndexes(): ����� �� �������� ������ $fn, ���������� � ��������� CLASSES.$class.FUNC") unless $self->can($fn);
                $self->setError("");
                
                my $v = undef;
                eval {
                    $v = $self->$fn($class,$suffix);
                };
                return $self->error("_getIndexes(): ����� ������ $fn, ���������� � ��������� CLASSES.$class.FUNC, ��������� ������ $@") if $@;

                unless ($v) {
                    my $e = $self->getError();
                    return $self->error("_getIndexes(): ����� ������ $fn, ���������� � ��������� CLASSES.$class.FUNC, ��������� ������ $e") if $e;
                };
                $clFuncValues->{$class}->{$fn} = $v;
            }
            else {
                return $self->error("_getIndexes(): ����������� ��� ������� ������������ ������ � ��������� CLASS.$class");
            };
        };
    };

    if (scalar keys %{$pFields}) {
        my $sqlfields = join(',',keys %{$pFields});
        $sqlfields =~ s/,$//;
        my $sql = "select $sqlfields from ng_sitestruct where id=?";
        my $row = $self->db()->dbh()->selectrow_hashref($sql,undef,$self->getPageId()) or return $self->showError("_getIndexes(): ������ ��������� ������� ��������: ".$DBI::errstr);
        foreach my $field (keys %{$pFields}) {
            $pFieldValues->{$field} = $row->{$field};
        };
    };
    
    if ($sc->{RFUNCFIELDS}) {
        #����� ����� ����� ���� ������ � ��������, ���������
        foreach my $field ( split /,/,$sc->{RFUNCFIELDS} ) {
            $fieldObjs->{$field} = 1;
        };
    };

    # ��������� ������ ������������� �����
    my $sqlfields = "";
    foreach my $field (keys %{$fieldObjs}) {
        $sqlfields .= $field.",";
        $fieldObjs->{$field} = $self->getField($field) or return $self->error("� ������ ����� ������ �� ������� ���� $field, ��������� � ������������ ������");
    };
    $sqlfields =~ s/,$//;
    
    my $table = $self->{_table};
    $where =~ s/ and $//;
    $where = ($where)?"where $where":"";
    
    my $order = $sc->{ORDER} || "";
    $order = "order by $order" if $order;
    
    my $sql = "select $sqlfields from $table $where $order";
    my $sth = $dbh->prepare($sql) or return $self->error($DBI::errstr);
    $sth->execute(@{$whereParam}) or return $self->error("������ ��������� ������ ������:".$DBI::errstr);
    while (my $row=$sth->fetchrow_hashref()) {
        # �������� ���������� �������
        if ($filterRFunc) {
            $self->setError("");

            my $v = undef;
            eval {
                $v = $self->$filterRFunc($row,$suffix);
            };
            return $self->showError("_getIndexes(): ����� ������ $filterRFunc, ���������� � ��������� FILTER.RFUNC, ��������� ������ $@") if $@;
            
            unless ($v) {
                my $e = $self->getError();
                return $self->showError("_getIndexes(): ����� ������ $filterRFunc, ���������� � ��������� FILTER.RFUNC, ��������� ������ $e") if $e;
                next;
            };
        };
        
        #��������� �������
        my $allowed = 1;
        foreach my $ffield (keys %{$filterFValues}) {
            my $found = 0;
            my $rv = $row->{$ffield};
            foreach my $v (@{$filterFValues->{$ffield}}) {
                if ($rv eq $v) {
                    $found = 1;
                    last;
                }
            };
            unless ($found) {
                $allowed = 0;
                last;
            };
        };
        next unless $allowed;
        
        #������ ��������� ������
        if ($rFunc) {
            my $rowindex = undef;
            eval {
                $rowindex = $self->$rFunc($row);
            };
            $self->error("_getIndexes(): ������ ������ ������ $rFunc: $@") if $@;
            $self->showError("_getIndexes(): ������ ������ ������ $rFunc") unless $rowindex;
            next unless scalar keys %{$rowindex};

            return $self->showError("_getIndexes: ������, ������������ getRowIndex() ������ ".ref($self)." ��������� �������� ���� DATA (�� HASHREF).") if (ref $rowindex->{DATA} ne "HASH");
            if (exists $rowindex->{SUFFIX} && $rowindex->{SUFFIX} ne $suffix) {
                return $self->showError("_getIndexes: getRowIndex() ��������� �������� ������� ������: '".$rowindex->{SUFFIX}."' �� ��������� � ��������� ".$suffix.".");
            }
            next unless scalar keys %{$rowindex->{DATA}};

            foreach my $class (keys %{$rowindex->{DATA}}) {
                $index->{DATA}->{$class} .= " " if ($index->{DATA}->{$class});
                $index->{DATA}->{$class} .= $rowindex->{DATA}->{$class};
            };
        }
        else {
            my $rowFieldValues = {};
            foreach my $class (keys %{$sc->{CLASSES}}) {
                my $ccfg = $sc->{CLASSES}->{$class};
                my $cvalue = "";
                foreach my $param (@{$ccfg}) {
                    my $v = "";
                    if (exists $param->{FIELD}) {
                        my $fn = $param->{FIELD};
                        if (exists $rowFieldValues->{$fn}) {
                            $v = $rowFieldValues->{$fn};
                        }
                        else {
                            $v = $self->_indexGetFieldValue($fieldObjs->{$fn},$row);
                            unless ($v) {
                                my $e = $self->error();
                                return $self->showError("_getIndexes(): ������ ��������� �������� ���� $fn ��� ������ $class: $e") if $e;
                            };
                            $rowFieldValues->{$fn} = $v;
                        };
                    }
                    elsif (exists $param->{PFIELD}) {
                        $v = $pFieldValues->{$param->{PFIELD}};
                    }
                    elsif (exists $param->{TEXT}) {
                        $v = $param->{TEXT};
                    }
                    elsif (exists $param->{RFUNC}) {
                        my $fn = $param->{RFUNC};
                        $self->setError("");
                        eval {
                            $v = $self->$fn($row,$class,$suffix);
                        };
                        return $self->error("_getIndexes(): ����� ������ $fn, ���������� � ��������� CLASSES.$class.RFUNC, ��������� ������ $@") if $@;
                        unless ($v) {
                            my $e = $self->getError();
                            return $self->showError("_getIndexes(): ����� ������ $fn, ���������� � ��������� CLASSES.$class.RFUNC, ��������� ������ $e") if $e;
                        };
                    }
                    elsif (exists $param->{FUNC}) {
                        $v = $clFuncValues->{$class}->{$param->{FUNC}};
                    }
                    else {
                        return $self->showError("_getIndexes(): ����������� ��� ������� ������������ ������ � ��������� CLASS.$class");
                    };
                    if ($v) {
                        $cvalue .= " " if $cvalue;
                        $cvalue .= $v;
                    };
                };
                $index->{DATA}->{$class} .= " " if ($index->{DATA}->{$class});
                $index->{DATA}->{$class} .= $cvalue;
            };
        };
    };
    $sth->finish();
    return $index;
};

sub _indexGetFieldValue {
    my $self = shift;
    my $fieldObj = shift;
    my $row = shift;

    if ($fieldObj->{TYPE} eq "text") {
        return $row->{$fieldObj->{FIELD}};
    }
    elsif ($fieldObj->{TYPE} eq "textarea") {
        return $row->{$fieldObj->{FIELD}};
    }
    elsif ($fieldObj->{TYPE} eq "rtf") {
        return strip_tags($row->{$fieldObj->{FIELD}});
    }
    elsif ($fieldObj->{TYPE} eq "rtffile") {
        return $self->error("Can`t load data from file: OPTIONS.FILEDIR is not specified for \"rtffile\" field \"$fieldObj->{FIELD}\" ��� ���������� �������.") if (is_empty($fieldObj->{OPTIONS}->{FILEDIR}));
        if ($row->{$fieldObj->{FIELD}}) {
            my ($value,$e) = loadValueFromFile($self->getSiteRoot().$fieldObj->{OPTIONS}->{FILEDIR}.$row->{$fieldObj->{FIELD}});
            return $self->error("������ ������ ����� � ������� ���� $fieldObj->{FIELD}: ".$e) unless defined $value;
            return strip_tags($value);
        }
        else {
            return $self->error("�� ������ ���� ������ ���� ".$fieldObj->{FIELD}." ���� ".$fieldObj->{TYPE});
        }
    }
    elsif ($fieldObj->{TYPE} eq "file") {
        #$index->{DATAADDON} = "����������, ���: ".$self->getFileURL($row->{$indexfield->{FIELD}});
        #$index->{DATAADDON} .= "������ �����: ".$self->getFileURL($row->{'small_img'});
    }
    elsif ($fieldObj->{TYPE} eq "date") {
        return $self->db()->date_from_db($row->{$fieldObj->{FIELD}});
    }
    elsif ($fieldObj->{TYPE} eq "datetime") {
        return $self->db()->datetime_from_db($row->{$fieldObj->{FIELD}});
    }
    return $self->error("���������������� ������������ ��� ���� ".$fieldObj->{TYPE}." - ���� ".$fieldObj->{FIELD});
};

sub getField {
	my $self = shift;
	my $fieldname = shift;

    return {NAME=>"�",TYPE=>"_counter_"} if ($fieldname eq "_counter_");
    
	foreach my $field (@{$self->{_fields}}) {
		if ($field->{FIELD} eq $fieldname)  {
			return $field;
			last;
		}
	}
	return undef;
} 

sub _makeEvent {
    my $self = shift;
    my $ename = shift;
    my $eopts = shift;
            
    my $event = NG::Module::Record::Event->new($self,$ename,$eopts);
    $self->cms()->processEvent($event);
};
                    
sub blockPrivileges {
    return undef;
}

return 1;
END{};
