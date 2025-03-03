# Use the official Alpine image as the base
FROM alpine:latest

# Install necessary packages
RUN apk add --no-cache \
    curl \
    jq \
    bash \
    && rm -rf /var/cache/apk/*

# Download and install Aliyun CLI
RUN curl -L -o aliyun-cli.tgz https://github.com/aliyun/aliyun-cli/releases/download/v3.0.255/aliyun-cli-linux-3.0.255-amd64.tgz \
    && tar -zxvf aliyun-cli.tgz \
    && mv aliyun /usr/local/bin/ \
    && chmod +x /usr/local/bin/aliyun \
    && rm aliyun-cli.tgz

# Copy the token generator script into the image
COPY token_generator.sh /usr/local/bin/aliyun_token_generator.sh

# Ensure the script is executable
RUN chmod +x /usr/local/bin/aliyun_token_generator.sh

# Set the entrypoint (optional, can be overridden in the Job spec)
ENTRYPOINT ["/usr/local/bin/aliyun_token_generator.sh"]
