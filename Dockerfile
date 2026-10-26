# Bump to a newer minor version with a supported Alpine base
FROM nginx:1.27-alpine

# Force a package upgrade to patch any latest CVEs before copying code
RUN apk update && apk upgrade --no-cache

# Copy local web assets into the container's Nginx html path
COPY html/ /usr/share/nginx/html/

# Expose HTTP port
EXPOSE 80

# Start Nginx in the foreground
CMD ["nginx", "-g", "daemon off;"]
