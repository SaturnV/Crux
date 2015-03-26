#! /usr/bin/perl
###### NAMESPACE ##############################################################

package Crux::Model;

###### IMPORTS ################################################################

use Essence::Strict;

use parent qw( Blueprint );

use Scalar::Util;
use Carp;

use Blueprint::Stash;

use Crux::_Queue;

###### VARS ###################################################################

my $mod_name = __PACKAGE__;

###### METHODS ################################################################

# ==== API ====================================================================

sub _api_return
{
  # my ($class, $s, $obj) = @_;
  return ref($_[2]) ? $_[2]->SerializeToJson($_[1]) : $_[2];
}

# ---- Blueprint interface ----------------------------------------------------

sub _api_id_cols
{
  my ($self) = @_;
  my $class = ref($self) || $self;
  my $metaclass = $class->get_metaclass();
  my $key = $metaclass->GetConfig('db.key') // 'id';
  return ref($key) ? @{$key} : ($key);
}

sub api_id_col
{
  my ($self, $s) = @_;
  my $class = ref($self) || $self;
  my @id_cols = $self->_api_id_cols($s);

  die "$class: No id" unless @id_cols;
  die "$class: Composite ids not supported.\n"
    if ((scalar(@id_cols) > 1) && !wantarray);

  return @id_cols if wantarray;
  return $id_cols[0];
}

sub _api_new { return shift->new(@_) }

sub _ApiEdit { return shift->Edit(@_) }
sub _api_edit
{
  my ($class, $s, $obj, @rest) = @_;
  return $obj->_ApiEdit($s, @rest);
}

# DB

sub _api_id2where
{
  # my ($class, $s, $action, $id) = @_;
  my ($class, $s, undef, $id) = @_;
  my $where;

  if (ref($id))
  {
    my @id_cols = $class->api_id_col($s);
    # $where = {};
    # @{$where}{@id_cols} = @{$id}{@id_cols};
    $where = { map { ($_ => $id->{$_}) } @id_cols };
  }
  else
  {
    my $id_col = $class->api_id_col($s);
    $where = { $id_col => $id };
  }

  return $where;
}

# TODO die \'not_found'
sub _api_db_load { return shift->db_load(@_) }

sub _api_db_insert
{
  my ($class, $s, $obj, @rest) = @_;
  return $obj->_ApiDbInsert($s, @rest);
}

sub _api_db_update
{
  my ($class, $s, $obj, @rest) = @_;
  return $obj->_ApiDbUpdate($s, @rest);
}

sub _api_db_delete
{
  my ($class, $s, $obj, @rest) = @_;
  return Scalar::Util::blessed($obj) ?
      $obj->_ApiDbDelete($s, @rest) :
      $class->db_delete($s, $obj, @rest);
}

sub _ApiPrepareDbWrite { return }

sub _ApiDbInsert
{
  my $obj = shift;
  $obj->_ApiPrepareDbWrite($_[0], 'insert');
  $obj->DbInsert(@_);
  return $obj;
}

sub _ApiDbUpdate
{
  my $obj = shift;
  $obj->_ApiPrepareDbWrite($_[0], 'update');
  $obj->DbUpdate(@_);
  return $obj;
}

sub _ApiDbDelete
{
  my $obj = shift;
  $obj->DbDelete(@_);
  return $obj;
}

# ---- Delayed Update ---------------------------------------------------------

sub __crux_delayed_update
{
  my ($s, $ret) = @_;

  if (my $q = $s->Singleton('crux_delayed_update'))
  {
    my $obj;
    $obj->_ApiDbUpdate($s) while ($obj = $q->Shift());
  }

  return $ret;
}

sub ApiDelayedUpdate
{
  my ($obj, $s) = @_;

  my $q = $s->Singleton('crux_delayed_update');
  if (!$q)
  {
    $q = $s->Singleton('crux_delayed_update', Crux::_Queue->new());
    $s->BeforeCommit(\&__crux_delayed_update);
  }
  $q->Push($obj);

  return $obj;
}

# ---- Helpers ----------------------------------------------------------------

sub api_extract_id
{
  # my ($class, $s, $action, $route_params, $query_param, $post_data) = @_;
  my ($class, $s, undef, $route_params) = @_;
  my @id_cols = $class->api_id_col($s);
  return $#id_cols ?
      { map { ($_ => $route_params->{$_}) } @id_cols } :
      $route_params->{$id_cols[0]};
}

