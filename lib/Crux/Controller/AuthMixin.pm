#! /usr/bin/perl
###### NAMESPACE ##############################################################

package Crux::Controller::AuthMixin;

###### IMPORTS ################################################################

use Essence::Strict;

###### METHODS ################################################################

# Implement these
sub ExtractSessionId { return }
sub CreateSession { die }
sub LoadSession { die }
sub CheckSession { return }

# Callback
sub _SessionChanged { return }

# ==== $s / Session ===========================================================

sub GetSession
{
  # my ($self, $s) = @_;
  return $_[1]->Get('session');
}

sub SetSession
{
  my ($self, $s, $session) = @_;
  $s->Set('session' => $session);
  return $self->_SessionChanged($s, $session);
}

sub KillSession
{
  my ($self, $s) = @_;
  $s->Clear('session');
  return $self->_SessionChanged($s);
}

# ==== Request -> Session =====================================================

sub ExtractSession
{
  my ($self, $s) = @_;
  my ($session_id, $session);

  if (defined($session_id = $self->ExtractSessionId($s)))
  {
    $self->LogDebug("SessionId:", $session_id);

    $session = $self->LoadSession($s, $session_id);
  }
  else
  {
    $self->LogDebug("SessionId: <none>");

    $session = $self->CreateSession($s)
      if $self->GetParam($s, 'auth.make_session');
  }

  return $session;
}

sub DoAuth
{
  my ($self, $s) = @_;

  my $session = $self->ExtractSession($s);
  $self->CheckSession($s, $session);
  $self->SetSession($s, $session);

  return $session;
}

sub DoKeepalive
{
  my ($self, $s) = @_;

  my $session = $self->GetSession($s);
  $self->KeepaliveSession($s, $session)
    if $session;

  return $session;
}

sub wrap_auth
{
  my ($self, $s, @rest) = @_;
  my ($ret, $error);

  my $session = $self->DoAuth($s);
  $self->LogDebug("Session:", $session);

  $ret = eval { $self->NextHandler($s, @rest) };
  $error = $@;

  $self->DoKeepalive($s);
  die $error if $error;

  return $ret;
}

###############################################################################

1
