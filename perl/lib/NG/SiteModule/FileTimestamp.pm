package NG::SiteModule::FileTimestamp;
use strict;
use NG::Module;
our @ISA = qw(NG::Module);

=comment
    Использование:
    
    1) Использование как плагина
        Регистрируем модуль (например, с кодом TIMESTAMP)
        Заносим в блоки запись плагина, обязательно action=FILETIMESTAMP, значение code произвольно
        В параметры записи плагина пишем параметр требуемого файла относительно siteroot, пример: file: /htdocs/js/script.js
        В шаблоне обращаемся примерно так: <TMPL_VAR PLUGINS.TIMESTAMP_JS> - TIMESTAMP_JS - значение code из записи плагина
      
    2) Использование как модуля
        Регистрируем модуль (например, с кодом TIMESTAMP)
        В шаблоне обращаемся примерно так: <TMPL_VAR MODULES.TIMESTAMP_JS1>
        
        Имя файла будет взято из конфига:
        [MODULE_TIMESTAMP]
        File_JS1="/htdocs/js/combined.min.js"
=cut

sub getBlockContent {
    my ($self,$action,$keys,$params) = (shift,shift,shift,shift);
    
    my $cms = $self->cms();
    
    if ($action eq "FILETIMESTAMP") { #Plugin
        my $fName = $self->pluginParam('file') or return $cms->error('Plugin FILETIMESTAMP has no \'file\' parameter');
        
        my @v = stat($cms->getSiteRoot().$fName);
        return $cms->error("Plugin FILETIMESTAMP: file $fName was not found") unless scalar @v;
        
        return $cms->output($v[9]);
    };
    
    my $fName = $self->confParam('File_'.$action) or return $cms->error('Module NG::SiteModule::FileTimestamp : missing value for config file parameter MODULE_'.$self->getModuleCode().'.File_'.$action);

    my @v = stat($cms->getSiteRoot().$fName);
    return $cms->error("Module NG::SiteModule::FileTimestamp : file $fName was not found (Configfile parameter MODULE_".$self->getModuleCode().".File_$action)") unless scalar @v;
    
    return $cms->output($v[9]);
};

1;
