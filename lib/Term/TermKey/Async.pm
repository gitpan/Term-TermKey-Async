#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2008 -- leonerd@leonerd.org.uk

package Term::TermKey::Async;

use strict;
use base qw( IO::Async::Notifier );

our $VERSION = '0.01';

use Carp;

use Term::TermKey qw( RES_EOF RES_KEY RES_AGAIN );

=head1 NAME

C<Term::TermKey::Async> - perl wrapper around C<libtermkey> for C<IO::Async>

=head1 SYNOPSIS

 use Term::TermKey::Async qw( FORMAT_VIM KEYMOD_CTRL );
 use IO::Async::Loop;
 
 my $loop = IO::Async::Loop->new();
 
 my $tka = Term::TermKey::Async->new(
    term => \*STDIN,

    on_key => sub {
       my ( $self, $key ) = @_;
 
       print "Got key: ".$self->format_key( $key, FORMAT_VIM )."\n";
 
       $loop->loop_stop if $key->type_is_unicode and
                           $key->utf8 eq "C" and
                           $key->modifiers & KEYMOD_CTRL;
    },
 );
 
 $loop->add( $tka );
 
 $loop->loop_forever;

=head1 DESCRIPTION

This object class implements an asynchronous perl wrapper around the
C<libtermkey> library for handling terminal keypress events. This library
attempts to provide an abstract way to read keypress events in terminal-based
programs by providing structures that describe keys, rather than simply
returning raw bytes as read from the TTY device.

This class is a subclass of C<IO::Async::Notifier>, allowing it to be put in
an C<IO::Async::Loop> object and used alongside other objects in an
C<IO::Async> program.

This object internally uses an instance of L<Term::TermKey> to access the
underlying C library. For details on general operation, including the
representation of keypress events as objects, see the documentation on that
class.

For implementation reasons, this class is not actually a subclass of
C<Term::TermKey>. Instead, an object of that class is stored and accessed by
this object, which is a subclass of C<IO::Async::Notifier>. This distinction
should not normally be noticable. Proxy methods exist for the normal accessors
of C<Term::TermKey>, and the usual behaviour of the C<getkey()> or other
methods is instead replaced by the C<on_key> callback or method.

This object may be used in one of two ways; with a callback function, or as a
base class.

=head2 Callbacks

This object may take a CODE reference to a callback function in its
constructor:

 $on_key->( $self, $key )

The C<$key> parameter will contain an instance of C<Term::TermKey::Key>
representing the keypress event.

=head2 Base Class

Alternatively, a subclass of this class may be built which handles the
following method:

 $self->on_key( $key )

The C<$key> parameter will contain an instance of C<Term::TermKey::Key>
representing the keypress event.

=cut

# Forward any requests for symbol imports on to Term::TermKey
sub import {
   shift; unshift @_, "Term::TermKey";
   my $import = $_[0]->can( "import" );
   goto &$import; # So as not to have to fiddle with Sub::UpLevel
}

=head1 CONSTRUCTOR

=cut

=head2 $tka = Term::TermKey::Async->new( %args )

This function returns a new instance of a C<Term::TermKey::Async> object. It
takes the following named arguments:

=over 8

=item term => IO or INT

Optional. File handle or POSIX file descriptor number for the file handle to
use as the connection to the terminal. If not supplied C<STDIN> will be used.

=item on_key => CODE

Callback to invoke when a key is pressed.

=back

=cut

sub new
{
   my $class = shift;
   my %args = @_;

   # TODO: Find a better algorithm to hunt my terminal
   my $term = $args{term} || \*STDIN;

   my $on_key = $args{on_key} || $class->can( "on_key" )
      or croak "Expected 'on_key' or to be a class that can ->on_key";

   my $termkey = Term::TermKey->new( $term, $args{flags} );
   if( !defined $termkey ) {
      croak "Cannot construct a termkey instance\n";
   }

   my $self = $class->SUPER::new(
      read_handle => $term,
   );

   $self->{termkey} = $termkey;
   $self->{timerid} = undef;

   $self->{on_key} = $on_key;

   return $self;
}

# For IO::Async::Notifier
sub on_read_ready
{
   my $self = shift;

   my $loop = $self->get_loop;

   if( defined $self->{timerid} ) {
      $loop->cancel_timer( $self->{timerid} );
      undef $self->{timerid};
   }

   my $termkey = $self->{termkey};
   my $on_key = $self->{on_key};

   return unless $termkey->advisereadable == RES_AGAIN;

   my $key = Term::TermKey::Key->new();

   my $ret;
   while( ( $ret = $termkey->getkey( $key ) ) == RES_KEY ) {
      $on_key->( $self, $key );
   }

   if( $ret == RES_AGAIN ) {
      $self->{timerid} = $loop->enqueue_timer(
         delay => $termkey->get_waittime / 1000,
         code => sub {
            if( $termkey->getkey_force( $key ) == RES_KEY ) {
               $on_key->( $self, $key );
            }
            undef $self->{timerid};
         },
      );
   }
   elsif( $ret == RES_EOF ) {
      $self->close;
   }
}

=head1 METHODS

=cut

=head2 $tk = $tka->termkey

Returns the C<Term::TermKey> object being used to access the C<libtermkey>
library. Normally should not be required; the proxy methods should be used
instead. See below.

=cut

sub termkey
{
   my $self = shift;
   return $self->{termkey};
}

=head2 $flags = $tka->get_flags

=head2 $tka->set_flags( $flags )

=head2 $msec = $tka->get_waittime

=head2 $tka->set_waittime( $msec )

=head2 $str = $tka->get_keyname( $sym )

=head2 $str = $tka->format_key( $key, $format )

These methods all proxy to the C<Term::TermKey> object, and allow transparent
use of the C<Term::TermKey::Async> object as if it was a subclass.
Their arguments, behaviour and return value are therefore those provided by
that class. For more detail, see the L<Term::TermKey> documentation.

=cut

# Proxy methods for normal Term::TermKey access
foreach my $method (qw(
   get_flags
   set_flags
   get_waittime
   set_waittime
   get_keyname
   format_key
)) {
   no strict 'refs';
   *{$method} = sub {
      my $self = shift;
      $self->termkey->$method( @_ );
   };
}

# Keep perl happy; keep Britain tidy
1;

__END__

=head1 AUTHOR

Paul Evans E<lt>leonerd@leonerd.org.ukE<gt>
