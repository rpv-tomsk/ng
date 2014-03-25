package NG::SiteBlocks::Catalog;
use strict;
use NG::Module::List;
our @ISA = qw(NG::Module::List);
use NSecure;

## В даном модуле используется балансированые деревья, так что Я БЫ НЕ СОВЕТОВАЛ ЕГО ИСПОЛЬЗОВАТЬ ПРИ АКТИВНЫХ ВСТАВКАХ
## Так же тут балансировка делается через скрипты без использования базы так что Я БЫ НЕ СОВЕТОВАЛ ЕГО ИСПОЛЬЗОВАТЬ ПРИ АКТИВНЫХ ВСТАВКАХ
## В разделах каталога не должно быть фильтрации , ибо в листе какая то мутная передвигалка
## при перемещения tree_order будут пересчитыаться отдельно , так как передвигать будут соседние позиции

sub config {
    my $self = shift;
    my $q = $self->q();
    my $parent_id = $q->param('parent_id');
    $parent_id = 0 unless is_valid_id($parent_id);
    $self->{'_table'} = $self->catalog_table();
    my $action = $q->param('action') || $q->url_param('action');
    my $formaction = $q->param('formaction');
    my $update = $action eq 'updf' || ($action eq 'formaction' && $formaction eq 'update') ? 1 : 0;
    my @parent_field = ();
    unless ($update) {
        @parent_field = ($parent_id ?  {'FIELD'=>'parent_id', 'TYPE'=>'fkparent', 'VALUE'=>$parent_id, 'DEFAULT'=>$parent_id} :  {'FIELD'=>'parent_id', 'TYPE'=>'filter', 'VALUE'=>0});
    };
    $self->fields(
        {'FIELD'=>'id', 'TYPE'=>'id'},
        @parent_field,
        {'FIELD'=>'tree_order', 'TYPE'=>'hidden', 'DEFAULT'=>0, 'IS_FAKEFIELD'=>1, 'NAME'=>'Позиция'},
        {'FIELD'=>'level', 'TYPE'=>'hidden', 'DEFAULT'=>1, 'IS_FAKEFIELD'=>1},
        {'FIELD'=>'position', 'TYPE'=>'posorder', 'NAME'=>'Позиция'},
        $self->data_fields()
    );
    
    $self->formfields(
        {'FIELD'=>'id'},
        {'FIELD'=>'tree_order'},
        {'FIELD'=>'level'},
        $self->_compose_form_fields()
    );
    $self->listfields(
        {'FIELD'=>'id', 'TYPE'=>'hidden'},
        $self->_compose_list_fields()
    );
    
    $self->addRowLink({'NAME'=>'Подразделы','URL'=>$self->getBaseURL().'?parent_id={id}'});
    $self->addRowLink({'NAME'=>'Позиции','URL'=>$self->getBaseURL().'position/?parent_id={id}'});
    if ($parent_id) {
        my ($grand_parent_id) = $self->dbh()->selectrow_array('select parent_id from '.$self->catalog_table().' where id=?', undef, $parent_id);
        $self->addTopbarLink({'NAME'=>'Назад', 'URL'=>'?parent_id='.$grand_parent_id}); 
    }
};

sub afterMove {
    my ($self, $id, $moveDir) = @_;
    my $dbh = $self->dbh();
    my $current = $dbh->selectrow_hashref('select id,tree_order,level from '.$self->catalog_table().' where id=?', undef, $id);
    return 1 unless $current;
    
    my $swap = undef;
    if ($moveDir eq 'up') {
        $swap = $dbh->selectrow_hashref('select id,tree_order,level from '.$self->catalog_table().' where level=? and tree_order<? order by tree_order desc limit 1', undef, $current->{'level'}, $current->{'tree_order'});
    }
    elsif ($moveDir eq 'down') {
        $swap = $dbh->selectrow_hashref('select id,tree_order,level from '.$self->catalog_table().' where level=? and tree_order>? order by tree_order asc limit 1', undef, $current->{'level'}, $current->{'tree_order'});
    };
    return 1 unless $swap;
    
    my $current_sibling_order = undef;
    my $swap_sibling_order = undef;
    $current_sibling_order = $swap->{'tree_order'} if ($current->{'tree_order'}<$swap->{'tree_order'});
    $swap_sibling_order = $current->{'tree_order'} if ($current->{'tree_order'}>$swap->{'tree_order'});
    if (!defined $current_sibling_order) {
        ($current_sibling_order) = $dbh->selectrow_array('select tree_order from '.$self->catalog_table().' where level<=? and tree_order>? order by tree_order asc limit 1', undef, $current->{'level'}, $current->{'tree_order'}); 
    };
    if (!defined $swap_sibling_order) {
        ($swap_sibling_order) = $dbh->selectrow_array('select tree_order from '.$self->catalog_table().' where level<=? and tree_order>? order by tree_order asc limit 1', undef, $swap->{'level'}, $swap->{'tree_order'}); 
    };
    
    my ($current_last_child) = $dbh->selectrow_hashref('select id,level,tree_order from '.$self->catalog_table().' where level>=? and tree_order>=? '.(defined $current_sibling_order?'and tree_order<?':'').' order by tree_order desc limit 1', undef, $current->{'level'}, $current->{'tree_order'}, (defined $current_sibling_order?$current_sibling_order:()));
    my ($swap_last_child) = $dbh->selectrow_hashref('select id,level,tree_order from '.$self->catalog_table().' where level>=? and tree_order>=? '.(defined $swap_sibling_order?'and tree_order<?':'').' order by tree_order desc limit 1', undef, $swap->{'level'}, $swap->{'tree_order'},  (defined $swap_sibling_order?$swap_sibling_order:()));
    
    my ($f1,$f2,$f3,$f4) = ($current->{'tree_order'},$current_last_child->{'tree_order'},$swap->{'tree_order'},$swap_last_child->{'tree_order'});
    ($f1,$f2,$f3,$f4) = ($f3,$f4,$f1,$f2) if ($swap->{'tree_order'} < $current->{'tree_order'});
    
    my $delta1 = $f4-$f2; # На сколько на надо сместить первый отрезок вперед;
    my $delta2 = $f3-$f1; # На сколько нам надо сместить второй отрезок назад
    $dbh->do('update '.$self->catalog_table().' set tree_order= (-1)*tree_order where tree_order>=? and tree_order<=?',undef,$f1,$f2);
    $dbh->do('update '.$self->catalog_table().' set tree_order= tree_order - ? where tree_order>=? and tree_order<=?',undef,$delta2,$f3,$f4);
    $dbh->do('update '.$self->catalog_table().' set tree_order= (-1)*tree_order + ? where tree_order<=? and tree_order>=?',undef,$delta1,-1*$f1,-1*$f2);
};


