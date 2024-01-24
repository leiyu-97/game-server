FROM steamcmd/steamcmd:ubuntu-18

EXPOSE 8211/udp

USER root
RUN apt update && apt install -y curl
ADD start.sh /start.sh
RUN chmod +x /start.sh
RUN groupadd steam && useradd steam -g root
RUN mkdir /palworld && mkdir /home/steam
RUN chown -R steam:root /palworld && chown -R steam:root /home/steam
USER steam
RUN mkdir /home/steam/.steam && cd /home/steam/.steam && curl -sqL 'https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz' | tar zxvf -
RUN ln -s /home/steam/.steam/linux64 /home/steam/.steam/sdk64 && ln -s /home/steam/.steam/linux32 /home/steam/.steam/sdk32
USER root

ENTRYPOINT ["/start.sh"]