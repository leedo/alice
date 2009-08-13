#!/usr/bin/perl

use strict;
use warnings;

use Gtk2 -init;
use Gtk2::WebKit;

my $window = Gtk2::Window->new;
my $view = Gtk2::WebKit::WebView->new;
$window->add($view);
$view->open("http://127.0.0.1:8080/view");

$view->signal_connect('navigation-requested' => sub {
  my (undef, undef, $req) = @_;
  my $uri = $req->get_uri;
  return if $uri !~ /^https?:\/\//;
  my $pid = fork();
  if ($pid == 0) {
    exec('x-www-browser', $uri);
    exit 0;
  }
  return 'ignore';
});
$view->signal_connect('populate_popup' => sub {
  my (undef, $menu) = @_;
  for my $menuitem ($menu->get_children) {
    my $label = ($menuitem->get_children)[0];
    next unless $label;
    if ($label->get_text ne 'Reload'
        and $label->get_text ne 'Open Link'
        and $label->get_text ne 'Copy Link Location'
        and $label->get_text ne 'Copy Image') {
      $menu->remove($menuitem);
    }
  }
});

$window->show_all;
Gtk2->main;
