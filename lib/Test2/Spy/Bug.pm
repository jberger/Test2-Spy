package Test2::Spy::Bug;

use Mojo::Base -strict;

use Mojo::File 'path';
use Mojo::JSON 'encode_json';
use Test2::API qw/test2_add_callback_exit test2_add_callback_post_load test2_stack/;
use Test2::Harness::Result;

sub import {
  my (undef, $target) = @_;

  test2_add_callback_post_load(sub{
    my $stack = test2_stack();
    my $hub = $stack->top;
    my ($file, $result);

    $hub->listen(sub{
      my ($hub, $e) = @_;
      $file ||= $e->trace->file;
      $result ||= Test2::Harness::Result->new(
        file => $file,
        name => $file,
        job => 1,
      );
      $result->add_event($e);
    }, inherit => 1);

    test2_add_callback_exit(sub{
      my ($context, $exit, $new_exit) = @_;
      die 'no result created' unless $result;
      $result->stop($$new_exit);

      local *Test2::Harness::Result::TO_JSON = Test2::Event->can('TO_JSON') unless Test2::Harness::Result->can('TO_JSON');
      my $tmp = path($target)->child($file);
      $tmp->dirname->make_path;
      $tmp->spurt(encode_json $result);
    });
  });

}

1;

