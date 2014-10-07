#! /usr/bin/perl

package Crux::MojoLogger;

use Essence::Strict;

use base 'Mojo::Log';

use Essence::Logger qw();

sub new
{
  my $self = shift->next::method(@_);
  $self->unsubscribe('message', $_)
    foreach (@{$self->subscribers('message')});
  $self->on('message', '_message');
  return $self;
}

sub _message
{
  my ($self, $level, @lines) = @_;
  Essence::Logger->Log($level, @lines);
}

1
