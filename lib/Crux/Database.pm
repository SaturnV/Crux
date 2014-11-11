#! /usr/bin/perl

package Crux::Database;

use Essence::Strict;

use parent 'Essence::Sql';

sub new
{
  my $class = shift;
  my $ctrl = shift;
  my $self = $class->next::method(@_);
  $self->{'controller'} = $ctrl;
  return $self;
}

# TODO Better formatting
sub _debug
{
  my $self = shift;
  my $category = shift;
  my $ctrl = $self->{'controller'};
  $ctrl->LogDebug($category,
      map { ref($_) ? $_ : "    $_" }
          grep { defined($_) } @_);
}

1
