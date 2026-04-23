FROM steamcmd/steamcmd:ubuntu-24

ENV DEBIAN_FRONTEND=noninteractive

RUN apt update \
 && apt install -y --no-install-recommends --no-install-suggests \
    bash \
    wine \
    xvfb \
    xauth \
    procps \
 && apt clean \
 && rm -rf /var/lib/apt/lists/*

COPY start.sh /start.sh

RUN chmod +x /start.sh

WORKDIR /root

ENTRYPOINT ["/start.sh"]
