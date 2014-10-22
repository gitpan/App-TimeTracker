package App::TimeTracker::Command::Post2IRC;
use strict;
use warnings;
use 5.010;

# ABSTRACT: App::TimeTracker plugin for posting to IRC

use Moose::Role;
use LWP::UserAgent;
use Digest::SHA1 qw(sha1_hex);

has 'irc_quiet' => (
    is=>'ro',
    isa=>'Bool',
    documentation=>'IRC: Do not post to IRC',
    cmd_aliases => [qw/ircquiet/],
    traits    => [ 'Getopt' ],
);

after ['cmd_start','cmd_continue'] => sub {
    my $self = shift;
    return if $self->irc_quiet;
    my $task = $self->_current_task;
    $self->_post_to_irc(start => $task);
};

after 'cmd_stop' => sub {
    my $self = shift;
    return if $self->irc_quiet;
    return unless $self->_current_command eq 'cmd_stop';
    my $task = App::TimeTracker::Data::Task->previous($self->home);
    $self->_post_to_irc(stop => $task);
};

sub _post_to_irc {
    my ($self, $status, $task) = @_;
    my $cfg = $self->config->{post2irc};
    return unless $cfg;

    my $ua = LWP::UserAgent->new(timeout=>3);
    my $message = $task->user 
        . ( $status eq 'start' ? ' is now' : ' stopped' ) 
        . ' working on '
        . $task->say_project_tags;
    my $token = sha1_hex($message, $cfg->{secret});
    my $res = $ua->get($cfg->{host}.'?message='.$message.'&token='.$token);
    unless ($res->is_success) {
        say "Could not post to IRC...";
    }
}

no Moose::Role;
1;



=pod

=head1 NAME

App::TimeTracker::Command::Post2IRC - App::TimeTracker plugin for posting to IRC

=head1 VERSION

version 2.009

=head1 DESCRIPTION

We use an internal IRC channel for internal communication. And we all want (need) to know what other team members are currently doing. This plugin helps us making sharing this information easy.

After running some commands, this plugin prepares a short message and
sends it (together with an authentification token) to a small
webserver-cum-irc-bot (C<Bot::FromHTTP>, not yet on CPAN, but basically
just a slightly customized/enhanced pastebin).

The messages is transfered as a GET-Request like this:

  http://yourserver/?message=some message&token=a58875d576e8c09a...

=head1 CONFIGURATION

=over

=item * add C<Post2IRC> to your list of plugins

=item * add a hash named C<post2irc>, containing the following keys:

=over

=item * host

The hostname of the server C<Bot::FromHTTP> is running on. Might also contain a special port number (C<http://ircbox.vpn.yourcompany.com:9090>)

=item secret

A shared secret used to calculate the authentification token. The token is calculated like this:

  my $token = Digest::SHA1::sha1_hex($message, $secret);

=back

=back

=head1 NEW COMMANDS

none

=head1 CHANGES TO OTHER COMMANDS

=head2 start, stop, continue

After running the respective command, a message is sent to the
webservice that will afterwards post the message to IRC.

B<New Options>:

=over

=item --irc_quiet

    ~/perl/Your-Project$ tracker start --irc_quiet

Do not post this action to IRC.

=back

=head1 AUTHOR

Thomas Klausner <domm@cpan.org>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2011 by Thomas Klausner.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut


__END__

