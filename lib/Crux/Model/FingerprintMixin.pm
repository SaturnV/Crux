#! /usr/bin/perl
###### NAMESPACE ##############################################################

package Crux::Model::FingerprintMixin;

###### IMPORTS ################################################################

use Essence::Strict;

use parent 'Crux::Model::FingerprintMixin_';

###### METHODS ################################################################

sub _ApiPrepareDbWrite
{
  my ($self, @rest) = @_;
  my $s = $rest[0];
  my $updated;

  $updated = $self->ApiUpdateFingerprint($s)
    unless scalar($s->Get('#skip_fingerprint::' . ref($self)));

  return $self->next::method(@rest) || $updated;
}

sub ApiUpdateFingerprint
{
  my ($self, $s) = @_;
  my $updated;

  my $old = $self->Get('_fingerprint');
  my $new = $self->Fingerprint($s);
  if (defined($old) ? (!defined($new) || ($new ne $old)) : defined($new))
  {
    $self->Set('_fingerprint' => $new);
    $updated = 1;
  }

  return $updated;
}

###############################################################################

1
