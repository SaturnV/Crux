#! /usr/bin/perl
###### NAMESPACE ##############################################################

package Crux::Model::CompositeMixin;

###### IMPORTS ################################################################

use Essence::Strict;

use parent qw( Blueprint::Composite );

use Essence::Merge;

###### METHODS ################################################################

sub _api_id_cols
{
  my ($class, @rest) = @_;
  return @{Essence::Merge::merge_arrays_keep_order(
      map { [$_->_api_id_cols(@rest)] }
          @{$class->get_metaclass()->GetConfig(':components')})};
}

sub api_load_by_id
{
  # my ($class, $s, $id, $action, $opts) = @_;
  my ($class, $s, $id, $action, @rest) = @_;
  return $class->assemble($s,
      map {
            $_->api_load_by_id($s,
                $_->api_extract_verify_id($s, $action, $id),
                $action, @rest)
          } @{$class->get_metaclass()->GetConfig(':components')});
}

sub _ApiDbInsert
{
  my $obj = shift;
  my ($s) = @_;

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
  $_->_ApiDbUpdate(@_) foreach ($obj->GetComponents($s));
  return $obj;
}

###############################################################################

1
