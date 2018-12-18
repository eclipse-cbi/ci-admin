#!/usr/bin/env sh

chmod 700 "${HOMEDIR}"

if [ ! -f "${HOMEDIR}/gpg-agent.conf" ]; then
  echo "allow-loopback-pinentry" > "${HOMEDIR}/gpg-agent.conf"
fi

exec gpg --homedir ${HOMEDIR} "$@"