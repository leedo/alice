use inc::Module::Install;

name        'App-Alice',
version     '0.01';
license     'perl';

requires    'YAML'                         => '0.70';
requires    'JSON'                         => '2.15';
requires    'CLASS'                        => '1.00';
requires    'MooseX::Declare'              => '0.27';
requires    'MooseX::ClassAttribute'       => '0.09';
requires    'MooseX::POE'                  => '0.205';
requires    'POE::Component::IRC'          => '6.10';
requires    'POE::Component::Server::HTTP' => '0.09';
requires    'POE::Component::SSLify'       => '0.15';
requires    'Template'                     => '2.22';
requires    'Template::Plugin::JavaScript' => '0.01';
requires    'IRC::Formatting::HTML'        => '0.03';
requires    'DateTime'                     => '0.50';
requires    'File::ShareDir'               => '0.02';
requires    'MIME::Base64'                 => '3.08';
requires    'Digest::CRC'                  => '0.14';


install_share  'share';
install_script 'script/alice';
WriteAll;
