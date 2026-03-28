FROM steamcmd/steamcmd:ubuntu-24

WORKDIR /desynced

RUN apt update \
 && apt install -y --no-install-recommends --no-install-suggests wine xvfb \
 && apt clean \
 && rm -rf /var/lib/apt/lists/*

COPY start.sh ./start.sh

ENTRYPOINT ["./start.sh"]