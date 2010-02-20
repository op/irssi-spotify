# spotify.pl - lookup spotify resources
#
# Copyright (c) 2009 Örjan Persson <o@42mm.org>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA

use strict;
use vars qw($VERSION %IRSSI);
$VERSION = '0.1';
%IRSSI = (
	authors     => 'Örjan Persson',
	contact     => 'o@42mm.org',
	name        => 'spotify',
	description => 'Lookup spotify uris',
	license     => 'GPLv2'
);  

use Irssi;

use Encode;
use HTML::Entities;
use LWP::UserAgent;
use POSIX;
use XML::DOM;

sub cmd_spotify_help {
	Irssi::print(<<'EOF', MSGLEVEL_CLIENTCRAP);
SPOTIFY [-a | auto] [-l | lookup] [...]

    -a, auto: see SPOTIFY AUTO
    -l, lookup: see SPOTIFY LOOKUP

Lookup spotify uris to get information on tracks, albums,
and artists. You can configure it to do automatic lookup
when someone sends it in a channel or privatley.

There are several settings which can be configured.

/SET spotify_header_format <string>
    Header message above lookup result. Available variables:
        %%uri            requested uri

/SET spotify_album_format <string>
    Format for album results. Available variables:
        %%name           name of the album
        %%artist         album artists
        %%year           year the album was released
        %%territories    territories the album is available in

/SET spotify_artist_format <string>
    Format for artist results. Available variables:
        %%name           name of the artist

/SET spotify_track_format <string>
    Format for track results. Available variables:
        %%name           name of the track
        %%album          name of the album
        %%artist         track artists
        %%popularity     track popularity

See /SPOTIFY <section> help for more information.

EOF
}

sub cmd_spotify_help_lookup {
	Irssi::print(<<'EOF', MSGLEVEL_CLIENTCRAP);
SPOTIFY LOOKUP [-p | public] <resource>

    -p, public: return result to current window
    -h, help:   show this help

Lookup the given resource and return the result. If the public
argument is given, the result is returned to the current window.
EOF
}

sub cmd_spotify_help_auto {
	Irssi::print(<<'EOF', MSGLEVEL_CLIENTCRAP);
SPOTIFY AUTO [-p | public] [-i | info] [-e | enable] [-d | disable] [-w | whitelist] [-b | blacklist]

    -p, public: see SPOTIFY AUTO PUBLIC
    -i, info: display current settings for SPOTIFY AUTO
    -e, enable: enable automatic lookup
    -d, disable: disable automatic lookup

Configure automatic features. The public section is for
automatic return results in the window the Spotify resource
was sent in.

Info will display settings for all automatic features and
you can use enable or disable to turn automatic functions
on or off.
EOF
}

sub cmd_spotify_help_auto_public {
	Irssi::print(<<'EOF', MSGLEVEL_CLIENTCRAP);
SPOTIFY AUTO PUBLIC [OPTION...]

    -a, add: add nick or channel to auto list
    -d, del: delete nick or channel from auto list
    -n, nick: use command on nick list
    -c, channel: use command on channel list

    -i, info: display current settings for SPOTIFY AUTO
    -w, whitelist: treaten list as a whitelist
    -b, blacklist: treaten list as a blacklist

Add a nick or channel to search from when matching 
Configure automatic features. The public section is for
automatic return results in the window the Spotify resource
was sent in.

Info will display settings for all automatic features and
you can use enable or disable to turn automatic functions
on or off.

You can also set if you want the list of nicks and channels
to be interpretted as a whitelist or blacklist.
EOF
}

sub cmd_help {
	my ($args, $server, $window) = @_;

	if ($args =~ /^spotify\s*$/) {
		cmd_spotify_help();
	} elsif ($args =~ /^spotify lookup\s*$/i) {
		cmd_spotify_help_lookup();
	} elsif ($args =~ /^spotify auto\s*$/i) {
		cmd_spotify_help_auto();
	} elsif ($args =~ /^spotify auto public\s*$/i) {
		cmd_spotify_help_auto_public();
	}
}

