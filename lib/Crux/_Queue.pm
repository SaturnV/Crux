#! /usr/bin/perl
###### NAMESPACE ##############################################################

package Crux::_Queue;

###### IMPORTS ################################################################

use Essence::Strict;

###### VARS ###################################################################

my $mod_name = __PACKAGE__;

###### METHODS ################################################################

sub new
{
  my $class = shift;
  my $self = bless(
      { 'seq' => 0, 'ranks' => {}, 'values' => {} },
      $class);
  return @_ ? $self->Push(@_) : $self;
}

sub Push
{
  my $self = shift;

  my $ranks = $self->{'ranks'};
  my $values = $self->{'values'};
  foreach (@_)
  {
    $ranks->{$_} = $self->{'seq'}++;
    $values->{$_} = $_;
  }

  return $self;
}

sub Shift
{
  my $self = $_[0];
  my $ret;

  if (my $ranks = $self->{'ranks'})
  {
    my ($head, $head_rank);
    foreach (keys(%{$ranks}))
    {
      if (!defined($head_rank) || ($ranks->{$_} < $head_rank))
      {
        $head_rank = $ranks->{$_};
        $head = $_;
      }
    }
    delete($ranks->{$head});

    $ret = delete($self->{'values'}->{$head});
  }

  return $ret;
}

###############################################################################

1
