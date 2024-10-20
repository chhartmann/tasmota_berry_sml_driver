FROM mcr.microsoft.com/devcontainers/base:jammy
RUN apt-get update && apt-get install -y libreadline-dev
RUN git clone https://github.com/berry-lang/berry.git
WORKDIR berry
RUN make
