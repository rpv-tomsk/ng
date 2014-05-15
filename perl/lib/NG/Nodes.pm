package NG::Nodes;

use strict;
use Tree::Simple;
use NSecure;
use Carp;

use Scalar::Util qw (blessed);

$NG::Nodes::VERSION = 0.4;

BEGIN {
	use vars qw(@ISA $DB $TABLE $FIELDS $JOIN);
	@ISA = qw(Tree::Simple);
};

=head
    NB:  loadtree/etc не выставляют $self->{_prev_sibling_order}
=cut

#my $CLASS = "NG::Nodes";

##
# Override methods

sub _setParent {
	my ($self,$parent) = @_;
	
	#(blessed ($self) && $self->isa($CLASS)) || ($parent eq $self->ROOT) || die "Subtree ".$self->getNodeValue()." must be $CLASS object";

	if ($parent ne $self->ROOT) {
		$self->{_db} = $parent->{_db};
		$self->{_dbtable} = $parent->{_dbtable};
		$self->{_fields} = $parent->{_fields};
	}
	$self->SUPER::_setParent($parent);
}

sub _init {
	my ($self, $node, $parent, $children) = @_;

	$self->{_childs_loaded}=0;
	$self->{_loaded} = 0;
	
	if (!defined $node) {$node = {}; };
	
	return $self->SUPER::_init($node,$parent,$children);
}

sub removeChild {
    my ($self, $child_to_remove) = @_;
    $self->SUPER::removeChild($child_to_remove);
    
    my $pch = undef;
    foreach my $ch (@{$self->{_children}}) {
        $pch->{_next_sibling_order} = $ch->{_order} if $pch;
        $pch = $ch;
    };
    $pch->{_next_sibling_order} = undef if $pch;
    $self->{_last_child_order} = undef;
    $self->{_last_child_order} = $pch->{_order} if $pch;
};

## Internal used methods

sub _getNewObj {
	my $self = shift;
	
	my $new = $self->new();
	$new->{_db} = $self->db();
	$new->{_dbtable} = $self->table();
	$new->{_fields} = $self->fields();
	$new->{_join} = $self->join();
	$new;
};

sub db {
    my $self = shift;
    $self->{_db} = $DB unless exists $self->{_db};
    return $self->{_db} || croak("NG::Nodes::db(): Class or object not initialised via initdbparams()");
};

sub table {
    my $self = shift;
    $self->{_dbtable} = $TABLE unless exists $self->{_dbtable};
    return $self->{_dbtable} || croak("NG::Nodes::table(): Class or object not initialised via initdbparams()");
};

sub fields {
    my $self = shift;
    $self->{_fields} = $FIELDS unless exists $self->{_fields};
    return $self->{_fields} || croak("NG::Nodes::fields(): Class or object not initialised via initdbparams()");
};

sub join {
    my $self = shift;
    $self->{_join} = $JOIN unless exists $self->{_join};
    return $self->{_join} || "";
};

##
# New public methods

##
## Функция, вызываемая для каждой ноды должна возвратить 0. Иначе выполнение обхода дерева прекратится, код возврата передастся наверх
##  

sub traverseWithCheck {
    my ($self, $func, $post) = @_;
    (defined($func)) || die "Insufficient Arguments : Cannot traverse without traversal function";
    (ref($func) eq "CODE") || die "Incorrect Object Type : traversal function is not a function";
    (ref($post) eq "CODE") || die "Incorrect Object Type : post traversal function is not a function"
        if defined($post);
    foreach my $child ($self->getAllChildren()) {
        my $res = $func->($child);
		return $res if $res;
        $res = $child->traverseWithCheck($func, $post);
		return $res if $res;
        if (defined($post)){
			$res = $post->($child);
			return $res if $res;
		}  
    }
	return 0;
};

sub loadNode {
    my $self = shift;
    
    $self = $self->new() unless ref $self;

    my $key = "";
    my $id = 0;
    if (scalar(@_) == 1) {
        $key = "main.id";
        $id = shift;
    }
    elsif (scalar(@_) == 2) {
        $key = shift;
        $id = shift;
    }
    else {
        croak("NG::Nodes::loadNode(): invalid parameters");
    };

    croak ("NG::Nodes::loadNode(): node has loaded already") if $self->loaded();
    croak ("NG::Nodes::loadNode(): id not specified") unless defined $id;

	my $dbh   = $self->db()->dbh();
	my $table = $self->table();
	my $fields= $self->fields();
	my $where = $self->{_dbwhere};
	my $join  = $self->join();
	
	my $sql="select main.id,main.parent_id,main.tree_order,main.level".(($fields)?",$fields":"")." from $table as main $join where $key = ?".(($where)?" and $where ":"");

	my $sth=$dbh->prepare($sql) or die $DBI::errstr;
	$sth->execute($id) or die $DBI::errstr;
	my $row = $sth->fetchrow_hashref();
    my $nrow = $sth->fetchrow_hashref();
	$sth->finish();
	
    return 0 unless $row;   ## No Node found
    croak("Key \"$key\" is not unique: duplicate row for value $id detected") if $nrow;

	$self->{_id} = $row->{id};
	$self->{_parent_id} = $row->{parent_id};
	$self->{_order} = $row->{tree_order};
	$self->{_level} = $row->{level};
	$self->{_loaded} = 1;
    
    $self->{_first_child_order} = undef;
    $self->{_last_child_order}  = undef;
    $self->{_prev_sibling_order}  = undef;
    $self->{_next_sibling_order}  = undef;
    $self->{_last_relative_order} = undef;
    $self->{_subtree_border_order} = undef;
    
	$self->setNodeValue($row);
	$self;
};

sub loaded {
    my $self = shift;
    return $self->{_loaded};
};

sub _setFirstLastChildOrder {
    my $self = shift;
   
    my $dbh = $self->db()->dbh();
    my $table = $self->table();

    #Первый и последний ребенок
    my $sql="select min(tree_order),max(tree_order) from $table where parent_id = ?";
    my $sth=$dbh->prepare($sql) or die "_setFirstLastChildOrder(): ".$DBI::errstr;
    $sth->execute($self->{_id}) or die "_setFirstLastChildOrder(): ".$DBI::errstr;
    ($self->{_first_child_order}, $self->{_last_child_order}) = $sth->fetchrow();
    $sth->finish();
};

sub getFirstChildOrder {
    #Находим tree_order первого ребенка текущей ноды
    my $self = shift;
    croak "getFirstChildOrder: node not loaded" unless $self->loaded();
    
    return $self->{_first_child_order} if defined $self->{_first_child_order};
    $self->_setFirstLastChildOrder();
    return $self->{_first_child_order};
};

