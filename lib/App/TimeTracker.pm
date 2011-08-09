package App::TimeTracker;
use strict;
use warnings;
use 5.010;

our $VERSION = "2.008";
# ABSTRACT: Track time spend on projects from the commandline

use App::TimeTracker::Data::Task;

use DateTime;
use Moose;
use Moose::Util::TypeConstraints;
use Path::Class::Iterator;
use MooseX::Storage::Format::JSONpm;

our $HOUR_RE = qr/(?<hour>[012]?\d)/;
our $MINUTE_RE = qr/(?<minute>[0-5]?\d)/;
our $DAY_RE = qr/(?<day>[0123]?\d)/;
our $MONTH_RE = qr/(?<month>[01]?\d)/;
our $YEAR_RE = qr/(?<year>2\d{3})/;

with qw(
    MooseX::Getopt
);

subtype 'TT::DateTime' => as class_type('DateTime');
subtype 'TT::RT' => as 'Int';

coerce 'TT::RT'
    => from 'Str'
    => via {
    my $raw = $_;
    $raw=~s/\D//g;
    return $raw;
};

coerce 'TT::DateTime'
    => from 'Str'
    => via {
    my $raw = $_;
    my $dt = DateTime->now;
    $dt->set_time_zone('local');

    given ($raw) {
        when(/^ $HOUR_RE : $MINUTE_RE $/x) { # "13:42"
            $dt = DateTime->today;
            $dt->set(hour=>$+{hour}, minute=>$+{minute});
        }
        when(/^ $YEAR_RE [-.]? $MONTH_RE [-.]? $DAY_RE $/x) { # "2010-02-26"
            $dt = DateTime->today;
            $dt->set(year => $+{year}, month=>$+{month}, day=>$+{day});
        }
        when(/^ $YEAR_RE [-.]? $MONTH_RE [-.]? $DAY_RE \s+ $HOUR_RE : $MINUTE_RE $/x) { # "2010-02-26 12:34"
            $dt = DateTime->new(year => $+{year}, month=>$+{month}, day=>$+{day}, hour=>$+{hour}, minute=>$+{minute});
        }
        when(/^ $DAY_RE [-.]? $MONTH_RE [-.]? $YEAR_RE $/x) { # "26-02-2010"
            $dt = DateTime->today;
            $dt->set(year => $+{year}, month=>$+{month}, day=>$+{day});
        }
        when(/^ $DAY_RE [-.]? $MONTH_RE [-.]? $YEAR_RE \s $HOUR_RE : $MINUTE_RE $/x) { # "26-02-2010 12:34"
            $dt = DateTime->new(year => $+{year}, month=>$+{month}, day=>$+{day}, hour=>$+{hour}, minute=>$+{minute});
        }
        default {
            confess "Invalid date format '$raw'";
        }
    }
    return $dt;
};

MooseX::Getopt::OptionTypeMap->add_option_type_to_map(
    'TT::DateTime' => '=s',
);
MooseX::Getopt::OptionTypeMap->add_option_type_to_map(
    'TT::RT' => '=i',
);

no Moose::Util::TypeConstraints;

has 'home' => (
    is=>'ro',
    isa=>'Path::Class::Dir',
    traits => [ 'NoGetopt' ],
    required=>1,
);
has 'config' => (
    is=>'ro',
    isa=>'HashRef',
    required=>1,
    traits => [ 'NoGetopt' ],
);
has '_currentproject' => (
    is=>'ro',
    isa=>'Str',
    traits => [ 'NoGetopt' ],
);

has 'tags' => (
    isa=>'ArrayRef',
    is=>'ro',
    traits  => ['Array'],
    default=>sub {[]},
    handles => {
        insert_tag  => 'unshift',
        add_tag  => 'push',
    },
    documentation => 'Tags [Multiple]',
);

has '_current_command' => (
    isa=>'Str',
    is=>'rw',
    traits => [ 'NoGetopt' ],
);

has '_current_task' => (
    isa=>'App::TimeTracker::Data::Task',
    is=>'rw',
    traits => [ 'NoGetopt' ],
);

has '_previous_task' => (
    isa=>'App::TimeTracker::Data::Task',
    is=>'rw',
    traits => [ 'NoGetopt' ],
);

sub run {
    my $self = shift;
    my $command = 'cmd_'.($self->extra_argv->[0] || 'missing');

    $self->cmd_commands unless $self->can($command);
    $self->_current_command($command);
    $self->$command;
}

sub now {
    my $dt = DateTime->now();
    $dt->set_time_zone('local');
    return $dt;
}

sub beautify_seconds {
    my ( $self, $s ) = @_;
    return '0' unless $s;
    my ( $m, $h )= (0, 0);

    if ( $s >= 60 ) {
        $m = int( $s / 60 );
        $s = $s - ( $m * 60 );
    }
    if ( $m && $m >= 60 ) {
        $h = int( $m / 60 );
        $m = $m - ( $h * 60 );
    }
    return sprintf("%02d:%02d:%02d",$h,$m,$s);
}

sub find_task_files {
    my ($self, $args) = @_;

    my ($cmp_from, $cmp_to);

    if (my $from = $args->{from}) {
        my $to = $args->{to} || $self->now;
        $to->set(hour=>23,minute=>59,second=>59) unless $to->hour;
        $cmp_from = $from->strftime("%Y%m%d%H%M%S");
        $cmp_to = $to->strftime("%Y%m%d%H%M%S");
    }
    my $projects;
    if ($args->{projects}) {
        $projects = join('|',@{$args->{projects}});
    }

    my @found;
    my $iterator = Path::Class::Iterator->new(
        root => $self->home,
    );
    until ($iterator->done) {
        my $file = $iterator->next;
        next unless -f $file;
        my $name = $file->basename;
        next unless $name =~/\.trc$/;

        if ($cmp_from) {
            $file =~ /(\d{8})-(\d{6})/;
            my $time = $1 . $2;
            next if $time < $cmp_from;
            next if $time > $cmp_to;
        }

        next if $projects && ! ($name ~~ /$projects/);

        push(@found,$file);
    }
    return sort @found;
}

1;



=pod

=head1 NAME

App::TimeTracker - Track time spend on projects from the commandline

=head1 VERSION

version 2.008

=head1 CONTRIBUTORS

Maros Kollar C<< <maros@cpan.org> >>, Klaus Ita C<< <klaus@worstofall.com> >>

=head1 AUTHOR

Thomas Klausner <domm@cpan.org>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2011 by Thomas Klausner.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut


__END__



