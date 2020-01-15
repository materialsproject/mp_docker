FROM python:3.7-slim
RUN set -ex \
    && RUN_DEPS="libpcre3 mime-support software-properties-common git curl apt-utils vim" \
    && seq 1 8 | xargs -I{} mkdir -p /usr/share/man/man{} \
    && apt-get update && apt-get install -y --no-install-recommends $RUN_DEPS \
    && curl -sL https://deb.nodesource.com/setup_10.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

# requirements
COPY materials_django/requirements.txt requirements-django.txt
COPY pymatpro/requirements.txt requirements-pymatpro.txt
RUN cat requirements-*.txt > requirements.txt

ENV PATH="/venv/bin:${PATH}"
COPY pymatpro /pymatpro

RUN set -ex \
    && BUILD_DEPS="build-essential gcc cmake libpcre3-dev libpq-dev libxml2-dev" \
    && apt-get update && apt-get install -y --no-install-recommends $BUILD_DEPS \
    && python3.7 -m venv /venv \
    && pip install -U pip && pip install --no-cache numpy \
    && pip install --no-cache-dir -r /requirements.txt \
    && git clone https://github.com/openbabel/openbabel.git \
    && cd openbabel && git checkout c9c500388dac1469364f778f4f4aa3a6ff7cc7c5 \
    && mkdir /openbabel-build && cd /openbabel-build && cmake /openbabel && make -j4 && make install \
    && cd /pymatpro && pip install --no-cache -e . \
    && apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false $BUILD_DEPS \
    && rm -rf /var/lib/apt/lists/*

EXPOSE 8080
ENV PYTHONUNBUFFERED 1
ENV PRODUCTION 0
ENV SSL_TERMINATION 0
ENV DJANGO_SETTINGS_MODULE=materials_django.settings

WORKDIR /app

COPY materials_django/package.json .
RUN npm install --unsafe-perm -g npm@latest grunt-cli npm install --unsafe-perm && npm cache clean -f

COPY materials_django/* /app/
#RUN grunt compile && \
RUN python manage.py makemigrations && \
    python manage.py migrate && \
    python manage.py init_sandboxes configs/sandboxes.yaml && \
    python manage.py load_db_config configs/*_db_*.yaml && \
    #python manage.py shell < dev_scripts/add_test_models.py
    # && sh dev_scripts/load_prod_as_dev.sh && \
    #python manage.py collectstatic --noinput && echo "DONE"

COPY docker-entrypoint.sh .
ENTRYPOINT ["/app/docker-entrypoint.sh"]
CMD ["python", "manage.py", "runserver", "0.0.0.0:8080"]
