#! /usr/bin/perl
###### NAMESPACE ##############################################################

package Crux::Model::FtsMixin;

###### IMPORTS ################################################################

use Essence::Strict;

use parent 'Crux::Model::FtsMixin_';

###### METHODS ################################################################

sub _ApiPrepareDbWrite
{
  my ($self, @rest) = @_;
  my $s = $rest[0];
  my $updated;

  $updated = $self->ApiUpdateFts($s)
    unless scalar($s->Get('#skip_fts::' . ref($self)));

  return $self->next::method(@rest) || $updated;
}

sub ApiUpdateFts
{
  my ($self, $s) = @_;
  my $updated;

  my $old = $self->Get('_fts');
  my $new = $self->FtsText($s);
  if (defined($old) ? (!defined($new) || ($new ne $old)) : defined($new))
  {
    $self->Set('_fts' => $new);
    $updated = 1;
  }

  return $updated;
}

###############################################################################

1
