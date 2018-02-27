FROM ubuntu:16.04
 
RUN apt-get update -y && \
        apt-get install -y apt-utils python wget bzip2 apt-utils dialog apache2 apache2-dev git vim gcc nodejs npm sudo
 


# Mongo
RUN apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv EA312927
RUN echo "deb http://repo.mongodb.org/apt/ubuntu xenial/mongodb-org/3.2 multiverse" | tee /etc/apt/sources.list.d/mongodb-org-3.2.list
RUN apt-get update && apt-get install -y mongodb-org


# Conda
WORKDIR /root 
RUN wget -q https://repo.continuum.io/miniconda/Miniconda2-latest-Linux-x86_64.sh && \
        bash ./Miniconda2-latest-Linux-x86_64.sh -f -b -p /opt/anaconda2

RUN /opt/anaconda2/bin/conda update -y conda
RUN /opt/anaconda2/bin/conda install -y --channel matsci pymatgen pyhull pybtex


COPY materials_django /var/www/materials_django
COPY pymatpro /var/www/pymatpro

# Mods to OS
RUN chown -R www-data /var/www/materials_django && \
	mkdir /var/www/static/ && \
    ln -s /var/log/apache2 /var/log/httpd && \
    ln -s /usr/bin/nodejs /usr/local/bin/node

# Pymatpro
WORKDIR /var/www/pymatpro
RUN /opt/anaconda2/bin/python setup.py install


WORKDIR /var/www/materials_django
#### TODO: Comment out lines in requirements.txt or convert to conda
RUN /opt/anaconda2/bin/pip install -r requirements.txt
RUN /opt/anaconda2/bin/pip install -e git://github.com/materialsproject/gbml#egg=gbml
RUN /opt/anaconda2/bin/pip install mod_wsgi funcy unidecode dicttoxml

# Setup Matplotlib backend
RUN mkdir -p /var/www/.config/matplotlib/ && \
	echo "backend: Agg" > /var/www/.config/matplotlib/matplotlibrc && \
	chown -R www-data /var/www/.config/matplotlib




RUN /opt/anaconda2/bin/python manage.py makemigrations && /opt/anaconda2/bin/python manage.py migrate
RUN npm install -g grunt-cli && npm cache clean && npm install && grunt compile


# Apache
RUN a2enmod proxy proxy_http deflate rewrite headers

COPY apache/wsgi.conf /etc/apache2/sites-available/wsgi.conf
RUN a2ensite wsgi




###################  WIKI and MySQL stuff
#
# RUN apt-get update -y && \
#	    apt-get install -y mysql-server php libapache2-mod-php php-xml php-mbstring
#
#### TODO: copy wiki.conf
# RUN a2ensite wiki
