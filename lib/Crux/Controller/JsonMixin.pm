#! /usr/bin/perl
###### NAMESPACE ##############################################################

package Crux::Controller::JsonMixin;

###### IMPORTS ################################################################

use Essence::Strict;

use Crux::JsonSanitizer;
use Crux::Utils;

###### METHODS ################################################################

sub wrap_json
{
  my ($self, $s) = (shift, shift);
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

    $ret = $self->NextHandler($s, $content_json, @_);
  };
  if ($@)
  {
    my ($msg, $code, $json, $content) =
        Crux::Utils::extract_error($@, 'Something spooky is in that jungle');
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
      $ret = { 'error' =>
          (ref($json) eq 'HASH') ?
              { map { ($_ => $json->{$_} ) }
                    grep { !/^_/ } keys(%{$json}) } :
              $json };
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
