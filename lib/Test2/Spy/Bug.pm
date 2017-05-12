package Test2::Spy::Bug;

use strict;
use warnings;

use Test2::API qw/test2_add_callback_exit test2_add_callback_post_load test2_stack/;

sub import {
  (undef, $target) = @_;

  my $transport;
  if ($target =~ m[ws(?:s)?://]) {
    require Test2::Spy::Transport::WebSocket;
    $transport = Test2::Spy::Transport::WebSocket->new(target => $target);
    $transport->outfile;
  } else {
    die 'target protocol not understood';
  }

  test2_add_callback_post_load(sub{
    my $stack = test2_stack();
    my $hub = $stack->top;

    $hub->listen(sub{
      my ($hub, $e) = @_;
      $transport->write_event($e);
    }, inherit => 1);

    test2_add_callback_exit(sub{
      my ($context, $exit, $new_exit) = @_;
      $transport->write_event({__SPY__ => 1, exit => $$new_exit});
    });
  });

}

1;

