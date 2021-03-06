#! /usr/bin/perl
###### NAMESPACE ##############################################################

package Crux::Model::CompositeMixin;

###### IMPORTS ################################################################

use Essence::Strict;

use Essence::Merge;

###### METHODS ################################################################

sub _api_id_cols
{
  my ($class, @rest) = @_;
  return @{Essence::Merge::merge_arrays_keep_order(
      map { [$_->_api_id_cols(@rest)] } $class->get_components())};
}

sub api_load_by_id
{
  my ($class, $s, $id, $action, $opts) = @_;
  return $class->assemble($s,
      map {
            $_->api_call_clean($s, 'api_extract_verify_load',
                $action, $opts, $id);
          } $class->get_components());
}

sub _ApiDbInsert
{
  my $obj = shift;
  my ($s) = @_;

  $obj->_ApiPrepareDbWrite($s, 'insert');

  my @cs = $obj->GetComponents($s);
  my ($c, $v, $serials, @serials);
  while (@cs)
  {
    $c = shift(@cs)->_ApiDbInsert(@_);

    # Merge forward serials
    last unless @cs; # shortcut
    $serials = ref($c)->get_metaclass()->GetConfig('db.serial');
    if (defined($serials))
    {
      @serials = ref($serials) ? @{$serials} : ($serials);
      foreach my $n (@serials)
      {
        if (defined($v = $c->Get($s, $n)))
        {
          $_->Set($s, $n, $v) foreach @cs;
        }
      }
    }
  }

  return $obj;
}

sub _ApiDbUpdate
{
  my $obj = shift;
  my ($s) = @_;
  $obj->_ApiPrepareDbWrite($s, 'update');
  $_->_ApiDbUpdate(@_) foreach ($obj->GetComponents($s));
  return $obj;
}

###############################################################################

1
