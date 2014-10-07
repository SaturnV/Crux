#! /usr/bin/perl
###### NAMESPACE ##############################################################

package Crux::JsonSanitizer;

###### IMPORTS ################################################################

use Essence::Strict;

use Storable qw( dclone );

###### Exports ################################################################

use Exporter qw( import );
our @EXPORT_OK = qw( sanitize_json remove_pwd remove_pwd_destructive );

###### SUBS ###################################################################

# ==== Sanitize ===============================================================

sub _sanitize_json;

sub _sanitize_json_msg
{
  my $msg = shift;
  my $loc = join('->', '$json', @_);
  return "$msg at $loc\n";
}

sub _sanitize_json_die { die _sanitize_json_msg(@_) }
sub _sanitize_json_warn { warn _sanitize_json_msg(@_) }

sub _sanitize_json_array
{
  my $j = shift;
  _sanitize_json($j->[$_], @_, "[$_]")
    foreach (0 .. $#{$j});
  return $j;
}

sub _sanitize_json_hash
{
  my $j = shift;
  foreach (keys(%{$j}))
  {
    _sanitize_json_die(
        "Bad key '" . quotemeta($_) . "'in hash", @_)
      unless /^[0-9A-Za-z:_.-]{1,32}\z/;
    _sanitize_json($j->{$_}, @_, "{'$_'}");
  }
  return $j;
}

sub _sanitize_json_str
{
  # http://stackoverflow.com/a/2973494
  if ($_[0])
  {
    my $c =
        $_[0] =~
            s/[\x{0000}\x{00ad}\x{0600}-\x{0604}\x{070f}\x{17b4}\x{17b5}\x{200c}-\x{200f}\x{2028}-\x{202f}\x{2060}-\x{206f}\x{feff}\x{fff0}-\x{ffff}]//g;
    _sanitize_json_warn("Removed $c suspicious characters", @_[1 .. $#_])
      if $c;
  }
  return $_[0];
}

sub _sanitize_json
{
  given (ref($_[0]))
  {
    when ('') { _sanitize_json_str(@_) if defined }
    when ('ARRAY') { _sanitize_json_array(@_) }
    when ('HASH') { _sanitize_json_hash(@_) }
    when (['Mojo::JSON::_Bool', 'JSON::XS::Boolean']) { $_[0] = $_[0] ? 1 : 0 }
    default { shift; _sanitize_json_die("Bad JSON data type '$_'", @_) }
  }

  return $_[0];
}

sub sanitize_json { return _sanitize_json(dclone($_[0])) }

# ==== Remove passwords =======================================================

sub remove_pwd_destructive
{
  given (ref($_[0]))
  {
    when ('ARRAY')
    {
      remove_pwd_destructive($_) foreach (@{$_[0]});
    }
    when ('HASH')
    {
      my $h = $_[0];
      foreach (keys(%{$h}))
      {
        if (ref($h->{$_}))
        {
          remove_pwd_destructive($h->{$_});
        }
        elsif (defined($h->{$_}) &&
               (/(?:^|_)pwd(?:_|\z)/ || /(?:^|_)password\z/))
        {
          $h->{$_} = '****';
        }
      }
    }
  }

  return $_[0];
}

sub remove_pwd
{
  return remove_pwd_destructive(dclone($_[0]));
}

###############################################################################

1
