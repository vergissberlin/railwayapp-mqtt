FROM eclipse-mosquitto:latest

COPY config/mqtt/mosquitto.conf /mosquitto/config/mosquitto.conf
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# MQTT is a plain TCP service (no HTTP endpoint), so healthcheck via a
# local publish/subscribe round-trip against the broker itself.
HEALTHCHECK --interval=30s --timeout=10s --start-period=10s --retries=3 \
  CMD if [ -n "$MQTT_USER" ] && [ -n "$MQTT_PASS" ]; then \
        mosquitto_pub -h localhost -u "$MQTT_USER" -P "$MQTT_PASS" -t healthcheck -m ping -q 0; \
      else \
        mosquitto_pub -h localhost -t healthcheck -m ping -q 0; \
      fi

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["/usr/sbin/mosquitto", "-c", "/mosquitto/config/mosquitto.conf"]
