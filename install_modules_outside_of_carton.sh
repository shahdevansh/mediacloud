#!/bin/bash

working_dir=`dirname $0`

cd $working_dir

source ./script/set_perl_brew_environment.sh
perl -v
set -u
set -o  errexit

if [ `uname` == 'Darwin' ]; then

    # Mac OS X
    CPANM=/usr/local/bin/cpanm

else

    # assume Ubuntu
    CPANM=cpanm

fi

# FIXME Install ExtUtils::MakeMaker (a Carton dependency) separately
# without testing it because t/meta_convert.t fails on some machines
# (https://rt.cpan.org/Public/Bug/Display.html?id=85861)
$CPANM --notest ExtUtils::MakeMaker

<<<<<<< HEAD
$CPANM Carton~0.9.15
=======
$CPANM ./foreign_modules/carton-v0.9.15.tar.gz
>>>>>>> parent of b6c6c53... don't store Carton's tarball in the repository, pass the required version as a parameter to cpanm instead
$CPANM List::MoreUtils
$CPANM Devel::NYTProf
