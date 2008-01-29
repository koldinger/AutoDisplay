#Autodisplay.pm
#Date: 5/11/2005
#Purpose: To allow automatic display brightness on-off at specific times.
#Author: Felix Mueller <felix.mueller(at)gwendesign.com>
#Redesigned for Slimserver 6.0+ by Tobias Goldstone <tgoldstone(at)familyzoo.net>
#
#	Copyright (c) 2004 - 2006 GWENDESIGN
#	All rights reserved.
#
#       Based on AlarmClock
#	And based on Autodisplay Revision .2 by Felix Mueller
#
#	History:
#	2006/12/24 v0.82 Minor bug fix.
#	2006/12/10 V0.81 24H time format does not save in Web UI
#	2006/11/12 V0.8 - Various bugfixes
#	2006/09/24 v0.7 - Brighness level now selectable
#			  (Idea by Philip Ivanier, programmed by Tobias Goldstone)
#	2006/08/85 v0.6	- SS 6.5 beta ready
#	2006/05/20 v0.5 - Some cleanup from Daryle, Thanks.
#	2005/11/07 v0.41 - Added Web UI
#	2005/11/02 v0.4a - The display is shutoff whenever it is in the 'display off'
#	                    time window, as opposed to only at the rollover times.
#	                    It also does not blank when 'on' and presumably in use.
#	                    (Thanks to Daryle A. Tilroe)
#
#	2005/10/31 v0.4 - Fix a bug (Thanks to Daryle and LJ for reporting)
#	2005/05/11 v0.3 - Cleaned code and allowed use with Slimserver 6.0+
#	
#	2004/05/15 v0.2	- Make use of the server integrated functions:
#	                    timeDigits and scrollTime
#	2004/04/27 v0.1	- Initial version
#	----------------------------------------------------------------------
#       To do:
#
#       - Multi language
#
#
#	This program is free software; you can redistribute it and/or modify
#	it under the terms of the GNU General Public License as published by
#	the Free Software Foundation; either version 2 of the License, or
#	(at your option) any later version.
#
#	This program is distributed in the hope that it will be useful,
#	but WITHOUT ANY WARRANTY; without even the implied warranty of
#	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#	GNU General Public License for more details.
#
#	You should have received a copy of the GNU General Public License
#	along with this program; if not, write to the Free Software
#	Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA
#	02111-1307 USA
#

package Plugins::AutoDisplay::Plugin;

use base qw(Slim::Plugin::Base);

use Plugins::AutoDisplay::PlayerSettings;

use Slim::Utils::Strings qw (string);
use Time::HiRes;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Prefs;
use Slim::Player::Player;
use Slim::Player::Client;

use strict;

use vars qw($VERSION);
$VERSION = "0.9";

my $log = Slim::Utils::Log->addLogCategory({
    'category' => 'plugin.autodisplay',
    'defaultLevel' => 'DEBUG',
    'description' => 'PLUGIN_AUTODISPLAY_NAME'
});

sub getDisplayName {
	return 'PLUGIN_AUTODISPLAY_NAME'
};


#Slim::Buttons::Common::addMode(string('PLUGIN_AUTODISPLAY_NAME'), getFunctions(), \&Plugins::AutoDisplay::Plugin::setMode);

my $myPrefs = preferences('plugin.autodisplay');

