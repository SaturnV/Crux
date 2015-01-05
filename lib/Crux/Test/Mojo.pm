#! /usr/bin/perl
###### NAMESPACE ##############################################################

package Crux::Test::Mojo;

###### IMPORTS ################################################################

use Essence::Strict;

use parent 'Test::Mojo';

use Test::Deep;
use Text::Balanced qw( extract_bracketed );
use JSON;

###### CONFIG #################################################################

# ==== RenderIndex + Status / Config ==========================================

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

# ==== API ====================================================================

sub api_is_success
{
  my ($self, $desc) = @_;
  $desc //= 'api_is_success';
  $self->status_is(200, "$desc status")
       ->content_type_is('application/json', "$desc content-type")
       ->json_is('/success', 'great', "$desc success");
}

sub api_content_superhash
{
  my ($self, $data, $desc) = @_;
  my $api_response_content = $self->tx()->res()->json('/content');
  cmp_deeply($api_response_content, superhashof($data), "$desc cmp");
  return $self;
}

sub api_put_get
{
  my ($self, $url, $data, $desc) = @_;
  $desc //= 'put_get';
  $self->put_ok($url, 'json' => $data)
      ->api_is_success("$desc PUT success")
      ->api_content_superhash($data, "$desc PUT");
  $self->get_ok($url)
      ->api_is_success("$desc GET success")
      ->api_content_superhash($data, "$desc GET");
}

###############################################################################

1
