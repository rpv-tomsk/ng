package NG::Field::Turing;
use strict;
use NG::Field;
use vars qw(@ISA);
@ISA = qw(NG::Field);
use NGTuring;
use NGService;
use NSecure;

sub prepareOutput {
	my $field = shift;
	$field->{IMAGE} = getURLWithParams($field->{IMAGEURL},"rand=".rand(10000));
	return 1;
};

sub init {
    my $field = shift;
    
    $field->SUPER::init(@_) or return undef;

	$field->pushErrorTexts({
        CODE_NOT_MATCH       => "Код не совпадает",
    });
	return 1;
};

sub check {
	my $field = shift;
	my $cms = $field->cms();
	
	my $value = $field->value();
    if (is_empty($value)) {
        return $field->setErrorByCode("IS_EMPTY");
    };
    my $tObj = $cms->getObject("NGTuring");
    if ($tObj->checkTuringInput(number => $value) != 1) {
        return $field->setErrorByCode("CODE_NOT_MATCH");
    }
	$tObj->resetSession() unless $field->{NORESETONSUCCESS};
	return 1;
};

sub getJSSetValue {
	my $field = shift;
	my $key_value = $field->parent()->getComposedKeyValue();
	my $fd = $field->{FIELD};
	
	return "parent.document.getElementById('timg_$fd$key_value').src='".getURLWithParams($field->{IMAGEURL},"rand=".rand(10000))."';" if $field->error();
	return "";
};

return 1;
