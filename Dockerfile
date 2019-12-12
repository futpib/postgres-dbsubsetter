FROM postgres:11.6-alpine

RUN apk add --update openjdk8-jre java-postgresql-jdbc socat

RUN wget https://github.com/bluerogue251/DBSubsetter/releases/download/v1.0.0-beta.3/DBSubsetter.jar

COPY docker-entrypoint-initdb.d/ /docker-entrypoint-initdb.d/
