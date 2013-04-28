package App::cpangrep;

use strict;
use warnings;
use 5.008_005;
use utf8;
use open OUT => qw< :encoding(UTF-8) :std >;

our $VERSION = '0.01';

use URI::Escape qw(uri_escape);
use HTTP::Tiny;
use JSON qw(decode_json);
use CPAN::DistnameInfo;
use Term::ANSIColor qw(GREEN BLUE RED BOLD RESET);

our $DEBUG;

# TODO:
#
#   • Add paging data to api results and support for page=N parameter
#
#   • Support pages, first with --page, then with 'cpangrep
#     next' and 'cpangrep prev' or similar?  something smarter?
#

sub run {
    require Getopt::Long;
    Getopt::Long::GetOptions(
        'd|debug!'  => \$DEBUG,
        'h|help'    => \(my $help),
        'version'   => \(my $version),
    );

    if ($help) {
        print help();
        return 0;
    }
    elsif ($version) {
        print "cpangrep version $VERSION\n";
        return 0;
    }
    elsif (not @ARGV) {
        warn "A query is required.\n\n";
        print help();
        return 1;
    }
    else {
        my $query = join " ", @ARGV;
        debug("Using query «$query»");

        my $search = search($query)
            or return 2;

        display($search);
        return 0;
    }
    return 0;
}

sub help {
    return <<'    USAGE';
usage: cpangrep [--debug] <query>

The query is a Perl regular expression without look-ahead/look-behind.
Several operators are supported as well for advanced use.

See <http://grep.cpan.me/about#re> for more information.

Multiple query arguments will be joined with spaces for convenience.

  --debug       Print debug messages to stderr
  --help        Show this help and exit
  --version     Show version

    USAGE
}

sub search_url     { "http://grep.cpan.me/?q="    . uri_escape(shift) }
sub search_api_url { "http://grep.cpan.me/api?q=" . uri_escape(shift) }

sub search {
    my $query = shift;
    my $ua    = HTTP::Tiny->new(
        agent => "cpangrep/$VERSION",
    );

    my $response = $ua->get( search_api_url($query) );

    if (!$response->{success}) {
        warn "Request failed: $response->{status} $response->{reason}\n";
        return;
    }

    debug("Successfully received " . length($response->{content}) . " bytes");

    my $result = eval { decode_json($response->{content}) };
    if ($@ or not $result) {
        warn "Error decoding response: $@\n";
        return;
    }
    return $result;
}

sub display {
    my $search  = shift or return;
    my $results = $search->{results} || [];
    printf "%d result%s.", $search->{count}, ($search->{count} != 1 ? "s" : "");
    printf "  Showing first %d.\n", scalar @$results
        if @$results;
    print "\n";

    for my $result (@$results) {
        my $fulldist = $result->{dist};
           $fulldist =~ s{^(?=(([A-Z])[A-Z]))}{$2/$1/};
        my $dist = CPAN::DistnameInfo->new($fulldist);

        for my $file (@{$result->{files}}) {
            print GREEN, join("/", $dist->cpanid, $dist->distvname, $file->{file}), RESET, "\n";

            for my $match (@{$file->{results}}) {
                my $snippet = $match->{text};

                substr($snippet, $match->{match}[1], 0) = RESET;
                substr($snippet, $match->{match}[0], 0) = BOLD RED;

                chomp $snippet;
                $snippet =~ s/^/  /mg;

                print $snippet, RESET, "\n\n";

                # XXX TODO: Display line numbers
            }
            printf "  → %d more match%s from this file.\n\n",
                $file->{truncated}, ($file->{truncated} != 1 ? "es" : "")
                    if $file->{truncated};
        }
        printf "→ %d more file%s matched in %s.\n\n",
            $result->{truncated}, ($result->{truncated} != 1 ? "s" : ""), $dist->distvname
                if $result->{truncated};
    }
}

sub debug {
    return unless $DEBUG;
    warn "DEBUG: ", @_, " [", join("/", (caller(1))[3,2]), "]\n";
}

1;
__END__

=encoding utf-8

=head1 NAME

App::cpangrep - Grep CPAN from the command-line using grep.cpan.me

=head1 SYNOPSIS

  cpangrep "\bpackage\s+App::cpangrep\b"

  cpangrep --help

=head1 DESCRIPTION

App::cpangrep provides the C<cpangrep> program which is a command-line
interface for L<http://grep.cpan.me>.

=head1 AUTHOR

Thomas Sibley E<lt>tsibley@cpan.orgE<gt>

=head1 COPYRIGHT

Copyright 2013- Thomas Sibley

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 SEE ALSO

L<cpangrep>, L<http://grep.cpan.me>

=cut
