package Test2::Spy;

use Mojo::Base -strict;

use Mojo::File 'tempdir';
use Mojo::JSON qw/decode_json encode_json/;

CHECK {
  my $orig = App::cpanminus::script->can('test');
  return unless $orig;
  my $out = Mojo::File->new('out.json')->to_abs;

  no warnings 'redefine';
  *App::cpanminus::script::test = sub {
    my $tmp = tempdir(CLEANUP => 0);
    local $ENV{PERL5OPT} = $ENV{PERL5OPT} . " -MTest2::Spy::Bug=$tmp";
    my $ret = $orig->(@_);
    my %out;
    $tmp->list_tree->each(sub{ $out{$_->to_rel($tmp)} = decode_json $_->slurp });
    $out->spurt(encode_json(\%out));
    return $ret;
  };
}

1;