sub getLastChildOrder {
    #Находим tree_order последнего ребенка текущей ноды
    my $self = shift;
    croak "getLastChildOrder: node not loaded" unless $self->loaded();

    return $self->{_last_child_order} if defined $self->{_last_child_order};
    $self->_setFirstLastChildOrder();
    return $self->{_last_child_order};
};

sub getPrevSiblingOrder {
    #Находим tree_order предыдущего соседа текущей ноды
    my $self = shift;
    croak "getPrevSiblingOrder: node not loaded" unless $self->loaded();
    
    return $self->{_prev_sibling_order} if defined $self->{_prev_sibling_order};

    my $dbh = $self->db()->dbh();
    my $table = $self->table();

    my $sql = "select max(tree_order) from $table where tree_order < ? and parent_id = ? ";
    my $sth=$dbh->prepare($sql) or die $DBI::errstr;
    $sth->execute($self->{_order},$self->{_parent_id}) or die $DBI::errstr;
    $self->{_prev_sibling_order} = $sth->fetchrow();
    $sth->finish();
    
    return $self->{_prev_sibling_order};
};

sub getNextSiblingOrder {
    #Находим tree_order следующего соседа текущей ноды
    my $self = shift;
    croak "getNextSiblingOrder: node not loaded" unless $self->loaded();

    return $self->{_next_sibling_order} if defined $self->{_next_sibling_order};

    my $dbh = $self->db()->dbh();
    my $table = $self->table();

    my $sql = "select min(tree_order) from $table where tree_order > ? and parent_id = ? ";
    my $sth=$dbh->prepare($sql) or die $DBI::errstr;
    $sth->execute($self->{_order},$self->{_parent_id}) or die $DBI::errstr;
    $self->{_next_sibling_order} = $sth->fetchrow();
    $sth->finish();
    
    return $self->{_next_sibling_order};
};

sub getLastRelativeOrder {
    #Находим order последней ноды в поддеререве
    my $self = shift;
    croak "getLastRelativeOrder: node not loaded" unless $self->loaded();
    
    return $self->{_last_relative_order} if defined $self->{_last_relative_order};
    
    my $dbh = $self->db()->dbh();
    my $table = $self->table();
    
    my $i = $self->getSubtreeBorderOrder();

    my $where = "";
    my @params = ();
    if ($i) {
        #если за поддеревом существуют другие ноды
        $where .= " tree_order <?";
        push @params, $i;
    };
    $where = "where ". $where if $where;
    
    my $sth = $dbh->prepare_cached("select max(tree_order) from $table $where") or die $DBI::errstr;
    $sth->execute(@params) or die $DBI::errstr;
    my $order = $sth->fetchrow() or croak "getLastRelativeOrder(): no tree_order found";
    $sth->finish();
    
    die "_last_relative_order < tree_order" if ($order < $self->{_order});
    
    $self->{_last_relative_order} = $order;
    return $order;
};

sub getSubtreeBorderOrder {
    # Находим ноду, следующую за поддеревом (веткой) этой ноды
    # Если за поддеревом отсутствуют ноды, значит возвращаем ноль
    my $self = shift;
    
    croak "getSubtreeBorderOrder: node not loaded" unless $self->loaded();
    
    return $self->{_subtree_border_order} if defined $self->{_subtree_border_order};

    my $dbh   = $self->db()->dbh();
    my $table = $self->table();
    
    my $sth = $dbh->prepare_cached("select min(tree_order) from $table where tree_order>? and level <=?") or die $DBI::errstr;
    $sth->execute($self->{_order},$self->{_level}) or die $DBI::errstr;
    my $order = $sth->fetchrow();
    $sth->finish();

    $order||=0;
    $self->{_subtree_border_order} = $order;
    return $order;
}

sub getNodeById {
    my $self = shift;
    my $id = shift;
use Carp qw/croak/;
croak("Not defined ID") unless defined $id;

    return $self if $self->{_id} eq $id;
    foreach my $child ($self->getAllChildren()) {
	    if ($child->{_id} eq $id) { return $child; };
	    if ($child->getChildCount()>0)  {
			my $result = $child->getNodeById($id);
			if ($result) { return $result; };
	    };
    };
    return undef;
};

sub DBaddChild {
    my $self = shift;
    my $data = shift;
	my $opts = shift; # Currently supported: AFTER=> (id | NG::Nodes)
    
	croak ("NG::Nodes::DBaddChild: node has not loaded") if (!defined $self->{_id});
	croak ("NG::Nodes::DBaddChild: node has not loaded") if ($self->{_loaded} != 1);
	croak ("NG::Nodes::DBaddChild: opts is not HASHREF") if ($opts && ref $opts ne "HASH");
	
	$opts ||= {};

    my $dbh   = $self->db()->dbh();
    my $table = $self->table();
    my $fields= $self->fields();
	
	my $afterNode = undef;
	if (exists $opts->{AFTER}) {
		if (ref $opts->{AFTER}) {
			croak ("NG::Nodes::DBaddChild: opts->AFTER is not valid object") unless $opts->{AFTER}->isa(ref($self));
			$afterNode = $opts->{AFTER};
		}
		else {
			$afterNode = $self->_getNewObj();
			$afterNode->loadNode(id=>$opts->{AFTER}) or croak("DBaddChild(): opts->{AFTER} - node not found");
		};
		croak("NG::Nodes::DBaddChild: Node in opts->AFTER is not valid child") unless $afterNode->{_parent_id} == $self->{_id};
	};
	$afterNode ||= $self;
    
    my $i1 = $afterNode->getLastRelativeOrder();
    my $i2 = $afterNode->getSubtreeBorderOrder();
    
    if ($i2 && ($i1 + 1 >= $i2)) {
        #croak("DBaddChild: no space for new child, need tree balancing");
    	#Mysql Version ... 
    	#$dbh->do("UPDATE $table set tree_order = tree_order + 10 where tree_order > ? order by tree_order desc",undef,$i1) or die $DBI::errstr;
    	#
    	# PG version
        $dbh->do("UPDATE $table set tree_order = -tree_order-10 where tree_order > ?",undef,$i1) or die $DBI::errstr;
        $dbh->do("UPDATE $table set tree_order = -tree_order where tree_order < 0") or die $DBI::errstr;
    };
    
    my $idvalue = 0;
    my @values = ();
	
    my @fields = split /\s*\,\s*/ , $fields;
    $fields = "";
    foreach my $fieldname (@fields)  {
   		push @values, $data->{$fieldname};
   		$fields .= $fieldname.","
    };
	$idvalue = $data->{id};
    $fields =~ s/\,$//;
    $idvalue = $self->db()->get_id($table) if (!is_valid_id($idvalue));
    
    
    my $sth=$dbh->prepare("INSERT into $table (id,parent_id,tree_order,level".(($fields)?",$fields":"").") values (?,?,?,?".( ",?" x scalar(@values)).")");
    $sth->execute($idvalue,$self->{_id},$i1+1,$self->{_level}+1, @values) or die $DBI::errstr;
    $sth->finish();

    $self->{_last_child_order}= $i1+1;
    $self->{_last_relative_order}= $i1+1;
    return $idvalue;
}

