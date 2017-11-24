#!/bin/bash

## Test for single domain certificates.

set -e

# Create the $domains array from comma separated domains in TEST_DOMAINS.
IFS=',' read -r -a domains <<< "$TEST_DOMAINS"

# Run a separate nginx container for each domain in the $domains array.
# Start all the containers in a row so that docker-gen debounce timers fire only once.
for domain in "${domains[@]}"; do
  docker run --rm -d \
    --name "$domain" \
    -e "VIRTUAL_HOST=${domain}" \
    -e "VIRTUAL_PORT=80" \
    -e "LETSENCRYPT_HOST=${domain}" \
    -e "LETSENCRYPT_EMAIL=foo@bar.com" \
    nginx:alpine > /dev/null && echo "Started test web server for $domain"
done

for domain in "${domains[@]}"; do

  # Wait for a file at /etc/nginx/certs/$domain/cert.pem
  # then grab the certificate in text form from the file.
  wait_for_cert "$domain" "$LETSENCRYPT_CONTAINER_NAME"
  created_cert="$(docker exec "$LETSENCRYPT_CONTAINER_NAME" openssl x509 -in "/etc/nginx/certs/${domain}/cert.pem" -text -noout)"

  # Check if the domain is on the certificate.
  if grep -q "$domain" <<< "$created_cert"; then
    echo "Domain $domain is on certificate."
  else
    echo "Domain $domain isn't on certificate."
    exit 1
  fi

  # Wait for a connection to https://domain then grab the served certificate in text form.
  wait_for_conn "$domain"
  served_cert="$(echo \
    | openssl s_client -showcerts -servername "$domain" -connect "$domain:443" 2>/dev/null \
    | openssl x509 -inform pem -text -noout)"

  # Compare the cert on file and what we got from the https connection, if not identical, display a diff.
  if [ "$created_cert" != "$served_cert" ]; then
    echo "Nginx served an incorrect certificate for $domain."
    diff -u <"$(echo "$created_cert")" <"$(echo "$served_cert")"
    exit 1
  else
    echo "The correct certificate for $domain was served by Nginx."
  fi

  # Stop the Nginx container silently.
  docker stop "$domain" > /dev/null
done

# Cleanup the files created by this run of the test to avoid foiling following test(s).
docker exec "$LETSENCRYPT_CONTAINER_NAME" sh -c 'rm -rf /etc/nginx/certs/le?.wtf*'
