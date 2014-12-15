#! /usr/bin/perl
###### NAMESPACE ##############################################################

package Crux::Controller::ApiMixin;

use parent qw( Crux::Controller::JsonMixin Crux::Controller::TransactionMixin );

###### IMPORTS ################################################################

use Essence::Strict;

use Carp;

###### METHODS ################################################################

# ==== Routes =================================================================

sub add_model_routes
{
  my ($self, $app, $route_base, $model, $settings) =
      (shift, shift, shift, shift, shift);
  my $class = ref($self) || $self;

  my $route_id;
  $route_base =~ s{//+}{/}g;
  if ($route_base =~ m{^/?\z})
  {
    $route_base = '/';
    $route_id = '/:id';
  }
  else
  {
    $route_base =~ s{[^/]\K/+\z}{};
    $route_id = "$route_base/:id";
  }

  # TODO make this more modular
  my @rs;
  foreach (@_)
  {
    when ('create') { push(@rs, [ 'POST',   $route_base => $_ ]) }
    when ('list')   { push(@rs, [ 'GET',    $route_base => $_ ]) }
    when ('read')   { push(@rs, [ 'GET',    $route_id   => $_ ]) }
    when ('update') { push(@rs, [ 'PUT',    $route_id   => $_ ]) }
    when ('delete') { push(@rs, [ 'DELETE', $route_id   => $_ ]) }
    default { croak "Bad api action '$_'" }
  }

  $app->AddRoute($class,
      { ':wrap' => [ 'api' ], ':model' => $model },
      $settings,
      @rs)
    if @rs;
}

# ==== Wrap ===================================================================

sub wrap_api
{
  my $self = shift;
  $self->HijackNextHandler('wrap_json', 'wrap_transaction');
  return $self->NextHandler(@_);
}

# ==== Actions ================================================================

sub _act_model
{
  my ($self, $s, $action, @rest) = @_;

  my $api_action = $action;
  $api_action = "api_$api_action"
    unless ($api_action =~ /^(?:[a-z][0-9A-Za-z]*)?api_/);

  my $model = $s->Get('crux.model');
  if (!$model)
  {
    $model = $self->GetRouteSetting(':model') or
      confess "No model";
    $s->Set('crux.model' => $model);
  }

  Essence::Logger->LogInfo("${model}->$api_action");

  return $model->$api_action($s, @rest);
}

# ---- .../thing --------------------------------------------------------------

sub _act_noid { shift->_act_model(@_) }

sub act_create { return shift->_act_noid(shift, 'create', @_) }
sub act_list { return shift->_act_noid(shift, 'list', @_) }

# ---- .../thing/:id ----------------------------------------------------------

sub _act_id
{
  my ($self, $s, $action, @rest) = @_;
  return $self->_act_model($s, $action, scalar($self->param('id')), @rest);
}

sub act_read { return shift->_act_id(shift, 'read', @_) }
sub act_update { return shift->_act_id(shift, 'update', @_) }
sub act_delete { return shift->_act_id(shift, 'delete', @_) }

###############################################################################

1
