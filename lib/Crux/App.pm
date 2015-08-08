#! /usr/bin/perl
# Coro, Devil should be optional
###### NAMESPACE ##############################################################

package Crux::App;

###### IMPORTS ################################################################

use Essence::Strict;

use parent 'Essence::Logger::Mixin';

use Coro;
use Devil;

use Essence::UUID;
use Essence::Module;
use Essence::Logger::Id;
use Scalar::Util qw( blessed );
use List::MoreUtils qw( any );
use Carp;

# TODO These are needed for DB => should be optional
use AnyEvent;
use Essence::Sql;
use Essence::Sql::AsyncMysql;

use Crux::Stash;

###### VARS ###################################################################

my $coro_worker_seq = 0;

our $CoroDebug;

our $EventQueueLength = $ENV{'CRUX_REALTIME_BACKLOG'} // 100;

###### METHODS ################################################################

# ==== Startup ================================================================

sub new
{
  # my $self = bless({}, $class);
  return bless({}, $_[0])->_Initialize();
}

sub _Initialize
{
  my $self = $_[0];

  $Essence::Logger::Default //= Essence::Logger::Id->new("#$$");

  # TODO This seems like a pretty arbitrary limitation -> remove.
  $self->LogWarn("More apps seem to be running?")
    if ($Crux::App && ($Crux::App ne $self));

  if (!$ENV{'CRUX_MODE_PRODUCTION'} && !$CoroDebug)
  {
    require Coro::Debug;
    $CoroDebug = Coro::Debug->new_unix_server('/tmp/crux_debug.sock');
  }

  $self->_InitializeRealtime();

  return $Crux::App = $self;
}

sub load_module
{
  # my ($self, $from, $module) = @_;
  my $module_class = Essence::Module::load_module(@_);
  # log_info "Loading module $module_class";
  return $module_class->initialize($_[0]);
}

# Doesn't use Get/ReleaseDatabase, plain blocking Sql, no Coro
sub just_gimme_s_with_db
{
  Essence::Sql->connect();
  return shift->new()->MakeStash('db' => 'Essence::Sql', @_);
}

# ==== Coro ===================================================================

sub Async
{
  my ($self, @rest) = @_;
  return async { $self->_CoroWrapper(@rest) };
}

sub AsyncPool
{
  my ($self, @rest) = @_;
  return async_pool { $self->_CoroWrapper(@rest) };
}

sub _CoroWrapper
{
  my ($self, $sub, @args) = @_;

  my $my = {};
  my $saved = {};
  Coro::on_enter { $self->_CoroEnter($my, $saved) };
  Coro::on_leave { $self->_CoroLeave($my, $saved) };
  $self->_CoroSetup($my, $saved);

  Devil->initialize_coro();
  my $ret = (ref($sub) eq 'CODE') ? $sub->(@args) : $self->$sub(@args);
  Devil->cleanup_coro();

  return $ret;
}

sub _CoroSetup
{
  if (!defined($Coro::current->{'Crux::Id'}))
  {
    $Coro::current->{'Crux::Id'} = $coro_worker_seq++;
    $_[0]->_CoroSetupNew();
  }

  $Crux::Globals = {};
}

sub _CoroSetupNew
{
  Essence::Logger->install_handlers();
}

sub _CoroEnter
{
  my ($self, $my, $saved) = @_;

  $saved->{'Crux::Globals'} = $Crux::Globals;
  $Crux::Globals = $my->{'Crux::Globals'};

  $saved->{'Essence::Logger::Default'} = $Essence::Logger::Default;
  $Essence::Logger::Default = $my->{'Essence::Logger::Default'}
    if $my->{'Essence::Logger::Default'};

  # $saved->{'xxx'} = $xxx;
  # $xxx = $my->{'xxx'};
}

sub _CoroLeave
{
  my ($self, $my, $saved) = @_;

  $my->{'Essence::Logger::Default'} = $Essence::Logger::Default;
  $Essence::Logger::Default = $saved->{'Essence::Logger::Default'};

  $my->{'Crux::Globals'} = $Crux::Globals;
  $Crux::Globals = $saved->{'Crux::Globals'};

  # $my->{'xxx'} = $Crux::Globals;
  # $Crux::Globals = $saved->{'xxx'};
}

# ==== Realtime ===============================================================

sub _InitializeRealtime
{
  my ($self) = @_;
  $self->{'Crux::Guid'} //= uuid_hex();
  $self->{'Crux::EventSeq'} //= 0;
  $self->{'Crux::EventQueueBase'} //= 0;
  $self->{'Crux::EventQueue'} //= [];
  return $self;
}

