#!/usr/bin/perl

use strict;
use warnings;

use Gtk2 -init;
use Gtk2::WebKit;

my $window = Gtk2::Window->new;
my $view = Gtk2::WebView->new;
$window->add($view);
$view->open("http://127.0.0.1:8080/view");
$window->show_all;
Gtk2->main;
