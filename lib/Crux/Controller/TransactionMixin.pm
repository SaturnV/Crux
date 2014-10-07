#! /usr/bin/perl
###### NAMESPACE ##############################################################

package Crux::Controller::TransactionMixin;

###### IMPORTS ################################################################

use Essence::Strict;

###### METHODS ################################################################

# ==== Wrap ===================================================================

sub wrap_transaction
{
  my ($self, @rest) = @_;
  return $self->app()->WrapInTransaction(
      sub
      {
        # my ($s) = @_;
        return $self->NextHandler(
            $self->PrepareStash($_[0], @rest),
            @rest);
      });
}

# ==== Stash ==================================================================

sub PrepareStash
{
  # my ($self, $s, @rest) = @_;
  $_[1]->Set(
      'crux.action' => $_[0]->stash('crux.action'));
  return $_[1];
}

###############################################################################

1