sub DBdelete {
    my $self = shift;
    my $dbh   = $self->db()->dbh();
    my $table = $self->table();
    
	croak ("NG::Nodes::DBdelete(): node has not loaded") if ($self->{_loaded} != 1);
	
    my $i1 = $self->getSubtreeBorderOrder();
    my $where = "";
    my @params = ();
    
    $where .= "tree_order>=? "; push @params, $self->{_order};
    if ($i1) {
        #Если после нашей ветки есть другие ноды, то удаляем до них, иначе до конца
        $where .= "and tree_order<? "; push @params, $i1;
    };
    #Для надежности, ограничим удаляемую ветку по уровню, не только по tree_order
    $where .= "and level>=? ";  push @params, $self->{_level};
	$dbh->do("DELETE FROM $table where $where",undef,@params) or die $DBI::errstr;
    undef($self); ## XXX: TODO: this
}

sub DBmoveNodeUp {
    my $self = shift;
	
	croak ("NG::Nodes::DBmoveNodeUp(): node has not loaded") unless $self->loaded();
    
    # находим ноду, выше которой хотим встать (предыдущего соседа)
    my $prow_order = $self->getPrevSiblingOrder();
    return 1 unless $prow_order;    #Выше ничего нет
    my $prevSibling = $self->_getNewObj();
    $prevSibling->loadNode(tree_order=> $prow_order);
    return $self->DBmoveNode(before=>$prevSibling);
}

sub DBmoveNodeDn {
    my $self = shift;

    croak ("NG::Nodes::DBmoveNodeDn(): node has not loaded") unless $self->loaded();

    my $nso = $self->getNextSiblingOrder();
    return 1 unless $nso; #Ниже ничего нет
    my $nextSibling = $self->_getNewObj();
    $nextSibling->loadNode(tree_order=> $nso);
    return $self->DBmoveNode(after=>$nextSibling);
};

sub DBmoveNode {
    my $self = shift;
    my $action = shift;
    my $pnode = shift;
    
    
    my $table = $self->table();
    my $dbh = $self->db()->dbh();
    
    my $partnerRow = undef;
    if (ref $pnode) {
        $partnerRow = $pnode->getNodeValue();
    }
    else {
        my $sth=$dbh->prepare("select id,parent_id,tree_order,level from $table where id = ?") or die $DBI::errstr;
        $sth->execute($pnode) or die $DBI::errstr;
        $partnerRow = $sth->fetchrow_hashref();
        $sth->finish();
        croak("DBmoveNode(): partner node not found") unless $partnerRow;
    };
    
    #Находим границу перемещаемой ветки
    my $borderOrder = $self->getSubtreeBorderOrder();
    unless ($borderOrder) {
        my $sth = $dbh->prepare_cached("select max(tree_order) from $table") or die $DBI::errstr;
        $sth->execute() or die $DBI::errstr;
        $borderOrder = $sth->fetchrow() or croak "no tree_order found";
        $sth->finish();
        $borderOrder++;
    };
    
    if ($partnerRow->{tree_order} >= $self->{_order} && $partnerRow->{tree_order} < $borderOrder) {
        croak "DBmoveNode(): Node cannot be moved to own subtree";
    };
    
    my $levelDelta = $partnerRow->{level} - $self->{_level};
    
    if ($action eq "before") {
        if ($partnerRow->{tree_order} < $borderOrder) {
            $self->_swapIntervals($partnerRow->{tree_order}, $self->{_order}, $borderOrder, 0, $levelDelta);
        }
        elsif ($partnerRow->{tree_order} == $borderOrder) {
            #Уже упорядочены как надо, но возможно надо поправить level
            $self->_swapIntervals($self->{_order}, $borderOrder, $partnerRow->{tree_order}, $levelDelta, 0);
        }
        elsif ($partnerRow->{tree_order} > $borderOrder) {
            $self->_swapIntervals($self->{_order}, $borderOrder, $partnerRow->{tree_order}, $levelDelta, 0);
        }
        else {
            croak("DBmoveNode(): my logic has something wrong...");
        };
    }
    elsif ($action eq "after") {
        #Находим границу ветки ноды-партнера
        my $sth = $dbh->prepare_cached("select min(tree_order) from $table where tree_order>? and level <=?") or die $DBI::errstr;
        $sth->execute($partnerRow->{tree_order},$partnerRow->{level}) or die $DBI::errstr;
        my $partnerBorderOrder = $sth->fetchrow();
        $sth->finish();
        
        unless ($partnerBorderOrder) {
            $sth = $dbh->prepare_cached("select max(tree_order) from $table") or die $DBI::errstr;
            $sth->execute() or die $DBI::errstr;
            $partnerBorderOrder = $sth->fetchrow() or croak "no tree_order found";
            $sth->finish();
            $partnerBorderOrder++;
        };
        
        if ($partnerBorderOrder < $self->{_order}) {
            $self->_swapIntervals($partnerBorderOrder, $self->{_order}, $borderOrder, 0, $levelDelta);
        }
        elsif ($partnerBorderOrder == $self->{_order}) {
            #Уже упорядочены как надо, но возможно надо поправить level
            $self->_swapIntervals($self->{_order}, $borderOrder, $partnerBorderOrder, $levelDelta, 0);
        }
        elsif ($partnerBorderOrder > $self->{_order}) {
            $self->_swapIntervals($self->{_order}, $borderOrder, $partnerBorderOrder, $levelDelta, 0);
        }
        else {
            croak("DBmoveNode(): my logic has something wrong...");
        };
    }
    else {
        croak "NG::Nodes::DBmoveNode(): invalid action $action";
    };
    if ($levelDelta) {
        $dbh->do("update $table set parent_id = ? where id = ?",undef,$partnerRow->{parent_id},$self->{_id});
    };
};

