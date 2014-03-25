package NG::FilesArchive;
use strict;
use NG::Module;
use vars qw(@ISA);
@ISA = qw(NG::Module);

sub moduleTabs {
    return [{HEADER=>"Файловый архив",URL=>"/"}];
};

sub moduleBlocks {
    return [{BLOCK=>"NG::FilesArchive::List",URL=>"/"}];
};

1;

package NG::FilesArchive::List;
use strict;
use NG::Module::List;
use vars qw(@ISA);
@ISA = qw(NG::Module::List);

sub getUploadDir {
    return "/upload/filesarchive/";
};

sub config {
    my $self = shift;
    $self->{_table} = "filearchive";
    
    $self->fields(
        {FIELD=>"id", TYPE=>"id",IS_NOTNULL=>1},
        {FIELD=>"name", TYPE=>"text", NAME=>"Название", IS_NOTNULL=>1},
        {FIELD=>"file", TYPE=>"file", NAME=>"Файл", IS_NOTNULL=>1,UPLOADDIR=>$self->getUploadDir(),
            OPTIONS=>{
                FILENAME_MASK => "{name}_{k}_{r}{e}"
            }
        },
        {FIELD=>"link", TYPE=>"text", NAME=>"Ссылка", IS_FAKEFIELD=>1}
    );
    
    $self->formfields(
        {FIELD=>"id"},
        {FIELD=>"name"},
        {FIELD=>"file"}
    );

    $self->listfields(
        {FIELD=>"name"},
        {FIELD=>"file"},
        {FIELD=>"link"}
    );
    
    $self->order({FIELD=>"id",DEFAULT=>1,DEFAULTBY=>"DESC"});
};

sub rowFunction {
    my $self = shift;
    my $row = shift;
    $row->{link} = $self->getUploadDir().$row->{file};
};

1;

=comment
    create table filearchive (
        id serial primary key not null, 
        name varchar(255) not null,
        file varchar(255) not null
    );
    
    create table filearchive (
        id int primary key not null auto_increment, 
        name varchar(255) not null,
        file varchar(255) not null
    );    
=cut