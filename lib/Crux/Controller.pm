#! /usr/bin/perl
###### NAMESPACE ##############################################################

package Crux::Controller;

###### IMPORTS ################################################################

use Essence::Strict;

use Mojo::Base 'Mojolicious::Controller';
use parent 'Essence::Logger::Mixin';

use Essence::UUID;
use Scalar::Util qw( blessed );
use JSON;

###### METHODS ################################################################

sub ClickId { return $_[0]->req()->{'Crux::ClickId'} }
sub ShortId { return $_[0]->req()->{'Crux::ClickId::Short'} }

# ---- UserAgent --------------------------------------------------------------

sub UserAgent
{
  return $_[0]->req()->content()->headers()->user_agent() // '<undef>';
}

sub UserAgentMatch
{
  my ($self, $pattern) = @_;
  return (defined($pattern) && ($self->UserAgent() =~ /\Q$pattern\E/i));
}

# ==== $s =====================================================================

sub PrepareStash
{
  my ($self, $s) = @_;
  $s->Set('crux.action' => $self->stash('crux.action'));
  return $s;
}

sub MakeStash
{
  my $self = shift;
  return $self->PrepareStash($self->app()->MakeStash(@_));
}

sub GetSetting
{
  my ($self, $s, $n, $d) = @_;
  my @v = $s->Get($n) || $self->GetRouteSetting($n, $d);
  return @v if wantarray;
  return $v[0];
}

# ==== MojoSession ============================================================
# Just a wrapper around mojo's session handler with logging.

# ---- Implementation ---------------------------------------------------------

sub _SetMojoSessionVariable { $_[0]->session($_[1] => $_[2]) }

sub _KillMojoSessionVariable
{
  my ($self, $n) = @_;
  my $session = $self->session();
  delete($session->{$n});
}

sub _KillMojoSession
{
  my ($self, $n) = @_;
  my $session = $self->session();
  %{$session} = ();
}

# ---- Interface --------------------------------------------------------------

# No stub for readers
sub GetMojoSessionVariable
{
  # my ($self, $var) = @_;
  return $_[0]->session($_[1]);
}

sub ListMojoSessionVariables
{
  my $self = shift;
  my $session = $self->session();
  my @vars = keys(%{$session});

  if (@_)
  {
    my %list = map { ($_ => 1) } @_;
    @vars = grep { $list{$_} } @vars;
  }

  return @vars;
}

sub SetMojoSessionVariable
{
  my $self = shift;

  my ($n, $v);
  while (@_)
  {
    $n = shift;
    $v = shift;

    if (ref($v))
    {
      $self->LogInfo("MojoSession var '$n' =>", $v);
    }
    elsif (defined($v))
    {
      $self->LogInfo("MojoSession var '$n' => '$v'");
    }
    else
    {
      $self->LogInfo("MojoSession var '$n' => undef");
    }

    $self->_SetMojoSessionVariable($n, $v);
  }
}

sub KillMojoSessionVariable
{
  my ($self, $n) = @_;
  $self->LogInfo("MojoSession var '$n' deleted");
  $self->_KillMojoSessionVariable($n);
}

sub KillMojoSession
{
  # my ($self) = @_;
  $_[0]->LogInfo('Whole mojo session deleted');
  $_[0]->_KillMojoSession();
}

# ==== index.html =============================================================

sub _RenderIndexDefaults
{
  my ($self, $s, $status, $config) = @_;

  $config->{'window_id'} //= uuid_hex();
  $self->LogDebug("Generated window_id: $config->{'window_id'}");

  foreach (keys(%ENV))
  {
    $config->{lc($1)} = $ENV{$_}
      if /^CRUX_HTMLCFG_(.+)/;
    $self->stash(lc($1) => $ENV{$_})
      if /^CRUX_HTMLVAR_(.+)/;
  }
}

