FROM debian:stretch-slim

ENV BUILD_DEPS build-essential zlib1g-dev liblz4-dev libssl-dev libsasl2-dev wget python cmake libcurl4-openssl-dev pkg-config ca-certificates

RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends $BUILD_DEPS $RUN_DEPS

COPY . /usr/src/kafkacat

RUN cd /usr/src/kafkacat && \
  rm -rf tmp-bootstrap && \
  echo "Source versions:" && \
  grep ^github_download ./bootstrap.sh && \
  ./bootstrap.sh && \
  mv kafkacat /usr/bin/

RUN rm -rf /usr/src/kafkacat; \
  apt-get purge -y --auto-remove $BUILD_DEPS ; \
  apt-get clean -y ; \
  apt-get autoclean -y ; \
  rm /var/log/dpkg.log /var/log/alternatives.log /var/log/apt/*.log; \
  rm -rf /var/lib/apt/lists/*

FROM debian:stretch-slim

ENV RUN_DEPS libssl1.1 libsasl2-2 ca-certificates

RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends $RUN_DEPS

COPY --from=0 /usr/bin/kafkacat /usr/bin/kafkacat

RUN kafkacat -V

ENTRYPOINT ["kafkacat"]
