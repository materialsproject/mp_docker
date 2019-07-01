FROM docker.elastic.co/beats/filebeat:7.2.0

USER root
COPY filebeat.yml /run/secrets/filebeat-conf
RUN rm /usr/share/filebeat/filebeat.yml
RUN ln -s /run/secrets/filebeat-conf /usr/share/filebeat/filebeat.yml
RUN chown filebeat:filebeat /usr/share/filebeat/filebeat.yml

USER filebeat
RUN filebeat modules enable apache
CMD ["filebeat -e"]
