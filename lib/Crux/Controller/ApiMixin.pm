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

  my $id = $settings->{':id'};
  if (!defined($id))
  {
    # CAVEAT: No $s
    my @id_cols = $model->api_id_col();
    $id = $id_cols[0] unless $#id_cols;
  }
  $id //= 'id';

  my $route_id;
  $route_base =~ s{//+}{/}g;
  if ($route_base =~ m{^/?\z})
  {
    $route_base = '/';
    $route_id = "/:$id";
  }
  else
  {
    $route_base =~ s{[^/]\K/+\z}{};
    $route_id = "$route_base/:$id";
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

sub _model
{
  # my ($self, $s, $action) = @_;
  my ($self, $s) = @_;
  my $model = $self->GetRouteSetting(':model');
  confess "No model" unless defined($model);
  return $model;
}

sub _act_model_
{
  # my ($self, $s, $action, $route_params, $query_params, @rest) = @_;
  my ($self, $s, $action, @rest) = @_;

  my $model = $self->_model($s, $action);
  my $api_action = $action;
  $api_action = "api_$api_action"
    unless ($api_action =~ /^(?:[a-z][0-9A-Za-z]*)?api_/);
  Essence::Logger->LogInfo("${model}->$api_action");

  # $model->$api_action($s, $route_params, $query_params, $post_json)
  return $model->$api_action($s, @rest);
}

sub _act_model
{
  my ($self, $s, $action, @rest) = @_;
  my $route_params = $self->GetRouteParamHash();
  my $query_params = $self->GetQueryParamHash();
  return $self->_act_model_($s, $action, $route_params, $query_params, @rest);
}

# .../thing
sub act_create { return shift->_act_model(shift, 'create', @_) }
sub act_list { return shift->_act_model(shift, 'list', @_) }

# .../thing/:id
sub act_read { return shift->_act_model(shift, 'read', @_) }
sub act_update { return shift->_act_model(shift, 'update', @_) }
sub act_delete { return shift->_act_model(shift, 'delete', @_) }

###############################################################################

1
