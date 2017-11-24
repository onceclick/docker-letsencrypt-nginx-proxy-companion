#!/bin/bash

## Test for SAN (Subject Alternative Names) certificates.

set -e

# Create the $domains array from comma separated domains in TEST_DOMAINS.
IFS=',' read -r -a domains <<< "$TEST_DOMAINS"

# Create three different comma separated list from the first three domains in $domains.
# testing for regression on spaced lists https://github.com/JrCs/docker-letsencrypt-nginx-proxy-companion/issues/288
# and with trailing comma https://github.com/JrCs/docker-letsencrypt-nginx-proxy-companion/issues/254
letsencrypt_hosts=( \
  [0]="${domains[0]},${domains[1]},${domains[2]}" \     #straight comma separated list
  [1]="${domains[1]}, ${domains[2]}, ${domains[0]}" \   #comma separated list with spaces
  [2]="${domains[2]}, ${domains[0]}, ${domains[1]}," )  #comma separated list with spaces and a trailing comma

i=1

for hosts in "${letsencrypt_hosts[@]}"; do

  # Get the base domain (first domain of the list).
  base_domain="$(get_base_domain "$hosts")"
  container="test$i"

  # Run an Nginx container passing one of the comma separated list as LETSENCRYPT_HOST env var.
  docker run --rm -d \
    --name "$container" \
    -e "VIRTUAL_HOST=${TEST_DOMAINS}" \
    -e "VIRTUAL_PORT=80" \
    -e "LETSENCRYPT_HOST=${hosts}" \
    -e "LETSENCRYPT_EMAIL=foo@bar.com" \
    nginx:alpine > /dev/null && echo "Started test web server with LETSENCRYPT_HOST=$hosts"

  # Wait for a file at /etc/nginx/certs/$base_domain/cert.pem
  # then grab the certificate in text form from the file.
  wait_for_cert $base_domain $LETSENCRYPT_CONTAINER_NAME
  created_cert="$(docker exec $LETSENCRYPT_CONTAINER_NAME openssl x509 -in /etc/nginx/certs/${base_domain}/cert.pem -text -noout)"

  for domain in "${domains[@]}"; do
  ## For all the domains in the $domains array ...

    # Check if the domain is on the certificate.
    if grep -q "$domain" <<< "$created_cert"; then
      echo "$domain is on certificate."
    else
      echo "$domain did not appear on certificate."
      exit 1
    fi

    # Wait for a connection to https://domain then grab the served certificate in text form.
    wait_for_conn $domain
    served_cert="$(echo \
      | openssl s_client -showcerts -servername $domain -connect $domain:443 2>/dev/null \
      | openssl x509 -inform pem -text -noout)"

    # Compare the cert on file and what we got from the https connection, if not identical, display a diff.
    if [ "$created_cert" != "$served_cert" ]; then
      echo "Nginx served an incorrect certificate for $domain."
      diff -u <"$(echo "$created_cert")" <"$(echo "$served_cert")"
      exit 1
    else
      echo "The correct certificate for $domain was served by Nginx."
    fi
  done

  # Stop the Nginx container silently.
  docker stop $container > /dev/null
  # Cleanup the files created by this run of the test to avoid foiling following test(s).
  docker exec $LETSENCRYPT_CONTAINER_NAME sh -c 'rm -rf /etc/nginx/certs/le?.wtf*'
  i=$(( $i + 1 ))

done
