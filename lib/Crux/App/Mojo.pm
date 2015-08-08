#! /usr/bin/perl
###### NAMESPACE ##############################################################

package Crux::App::Mojo;

###### IMPORTS ################################################################

use Essence::Strict;

use Mojo::Base 'Mojolicious';
use parent 'Crux::App';
use mro 'c3';

use Coro;

use Carp;
use Essence::UUID;
use Essence::Logger qw();
use Essence::Logger::Id;
use Essence::Merge qw( merge_deep_override );

use Crux::MojoLogger;
use Crux::JsonSanitizer qw( remove_pwd_destructive );

###### METHODS ################################################################

# ==== Init ===================================================================

sub new
{
  # my $class = shift;
  my $self = shift->next::method(@_);
  $self->_Initialize()
    unless ($Crux::App && ($Crux::App eq $self));
  return $self;
}

sub startup
{
  my $self = $_[0];

  $self->secrets([split(',', $ENV{'CRUX_MOJO_SECRET'})])
    if defined($ENV{'CRUX_MOJO_SECRET'});

  # https://gist.github.com/kraih/6082061
  # Kraih (the Mojo guy) messes around with the hooks.
  # I don't understand what and why it is.
  # I don't use code I don't understand.
  $self->hook(
      'around_dispatch' =>
          sub { $self->_MojoDispatchMain(@_) });

  # This is recommended in the above gist, but it's a
  # significant cpu hit on mac and everything seems to
  # work properly without it.
  # Mojo::IOLoop->recurring(0 => sub { cede() });
}

# ==== Routing ================================================================

sub AddRoute
{
  my $self = shift;

  my $namespace = ref($_[0]) ? caller : shift or
    croak "Can't route without a namespace";
  $namespace->isa('Mojolicious::Controller') or
    croak "Can't route to class that is not a Mojolicious::Controller";

  my $mojo_router = $self->routes();

  my @common_settings;
  my ($mojo_method, $merged_settings);
  foreach my $r (@_)
  {
    if (ref($r) eq 'ARRAY')
    {
      my ($r_method, $r_path, $r_action, @r_misc) = @{$r};
      croak "No path in route.\n"
        unless defined($r_path);
      croak "No method in route for '$r_path'"
        unless defined($r_method);
      croak "No action for '$r_method $r_path'"
        unless defined($r_action);

      $mojo_method = lc($r_method);
      $merged_settings = merge_deep_override(@common_settings, @r_misc);
      # BUG $self->LogDebug(
      # Essence::Logger->LogDebug(
      #     "AddRoute $r_method $r_path -> ${namespace}::$r_action",
      #     $merged_settings);
      $mojo_router->$mojo_method($r_path)->to(
          'namespace' => $namespace,
          'action' => 'MojoActionWrapper',
          'crux.action' => $r_action,
          'crux.route_settings' => $merged_settings);
    }
    elsif (ref($r) eq 'HASH')
    {
      push(@common_settings, $r);
    }
    else
    {
      croak "Route '$r' doesn't look good";
    }
  }
}

# ==== Coro ===================================================================

sub _MojoDispatchMain
{
  my ($self, @rest) = @_;
  $self->app()->AsyncPool(sub { $self->_MojoDispatchCoro(@rest) });
  cede();
}

sub _MojoDispatchCoro { return shift->_Dispatch(@_) }

# ==== Dispatch ===============================================================

sub _Prepare
{
  my ($self, $c) = @_;

  my $req = $c->req();
  my $clickid = $Crux::Globals->{'Crux::ClickId'} =
      $req->{'Crux::ClickId'} //= uuid_url64();
  my $shortid = $Crux::Globals->{'Crux::ClickId::Short'} =
      $req->{'Crux::ClickId::Short'} //= substr($clickid, 0, 6);
  $Coro::current->desc($clickid);

  $Essence::Logger::Default =
      $Crux::Globals->{'Crux::Logger'} //=
          Essence::Logger::Id->new($shortid);

  return $clickid;
}

sub _Dispatch
{
  my ($self, $next, $c) = @_;

  my $clickid = $self->_Prepare($c);
  {
    local $Crux::Transactions{$clickid} = $c->tx();
    $self->_LogStart($c);
    $next->();
    $self->_LogEnd($c);
  }
}

# ==== Logging ================================================================

sub log
{
  return $_[0]->{'log'} //= Crux::MojoLogger->new();
}

sub _LogStart
{
  my ($self, $ctrl) = @_;
  my $req = $ctrl->req();
  my $tx = $ctrl->tx();

  my $remote_addr = $tx->remote_address();
  my $remote_port = $tx->remote_port();

  my %stuff_to_log =
      (
        'CLICKID' => $req->{'Crux::ClickId'},
        'CORO' => $Coro::current->{'Crux::Id'} // '???',
        'CLIENT' => "$remote_addr:$remote_port"
      );
  my $shortid = $req->{'Crux::ClickId::Short'} // 'anon';

  {
    my $method = $req->method();
    $stuff_to_log{'method'} = $method
      if defined($method);

    my $base = $req->url()->base()->to_string();
    my $path = $req->url()->path()->to_string();
    my $query = $req->url()->query();

    # TODO https, wss
    my $url = $base . $path;
    $url .= "?$query"
      if (defined($query) && ($query ne ''));

    $stuff_to_log{'url'} = $url;
  }

  $stuff_to_log{'headers'} = $req->headers()->to_hash();
  # $stuff_to_log{'session'} = $ctrl->session();

  my $params = $req->params()->to_hash();
  $stuff_to_log{'params'} = remove_pwd_destructive($params)
    if ($params && %{$params});

  # TODO cookies?

  Essence::Logger->LogInfo(
      "######## START $shortid ########",
      \%stuff_to_log);
}

sub _LogEnd
{
  my ($self, $ctrl) = @_;
  my $shortid = $Crux::Globals->{'Crux::ClickId::Short'} // 'anon';
  Essence::Logger->LogInfo("######## END $shortid ########");
}

###############################################################################

1
