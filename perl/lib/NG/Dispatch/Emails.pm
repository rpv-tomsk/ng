package NG::Dispatch::Emails;

use NGService;
use NSecure;
use NG::Form;
use NHtml;
use NG::DBlist;
use NG::Image;
use NG::Module;


use vars qw(@ISA);

sub AdminMode {
    use NG::Module::List;
    @ISA = qw(NG::Module::List);
};

sub config  {
    my $self = shift;
    $self->{_table} = "dispatch_emails";
    
    $self->fields(
        {FIELD=>'id',  	     TYPE=>'id',   NAME=>'Код'},
        {FIELD=>'email',      TYPE=>'email', NAME=>'E-mail подписчика', IS_NOTNULL=>1},
      );
    
    # Списковая
    $self->listfields([
        {FIELD=>'_counter_',NAME=>"№"},
        {FIELD=>'email'},
    ]);
    
    # Формовая часть
    $self->formfields(
        {FIELD=>'id'},
        {FIELD=>'email'},
    );
  
    $self->order("email");
    
    $self->filter(
  		NAME => "Категории подписчиков",
  		TYPE => "select",
  		VALUES=>[
  			  { NAME=>"Все записи", WHERE=>""},
  			  { NAME=>"Подписавшиеся", WHERE=>"subscribe_apply=0"},
  			  { NAME=>"Получающие рассылку", WHERE=>"subscribe_apply=1"},
  			  { NAME=>"Отписавшиеся", WHERE=>"unsubscribe_question=1"},
  		],
  	);  
};



return 1;