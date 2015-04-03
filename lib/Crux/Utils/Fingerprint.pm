#! /usr/bin/perl
###### NAMESPACE ##############################################################

package Crux::Utils::Fingerprint;

###### IMPORTS ################################################################

use Essence::Strict;

use Digest::SHA qw( sha256_hex );
use JSON;

###### EXPORTS ################################################################

use Exporter qw( import );

our @EXPORT_OK = qw( $JsonEncoder fingerprint );

###### VARS ###################################################################

our $JsonEncoder = JSON->new();
$JsonEncoder->canonical(1);
$JsonEncoder->utf8(1);

###### SUBS ###################################################################

sub fingerprint
{
  return defined($_[0]) ? sha256_hex($JsonEncoder->encode($_[0])) : undef;
}

###############################################################################

1
