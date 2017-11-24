#!/bin/bash

set -e

boulder_ip="$(ifconfig docker0 | grep "inet addr:" | cut -d: -f2 | awk '{ print $1}')"

# shellcheck source=../tests/test-functions.sh
source ${TRAVIS_BUILD_DIR}/test/tests/test-functions.sh

case $SETUP in

  2containers)
    docker run -d -p 80:80 -p 443:443 \
      --name $NGINX_CONTAINER_NAME \
      -v /etc/nginx/vhost.d \
      -v /usr/share/nginx/html \
      -v /var/run/docker.sock:/tmp/docker.sock:ro \
      jwilder/nginx-proxy

    docker run -d \
      --name $LETSENCRYPT_CONTAINER_NAME \
      --volumes-from $NGINX_CONTAINER_NAME \
      -v /var/run/docker.sock:/var/run/docker.sock:ro \
      --add-host boulder:$boulder_ip \
      -e "DEBUG=true" \
      -e "ACME_CA_URI=http://${boulder_ip}:4000/directory" \
      -e "ACME_TOS_HASH=b16e15764b8bc06c5c3f9f19bc8b99fa48e7894aa5a6ccdad65da49bbf564793" \
      $IMAGE
    ;;

  3containers)
    curl https://raw.githubusercontent.com/jwilder/nginx-proxy/master/nginx.tmpl > ${TRAVIS_BUILD_DIR}/nginx.tmpl

    docker run -d -p 80:80 -p 443:443 \
      --name $NGINX_CONTAINER_NAME \
      -v /etc/nginx/conf.d \
      -v /etc/nginx/certs \
      -v /etc/nginx/vhost.d \
      -v /usr/share/nginx/html \
      nginx:alpine

    docker run -d \
      --name $DOCKER_GEN_CONTAINER_NAME \
      --volumes-from $NGINX_CONTAINER_NAME \
      -v ${TRAVIS_BUILD_DIR}/nginx.tmpl:/etc/docker-gen/templates/nginx.tmpl:ro \
      -v /var/run/docker.sock:/tmp/docker.sock:ro \
      --label com.github.jrcs.letsencrypt_nginx_proxy_companion.docker_gen \
      jwilder/docker-gen \
      -notify-sighup $NGINX_CONTAINER_NAME -watch -wait 5s:30s /etc/docker-gen/templates/nginx.tmpl /etc/nginx/conf.d/default.conf

    docker run -d \
      --name $LETSENCRYPT_CONTAINER_NAME \
      --volumes-from $NGINX_CONTAINER_NAME \
      -v /var/run/docker.sock:/var/run/docker.sock:ro \
      --add-host boulder:$boulder_ip \
      -e "DEBUG=true" \
      -e "ACME_CA_URI=http://${boulder_ip}:4000/directory" \
      -e "ACME_TOS_HASH=b16e15764b8bc06c5c3f9f19bc8b99fa48e7894aa5a6ccdad65da49bbf564793" \
      $IMAGE
    ;;

  *)
    echo "$0 $SETUP: invalid option."
    exit 1

esac

wait_for_dhparam $LETSENCRYPT_CONTAINER_NAME
