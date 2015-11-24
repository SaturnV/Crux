#! /usr/bin/perl
###### NAMESPACE ##############################################################

package Crux::Stash;

###### IMPORTS ################################################################

use Essence::Strict;

use parent 'Blueprint::Stash';

use Scalar::Util qw( blessed );

###### VARS ###################################################################

my $mod_name = __PACKAGE__;

###### METHODS ################################################################

# ==== Hooks ==================================================================

sub _AddHook
{
  my ($self, $hook) = (shift, shift);
  my $subs = $self->Singleton("${mod_name}::$hook", []);
  unshift(@{$subs}, reverse(@_));
}

sub _Trigger
{
  my ($self, $hook, $ret) = (shift, shift, shift);

  if (my $subs = $self->Singleton("${mod_name}::$hook"))
  {
    $ret = $self->$_($ret, @_)
      foreach (@{$subs});
  }

  return $ret;
}

# -----------------------------------------------------------------------------

sub BeforeBegin { return shift->_AddHook('BeforeBegin', @_) }
sub TriggerBeforeBegin { return shift->_Trigger('BeforeBegin', @_) }

sub AfterBegin { return shift->_AddHook('AfterBegin', @_) }
sub TriggerAfterBegin { return shift->_Trigger('AfterBegin', @_) }

sub BeforeCommit { return shift->_AddHook('BeforeCommit', @_) }
sub TriggerBeforeCommit { return shift->_Trigger('BeforeCommit', @_) }

sub AfterCommit { return shift->_AddHook('AfterCommit', @_) }
sub TriggerAfterCommit { return shift->_Trigger('AfterCommit', @_) }

sub AfterRollback { return shift->_AddHook('AfterRollback', @_) }
sub TriggerAfterRollback { return shift->_Trigger('AfterRollback', @_) }

# ==== Realtime ===============================================================

sub QueueRealtimeEvents
{
  my $self = shift;

  if (@_)
  {
    my $q = $self->Singleton('Crux::RealtimeEventQueue', []);
    push(@{$q}, $self->_SerializeRealtimeEvents(@_));
  }

  return $self;
}

sub SubmitRealtimeEvents
{
  my ($self) = @_;

  if (my $q = $self->Singleton('Crux::RealtimeEventQueue'))
  {
    if (my @events = splice(@{$q}))
    {
      my $app = $self->Get('Crux::App');
      $app->SubmitRealtimeEvents(@events)
        if $app;
    }
  }

  return $self;
}

sub _SerializeRealtimeObject
{
  my ($self, $obj) = @_;
  my $method = $obj->can('SerializeToRealtime') ||
      $obj->can('SerializeToJson') or
    die "$mod_name: Can't serialize '$obj'.\n";
  return $obj->$method($self);
}

sub _SerializeRealtimeEvents
{
  my $self = shift;
  return map { blessed($_) ? $self->_SerializeRealtimeObject($_) : $_ } @_;
}

###############################################################################

1
