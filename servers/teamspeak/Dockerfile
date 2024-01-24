FROM ubuntu:18.04

RUN apt update && apt install -y wget

ADD ./install.sh /install.sh
ENTRYPOINT [ "/install.sh" ]