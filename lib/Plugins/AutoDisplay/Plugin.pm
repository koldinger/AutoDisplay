#Autodisplay.pm
#Date: 5/11/2005
#Purpose: To allow automatic display brightness on-off at specific times.
#Author: Felix Mueller <felix.mueller(at)gwendesign.com>
#Redesigned for Slimserver 6.0+ by Tobias Goldstone <tgoldstone(at)familyzoo.net>
#Ported to SqueezeCenter 7.0+ by Eric Koldinger <eric(at)koldware.com>
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
$VERSION = "1.00";

my $log = Slim::Utils::Log->addLogCategory({
    'category' => 'plugin.autodisplay',
    'defaultLevel' => 'DEBUG',
    'description' => 'PLUGIN_AUTODISPLAY_NAME'
});

sub getDisplayName {
	return 'PLUGIN_AUTODISPLAY_NAME'
};

my $myPrefs = preferences('plugin.autodisplay');
my $serverPrefs = preferences('server');

my @browseMenuChoices;
my %menuSelection;

my $timer;

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
			elsif($browseMenuChoices[$menuSelection{$client}] eq $client->string('PLUGIN_AUTODISPLAY_DIM_SET')) {
				
				my %params = (
					'header' => $client->string('PLUGIN_AUTODISPLAY_DIM_SET'),
					'valueRef' => $myPrefs->client($client)->get('autodisplay_off_time'),
					'cursorPos' => 0,
					'callback' => \&settingsExitHandler
				);
				Slim::Buttons::Common::pushModeLeft($client, 'INPUT.Time',\%params);
			}

			#Set time for plugin to turn on display	
			elsif ($browseMenuChoices[$menuSelection{$client}] eq $client->string('PLUGIN_AUTODISPLAY_BRIGHT_SET')) {
    			my %params = (
    					'header' => $client->string('PLUGIN_AUTODISPLAY_BRIGHT_SET'),
    					'valueRef' => $myPrefs->client($client)->get('autodisplay_on_time'),
    					'cursorPos' => 0,
    					'callback' => \&settingsExitHandler
    				);
    				Slim::Buttons::Common::pushModeLeft($client, 'INPUT.Time',\%params);
			}
			elsif ($browseMenuChoices[$menuSelection{$client}] eq $client->string('PLUGIN_AUTODISPLAY_BRIGHTNESS_SET')) {
    			my %params = (
						'listRef' => [0 .. $client->display->maxBrightness()],
						'externRef' => [string('BRIGHTNESS_DARK'),
										1 .. $client->display->maxBrightness() - 1,
										string('BRIGHTNESS_BRIGHTEST')],
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

sub setMode() {
	my $class = shift;
	my $client = shift;
	$log->debug("Setting autodisplay mode for " . $client->name());
	@browseMenuChoices = (
		$client->string('PLUGIN_AUTODISPLAY_FLAG_ON_OFF'),
		$client->string('PLUGIN_AUTODISPLAY_BRIGHT_SET'),
		$client->string('PLUGIN_AUTODISPLAY_DIM_SET'),
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

	## Anytime there's a power event, or a new client (or even client forgotten) event,
	## let's check everything.
	Slim::Control::Request::subscribe( \&checkOnOff, [['power', 'client']]);

    setTimer(now());
}

sub settingsExitHandler {
	my ($client,$exittype) = @_;

	$exittype = uc($exittype);

	if ($exittype eq 'LEFT' || $exittype eq 'RIGHT') {
		if ($browseMenuChoices[$menuSelection{$client}] eq $client->string('PLUGIN_AUTODISPLAY_BRIGHT_SET')) {
			$myPrefs->client($client)->set('autodisplay_on_time', ${$client->modeParam('valueRef')});
			Slim::Buttons::Common::popModeRight($client);
		}
		elsif ($browseMenuChoices[$menuSelection{$client}] eq $client->string('PLUGIN_AUTODISPLAY_DIM_SET')){
			$myPrefs->client($client)->set('autodisplay_off_time', ${$client->modeParam('valueRef')});
			Slim::Buttons::Common::popModeRight($client);
		}
		elsif ($browseMenuChoices[$menuSelection{$client}] eq $client->string('PLUGIN_AUTODISPLAY_BRIGHTNESS_SET')){
			$myPrefs->client($client)->set('autodisplay_brightness', ${$client->modeParam('valueRef')});
			Slim::Buttons::Common::popModeRight($client);
		}
		else {
			return;
		}
	} 
}

sub setTimer {
	my $now = shift;
    Slim::Utils::Timers::killSpecific($timer) if (defined $timer);
    
	my $later = nextTime($now);
    my $time = Time::HiRes::time() + ($later - $now);
    $log->debug("Setting timer: " . $time . "(" . $later . " " . $now . ")");
    $timer = Slim::Utils::Timers::setTimer(0, $time, \&checkOnOff);
}

sub now {
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
    my $time = $hour * 60 * 60 + $min * 60 + $sec;
    return $time;
}

sub nextTime {
    my $now = shift;
	my $day = 3600 * 24;				## Seconds in a day
	my $earliest = $now + $day * 7;		## Week away.  Good number.
	foreach my $client (Slim::Player::Client::clients()) {
		my $clientPrefs = $myPrefs->client($client);
		my $flag = $clientPrefs->get('autodisplay_flag');
		if ($flag) {
			my $ontime =  $clientPrefs->get('autodisplay_on_time');
			my $offtime =  $clientPrefs->get('autodisplay_off_time');

			$ontime   += $day if ($ontime <= $now);
			$offtime  += $day if ($offtime <= $now);
			$earliest = $ontime  if ($ontime < $earliest);
			$earliest = $offtime if ($offtime < $earliest);
		}
	}
	return $earliest;
}

sub checkOnOff {
	my $time = now();
	
	$log->debug("Checking timer Autodisplay plugin: " . $time);
	
	foreach my $client (Slim::Player::Client::clients()) {
		my $clientPrefs = $myPrefs->client($client);
		my $flag = $clientPrefs->get('autodisplay_flag');
		if ($flag) {
			my $ontime =  $clientPrefs->get('autodisplay_on_time');
			my $offtime =  $clientPrefs->get('autodisplay_off_time');
			my $brightness = $clientPrefs->get('autodisplay_brightness');
			my $clientname = $client->name();

			$log->debug($clientname . " :: " . $flag . " :: " . $ontime . " :: " . $offtime . " :: " . $brightness);

			#If client has autodisplay on/off preference and times set then continue...
			if (defined($flag) && defined($offtime) && defined($ontime)) {
				#If autodisplay has been set to "ON" then continue...
				my $power = $client->power();
					
				if ( !$power ) {
					if (($offtime > $ontime && ($time >= $offtime || $time < $ontime)) ||
						($offtime < $ontime && $time >= $offtime && $time < $ontime)) {
					
						$log->debug("$clientname Lowering $brightness");
						#Set client brightness off
						$client->brightness($brightness);
					} else {
						#Reset display brightness to user preference.
						my $x = $serverPrefs->client($client)->get('powerOffBrightness');
						$log->debug("$clientname Raising " .  $x);
						$client->brightness($x);
					}
				}
			}
		}
	}

	setTimer($time);
}

1;
