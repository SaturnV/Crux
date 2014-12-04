#! /usr/bin/perl

package Crux::Test::Mojo;

use Essence::Strict;

use parent 'Test::Mojo';

use Text::Balanced qw( extract_bracketed );
use JSON;

$LSnext::Mojo = 1;
$LSnext::Mojo = 2;

sub GetContent { return $_[0]->tx()->res()->text() }

sub _GetJsonText
{
  my ($self, $what) = @_;
  my $json;

  my $content = $self->GetContent();
  ($json) = extract_bracketed($content, "{[\"']}")
    if (defined($content) &&
        ($content =~ /^ \s* var \s+ \Q$what\E \s* = \s*/gmx));

  return $json;
}

sub _GetJson
{
  my ($self, $what) = @_;
  my $json = $self->_GetJsonText($what);
  $json = from_json($json) if defined($json);
  return $json;
}

sub GetStatus { return $_[0]->_GetJson('ntStatus') }
sub GetConfig { return $_[0]->_GetJson('ntConfig') }

1
