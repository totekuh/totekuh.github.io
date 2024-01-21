FROM ubuntu:latest

ENV PAGES_HOME="/pages"

RUN apt update && apt install -y \
    make \
    git \
    gcc \
    g++ \
    ruby \
    ruby-bundler \
    ruby-dev

WORKDIR $PAGES_HOME

COPY . .

RUN bundle install

ENTRYPOINT ["/bin/bash", "entrypoint.sh"]
