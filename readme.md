# postgres-dbsubsetter

> Postgres & [DBSubsetter](https://github.com/bluerogue251/DBSubsetter) in one docker image

[![Build Status](https://travis-ci.org/futpib/postgres-dbsubsetter.svg?branch=master)](https://travis-ci.org/futpib/postgres-dbsubsetter) [![Docker Cloud Build Status](https://img.shields.io/docker/cloud/build/futpib/postgres-dbsubsetter)](https://hub.docker.com/r/futpib/postgres-dbsubsetter/tags)

## Example

```bash
docker run \
    -p 5432:5432 \
    -e ORIGIN_HOST=example.com \
    -e ORIGIN_DB=postgres \
    -e ORIGIN_USER=postgres \
    -e ORIGIN_PASSWORD=postgres \
    -e DB_SUBSETTER_ARGS="--schemas public --baseQuery 'your_schema.users ::: id % 100 = 0 ::: includeChildren'" \
    futpib/postgres-dbsubsetter:master
```