my @browseMenuChoices;
my %menuSelection;
our $brightness = ();
my %functions = (
    	'up' => sub  {
    		my $client = shift;
    		my $newposition = Slim::Buttons::Common::scroll($client, -1, ($#browseMenuChoices + 1), $menuSelection{$client});
    
    		$menuSelection{$client} =$newposition;
    		$client->update();
    	},
    	'down' => sub  {
    		my $client = shift;
    		my $newposition = Slim::Buttons::Common::scroll($client, +1, ($#browseMenuChoices + 1), $menuSelection{$client});
    
    		$menuSelection{$client} =$newposition;
    		$client->update();
    	},

# Need more information about knob first, like how to make it stop at the end of the list
#	'knob' => sub {
#    		my $client = shift;
#
#    		my $newposition = Slim::Buttons::Common::scroll($client, $client->knobPos() - $menuSelection{$client}, ($#browseMenuChoices + 1), $menuSelection{$client});
#    
#    		$menuSelection{$client} =$newposition;
#    		$client->update();
#	},

    	'left' => sub  {
    		my $client = shift;
    
    		Slim::Buttons::Common::popModeRight($client);
    	},
    	'right' => sub {
    		my $client = shift;
###    		my @oldlines = Slim::Display::Display::curLines($client);
    		my @oldlines = $client->curLines();

			if ($browseMenuChoices[$menuSelection{$client}] eq $client->string('PLUGIN_AUTODISPLAY_FLAG_ON_OFF')) {
				my $flag = $myPrefs->client($client)->get('autodisplay_flag');
				
			#Turn on or off plugin using player menu
			#If plugin is 'ON' then set to 'OFF' and display message
				if ($flag ==1) {
					
					$myPrefs->client($client)->set('autodisplay_flag','0');
					my $newflag = $myPrefs->client($client)->get('autodisplay_flag');
					$client->showBriefly({'line1' => $client->string('PLUGIN_AUTODISPLAY_TURNING_OFF'), 'line2' => ''});
				}	
			#If plugin has been set to'OFF' then set to 'ON'
				else {
				
					$myPrefs->client($client)->set('autodisplay_flag','1');
					$client->showBriefly({ 'line1' => $client->string('PLUGIN_AUTODISPLAY_TURNING_ON'), 'line2' => ''});
					my $displayflag = $myPrefs->client($client)->get('autodisplay_flag');
					
				}
			}

			#Set time to turn off display
			elsif($browseMenuChoices[$menuSelection{$client}] eq $client->string('PLUGIN_AUTODISPLAY_OFF_SET')) {
				
				my %params = (
					'header' => $client->string('PLUGIN_AUTODISPLAY_OFF_SET'),
					'valueRef' => $myPrefs->client($client)->get('autodisplay_off_time'),
					'cursorPos' => 0,
					'callback' => \&settingsExitHandler
				);
				Slim::Buttons::Common::pushModeLeft($client, 'INPUT.Time',\%params);
			}

			#Set time for plugin to turn on display	
			elsif ($browseMenuChoices[$menuSelection{$client}] eq $client->string('PLUGIN_AUTODISPLAY_ON_SET')) {
    			my %params = (
    					'header' => $client->string('PLUGIN_AUTODISPLAY_ON_SET'),
    					'valueRef' => $myPrefs->client($client)->get('autodisplay_on_time'),
    					'cursorPos' => 0,
    					'callback' => \&settingsExitHandler
    				);
    				Slim::Buttons::Common::pushModeLeft($client, 'INPUT.Time',\%params);
			}
			elsif ($browseMenuChoices[$menuSelection{$client}] eq $client->string('PLUGIN_AUTODISPLAY_BRIGHTNESS_SET')) {
    			my %params = (
						'listRef' => ['0','1','2','3','4'],
						'externRef' => [string('BRIGHTNESS_DARK'),1,2,3,string('BRIGHTNESS_BRIGHTEST')],
    					'header' => $client->string('PLUGIN_AUTODISPLAY_BRIGHTNESS_SET'),
    					'valueRef' => $myPrefs->client($client)->get('autodisplay_brightness'),
    					'cursorPos' => 0,
    					'callback' => \&settingsExitHandler,
    				);
				Slim::Buttons::Common::pushModeLeft($client, 'INPUT.List',\%params);
			}
    	},
    	'play' => sub {
    		my $client = shift;
    	},
    );

# setTimer();

sub setMode() {
	my $class = shift;
	my $client = shift;
	$log->debug("Setting autodisplay mode for " . $client->name());
	@browseMenuChoices = (
		$client->string('PLUGIN_AUTODISPLAY_FLAG_ON_OFF'),
		$client->string('PLUGIN_AUTODISPLAY_OFF_SET'),
		$client->string('PLUGIN_AUTODISPLAY_ON_SET'),
		$client->string('PLUGIN_AUTODISPLAY_BRIGHTNESS_SET')
		);
	
	if (!defined($menuSelection{$client})) { $menuSelection{$client} = 0; };
	$client->lines(\&lines);

	#Set client default
	my $flag = $myPrefs->client($client)->get('autodisplay_flag');
	if (!defined($flag)) {$myPrefs->client($client)->set('autodisplay_flag',0); }
	

	#get previous set on time or set a default
	my $ontime = $myPrefs->client($client)->get('autodisplay_on_time');
	if (!defined($ontime)) {$myPrefs->client($client)->set('autodisplay_on_time',8 * 60 * 60); }

	#get previous set off time or set a default
	my $offtime = $myPrefs->client($client)->get('autodisplay_off_time');
	if (!defined($offtime)) {$myPrefs->client($client)->set('autodisplay_off_time',20 * 60 * 60); }

	#get brightness level or set a default
	my $brightness = $myPrefs->client($client)->get('autodisplay_brightness');
	if (!defined($brightness)) {$myPrefs->client($client)->set('autodisplay_brightness',0); }
}
   
sub lines {
	my $client = shift;
	my ($line1, $line2, $overlay2);

	$overlay2 = overlay($client);
	
	$line1 = $client->string('PLUGIN_AUTODISPLAY_NAME') . " (" . ($menuSelection{$client}+1) . " " . $client->string('OF') . " " . ($#browseMenuChoices + 1) . ")";

	$line2 = $browseMenuChoices[$menuSelection{$client}];
	
	return { 'line1' => $line1, 'line2' => $line2, 'overlay' => $overlay2 };
}

sub overlay {
	my $client = shift;
	
	return $client->symbols('rightarrow');

	return undef;
}

sub getFunctions { return \%functions;}

sub initPlugin {
    my $class = shift;
    $class->SUPER::initPlugin(@_);

    $log->info(string('PLUGIN_AUTODISPLAY_NAME') . " -- Starting -- $VERSION");
    Plugins::AutoDisplay::PlayerSettings->new();

    setTimer();
}

sub settingsExitHandler {
	my ($client,$exittype) = @_;

	$exittype = uc($exittype);

	if ($exittype eq 'LEFT') {
		if ($browseMenuChoices[$menuSelection{$client}] eq $client->string('PLUGIN_AUTODISPLAY_ON_SET')) {
			my $value = ${$client->modeParam('valueRef')};

			#$::d_plugins && msg ("my value is $value\n");

			$myPrefs->client($client)->set('autodisplay_on_time',${$client->modeParam('valueRef')});
    			Slim::Buttons::Common::popModeRight($client);
		}
		elsif ($browseMenuChoices[$menuSelection{$client}] eq $client->string('PLUGIN_AUTODISPLAY_OFF_SET')){
			$myPrefs->client($client)->set('autodisplay_off_time',${$client->modeParam('valueRef')});
    			Slim::Buttons::Common::popModeRight($client);
		}
		elsif ($exittype eq 'RIGHT') {
			$client->bumpRight();
		}
		elsif ($browseMenuChoices[$menuSelection{$client}] eq $client->string('PLUGIN_AUTODISPLAY_BRIGHTNESS_SET')){
			$myPrefs->client($client)->set('autodisplay_brightness',${$client->modeParam('valueRef')});
    			Slim::Buttons::Common::popModeRight($client);
		}
		else {
			return;
		}
	}
}

sub setTimer {
    # timer to check alarms on an 60 second interval
    my $time = Time::HiRes::time() + 60;
    $log->debug("Setting timer: " . $time);
    Slim::Utils::Timers::setTimer(0, $time, \&checkOnOff);
}

sub checkOnOff {
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
	my $time = $hour * 60 * 60 + $min * 60;
	
	$log->debug("Checking timer Autodisplay plugin");
	
	foreach my $client (Slim::Player::Client::clients()) {
		my $ontime =  $myPrefs->client($client)->get('autodisplay_on_time');
		my $offtime =  $myPrefs->client($client)->get('autodisplay_off_time');
		my $flag = $myPrefs->client($client)->get('autodisplay_flag');
		my $brightness = $myPrefs->client($client)->get('autodisplay_brightness');
		my $clientname = $client->name();

		$log->debug($clientname . " :: " . $flag . " :: " . $ontime . " :: " . $offtime . " :: " . $brightness);

		#If client has autodisplay on/off preference and times set then continue...
		if (defined($flag) && defined($offtime) && defined($ontime)) {
			#If autodisplay has been set to "ON" then continue...
    			if ($flag==1) {

				#Get client power state
    				my $power = $client->power();
				
        			if ( !$power && ( ($offtime > $ontime && ($time >= $offtime || $time <= $ontime)) || ($offtime < $ontime && $time >= $offtime && $time <= $ontime) ) ) {
					
					$log->debug("$clientname...Hiding display");
					$log->debug("$clientname brightness set to $brightness");
        				#Set client brightness off
        				$client->brightness($brightness);
       			}
        	  
        			elsif (!$power) {
       			
           				#Reset display brightness to user preference.
        				$client->brightness($myPrefs->client($client)->get('powerOffBrightness'));
        			}
        		}			
		}
	}
	setTimer();
}

sub enabled {
	return 1;
}

sub setupGroup {
	my $client = shift;
	my %group = (
		'PrefOrder' => ['autodisplay_flag','autodisplay_off_time','autodisplay_on_time','autodisplay_brightness']
		,'GroupHead' => Slim::Utils::Strings::string('SETUP_GROUP_PLUGIN_PLUGINNAME')
		,'GroupDesc' => Slim::Utils::Strings::string('SETUP_GROUP_PLUGIN_PLUGINNAME_DESC')
		,'GroupLine' => 1
		,'GroupSub'  => 1
		,'PrefsInTable' => 1
		,'Suppress_PrefHead' => 1
		,'Suppress_PrefDesc' => 1
		,'Suppress_PrefLine' => 1
		,'Suppress_PrefSub' => 1
	);
	my %prefs = (
		'autodisplay_flag' => {
###			'validate' => \&Slim::Web::Setup::validateTrueFalse
			'validate' => \&Slim::Utils::Validate::trueFalse
			,'currentValue' => sub {
				my $client = shift;
				my $val = $myPrefs->client($client)->get('autodisplay_flag');
				if (!defined $val) {
							$myPrefs->client($client)->set('autodisplay_flag',0);
						}

				return $val;
			}
			
			,'PrefHead' => ' '
			,'PrefChoose' => string('PLUGIN_AUTODISPLAY_FLAG_ON_OFF').string('COLON')
			,'changeIntro' => string('PLUGIN_AUTODISPLAY_FLAG_ON_OFF').string('COLON')
			,'options'  => {
				'1' => string('ON'),
				'0' => string('OFF'),		
			}
		},

		'autodisplay_on_time' => {
###			'validate' => \&Slim::Web::Setup::validateTime
			'validate' => \&Slim::Utils::Validate::isTime
			,'validateArgs' => [0,undef]
			,'PrefHead' => ' '
			,'PrefChoose' => string('PLUGIN_AUTODISPLAY_ON_SET').string('COLON')
			,'rejectIntro' => string('PLUGIN_REJECT_INTRO').string('COLON').string('PLUGIN_AUTODISPLAY_ON_SET')
			,'rejectMSG' => string('PLUGIN_REJECT_MSG')
			,'changeIntro' => string('PLUGIN_AUTODISPLAY_ON_SET').string('COLON')
			,'currentValue' => sub {
				my $client = shift;
				return if (!defined($client));
				my $time =  $myPrefs->client($client)->get('autodisplay_on_time');
				my ($h0, $h1, $m0, $m1, $p) = Slim::Buttons::Common::timeDigits($client,$time);
				my $timestring = ((defined($p) && $h0 == 0) ? ' ' : $h0) . $h1 . ":" . $m0 . $m1 . " " . (defined($p) ? $p : '');
				
				return $timestring;
										
			}
			,'onChange' => sub {
				my ($client,$changeref,$paramref,$pageref) = @_;
				return if (!defined($client));
				my $time = $changeref->{'autodisplay_on_time'}{'new'};
				my $newtime = 0;
				$time =~ s{
					^(0?[0-9]|1[0-9]|2[0-4]):([0-5][0-9])\s*(P|PM|A|AM)?$
				}{
					if (defined $3) {
						$newtime = ($1 == 12?0:$1 * 60 * 60) + ($2 * 60) + ($3 =~ /P/?12 * 60 * 60:0);
					} else {
						$newtime = ($1 * 60 * 60) + ($2 * 60);
					}
				}iegsx;
				$myPrefs->client($client)->set('autodisplay_on_time',$newtime);
			}
		},
		'autodisplay_off_time' => {
###			'validate' => \&Slim::Web::Setup::validateAcceptAll
			'validate' => \&Slim::Utils::Validate::isTime
			,'PrefHead' => ' '
			,'PrefChoose' => string('PLUGIN_AUTODISPLAY_OFF_SET').string('COLON')
			,'changeIntro' => string('PLUGIN_AUTODISPLAY_OFF_SET').string('COLON')
			,'rejectIntro' => string('PLUGIN_REJECT_INTRO').string('COLON').string('PLUGIN_AUTODISPLAY_OFF_SET')
			,'rejectMSG' => string('PLUGIN_REJECT_MSG')
			,'validateArgs' => [0,undef]
			,'currentValue' => sub {
				my $client = shift;
				return if (!defined($client));
				my $time =  $myPrefs->client($client)->get('autodisplay_off_time');
				my ($h0, $h1, $m0, $m1, $p) = Slim::Buttons::Common::timeDigits($client,$time);
				my $timestring = ((defined($p) && $h0 == 0) ? ' ' : $h0) . $h1 . ":" . $m0 . $m1 . " " . (defined($p) ? $p : '');
				return $timestring;							
			}
			,'onChange' => sub {
				my ($client,$changeref,$paramref,$pageref) = @_;
				my $time = $changeref->{'autodisplay_off_time'}{'new'};
				my $newtime = 0;
				
				$time =~ s{
					^(0?[0-9]|1[0-9]|2[0-4]):([0-5][0-9])\s*(P|PM|A|AM)?$
				}{
					if (defined $3) {
						$newtime = ($1 == 12?0:$1 * 60 * 60) + ($2 * 60) + ($3 =~ /P/?12 * 60 * 60:0);
					} else {
						$newtime = ($1 * 60 * 60) + ($2 * 60);
					}
				}iegsx;
				$myPrefs->client($client)->set('autodisplay_off_time',$newtime);
			}
		},
		'autodisplay_brightness' => {
			'validate'     => \&Slim::Utils::Validate::isInt
			,'validateArgs' => [0,1,2,3,4]
			,'optionSort'   => 'NK'
			,'options'      => \&getBrightnessOptions
			,'PrefHead' => ' '
			,'PrefChoose' => string('PLUGIN_AUTODISPLAY_BRIGHTNESS_SET').string('COLON')
			,'changeIntro' => string('PLUGIN_AUTODISPLAY_BRIGHTNESS_SET').string('COLON')
			,'rejectIntro' => string('PLUGIN_REJECT_INTRO').string('COLON').string('PLUGIN_AUTODISPLAY_BRIGHTNESS_SET')
			,'rejectMSG' => string('PLUGIN_REJECT_MSG')
			,'currentValue' => sub {
				my $client = shift;
				my $brightness =  $myPrefs->client($client)->get('autodisplay_brightness');
				return $brightness;							
			}
			,'onChange' => sub {
				my ($client,$changeref,$paramref,$pageref) = @_;
				my $brightness = $changeref->{'autodisplay_brightness'}{'new'};
				$myPrefs->client($client)->set('autodisplay_brightness',$brightness);
			}
		}
	);
	
	return (\%group,\%prefs,1);

    sub getBrightnessOptions {
	    my %brightnesses = (
						    '0' => '0 ('.string('PLUGIN_AUTODISPLAY_BRIGHTNESS_DARK').')',
						    '1' => '1',
						    '2' => '2',
						    '3' => '3',
						    '4' => '4 ('.string('PLUGIN_AUTODISPLAY_BRIGHTNESS_BRIGHTEST').')',
						    );
	    return \%brightnesses;
    }
}
1;
