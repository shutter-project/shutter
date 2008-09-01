#Copyright (C) Mario Kemper 2008 <mario.kemper@googlemail.com> Mi, 09 Apr 2008 22:58:09 +0200 

#This program is free software: you can redistribute it and/or modify
#it under the terms of the GNU General Public License as published by
#the Free Software Foundation, either version 3 of the License, or
#(at your option) any later version.

#This program is distributed in the hope that it will be useful,
#but WITHOUT ANY WARRANTY; without even the implied warranty of
#MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#GNU General Public License for more details.
#
#You should have received a copy of the GNU General Public License
#along with this program.  If not, see <http://www.gnu.org/licenses/>.

package GScrot::UbuntuPics;
use strict;
our(@ISA, @EXPORT);
use Exporter;
my $VERSION = 1.00;
@ISA = qw(Exporter);

@EXPORT = qw(&fct_upload_ubuntu_pics);

use WWW::Mechanize;
use HTTP::Status;

##################public subs##################
sub fct_upload_ubuntu_pics
{
	my ($upload_filename, $username, $password, $debug, $gscrot_version) = @_;

	my %links; #returned links will be stored here

	my $filesize = -s $upload_filename;
	if($filesize > 2048000){
		$links{'status'} = "FILESIZE_EXCEEDED";
		return %links;			
	} 
	
	my $mech = WWW::Mechanize->new(agent => "GScrot $gscrot_version");
	
	if($username ne "" && $password ne ""){

		$mech->get("http://www.ubuntu-pics.de/login.html");
		$mech->form_number(2);
		$mech->field(name => $username);
		$mech->field(passwort => $password);
		$mech->click("login");

		my $http_status = $mech->status();
		unless(is_success($http_status)){
			$links{'status'} = $http_status; return %links;
		}
		if($mech->content =~/Diese Login Daten sind leider falsch/){
			$links{'status'} = "LOGIN_FAILED"; return %links;	
		}  
		$links{status}='OK Login';

	}
	
	$mech->get("http://www.ubuntu-pics.de/easy.html");

	$mech->submit_form(
		form_name 	=> 'upload_bild',
		fields      => {
			"datei[]"    => $upload_filename,
			}
		);
				
	my $http_status = $mech->status();

	if (is_success($http_status)){
		my $html_file = $mech->content;

		$html_file =~ /id="thumb1" value='(.*)' onclick/g;
		$links{'thumb1'} = &function_switch_html_entities($1);

		$html_file =~ /id="thumb2" value='(.*)' onclick/g;
		$links{'thumb2'} = &function_switch_html_entities($1);

		$html_file =~ /id="bbcode" value='(.*)' onclick/g;
		$links{'bbcode'} = &function_switch_html_entities($1);
		
		$html_file =~ /id="ubuntucode" value='(.*)' onclick/g;
		$links{'ubuntucode'} = &function_switch_html_entities($1);
		
		$html_file =~ /id="direct" value='(.*)' onclick/g;
		$links{'direct'} = &function_switch_html_entities($1);

		if ($debug){
			print "The following links were returned by http://www.ubuntu-pics.de:\n";
			print "Thumbnail for websites (with Border)\n$links{'thumb1'}\n";
			print "Thumbnail for websites (without Border)\n$links{'thumb2'}\n";
			print "Thumbnail for forums \n$links{'bbcode'}\n";
			print "Thumbnail for Ubuntuusers.de forum \n$links{'ubuntucode'}\n";
			print "Direct link \n$links{'direct'}\n";
		}
		
		$links{'status'} = $http_status;
		return %links;
		
	}else{
		$links{'status'} = $http_status;
		return %links;	
	}
}

##################private subs##################
sub function_switch_html_entities
{
	my ($code) = @_;
	$code =~ s/&amp;/\&/g;
	$code =~ s/&lt;/</g;
	$code =~ s/&gt;/>/g;
	$code =~ s/&quot;/\"/g;
	return $code;		
}

1;
