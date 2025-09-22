# version 0.0
FROM debian:trixie
WORKDIR /app
RUN apt update -y; apt -y install ruby ruby-dev build-essential libyaml-dev locales locales-all
ENV LC_ALL en_US.UTF-8
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US.UTF-8
COPY ../Gemfile ./
RUN gem install bundler && bundle install
COPY ../ ./
EXPOSE 4567
CMD ["ruby", "visualize.rb"]
