#! /usr/bin/perl
###### NAMESPACE ##############################################################

package Crux::Model::FtsMixin_;

###### IMPORTS ################################################################

use Essence::Strict;

use Essence::Utils qw( normalize_str remove_html );
use Crux::Utils::Fts qw( grep_valid_fts_tokens );
use Scalar::Util qw( blessed );
use Carp;

###### METHODS ################################################################

# ---- _FtsValue --------------------------------------------------------------

# @fts = $self->_FtsValue_x($s, $attr, $v, $mc, $ma, @rest);
sub _FtsValue_default { return $_[3] }
sub _FtsValue_text { return normalize_str($_[3]) }

sub _FtsValue_html
{
  # my ($self, $s, $attr, $v, $mc, $ma, @rest) = @_;
  my ($self, @rest) = @_;
  $rest[2] = remove_html($rest[2]);
  return $self->_FtsValue_text(@rest);
}

sub _FtsValue_child
{
  # my ($self, $s, $attr, $v, $mc, $ma, @rest) = @_;
  my ($s, $v) = @_[1, 3];
  return map { $_->FtsText_($s) } @{$v} if (ref($v) eq 'ARRAY');
  return map { $_->FtsText_($s) } values(%{$v}) if (ref($v) eq 'HASH');
  return $v->FtsText_($s) if blessed($v);

  my ($self, $attr) = @_[0, 2];
  my $class = ref($self);
  my $v_class = defined($v) ? (ref($v) || '<scalar>') : '<undef>';
  confess "$class: Can't fts child '$attr' ($v_class)";
}

sub _FtsValue
{
  my ($self, $s, $attr, $v, $mc, $ma, @rest) = @_;

  $mc //= $self->get_metaclass();
  $ma //= $mc->GetAttribute($attr);

  my $kind = $ma->GetMeta('kind');
  my $method = (defined($kind) && $self->can("_FtsValue_$kind")) ||
      '_FtsValue_default';

  return $self->$method($s, $attr, $v, $mc, $ma, @rest);
}

# ---- _FtsAttr ---------------------------------------------------------------

sub _FtsAttr
{
  my ($self, $s, $attr, $mc, @rest) = @_;

  my $v = $self->Get($attr);
  return unless defined($v);

  my $ma = ($mc //= $self->get_metaclass())->GetAttribute($attr);
  return $self->_FtsValue($s, $attr, $v, $mc, $ma, @rest);
}

# ---- FtsText ----------------------------------------------------------------

sub FtsText_
{
  my ($self, $s, @rest) = @_;
  my $mc = $self->get_metaclass();
  return map { $self->_FtsAttr($s, $_, $mc, @rest) }
      $mc->GetAttributeNamesWithMeta('fts');
}

sub FtsText
{
  # my ($self, $s) = @_;
  my $self = shift;
  return normalize_str(
      join(' # ',
          grep_valid_fts_tokens(
              $self->FtsText_(@_))));
}

###############################################################################

1
