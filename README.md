# mp_docker

Repo for building a materials_django docker image

To build

```
git clone git@github.com:materialsproject/mp_docker.git
cd mp_docker
git submodule init
git submodule update
docker build -t mp_docker .
```

Start by hand
```
docker run -it -p8888:80 mp_docker /bin/bash

## If prod turn uncomment PRODUCTION flag
# export PRODUCTION=1
export SSL_TERMINATION=1
export LD_LIBRARY_PATH=/opt/anaconda2/lib

## If you need to setup tunnel:
# ssh -f -N -L *:57003:mongodb03.nersc.gov:27017 -L *:57001:mongodb01.nersc.gov:27017 -L *:57004:mongodb04.nersc.gov:27017 <username>@matgen.nersc.gov

apachectl start

## Create superuser
## Follow instructions in MP docs

```

Autostart:
```
docker run -d -p8888:80 -e SSL_TERMINATION=1 -e LD_LIBRARY_PATH=/opt/anaconda2/lib mp_docker apachectl -DFOREGROUND
```