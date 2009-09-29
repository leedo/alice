use inc::Module::Install;

name         'App-Alice';
author       'Lee Aylward <leedo@cpan.org>';
perl_version '5.010';
all_from     'lib/App/Alice.pm';

requires    'YAML'                         => '0.66';
requires    'Moose'                        => '0.90';
requires    'MooseX::Declare'              => '0.22';
requires    'MooseX::ClassAttribute'       => '0.09';
requires    'POE::Component::IRC'          => '5.88';
requires    'POE::Component::Server::HTTP' => '0.09';
requires    'POE::Component::SSLify'       => '0.10';
requires    'MooseX::POE'                  => '0.205';
requires    'Template'                     => '2.20';
requires    'Template::Plugin::JavaScript' => '0.01';
requires    'IRC::Formatting::HTML'        => '0.03';
requires    'JSON'                         => '2.12';
requires    'DateTime'                     => '0.49';
requires    'DateTime::TimeZone'           => '0.91';
requires    'File::ShareDir'               => '0.01';
requires    'Digest::CRC'                  => '0.14';

test_requires 'Test::More'                 => '0.86';

install_share  'share';
install_script 'bin/alice';
no_index    'directory' => 'share/sprockets';

WriteAll;