sub cmd_spotify_lookup {
	my ($args, $server, $window) = @_;
	my @argv = split(/ /, $args);

	my $public = 0;

	# Simple parse arguments (debian still has an old version of irssi..)
	my $i;
	for ($i = 0; $i <= $#argv; $i++) {
		if ($argv[$i] eq '-p' || $argv[$i] eq 'public') { $public = 1; }
		elsif ($argv[$i] eq '-h' || $argv[$i] eq 'help') {
			return Irssi::command_runsub('spotify lookup', $args, $server, $window);
		}
		else { last; }
	}

	# Treat the rest as data argument
	my $data = join(' ', @argv[$i..$#argv]);

	# Make sure we actually have a window reference and check if we can write	
	if ($public) {
		if (!$window) {
			Irssi::active_win()->print("Must be run run in a valid window (CHANNEL|QUERY)");
			return;
		}
	} else {
		$window = Irssi::active_win();
	}

	# Dispatch the work to be done
	my @worker_args = ($data, 1);
	my @output_args = ($server->{tag}, $window->{name}, $public ? $window->{name} : 0);
	dispatch(\&spotify_lookup, \@worker_args, \@output_args);
}

sub cmd_spotify_auto {
	my ($args, $server, $window) = @_;

	if ($args eq 'info' || $args eq '-i') {

		my $lookup = Irssi::settings_get_str('spotify_automatic_lookup');
		my $lookup_public = Irssi::settings_get_str('spotify_automatic_lookup_public');
		my $lookup_public_blacklist = Irssi::settings_get_str('spotify_automatic_lookup_public_blacklist');
		my $lookup_public_channels = Irssi::settings_get_str('spotify_automatic_lookup_public_channels');
		my $lookup_public_nicks = Irssi::settings_get_str('spotify_automatic_lookup_public_nicks');
		my $policy = $lookup_public_blacklist eq 'yes' ? 'disable' : 'enable';
		Irssi::print(<<"EOF", MSGLEVEL_CLIENTCRAP);
Spotify automatic settings:
 automatic lookup: %_${lookup}%_
 automatic lookup to public: %_${lookup_public}%_
 interpret list of channels and nicks as blacklist: %_${lookup_public_blacklist}%_
 ${policy} lookup for channels: %_${lookup_public_channels}%_
 ${policy} lookup for nicks: %_${lookup_public_nicks}%_
EOF
	} elsif ($args eq 'enable' || $args eq '-e') {
		Irssi::settings_set_bool('spotify_automatic_lookup', 1);
		cmd_spotify_auto('info', $server, $window);
	} elsif ($args eq 'disable' || $args eq '-d') {
		Irssi::settings_set_bool('spotify_automatic_lookup', 0);
		cmd_spotify_auto('info', $server, $window);
	} else {
		Irssi::command_runsub('spotify auto', $args, $server, $window);
	}
}

sub cmd_spotify_auto_public {
	my ($args, $server, $window) = @_;

	if ($args eq 'info' || $args eq '-i') {
		cmd_spotify_auto('info', $server, $window);
	} elsif ($args eq 'whitelist' || $args eq '-w') {
		Irssi::settings_set_bool('spotify_automatic_lookup_public_blacklist', 0);
		cmd_spotify_auto('info', $server, $window);
	} elsif ($args eq 'blacklist' || $args eq '-b') {
		Irssi::settings_set_bool('spotify_automatic_lookup_public_blacklist', 1);
		cmd_spotify_auto('info', $server, $window);
	} elsif ($args eq 'enable' || $args eq '-e') {
		Irssi::settings_set_bool('spotify_automatic_lookup_public', 1);
		cmd_spotify_auto('info', $server, $window);
	} elsif ($args eq 'disable' || $args eq '-d') {
		Irssi::settings_set_bool('spotify_automatic_lookup_public', 0);
		cmd_spotify_auto('info', $server, $window);
	} else {
		Irssi::command_runsub('spotify auto public', $args, $server, $window);
	}
}

sub cmd_spotify_auto_public_add {
	my ($args, $server, $window) = @_;
	
	my @argv = split(/ /, $args);
	my $type = shift(@argv);

	if ($type eq 'channel' || $type eq '-c') {
		$type = 'channel';
	} elsif ($type eq 'nick' || $type eq '-n') {
		$type = 'nick';
	} else {
		return Irssi::command_runsub('spotify auto public add', $args, $server, $window);
	}

	my @array = settings_get_array("spotify_automatic_lookup_public_${type}s");
	foreach my $arg (@argv) {
		push(@array, $arg);
	}
	settings_set_array("spotify_automatic_lookup_public_${type}s", @array);
	cmd_spotify_auto('info', $server, $window);
}

sub cmd_spotify_auto_public_del {
	my ($args, $server, $window) = @_;

	my @argv = split(/ /, $args);
	my $type = shift(@argv);

	if ($type eq 'channel' || $type eq '-c') {
		$type = 'channel';
	} elsif ($type eq 'nick' || $type eq '-n') {
		$type = 'nick';
	} else {
		return Irssi::command_runsub('spotify auto public del', $args, $server, $window);
	}

	my @array = settings_get_array("spotify_automatic_lookup_public_${type}s");
	foreach my $arg (@argv) {
		for (my $i = 0; $i <= $#array; $i++) {
			if ($array[$i] eq $arg) {
				splice(@array, $i, 1);
				last;
			}
		}
	}
	settings_set_array("spotify_automatic_lookup_public_${type}s", @array);
	cmd_spotify_auto('info', $server, $window);
}

sub event_message_topic {
	my ($server, $channel, $topic, $nick, $address) = @_;

	if ($server->{nick} ne $nick) {
		event_message($server, $topic, $nick, $address, $channel);
	}	

}

sub event_message {
	my ($server, $text, $nick, $address, $target) = @_;

	if (!Irssi::settings_get_bool('spotify_automatic_lookup')) {
		return;
	}

	# Retrieve window object and decide wether to do lookup public or not
	my ($window, $public);
	if (!$server->ischannel($target)) {
		$window = Irssi::window_item_find($nick);
		$public = public_lookup_permitted($nick);
		$target = $nick;
	} else {
		$window = Irssi::window_item_find($target);
		$public = public_lookup_permitted($nick, $target);
	}

	# Dispatch a lookup for each matching uri
	my @output_args = ($server->{tag}, $window->{name}, $public ? $target : 0);
	while ($text =~ m/(http:\/\/open\.spotify\.com\/|spotify:)(track|user|album|artist)[\/:][^\s]+/g) {
		my @worker_args = ($&, 0);
		dispatch(\&spotify_lookup, \@worker_args, \@output_args);
	}
}

sub dispatch {
	my $action = shift;
	my @writer_args = @{$_[0]};
	my @reader_args = @{$_[1]};


	# Create communication between child and main process
	my ($reader, $writer);
	pipe($reader, $writer);

	# Create child process
	my $pid = fork();
	if ($pid > 0) {
		# Main process, close writer and add child pid to waiting list
		close($writer);
		Irssi::pidwait_add($pid);

		# Add reader and input pipe tag to arguments and pass it to
		# dispatch_reader when finished
		my $input_tag;
		unshift(@reader_args, $pid);
		unshift(@reader_args, \$input_tag);
		unshift(@reader_args, $reader);

		# Wait for child to finish and send result to input_reader
		$input_tag = Irssi::input_add(fileno($reader), INPUT_READ,
		                              'input_reader', \@reader_args);
	} elsif ($pid == 0) {
		# Child process, close reader and do the work to be done
		close($reader);
		my $rc = $action->($writer, \@writer_args) || 0;
		close($writer);
		POSIX::_exit($rc);
	} else {
		# Fork error, something nasty must have happened
		Irssi::print('spotify: failed to fork(), aborting $cmd.', MSGLEVEL_CLIENTCRAP);
		close($reader);
		close($writer);
	}
}

sub input_reader {
	my ($reader, $input_tag, $pid, $server, $window, $target) = @{$_[0]};
	my @data = <$reader>;

	# Cleanup before doing anything else
	close($reader);
	Irssi::input_remove($$input_tag);

	# Get exit code from child and force non-public output on error
	while (waitpid($pid, POSIX::WNOHANG) == 0) {
		sleep 1;
	}
	my $rc = POSIX::WEXITSTATUS($?);
	if ($rc) { $target = 0; }

	# Find output window
	$server = Irssi::server_find_tag($server);
	$window = $server ? $server->window_item_find($window) : undef;

	if (!defined($window)) {
		$window = Irssi::active_win();
	}

	# Handle result from child
	foreach my $line (@data) {
		chomp($line);
		if ($target) {
			# Remove any trace of colors (could probably break things)
			$line =~ s/%[krgybmpcwn:|#_]//ig;
			$window->command("/NOTICE $target " . $line);
		}
		else { $window->print($line); }
	}
}

sub spotify_lookup {
	my $writer = shift;
	my ($uri, $manual) = @{$_[0]};

	# Retrieve text values from xml nodes by a search path
	#
	# Imagine that you have this XML:
	# <elem1><elem2><elem3>text</elem3></elem2></elem1>
	#
	# You can easily retrieve the 'text' by setting the search pattern to
	# elem1/elem2/elem3.
	sub getTextValue {
		my $node = shift;
		my $path = shift;
		my $recurse = shift || 0;

		# Walk through the path and pop the base
		my ($name, $subpath) = split(/\//, $path, 2);

		my $text = '';
		my $i = 0;
		foreach my $child ($node->getElementsByTagName($name, $recurse)) {
			if ($i > 0) { $text .= ', '; }
			if (defined($subpath)) { $text .= getTextValue($child, $subpath, $recurse); }
			else { $text .= HTML::Entities::decode($child->getFirstChild->toString()); }
		}

		return $text;
	}

	# Sanitize uri
	$uri =~ s/^\s+//g;
	$uri =~ s/\s+$//g;

	# Initialize LWP
	my $ua = new LWP::UserAgent(agent => "spotify.pl/$VERSION", timeout => 10);
	$ua->env_proxy();

	# Do the actual lookup
	my $url = "http://ws.spotify.com/lookup/1/?uri=$uri";
	my $request = new HTTP::Request(GET => $url);
	my $response = $ua->request($request);

	if ($response->code / 100 != 2) {
		print($writer "Failed to retrieve: $uri (error: " . $response->code . ")");
		return 1;
	}

	# Parse XML result
	my $parser = new XML::DOM::Parser();
	my $dom = $parser->parse($response->decoded_content());
	my $root = $dom->getDocumentElement();

	my $message = undef;
	my %data;

	if ($root->getNodeName() eq "track") {
		$data{'name'} = getTextValue($root, 'name');
		$data{'artist'} = getTextValue($root, 'artist/name');
		$data{'album'} = getTextValue($root, 'album/name');

		# Try to make some perty popularity
		my $popularity = getTextValue($root, 'popularity');
		$data{'popularity'} = '';
		for (my $i = 0; $i < 5; $i++) {
			if (($i*2/10) <= $popularity) { $data{'popularity'} .= '*'; }
			else { $data{'popularity'} .= '-'; }
		}

		$message = Irssi::settings_get_str('spotify_track_format');
		$message =~ s/%(name|artist|album|popularity)/$data{$1}/ge;

	} elsif ($root->getNodeName() eq "album") {
		$data{'name'} = getTextValue($root, 'name');
		$data{'artist'} = getTextValue($root, 'artist/name');
		$data{'year'} = getTextValue($root, 'released');
		$data{'territories'} = getTextValue($root, 'availability/territories');

		$message = Irssi::settings_get_str('spotify_album_format');
		$message =~ s/%(name|artist|year|territories)/$data{$1}/ge;

	} elsif ($root->getNodeName() eq "artist") {
		$data{'name'} = getTextValue($root, 'name');

		$message = Irssi::settings_get_str('spotify_artist_format');
		$message =~ s/%name/$data{'name'}/ge;
	}

	my $charset = Irssi::settings_get_str('term_charset');
	if ($charset =~ /^utf-8/i) {
		binmode $writer, ':utf8';
	} else {
		Encode::from_to($message, "utf-8", Irssi::settings_get_str('term_charset'));
	}

	# Only write header for manual lookups
	if ($manual) {
		my $header = Irssi::settings_get_str('spotify_header_format');
		$header =~ s/%uri/$uri/ge;
		if ($header ne "") { print($writer $header . "\n"); }
	}

	print($writer $message);

	return 0;
}

sub settings_get_array {
	my $key = shift;
	my $value = Irssi::settings_get_str($key);
	return split(/[ :;,]/, $value);
}

sub settings_set_array {
	my ($key, @value) = @_;
	my $str = join(' ', @value);
	Irssi::settings_set_str($key, $str);
}

sub public_lookup_permitted {
	my ($nick, $channel) = @_;

	if (!Irssi::settings_get_bool('spotify_automatic_lookup_public')) {
		return 0;
	}

	# Default lookup policy can either be deny or allow, and matching will
	# invert the default result. If this is True, the policy list will be used
	# as a blacklist. If this is False, the policy list is a whitelist.
	my $blacklist = Irssi::settings_get_bool('spotify_automatic_lookup_public_blacklist');

	sub in_array {
		my ($type, $target) = @_;

		my @array = settings_get_array("spotify_automatic_lookup_public_${type}s");
		foreach my $item (@array) {
			if ($item eq $target) { return 1; }
		}
		return 0;
	}

	if (defined($channel) && in_array('channel', $channel)) {
		return $blacklist ? 0 : 1;
	}
	if (defined($nick) && in_array('nick', $nick)) {
		return $blacklist ? 0 : 1;
	}

	return $blacklist ? 1 : 0;
}

### Signals
Irssi::signal_add_last('message public',  'event_message');
Irssi::signal_add_last('message private', 'event_message');
Irssi::signal_add_last('message topic', 'event_message_topic');

### Commands
Irssi::command_bind('spotify' => sub {
	my ($args, $server, $window) = @_;
	$args =~ s/\s+$//g;
	Irssi::command_runsub('spotify', $args, $server, $window);
});

Irssi::command_bind('spotify help', \&cmd_spotify_help);
Irssi::command_bind('help', \&cmd_help);

Irssi::command_bind('spotify lookup', \&cmd_spotify_lookup);
Irssi::command_bind('spotify -l', \&cmd_spotify_lookup);
Irssi::command_bind('spotify lookup help', \&cmd_spotify_help_lookup);
Irssi::command_bind('spotify lookup -h', \&cmd_spotify_help_lookup);
Irssi::command_bind('spotify lookup public', \&cmd_spotify_lookup);
Irssi::command_bind('spotify lookup -p', \&cmd_spotify_lookup);

Irssi::command_bind('spotify auto', \&cmd_spotify_auto);
Irssi::command_bind('spotify -a', \&cmd_spotify_auto);
Irssi::command_bind('spotify auto help', \&cmd_spotify_help_auto);
Irssi::command_bind('spotify auto -h', \&cmd_spotify_help_auto);
Irssi::command_bind('spotify auto info', \&cmd_spotify_auto_info);
Irssi::command_bind('spotify auto -i', \&cmd_spotify_auto);
Irssi::command_bind('spotify auto enable', \&cmd_spotify_auto);
Irssi::command_bind('spotify auto -e', \&cmd_spotify_auto);
Irssi::command_bind('spotify auto disable', \&cmd_spotify_auto);
Irssi::command_bind('spotify auto -d', \&cmd_spotify_auto);

Irssi::command_bind('spotify auto public', \&cmd_spotify_auto_public);
Irssi::command_bind('spotify auto -p', \&cmd_spotify_auto_public);
Irssi::command_bind('spotify auto public help', \&cmd_spotify_help_auto_public);
Irssi::command_bind('spotify auto public -h', \&cmd_spotify_help_auto_public);
Irssi::command_bind('spotify auto public info', \&cmd_spotify_auto_public);
Irssi::command_bind('spotify auto public -i', \&cmd_spotify_auto_public);
Irssi::command_bind('spotify auto public enable', \&cmd_spotify_auto_public);
Irssi::command_bind('spotify auto public -e', \&cmd_spotify_auto_public);
Irssi::command_bind('spotify auto public disable', \&cmd_spotify_auto_public);
Irssi::command_bind('spotify auto public -d', \&cmd_spotify_auto_public);
Irssi::command_bind('spotify auto public whitelist', \&cmd_spotify_auto_public);
Irssi::command_bind('spotify auto public -w', \&cmd_spotify_auto_public);
Irssi::command_bind('spotify auto public blacklist', \&cmd_spotify_auto_public);
Irssi::command_bind('spotify auto public -b', \&cmd_spotify_auto_public);

Irssi::command_bind('spotify auto public add', \&cmd_spotify_auto_public_add);
Irssi::command_bind('spotify auto public -a', \&cmd_spotify_auto_public_add);
Irssi::command_bind('spotify auto public add nick', \&cmd_spotify_auto_public_add);
Irssi::command_bind('spotify auto public add -n', \&cmd_spotify_auto_public_add);
Irssi::command_bind('spotify auto public add channel', \&cmd_spotify_auto_public_add);
Irssi::command_bind('spotify auto public add -c', \&cmd_spotify_auto_public_add);
Irssi::command_bind('spotify auto public del', \&cmd_spotify_auto_public_del);
Irssi::command_bind('spotify auto public -d', \&cmd_spotify_auto_public_del);
Irssi::command_bind('spotify auto public del nick', \&cmd_spotify_auto_public_del);
Irssi::command_bind('spotify auto public del -n', \&cmd_spotify_auto_public_del);
Irssi::command_bind('spotify auto public del channel', \&cmd_spotify_auto_public_del);
Irssi::command_bind('spotify auto public del -c', \&cmd_spotify_auto_public_del);

### Settings
Irssi::settings_add_bool('spotify', 'spotify_automatic_lookup', 1);
Irssi::settings_add_bool('spotify', 'spotify_automatic_lookup_public', 0);
Irssi::settings_add_bool('spotify', 'spotify_automatic_lookup_public_blacklist', 0);

Irssi::settings_add_str('spotify', 'spotify_header_format',         'Lookup result for %_%uri%_:');
Irssi::settings_add_str('spotify', 'spotify_track_format',          '%_%name%_ by %_%artist%_ (from %album) [%_%popularity%_]');
Irssi::settings_add_str('spotify', 'spotify_album_format',          '%_%name%_ by %_%artist%_ (%year)');
Irssi::settings_add_str('spotify', 'spotify_artist_format',         '%_%name%_');

Irssi::settings_add_str('spotify', 'spotify_automatic_lookup_public_channels', '');
Irssi::settings_add_str('spotify', 'spotify_automatic_lookup_public_nicks', '');