sub _swapIntervals  {
    my $self = shift;
    my ($a,$c,$q) = (shift,shift,shift);  # три точки, два отрезка
    my ($dl1,$dl2) = (shift,shift);       # изменения level для отрезков AC и CQ соответственно
    
    croak "_swapIntervals(): \$a > \$c" if $a > $c;
    croak "_swapIntervals(): \$c > \$q" if $c > $q;
    
    my $dbh = $self->db()->dbh();
    my $table = $self->table();
    
    $dbh->do("UPDATE $table set tree_order = -tree_order - ?, level = level + ? where tree_order >= ? and tree_order < ?",undef,($q-$c), $dl1, $a,$c) or die $DBI::errstr;
    $dbh->do("UPDATE $table set tree_order = -tree_order + ?, level = level + ? where tree_order >= ? and tree_order < ?",undef,($c-$a), $dl2, $c,$q) or die $DBI::errstr;
    $dbh->do("UPDATE $table set tree_order = -tree_order where tree_order > ? and tree_order <= ?",undef,-1*$q,-1*$a) or die $DBI::errstr;
};


sub printNode () {
    my $self = shift;
    print $self->getNodeValue()->{name};
    print "\tID=".$self->{_id};
    print " PID=".$self->{_parent_id};
    print " ORD=".$self->{_order};
    print " NS_ORD=".$self->{_next_sibling_order};
    print " NC_ORD=".$self->{_first_child_order};
    print " LC_ORD=".$self->{_last_child_order};
    print " CHL=".$self->{_childs_loaded};
	print " LL=".$self->{_level};
    print "<br>\n";
};

sub printSubtree {
    my $tree = shift;
    $tree->traverse(
	sub {
	    my ($_tree) = @_;
    	    print "\t" x $_tree->getDepth();
	    $_tree->printNode();
	}
    );
}

sub initdbparams {
    my $self = shift;
    my %args = (@_);
    # XXX need to copy this internal variables in overrided _setParent() function !!!
    
    croak("initdbparams: db not defined")    unless exists $args{db};
    croak("initdbparams: table not defined") unless exists $args{table};
    croak("initdbparams: fields not defined") unless exists $args{fields};

    my @fields = split /\s*\,\s*/ , $args{fields};
    my $fields = "";
    foreach my $f (@fields)  {
        next if $f eq "id";
        next if $f eq "parent_id";
        next if $f eq "tree_order";
        next if $f eq "level";
    	$fields .= $f.",";
    };
    $fields =~ s/\,$//;

    if (ref $self) {
        $self->{_fields} =  $fields;
        $self->{_db} = $args{db};
        $self->{_dbtable} = $args{table};
        $self->{_join} = $args{'join'};
    }
    else {
        $DB = $args{db};
        $TABLE = $args{table};
        $FIELDS = $args{fields};
        $JOIN = $args{'join'};
    };
    #$self->{_dbwhere} = exists $args{where} ? $args{where} : "";
};

sub loadChilds {
	my $self = shift;
	
	croak ("NG::Nodes::loadChilds(): node has loaded childs already") if ($self->{_childs_loaded}==1);

	my $dbh   = $self->db()->dbh();
	my $table = $self->table();
	my $fields= $self->fields();

	my $join  = $self->join();

	my $sql="select main.id,main.parent_id,main.tree_order,main.level".(($fields)?",$fields":"")." from $table main $join where main.parent_id = ? order by main.tree_order";
	my $sth=$dbh->prepare($sql) or die $DBI::errstr;
	$sth->execute($self->{_id}) or die $DBI::errstr;

	my $prev_node;

	while(my $row=$sth->fetchrow_hashref()) {
		# Создаем ноду		
		my $new_node = $self->new();
		# Выставляем значения данных и инициализируем
		$new_node->setNodeValue($row);
		$new_node->{_id} = $row->{id};
		$new_node->{_parent_id} = $row->{parent_id};
		$new_node->{_order} = $row->{tree_order};
		$new_node->{_level} = $row->{level};
		
		$prev_node->{_next_sibling_order} = $row->{tree_order} if $prev_node;
		$prev_node = $new_node;
		
		$self->addChild($new_node);
		$self->{_last_child_order} = $new_node->{_order};
		$self->{_first_child_order} ||= $new_node->{_order};
	};
	$self->{_childs_loaded}=1;		
};

