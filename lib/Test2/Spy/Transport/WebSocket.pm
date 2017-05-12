package Test2::Spy::Transport::WebSocket;

use strict;
use warnings;

use Mojo::Base 'Test2::Spy::Transport';

use Mojo::File;
use Mojo::JSON 'encode_json';
use Mojo::IOLoop;
use Mojo::Server::Daemon;
use Mojo::UserAgent;

use POSIX ":sys_wait_h";

use Test2::Spy::Transport::WebSocket::App;

has outfile => sub { Mojo::File->new('out.json') };
has target => sub { die 'target is required' };
has ua     => sub { Mojo::UserAgent->new };

sub around_test {
  my($self, $orig, $cpanm, $cmd, $distname, $depth) = @_;
  my $app = Test2::Spy::Transport::WebSocket::App->new;
  $app->log->level('warn');
  my $server = Mojo::Server::Daemon->new(app => $app, silent => 1);
  my $port = $server->listen(["http://127.0.0.1"])->start->ports->[0];

  local $ENV{PERL5OPT} = $ENV{PERL5OPT} . " -MTest2::Spy::Bug=ws://127.0.0.1:$port/";
  our $TIMEOUT;

  no warnings 'redefine';

  local *App::cpanminus::script::run_timeout = sub {
    my($self, $cmd, $timeout) = @_;
    local $TIMEOUT = $timeout if $timeout;
    return $self->run($cmd);
  };

  local *App::cpanminus::script::run = sub {
    my($self, $cmd) = @_;
    my $pid;
    if ($self->WIN32) {
      $cmd = $self->shell_quote(@$cmd) if ref $cmd eq 'ARRAY';
      unless ($self->{verbose}) {
        $cmd .= " >> " . $self->shell_quote($self->{log}) . " 2>&1";
      }
      $pid = !system 1, $cmd;
    } else {
      $pid = fork;
      unless ($pid) {
        $server->stop;
        $self->run_exec($cmd);
      }
    }

    my $rid = Mojo::IOLoop->recurring(1 => sub {
      Mojo::IOLoop->stop if waitpid($pid, WNOHANG) > 0;
    });

    my $tid = $TIMEOUT ? Mojo::IOLoop->timer($TIMEOUT => sub {
      Mojo::IOLoop->stop;
      $cpanm->diag_fail("Timed out (> ${TIMEOUT}s). Use --verbose to retry.");
      local $SIG{TERM} = 'IGNORE';
      kill TERM => 0;
      waitpid $pid, 0;
    }) : undef;

    Mojo::IOLoop->start;
    $server->stop;
    $_ && Mojo::IOLoop->remove($_) for ($rid, $tid);

    return 1;
  };

  $cpanm->$orig(@_);

  my $results = $app->results;
  print $app->format_result($_) for @$results;
  print @$results . " tests run\n";

  {
    local *Test2::Harness::Result::TO_JSON = Test2::Event->can('TO_JSON')
      unless Test2::Harness::Result->can('TO_JSON');
    $self->outfile->spurt(encode_json $results);
  }

  return 1;
}

sub write_event {
  my ($self, $data) = @_;
  Mojo::IOLoop->delay(
    sub {
      my $delay = shift;
      my $tx = $self->{tx};
      return $delay->pass($tx) if $tx;
      $self->ua->websocket($self->target, $delay->begin);
    },
    sub {
      my ($delay, $tx) = @_;
      $self->{tx} = $tx if $tx;
      die 'Not a websocket' unless $tx->is_websocket;
      $tx->send({json => $data}, $delay->begin);
    },
  )->catch(sub{ warn $_[1] })->wait;
}

1;

