#!/usr/bin/perl -w

use Test::More tests => 24;
use Test::Exception;

use lib ('../perl/lib');
use NGPlugins;
use NG::PageModule;

#Some init...
NGPlugins->registerPlugin('NG::PageModule','Test::Module1',4);
NGPlugins->registerPlugin('NG::PageModule','Test::PageModuleAtEnd',8);
NGPlugins->registerPlugin('NG::Module','Test::Later',5);
NGPlugins->registerPlugin('NG::Module','Test::Module1',0);
#NGPlugins->registerPlugin('NG::Module','Test::Module2',8);
NGPlugins->registerPlugin('Site::PageModule','Test::SiteMenu::Plugin');

#Get some work result
use Site::PageModule;
my $o = {};
bless $o, "Site::PageModule";
#use Data::Dumper;

#This was needed for module fixes when writing these tests..
#print Dumper($NGPlugins::PLUGINS);
#exit();
my @got = ();

my @expectedClass1 = ('Test::Module1','Test::Later');  #For 'NG::Module'

#Проверяем вызов плагинов на статическую привязку
@got = NGPlugins->plugins('NG::Module','unexistent');
is_deeply(\@got,\@expectedClass1,'Plugin call sequence for class (1)');
@got = NGPlugins->plugins('NG::Module','unexistent');
is_deeply(\@got,\@expectedClass1,'Plugin call sequence for class (1), sequential requests ok. (caching check)');

#Вызываем плагины динамической привязки
my @expectedObject1 = ('Test::Module1','Test::SiteMenu::Plugin','Test::Later','Test::PageModuleAtEnd');
@got = NGPlugins->plugins($o,'unexistent');
is_deeply(\@got,\@expectedObject1,'Plugin call sequence for $object');
@got = NGPlugins->plugins($o,'unexistent');
is_deeply(\@got,\@expectedObject1,'Plugin call sequence for $object, sequential requests ok. (caching check) ');

#Регистрируем динамическую привязку
diag "Registered new plugin for object";
NGPlugins->registerPlugin($o,'Test::PageModule1');

#Снова проверяем вызов плагинов на статическую привязку. Ничего не должно измениться.
@got = NGPlugins->plugins('NG::Module','unexistent');
is_deeply(\@got,\@expectedClass1,'Plugin call sequence for class (1)');
@got = NGPlugins->plugins('NG::Module','unexistent');
is_deeply(\@got,\@expectedClass1,'Plugin call sequence for class (1), sequential requests ok. (caching check)');

#Вызываем плагины динамической привязки, с учетом новой регистрации
my @expectedObject2 = ('Test::Module1','Test::SiteMenu::Plugin','Test::PageModule1','Test::Later','Test::PageModuleAtEnd');
@got = NGPlugins->plugins($o,'unexistent');
is_deeply(\@got,\@expectedObject2,'Plugin call sequence for $object');
@got = NGPlugins->plugins($o,'unexistent');
is_deeply(\@got,\@expectedObject2,'Plugin call sequence for $object, sequential requests ok. (caching check) ');

#Регистрируем статическую привязку.
diag "Registered new plugin for class";
NGPlugins->registerPlugin('NG::Module','Test::Module2');

#Снова проверяем вызов плагинов на статическую привязку, с учетом новой регистрации
my @expectedClass2 = ('Test::Module1','Test::Module2','Test::Later');  #For 'NG::Module'
@got = NGPlugins->plugins('NG::Module','unexistent');
is_deeply(\@got,\@expectedClass2,'Plugin call sequence for class (1)');
@got = NGPlugins->plugins('NG::Module','unexistent');
is_deeply(\@got,\@expectedClass2,'Plugin call sequence for class (1), sequential requests ok. (caching check)');

#Вызываем плагины динамической привязки, с учетом новой регистрации
my @expectedObject3 = ('Test::Module1','Test::SiteMenu::Plugin','Test::Module2','Test::PageModule1','Test::Later','Test::PageModuleAtEnd');
@got = NGPlugins->plugins($o,'unexistent');
is_deeply(\@got,\@expectedObject3,'Plugin call sequence for $object');
@got = NGPlugins->plugins($o,'unexistent');
is_deeply(\@got,\@expectedObject3,'Plugin call sequence for $object, sequential requests ok. (caching check) ');

#Проверка наличия фантомных привязок на класс
diag "Check for plugins on classes without plugins registed";
my @expectedEmpty = ();
@got = NGPlugins->plugins('NG::NoModule','unexistent');
is_deeply(\@got,\@expectedEmpty,'Plugin call sequence for class (2) with no registered plugins.');
@got = NGPlugins->plugins('NG::NoModule','unexistent');
is_deeply(\@got,\@expectedEmpty,'Plugin call sequence for class (2), sequential requests ok. (caching check)');
#... и на объект
my $oo = {};
bless $oo, "Some::New::Module";
@got = NGPlugins->plugins($oo,'unexistent');
is_deeply(\@got,\@expectedEmpty,'Plugin call sequence for object (3) with no registered plugins.');
@got = NGPlugins->plugins($oo,'unexistent');
is_deeply(\@got,\@expectedEmpty,'Plugin call sequence for object (3), sequential requests ok. (caching check)');

diag "Check for Duplicate registrations catch";
throws_ok { NGPlugins->registerPlugin('NG::Module','Test::Module2',8); } qr/Duplicate registration/, 'Duplicate module registration catched';
throws_ok { NGPlugins->registerPlugin('NG::Module','Test::Module2',$NGPlugins::REAL_START); } qr/REAL_START can be used only once/, 'Duplicate registration to REAL_START position catched';
throws_ok { NGPlugins->registerPlugin('NG::PageModule','Test::Module2',$NGPlugins::REAL_END); } qr/REAL_END can be used only once/, 'Duplicate registration to REAL_END position catched';

@got = NGPlugins->plugins($o,'unexistent');
is_deeply(\@got,\@expectedObject3,'Plugin list for object is not corrupted by \'die\', thrown due duplicate found.');

diag "Check for references to objects in plugin system";
ok($Site::PageModule::CHECKDESTROY == 0, 'Object is alive');
$o = undef;
ok($Site::PageModule::CHECKDESTROY == 1, 'Object is destroyed when expected');

diag "Check for plugins on classes after unregistering object and all these tests";
@got = NGPlugins->plugins('NG::Module','unexistent');
is_deeply(\@got,\@expectedClass2,'Plugin call sequence for class (1)');
my @expectedClass3 = ('Test::Module1','Test::PageModuleAtEnd');  #For 'NG::PageModule'
@got = NGPlugins->plugins('NG::PageModule','unexistent');
is_deeply(\@got,\@expectedClass3,'Plugin call sequence for class (2)');

#Some packages for testing, as NGPlugins tries to 'use' them.
package Test::PageModule1;
package Test::Module1;
package Test::Module2;
package Test::Later;
package Test::PageModuleAtEnd;
package Test::SiteMenu::Plugin;

1;
