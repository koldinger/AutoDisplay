package Plugins::AutoDisplay::PlayerSettings;

# SqueezeCenter Copyright 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Strings qw (string);
use Slim::Display::NoDisplay;
use Slim::Display::Display;


my $prefs = preferences('plugin.autodisplay');
my $log   = logger('plugin.autodisplay');

sub name {
	return Slim::Web::HTTP::protectName('PLUGIN_AUTODISPLAY_NAME');
}

sub needsClient {
	return 1;
}

sub page {
	return Slim::Web::HTTP::protectURI('plugins/AutoDisplay/settings/player.html');
}

sub prefs {
	my $class = shift;
	my $client = shift;
	return ($prefs->client($client), qw(autodisplay_flag autodisplay_brightness));
}

sub handler {
	my ($class, $client, $params) = @_;
	$log->debug("AutoDisplay::PlayerSettings->handler() called. " . $client->name());
	Plugins::AutoDisplay::Plugin->extSetDefaults($client, 0);

	if ($params->{'saveSettings'})
	{
		$prefs->client($client)->set('autodisplay_on_time', Slim::Utils::DateTime::prettyTimeToSecs($params->{'brighttime'}));
		$prefs->client($client)->set('autodisplay_off_time', Slim::Utils::DateTime::prettyTimeToSecs($params->{'dimtime'}));
		# Settings have been changed. Force an update of the player
		Plugins::AutoDisplay::Plugin->checkOnOff();
	}
	$params->{'nodisplay'} = 1 if ($client->display->isa('Slim::Display::NoDisplay'));

	$params->{'brighttime'} = Slim::Utils::DateTime::secsToPrettyTime($prefs->client($client)->get('autodisplay_on_time'));
	$params->{'dimtime'} = Slim::Utils::DateTime::secsToPrettyTime($prefs->client($client)->get('autodisplay_off_time'));
	$params->{'brightValues'} = makeBrightValues($client);

	return $class->SUPER::handler( $client, $params );
}

sub makeBrightValues {
	my $client = shift;
	my $max = $client->display->maxBrightness();
	my $brightValues;
	foreach my $i (0 .. $max)
	{
		my $string = $i;
		$string = $string . " " . string('PLUGIN_AUTODISPLAY_BRIGHTNESS_DARK') if ($i == 0);
		$string = $string . " " . string('PLUGIN_AUTODISPLAY_BRIGHTNESS_BRIGHTEST') if ($i == $max);
		$brightValues->{$i} = $string;
	}
	return $brightValues;
}

1;
