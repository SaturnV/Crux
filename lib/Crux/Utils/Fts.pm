#! /usr/bin/perl
###### NAMESPACE ##############################################################

package Crux::Utils::Fts;

###### IMPORTS ################################################################

use Essence::Strict;

###### EXPORTS ################################################################

use Exporter qw( import );

our @EXPORT_OK = qw(
    $ReValidFtsToken is_valid_fts_token grep_valid_fts_tokens
    token2mysql tokens2mysql );

###### VARS ###################################################################

our $ReValidFtsToken = qr/[\w\p{Letter}]/;

###### SUBS ###################################################################

sub is_valid_fts_token
{
  return defined($_[0]) && !ref($_[0]) && ($_[0] =~ $ReValidFtsToken);
}

sub grep_valid_fts_tokens
{
  return grep { defined($_) && !ref($_) && ($_ =~ $ReValidFtsToken) } @_;
}

sub token2mysql
{
  my $token = $_[0];
  $token =~ s/[^\w\p{Letter}]/ /g;
  $token =~ s/\s+\z//;
  $token =~ s/^\s+//;
  $token =~ s/\s+/ /g;
  $token = ($token =~ / /) ? "\"$token\"" : "$token*";
  return "+$token";
}

sub tokens2mysql { return map { token2mysql($_) } @_ }

###############################################################################

1
