FROM steamcmd/steamcmd:ubuntu-24

ENV DEBIAN_FRONTEND=noninteractive

RUN apt update \
 && apt install -y --no-install-recommends --no-install-suggests \
    bash \
    ca-certificates \
    procps \
    python3 \
    wine \
    xauth \
    xvfb \
 && apt clean \
 && rm -rf /var/lib/apt/lists/*

COPY start.sh /start.sh
COPY bootstrap.py /bootstrap.py

RUN chmod +x /start.sh

WORKDIR /data/server

ENTRYPOINT ["/start.sh"]
