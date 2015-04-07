#! /usr/bin/perl
###### NAMESPACE ##############################################################

package Crux::Utils::Fingerprint;

###### IMPORTS ################################################################

use Essence::Strict;

use Digest::SHA qw( sha256_hex );
use JSON;
use Carp;

###### EXPORTS ################################################################

use Exporter qw( import );

our @EXPORT_OK = qw( $JsonEncoder fingerprint );

###### VARS ###################################################################

our $JsonEncoder = JSON->new();
$JsonEncoder->canonical(1);
$JsonEncoder->utf8(1);

###### SUBS ###################################################################

# { 'a' => 0 } vs { 'a' => '0' }
sub __stringify
{
  return defined($_[0]) ? "$_[0]" : undef unless ref($_[0]);
  return [map { __stringify($_) } @{$_[0]}] if (ref($_[0]) eq 'ARRAY');

  my $p = $_[0];
  return { map { ($_ => __stringify($p->{$_})) } keys(%{$p}) }
    if (ref($p) eq 'HASH');

  my $ref = ref($p);
  confess "Can't stringify '$ref'";
}

sub fingerprint
{
  return defined($_[0]) ?
      (ref($_[0]) ?
           sha256_hex($JsonEncoder->encode(__stringify($_[0]))) :
           $_[0]) :
      undef;
}

###############################################################################

1
