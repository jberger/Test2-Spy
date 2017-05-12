package Test2::Spy::Drop;

use Mojo::Base 'Mojolicious';

use Test2::Event;
use Test2::Harness::Result;

has results => sub { [] };

sub startup {
  my $app = shift;

  $app->helper(result => sub {
    my $c = shift;
    my $result = $c->stash->{'spy.result'};
    unless ($result) {
      if (my $file = shift) {
        $result = $c->stash->{'spy.result'} = Test2::Harness::Result->new(
          file => $file,
          name => $file,
          job  => 1,
        );
        push @{ $c->app->results }, $result;
      } else {
        die 'Test file not started';
      }
    }
    return $result;
  });

  $app->helper(finalize => sub {
    my ($c, $exit) = @_;
    return if $c->stash->{'spy.finalized'}++;
    $c->result->stop($exit);
  });

  $app->helper(format_result => sub {
    my ($c, $result) = @_;
    die 'result required' unless eval { $result->isa('Test2::Harness::Result') };
    my $name = $result->name;
    my $state = $result->passed ? 'PASSED' : 'FAILED';
    my $duration = $result->stop_time - $result->start_time;
    $duration = sprintf "%.1f", $duration * 10**3;
    my $total = $result->total;
    my $exit = $result->exit;
    return "$name: $state, ran $total tests in ${duration}ms, exitted $exit\n";
  });

  $app->routes->websocket('/' => sub {
    my $c = shift;
    $c->on(json => sub {
      my ($c, $data) = @_;
      if ($data->{__SPY__}) {
        $c->finalize($data->{exit}) if exists $data->{exit};
        return;
      }
      my $e = Test2::Event->from_json(%$data);
      $c->result($e->trace->file)->add_event($e);
    });
    $c->on(finish => sub { shift->finalize });
  });

}

1;

