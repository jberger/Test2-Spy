package Test2::Spy;

BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }

use Mojo::Base -strict;

use Test2::Spy::Drop;
use Mojo::Server::Daemon;

use POSIX ":sys_wait_h";

my $orig;
sub test {
  my($self, $cmd, $distname, $depth) = @_;
  my $drop = Test2::Spy::Drop->new;
  $drop->log->level('warn');
  my $server = Mojo::Server::Daemon->new(app => $drop, silent => 1);
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
      $self->diag_fail("Timed out (> ${TIMEOUT}s). Use --verbose to retry.");
      local $SIG{TERM} = 'IGNORE';
      kill TERM => 0;
      waitpid $pid, 0;
    }) : undef;

    local $SIG{HUP} = sub { Mojo::IOLoop->stop };

    Mojo::IOLoop->start;
    $server->stop;
    $_ && Mojo::IOLoop->remove($_) for ($rid, $tid);

    return 1;
  };

  $orig->(@_);

  my $results = $drop->results;
  print $drop->format_result($_) for @$results;
  print @$results . " tests run\n";

  return 1;
}

CHECK {
  $orig = App::cpanminus::script->can('test');
  return unless $orig;
  no warnings 'redefine';
  *App::cpanminus::script::test = \&test;
}

1;

