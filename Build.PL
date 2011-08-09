
use strict;
use warnings;

use Module::Build 0.3601;


my %module_build_args = (
  'build_requires' => {
    'File::Copy::Recursive' => '0',
    'File::Temp' => '0',
    'IO::Capture::Stdout' => '0',
    'Module::Build' => '0.3601',
    'Test::File' => '0',
    'Test::More' => '0',
    'Test::Most' => '0',
    'Test::Trap' => '0'
  },
  'configure_requires' => {
    'Module::Build' => '0.3601'
  },
  'dist_abstract' => 'Track time spend on projects from the commandline',
  'dist_author' => [
    'Thomas Klausner <domm@cpan.org>'
  ],
  'dist_name' => 'App-TimeTracker',
  'dist_version' => '2.008',
  'license' => 'perl',
  'module_name' => 'App::TimeTracker',
  'recommends' => {},
  'recursive_test_files' => 1,
  'requires' => {
    'Carp' => '0',
    'Data::Dumper' => '0',
    'DateTime' => '0',
    'DateTime::Format::Duration' => '0',
    'DateTime::Format::ISO8601' => '0',
    'Digest::SHA1' => '0',
    'File::Copy' => '0',
    'File::Find::Rule' => '0',
    'File::HomeDir' => '0',
    'Git::Repository' => '0',
    'Hash::Merge' => '0',
    'JSON::XS' => '0',
    'LWP::UserAgent' => '0',
    'Moose' => '0',
    'Moose::Role' => '0',
    'Moose::Util::TypeConstraints' => '0',
    'MooseX::Getopt' => '0',
    'MooseX::Storage' => '0',
    'MooseX::Storage::Format::JSONpm' => '0',
    'MooseX::Types::Path::Class' => '0',
    'Path::Class' => '0',
    'Path::Class::Iterator' => '0',
    'RT::Client::REST' => '0',
    'RT::Client::REST::Ticket' => '0',
    'Try::Tiny' => '0',
    'Unicode::Normalize' => '0',
    'User::pwent' => '0',
    'namespace::autoclean' => '0',
    'perl' => '5.010'
  },
  'script_files' => [
    'bin/tracker'
  ]
);


my $build = Module::Build->new(%module_build_args);

$build->create_build_script;