sub catalog_table {
    return 'catalog';
};

sub treeorder_step {
    return 20;
};

sub data_fields {
    return ();
};

sub form_fields {
    return ();
};

sub list_fields {
    return ();
};


sub _compose_fields {
    my $self = shift;
    my @fields = @_;
    my @result = ();
    foreach my $f (@fields) {
        push @result, {'FIELD'=>$f}
    };
    return @result;
};

sub _compose_form_fields {
    my $self = shift;
    return $self->_compose_fields($self->form_fields());
};

sub _compose_list_fields {
    my $self = shift;
    return $self->_compose_fields($self->list_fields());
};


sub prepareData {
    my $self = shift;
    my $form = shift;
    my $action = shift;
    
    if ($action eq 'insert') {
        my ($tree_order,$level) = $self->get_newnode_param();
        my $f_tree_order = $form->getField('tree_order');
        my $f_level = $form->getField('level');
        $f_tree_order->{'IS_FAKEFIELD'} = 0;
        $f_tree_order->setValue($tree_order); 
        $f_level->{'IS_FAKEFIELD'} = 0;     
        $f_level->setValue($level);
    };
    
    return NG::Block::M_OK;
};

sub get_newnode_param {
    my $self = shift;
    my $q = $self->q();
    my $dbh = $self->dbh();
    
    my ($tree_order, $level) = (undef,undef);
    my $parent_id = $q->param('parent_id');
    $parent_id = 0 unless is_valid_id($parent_id);
    my $parent_element = $dbh->selectrow_hashref('select id,tree_order,level from '.$self->catalog_table().' where id=?',undef,$parent_id);
    
    unless ($parent_element) {
        $level = 1;
        ($tree_order) = $dbh->selectrow_array('select max(tree_order) from '.$self->catalog_table().' where parent_id=?',undef,$parent_id);
        if  (!defined $tree_order) {
            $tree_order = 0;
        }
        else {
            $tree_order += $self->treeorder_step();
        };
    }
    else {
        $level = $parent_element->{'level'} + 1;
        my ($prev_tree_order) = $dbh->selectrow_array('select max(tree_order) from '.$self->catalog_table().' where parent_id=?',undef,$parent_id);
        $prev_tree_order = $parent_element->{'tree_order'} unless defined $prev_tree_order;
        my ($next_tree_order) = $dbh->selectrow_array('select tree_order from '.$self->catalog_table().' where level=? and tree_order>? order by tree_order asc limit 1',undef,$parent_element->{'level'},$parent_element->{'tree_order'});
#         die $next_tree_order.'-'.$parent_element->{'level'}.'-'.$parent_element->{'tree_order'};
        if (!defined $next_tree_order) {
            $tree_order = $prev_tree_order + $self->treeorder_step();
        }
        else {
            if($prev_tree_order +1 == $next_tree_order) {
                $dbh->do('update '.$self->catalog_table().' set tree_order=tree_order+? where tree_order>=?',undef,$self->treeorder_step()*5,$next_tree_order);
                $next_tree_order += $self->treeorder_step()*5;                                
            };
            $tree_order = $prev_tree_order + int(($next_tree_order - $prev_tree_order)/2);
        };            
    };
    return ($tree_order,$level);
};
1;