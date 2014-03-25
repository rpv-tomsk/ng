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
        {FIELD=>'id',  	     TYPE=>'id',   NAME=>'���'},
        {FIELD=>'email',      TYPE=>'email', NAME=>'E-mail ����������', IS_NOTNULL=>1},
      );
    
    # ���������
    $self->listfields([
        {FIELD=>'_counter_',NAME=>"�"},
        {FIELD=>'email'},
    ]);
    
    # �������� �����
    $self->formfields(
        {FIELD=>'id'},
        {FIELD=>'email'},
    );
  
    $self->order("email");
    
    $self->filter(
  		NAME => "��������� �����������",
  		TYPE => "select",
  		VALUES=>[
  			  { NAME=>"��� ������", WHERE=>""},
  			  { NAME=>"�������������", WHERE=>"subscribe_apply=0"},
  			  { NAME=>"���������� ��������", WHERE=>"subscribe_apply=1"},
  			  { NAME=>"������������", WHERE=>"unsubscribe_question=1"},
  		],
  	);  
};



return 1;