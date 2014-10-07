#! /usr/bin/perl
###### NAMESPACE ##############################################################

package Crux::Controller;

###### IMPORTS ################################################################

use Essence::Strict;

use Mojo::Base 'Mojolicious::Controller';
use base 'Essence::Logger::Mixin';

use Essence::UUID;
use JSON;

###### METHODS ################################################################

sub ClickId { return $_[0]->req()->{'Crux::ClickId'} }
sub ShortId { return $_[0]->req()->{'Crux::ClickId::Short'} }

sub UserAgent
{
  return $_[0]->req()->content()->headers()->user_agent() // '<undef>';
}

sub UserAgentMatch
{
  my ($self, $pattern) = @_;
  return (defined($pattern) && ($self->UserAgent() =~ /\Q$pattern\E/i));
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
  my ($self, $status, $config) = @_;

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

# $self->RenderIndex($route);
# $self->RenderIndex($route, $status, $config, $render_opts);
sub RenderIndex
{
  my $self = shift;

  my ($route, $status, $config, $render_opts);
  $route = shift unless ref($_[0]);
  ($status, $config, $render_opts) = @_;
  $render_opts //= {};
  $status //= {};
  $config //= {};

  $status->{'http_status'} = $render_opts->{'status'} // 200;
  $status->{'route'} = $route
    if defined($route);

  $self->_RenderIndexDefaults($status, $config);

  $self->LogDebug('Status: ', $status);
  $self->LogDebug('Config: ', $config);
  $self->stash('crux_status' => to_json($status));
  $self->stash('crux_config' => to_json($config));

  $render_opts->{'template'} //= 'index';

  $self->render(%{$render_opts});
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

sub GetRouteParam
{
  # my ($self, $n, $d) = @_;

  my $route_params = $_[0]->stash('crux.route_params');
  return $route_params ?
    (exists($route_params->{$_[1]}) ? $route_params->{$_[1]} : $_[2]) :
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

  if (my $route_params = $self->stash('crux.route_params'))
  {
    if (my $wrappers = $route_params->{':wrap'})
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

  return $self->NextHandler(@_);
}

###############################################################################

1