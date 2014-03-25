package NG::SiteBlocks::FilesBlock;
use strict;
use NG::Module::List;
our @ISA = qw(NG::Module::List);

sub config {
    my $self = shift;
    
    $self->{'_table'} = $self->opts()->{'TABLE'};
    
    $self->fields(
        {'FIELD'=>'id', 'TYPE'=>'id'},
        {'FIELD'=>'page_id', 'TYPE'=>'pageId'},
        {'FIELD'=>'name', 'TYPE'=>'text', 'NAME'=>'Название', 'IS_NOTNULL'=>1},
        {'FIELD'=>'filename', 'TYPE'=>'file', 'UPLOADDIR'=>$self->opts()->{'UPLOADDIR'}, 'IS_NOTNULL'=>1, 'NAME'=>'Файл',
            'OPTIONS'=>{
                'ALLOWED_EXT'=>$self->opts()->{'ALLOWED_EXT'},
                'STEPS' => [
                    {'METHOD'=>'copyFileSize', 'PARAMS'=>{'field'=>'size'}},
                    {'METHOD'=>'copyFileExtension', 'PARAMS'=>{'field'=>'ext'}}
                ]                
            } 
        },
        {'FIELD'=>'size', 'TYPE'=>'text', 'NAME'=>'Размер', 'HIDE'=>1},
        {'FIELD'=>'ext', 'TYPE'=>'text', 'NAME'=>'Расширение', 'HIDE'=>1},        
        {'FIELD'=>'position', 'TYPE'=>'posorder', 'NAME'=>'Позиция'}
    );
    
    $self->formfields(
        {'FIELD'=>'id'},
        {'FIELD'=>'name'},
        {'FIELD'=>'filename'},
        {'FIELD'=>'size'},
        {'FIELD'=>'ext'},
    );
    
    $self->listfields(
        {'FIELD'=>'name'},
        {'FIELD'=>'size'},
        {'FIELD'=>'ext'},
        {'FIELD'=>'filename'},
    );
};

1;