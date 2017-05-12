package Test2::Spy::Transport;

use Mojo::Base -base;

sub around_test { die 'around_test not implemented by subclass' }

sub write_event { die 'write_event not implemented by subclass' }

1;

