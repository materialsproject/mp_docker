FROM ubuntu:16.04

RUN apt-get update -y && \
  apt-get install -y apt-utils python wget bzip2 dialog apache2 apache2-dev \
  git vim gcc nodejs npm sudo

# Conda
WORKDIR /root
RUN wget -q \
  https://repo.continuum.io/miniconda/Miniconda2-latest-Linux-x86_64.sh \
  && bash ./Miniconda2-latest-Linux-x86_64.sh -f -b -p /opt/anaconda2

RUN /opt/anaconda2/bin/conda update -y conda
RUN /opt/anaconda2/bin/conda install -y --channel matsci pymatgen pyhull pybtex


## Mimic cori "dwinston" user for apache
ARG UID=62983
RUN adduser --disabled-password --gecos '' --shell /usr/sbin/nologin --home /var/www --uid $UID www-matgen
RUN sed --in-place s/APACHE_RUN_USER=www-data/APACHE_RUN_USER=www-matgen/g /etc/apache2/envvars


COPY materials_django /var/www/materials_django
COPY pymatpro /var/www/pymatpro

# Mods to OS
RUN mkdir /var/www/static/ && \
	chown -R www-matgen /var/www/materials_django && \
	chown -R www-matgen /var/www/static && \
	chown www-matgen /var/log/apache2 && \
    ln -s /var/log/apache2 /var/log/httpd && \
    ln -s /usr/bin/nodejs /usr/local/bin/node

# Pymatpro
WORKDIR /var/www/pymatpro
RUN /opt/anaconda2/bin/python setup.py install


WORKDIR /var/www/materials_django
#### TODO: Comment out lines in requirements.txt or convert to conda
RUN /opt/anaconda2/bin/pip install -r requirements.txt
RUN /opt/anaconda2/bin/pip install mod_wsgi

# Setup Matplotlib backend
RUN mkdir -p /var/www/.config/matplotlib/ && \
	mkdir -p /root/.config/matplotlib/ && \
	echo "backend: Agg" > /var/www/.config/matplotlib/matplotlibrc && \
	echo "backend: Agg" > /root/.config/matplotlib/matplotlibrc && \
	chown -R www-matgen /var/www/.config/matplotlib


RUN npm install -g grunt-cli && npm cache clean && npm install && grunt compile

USER www-matgen
RUN /opt/anaconda2/bin/python manage.py makemigrations && \
	/opt/anaconda2/bin/python manage.py migrate && \
	/opt/anaconda2/bin/python manage.py init_sandboxes configs/sandboxes.yaml && \
	/opt/anaconda2/bin/python manage.py load_db_config configs/*_db_*.yaml && \
	/opt/anaconda2/bin/python manage.py collectstatic --noinput

USER root

RUN chown -R www-matgen materials_django

# Apache
RUN a2enmod proxy proxy_http deflate rewrite headers

COPY apache/wsgi.conf /etc/apache2/sites-available/wsgi.conf
RUN a2ensite wsgi

ENV LD_LIBRARY_PATH=/opt/anaconda2/lib
# If dev, build with `--build-arg PRODUCTION=0`
ARG PRODUCTION=1
ENV PRODUCTION=$PRODUCTION
# build with 0 for no SSL check
ARG SSL_TERMINATION=1
ENV SSL_TERMINATION=$SSL_TERMINATION




CMD ["apachectl", "-DFOREGROUND"]

####### Mongo
#
# RUN apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv EA312927
# RUN echo \
#   "deb http://repo.mongodb.org/apt/ubuntu xenial/mongodb-org/3.2 multiverse" \
#   | tee /etc/apt/sources.list.d/mongodb-org-3.2.list
# RUN apt-get update && apt-get install -y mongodb-org


###################  WIKI and MySQL stuff
#
# RUN apt-get update -y && \
#	    apt-get install -y mysql-server php libapache2-mod-php php-xml php-mbstring
#
#### TODO: copy wiki.conf
# RUN a2ensite wiki
