package App::TimeTracker::Command::Core;
use strict;
use warnings;
use 5.010;

# ABSTRACT: App::TimeTracker Core commands

use Moose::Role;
use File::Copy qw(move);
use File::Find::Rule;
use Data::Dumper;

sub cmd_start {
    my $self = shift;

    $self->cmd_stop('no_exit');
    
    my $task = App::TimeTracker::Data::Task->new({
        start=>$self->at || $self->now,
        project=>$self->project,
        tags=>$self->tags,
        description=>$self->description,
    });
    $self->_current_task($task);

    $task->do_start($self->home);
}

sub cmd_stop {
    my ($self, $dont_exit) = @_;

    my $task = App::TimeTracker::Data::Task->current($self->home);
    unless ($task) {
        return if $dont_exit;
        say "Currently not working on anything";
        exit;
    }
    $self->_previous_task($task);

    $task->stop($self->at || $self->now);
    $task->save($self->home);
    
    move($self->home->file('current')->stringify,$self->home->file('previous')->stringify);
    
    say "Worked ".$task->duration." on ".$task->say_project_tags;
}

sub cmd_current {
    my $self = shift;
    
    if (my $task = App::TimeTracker::Data::Task->current($self->home)) {
        say "Working ".$task->_calc_duration($self->now)." on ".$task->say_project_tags;
    }
    elsif (my $prev = App::TimeTracker::Data::Task->previous($self->home)) {
        say "Currently not working on anything, but the last thing you worked on was:";
        say $prev->say_project_tags;
    }
    else {
        say "Currently not working on anything, and I have no idea what you worked on earlier...";
    }
}

sub cmd_append {
    my $self = shift;

    if (my $task = App::TimeTracker::Data::Task->current($self->home)) {
        say "Cannot 'append', you're actually already working on :"
            . $task->say_project_tags . "\n";
    }
    elsif (my $prev = App::TimeTracker::Data::Task->previous($self->home)) {

        my $task = App::TimeTracker::Data::Task->new({
            start=>$prev->stop,
            project => $self->project,
            tags=>$self->tags,
        });
        $self->_current_task($task);
        $task->do_start($self->home);
    }
    else {
        say "Currently not working on anything and I have no idea what you've been doing.";
    }
}

sub cmd_continue {
    my $self = shift;

    if (my $task = App::TimeTracker::Data::Task->current($self->home)) {
        say "Cannot 'continue', you're working on something:\n".$task->say_project_tags;
    }
    elsif (my $prev = App::TimeTracker::Data::Task->previous($self->home)) {
        my $task = App::TimeTracker::Data::Task->new({
            start=>$self->at || $self->now,
            project=>$prev->project,
            tags=>$prev->tags,
        });
        $self->_current_task($task);
        $task->do_start($self->home);
    }
    else {
        say "Currently not working on anything, and I have no idea what you worked on earlier...";
    }
}

sub cmd_worked {
    my $self = shift;

    my @files = $self->find_task_files({
        from=>$self->from,
        to=>$self->to,
        projects=>$self->projects,
    });

    my $total=0;
    foreach my $file ( @files ) {
        my $task = App::TimeTracker::Data::Task->load($file->stringify);
        $total+=$task->seconds // $task->_build_seconds;
    }

    say $self->beautify_seconds($total);
}

