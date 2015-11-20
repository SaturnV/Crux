#! /usr/bin/perl

package Crux::Utils::Extract;

use Text::Balanced qw( extract_bracketed );
use JSON;

use Exporter qw( import );

our @EXPORT_OK = qw( extract_json_text extract_json );

sub extract_json_text
{
  my ($from, $what) = @_;
  my $json;

  ($json) = extract_bracketed($from, "{[\"']}")
    if (defined($from) &&
        ($from =~ /^ \s* var \s+ \Q$what\E \s* = \s*/gmx));

  return $json;
}

sub extract_json
{
  local $@;
  my $str = extract_json_text(@_) // return;
  return eval { from_json($str) };
}

1
