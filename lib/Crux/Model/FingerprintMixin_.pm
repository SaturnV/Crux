#! /usr/bin/perl
###### NAMESPACE ##############################################################

package Crux::Model::FingerprintMixin_;

###### IMPORTS ################################################################

use Essence::Strict;

use Essence::Utils qw( xne normalize_str remove_html );
use Crux::Utils::Fingerprint qw( fingerprint );
use Scalar::Util qw( blessed );
use Carp;

###### SUBS ###################################################################

sub __has { return ((ref($_[0]) eq 'HASH') && exists($_[0]->{$_[1]})) }
sub __Has
{
  return (blessed($_[0]) &&
          $_[0]->can('get_metaclass') &&
          $_[0]->get_metaclass()->GetAttribute($_[1]));
}

###### METHODS ################################################################

# ---- _FingerprintValue ------------------------------------------------------

# TODO Better default check (default.Set, builder, objects/refs)
sub _FingerprintValue_default
{
  # my ($self, $s, $fp, $attr, $v, $mc, $ma, @rest) = @_;
  my ($v, $ma) = @_[4, 6];
  my @default = $ma->GetConfig(':default.new');
  return (!@default || xne($v, $default[0])) ? ($v) : ();
}

sub _FingerprintValue_text
{
  # my ($self, $s, $fp, $attr, $v, $mc, $ma, @rest) = @_;
  my $fp_str = lc(normalize_str($_[4]));
  return (defined($fp_str) && ($fp_str ne '')) ? ($fp_str) : ();
}

sub _FingerprintValue_html
{
  # my ($self, $s, $fp, $attr, $v, $mc, $ma, @rest) = @_;
  my ($self, @rest) = @_;
  $rest[3] = remove_html($rest[3]);
  return $self->_FingerprintValue_text(@rest);
}

sub _FingerprintChildren
{
  my ($self, $s, $fp, $attr, $v, $mc, $ma, $rest, @objs) = @_;

  if (__Has($objs[0], '_fingerprint'))
  {
    return map { scalar($_->Get('_fingerprint')) } @objs;
  }
  elsif (__has($objs[0], '_fingerprint'))
  {
    return map { $_->{'_fingerprint'} } @objs;
  }
  elsif (blessed($objs[0]))
  {
    return map { $_->Fingerprint_($s, @{$rest}) } @objs
      if $objs[0]->can('Fingerprint_');

    my $class = ref($self);
    my $obj_class = ref($objs[0]);
    confess "$class: Can't fingerprint child '$attr' ($obj_class)"
  }
  else
  {
    return @objs;
  }
}

sub _FingerprintValue_child
{
  my ($self, $s, $fp, $attr, $v, $mc, $ma, @rest) = @_;

  if (ref($v) eq 'ARRAY')
  {
    return unless @{$v};

    # @objs and @fps are assumed homogeneous
    my @objs = @{$v};

    my $sorted;
    if (__Has($objs[0], 'rank'))
    {
      @objs = sort { $a->Get('rank') <=> $b->Get('rank') } @objs;
      $sorted = 1;
    }
    elsif (__has($objs[0], 'rank'))
    {
      @objs = sort { $a->{'rank'} <=> $b->{'rank'} } @objs;
      $sorted = 1;
    }

    my @fps = $self->_FingerprintChildren(
        $s, $fp, $attr, $v, $mc, $ma, \@rest, @objs);
    @fps = sort @fps unless ($sorted || ref($fps[0]));

    return \@fps;
  }
  elsif (ref($v) eq 'HASH')
  {
    my %fps;
    my @keys = keys(%{$v});
    @fps{@keys} = $self->_FingerprintChildren(
        $s, $fp, $attr, $v, $mc, $ma, \@rest, @{$v}{@keys});
  }
  else
  {
    return $self->_FingerprintChildren(
        $s, $fp, $attr, $v, $mc, $ma, \@rest, $v);
  }
}

sub _FingerprintValue
{
  my ($self, $s, $fp, $attr, $v, $mc, $ma, @rest) = @_;

  $mc //= $self->get_metaclass();
  $ma //= $mc->GetAttribute($attr);

  my $kind = $ma->GetMeta('kind');
  my $method = (defined($kind) && $self->can("_FingerprintValue_$kind")) ||
      '_FingerprintValue_default';

  return $self->$method($s, $fp, $attr, $v, $mc, $ma, @rest);
}

# ---- _FingerprintAttr -------------------------------------------------------

sub _FingerprintAttr
{
  my ($self, $s, $fp, $attr, $mc, @rest) = @_;

  my $v = $self->Get($attr);
  return unless defined($v);

  my $ma = ($mc //= $self->get_metaclass())->GetAttribute($attr);
  return $self->_FingerprintValue($s, $fp, $attr, $v, $mc, $ma, @rest);
}

# ---- Fingerprint ------------------------------------------------------------

sub Fingerprint_
{
  my ($self, $s, $fp, @rest) = @_;

  # No / missing / default value should not even exist in fp hash
  # to allow for extension without reindexing.

  my @fp;
  my $mc = $self->get_metaclass();
  foreach my $attr ($mc->GetAttributeNamesWithMeta('fingerprint'))
  {
    $fp->{$attr} = $fp[0]
      if (@fp = $self->_FingerprintAttr($s, $fp, $attr, $mc, @rest));
  }

  return $fp;
}

sub Fingerprint
{
  my ($self, $s, @rest) = @_;
  return fingerprint($self->Fingerprint_($s, {}, @rest));
}

###############################################################################

1