sub cmd_report {
    my $self = shift;

    my @files = $self->find_task_files({
        from=>$self->from,
        to=>$self->to,
        projects=>$self->projects,
    });

    my $total = 0;
    my $report={};
    my $format="%- 20s % 12s\n";

    foreach my $file ( @files ) {
        my $task = App::TimeTracker::Data::Task->load($file->stringify);
        my $time = $task->seconds // $task->_build_seconds;
        my $project = $task->project;

        if ($time >= 60*60*8) {
            say "Found dubious trackfile: ".$file->basename;
            say "  Are you sure you worked ".$self->beautify_seconds($time)." on one task?";
        }

        $total+=$time;

        $report->{$project}{'_total'} += $time;

        if ( $self->detail ) {
            my $tags = $task->tags;
            if (@$tags) {
                foreach my $tag ( @$tags ) {
                    $report->{$project}{$tag} += $time;
                }
            }
            else {
                $report->{$project}{'_untagged'} += $time;
            }
        }
        if ($self->verbose) {
            printf("%- 40s -> % 8s\n",$file->basename, $self->beautify_seconds($time));
        }
    }

# TODO: calc sum for parent(s)
#    foreach my $project (keys %$report) {
#        my $parent = $project_map->{$project}{parent};
#        while ($parent) {
#            $report->{$parent}{'_total'}+=$report->{$project}{'_total'} || 0;
#            $report->{$parent}{$project} = $report->{$project}{'_total'} || 0;
#            $parent = $project_map->{$parent}{parent};
#        }
#    }

    my $padding='';
    my $tagpadding='   ';
    foreach my $project (sort keys %$report) {
        my $data = $report->{$project};
        printf( $padding.$format, $project, $self->beautify_seconds( delete $data->{'_total'} ) );
        printf( $padding.$tagpadding.$format, 'untagged', $self->beautify_seconds( delete $data->{'_untagged'} ) ) if $data->{'_untagged'};

        if ( $self->detail ) {
            foreach my $tag ( sort { $data->{$b} <=> $data->{$a} } keys %{ $data } ) {
                my $time = $data->{$tag};
                printf( $padding.$tagpadding.$format, $tag, $self->beautify_seconds($time) );
            }
        }
    }
    #say '=' x 35;
    printf( $format, 'total', $self->beautify_seconds($total) );
}

sub cmd_recalc_trackfile {
    my $self = shift;
    my $file = $self->trackfile;
    unless (-e $file) {
        $file =~ /(?<year>\d\d\d\d)(?<month>\d\d)\d\d-\d{6}_\w+\.trc/;
        if ($+{year} && $+{month}) {
            $file = $self->home->file($+{year},$+{month},$file)->stringify;
            unless (-e $file) {
                say "Cannot find file ".$self->trackfile;
                exit;
            }
        }
    }

    my $task = App::TimeTracker::Data::Task->load($file);
    $task->save($self->home);
    say "recalced $file";
}

sub cmd_show_config {
    my $self = shift;
    warn Data::Dumper::Dumper $self->config;
}

sub cmd_init {
    my $self = shift;
    my $cwd = Path::Class::Dir->new->absolute;
    if (-e $cwd->file('.tracker.json')) {
        say "This directory is already set up.\nTry 'tracker show_config' to see the current aggregated config.";
        exit;
    }

    my @dirs = $cwd->dir_list;
    my $project = $dirs[-1];
    my $fh = $cwd->file('.tracker.json')->openw;
    say $fh <<EOCONFIG;
{
    "project":"$project"
}
EOCONFIG
    say "Set up this directory for time-tracking via file .tracker.json";
}

sub cmd_plugins {
    my $self = shift;

    my $base = Path::Class::file($INC{'App/TimeTracker/Command/Core.pm'})->parent;
    my @hits;
    while (my $file = $base->next) {
        next unless -f $file;
        next if $file->basename eq 'Core.pm';
        my $plugin = $file->basename;
        $plugin =~s/\.pm$//;
        push(@hits, $plugin);
    }
    say "Installed plugins:\n  ".join(', ',@hits);
}

sub cmd_commands {
    my $self = shift;

    say "Available commands:";
    foreach my $method ($self->meta->get_all_method_names) {
        next unless $method =~ /^cmd_/;
        $method =~ s/^cmd_//;
        say "\t$method";
    }
    exit;
}

