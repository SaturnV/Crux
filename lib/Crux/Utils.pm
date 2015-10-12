#! /usr/bin/perl
###### NAMESPACE ##############################################################

package Crux::Utils;

###### IMPORTS ################################################################

use Essence::Strict;

use Scalar::Util qw( blessed );

###### EXPORTS ################################################################

use Exporter qw( import );

our @EXPORT_OK = qw( extract_error );

###### SUBS ###################################################################

# ---- extract_error ----------------------------------------------------------

sub extract_error
{
  my ($error, $default_msg) = @_;
  my ($msg, $code, $json, $content);

  $msg = $default_msg;
  if (blessed($error))
  {
    $msg = "$error"
      if $error->isa('Mojo::Exception');
  }
  elsif (ref($error))
  {
    $json = [ { 'code' => ${$error} } ] if (ref($error) eq 'SCALAR');
    $json = [ $error ] if (ref($error) eq 'HASH');
    $json //= $error;
    undef($msg);
  }
  else
  {
    $msg = $error;
  }

  if (ref($json) eq 'ARRAY')
  {
    my $c;
    foreach (@{$json})
    {
      $_->{'code'} = 'error_' . $c
        if (defined($c = $_->{'code'}) && ($c !~ /^err(?:or)?_/));
      $c = delete($_->{':content'});
      $code //= $_->{'code'};
      $content //= $c;
    }
  }
  elsif (!$json)
  {
    $json //= [ { 'code' => 'err_or' } ];
    $code = 'err_or';
  }

  return ($msg, $code, $json, $content) if wantarray;
  return $code;
}

###############################################################################

1
