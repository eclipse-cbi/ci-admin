FROM alpine:3.8

# Check on 
# https://pkgs.alpinelinux.org/packages?name=gnupg&branch=v3.8
ARG GNUPG_VERSION="2.2.8-r0"

RUN apk --no-cache add \
      gnupg=${GNUPG_VERSION}

COPY gpg_wrapper.sh /usr/local/bin/gpg_wrapper.sh
RUN chmod ug+x /usr/local/bin/gpg_wrapper.sh && \
    chgrp 0 /usr/local/bin/gpg_wrapper.sh
ENTRYPOINT [ "gpg_wrapper.sh" ]

ENV HOMEDIR="/run/gnupg"

USER 1001