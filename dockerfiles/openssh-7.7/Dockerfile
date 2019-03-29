FROM alpine:3.8

# Check on 
# https://pkgs.alpinelinux.org/packages?name=openssh&branch=v3.8
ARG OPENSSH_VERSION="7.7_p1-r4"

RUN apk --no-cache add \
      openssh=${OPENSSH_VERSION}

COPY uid_entrypoint /usr/local/bin
RUN chgrp 0 /etc/passwd && chmod g+rw /etc/passwd && \
  chgrp 0 /usr/local/bin/uid_entrypoint && chmod g+rx /usr/local/bin/uid_entrypoint

ENTRYPOINT [ "uid_entrypoint" ]

USER 1001