sub _load_attribs_worked {
    my ($class, $meta) = @_;
    $meta->add_attribute('from'=>{
        isa=>'TT::DateTime',
        is=>'ro',
        coerce=>1,
        lazy_build=>1,
        #cmd_aliases => [qw/start/],
    });
    $meta->add_attribute('to'=>{
        isa=>'TT::DateTime',
        is=>'ro',
        coerce=>1,
        #cmd_aliases => [qw/end/],
        lazy_build=>1,
    });
    $meta->add_attribute('this'=>{
        isa=>'Str',
        is=>'ro',
    });
    $meta->add_attribute('last'=>{
        isa=>'Str',
        is=>'ro',
    });
    $meta->add_attribute('projects'=>{
        isa=>'ArrayRef[Str]',
        is=>'ro',
    });
}
sub _load_attribs_report {
    my ($class, $meta) = @_;
    $class->_load_attribs_worked($meta);
    $meta->add_attribute('detail'=>{
        isa=>'Bool',
        is=>'ro',
        documentation=>'Be detailed',
    });
    $meta->add_attribute('verbose'=>{
        isa=>'Bool',
        is=>'ro',
        documentation=>'Be verbose',
    });
}

sub _load_attribs_start {
    my ($class, $meta) = @_;
    $meta->add_attribute('at'=>{
        isa=>'TT::DateTime',
        is=>'ro',
        coerce=>1,
        documentation=>'Start at',
    });
    $meta->add_attribute('project'=>{
        isa=>'Str',
        is=>'ro',
        documentation=>'Project name',
        lazy_build=>1,
    });
    $meta->add_attribute('description'=>{
        isa=>'Str',
        is=>'rw',
        documentation=>'Description',
    });
}

sub _build_project {
    my $self = shift;
    return $self->_currentproject;
}

*_load_attribs_append = \&_load_attribs_start;
*_load_attribs_continue = \&_load_attribs_start;
*_load_attribs_stop = \&_load_attribs_start;

sub _load_attribs_recalc_trackfile {
    my ($class, $meta) = @_;
    $meta->add_attribute('trackfile'=>{
        isa=>'Str',
        is=>'ro',
        required=>1,
    });
}

sub _build_from {
    my $self = shift;
    if (my $last = $self->last) {
        return $self->now->truncate( to => $last)->subtract( $last.'s' => 1 );
    }
    elsif (my $this = $self->this) {
        return $self->now->truncate( to => $this);
    }
}

sub _build_to {
    my $self = shift;
    my $dur = $self->this || $self->last;
    return $self->from->clone->add( $dur.'s' => 1 );
}

no Moose::Role;
1;



=pod

=head1 NAME

App::TimeTracker::Command::Core - App::TimeTracker Core commands

=head1 VERSION

version 2.009

=head1 CORE COMMANDS

More commands are implemented in various plugins. Plugins might also alter and/or amend commands.

=head2 start

    ~/perl/Your-Project$ tracker start
    Started working on Your-Project at 23:44:19

Start tracking the current project now. Automatically stop the previous task, if there was one.

B<Options:>

=over

=item --at TT::DateTime

    ~/perl/Your-Project$ tracker start --at 12:42
    ~/perl/Your-Project$ tracker start --at '2011-02-26 12:42'

Start at the specified time/datetime instead of now. If only a time is
provided, the day defaults to today. See L<TT::DateTime> in L<App::TimeTracker>.

=item --project SomeProject

  ~/perl/Your-Project$ tracker start --project SomeProject

Use the specified project instead of the one determined by the current
working directory.

=item --description 'some prosa'

  ~/perl/Your-Project$ tracker start --description "Solving nasty bug"

Supply some descriptive text to the task. Might be used by reporting plugins etc.

=item --tags RT1234 [Multiple]

  ~/perl/Your-Project$ tracker start --tag RT1234 --tag testing

A list of tags to add to the task. Can be used by reporting plugins.

=back

=head2 stop

    ~/perl/Your-Project$ tracker stop
    Worked 00:20:50 on Your-Project

Stop tracking the current project now.

B<Options:>

=over

=item --at TT::DateTime

