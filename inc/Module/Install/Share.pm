#line 1
package Module::Install::Share;

use strict;
use Module::Install::Base ();

use vars qw{$VERSION @ISA $ISCORE};
BEGIN {
	$VERSION = '0.91';
	@ISA     = 'Module::Install::Base';
	$ISCORE  = 1;
}

sub install_share {
	my $self = shift;
	my $dir  = @_ ? pop   : 'share';
	my $type = @_ ? shift : 'dist';
	unless ( defined $type and $type eq 'module' or $type eq 'dist' ) {
		die "Illegal or invalid share dir type '$type'";
	}
	unless ( defined $dir and -d $dir ) {
		die "Illegal or missing directory install_share param";
	}

	# Split by type
	my $S = ($^O eq 'MSWin32') ? "\\" : "\/";
	if ( $type eq 'dist' ) {
		die "Too many parameters to install_share" if @_;

		# Set up the install
		$self->postamble(<<"END_MAKEFILE");
config ::
\t\$(NOECHO) \$(MOD_INSTALL) \\
\t\t"$dir" \$(INST_LIB)${S}auto${S}share${S}dist${S}\$(DISTNAME)

END_MAKEFILE
	} else {
		my $module = Module::Install::_CLASS($_[0]);
		unless ( defined $module ) {
			die "Missing or invalid module name '$_[0]'";
		}
		$module =~ s/::/-/g;

		# Set up the install
		$self->postamble(<<"END_MAKEFILE");
config ::
\t\$(NOECHO) \$(MOD_INSTALL) \\
\t\t"$dir" \$(INST_LIB)${S}auto${S}share${S}module${S}$module

END_MAKEFILE
	}

	# The above appears to behave incorrectly when used with old versions
	# of ExtUtils::Install (known-bad on RHEL 3, with 5.8.0)
	# So when we need to install a share directory, make sure we add a
	# dependency on a moderately new version of ExtUtils::MakeMaker.
	$self->build_requires( 'ExtUtils::MakeMaker' => '6.11' );

	# 99% of the time we don't want to index a shared dir
	$self->no_index( directory => $dir );
}

1;

__END__

#line 125
