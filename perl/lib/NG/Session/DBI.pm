package NG::Session::DBI;
use strict;

use NG::Session;
use vars qw(@ISA);
@ISA = qw(NG::Session);

=head

������ ������� (��� ������ - Face):

[SessionFace]
Module = "NG::Session::DBI"

#��� ������� � ��������, �� ��������� session
TableName= 'session'

#�������������� ��������� ��������������� �����.�� ���������:
IdColName='id'
DataColName='a_session'

#��������� ���������, �������� - ���������� �� ����������.
DataSource=>'dbi:pg:dbname=project'
User = 'someUser'
Password = 'somePassword'

#���� �� ��������� ��������� ���������, ������������ �������� ���������� � �� �����.

#�������������� �����:
   ��� Postgresql:
    - ColumnType
=cut

sub getDSN {
    my $self=shift;
    
    my ($is_mysql, $is_pgsql) = (0,0);
    
    my $dsn    = "";
    my $params = {};
    #����� ���������
    $params->{'TableName'}=$self->getConfParam("TableName","sessions");
    if (my $p = $self->getConfParam("IdColName","")) {
        $params->{IdColName} = $p;
    };
    if (my $p = $self->getConfParam("DataColName","")) {
        $params->{DataColName} = $p;
    };
    
    #��������� ��������� ��������
    my $ds = $self->getConfParam("DataSource","");
    if ($ds) {
        $params->{'DataSource'} = $ds;
        $params->{'User'} = $self->getConfParam("User","");
        $params->{'Password'} = $self->getConfParam("Password","");
        
        if ($ds =~ /dbi:mysql/i) {
            $is_mysql = 1;
        }
        elsif ($ds =~ /dbi:pg/i) {
            $is_pgsql = 1;
        };
    }
    else {
        my $db = $self->app()->db();
        $params->{Handle} = $db->dbh();
        
        if ($db->isa("NG::DBI::Mysql")) {
            $is_mysql = 1;
        }
        elsif ($db->isa("NG::DBI::Postgres")) {
            $is_pgsql = 1;
        };
    };
    
    if ($is_mysql) {
        $dsn = "driver:mysql";
    }
    elsif ($is_pgsql) {
        if (my $p = $self->getConfParam("ColumnType","")) {
            $params->{ColumnType} = $p;
        };
        $dsn = "driver:PostgreSQL"; 
    }
    else {
        $dsn = "driver::DBI";
    };
    return ($dsn,$params);
};

return 1;
END{};