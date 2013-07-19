package App::cpangrep;

use strict;
use warnings;
use 5.008_005;
use utf8;
use open OUT => qw< :encoding(UTF-8) :std >;

our $VERSION = '0.03';

use Config;
use URI::Escape qw(uri_escape);
use LWP::UserAgent;
use JSON qw(decode_json);
use CPAN::DistnameInfo;

our $SERVER = "http://grep.cpan.me";
our $COLOR;
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
        'color!'    => \$COLOR,
        'd|debug!'  => \$DEBUG,
        'h|help'    => \(my $help),
        'version'   => \(my $version),

        'l'         => \(my $list),
        'server=s'  => \$SERVER,
    );

    setup_colors() unless defined $COLOR and not $COLOR;

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

        if ($list) {
            display_list($search);
        } else {
            display($search);
        }
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

  -l            List only matching filenames.  Note that omitted results are
                not mentioned, but your pattern is likely to match many more
                files than output.

  --color       Enable colored output even if STDOUT isn't a terminal
  --no-color    Disable colored output

  --server      Specifies an alternate server to use, for example:
                    --server http://localhost:5000

  --debug       Print debug messages to stderr
  --help        Show this help and exit
  --version     Show version

    USAGE
}

sub search_url     { "$SERVER/?q="    . uri_escape(shift) }
sub search_api_url { "$SERVER/api?q=" . uri_escape(shift) }

sub search {
    my $query = shift;
    my $ua    = LWP::UserAgent->new(
        agent => "cpangrep/$VERSION",
    );
    $ua->env_proxy;

    my $response = $ua->get( search_api_url($query) );

    if (not $response->is_success) {
        warn "Request failed: ", $response->status_line, "\n";
        return;
    }

    my $content = $response->decoded_content;
    debug("Successfully received " . length($content) . " bytes");

    my $result = eval { decode_json($content) };
    if ($@ or not $result) {
        warn "Error decoding JSON response: $@\n";
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
            print colored(["GREEN"], join("/", $dist->cpanid, $dist->distvname, $file->{file})), "\n";

            for my $match (@{$file->{results}}) {
                my $snippet = $match->{text};

                my ($start, $len) = @{$match->{match}};
                $len -= $start;

                substr($snippet, $start, $len) = colored(substr($snippet, $start, $len), "BOLD RED");

                if ($match->{line}) {
                    my $ln       = $match->{line}[0] - (substr($snippet, 0, $start) =~ y/\n//);
                    my $print_ln = sub {
                        colored($ln++, "BLUE") . colored(":", "CYAN")
                    };
                    $snippet =~ s/^/$print_ln->()/mge;
                }

                chomp $snippet;
                print $snippet, color("reset"), "\n\n";
            }
            printf colored("  → %d more match%s from this file.\n\n", "MAGENTA"),
                $file->{truncated}, ($file->{truncated} != 1 ? "es" : "")
                    if $file->{truncated};
        }
        printf colored("→ %d more file%s matched in %s.\n\n", "MAGENTA"),
            $result->{truncated}, ($result->{truncated} != 1 ? "s" : ""), $dist->distvname
                if $result->{truncated};
    }
}

sub display_list {
    my $search  = shift or return;
    my $results = $search->{results} || [];
    for my $result (@$results) {
        my $fulldist = $result->{dist};
           $fulldist =~ s{^(?=(([A-Z])[A-Z]))}{$2/$1/};
        my $dist = CPAN::DistnameInfo->new($fulldist);

        for my $file (@{$result->{files}}) {
            print join("/", $dist->cpanid, $dist->distvname, $file->{file}), "\n";
        }
    }
}

# Setup colored output if we have it
sub setup_colors {
    eval { require Term::ANSIColor };
    if ( not $@ and supports_color() ) {
        $Term::ANSIColor::EACHLINE = "\n";
        *color   = *_color_real;
        *colored = *_colored_real;
    }
}

# No-op passthrough defaults
sub color           { "" }
sub colored         { ref $_[0] ? @_[1..$#_] : $_[0] }
sub _color_real     { Term::ANSIColor::color(@_) }
sub _colored_real   { Term::ANSIColor::colored(@_) }

sub supports_color {
    # We're not on a TTY and don't force it, kill color
    return 0 unless -t *STDOUT or $COLOR;

    if ( $Config{'osname'} eq 'MSWin32' ) {
        eval { require Win32::Console::ANSI; };
        return 1 if not $@;
    }
    else {
        return 1 if $ENV{'TERM'} =~ /^(xterm|rxvt|linux|ansi|screen)/;
        return 1 if $ENV{'COLORTERM'};
    }
    return 0;
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
