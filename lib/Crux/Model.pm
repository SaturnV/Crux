#! /usr/bin/perl
###### NAMESPACE ##############################################################

package Crux::Model;

###### IMPORTS ################################################################

use Essence::Strict;

use base qw( Blueprint );

use Scalar::Util;
use Carp;

use Blueprint::Stash;

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

sub _api_new { return shift->new(@_) }

sub _ApiEdit { return shift->Edit(@_) }
sub _api_edit
{
  my ($class, $s, $obj) = (shift, shift, shift);
  return $obj->_ApiEdit($s, @_);
}

# DB

# TODO die \'not_found'
sub _api_db_load { return shift->db_load(@_) }

sub _api_db_insert
{
  my ($class, $s, $obj) = (shift, shift, shift);
  return $obj->_ApiDbInsert($s, @_);
}

sub _api_db_update
{
  my ($class, $s, $obj) = (shift, shift, shift);
  return $obj->_ApiDbUpdate($s, @_);
}

sub _api_db_delete
{
  my ($class, $s, $obj) = (shift, shift, shift);
  return Scalar::Util::blessed($obj) ?
      $obj->_ApiDbDelete($s, @_) :
      $class->db_delete($s, $obj, @_);
}

sub _ApiDbInsert
{
  my $obj = shift;
  $obj->DbInsert(@_);
  return $obj;
}

sub _ApiDbUpdate
{
  my $obj = shift;
  $obj->DbUpdate(@_);
  return $obj;
}

sub _ApiDbDelete
{
  my $obj = shift;
  $obj->DbDelete(@_);
  return $obj;
}

# ---- Helpers ----------------------------------------------------------------

sub _api_action_to_lock
{
  my ($class, $s, $action) = @_;
  $action //= $s->Get('crux.action') // '';
  return ($action =~ /^(?:read|list)(?:_|\z)/) ? 'r' : 'w';
}

sub api_load_by_id
{
  my ($class, $s, $id, $action_or_opts) = @_;
  my $obj;

  $id //= $s->Get('crux.params.id') or
    croak "Trying to load object without id";

  $action_or_opts //=
      { ':lock' => $class->_api_action_to_lock($s, $action_or_opts) }
    unless ref($action_or_opts);

  eval
  {
    $obj = $class->_api_db_load($s,
        { 'id' => $id },
        $action_or_opts);
  };
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
  # my ($class, $s, $id, $action_or_opts) = @_;
  my ($class, $s) = (shift, @_);
  return $s->Get('crux.obj') //
    $s->Set('crux.obj' => $class->api_load_by_id(@_));
}

sub _api_verify_set_id
{
  my ($class, $s, $id, $field) = @_;
  $field //= 'id';

  if (my $err = $class->verify('id' => $id))
  {
    Essence::Logger->LogInfo("$class.id: $err");
    die { 'code' => 'bad_value', 'fld' => $field };
  }
  $s->Set("crux.params.$field" => $id);

  return $id;
}

# ---- Verify -----------------------------------------------------------------

