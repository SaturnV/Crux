#! /usr/bin/perl
###### NAMESPACE ##############################################################

package Crux::Controller::IndexMixin;

###### IMPORTS ################################################################

use Essence::Strict;

use Crux::Utils;

###### METHODS ################################################################

sub wrap_index
{
  my ($self, $s, @rest) = @_;
  my ($route, $status);

  eval { $status->{'content'} = $self->NextHandler($s, @rest) };
  if ($@)
  {
    my ($msg, $code, $json) = Crux::Utils::extract_error($@);
    warn $msg if $msg;

    $route = 'error';
    $status->{'msg'} = $code // 'err_or';
    $status->{'error'} = $json if $json;
  }
  else
  {
    $route = substr($self->req()->url()->path()->to_string(), 1);
  }

  $self->RenderIndex($s, $route, $status);
}

###############################################################################

1