Stop at the specified time/datetime instead of now.

=back

=head2 continue

    ~/perl/Your-Project$ tracker continue

Continue working on the previous task after a break.

Example:

    ~$ tracker start --project ExplainContinue --tag testing
    Started working on ExplainContinue (testing) at 12:42
    
    # ... time passes, it's now 13:17
    ~$ tracker stop
    Worked 00:35:00 on ExplainContinue
    
    # back from lunch at 13:58
    ~$ tracker continue
    Started working on ExplainContinue (testing) at 13:58

B<Options:> same as L<start>

=head2 append 

    ~/perl/Your-Project$ tracker append

Start working on a task at exactly the time you stopped working at the previous task.

Example:

    ~$ tracker start --project ExplainAppend --tag RT1234
    Started working on ExplainAppend (RT1234) at 14:23
    
    # ... time passes (14:46)
    ~$ tracker stop
    Worked 00:23:00 on ExplainAppend (RT1234)
    
    # start working on new ticket
    # ...
    # but forgot to hit start (14:53)
    ~$ tracker append --tag RT7890
    Started working on ExplainAppend (RT7890) at 14:46

B<Options:> same as L<start>

=head2 current

    ~/perl/Your-Project$ tracker current
    Working 00:20:17 on Your-Project

Display what you're currently working on, and for how long.

B<Options:> none

=head2 worked

    ~/perl/Your-Project$ tracker worked [SPAN]

Report the total time worked in the given time span, maybe limited to
some projects.

B<Options:>

=over

=item --from TT::DateTime [REQUIRED (or use --this/--last)]

Begin of reporting iterval.

=item --to TT::DateTime [REQUIRED (or use --this/--last)]

End of reporting iterval.

=item --this [day, week, month, year]

Automatically set C<--from> and C<--to> to the calculated values

    ~/perl/Your-Project$ tracker worked --this week
    17:01:50

=item --last [day, week, month, year]

Automatically set C<--from> and C<--to> to the calculated values

    ~/perl/Your-Project$ tracker worked --last day (=yesterday)
    06:39:12

=item --project SomeProject [Multiple]

    ~$ tracker worked --last day --project SomeProject
    02:04:47

=back

=head2 report

    ~/perl/Your-Project$ tracker report

Print out a detailed report of what you did. All worked times are
summed up per project (and optionally per tag)

B<Options:>

The same options as for L<worked>, plus:

=over

=item --detail

    ~/perl/Your-Project$ tracker report --last month --detail

Also calc sums per tag.

=item --verbose

    ~/perl/Your-Project$ tracker report --last month --verbose

Lists all found trackfiles and their respective duration before printing out the report.

=back

=head2 init

    ~/perl/Your-Project$ tracker init

Create a rather empty F<.tracker.json> config file in the current directory.

B<Options:> none

=head2 show_config

    ~/perl/Your-Project$ tracker show_config

Dump the config that's valid for the current directory. Might be handy when setting up plugins etc.

B<Options:> none

=head2 plugins

    ~/perl/Your-Project$ tracker plugins

List all installed plugins (i.e. stuff in C<App::TimeTracker::Command::*)

B<Options:> none

=head2 recalc_trackfile

    ~/perl/Your-Project$ tracker recalc_trackfile --trackfile 20110808-232327_App_TimeTracker.trc

Recalculates the duration stored in an old trackfile. Might be useful
after a manual update in a trackfile. Might be unneccessary in the
future, as soon as task duration is always calculated lazyly.

B<Options:>

=over

=item --trackfile name_of_trackfile.trc REQUIRED

Only the name of the trackfile is required, but you can also pass in
the absolute path to the file. Broken trackfiles are sometimes
reported during L<report>.

=back

=head2 commands

    ~/perl/Your-Project$ tracker commands

List all available commands, based on your current config.

B<Options:> none

=head1 AUTHOR

Thomas Klausner <domm@cpan.org>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2011 by Thomas Klausner.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut


__END__

