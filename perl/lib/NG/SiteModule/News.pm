package NG::SiteModule::News;
use strict;
use NG::PageModule;
our @ISA = qw(NG::PageModule);

sub moduleBlocks {
    return [{'URL'=>'/', 'BLOCK'=>'NG::SiteModule::News::List'}];
};

sub moduleTabs {
    return [{'URL'=>'/', 'HEADER'=>'Новости'}];    
};

sub getUploadDir {
    return '/upload/news/images/'
};

sub getUploadRtfDir {
    return '/upload/news/rtf/';    
}; 

package NG::SiteModule::News::List;
use strict;
use NG::Module::List;
use NGService;
our @ISA = qw(NG::Module::List);

sub config {
    my $self = shift;
    my $m = $self->getModuleObj();
    $self->{'_table'} = 'news';
    $self->fields(
        {'FIELD'=>'id', 'TYPE'=>'id'},
        {'FIELD'=>'page_id', 'TYPE'=>'pageId'},
        {'FIELD'=>'header', 'TYPE'=>'text', 'IS_NOTNULL'=>1, 'NAME'=>'Заголовок'},
        {'FIELD'=>'create_date', 'TYPE'=>'datetime', 'IS_NOTNULL'=>1, 'NAME'=>'Дата', 'DEFAULT'=>current_datetime()},
        {'FIELD'=>'stext', 'TYPE'=>'textarea', 'NAME'=>'Краткий текст'},
        {'FIELD'=>'ftext', 'TYPE'=>'rtf', 'NAME'=>'Текст',
            'OPTIONS'=>{
			    'CONFIG'=>'rtf',
				'IMG_TABLE'=>'news_images',
				'IMG_UPLOADDIR'=>$m->getUploadRtfDir(),
				'IMG_TABLE_FIELDS_MAP'=>{'id'=>'parent_id'}                
            }
        },
        {'FIELD'=>'image', 'TYPE'=>'image', 'NAME'=>'Изображение', 'UPLOADDIR'=>$m->getUploadDir(),
            'OPTIONS'=>{
                'STEPS'=>[
                    {'METHOD'=>'towidth', 'PARAMS'=>{'width'=>$self->cms->confParam("News.Width")}}
                ]
            }
        },
        {'FIELD'=>'source', 'TYPE'=>'text', 'NAME'=>'Источник'},
        {'FIELD'=>'source_url', 'TYPE'=>'url', 'NAME'=>'Ссылка на источник'}
    );   
    
    $self->formfields(
        {'FIELD'=>'id'},
        {'FIELD'=>'header'},
        {'FIELD'=>'create_date'},
        {'FIELD'=>'stext'},
        {'FIELD'=>'ftext'},
        {'FIELD'=>'image'},
        {'FIELD'=>'source'},
        {'FIELD'=>'source_url'}
    );
            
    $self->listfields(
        {'FIELD'=>'create_date'},
        {'FIELD'=>'header'},
        {'FIELD'=>'stext'}
    );            
                        
    $self->order({'DEFAULT'=>'DESC', 'DEFAULTBY'=>'DESC', 'FIELD'=>'create_date', 'ORDER_DESC'=>'create_date desc,id desc', 'ORDER_ASC'=>'create_date asc,id asc'});                        
                            
};

1;

=comment
    postgres sql
    create table news(
        id serial primary key not null,
        page_id int not null,
        header varchar(255) not null,
        create_date timestamp with time zone,
        stext text,
        ftext text,
        image varchar(255),
        source varchar(255),
        source_url varchar(255) 
    );
    
    create table news_images (
        id serial primary key not null,
        page_id int not null,
        parent_id int not null,
        filename varchar(255)
    );
    
=cut