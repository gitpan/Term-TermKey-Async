use strict;
use warnings;

use Module::Build;

my $build = Module::Build->new
  (
   module_name => 'Term::TermKey::Async',
   requires => {
                 'IO::Async' => '0.21',
                 'Term::TermKey' => '0.03',
               },
   build_requires => {
               },
   license => 'perl',
   create_makefile_pl => 'traditional',
  );

$build->create_build_script;
