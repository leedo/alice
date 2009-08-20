#Installation

##Debian

This apt command will take care of most of the dependencies:

apt-get install libyaml-perl libjson-perl libmoosex-declare-perl lib-poecomponent-irc-perl libpoe-component-server-http-perl libpoe-component-sslify-perl libtemplate-perl libdatetime-perl libfile-sharedir-perl libdigest-crc-perl

You will then need to install MooseX::ClassAttribute, MooseX::POE, Template::Plugin::Javascript, and IRC::Formatting::HTML from the CPAN.


#Usage

After installing simply run the command 'alice'

You can then connect to alice using a WebKit browser at
http://127.0.0.1:8080/view

To add a new IRC server click on the gear icon in the
bottom right corner. After adding a server it should
connect automatically and open any channels as new
tabs.