sub loadPartOfTree {
	my $tree=shift;
	my $root_id = shift;
	my $id = shift;
	
	croak ("NG::Nodes::loadChilds(): node has loaded already") if ($tree->{_loaded} == 1);

	my $dbh   = $tree->db()->dbh();
	my $table = $tree->table();
	my $fields= $tree->fields();
	my $join  = $tree->join();

	$tree->loadtree($root_id,2);  #Загружаем первый и второй уровни
	my $rootlevel = $tree->getChild(0)->{_level}-1;
	if (!defined($id)) { return $tree; };  # Загрузили первый второй уровень и успокоились.
	
	if (($tree->getChildCount()==1) && ($tree->getChild(0)->getChildCount()==0)) { return $tree; };   #а есть ли второй уровень? Если нет работать дальше нет смысла

	# Загружаем выбранную ноду.
	my $sth=$dbh->prepare("select main.id,main.parent_id,main.tree_order,main.level from $table as main $join where main.id=?") or die $DBI::errstr;    
	$sth->execute($id) or die $DBI::errstr;
	my $selected=$sth->fetchrow_hashref();

	if ( !defined $selected )        { return $tree; };  #TODO: XXX if selected id is not found...
	if ( $selected->{'level'} == $rootlevel + 1 ) { return $tree; }; # Второй уровень уже загружен. 

	if ($selected->{'level'} == $rootlevel + 2) {
		#Нужно загрузить третий уровень.
		my $l2_node = $tree->getNodeById($id) or die("Level 2 node not found for selected node with level = 2"); 
		$l2_node->loadChilds();
		return $tree;
	};
	if ($selected->{level} == $rootlevel + 3) {
		#Родительская нода для выбранной уже загружена
		my $l2_node = $tree->getNodeById($selected->{parent_id}) or die("Level 2 node not found for selected node with level = 3");
		$l2_node->loadChilds();
		my $l3_node = $l2_node->getNodeById($selected->{id});
		$l3_node->loadChilds();
		return $tree;
	};
	if ($selected->{level} > $rootlevel + 3) {
		#Выбранная нода находится глубоко. Находим ноду второго уровня которая является предком выбранной
		my $l2_node = undef;
		$sth=$dbh->prepare("select max(tree_order) as max_order from $table where level=? and tree_order<?") or die $DBI::errstr;
		$sth->execute($rootlevel+2,$selected->{'tree_order'}) or die $DBI::errstr;
		my $l2_order = $sth->fetchrow();
#die $l2_order;
#use Data::Dumper;
#die Dumper($tree->getChild(0)->getAllChildren());		
#print "Content-type: text/html; charset=windows-1251\n\n";
#print Dumper($tree->getChild(0)->getAllChildren());
#exit();
		# Ищем ноду
		foreach my $l1 ($tree->getAllChildren()) {
			foreach my $node ($l1->getAllChildren()) {
				#print $node->{'_order'}."".$node->{'level'};
				#print "<br/>---------------------------------</br>";
				if ($node->{_order} == $l2_order) {
					$l2_node = $node;
					last;
				};
			};
		};
		if (!defined $l2_node) { die "Level 2 node not found for selected node (RL $rootlevel ord $l2_order) with level > 3 "; };

		my $subtree = $tree->_getNewObj();
		$subtree->loadtree(
			$selected->{id},
			2,
		);

		my $sibtree = $tree->_getNewObj();
		
		if ($subtree->getChild(0)->getChildCount()>0) {
			#У выбранной ноды есть чайлды. Нужно догрузить соседей выбранной ноды
			$sibtree->loadtree(
				$selected->{parent_id}, # подгружаем по родителю
				2,     # только соседей
			);
			my $nv = $sibtree->getChild(0)->getNodeValue();
			$nv->{name}="...";
			$sibtree->getChild(0)->setNodeValue($nv);
			$l2_node->addChild($sibtree->getChild(0));
			$l2_node->{_first_child_order} = $sibtree->getChild(0)->{_order};
			my $selected_node = $sibtree->getNodeById($selected->{id});
			$selected_node->addChildren($subtree->getChild(0)->getAllChildren());
			$selected_node->{_last_child_order} = $subtree->getChild(0)->{_last_child_order};
		}
		else {
			#У выбранной ноды нет чайлдов. Нужно догрузить соседей родителя выбранной ноды	
			if ($selected->{level}> $rootlevel + 4) {
				
				$sth=$dbh->prepare("select parent_id from $table where id = ?") or die $DBI::errstr;
				$sth->execute($selected->{parent_id}) or die $DBI::errstr;
				my $pparent_id = $sth->fetchrow();
				$sth->finish();
				
				$sibtree->loadtree(
					$pparent_id,            # подгружаем по родителю
					2,   # только соседей
				);			
				my $nv = $sibtree->getChild(0)->getNodeValue();
				$nv->{name}="...";
				$sibtree->getChild(0)->setNodeValue($nv);
				$l2_node->addChild($sibtree->getChild(0));
				my $selected_node = $sibtree->getNodeById($selected->{parent_id});
				$selected_node->loadChilds();
				$selected_node->getNodeById($selected->{id})->{_childs_loaded} = 1 ;  ## interface only specific 
			}
			else {
				$l2_node->loadChilds();

				$sibtree->loadtree(
					$selected->{parent_id}, # подгружаем по родителю
					2,     # только соседей, 
				);

				my $selected_node = $l2_node->getNodeById($selected->{parent_id}) or die("l3 node nf");
				$selected_node->addChildren($sibtree->getChild(0)->getAllChildren());
				$selected_node->{_childs_loaded} = 1;
				$selected_node->{_last_child_order} = $sibtree->getChild(0)->{_last_child_order};
			};
		};
		return $tree;		
	};
	$tree->{_loaded} = 1;
	return $tree;
}

