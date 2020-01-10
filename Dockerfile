FROM ubuntu:16.04

RUN apt-get update -y && \
  apt-get install -y apt-utils python wget bzip2 dialog apache2 apache2-dev \
  git vim gcc nodejs npm sudo cmake libxml2-dev libmysqlclient-dev \
  && rm -rf /var/lib/apt/lists/*

# Mimic cori "mkhorton" user for apache
ARG UID=72748
RUN adduser --disabled-password --gecos '' --shell /usr/sbin/nologin --home /var/www --uid $UID www-matgen
RUN sed --in-place s/APACHE_RUN_USER=www-data/APACHE_RUN_USER=www-matgen/g /etc/apache2/envvars

# Conda
WORKDIR /root
RUN wget -q \
  https://repo.continuum.io/miniconda/Miniconda3-4.5.4-Linux-x86_64.sh && \
  bash ./Miniconda3-4.5.4-Linux-x86_64.sh -f -b -p /opt/miniconda3

RUN /opt/miniconda3/bin/conda update -y conda && \
    /opt/miniconda3/bin/conda create -y -n mpprod3 python=3.6 && \
    /opt/miniconda3/bin/pip install --no-cache mod_wsgi && \
    /opt/miniconda3/bin/conda clean -afy

ENV PATH /opt/miniconda3/envs/mpprod3/bin:$PATH

# openbabel
RUN git clone https://github.com/openbabel/openbabel.git /root/openbabel
WORKDIR /root/openbabel
RUN git checkout c9c500388dac1469364f778f4f4aa3a6ff7cc7c5 # Last commit before 2018-08-16
WORKDIR /root/openbabel-build
RUN cmake ../openbabel && make -j4 && make install

# npm
WORKDIR /var/www/python/matgen_prod/materials_django
COPY materials_django/package.json package.json
RUN npm install -g npm@latest grunt-cli && npm install

# requirements
COPY materials_django/requirements.txt requirements.txt
COPY pymatpro pymatpro
RUN pip install --no-cache -U pip && pip install --no-cache numpy && \
    pip install --no-cache -r requirements.txt && \
    cd pymatpro && pip install --no-cache -e .

COPY materials_django materials_django
RUN grunt compile

# Mods to OS
RUN mkdir /var/www/static/ && \
	chown -R www-matgen /var/www/python && \
	chown -R www-matgen /var/www/static && \
	chown www-matgen /var/log/apache2 && \
    ln -s /var/log/apache2 /var/log/httpd && \
    ln -s /usr/bin/nodejs /usr/local/bin/node

# Setup Matplotlib backend
RUN mkdir -p /var/www/.config/matplotlib/ && \
	mkdir -p /root/.config/matplotlib/ && \
	echo "backend: Agg" > /var/www/.config/matplotlib/matplotlibrc && \
	echo "backend: Agg" > /root/.config/matplotlib/matplotlibrc && \
	chown -R www-matgen /var/www/.config/matplotlib

# env and args
ARG PRODUCTION=0
ENV PRODUCTION=$PRODUCTION
ARG SSL_TERMINATION=0
ENV SSL_TERMINATION=$SSL_TERMINATION
ARG MP_USERDB_USER
ENV MP_USERDB_USER=$MP_USERDB_USER
ARG MP_USERDB_PASS
ENV MP_USERDB_PASS=$MP_USERDB_PASS
RUN echo $SSL_TERMINATION $PRODUCTION && echo $MP_USERDB_USER $MP_USERDB_PASS

USER www-matgen
RUN if [ $PRODUCTION -eq 0 ]; then python manage.py makemigrations && \
    python manage.py migrate && \
    python manage.py init_sandboxes configs/sandboxes.yaml && \
    python manage.py load_db_config configs/*_db_*.yaml && \
    python manage.py shell < dev_scripts/add_test_models.py && \
    sh dev_scripts/load_prod_as_dev.sh; fi

RUN python manage.py collectstatic --noinput

USER root
RUN chown -R www-matgen materials_django
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

RUN touch /var/log/apache2/django-perf.log && touch /var/log/apache2/django.log && chown -R www-matgen.www-matgen /var/log/apache2 /var/cache/apache2 /var/lock/apache2 /var/run/apache2
RUN echo "export HOSTNAME" >> /etc/apache2/envvars

COPY apache/apache2-foreground /usr/local/bin/
CMD ["apache2-foreground"]
