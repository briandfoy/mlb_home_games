#!/Users/brian/bin/perls/perl5.28.0
use v5.28;
use utf8;
use strict;
use warnings;

use File::Path qw(make_path);
use File::Spec::Functions;
use IO::Interactive qw(interactive);
use Mojo::Useragent;
use Term::ANSIColor;

=encoding utf8

=head1 NAME

mlb_home_games.pl

=head1 SYNPOSIS

	$ perl download_home_games.pl

	# extra info if things aren't working
	$ DEBUG=1 perl download_home_games.pl

=head1 DESCRIPTION

This small Mojolicious program grabs the home game schedules for Major
League Baseball teams. At the beginning of 2019, each team has a
schedule page with a link to a CSV file.

In the current working directory, it creates a directory named
F<mlb_schedules> where each team gets a CSV file named after the team
(such as F<redsox.csv>).

This script starts at the team's main page and gets the downloadable
schedule link (except for the Brewers, which has no link). From the
download page, it gets the final link to the CSV file. It has to fix up
that URL because the host isn't correct.

=head2 Some exceptions

The Brewers don't link to their downloadable schedule but the URL is
there. I guess it based on the URL most common for other teams.

The link for the Braves is actually a redirect.

Most teams use this URL:

	https://www.mlb.com/$team/fans/downloadable-schedule

But a couple use:

	https://www.mlb.com/$team/schedule/downloadable-schedule

=head2 Debugging

Set the DEBUG environment variable to some true value. You'll get
extra output along the way.

Setting the MOJO_CLIENT_DEBUG to a true value will start debugging
the guts.

=head1 LICENSE

You can use, modify, and distribute this program under the Artistic
License 2.0.

L<https://opensource.org/licenses/Artistic-2.0>

=head1 COPYRIGHT

Copyright © 2019, brian d foy, All rights reserved.

=cut

my $DEBUG = $ENV{DEBUG} // 0;

my $ua = Mojo::UserAgent->new;
$ua->max_redirects(3); # braves needs this

my $base_url = Mojo::URL->new( 'https://www.mlb.com' );
my $tx = $ua->get( $base_url );

# Fetch the list of team names. Grab this from the "Teams" nav bar
# link in the main MLB page.
my @teams = $tx->result->dom
	->find( "a.teams-navbar-module__team-link" )
	->map( attr => 'href' )
	->map( sub { Mojo::URL->new($_)->path =~ s|\A/||gr } )
	->each;

my $dir = 'mlb_schedules';
make_path( $dir ) unless -d $dir;

foreach my $team ( @teams ) {
	say { interactive } "Processing <$team>";

	my $save_to = catfile( $dir, "$team.csv" );
	if( -e $save_to and ! -z $save_to ) {
		say { interactive } "\tAlready have file for <$team>";
		next;
		}

	# The main team page
	my $teams_tx = $ua->get( Mojo::URL->new("/$team")->base($base_url)->to_abs );
	unless( $teams_tx->res->is_success ) {
		say { interactive } "\tCould not fetch main page for <$team>\n";
		next;
		}

	# Find the download link. This isn't the same for each team, and
	# the text for that download link is not the same for each team
	# Some have:
	#
	#    Downloadable Schedule
	#    2019 Downloadable Schedule
	my $download_link = $teams_tx->res->dom
		# the $= CSS selector matches literal text at the end of this attribute
		->find( 'a[data-sub-nav-name$="Downloadable Schedule"]' )
		->map( attr => 'href' )
		->first;
	unless( $download_link ) {
		say { interactive } "\tCouldn't find download link for <$team>. Guessing.";
		# the Brewers don't link to their schedule so guess this one
		$download_link = "https://www.mlb.com/$team/fans/downloadable-schedule";
		}

	$download_link = Mojo::URL->new( $download_link )->base($base_url)->to_abs;
	say colored(['cyan'], "\tDownload link for <$team> => $download_link") if $DEBUG;

	# Get the general download page that has the links to the CSV
	# files
	my $download_tx = $ua->get( $download_link );
	unless( $download_tx->res->is_success ) {
		say { interactive } sprintf "\tDownload link for <$team> failed: %s: %s",
			map { $download_tx->res->$_() } qw(message code);
		next;
		}
	$download_tx->res->save_to( catfile( $dir, "$team.html") );

	# So far all of the download pages have the same link text but
	# that might change.
	my $csv_link = $download_tx->result->dom
		->find( 'a' )
		->grep( sub { $_->text eq 'Download Home Game Schedule' } )
		->map( attr => 'href' )
		->first;
	unless( $csv_link ) {
		warn colored(['red'], "\tNo CSV link for <$team>\n");
		next;
		}

	$csv_link = Mojo::URL->new($csv_link);
	# This happens inside the page through some sort of sorcery.
	# It's extracted as mlb.mlb.com (and that is a 404)
	$csv_link->host( 'www.ticketing-client.com' );
	say colored(['cyan'], "\tCSV link for <$team>: $csv_link") if $DEBUG;

	# Finally, the file I'm after. Ensure that it's actually a CSV
	# file because sometimes it's an error page.
	my $schedule_tx = $ua->get( $csv_link );
	my $content_type = $schedule_tx->result->headers->content_type;
	unless( $content_type =~ m/\A text\/csv (?: ; | \z ) /x ) {
		warn colored(['red'], "\tDid not get a text/csv content type for <$team>\n");
		next;
		}

	$schedule_tx->result->save_to( $save_to );
	}