sub loadtree {
	my $self = shift;
	my $root_id = shift;
	my $levels = shift || 0;
    
    $self = $self->new() unless ref $self;
	
	croak ("NG::Nodes::loadtree(): node has loaded already") if ($self->{_loaded} == 1);
	
	my $dbh   = $self->db()->dbh();
	my $table = $self->table();
	my $fields= $self->fields();
	my $where = $self->{_dbwhere};
	my $join  = $self->join();
	
	my $root_next_node_order = "";
	
	if (defined $root_id) {
	    #Находим рутовую ноду
	    my $sql = "select main.id,main.parent_id,main.tree_order,main.level ".(($fields)?",$fields":"")." from $table as main $join where main.id=?" .(($where)?" and $where ":"");
	    my $sth=$dbh->prepare($sql) or die $DBI::errstr;
	    $sth->execute($root_id) or die $DBI::errstr;
	    my $rootrow = $sth->fetchrow_hashref() || croak "loadtree: Root not found";
		
		if ($levels) {
			$levels += $rootrow->{level}-1;
		};
		
		$self->setNodeValue($rootrow);
		
	    #Находим границы запрашиваемого поддерева
	    $sql = "select min(main.tree_order) from $table as main where main.tree_order>? and main.level<=?" .(($where)?" and $where ":"");
	    $sth=$dbh->prepare($sql) or die $DBI::errstr;
	    $sth->execute($rootrow->{tree_order},$rootrow->{level}) or die $DBI::errstr;
	    $root_next_node_order = $sth->fetchrow();
		
	    if ($root_next_node_order) {
			#TODO: условие проверки root_next_node_order может быть "<"
	        $where .= (($where)?" and ":"")."main.tree_order>=".$rootrow->{tree_order}." and main.tree_order<=".$root_next_node_order;
	    } else {
	        $where .= (($where)?" and ":"")."main.tree_order>=".$rootrow->{tree_order};
	    };
        # Для стыковки объекта дерева и объектов нод.
        # Эти ключи в конце процедуры будут удалены.
	    $self->{_id} = $rootrow->{parent_id};
		$self->{_level} = $rootrow->{level}-1;
	} else {
        if ($levels) {
            my $sql = "select level from $table order by tree_order limit 1";
            my $sth = $dbh->prepare($sql) or die $DBI::errstr;
            $sth->execute() or die $DBI::errstr;
            my $rootrow = $sth->fetchrow_hashref();
            $sth->finish();
            $levels += $rootrow->{level}-1 if $rootrow;
        };
	};
	
	if ($levels) {
		$where = (($where)?" $where and ":"")."main.level<=$levels";
	};

#die $where;
	
	my $sql="select main.id,main.parent_id,main.tree_order,main.level".(($fields)?",$fields":"")." from $table as main $join ".(($where)?"where $where ":"")." order by main.tree_order";
	my $sth=$dbh->prepare($sql) or die $DBI::errstr;
	$sth->execute() or die $DBI::errstr;
	
	my @level_roots = ($self);
	my $new_node;
	$new_node->{_id}=0;
	while (my $row = $sth->fetchrow_hashref()) {
		if ($new_node->{_id}==$row->{parent_id}) {
			$new_node->{_first_child_order} = $row->{tree_order};
		};

		# Создаем ноду		
		$new_node = $self->new();
		# Выставляем значения данных и инициализируем
		$new_node->setNodeValue($row);
		$new_node->{_id} = $row->{id};
		$new_node->{_parent_id} = $row->{parent_id};
		$new_node->{_order} = $row->{tree_order};
		$new_node->{_level} = $row->{level};
		if ((!$levels) || (($levels) && ( $row->{level}<$levels ))) {
			$new_node->{_childs_loaded}=1; 
		};
		
		if ($root_next_node_order && $new_node->{_order} == $root_next_node_order) {
			$self->{_next_sibling_order} = $root_next_node_order if ($new_node->{_level}==$self->{_level});
			next; # Xmm... it must be last record
		};
		
	    # Ищем рутовую ноду для данной ноды 
		for (;;) {
			my $root = $level_roots[$#level_roots];
            
            if ($root eq $self && !defined $root_id) {
                $root->{_id} = $new_node->{_parent_id} if !exists $root->{_id};
                $root->{_level} = $new_node->{_level}-1 if !exists $root->{_level};
            };

			if ($new_node->{_parent_id} == $root->{_id}) {
			    # нашли рутовую ноду, продолжаем ветку рутовых нод вправо
			    $root->addChild($new_node);
				$root->{_childs_loaded}=1;
			    $root->{_last_child_order} = $new_node->{_order};
                die "Level of node ".$new_node->{_id}." (".$new_node->{_level}.") != level+1=".($root->{_level}+1). " of parent ". $root->{_id} if $new_node->{_level} != $root->{_level}+1;
			    push @level_roots,$new_node;
			    last;
			};

# Дампим стек рутовых нод
#      for (my $i=0;$i<=$#level_roots;$i++) {
#          my $node = $level_roots[$i];
#          print $node->{_id}."\t";
#      }
#      print "\n";

			# Если новая нода и предыдущая находятся на одном уровне, то пропишем её как соседа. next_sibling
			if ($root->{_parent_id} == $new_node->{_parent_id}) {
				$root->{_next_sibling_order} = $new_node->{_order};
			}
			# не нашли рутовую ноду. Двигаемся влево
			if ($#level_roots) {
				pop @level_roots;
			} else {
				croak "loadtree: Invalid data in table '$table'. Can`t find parent for node id=".$row->{id};
			}
		}
	};
    $sth->finish();
	$self->{_loaded} = 1;
    delete $self->{_id};
    delete $self->{_level};
    $self;
};

sub printToTemplate {
	my $self = shift;
	my $template = shift || die ("printToTemplate: \$template not specified");
	my $name = shift || die ("printToTemplate: template variable name not specified");
	my $selected_id = shift || 0;
	
    my @rows=();
    my @stack=();
    $self->traverse(
    	sub {
            my ($_tree) = @_;
    	    
    	    if ($_tree->getDepth()==0) { @stack=(); } else { splice @stack,$_tree->getDepth();  };
    	    $stack[$_tree->getDepth()] = $_tree;
    	    
            my @levels=();
            for (my $i=0; $i <= $_tree->getDepth();$i++) {
                my $root = $stack[$i];
                my $is_last = ($stack[$i-1]->{_last_child_order}) && ($stack[$i-1]->{_last_child_order} == $root->{_order});
                if ($i == $_tree->getDepth()) {
                    if ($root->isLeaf) {
                        if ($is_last)  {        	
                            push @levels,{IS_JOINB=>1};
                        }
                        else {
                            push @levels,{IS_JOIN=>1};
                        }
                    }
                    else {
                        if ($is_last) {
                            push @levels,{IS_MINUSB=>1};
                        }
                        else {
                            push @levels,{IS_MINUS=>1};
                        };
                    };
                }
                else {
                    if ($is_last) {
                        push @levels, {IS_BLANK=>1};
                    }
                    else {
                        push @levels, {IS_LINE=>1};
                    };
                };
            };
            #Картинка
			if ($_tree->{_childs_loaded}) {
				if (($_tree->isLeaf()) && ($_tree->{_id} ne $selected_id)) {
					push @levels, {IS_LEAF=>1};
				}
				else {
					push @levels, {IS_FOLDERO=>1};
				};
			}
			else {
				if ($_tree->{_id} ne $selected_id) {
					push @levels, {IS_FOLDER=>1};
				} else {
					push @levels, {IS_FOLDERO=>1};
				};
			};
			
			shift @levels;
            push @rows, {
				LEVELS=>\@levels,
				SELECTED=>(($selected_id==$_tree->{_id})?"1":"0"),
				%{$_tree->getNodeValue()},
    	    };
    	}
    );
	$template->param($name=>\@rows);
};

sub printToDivTemplate {
    my $self = shift;
    my $template = shift || die ("printToTemplate: \$template not specified");
    my $name = shift || die ("printToTemplate: template variable name not specified");
    my $selected_id = shift || 0;
    my $baseLevel=$self->getDepth()+1;

    my @elements=();
	my @stack = ();
	
    $self->traverse(
        sub {
            my ($_tree)=@_;
			my $row =  { %{$_tree->getNodeValue()} };
			
my $f = "";
			
			#Выгружаем из стека 
			for (;;) {
				last if ($#stack < 0);
				my $stackTop = $stack[$#stack];
				last if ($_tree->getDepth() > $stackTop->{NODE}->getDepth());
				pop @stack;
				
				push @elements,{
					NODE_END => 1,
					%{$stackTop->{ROW}},
				};
			};

			if (!$_tree->{'_next_sibling_order'}) {
				$row->{'LAST_CHILD'}   = 1;
$f.=" L_CHLD";
			};
            
            if ($_tree->getDepth() == $baseLevel) {
				if ($_tree->isLeaf() && !$_tree->{_has_childs} ) {
					$row->{LEVEL0_LEAF} = 1;
$f.=" L0_L";
				}
				else {
					$row->{LEVEL0_FOLDER} = 1;
$f.=" L0_F";
				};
			}
			else {
				if ($_tree->isLeaf() && !$_tree->{_has_childs}) {
					$row->{LEVEL_LEAF} = 1;
$f.=" L_L";
				}
				else {
					$row->{LEVEL_FOLDER} = 1;
$f.=" L_F";
				};
			};
			
            if($_tree->{'_id'}==$selected_id) {
            	$row->{'IS_SELECTED'}=1;
$f.=" IS_SLCTD";
            };
            
            if ($_tree->isLeaf() && $_tree->{_has_childs}) {
                #Надо нарисовать папку с плюсиком
                $row->{CHILDS_CLOSED} = 1;
				$f.=" CH_CLSD";
            };
			
$row->{NODEDEBUG}.=$f;
			
			push @elements, {
				NODE_START => 1,
				%{$row},
			};
			
			push @stack, {
				NODE => $_tree,
				ROW  => $row,
			};
        }
    );
	
	for (;;) {
		last if ($#stack < 0);
		my $stackTop = $stack[$#stack];
		pop @stack;
		push @elements,{
			NODE_END => 1,
			%{$stackTop->{ROW}},
		};
	};
    $template->param($name=>\@elements);
};

## TODO: переименовать метод
sub loadPartOfTree2 {
	my $tree=shift;
	my $root_id = shift;
    my $config = shift || {};
    
    $tree = $tree->new() unless ref $tree;

	my $dbh   = $tree->db()->dbh();
	my $table = $tree->table();
	my $fields= $tree->fields();
    my $join  = $tree->join();
	
    die "loadPartOfTree2: config is not hash" if (ref $config ne "HASH");
    croak ("NG::Nodes::loadChilds(): node has loaded already") if ($tree->{_loaded} == 1);
    
    my $id = $config->{SELECTEDNODE};
    my $ol = $config->{OPEN_LEVELS} || 2;
    my $collapse = $config->{COLLAPSE_FIELD} || ""; # 

	$tree->loadtree($root_id,$ol + 1);  #Загружаем нужное число уровней + 1 для определения наличия childs

    my $selected = undef;  #ряд таблицы для выбранной ноды
    my $path = undef;      #хэш по level пути к выбранной ноде
    my $link_node = undef; #Нода, в которую будет подставляться дерево к выбранной ноде
    if ($id) {
        # Загружаем выбранную ноду.
        my $sth=$dbh->prepare("select main.id,main.parent_id,main.tree_order,main.level from $table as main $join where main.id=?") or die $DBI::errstr;    
        $sth->execute($id) or die $DBI::errstr;
        $selected=$sth->fetchrow_hashref();
        $sth->finish();
        
        #Находим путь к выбранной ноде
        my $sql = "select main.id,main.tree_order,main.level from $table as main $join, (select max(tree_order) as maxorder from $table where tree_order <=? and level <=? group by level) o
            where main.tree_order=o.maxorder and main.level>0 order by main.tree_order";
        $sth = $dbh->prepare($sql) or die $DBI::errstr;
        $sth->execute($selected->{tree_order},$selected->{level}) or die $DBI::errstr;
            
        $path = $sth->fetchall_hashref('level');
        $sth->finish();
    };

    #вырезаем чайлдов, которые находятся ниже чем порог, заодно ищем стык для дерева с выбранной нодой
	my $rootlevel = $tree->getChild(0)->{_level}-1;
    $tree->traverse(
        sub {
            my ($_tree)=@_;
			my $row =  { %{$_tree->getNodeValue()} };
            
            if ($_tree->{_level} == $rootlevel + $ol) {
                my $t = 0;
                foreach my $child ($_tree->getAllChildren()) {
                    $_tree->removeChild($child);
                    $t = 1;
                };
                $_tree->{_has_childs} = $t;
                
                if ($path && exists $path->{$rootlevel+$ol} && $_tree->{_id} == $path->{$rootlevel+$ol}->{id}) {
                    $link_node = $_tree;
                };
            }
            elsif ($collapse && $row->{$collapse}) {
                unless ($path && exists $path->{$_tree->{_level}} && $_tree->{_id} == $path->{$_tree->{_level}}->{id}) {
                    my $t = 0;
                    foreach my $child ($_tree->getAllChildren()) {
                        $_tree->removeChild($child);
                        $t = 1;
                    };
                    $_tree->{_has_childs} = $t;
                };
            };
        }
    );
    
	return $tree if (!defined($id)); 		# Загрузили первый второй уровень и успокоились.
    return $tree if (!defined $selected );   # XXX id exists but node is not found by this id ...
	return $tree if ($selected->{level} < $rootlevel+$ol); # выбранная нода и её потомки уже загружены
	die "LINK NODE NOT FOUND" unless $link_node;
	return $tree if ($link_node->{_has_childs} == 0); #У ноды отсутствуют чайлды
	
    #Загружаем все дерево от $path->{$rootlevel+$ol} до $selected->{level} + 1
    my $subtree = NG::Nodes->new();
    $subtree->initdbparams(
        db    =>$tree->db(),
        table =>$tree->table(),
        fields=>$tree->fields(),
    );
    #Загружаем три уровня: саму ноду, её детей и их детей для определения их наличия
    $subtree->loadtree(
        $path->{$rootlevel+$ol}->{id},
        $selected->{level} - $path->{$rootlevel+$ol}->{level} + 3,
    );
    #Чистим детей, для нод, которые не лежат на пути к выбранной ноде
    $subtree->traverse(
        sub {
            my ($_tree)=@_;
            
            if ($_tree->{_level} > $selected->{level} || $path->{$_tree->{_level}}->{id} != $_tree->{_id}) {
                my $t = 0;
                foreach my $child ($_tree->getAllChildren()) {
                    $_tree->removeChild($child);
                    $t = 1;
                };
                $_tree->{_has_childs} = $t;
            };
        }
    );
    $link_node->addChildren($subtree->getChild(0)->getAllChildren());
    return $tree;
};

sub loadBranchToNode {
    my $tree = shift;
    my $nodeId = shift;
    my $levels = shift || 2;
    
    defined $nodeId or die "loadBranchToNode(): no nodeId";
    
	my $dbh   = $tree->db()->dbh();
	my $table = $tree->table();
    my $join  = $tree->join();
  
    # Загружаем выбранную ноду.
    my $sth=$dbh->prepare("select main.id,main.parent_id,main.tree_order,main.level from $table as main $join where main.id=?") or die $DBI::errstr;    
    $sth->execute($nodeId) or die $DBI::errstr;
    my $selected=$sth->fetchrow_hashref();
    $sth->finish();
    
    return $tree if (!defined $selected );   # XXX id exists but node is not found by this id ...
    #return $tree if ($selected->{level} < $rootlevel+$ol); # выбранная нода и её потомки уже загружены
    
    #Находим путь к выбранной ноде
    my $sql = "select main.id,main.tree_order,main.level from $table as main $join, (select max(tree_order) as maxorder from $table where tree_order <=? and level <=? group by level) o
        where main.tree_order=o.maxorder order by main.tree_order";
    $sth = $dbh->prepare($sql) or die $DBI::errstr;
    $sth->execute($selected->{tree_order},$selected->{level}) or die $DBI::errstr;
    my $path = $sth->fetchall_hashref('level');
    $sth->finish();
#use Data::Dumper;
#print STDERR Dumper($path);
#print STDERR $nodeId;
    my $linkNode = undef; #Нода, в которую будет подставляться дерево к выбранной ноде
    $linkNode = $tree;
    my $prevLinkNode = undef;
    while (1) {
        die "Selected node not belongs to tree" if ($path->{$linkNode->{_level}}->{id} ne $linkNode->{_id});
#print STDERR "NODE ".$linkNode->{_id}." LEVEL ".$linkNode->{_level};
        last if $linkNode->{_id} eq $nodeId;
        last unless $linkNode->getChildCount() > 0;
        $prevLinkNode = $linkNode;
        foreach my $_child ($linkNode->getAllChildren()) {
            if ($path->{$_child->{_level}}->{id} == $_child->{_id}) {
                $linkNode = $_child;
                last;
            }
        };
        die "No child found to attach selected node tree" if $prevLinkNode eq $linkNode;
        $prevLinkNode = $linkNode;
    };
    #Чтобы работала подсветка наличия чайлдов для нод граничного уровня, надо загрузить для них еще уровень ниже
    $linkNode = $linkNode->getParent(); 
#print STDERR "LOADING root=".$linkNode->{_id}." LEVELS ".($selected->{level} - $linkNode->{_level} + $levels);
    #Загружаем все дерево от $path->{$rootlevel+$ol} до $selected->{level} + 1
    my $subtree = $tree->_getNewObj();
    #Загружаем три уровня: саму ноду, её детей и их детей для определения их наличия
    $subtree->loadtree(
        $linkNode->{_id},
        $selected->{level} - $linkNode->{_level} + $levels,
    );
    
    for (my $i = $linkNode->getChildCount() - 1; $i >= 0; $i--) {
        $linkNode->removeChildAt($i);
    };
        
    $linkNode->addChildren($subtree->getChild(0)->getAllChildren()) if $subtree->getChild(0)->getChildCount();
    $tree;
};

=head
    $node->collapseBranch($opts):
    Схлопывает все ветки, ноды которых удовлетворяют условию:
    1. Нода не на пути к выбранной ноде, и значения $opts->{KEY} в ноде == 1
    2. Нода не на пути к выбранной ноде, и уровень ноды > разрешенного количества _в дереве_ $opts->{MAXLEVELS}
    Выбранная нода задается параметром opts->{SELECTEDNODE}
=cut
sub collapseBranch {
    my $tree = shift;
    my $opts = shift || {};  

    die "treeCollapse(\$opts) is not HASHREF" unless ref $opts eq "HASH";
    return $tree unless exists $opts->{MAXLEVELS} || exists $opts->{KEY};
    
    my $sNode = $opts->{SELECTEDNODE};
    die "SELECTEDNODE is invalid object" if defined $sNode && ref $sNode && !$sNode->isa(__PACKAGE__);
    $sNode = $tree->getNodeById($sNode) if defined $sNode && ref $sNode eq '';
#die $sNode->{_id};
    my $path = undef;
    if ($sNode) {
        my $t = $sNode;
        while ($t) {
            $path->{$t->{_level}} = $t->{_id};
            $t = $t->getParent();
            last if $t eq $tree;
            last if $t eq Tree::Simple->ROOT;
        };
        die "SELECTEDNODE object is from other tree" unless $t eq $tree;
    };
    
#    my $rootlevel = $tree->{_level} - 1;
#    $tree->traverse(
#        sub {
#            my ($_tree)=@_;
#            #Не трогаем ноды, которые лежат на пути к выбранной ноде
##print STDERR "NODE ".$_tree->{_id}." exists ".(exists $path->{$_tree->{_level}} && $_tree->{_id} == $path->{$_tree->{_level}})?"1":"0";
#            #return 1 if exists $path->{$_tree->{_level}} && $_tree->{_id} == $path->{$_tree->{_level}};
#      
#            #не трогаем ветку ниже чем выбранная нода
#            return 1 if $sNode && $_tree->{_level} > $sNode->{_level};
#            
#            #1)Удаляем чайлдов у нод, которые находятся на максимальном уровне,
#            #ограничивая тем самым максимальное количество уровней в дереве
#            #2)Схлопываем ноды с $opts->{KEY}
#            if (
#                ($opts->{MAXLEVELS} && $_tree->{_level} >= $rootlevel + $opts->{MAXLEVELS})
#                || ($opts->{KEY} && $_tree->getNodeValue()->{$opts->{KEY}})
#                ) {
#                my $t = 0;
#                foreach my $child ($_tree->getAllChildren()) {
#                    $t = 1;
#                    next if $path->{$child->{_level}} eq $child->{_id};
#                    $_tree->removeChild($child);
#                };
#                $_tree->{_has_childs} = $t;
#            };
#        }
#    );

    my $cleanFunction = sub {
        my $_tree = shift;
        my $t = $_tree->{_has_childs};
        foreach my $child ($_tree->getAllChildren()) {
            $t = 1;
            #next if $path && $path->{$child->{_level}} eq $child->{_id};
            $_tree->removeChild($child);
        };
        $_tree->{_has_childs} = $t;
    };

    my $rootlevel = $tree->{_level} - 1;
#print STDERR "ROOTLEVEL $rootlevel MAXLEVELS=".$opts->{MAXLEVELS};
    $tree->traverse (
        sub {
            my $_tree = shift;
            
            while (1) {
                #Ноду надо схлопнуть, поскольку её childs ниже требуемого MAXLEVELS уровня
                #или у неё выставлено значение KEY
                unless (($opts->{MAXLEVELS} && $_tree->{_level} >= $rootlevel + $opts->{MAXLEVELS}) || ($opts->{KEY} && $_tree->getNodeValue()->{$opts->{KEY}})) {
                    last;
                };
                my $t = $_tree->getParent();
                #Если у родителя удалили детей в cleanFunction,
                #то эти дети всё еще попадут в этот вызов, ибо они уже в traverse()
                #Но у них уже не будет родителя....
                last if $t eq Tree::Simple->ROOT;
                
                #Ноду не надо схлопывать, поскольку она лежит на элементе пути.
                last if $path && $path->{$_tree->{_level}} && $path->{$_tree->{_level}} eq $_tree->{_id};
                
                #Схлопываем.
                &$cleanFunction($_tree);
                last;
            };
        }
    );

    #1) Если есть opts.KEY проверяем что нода не лежит на пути, и удаляем всех её чайлдов если data->{KEY}=1
    #2) opts.MAXLEVELS Если уровень ноды больше или равен максимального, и не лежит на пути SELECTEDNODE
    #3) потомки SELECTEDNODE не Удаляются.

    $tree;
};

## Usage sample
#
#   my $tree = NG::Nodes->new();
#   $tree->initdbparams(
#       db    =>$self->db(),
#       table =>"ng_sitestruct",
#       fields=>$fields,
#   );
#
#   $tree->loadtree(...);
#   $tree->loadNode($id) or return "error";

#   NG::Nodes->initdbparams(
#       db    =>$self->db(),
#       table =>"ng_sitestruct",
#       fields=>$fields,
#   );
#   my $node1 = NG::Nodes->loadNode($id);
#   my $node2 = NG::Nodes->loadNode(id=>$id);
#   my $node3 = NG::Nodes->loadNode(tree_order=>$tree_order);
#
#


return 1;
END{};
