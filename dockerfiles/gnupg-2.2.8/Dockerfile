FROM alpine:3.8

# Check on 
# https://pkgs.alpinelinux.org/packages?name=gnupg&branch=v3.8
ARG GNUPG_VERSION="2.2.8-r0"

RUN apk --no-cache add \
      gnupg=${GNUPG_VERSION} \
    && adduser -D -u 1001 gnupggen

USER 1001