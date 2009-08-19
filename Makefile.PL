use inc::Module::Install;

name        'Alice',
version     '0.01';
license     'perl';

requires    'YAML';
requires    'JSON';
requires    'CLASS';
requires    'MooseX::Declare';
requires    'MooseX::ClassAttribute';
requires    'MooseX::POE';
requires    'POE::Component::IRC';
requires    'POE::Component::Server::HTTP';
requires    'POE::Component::SSLify';
requires    'Template';
requires    'Template::Plugin::JavaScript';
requires    'IRC::Formatting::HTML';
requires    'DateTime';
requires    'File::ShareDir';
requires    'MIME::Base64';
requires    'Digest::CRC';

install_share  'share';
install_script 'script/alice';
WriteAll;
