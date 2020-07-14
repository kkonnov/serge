FROM melopt/alpine-perl-devel AS build

RUN apk --no-cache add unzip libxslt-dev zlib-dev libgcrypt-dev
WORKDIR /app
COPY cpanfile* /app/
RUN build-perl-deps
COPY lib /app/lib
COPY bin /app/bin
COPY Build.PL /app/Build.PL
RUN build-perl-deps

FROM frolvlad/alpine-java:jre8-slim as java

FROM melopt/alpine-perl-runtime
COPY --from=java /usr/lib/jvm /usr/lib/jvm
COPY --from=java /usr/glibc-compat /usr/glibc-compat
COPY --from=java /etc/nsswitch.conf /etc/nsswitch.conf
ENV JAVA_HOME="/usr/lib/jvm/default-jvm" \
    CRWDIN_HOME="/usr/lib/jvm/ext/crowdin"
RUN mkdir "/lib64" && \
    ln -s "$JAVA_HOME/jre/bin/"* "/usr/bin/" && \
    ln -s "/usr/glibc-compat/lib/ld-linux-x86-64.so.2" "/lib/ld-linux-x86-64.so.2" && \
    ln -s "/usr/glibc-compat/lib/ld-linux-x86-64.so.2" "/lib64/ld-linux-x86-64.so.2" && \
    ln -s "/usr/glibc-compat/etc/ld.so.cache" "/etc/ld.so.cache"
RUN cd "/tmp" && \
    mkdir -p "${CRWDIN_HOME}" && \
    wget "https://downloads.crowdin.com/cli/v2/crowdin-cli.zip" && \
    unzip -jo "crowdin-cli.zip" && \
    mv "crowdin-cli.jar" "${CRWDIN_HOME}" && \
    rm -rf "/tmp/"* && \
    echo -e "#!/bin/sh\n\njava -jar ${CRWDIN_HOME}/crowdin-cli.jar \"\$@\"" > "/usr/bin/crowdin" && \
    chmod +x "/usr/bin/crowdin"
RUN apk --no-cache --repository http://dl-cdn.alpinelinux.org/alpine/edge/community add php7
RUN apk add nodejs npm
RUN npm install -g typescript@^3.8
COPY --from=build /app /app
ENTRYPOINT ["/app/bin/serge"]
