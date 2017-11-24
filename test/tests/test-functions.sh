#!/bin/bash

set -e

# Get the first domain of a comma separated list.
get_base_domain() {
  awk -F ',' '{print $1}' <(echo ${1:?}) | tr -d ' '
}
export -f get_base_domain

# Wait for the /etc/nginx/certs/dhparam.pem file to exist in container $1
wait_for_dhparam() {
  local i=0
  sleep 1
  echo -n "Waiting for the ${1:?} container to generate a DH parameters file, this might take a while..."
  until docker exec ${1:?} [ -f /etc/nginx/certs/dhparam.pem ]; do
    if [ $i -gt 600 ]; then
      echo "DH parameters file was not generated under ten minutes by the ${1:?} container, timing out."
      exit 1
    fi
    i=$((i + 5))
    sleep 5
  done
  echo "Done."
}
export -f wait_for_dhparam

# Wait for the /etc/nginx/certs/$1/cert.pem file to exist inside container $2
wait_for_cert() {
  local i=0
  until docker exec ${2:?} [ -f /etc/nginx/certs/${1:?}/cert.pem ]; do
    if [ $i -gt 60 ]; then
      echo "Certificate for ${1:?} was not generated under one minute, timing out."
      return 1
    fi
    i=$((i + 2))
    sleep 2
  done
  echo "Certificate for ${1:?} has been generated."
}
export -f wait_for_cert

# Wait for a successful https connection to domain $1
wait_for_conn() {
  local i=0
  until curl -k https://${1:?} > /dev/null 2>&1; do
    if [ $i -gt 60 ]; then
      echo "Could not connect to ${1:?} using https under one minute, timing out."
      return 1
    fi
    i=$((i + 2))
    sleep 2
  done
  echo "Connection to ${1:?} using https was successful."
}
export -f wait_for_conn
