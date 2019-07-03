FROM ubuntu:16.04

RUN apt-get update -y && \
  apt-get install -y apt-utils python wget bzip2 dialog apache2 apache2-dev \
  git vim gcc nodejs npm sudo cmake libxml2-dev libmysqlclient-dev 

# Conda
WORKDIR /root
RUN wget -q \
  https://repo.continuum.io/miniconda/Miniconda3-4.5.4-Linux-x86_64.sh && \
  bash ./Miniconda3-4.5.4-Linux-x86_64.sh -f -b -p /opt/miniconda3

RUN /opt/miniconda3/bin/conda update -y conda
RUN /opt/miniconda3/bin/conda create -y -n mpprod3 python=3.6
RUN /opt/miniconda3/bin/pip install mod_wsgi

# Set the PATH to use conda env
ENV PATH /opt/miniconda3/envs/mpprod3/bin:$PATH

RUN git clone https://github.com/openbabel/openbabel.git /root/openbabel
RUN mkdir openbabel-build
WORKDIR /root/openbabel
RUN git checkout c9c500388dac1469364f778f4f4aa3a6ff7cc7c5 # Last commit before 2018-08-16
WORKDIR /root/openbabel-build
RUN cmake ../openbabel && make -j4 && make install

RUN mkdir -p /var/www/python/matgen_prod


## Mimic cori "dwinston" user for apache
ARG UID=62983
RUN adduser --disabled-password --gecos '' --shell /usr/sbin/nologin --home /var/www --uid $UID www-matgen
RUN sed --in-place s/APACHE_RUN_USER=www-data/APACHE_RUN_USER=www-matgen/g /etc/apache2/envvars

WORKDIR /var/www/python/matgen_prod/materials_django
COPY materials_django/package.json /var/www/python/matgen_prod/materials_django/package.json
RUN npm install -g grunt-cli && npm install

COPY materials_django/requirements.txt /var/www/python/matgen_prod/materials_django/requirements.txt
COPY pymatpro /var/www/python/matgen_prod/pymatpro

# Mods to OS
RUN mkdir /var/www/static/ && \
	chown -R www-matgen /var/www/python && \
	chown -R www-matgen /var/www/static && \
	chown www-matgen /var/log/apache2 && \
    ln -s /var/log/apache2 /var/log/httpd && \
    ln -s /usr/bin/nodejs /usr/local/bin/node

WORKDIR /var/www/python/matgen_prod/materials_django
RUN pip install -U pip && \
       pip install numpy && \ 
       pip install -r requirements.txt

# Pymatpro
WORKDIR /var/www/python/matgen_prod/pymatpro
RUN pip install -e .

# Setup Matplotlib backend
RUN mkdir -p /var/www/.config/matplotlib/ && \
	mkdir -p /root/.config/matplotlib/ && \
	echo "backend: Agg" > /var/www/.config/matplotlib/matplotlibrc && \
	echo "backend: Agg" > /root/.config/matplotlib/matplotlibrc && \
	chown -R www-matgen /var/www/.config/matplotlib

WORKDIR /var/www/python/matgen_prod/materials_django
COPY materials_django /var/www/python/matgen_prod/materials_django
RUN chown -R www-matgen /var/www/python && grunt compile

USER www-matgen
# RUN python manage.py makemigrations && \
#	python manage.py migrate && \
#	python manage.py init_sandboxes configs/sandboxes.yaml && \
#	python manage.py load_db_config configs/*_db_*.yaml && \
RUN python manage.py collectstatic --noinput

USER root

RUN chown -R www-matgen materials_django

# Apache


RUN a2enmod proxy proxy_http deflate rewrite headers remoteip

RUN sed --in-place 's/Listen\ 80$/Listen\ 8080/g' /etc/apache2/ports.conf
RUN sed --in-place 's/<VirtualHost\ \*:80>/<VirtualHost\ \*:8080>/g' /etc/apache2/sites-available/000-default.conf
RUN sed --in-place 's/#ServerName www.example.com/ServerName materialsproject.org\n\tServerAlias www.materialsproject.org/g' /etc/apache2/sites-available/000-default.conf
RUN sed --in-place 's/ErrorLog/#ErrorLog/g' /etc/apache2/sites-available/000-default.conf
RUN sed --in-place 's/CustomLog/#CustomLog/g' /etc/apache2/sites-available/000-default.conf

RUN mkdir -p /run/secrets/

COPY apache/wsgi.conf /run/secrets/wsgi-conf
RUN ln -s /run/secrets/wsgi-conf /etc/apache2/sites-available/wsgi.conf
RUN a2ensite wsgi

COPY newrelic.ini /run/secrets/newrelic-ini
RUN ln -s /run/secrets/newrelic-ini /var/www/python/matgen_prod/newrelic.ini

COPY materials_django/materials_django/wsgi.py /run/secrets/wsgi-py
COPY materials_django/materials_django/settings.py /run/secrets/settings-py
RUN rm materials_django/wsgi.py && \
    ln -s /run/secrets/wsgi-py materials_django/wsgi.py && \
    rm materials_django/settings.py && \
    ln -s /run/secrets/settings-py materials_django/settings.py && \
    chown -R www-matgen /var/www/python

ENV LD_LIBRARY_PATH=/opt/miniconda3/lib
# If dev, build with `--build-arg PRODUCTION=0`
ARG PRODUCTION=1
ENV PRODUCTION=$PRODUCTION
# build with 0 for no SSL check
ARG SSL_TERMINATION=1
ENV SSL_TERMINATION=$SSL_TERMINATION

RUN touch /var/log/apache2/django-perf.log && touch /var/log/apache2/django.log && chown -R www-matgen.www-matgen /var/log/apache2 /var/cache/apache2 /var/lock/apache2 /var/run/apache2
RUN echo "export HOSTNAME" >> /etc/apache2/envvars

COPY apache/apache2-foreground /usr/local/bin/
CMD ["apache2-foreground"]
# CMD ["apachectl", "-DFOREGROUND"]

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
