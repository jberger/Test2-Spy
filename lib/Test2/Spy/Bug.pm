package Test2::Spy::Bug;

use Mojo::Base -strict;

use Mojo::UserAgent;
use Test2::API qw/test2_add_callback_exit test2_add_callback_post_load test2_stack/;

my $target;
my $ua = Mojo::UserAgent->new;
my $TX;

sub ws_send {
  my $data = shift;
  Mojo::IOLoop->delay(
    sub {
      my $delay = shift;
      return $delay->pass($TX) if $TX;
      $ua->websocket($target, $delay->begin);
    },
    sub {
      my ($delay, $tx) = @_;
      $TX = $tx if $tx;
      die 'Not a websocket' unless $tx->is_websocket;
      $tx->send({json => $data}, $delay->begin);
    },
  )->catch(sub{ warn $_[1] })->wait;
}

sub import {
  (undef, $target) = @_;

  test2_add_callback_post_load(sub{
    my $stack = test2_stack();
    my $hub = $stack->top;

    $hub->listen(sub{
      my ($hub, $e) = @_;
      ws_send($e);
    }, inherit => 1);

    test2_add_callback_exit(sub{
      my ($context, $exit, $new_exit) = @_;
      ws_send({__SPY__ => 1, exit => $$new_exit});
    });
  });

}

1;

