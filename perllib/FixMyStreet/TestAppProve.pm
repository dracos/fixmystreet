use strict; use warnings;
package FixMyStreet::TestAppProve;
use App::Prove;

use YAML ();
use Path::Tiny 'path';
use Test::PostgreSQL;
use Data::Dumper;
use Getopt::Long ':config' => qw(bundling pass_through no_ignore_case);

=head1 NAME

FixMyStreet::TestAppProve - spin up a clean database and configuration for tests

=head1 USAGE

see bin/test-wrapper for usage

=cut

sub run {
    my ($class, @args) = @_;
    local @ARGV = @args;

    my $config_file = 'conf/general.yml-example';
    my $db_config_file;

    my $recurse;
    my @state;

    GetOptions (
        # our own config variables
        'config=s'    => \$config_file,
        'db-config=s' => \$db_config_file,

        # App::Prove variables we want to munge
        'r|recurse' => \$recurse,
        'state=s@'  => \@state,
    );

    my $config = YAML::Load( path($config_file)->slurp );
    my $pg;
    if ($db_config_file) {
        my $db_config = YAML::Load( path($db_config_file)->slurp );
        $config->{FMS_DB_PORT} = $db_config->{FMS_DB_PORT};
        $config->{FMS_DB_NAME} = $db_config->{FMS_DB_NAME};
        $config->{FMS_DB_USER} = $db_config->{FMS_DB_USER};
        $config->{FMS_DB_HOST} = $db_config->{FMS_DB_HOST};
        $config->{FMS_DB_PASS} = $db_config->{FMS_DB_PASS};
    }
    else {
        warn "Spinning up a Pg cluster/database...\n";
        $pg = Test::PostgreSQL->new();

        warn sprintf "# Connected to %s\n", $pg->dsn;

        my $dbh = DBI->connect($pg->dsn);

        my $tmpwarn = $SIG{__WARN__};
        $SIG{__WARN__} =
          sub { print STDERR @_ if $_[0] !~ m/NOTICE:  CREATE TABLE/; };
        $dbh->do( path('db/schema.sql')->slurp ) or die $!;
        $dbh->do( path('db/alert_types.sql')->slurp ) or die $!;
        $dbh->do( path('db/generate_secret.sql')->slurp ) or die $!;
        $SIG{__WARN__} = $tmpwarn;

        $config->{FMS_DB_PORT} = $pg->port;
        $config->{FMS_DB_NAME} = 'test';
        $config->{FMS_DB_USER} = 'postgres';
        $config->{FMS_DB_HOST} = 'localhost';
        $config->{FMS_DB_PASS} = '';
    }

    my $config_out = 'general.test-autogenerated';
    path("conf/$config_out.yml")->spew( YAML::Dump($config) );

    local $ENV{FMS_OVERRIDE_CONFIG} = $config_out;

    if (@ARGV and -e $ARGV[-1]) {
        unshift @ARGV, '--verbose'
            if -f $ARGV[-1];
            # verbose if we have a single file
    }

    unshift @ARGV,
        '--recurse',                             # we always want to recurse
        '--state', (join ',' => @state, 'save'); # we always want to save state

    my $prove = App::Prove->new;
    $prove->process_args(@ARGV);
    $prove->run;
}

1;
