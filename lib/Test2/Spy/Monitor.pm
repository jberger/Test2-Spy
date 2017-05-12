package Test2::Spy::Monitor;

use Mojo::Base 'Mojolicious';

use Test2::Event;
use Test2::Harness::Result;

has results => sub { [] };

sub startup {
  my $app = shift;

  $app->helper(add_event => sub {
    my ($c, $e) = @_;
    my $result = $c->stash->{result};
    unless ($result) {
      $result = $c->stash->{result} = Test2::Harness::Result->new(
        file => $e->trace->file,
        name => $e->trace->file,
        job  => 1,
      );
      push @{ $c->app->results }, $result;
    }
    $result->add_event($e);
  });

  $app->helper(format_result => sub {
    my ($c, $result) = @_;
    die 'result required' unless eval { $result->isa('Test2::Harness::Result') };
    my $name = $result->name;
    my $state = $result->passed ? 'PASSED' : 'FAILED';
    my $duration = $result->stop_time - $result->start_time;
    $duration = sprintf "%.1f", $duration * 10**3;
    my $total = $result->total;
    return "$name: $state, $total tests (${duration}ms)\n";
  });

  $app->routes->websocket('/' => sub {
    my $c = shift;
    $c->on(json => sub {
      my ($c, $data) = @_;
      my $e = Test2::Event->from_json(%$data);
      $c->add_event($e);
    });
    $c->on(finish => sub {
      my $c = shift;
      my $result = $c->stash->{result};
      $result->stop if $result;
    });
  });

}

1;

