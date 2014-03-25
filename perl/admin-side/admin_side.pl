#!/usr/bin/perl -w
use strict;
use lib('/web/ng4/perl/lib','/web/prostobilet.ru/perl/lib'); 
use NG::Bootstrap;
NG::Bootstrap::importX(undef, App => 'NG::Adminside',DB=>'NG::DB',  SiteRoot=>'/web/ng4');
