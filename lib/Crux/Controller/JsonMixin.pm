#! /usr/bin/perl
###### NAMESPACE ##############################################################

package Crux::Controller::JsonMixin;

###### IMPORTS ################################################################

use Essence::Strict;

use Scalar::Util;
use JSON;

use Crux::JsonSanitizer;

###### METHODS ################################################################

sub ResponseContentType
{
  return $_[0]->res()->content()->headers()->content_type();
}

sub ResponseRendered { return defined($_[0]->ResponseContentType()) }

# ---- extract_error ----------------------------------------------------------

sub extract_error
{
  my ($self, $error, $default_msg) = @_;
  my ($msg, $code, $json, $content);

  $msg = $default_msg;
  if (Scalar::Util::blessed($error))
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

  return ($msg, $code, $json, $content);
}

# ---- wrap_json --------------------------------------------------------------

sub wrap_json
{
  my $self = shift;
  my $ret;

  eval
  {
    my $content_json = $self->req()->json();
    if (defined($content_json))
    {
      $content_json = Crux::JsonSanitizer::sanitize_json($content_json);
      $self->LogDebug('JSON content:',
          Crux::JsonSanitizer::remove_pwd($content_json));
    }

    $ret = $self->NextHandler($content_json, @_);
  };
  if ($@)
  {
    my ($msg, $code, $json, $content) =
        $self->extract_error($@, 'Something spooky is in that jungle');
    if ($msg)
    {
      $self->LogError($msg);
    }
    else
    {
      $self->LogDebug("JSON handler returned error code");
    }

    if (defined($json))
    {
      $ret = { 'error' => $json };
      $ret->{'content'} = $content
        if defined($content);
    }
  }
  else
  {
    $ret = { 'success' => 'great', 'content' => $ret };
  }

  if (!$self->ResponseRendered())
  {
    $self->LogDebug('JSON response:', $ret);
    $self->render('json' => $ret);
  }
}

###############################################################################

1
