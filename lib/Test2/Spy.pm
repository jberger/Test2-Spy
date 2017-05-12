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
    Mojo::IOLoop->recurring(1 => sub {
      Mojo::IOLoop->stop if waitpid($pid, WNOHANG) > 0;
    });
    local $SIG{HUP} = sub { Mojo::IOLoop->stop };
    Mojo::IOLoop->start;
  };

  $orig->(@_);

  print STDERR $spy->format_result($_) for @{ $spy->results };
}

CHECK {
  $orig = App::cpanminus::script->can('test');
  return unless $orig;
  *App::cpanminus::script::test = \&test;
}

1;