# $self->RenderIndex($s, $route);
# $self->RenderIndex($s, $route, $status, $config, $render_opts);
sub RenderIndex
{
  my $self = shift;
  my $s = shift
    if (blessed($_[0]) && $_[0]->isa('Crux::Stash'));

  my ($route, $status, $config, $render_opts);
  $route = shift unless ref($_[0]);
  ($status, $config, $render_opts) = @_;
  $render_opts //= {};
  $status //= {};
  $config //= {};

  $status->{'http_status'} = $render_opts->{'status'} // 200;
  $status->{'route'} = $route
    if defined($route);

  $self->_RenderIndexDefaults($s, $status, $config);

  $self->LogDebug('Status: ', $status);
  $self->LogDebug('Config: ', $config);
  $self->stash('crux_status' => to_json($status));
  $self->stash('crux_config' => to_json($config));

  $render_opts->{'template'} //= 'index';

  $self->render(%{$render_opts});
}

# ==== Parameters =============================================================

sub GetRouteParam
{
  my ($self, $n) = @_;
  my $match = $self->match();
  my $stack = $match->stack()->[$match->current()];
  return exists($stack->{$n}) ? ($stack->{$n}) : ()
    if wantarray;
  return $stack->{$n};
}

sub GetRouteParamHash
{
  my ($self) = @_;
  my $match = $self->match();
  my $stack = $match->stack()->[$match->current()];
  my $phs = $match->endpoint()->pattern()->placeholders();
  my $ret = { map { ($_ => $stack->{$_}) } @{$phs} };
  return %{$ret} if wantarray;
  return $ret;
}

# TODO
sub GetQueryParam
{
  return $_[0]->req()->query_params()->to_hash()->{$_[1]};
}
sub GetQueryParamHash
{
  my $ret = $_[0]->req()->query_params()->to_hash();
  return %{$ret} if wantarray;
  return $ret;
}

# ==== Misc ===================================================================

# http://stackoverflow.com/questions/49547/making-sure-a-web-page-is-not-cached-across-all-browsers
sub DisableCache
{
  # my ($self) = @_;
  my $hdrs = $_[0]->res()->headers();
  $hdrs->cache_control('no-cache, no-store, must-revalidate');
  $hdrs->expires(0);
  $hdrs->header('Pragma' => 'no-cache');
}

sub IsWebSocketRequest
{
  my ($self) = @_;
  my $upgrade = $self->req()->headers()->upgrade();
  return (defined($upgrade) && (lc($upgrade) eq 'websocket'));
}

# ==== Wrappers / Handlers ====================================================

sub GetRouteSetting
{
  # my ($self, $n, $d) = @_;

  my $route_settings = $_[0]->stash('crux.route_settings');
  return $route_settings ?
    (exists($route_settings->{$_[1]}) ? $route_settings->{$_[1]} : $_[2]) :
    $_[2];
}

sub _Handlers
{
  my ($self) = @_;

  my $handlers = $self->stash('crux._handlers');
  $self->Confess("D. B. Cooper was here")
    unless $handlers;
  $self->Confess("Jacob Black was here")
    unless (ref($handlers) eq 'ARRAY');

  return $handlers;
}

sub NextHandler
{
  my $self = shift;
  my $next = shift(@{$self->_Handlers()});
  $self->Confess("It's over, it ain't going any further")
    unless $next;
  # Essence::Logger->LogDebug("Next handler: $next", @_);
  return $self->$next(@_);
}

sub HijackNextHandler
{
  my $self = shift;
  unshift(@{$self->_Handlers()}, @_);
}

sub _MakeHandlers
{
  my ($self) = @_;
  my @handlers;

  if (my $route_settings = $self->stash('crux.route_settings'))
  {
    if (my $wrappers = $route_settings->{':wrap'})
    {
      push(@handlers,
          map { ref($_) ? $_ : "wrap_$_" }
              (ref($wrappers) ?  @{$wrappers} : ($wrappers)));
    }
  }
  if (my $action = $self->stash('crux.action'))
  {
    push(@handlers, ref($action) ? $action : "act_$action");
  }

  return @handlers;
}

sub MojoActionWrapper
{
  my $self = shift;

  $self->Confess("This is not good")
    if $self->stash('crux._handlers');

  my @handlers = $self->_MakeHandlers();
  die "No handlers.\n" unless @handlers;
  $self->stash('crux._handlers' => \@handlers);

  Essence::Logger->LogDebug('MojoSession:', $self->session());

  return $self->NextHandler($self->MakeStash(), @_);
}

###############################################################################

1
