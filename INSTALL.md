#Installing Alice's dependencies from the CPAN

Alice has a number of dependencies, all of which can be installed
from the CPAN. The simplest way to get these installed is with the
`cpanm` tool.

Install the `cpanm` by running

    curl -L http://cpanmin.us | perl - --sudo App::cpanminus

Install alice's dependencies with the following command

    cpanm --sudo --installdeps App::Alice

If you want to install alice from CPAN just omit the `--installdeps`
option.

If you are in a hurry you can use the --notest option, but don't
tell anyone!
