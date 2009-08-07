use inc::Module::Install;

name        'Alice',

requires    'YAML';
requires    'JSON';
requires    'Moose';
requires    'POE::Component::IRC';
requires    'POE::Component::Server::HTTP';
requires    'POE::Component::SSLify';
requires    'Template';
requires    'HTML::Entities';
requires    'List::MoreUtils';
requires    'IRC::Formatting::HTML';
requires    'DateTime';

auto_install(force => 1);
install_share  'share';
install_script 'script/alice';
WriteAll;
