package App::TimeTracker::Proto;
use strict;
use warnings;
use 5.010;

# ABSTRACT: App::TimeTracker Proto Class

use App::TimeTracker::Utils qw(error_message);

use Moose;
use MooseX::Types::Path::Class;
use File::HomeDir ();
use Path::Class;
use Hash::Merge qw(merge);
use JSON::XS;
use Carp;
use Try::Tiny;

use App::TimeTracker::Data::Task;

has 'home' => (
    is         => 'ro',
    isa        => 'Path::Class::Dir',
    lazy_build => 1,
);
sub _build_home {
    my $self = shift;
    my $home =
        Path::Class::Dir->new( File::HomeDir->my_home, '.TimeTracker' );
    $home->mkpath unless -d $home;
    return $home;
}

has 'global_config_file' => (
    is         => 'ro',
    isa        => 'Path::Class::File',
    lazy_build => 1,
);
sub _build_global_config_file {
    my $self = shift;
    return $self->home->file('tracker.json');
}

has 'config_file_locations' => (
    is         => 'ro',
    isa        => 'HashRef',
    lazy_build => 1,
);
sub _build_config_file_locations {
    my $self = shift;
    my $file = $self->home->file('projects.json');
    if (-e $file && -s $file) {
        return decode_json($file->slurp);
    }
    else {
        return {};
    }
}

has 'project' => (is=>'rw',isa=>'Str',predicate => 'has_project');

has 'json_decoder' => (is=>'ro',isa=>'JSON::XS',lazy_build=>1);
sub _build_json_decoder {
    my $self = shift;
    return JSON::XS->new->utf8->pretty->relaxed;
}

sub run {
    my $self = shift;

    my $config = $self->load_config;

    # unique plugins
    $config->{plugins} ||= [];
    my %plugins_unique = map {$_ =>  1} @{$config->{plugins}};
    $config->{plugins} = [ keys %plugins_unique ];

    my $class = Moose::Meta::Class->create_anon_class(
        superclasses => ['App::TimeTracker'],
        roles        => [
            map { 'App::TimeTracker::Command::' . $_ } 'Core', @{ $config->{plugins} }
        ],
    );

    my %commands;
    foreach my $method ($class->get_all_method_names) {
        next unless $method =~ /^cmd_/;
        $method =~ s/^cmd_//;
        $commands{$method}=1;
    }

    my $load_attribs_for_command;
    foreach (@ARGV) {
        if ($commands{$_}) {
            $load_attribs_for_command='_load_attribs_'.$_;
            last;
        }
    }
    if ($load_attribs_for_command && $class->has_method($load_attribs_for_command)) {
        $class->name->$load_attribs_for_command($class);
    }
    $class->make_immutable();

    $class->name->new_with_options( {
            home            => $self->home,
            config          => $config,
            ($self->has_project ? (_current_project=> $self->project) : ()),
        } )->run;
}

sub load_config {
    my ($self, $dir) = @_;
    $dir ||= Path::Class::Dir->new->absolute;
    my $config={};
    my @used_config_files;
    my $cfl = $self->config_file_locations;

    my $project;
    my $projects = $self->slurp_projects;
    my $opt_parser = Getopt::Long::Parser->new( config => [ qw( no_auto_help pass_through ) ] );
    $opt_parser->getoptions( "project=s" => \$project );

    if (defined $project) {
        if (my $project_config = $projects->{$project}) {
            $self->project($project);
            $dir = Path::Class::Dir->new($project_config);
        } else {
            my $error = "Cannot find project: $project\nKnown projects are:\n";
            foreach (keys %$projects) {
                $error .= "   ".$_."\n";
            }
            error_message($error);
            exit;
        }
    }

    WALKUP: while (1) {
        my $config_file = $dir->file('.tracker.json');
        my $this_config;
        if (-e $config_file) {
            push(@used_config_files, $config_file->stringify);
            $this_config = $self->slurp_config($config_file);
            $config = merge($config, $this_config);

            my @path = $config_file->parent->dir_list;
            my $project = $path[-1];
            $cfl->{$project}=$config_file->stringify;

            $self->project($project)
                unless $self->has_project;

        }
        last WALKUP if $dir->parent eq $dir;

        if (my $parent = $this_config->{'parent'}) {
            if ($projects->{$parent}) {
                $dir = Path::Class::file($projects->{$parent})->parent;
                say $dir;
            }
            else {
                $dir = $dir->parent;
                say "Cannot find project >$parent< that's specified as a parent in $config_file";
            }
        }
        else {
            $dir = $dir->parent;
        }
    }

    $self->_write_config_file_locations($cfl);

    if (-e $self->global_config_file) {
        push(@used_config_files, $self->global_config_file->stringify);
        $config = merge($config, $self->slurp_config( $self->global_config_file ));
    }
    $config->{_used_config_files} = \@used_config_files;

    return $config;
}

sub _write_config_file_locations {
    my ($self, $cfl) = @_;
    my $fh = $self->home->file('projects.json')->openw;
    print $fh $self->json_decoder->encode($cfl || $self->config_file_locations);
    close $fh;
}

sub slurp_config {
    my ($self, $file ) = @_;
    try {
        my $content = $file->slurp( iomode => '<:encoding(UTF-8)' );
        return $self->json_decoder->decode( $content );
    }
    catch {
        error_message("Cannot parse config file $file:\n%s",$_);
        exit;
    };
}

sub slurp_projects {
    my $self = shift;
    my $file = $self->home->file('projects.json');
    unless (-e $file && -s $file) {
        error_message("Cannot find projects.json\n");
        exit;
    }
    my $projects = decode_json($file->slurp);
    return $projects;
}

1;



=pod

=head1 NAME

App::TimeTracker::Proto - App::TimeTracker Proto Class

=head1 VERSION

version 2.010

=head1 DESCRIPTION

ugly internal stuff, see upcoming YAPC::Europe 2011 talk...

=head1 AUTHOR

Thomas Klausner <domm@cpan.org>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2011 by Thomas Klausner.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut


__END__
