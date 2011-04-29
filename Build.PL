use strict;
use warnings;

use Module::Build;

my $build = Module::Build->new(
   module_name => 'Term::TermKey::Async',
   requires => {
      'IO::Async' => '0.35',
      'Term::TermKey' => '0.08',
   },
   license => 'perl',
   create_makefile_pl => 'traditional',
   create_license => 1,
   create_readme  => 1,
);

$build->create_build_script;
