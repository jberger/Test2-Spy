package Test2::Spy;

BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }

use Mojo::Base -strict;

use Test2::Spy::Monitor;
use Mojo::Server::Daemon;

#use Fcntl qw/F_GETFL F_SETFL FD_CLOEXEC/;
use POSIX ":sys_wait_h";

my $orig;
sub test {
  my($self, $cmd, $distname, $depth) = @_;
  my $spy = Test2::Spy::Monitor->new;
  my $server = Mojo::Server::Daemon->new->app($spy);
  my $port = $server->listen(["http://127.0.0.1"])->start->ports->[0];
  #unless ($self->WIN32) {
    #for my $a (@{ $server->acceptors }) {
      #my $h = $server->ioloop->acceptor($a)->handle;
      #my $f = fcntl($h, F_GETFL, 0) or die "Can't get flags for the socket: $!\n";
      #fcntl($h, F_SETFL, $f | FD_CLOEXEC) or die "Can't set flags for the socket: $!\n";
    #}
  #}

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
    $_ && Mojo::IOLoop->remove($_) for ($rid, $tid);

    return 1;
  };

  $orig->(@_);

  my $results = $spy->results;
  print $spy->format_result($_) for @$results;
  print @$results . " tests run\n";

  return 1;
}

CHECK {
  $orig = App::cpanminus::script->can('test');
  return unless $orig;
  *App::cpanminus::script::test = \&test;
}

1;