sub SubmitRealtimeEvents
{
  my $self = shift;

  if (@_)
  {
    Essence::Logger->LogDebug('Realtime events:', \@_);

    my $eq = $self->{'Crux::EventQueue'};

    $_->{'rtsq'} = $self->{'Crux::EventSeq'}++ foreach(@_);
    push(@{$eq}, @_);

    if (scalar(@{$eq}) > $EventQueueLength)
    {
      my $drop = scalar(@{$eq}) - $EventQueueLength;
      splice(@{$eq}, 0, $drop);
      $self->{'Crux::EventQueueBase'} += $drop;
    }

    Devil->signal('realtime_events');
  }

  return $self;
}

sub RealtimeEventsFrom
{
  my ($self, $rtsq) = @_;
  my $from = $rtsq - $self->{'Crux::EventQueueBase'};
  my $to = $#{$self->{'Crux::EventQueue'}};
  return @{$self->{'Crux::EventQueue'}}[$from .. $to];
}

sub RealtimeMarkJson
{
  my ($self, $json) = @_;
  $json->{'rtid'} = $self->{'Crux::Guid'};
  $json->{'rtsq'} = $self->{'Crux::EventSeq'};
  return $json;
}

# ==== Stash ==================================================================

sub MakeStash
{
  my $self = shift;
  my $stash = Crux::Stash->new(@_);
  $stash->Set('Crux::App' => $self);
  return $stash;
}

# ==== Database ===============================================================
# TODO Make this optional

sub GetDatabase
{
  my ($self) = @_;
  my $db;

  if (!$self->{'Crux::DbQueue'})
  {
    $Essence::Sql::Debug //= 1
      unless $ENV{'CRUX_MODE_PRODUCTION'};
    $self->{'Crux::DbQueue'} = [];
    $self->{'Crux::DbSeq'} = 0;
  }

  if (@{$self->{'Crux::DbQueue'}})
  {
    $db = shift(@{$self->{'Crux::DbQueue'}});
    undef($self->{'Crux::DbKeepalive'})
      unless @{$self->{'Crux::DbQueue'}};
  }
  else
  {
    $db = Essence::Sql::AsyncMysql->new();
    $db->{'Crux::Id'} = $self->{'Crux::DbSeq'}++
      if $db->isa('HASH');
  }

  # Essence::Logger->LogDebug("Using DB $db->{'Crux::Id'}");

  return $db;
}

sub ReleaseDatabase
{
  my ($self, $db) = @_;

  croak "Trying to release a DB, before getting one"
    unless $self->{'Crux::DbQueue'};
  croak "Released DB doesn't look right"
    unless (blessed($db) && $db->isa('Essence::Sql'));
  croak "Trying to release DB twice"
    if (any { $_ eq $db } @{$self->{'Crux::DbQueue'}});
  push(@{$self->{'Crux::DbQueue'}}, $db);

  # Essence::Logger->LogDebug("Released DB $db->{'Crux::Id'}");

  $self->{'Crux::DbKeepalive'} //=
      AnyEvent->timer(
          'after' => 60,
          'interval' => 60,
          'cb' => sub { $self->AsyncPool('_DbKeepalive') });

  return $self;
}

sub WrapInTransaction
{
  my ($self, $s, $sub, @args) = (shift);
  my $ret;

  $s = (@_ && blessed($_[0]) && $_[0]->isa('Crux::Stash')) ?
      shift :
      $self->MakeStash();
  ($sub, @args) = @_;

  my $db = $self->GetDatabase();
  $s->Set('db' => $db);

  eval
  {
    $ret = $db->wrap_in_transaction(
        sub { return $s->TriggerBeforeCommit(scalar($sub->($s, @args))) });
  };
  my $error = $@;

  if ($error && ($error =~ /\bdatabase error\b/i))
  {
    warn "Database error, dropping DBH.\n";
  }
  else
  {
    $self->ReleaseDatabase($db);
    $s->Set('db' => undef);
  }

  if ($error)
  {
    $s->TriggerAfterRollback($ret);
    die $error;
  }

  $ret = $s->TriggerAfterCommit($ret);
  $s->SubmitRealtimeEvents();

  return $ret;
}

sub WrapInTransactionEval
{
  my $ret = eval { shift->WrapInTransaction(@_) };
  Essence::Logger->LogError("$@") if $@;
  return $ret;
}

sub DbKeepalive
{
  my ($self) = @_;

  if (@{$self->{'Crux::DbQueue'}})
  {
    my $db = $self->GetDatabase();

    eval { $db->do_select_col('SELECT 1') };
    if ($@)
    {
      Essence::Logger->LogWarning($@);
      Essence::Logger->LogWarning(
          'DB connection died, killing all queued handles');
      $self->{'Crux::DbQueue'} = [];
    }
    else
    {
      $self->ReleaseDatabase($db);
    }
  }

  return $self;
}

sub _DbKeepalive
{
  my ($self) = @_;

  $Coro::current->desc("Database Keepalive");
  $Essence::Logger::Default =
      $Crux::Globals->{'Crux::Logger'} //=
          Essence::Logger::Id->new('dbkeeper');

  eval { $self->DbKeepalive() };
  Essence::Logger->LogFatal($@) if $@;

  return;
}

###############################################################################

1