sub api_verify_id
{
  my ($class, $s, $id) = @_;

  if (ref($id))
  {
    my $err;
    my @id_cols = $class->api_id_col($s);
    my %id_cols = ( map { ($_ => 1) } @id_cols );
    foreach my $k (keys(%{$id}))
    {
      if (!$id_cols{$k})
      {
        Essence::Logger->LogInfo("$class.$k: Bad key component");
        die { 'code' => 'bad_value', 'fld' => $k };
      }
      if ($err = $class->verify($k => $id->{$k}))
      {
        Essence::Logger->LogInfo("$class.$k: $err");
        die { 'code' => 'bad_value', 'fld' => $k };
      }
    }

    my @missing = grep { !exists($id->{$_}) } @id_cols;
    if (@missing)
    {
      Essence::Logger->LogInfo(
          "$class: Missing key component: " .
          join(', ', @missing));
      die [ map { { 'code' => 'missing_param', 'fld' => $_ } } @missing ];
    }

    $id = $id->{$id_cols[0]} unless $#id_cols;
  }
  else
  {
    my $id_col = $class->api_id_col($s);
    if (my $err = $class->verify($id_col => $id))
    {
      Essence::Logger->LogInfo("$class.$id_col: $err");
      die { 'code' => 'bad_value', 'fld' => $id_col };
    }
  }

  return $id;
}

sub api_extract_verify_id
{
  # my ($class, $s, $action, $route_params, $query_param, $post_data) = @_;
  my ($class, $s, @rest) = @_;
  return $class->api_verify_id($s,
      $class->api_extract_id($s, @rest));
}

sub _api_action_to_lock
{
  my ($class, $s, $action) = @_;
  return (defined($action) && ($action =~ /^(?:read|list)(?:_|\z)/)) ?
      'r' : 'w';
}

sub api_load_by_id
{
  my ($class, $s, $id, $action, $opts) = @_;
  my $obj;

  croak "Trying to load object ($class) without id"
    unless defined($id);

  $opts //= { ':lock' => $class->_api_action_to_lock($s, $action) };

  my $where = $class->_api_id2where($s, 'load', $id);
  $obj = eval { $class->_api_db_load($s, $where, $opts) };
  if ($@)
  {
    die $@ if (ref($@) && !Scalar::Util::blessed($@));
    Essence::Logger->LogInfo("load: $@");
    die \'not_found' unless $obj;
  }

  return $obj;
}

sub api_object
{
  # my ($class, $s, $id, $action, $opts) = @_;
  my ($class, $s, @rest) = @_;
  return $s->Get('crux_obj') //
    $s->Set('crux_obj' => $class->api_load_by_id($s, @rest));
}

sub api_extract_verify_load
{
  # my ($class, $s, $action, $opts,
  #     $route_params, $query_param, $post_data) = @_;
  my ($class, $s, $action, $opts, @rest) = @_;

  # $classi->api_load_by_id($s, $id, $action, $opts);
  # $class->api_extract_verify_id($s, $action, ...);
  return $class->api_load_by_id($s,
      $class->api_extract_verify_id($s, $action, @rest),
      $action, $opts);
}

sub api_extract_verify_object
{
  # my ($class, $s, $action, $opts,
  #     $route_params, $query_param, $post_data) = @_;
  my ($class, $s, @rest) = @_;
  return $s->Get('crux_obj') //
      $s->Set('crux_obj' => $class->api_extract_verify_load($s, @rest));
}

# ---- Verify -----------------------------------------------------------------

