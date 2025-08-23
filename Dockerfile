FROM alpine:3.20
WORKDIR /app
COPY entry.sh /app/entry.sh
RUN chmod +x /app/entry.sh
ENTRYPOINT ["/app/entry.sh"]
