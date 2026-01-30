FROM debian:trixie-slim

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV TZ=Europe/Zurich
ENV SHIBBOLETH_VERSION=3.4

# Update repositories & install additional packages
# Custom Apache2 repo not feasible: libapache2-mod-shib requires Debian's Apache2 binary compatibility
RUN apt-get update && apt-get install -y \
    apache2 \
    curl \
    supervisor \
    ca-certificates \
    locales \
    tzdata \
    libapache2-mod-shib \
    shibboleth-sp-common \
    shibboleth-sp-utils \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Generate and set locale
RUN echo "en_US.UTF-8 UTF-8" > /etc/locale.gen && \
    locale-gen en_US.UTF-8 && \
    update-locale LANG=en_US.UTF-8

# Set timezone
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# Enable Apache modules (proxy for reverse proxy mode)
RUN a2enmod rewrite ssl shib remoteip proxy proxy_http proxy_fcgi headers

# Configure RemoteIP for proxy support
RUN { \
    echo RemoteIPHeader X-Real-IP ; \
    echo RemoteIPTrustedProxy 10.0.0.0/8 ; \
    echo RemoteIPTrustedProxy 172.16.0.0/12 ; \
    echo RemoteIPTrustedProxy 192.168.0.0/16 ; \
    } > /etc/apache2/conf-available/remoteip.conf; \
    a2enconf remoteip

# Generate Shibboleth configuration files from SWITCH
RUN curl --output /etc/shibboleth/shibboleth2.xml \
    "https://help.switch.ch/aai/docs/shibboleth/SWITCH/$SHIBBOLETH_VERSION/sp/deployment/download/customize.php/shibboleth2.xml?osType=nonwindows&hostname=__HOSTNAME__&targetURL=__TARGET_URL__&keyPath=%2Fvar%2Flib%2Fshibboleth%2Fsp-key.pem&certPath=%2Fvar%2Flib%2Fshibboleth%2Fsp-cert.pem&federation=SWITCHaai&supportEmail=__CONTACT__&wayfURL=https%3A%2F%2Fwayf.switch.ch%2FSWITCHaai%2FWAYF&metadataURL=http%3A%2F%2Fmetadata.aai.switch.ch%2Fmetadata.switchaai%2Bidp.xml&metadataFile=metadata.switchaai%2Bidp.xml&eduIDEntityID=https%3A%2F%2Feduid.ch%2Fidp%2Fshibboleth&hide=windows-only,metadataattributespart1,metadataattributespart2,eduid-only,interfederation,"

RUN curl --output /etc/shibboleth/attribute-map.xml \
    "https://help.switch.ch/aai/docs/shibboleth/SWITCH/$SHIBBOLETH_VERSION/sp/deployment/download/customize.php/attribute-map.xml?osType=nonwindows&hide=eduid-only,"

RUN curl --output /etc/shibboleth/attribute-policy.xml \
    "https://help.switch.ch/aai/docs/shibboleth/SWITCH/$SHIBBOLETH_VERSION/sp/deployment/download/customize.php/attribute-policy.xml?osType=nonwindows&hide="

RUN curl --output /etc/shibboleth/SWITCHaaiRootCA.crt.pem \
    https://ca.aai.switch.ch/SWITCHaaiRootCA.crt.pem

# Set handlerSSL to false in Shibboleth configuration file
# https://shibboleth.atlassian.net/wiki/spaces/SHIB2/pages/2577072242/SPReverseProxy
RUN sed -i "s|handlerSSL=\"true\"|handlerSSL=\"false\"|g" "/etc/shibboleth/shibboleth2.xml"

# Create non-root user for running services
# Add dockeruser to _shibd group so shibd daemon can access necessary files
RUN groupadd -r dockeruser --gid=1000 && \
    useradd -r -g dockeruser --uid=1000 --groups=_shibd --home-dir=/var/www/html --shell=/sbin/nologin dockeruser

# Create directories and adjust ownership
RUN mkdir -p /var/lib/shibboleth/ /run/shibboleth/ /run/supervisor/ /etc/apache2/vhost.d/ /var/log/supervisor/ && \
    chown -R dockeruser:dockeruser /var/lib/shibboleth/ /run/shibboleth/ /run/supervisor/ /etc/apache2/vhost.d/ && \
    chown -R dockeruser:dockeruser /var/www/html && \
    chown -R dockeruser:dockeruser /var/log/apache2/ && \
    chown -R dockeruser:dockeruser /var/log/supervisor/ && \
    chown -R dockeruser:dockeruser /var/run/apache2/ && \
    chown -R dockeruser:dockeruser /etc/apache2/sites-available/ && \
    chmod -R g+r /etc/shibboleth/ && \
    chown -R dockeruser:_shibd /etc/shibboleth/

# Copy configuration files
COPY config/vhost.conf /etc/apache2/sites-available/000-default.conf
COPY config/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# Copy the entrypoint script
COPY scripts/entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# Set ownership after copying files
RUN chown dockeruser:dockeruser /etc/apache2/sites-available/000-default.conf && \
    chown dockeruser:dockeruser /usr/local/bin/docker-entrypoint.sh

WORKDIR /var/www/html

EXPOSE 8080

USER dockeruser

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
