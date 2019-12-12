#!/Users/brian/bin/perls/perl-5.28.1
use v5.26;
use utf8;
use strict;
use warnings;

use Text::CSV_XS;
use Time::Moment;

my @schedules = glob( 'mlb_schedules/*.csv' );

my @grand = ();
foreach my $schedule ( @schedules ) {
	my( $team ) = $schedule =~ m| / (\S+?) \. |x;

	my $csv = Text::CSV_XS->new ({ binary => 1, auto_diag => 1 });
	open my $fh, "<:encoding(utf8)", $schedule or die "$schedule: $!";
	my $header = readline($fh);

	while( my $row = $csv->getline($fh) ) {
		my( $date, $time ) = $row->@[0,1];
		my( $month, $day, $year ) = split m|/|, $date;
		my $tm = Time::Moment->new(
			year  => $year,
			month => $month,
			day   => $day
			);
		my $day_of_week = (
			qw(foo Monday Tuesday Wednesday Thursday Friday Saturday Sunday)
			)[$tm->day_of_week];
		push @grand, [$team, $day_of_week, $date, $time];
		}
	close $fh;
	}

@grand = sort { $a->[2] cmp $b->[2] or $a->[0] cmp $b->[0] } @grand;

my $grand_filename = 'grand.csv';
open my $fh, ">:encoding(utf8)", $grand_filename or die "$grand_filename: $!";
my $csv = Text::CSV_XS->new ({ binary => 1, auto_diag => 1 });
$csv->say( *STDOUT, $_ ) for @grand;
$csv->say( $fh, $_ ) for @grand;
close $fh or die "new.csv: $!";
