package Test2::Spy;

BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }

use Mojo::Base -strict;

my $CLASS;

BEGIN {
  $CLASS = $ENV{TEST2_SPY_TRANSPORT} || 'Test2::Spy::Transport::WebSocket';
  eval "require $CLASS";
  die $@ if $@;
}

CHECK {
  my $orig = App::cpanminus::script->can('test');
  return unless $orig;
  my $transport = $CLASS->new;
  no warnings 'redefine';
  *App::cpanminus::script::test = sub { $transport->around_test($orig, @_) };
}

1;

