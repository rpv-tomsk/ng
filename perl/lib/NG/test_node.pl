#!/usr/bin/perl 

use lib ('/web/ladybird.ru/perl/lib','/web/siam.ru/perl/lib','/web/zaometnew.ru/perl/lib','../');

use strict;
#use NGcms;
#use NGcms::Mysql;
#use NGService;


# my $tree = NGTree->new();
# print ref $tree;
# print "\n";
# my $node = $tree->LoadNode(1);
# print ref $node;


    use NG::Nodes;
#    use Tnews::Config;
#    %NGcms::config = %Tnews::Config::config; 

#    NGcms::Initialise();
#    NGcms::Mysql::Initialise();
    
#    use Ladybird::DB;
#    my $db = Ladybird::DB->new();
    use Metallist::DB;
    my $db = Metallist::DB->new();
    
#    $dbh->trace(15,"log");
    
#    my $data;
#    $data->{'id'}=50;
    
#    my $sth = $dbh->prepare("insert into news(id,header,short_text,full_text,section_id,is_news,image_big,image_sm,author_id,issue_id,source,news_date,attent) values (?,?,?,?,?,?,?,?,?,?,?,?,?)") or showerror_to_resblock("prepare".$DBI::errstr);
#    $sth->execute(hashref_array_sql("id,header,short_text,full_text,section_id,is_news,image_big,image_sm,author_id,issue_id,source,news_date,attent",$data)) or showerror_to_resblock("exec".$DBI::errstr);
#    $sth->finish();

#    exit();

    my $tree = NG::Nodes->new();
    $tree->initdbparams(
            db=>$db,
            table=>"catalog_sections",
#            where=>"",
            fields=>"name",
    );
#    $tree->loadNode(14) or die ("cant find node");
##    $tree->DBmoveNodeUp(); # or die ("cant move node");
#    $tree->DBmoveNodeDn();
#    exit();

    $tree->loadNode(0) or die("Cant find node");   $tree->DBaddChild("name"); exit();

    
    my $id = 40;
    $tree->loadtree($id);
#    $tree->printSubtree();   #exit();
    my $sth_ = $tree->{_db}->dbh()->prepare("update ".$tree->{_dbtable}." set url=? where id=?") or die $DBI::errstr;    
    $tree->traverse(
        sub {
    	    my $_tree = shift;
    	    my $value = $_tree->getNodeValue();
	    my $parent = $_tree->getParent();
	    print "$_tree->{_id} $parent->{_id} $tree->{_id} URL:".$value->{url}."  -";
	    if ($_tree->{_id} != $id) {
		    my $parent_value = $parent->getNodeValue();
    		    my $parent_url = $parent_value->{url} ||"";
		    #my $parent_url = $_tree->getParent()->getNodeValue()->{url};
    		    $value->{url} =~ s/.*\/([^\/]+\/)$/$parent_url$1/;
		    print "$_tree->{_id} PU:$parent_url TO:$value->{url}\n";
#		    $sth_->execute($value->{url},$_tree->{_id}) or die $DBI::errstr;
	    };
	}
    );    
    exit();
#    $tree->printNode();
#    print "\n";
#    $tree->printSubtree();   exit();
    
#    $tree->loadNode(21) or die("Cant find node");   $tree->DBaddChild("name","url"); exit();
#    $tree->DBdelete();
#    $tree->printNode();

#    $tree->printSubtree();
    
    exit();
    

 
 $tree->addChild(NGNodes->new("1"));
 my $sub_tree = NGNodes->new("2", $tree);
 # chain method calls
 $tree->getChild(0)->addChild(NGNodes->new("1.1"));
 
 $sub_tree->addChildren(
                 NGNodes->new("2.1"),
                 NGNodes->new("2.2")
                           );

 # add siblings
 $sub_tree->addSibling(NGNodes->new("3"));
                
 # insert children a specified index
 $sub_tree->insertChild(2,NGNodes->new("2.2a"));

 $tree->getChild(0)->{_order}=10;
 $tree->getChild(1)->{_order}=20;
 
 #print $tree->isRoot();
 $tree->printSubtree();