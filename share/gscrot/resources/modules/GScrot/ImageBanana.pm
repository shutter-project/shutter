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

package GScrot::ImageBanana;

our(@ISA, @EXPORT);
use Exporter;
my $VERSION = 1.00;
@ISA = qw(Exporter);

@EXPORT = qw(&fct_upload_imagebanana);

use utf8;
use strict;
use WWW::Mechanize;
use HTTP::Status;

##################public subs##################
sub fct_upload_imagebanana
{
	my ($upload_filename, $username, $password, $debug, $gscrot_version) = @_;

	my %links; #returned links will be stored here

	my $filesize = -s $upload_filename;
	my $max_filesize = 2048000;
	if($filesize > $max_filesize){
		$links{'status'} = 998;
		$links{'max_filesize'} = sprintf( "%.2f", $max_filesize / 1024 ). " KB";	
		return %links;			
	} 

	my $mech = WWW::Mechanize->new(agent => "GScrot $gscrot_version");
	my $http_status = undef;
	
	utf8::encode $upload_filename;
	utf8::encode $password;
	utf8::encode $username;
	if($username ne "" && $password ne ""){
		
		$mech->get("http://www.imagebanana.com/myib/login/");
		$http_status = $mech->status();
		unless(is_success($http_status)){
			$links{'status'} = $http_status; return %links;
		}
		$mech->form_number(1);
		$mech->field(nick => $username);
		$mech->field(password => $password);
		$mech->click("login");

		$http_status = $mech->status();
		unless(is_success($http_status)){
			$links{'status'} = $http_status; return %links;
		}
		if($mech->content =~ /Login nicht erfolgreich/){
			$links{'status'} = 999; return %links;
		}  
		$links{status}='OK Login';
		
	}
	
	$mech->get("http://www.imagebanana.com/");
	$http_status = $mech->status();
	unless(is_success($http_status)){
		$links{'status'} = $http_status; return %links;
	}
	$mech->form_number(1);
	$mech->field(img => $upload_filename);
	$mech->click("send");
		
	$http_status = $mech->status();
	if (is_success($http_status)){
		my $html_file = $mech->content;
		$html_file = &function_switch_html_entities($html_file);

		my @link_array;
		while($html_file =~ /value="(.*)" class/g){
			push(@link_array, $1);				
		}
		
		$links{'thumb1'} = $link_array[0];
		$links{'thumb2'} = $link_array[1];	
		$links{'thumb3'} = $link_array[2];		
		$links{'friends'} = $link_array[3];	
		$links{'popup'} = $link_array[4];	
		$links{'direct'} = $link_array[5];
		$links{'hotweb'} = $link_array[6];		
		$links{'hotboard1'} = $link_array[7];	
		$links{'hotboard2'} = $link_array[8];	

		if ($debug){
			print "The following links were returned by http://www.imagebanana.com:\n";		
			print $links{'thumb1'}."\n"; 
			print $links{'thumb2'}."\n";
			print $links{'thumb3'}."\n";	
			print $links{'friends'}."\n";
			print $links{'popup'}."\n";
			print $links{'direct'}."\n"; 
			print $links{'hotweb'}."\n"; 	
			print $links{'hotboard1'}."\n"; 
			print $links{'hotboard2'}."\n"; 
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
