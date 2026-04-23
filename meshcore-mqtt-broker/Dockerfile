FROM node:22-alpine

WORKDIR /app

# Clone and build meshcore-mqtt-broker from upstream
RUN apk add --no-cache git && \
    git clone https://github.com/michaelhart/meshcore-mqtt-broker.git . && \
    npm ci && \
    npm run build && \
    apk del git

# Runtime env (override via --env-file or -e flags)
ENV NODE_ENV=production \
    MQTT_WS_PORT=8883 \
    MQTT_HOST=0.0.0.0

EXPOSE 8883

CMD ["npm", "start"]
