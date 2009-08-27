use inc::Module::Install;

name         'App-Alice';
author       'Lee Aylward <leedo@cpan.org>';
perl_version '5.008';
all_from     'lib/App/Alice.pm';
readme_from  'lib/App/Alice.pm';
license      'perl';

auto_license();
githubmeta();

# need a recent version to detect POE Components
configure_requires 'ExtUtils::MakeMaker'   => '6.54';

# need this for Devel::Declare (for MooseX::Declare)
requires    'ExtUtils::Depends'            => 0,
# need a recent version for clean_subroutines
requires    'namespace::clean'             => '0.11';

requires    'YAML'                         => '0.68';
requires    'MooseX::Declare'              => '0.23';
requires    'MooseX::ClassAttribute'       => '0.09';
requires    'POE::Component::IRC'          => '6.08';
requires    'POE::Component::Server::HTTP' => '0.09';
requires    'POE::Component::SSLify'       => '0.15';
requires    'MooseX::POE'                  => '0.205';
requires    'Template'                     => '2.20';
requires    'Template::Plugin::JavaScript' => '0.01';
requires    'IRC::Formatting::HTML'        => '0.03';
requires    'JSON'                         => '2.15';
requires    'DateTime'                     => '0.49';
requires    'DateTime::TimeZone'           => '0.91';
requires    'File::ShareDir'               => '0.01';
requires    'Digest::CRC'                  => '0.14';

test_requires 'Test::More'                 => '0.86';

install_share  'share';
install_script 'bin/alice';
no_index    'directory' => 'share/sprockets';

auto_install;
WriteAll;
