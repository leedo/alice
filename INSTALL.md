#Installing Alice's dependencies from the CPAN

Alice has a number of dependencies, all of which can be installed
from the CPAN. The simplest way to get these installed is with the
`cpanm` tool.

You'll need a working C compiler and `make` to install some of the
dependencies. If you are on OS X, this means the Dev Tools must be
installed.

Install `cpanm` by running

    curl -L http://xrl.us/cpanm | perl - --sudo App::cpanminus

Check out alice's git repository

    git clone https://github.com/leedo/alice.git
    cd alice

Install alice's dependencies into a self-contained directory

    cpanm --local-lib extlib local::lib
    cpanm --local-lib extlib --installdeps --notest .
