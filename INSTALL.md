Installing Alice's dependencies from the CPAN

Alice has a number of dependencies, all of which can be installed from CPAN. The
 quickest way to get these installed is listed below.

Install the `cpanminus` client by running

  curl -L http://cpanmin.us | perl - --sudo App::cpanminus

Install alice's dependencies with the following command

  cpanm --sudo --installdeps App::Alice
