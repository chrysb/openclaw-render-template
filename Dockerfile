FROM node:22-slim

RUN apt-get update && apt-get install -y git curl procps python3 make g++ cron tini && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY package.json ./
RUN npm install --omit=dev --prefer-online && npm cache clean --force

# Belt-and-suspenders PATH fix: alphaclaw spawns `openclaw` by bare name and
# inherits its PATH. The ENV below is the primary fix; these shims keep the
# binaries resolvable even if a future change drops or reorders the ENV, and
# `openclaw --version` fails the build early if the install is broken.
RUN printf '#!/bin/sh\nexec /app/node_modules/.bin/openclaw "$@"\n' > /usr/bin/openclaw \
 && printf '#!/bin/sh\nexec /app/node_modules/.bin/alphaclaw "$@"\n' > /usr/bin/alphaclaw \
 && chmod +x /usr/bin/openclaw /usr/bin/alphaclaw \
 && ln -sf /app/node_modules/.bin/openclaw /usr/local/bin/openclaw \
 && ln -sf /app/node_modules/.bin/alphaclaw /usr/local/bin/alphaclaw \
 && /usr/bin/openclaw --version

COPY start.sh /start.sh
COPY failure-server.js /failure-server.js
RUN chmod +x /start.sh

ENV PATH="/app/node_modules/.bin:$PATH"
ENV ALPHACLAW_ROOT_DIR=/data

# Route temp onto the persistent disk instead of the container's ephemeral
# /tmp, so a 24/7 service doesn't churn/fill the ephemeral layer. Only the
# standard temp env vars are set — bare /tmp itself is deliberately left
# untouched (no symlink/bind-mount), so code that hardcodes /tmp keeps working.
# NOTE: /data is a runtime-mounted disk, so this build-time mkdir is shadowed
# at runtime — start.sh recreates /data/tmp on boot. Kept for image
# self-consistency.
ENV TMPDIR=/data/tmp
ENV TEMP=/data/tmp
ENV TMP=/data/tmp

RUN mkdir -p /data/tmp && chmod 1777 /data/tmp

EXPOSE 3000

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["/start.sh"]