sub _api_verify_data
{
  # my ($class, $s, $action, $data, ...) = @_;
  my ($class, $s, $action, @rest) = @_;
  my ($data) = @rest;

  die { 'code' => 'bad_value' }
    unless (ref($data) eq 'HASH');

  my $metaattr;
  my $metaclass = $class->get_metaclass();
  my $re = qr/\b\Q$action\E\b/;

  foreach my $attr_name (keys(%{$data}))
  {
    # die { 'code' => 'unknown_param', 'fld' => $attr_name }
    #   unless ($metaattr = $metaclass->GetAttribute($attr_name));
    die { 'code' => 'no_access', 'fld' => $attr_name }
      unless (($metaattr = $metaclass->GetAttribute($attr_name)) &&
              (($metaattr->GetMeta('api') // '') =~ $re));
  }

  return @rest if wantarray;
  return $data;
}

sub _ApiVerify
{
  # my ($obj, $s, $action) = @_;
  return 1;
}

# ---- Tweak ------------------------------------------------------------------

sub _api_tweak_data
{
  # my ($class, $s, $action, $data, ...) = @_;
  return $_[3] unless wantarray;
  shift; shift; shift;
  return @_;
}

sub _api_tweak_object
{
  # my ($class, $s, $action, $obj) = @_;
  return $_[3] unless wantarray;
  shift; shift; shift;
  return @_;
}

# ---- Create -----------------------------------------------------------------

sub _api_create_input
{
  my ($class, $s, $route_params, $query_param, $post_data) = @_;
  my $data = { %{$post_data} };

  foreach ($class->api_id_col($s))
  {
    $data->{$_} = $route_params->{$_}
      if exists($route_params->{$_});
  }

  return $data unless wantarray;
  shift; shift;
  return ($data, @_);
}

# All systems GO
sub _api_create_
{
  # my ($class, $s, $data) = @_;
  my ($class, $s) = (shift, shift);
  my $obj = $class->_api_tweak_object($s, 'create',
      $class->_api_new($s, @_));
  $obj->_ApiVerify($s, 'create');
  return $class->_api_db_insert($s, $obj);
}

# Returns object
sub api_create_
{
  # my ($class, $s, $route_params, $query_param, $post_data) = @_;
  my ($class, $s, @params) = @_;
  my $action = 'create';
  return $class->_api_create_($s,
      $class->_api_tweak_data($s, 'create',
          $class->_api_verify_data($s, 'create',
              $class->_api_create_input($s, @params))));
}

# Returns JSON
sub api_create
{
  # my ($class, $s, $route_params, $query_param, $post_data) = @_;
  my ($class, $s, @params) = @_;
  return $class->_api_return($s, $class->api_create_($s, @params));
}

# ---- List -------------------------------------------------------------------

# TODO

# ---- Read -------------------------------------------------------------------

# All systems GO
sub _api_read_
{
  # my ($class, $s, $id, $route_params, $query_param) = @_;
  my ($class, $s, $id) = @_;
  return $class->api_object($s, $id, 'read');
}

# Returns object
sub api_read_
{
  # my ($class, $s, $route_params, $query_param) = @_;
  my ($class, $s, @params) = @_;
  return $class->_api_read_($s,
      $class->api_extract_verify_id($s, 'read', @params),
      @params);
}

# Returns JSON
sub api_read
{
  # my ($class, $s, $route_params, $query_param) = @_;
  my ($class, $s, @params) = @_;
  return $class->_api_return($s, $class->api_read_($s, @params));
}

# ---- Update -----------------------------------------------------------------

sub _api_update_input
{
  # my ($class, $s, $route_params, $query_param, $post_data) = @_;
  my $data = { %{$_[4]} };
  return $data unless wantarray;
  shift; shift;
  return ($data, @_);
}

# All systems GO
sub _api_update_
{
  # my ($class, $s, $id, $data, $route_params, $query_param, $post_data) = @_;
  my ($class, $s, $id, $data) = @_;
  my $obj = $class->api_object($s, $id, 'update');
  $obj = $class->_api_tweak_object($s, 'update',
      $class->_api_edit($s, $obj, $data));
  $obj->_ApiVerify($s, 'update');
  return $class->_api_db_update($s, $obj);
}

# Returns object
sub api_update_
{
  # my ($class, $s, $route_params, $query_param, $post_data) = @_;
  my ($class, $s, @params) = @_;
  return $class->_api_update_($s,
      $class->api_extract_verify_id($s, 'update', @params),
      $class->_api_tweak_data($s, 'update',
          $class->_api_verify_data($s, 'update',
              $class->_api_update_input($s, @params))));
}

# Returns JSON
sub api_update
{
  # my ($class, $s, $route_params, $query_param, $post_data) = @_;
  my ($class, $s, @rest) = @_;
  return $class->_api_return($s, $class->api_update_($s, @rest));
}

# ---- Delete -----------------------------------------------------------------

sub _api_delete_edit
{
  my ($class, $s, $id) = @_;
  my $obj = $class->api_object($s, $id, 'delete');
  $obj = $class->_api_edit($s, $obj, { 'deleted' => 1 });
  return $class->_api_db_update($s, $obj);
}

sub _api_delete_permanent
{
  my ($class, $s, $id) = @_;

  my $obj = $s->Get('crux_obj');
  if ($obj)
  {
    $class->_api_db_delete($s, $obj);
  }
  else
  {
    $class->_api_db_delete($s,
        $class->_api_id2where($s, 'delete', $id),
        {});
  }

  return;
}

# All systems GO
sub _api_delete_
{
  # my ($class, $s, $id, $route_params, $query_param, $post_data) = @_;
  my $class = shift;
  my $metaclass = $class->get_metaclass();
  return $metaclass->GetAttribute('deleted') ?
      $class->_api_delete_edit(@_) :
      $class->_api_delete_permanent(@_);
}

# Returns object
sub api_delete_
{
  # my ($class, $s, $route_params, $query_param, $post_data) = @_;
  my ($class, $s, @params) = @_;
  return $class->_api_delete_($s,
      $class->api_extract_verify_id($s, 'delete', @params),
      @params);
}

# Returns JSON
sub api_delete
{
  # my ($class, $s, $route_params, $query_param, $post_data) = @_;
  my ($class, $s, @params) = @_;
  return $class->_api_return($s, $class->api_delete_($s, @params));
}

# ---- Misc -------------------------------------------------------------------

sub api_call_clean
{
  my ($self, $s, @rest) = @_;

  my (@patch, $method);
  push(@patch, shift(@rest))
    while (@rest && (ref($rest[0]) eq 'HASH'));
  $method = shift(@rest);

  my $s_ = ref($s)->new(
      ':base' => $s,
      @patch,
      'crux_obj' => undef);

  return $self->$method($s_, @rest);
}

###############################################################################

1