sub _api_verify_data
{
  # my ($class, $s, $op, $data) = @_;
  my ($class, $s, $op, $data) = (shift, shift, shift, @_);

  die { 'code' => 'bad_value' }
    unless (ref($data) eq 'HASH');

  my $metaattr;
  my $metaclass = $class->get_metaclass();
  my $re = qr/\b\Q$op\E\b/;

  foreach my $attr_name (keys(%{$data}))
  {
    # die { 'code' => 'unknown_param', 'fld' => $attr_name }
    #   unless ($metaattr = $metaclass->GetAttribute($attr_name));
    die { 'code' => 'no_access', 'fld' => $attr_name }
      unless (($metaattr = $metaclass->GetAttribute($attr_name)) &&
              (($metaattr->GetMeta('api') // '') =~ $re));
  }

  return @_ if wantarray;
  return $data;
}

sub _ApiVerify
{
  # my ($obj, $s, $op) = @_;
  return 1;
}

# ---- Tweak ------------------------------------------------------------------

sub _api_tweak_data
{
  # my ($class, $s, $op, $data) = @_;
  return $_[3] unless wantarray;
  shift; shift; shift;
  return @_;
}

sub _api_tweak_object
{
  # my ($class, $s, $op, $obj) = @_;
  return $_[3] unless wantarray;
  shift; shift; shift;
  return @_;
}

# ---- Create -----------------------------------------------------------------

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
  # my ($class, $s, $data) = @_;
  my ($class, $s) = (shift, shift);
  return $class->_api_create_($s,
      $class->_api_tweak_data($s, 'create',
          $class->_api_verify_data($s, 'create', @_)));
}

# Returns JSON
sub api_create
{
  # my ($class, $s, $data) = @_;
  my ($class, $s) = (shift, shift);
  return $class->_api_return($s, $class->api_create_($s, @_));
}

# ---- List -------------------------------------------------------------------

# TODO

# ---- Read -------------------------------------------------------------------

# All systems GO
sub _api_read_
{
  # my ($class, $s) = @_;
  return shift->api_object(shift);
}

# Returns object
sub api_read_
{
  # my ($class, $s, $id) = @_;
  my ($class, $s, $id) = (shift, shift, shift);
  $class->_api_verify_set_id($s, $id);
  return $class->_api_read_($s, @_);
}

# Returns JSON
sub api_read
{
  # my ($class, $s, $id, $data) = @_;
  my ($class, $s) = (shift, shift);
  return $class->_api_return($s, $class->api_read_($s, @_));
}

# ---- Update -----------------------------------------------------------------

# All systems GO
sub _api_update_
{
  # my ($class, $s, $data) = @_;
  my ($class, $s) = (shift, shift);
  my $obj = $class->api_object($s);
  $obj = $class->_api_tweak_object($s, 'update',
      $class->_api_edit($s, $obj, @_));
  $obj->_ApiVerify($s, 'update');
  return $class->_api_db_update($s, $obj);
}

# Returns object
sub api_update_
{
  # my ($class, $s, $id, $data) = @_;
  my ($class, $s, $id) = (shift, shift, shift);
  $class->_api_verify_set_id($s, $id);
  return $class->_api_update_($s,
      $class->_api_tweak_data($s, 'update',
          $class->_api_verify_data($s, 'update', @_)));
}

# Returns JSON
sub api_update
{
  # my ($class, $s, $id, $data) = @_;
  my ($class, $s) = (shift, shift);
  return $class->_api_return($s, $class->api_update_($s, @_));
}

# ---- Delete -----------------------------------------------------------------

# All systems GO
sub _api_delete_
{
  # my ($class, $s) = @_;
  my $class = shift;
  my $metaclass = $class->get_metaclass();
  return $metaclass->GetAttribute('deleted') ?
      $class->_api_delete_edit(@_) :
      $class->_api_delete_permanent(@_);
}

sub _api_delete_edit
{
  my ($class, $s) = @_;
  my $obj = $class->api_object($s);
  $obj = $class->_api_edit($s, $obj, { 'deleted' => 1 });
  return $class->_api_db_update($s, $obj);
}

sub _api_delete_permanent
{
  my ($class, $s) = @_;

  my $obj = $s->Get('crux.obj');
  if ($obj)
  {
    $class->_api_db_delete($s, $obj);
  }
  else
  {
    $class->_api_db_delete($s,
          { 'id' => scalar($s->Get('crux.params.id')) },
          {});
  }

  return;
}

# Returns object
sub api_delete_
{
  # my ($class, $s, $id) = @_;
  my ($class, $s, $id) = (shift, shift, shift);
  $class->_api_verify_set_id($s, $id);
  return $class->_api_delete_($s, @_);
}

# Returns JSON
sub api_delete
{
  # my ($class, $s, $id) = @_;
  my ($class, $s) = (shift, shift);
  return $class->_api_return($s, $class->api_delete_($s, @_));
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
      # 'crux.params.id' => undef,
      'crux.obj' => undef);

  return $self->$method($s_, @rest);
}

###############################################################################

1
